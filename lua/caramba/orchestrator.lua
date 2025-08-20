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
local logger = require('caramba.logger')
local memory_vector = require('caramba.memory_vector')
local memory_vector_bin = require('caramba.memory_vector_bin')
local utils = require('caramba.utils')

-- Forward declarations
local request_plan_delta
local merge_plan_delta

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
  -- Ensure we load plan file if empty
  if (not plan_state or ((plan_state.goals == nil or #plan_state.goals == 0) and (plan_state.current_tasks == nil or #plan_state.current_tasks == 0))) then
    pcall(function() require('caramba.planner').load_project_plan() end)
    plan_state = state.get().planner or {}
  end
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

local function pick_code_bufnr()
  local function is_file_buf(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return false end
    if not vim.api.nvim_buf_is_loaded(buf) then return false end
    if vim.api.nvim_buf_get_option(buf, 'buftype') ~= '' then return false end
    local name = vim.api.nvim_buf_get_name(buf)
    if name == '' then return false end
    local stat = vim.loop.fs_stat(name)
    return stat and stat.type == 'file'
  end
  local alt = vim.fn.bufnr('#')
  if alt > 0 and is_file_buf(alt) then return alt end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if is_file_buf(b) then return b end
  end
  return vim.api.nvim_get_current_buf()
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
	local cfg = config.get() or {}
	logger.debug('Enrichment start')

    -- Prompt Engineering is surfaced in chat for visibility; avoid blocking here.

	-- Primary Tree-sitter context with siblings/imports
	local target_buf = pick_code_bufnr()
	local ctx = context.collect({ include_siblings = true, bufnr = target_buf })
	if ctx then
		local ctx_md = context.build_context_string(ctx)
		logger.debug('Enrichment ctx', { file = ctx.file_path, lang = ctx.language, len = ctx_md and #ctx_md or 0 })
		if ctx_md and ctx_md ~= '' then
			table.insert(parts, "## Primary Context (Tree-sitter)")
			table.insert(parts, "")
			table.insert(parts, ctx_md)
		end
		-- Related files (based on imports)
		local related = related_files_section(ctx)
		if related then
			logger.debug('Enrichment related files included')
			table.insert(parts, "")
			table.insert(parts, related)
		end
	end

	-- Plan summary (short, if present) and always include even if empty placeholder
	local plan_summary = summarize_plan() or '(No plan yet)'
	table.insert(parts, "\n## Plan Summary")
	table.insert(parts, plan_summary)

	-- Relevant memory using multiple angles
	local mem_results = memory.search_multi_angle(user_message, ctx, "coding assistant") or {}
	logger.debug('Enrichment memory results', { count = #mem_results })
	if #mem_results > 0 then
		table.insert(parts, "\n## Relevant Memory (Top)")
		for _, r in ipairs(mem_results) do
			table.insert(parts, string.format("- %s (src: %s, relevance: %.2f)", r.entry.content, r.source or "", r.relevance or 0))
		end
	end

	-- Compact recall pack from memory module
	local recall = memory.build_recall_pack(user_message, ctx)
	if recall and recall ~= '' then
		logger.debug('Enrichment recall pack added', { len = #recall })
		table.insert(parts, '')
		table.insert(parts, recall)
	end

	-- Optional: lightweight self-reflection scaffolding prompt to guide the model
	if (cfg.pipeline and cfg.pipeline.enable_self_reflection) ~= false then
		parts[#parts+1] = '\n## Self-Check Checklist'
		parts[#parts+1] = '- Verify correctness and edge cases\n- Follow file conventions and style\n- Prefer minimal edits with tests in mind\n- If unsure, propose a plan and ask clarifying questions'
	end

	-- Recent git changes to provide temporal context (best-effort)
	local ok_git, recent = pcall(function()
		local lines = vim.fn.systemlist("git --no-pager log -n 3 --pretty=format:%h %s --name-only")
		return lines
	end)
	if ok_git and recent and #recent > 0 then
		parts[#parts+1] = '\n## Recent Changes (git)'
		local count = 0
		for _, l in ipairs(recent) do
			if l ~= '' then
				parts[#parts+1] = ('- ' .. l)
				count = count + 1
				if count >= 12 then break end
			end
		end
	end

	-- Reviewer recommendations file (if present)
	local rec_path = vim.fn.stdpath('data') .. '/caramba/recommendations.md'
	if utils.file_exists(rec_path) then
		local rec = utils.read_file(rec_path)
		if rec and rec ~= '' then
			local max = 3000
			if #rec > max then rec = rec:sub(#rec - max + 1) end -- keep most recent part
			table.insert(parts, '\n## Reviewer Recommendations (recent)')
			table.insert(parts, rec)
		end
	end

	return table.concat(parts, "\n")
end

-- Convert a PM markdown summary into plan delta and merge it
function M.update_plan_from_markdown(markdown_text, context_text)
  if not markdown_text or markdown_text == '' then return end
  local prompt = string.format([[You are a planning assistant. Convert the following markdown plan into JSON with keys: goals[], current_tasks[], known_issues[]. No prose.

Context:
%s

Plan markdown:
%s
]], context_text or '', markdown_text)
  request_plan_delta(prompt, function(delta)
    if delta then
      merge_plan_delta(delta)
      vim.schedule(function() vim.notify('Planner: plan updated from markdown', vim.log.levels.INFO) end)
    end
  end)
end

-- Warm vector store from memory and a small sample of project files
function M.warm_vector_store()
  local ok = pcall(function()
    local entries = (memory._memory_cache or {}).entries or {}
    local added = 0
    for i = math.max(1, #entries - 100), #entries do
      local e = entries[i]
      if e and e.content then
        memory_vector_bin.add_from_text(e.content:sub(1, 1000), { snippet = e.content:sub(1, 160), source = 'memory_entry' })
        added = added + 1
        if added >= 50 then break end
      end
    end
    local root = utils.get_project_root()
    local samples = vim.fn.glob(root .. '/lua/**/*.lua', true, true)
    local count = 0
    for _, path in ipairs(samples) do
      local stat = vim.loop.fs_stat(path)
      if stat and stat.size and stat.size < 20000 then
        local okr, text = pcall(function() return table.concat(vim.fn.readfile(path), '\n') end)
        if okr and text and text ~= '' then
          memory_vector_bin.add_from_text(text:sub(1, 3000), { file = path, source = 'code_sample' })
          count = count + 1
          if count >= 25 then break end
        end
      end
    end
    logger.info('Vector warmup complete', { memory = added, files = count })
  end)
  if not ok then
    logger.warn('Vector warmup failed')
  end
end

-- Produce a short self-reflection critique of the assistant reply
function M.self_reflect(user_message, assistant_text, callback)
  local cfg = config.get() or {}
  if (cfg.pipeline and cfg.pipeline.enable_self_reflection) == false then
    if callback then callback(nil) end
    return
  end
  local prompt = {
    { role = 'system', content = 'You are a strict code reviewer. In 5-8 bullet points, critique the assistant answer for correctness, safety, missing context, and propose 1-2 concrete improvements. Keep it concise.' },
    { role = 'user', content = string.format('User request:\n%s\n\nAssistant answer:\n%s', user_message or '', assistant_text or '') }
  }
  llm.request(prompt, { task = 'chat' }, function(result, err)
    if err then logger.warn('self_reflect error', err) end
    if callback then callback(type(result) == 'string' and result or nil) end
  end)
end

-- Merge simple deltas into planner state (set-based uniqueness)
merge_plan_delta = function(delta)
	if type(delta) ~= 'table' then return end
	logger.debug('Merging plan delta', delta)
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
request_plan_delta = function(prompt_text, callback)
	local messages = {
		{ role = 'system', content = [[You maintain a concise implementation plan. Given input, output ONLY JSON with keys: goals[], current_tasks[], known_issues[]. No prose.]] },
		{ role = 'user', content = prompt_text },
	}
	local opts = {}
	local provider = (config.get() or {}).provider
	if provider == 'openai' then
		opts.response_format = { type = 'json_object' }
	end
	llm.request(messages, opts, function(result, err)
		if err then
			-- Reduce noise: log as warn but don't spam user
			vim.schedule(function()
				if (config.get() or {}).debug then
					vim.notify('Planner delta request failed: ' .. tostring(err), vim.log.levels.WARN)
				end
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
	local ctx = context.collect({ include_siblings = true, bufnr = pick_code_bufnr() })
	local summary = summarize_plan() or ''
	local cfg = config.get() or {}
	if (cfg.pipeline and cfg.pipeline.enable_auto_planning) == false then return end
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
			logger.info('Planner pre-send updated')
		end
	end)
end

--- Post-process an assistant response: store memory and update plan
--- @param user_message string
--- @param assistant_text string
function M.postprocess_response(user_message, assistant_text)
	if assistant_text and assistant_text ~= '' then
		local ctx = context.collect({ bufnr = pick_code_bufnr() }) or {}
		local ok_ft, ft = pcall(function() return vim.bo.filetype end)
		local ok_fp, fp = pcall(function() return vim.fn.expand('%:p') end)
		local tags = { "caramba", "assistant_response" }
		if ctx and ctx.language then table.insert(tags, ctx.language) end
		local snippet = assistant_text:sub(1, RESPONSE_STORE_CHAR_LIMIT)
		memory.store(snippet, {
			context = "assistant_response",
			file_path = ctx.file_path or (ok_fp and fp or ''),
			language = ctx.language or (ok_ft and ft or ''),
			prompt = user_message,
			timestamp = vim.fn.localtime(),
		}, tags)
		logger.debug('Stored assistant response to memory')
		-- Also vectorize a short snippet for future recall
		pcall(function()
			memory_vector_bin.add_from_text(snippet, { snippet = snippet, source = 'assistant_response', file = ctx.file_path or '' })
		end)
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
			logger.info('Planner post-response updated')
		end
	end)

	-- Memory extraction from response (entities/decisions/commands)
	local cfg = config.get() or {}
	if (cfg.pipeline and cfg.pipeline.enable_memory_extraction) ~= false then
		local mem_prompt = {
			{ role = 'system', content = 'Extract up to 5 short memory items from the assistant response (facts, decisions, learned patterns, commands). Return as JSON array of strings.' },
			{ role = 'user', content = assistant_text or '' },
		}
		llm.request(mem_prompt, { response_format = { type = 'json_object' }, task = 'chat' }, function(result)
			local arr = nil
			if type(result) == 'table' then arr = result
			elseif type(result) == 'string' then local ok, obj = pcall(vim.json.decode, result); if ok then arr = obj end end
			if type(arr) == 'table' then
				for _, item in ipairs(arr) do
					if type(item) == 'string' and item ~= '' then
						memory.store(item, { context = 'extracted_memory', source = 'assistant_response' }, { 'caramba', 'memory', 'extracted' })
					end
				end
			end
		end)
	end
end

return M
