-- Chat Orchestrator: builds enriched prompts and handles post-processing
-- Focus: simple, automatic context enrichment for high-quality responses

local M = {}

local context = require('caramba.context')
local memory = require('caramba.memory')
local state = require('caramba.state')
local utils = require('caramba.utils')
local config = require('caramba.config')
local planner = require('caramba.planner')
local llm = require('caramba.llm')

-- Short-lived cache of recently included related files to avoid repetition
M._recent_related_files = {}
local RELATED_TTL_SEC = 300

local function now_sec()
	return math.floor(vim.loop.now() / 1000)
end

local function mark_included(path)
	M._recent_related_files[path] = now_sec()
	-- prune entries older than TTL or when table grows too large
	local count = 0
	for _ in pairs(M._recent_related_files) do count = count + 1 end
	if count > 200 then
		local cutoff = now_sec() - RELATED_TTL_SEC
		for p, ts in pairs(M._recent_related_files) do
			if ts < cutoff then M._recent_related_files[p] = nil end
		end
	end
end

local function was_recently_included(path)
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
		-- look for import x from 'mod'; require('mod'); from "mod"; @module or plain quotes
		local m = line:match("from%s+['\"]([^'\"]+)['\"]")
		m = m or line:match("require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")
		m = m or line:match("['\"]([^'\"]+)['\"]")
		if m and not m:match('^%a+://') and not m:match('^%s*$') then
			-- trim loaders like .js, .ts from the module name end
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
		local pattern = string.format("%s/**/*%s%s.%s", root, module_name:sub(1,1) == '/' and '' or '', module_name:gsub('[/\\]', '*'), ext)
		local matches = vim.fn.glob(pattern, true, true)
		for _, p in ipairs(matches) do
			results[#results+1] = p
			if #results >= 5 then return results end
		end
		if #results >= 5 then break end
	end
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

-- Merge simple deltas into planner state
local function merge_plan_delta(delta)
	if type(delta) ~= 'table' then return end
	local plan = state.get().planner or {}
	plan.goals = plan.goals or {}
	plan.current_tasks = plan.current_tasks or {}
	plan.known_issues = plan.known_issues or {}
	local function add_unique(list, item)
		for _, v in ipairs(list) do if v == item or (type(v)=='table' and v.description==item) then return end end
		list[#list+1] = item
	end
	for _, g in ipairs(delta.goals or {}) do add_unique(plan.goals, g) end
	for _, t in ipairs(delta.current_tasks or {}) do
		if type(t) == 'string' then add_unique(plan.current_tasks, { description = t }) else add_unique(plan.current_tasks, t) end
	end
	for _, k in ipairs(delta.known_issues or {}) do add_unique(plan.known_issues, k) end
	-- persist
	planner.save_project_plan()
end

-- Ask LLM for plan deltas
local function request_plan_delta(prompt_text, callback)
	local messages = {
		{ role = 'system', content = [[You maintain a concise implementation plan. Given input, output ONLY JSON with keys: goals[], current_tasks[], known_issues[]. No prose.]] },
		{ role = 'user', content = prompt_text },
	}
	llm.request(messages, {}, function(result)
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
		local ctx = context.collect({})
		local tags = { "caramba", "assistant_response" }
		if ctx and ctx.language then table.insert(tags, ctx.language) end
		memory.store(assistant_text:sub(1, 2000), { 
			context = "assistant_response",
			file_path = ctx and ctx.file_path or vim.fn.expand('%:p'),
			language = ctx and ctx.language or vim.bo.filetype,
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
