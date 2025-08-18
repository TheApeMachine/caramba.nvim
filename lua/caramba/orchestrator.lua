-- Chat Orchestrator: builds enriched prompts and handles post-processing
-- Focus: simple, automatic context enrichment for high-quality responses

local M = {}

-- luacheck: globals vim
local vim = vim

local context = require('caramba.context')
local memory = require('caramba.memory')
local state = require('caramba.state')
local utils = require('caramba.utils')
local config = require('caramba.config')
local planner = require('caramba.planner')
local llm = require('caramba.llm')

-- Configurable limits
local RESPONSE_STORE_CHAR_LIMIT = ((config.get().performance or {}).response_store_char_limit) or 2000

-- Short-lived cache of recently included related files to avoid repetition
M._recent_related_files = {}
M._recent_related_files_count = 0
local RELATED_TTL_SEC = 300

-- Glob cache to reduce expensive file lookups
M._glob_cache = {}
local GLOB_CACHE_TTL_SEC = 90
local GLOB_CACHE_MAX = 300

local function now_sec()
	return math.floor(vim.loop.now() / 1000)
end

local function prune_glob_cache()
	local count = 0
	for _ in pairs(M._glob_cache) do count = count + 1 end
	if count <= GLOB_CACHE_MAX then return end
	local cutoff = now_sec() - GLOB_CACHE_TTL_SEC
	for k, entry in pairs(M._glob_cache) do
		if (entry.ts or 0) < cutoff then
			M._glob_cache[k] = nil
			count = count - 1
			if count <= GLOB_CACHE_MAX then break end
		end
	end
	-- If still too large, evict arbitrary keys
	if count > GLOB_CACHE_MAX then
		for k, _ in pairs(M._glob_cache) do
			M._glob_cache[k] = nil
			count = count - 1
			if count <= GLOB_CACHE_MAX then break end
		end
	end
end

local function mark_included(path)
	local is_new = (M._recent_related_files[path] == nil)
	M._recent_related_files[path] = now_sec()
	if is_new then
		M._recent_related_files_count = (M._recent_related_files_count or 0) + 1
	end
	-- prune entries older than TTL or when table grows too large
	if (M._recent_related_files_count or 0) > 200 then
		local cutoff = now_sec() - RELATED_TTL_SEC
		for p, ts in pairs(M._recent_related_files) do
			if ts < cutoff then
				M._recent_related_files[p] = nil
				M._recent_related_files_count = M._recent_related_files_count - 1
				if M._recent_related_files_count <= 200 then break end
			end
		end
		-- If still above threshold (no expired entries), evict arbitrary extras
		if M._recent_related_files_count > 200 then
			for p, _ in pairs(M._recent_related_files) do
				M._recent_related_files[p] = nil
				M._recent_related_files_count = M._recent_related_files_count - 1
				if M._recent_related_files_count <= 200 then break end
			end
		end
	end
end

local function was_recently_included(path)
	-- Opportunistic prune on read for stale entries
	local cutoff = now_sec() - RELATED_TTL_SEC
	for p, ts0 in pairs(M._recent_related_files) do
		if ts0 < cutoff then
			M._recent_related_files[p] = nil
			M._recent_related_files_count = math.max(0, (M._recent_related_files_count or 0) - 1)
		end
	end
	local ts = M._recent_related_files[path]
	if not ts then return false end
	return (now_sec() - ts) < RELATED_TTL_SEC
end

local function summarize_plan()
	local plan_state = state.get().planner or {}
	local lines = {}
	if plan_state.goals and #plan_state.goals > 0 then
		table.insert(lines, "Goals:")
		for i = 1, math.min(5, #plan_state.goals) do
			table.insert(lines, string.format("- %s", tostring(plan_state.goals[i])))
		end
	end
	if plan_state.current_tasks and #plan_state.current_tasks > 0 then
		table.insert(lines, "\nActive Tasks:")
		for i = 1, math.min(5, #plan_state.current_tasks) do
			table.insert(lines, string.format("- %s", tostring(plan_state.current_tasks[i].description or plan_state.current_tasks[i])))
		end
	end
	if plan_state.known_issues and #plan_state.known_issues > 0 then
		table.insert(lines, "\nKnown Issues:")
		for i = 1, math.min(5, #plan_state.known_issues) do
			table.insert(lines, string.format("- %s", tostring(plan_state.known_issues[i])))
		end
	end
	return #lines > 0 and table.concat(lines, "\n") or nil
end

local function extract_module_candidates(imports)
	local modules = {}
	for _, line in ipairs(imports or {}) do
		-- Restrictive matches to avoid false positives
		local m = line:match("%f[%a]from%s+['\"]([^'\"]+)['\"]")
		m = m or line:match("%f[%a]require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")
		m = m or line:match("^%s*import%s+[%w_%s{},*]+%s+from%s+['\"]([^'\"]+)['\"]")
		m = m or line:match("^%s*import%s*['\"]([^'\"]+)['\"]") -- bare import
		if m and not m:match('^%a+://') and not m:match('^%s*$') then
			m = m:gsub("%.[%w]+$", "")
			modules[#modules+1] = m
		end
	end
	return modules
end

local function find_files_for_module(module_name)
	local root = utils.get_project_root()
	local results = {}
	-- Try several patterns: exact basename match across common code extensions
	local exts = { 'lua','py','js','ts','tsx','jsx','go','rs','java','c','cpp','h','hpp' }
	for _, ext in ipairs(exts) do
		local pattern = string.format("%s/**/*%s%s.%s", root, (module_name:sub(1,1) == '/' and '' or '/'), module_name:gsub('[/\\]', '*'), ext)
		local cache_entry = M._glob_cache[pattern]
		local matches
		local now = now_sec()
		if cache_entry and (now - (cache_entry.ts or 0)) < GLOB_CACHE_TTL_SEC then
			matches = cache_entry.results
		else
			matches = vim.fn.glob(pattern, true, true)
			M._glob_cache[pattern] = { results = matches, ts = now }
		end
		for _, p in ipairs(matches) do
			results[#results+1] = p
			if #results >= 5 then return results end
		end
		if #results >= 5 then break end
	end
	prune_glob_cache()
	return results
end

local function read_file_limited(path)
	local max_lines = (config.get().context and config.get().context.max_lines) or 200
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok or not lines then return nil end
	if #lines > max_lines then
		local sliced = {}
		for i=1,max_lines do sliced[i] = lines[i] end
		lines = sliced
	end
	return table.concat(lines, "\n")
end

local function related_files_section(ctx)
	if not ctx then return nil end
	local imports = ctx.imports or {}
	if #imports == 0 then return nil end
	local modules = extract_module_candidates(imports)
	if #modules == 0 then return nil end
	local seen = {}
	local collected = {}
	for _, mod in ipairs(modules) do
		if not seen[mod] then
			seen[mod] = true
			for _, path in ipairs(find_files_for_module(mod)) do
				if not was_recently_included(path) and vim.loop.fs_stat(path) and #collected < 3 then
					local content = read_file_limited(path)
					if content and content ~= '' then
						collected[#collected+1] = { path = path, content = content }
						mark_included(path)
					end
				end
				if #collected >= 3 then break end
			end
		end
		if #collected >= 3 then break end
	end
	if #collected == 0 then return nil end
	local parts = { "## Related Files (heuristic)", "" }
	for _, f in ipairs(collected) do
		local ft = f.path:match("%.([%w]+)$") or ''
		table.insert(parts, string.format("[File: %s]", f.path))
		table.insert(parts, string.format("```%s\n%s\n```", ft, f.content))
	end
	return table.concat(parts, "\n")
end

--- Build an enriched prompt section (markdown) for chat
--- @param user_message string
--- @return string extra_markdown
function M.build_enriched_prompt(user_message)
	local parts = {}

	-- Primary Tree-sitter context with siblings/imports
	local ctx = context.collect({ include_siblings = true })
	if ctx then
		local ctx_md = context.build_context_string(ctx)
		if ctx_md and ctx_md ~= '' then
			table.insert(parts, "## Primary Context (Tree-sitter)")
			table.insert(parts, "")
			table.insert(parts, ctx_md)
		end
		-- Related files (based on imports)
		local related = related_files_section(ctx)
		if related then
			table.insert(parts, "")
			table.insert(parts, related)
		end
	end

	-- Plan summary (short, if present)
	local plan_summary = summarize_plan()
	if plan_summary then
		table.insert(parts, "\n## Plan Summary")
		table.insert(parts, plan_summary)
	end

	-- Relevant memory using multiple angles
	local mem_results = memory.search_multi_angle(user_message, ctx, "coding assistant") or {}
	if #mem_results > 0 then
		table.insert(parts, "\n## Relevant Memory (Top)")
		for _, r in ipairs(mem_results) do
			table.insert(parts, string.format("- %s (src: %s, relevance: %.2f)", r.entry.content, r.source or "", r.relevance or 0))
		end
	end

	return table.concat(parts, "\n")
end

-- Merge simple deltas into planner state (set-based uniqueness)
local function merge_plan_delta(delta)
	if type(delta) ~= 'table' then return end
	local plan = state.get().planner or {}
	plan.goals = plan.goals or {}
	plan.current_tasks = plan.current_tasks or {}
	plan.known_issues = plan.known_issues or {}
	-- Sets for uniqueness
	local goals_set = {}
	for _, v in ipairs(plan.goals) do goals_set[v] = true end
	local tasks_set = {}
	for _, v in ipairs(plan.current_tasks) do
		if type(v) == 'table' and v.description then tasks_set[v.description] = true end
	end
	local issues_set = {}
	for _, v in ipairs(plan.known_issues) do issues_set[v] = true end
	-- Merge goals
	for _, g in ipairs(delta.goals or {}) do
		if g and not goals_set[g] then
			table.insert(plan.goals, g)
			goals_set[g] = true
		end
	end
	-- Merge current tasks by description
	for _, t in ipairs(delta.current_tasks or {}) do
		local desc
		if type(t) == 'string' then
			desc = t
			t = { description = t }
		elseif type(t) == 'table' then
			desc = t.description
		end
		if desc and not tasks_set[desc] then
			table.insert(plan.current_tasks, t)
			tasks_set[desc] = true
		end
	end
	-- Merge known issues
	for _, k in ipairs(delta.known_issues or {}) do
		if k and not issues_set[k] then
			table.insert(plan.known_issues, k)
			issues_set[k] = true
		end
	end
	-- persist
	planner.save_project_plan()
end

-- Ask LLM for plan deltas
local function request_plan_delta(prompt_text, callback)
	local messages = {
		{ role = 'system', content = [[You maintain a concise implementation plan. Given input, output ONLY JSON with keys: goals[], current_tasks[], known_issues[]. No prose.]] },
		{ role = 'user', content = prompt_text },
	}
	llm.request(messages, {}, function(result, err)
		if err then
			vim.schedule(function()
				vim.notify('Planner delta request failed: ' .. tostring(err), vim.log.levels.WARN)
			end)
			callback(nil)
			return
		end
		local decoded = nil
		if type(result) == 'table' then decoded = result
		elseif type(result) == 'string' then local ok, obj = pcall(vim.json.decode, result); if ok then decoded = obj end end
		callback(decoded)
	end)
end

--- Update plan before sending a message (asynchronous)
function M.update_plan_from_prompt(user_message)
	local ctx = context.collect({ include_siblings = true })
	local summary = summarize_plan() or ''
	local prompt = string.format([[User message:
%s

Context summary:
%s

Current plan (summary):
%s

Return JSON with updated goals, current_tasks, known_issues.]], user_message, context.build_context_string(ctx or {}), summary)
	request_plan_delta(prompt, function(delta)
		if delta then
			merge_plan_delta(delta)
			vim.schedule(function() vim.notify('Planner: pre-send plan updated', vim.log.levels.INFO) end)
		end
	end)
end

--- Post-process an assistant response: store memory and update plan
--- @param user_message string
--- @param assistant_text string
function M.postprocess_response(user_message, assistant_text)
	if assistant_text and assistant_text ~= '' then
		local ctx = context.collect({}) or {}
		local ok_ft, ft = pcall(function() return vim.bo.filetype end)
		local ok_fp, fp = pcall(function() return vim.fn.expand('%:p') end)
		local tags = { "caramba", "assistant_response" }
		if ctx and ctx.language then table.insert(tags, ctx.language) end
		memory.store(assistant_text:sub(1, RESPONSE_STORE_CHAR_LIMIT), {
			context = "assistant_response",
			file_path = ctx.file_path or (ok_fp and fp or ''),
			language = ctx.language or (ok_ft and ft or ''),
			prompt = user_message,
			timestamp = vim.fn.localtime(),
		}, tags)
	end
	-- Plan delta from response
	local plan_summary = summarize_plan() or ''
	local prompt = string.format([[User message:
%s

Assistant response:
%s

Current plan (summary):
%s

Return JSON with updated goals, current_tasks, known_issues.]], user_message or '', assistant_text or '', plan_summary)
	request_plan_delta(prompt, function(delta)
		if delta then
			merge_plan_delta(delta)
			vim.schedule(function() vim.notify('Planner: post-response plan updated', vim.log.levels.INFO) end)
		end
	end)
end

return M
