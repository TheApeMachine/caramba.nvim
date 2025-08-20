-- Caramba Chat Panel Module
-- Provides an interactive chat interface with context awareness

local M = {}

-- Dependencies
local llm = require('caramba.llm')
local edit = require('caramba.edit')
local config = require('caramba.config')
local context = require('caramba.context')
-- local planner = require('caramba.planner') -- not used here
-- local utils = require('caramba.utils') -- not used here
local memory = require('caramba.memory')
local state = require('caramba.state')

local openai_tools = require('caramba.openai_tools')
local orchestrator = require('caramba.orchestrator')
local logger = require('caramba.logger')
-- Add highlight namespace and activity helper
local chat_hl_ns = vim.api.nvim_create_namespace('CarambaChatHL')
local function push_activity(text)
  if not text or text == '' then return end
  M._chat_state = M._chat_state or {}
  M._chat_state.activity = M._chat_state.activity or {}
  table.insert(M._chat_state.activity, text)
  if #M._chat_state.activity > 100 then
    table.remove(M._chat_state.activity, 1)
  end
end
M.push_activity = push_activity

-- Animation helpers
local function get_frames_for_mode(mode)
  if mode == 'tool' then
    return { '🔧', '🔧.', '🔧..', '🔧...' }
  elseif mode == 'writing' then
    return { '✍️', '✍️.', '✍️..', '✍️...' }
  else
    return { '🤔', '🤔.', '🤔..', '🤔...' }
  end
end

local function get_mode_label(mode)
  if mode == 'tool' then return 'Using tools' end
  if mode == 'writing' then return 'Writing' end
  return 'Thinking'
end

local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

local function current_mode_emoji(mode)
  if mode == 'tool' then return '🔧' end
  if mode == 'writing' then return '✍️' end
  return '🤔'
end

local function update_window_title()
  if not (M._chat_state and M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid)) then
    return
  end
  local anim = M._chat_state.animation or {}
  local emoji = current_mode_emoji(anim.mode or 'thinking')
  local spinner = spinner_frames[(anim.spinner_idx or 1)]
  local title = string.format(' Caramba Chat  %s %s ', emoji, spinner)
  local cfg = vim.api.nvim_win_get_config(M._chat_state.winid)
  cfg.title = title
  cfg.title_pos = cfg.title_pos or 'center'
  vim.api.nvim_win_set_config(M._chat_state.winid, cfg)
end

local function start_animation(mode)
  M._chat_state.animation = M._chat_state.animation or {}
  local anim = M._chat_state.animation
  if anim.timer then
    vim.fn.timer_stop(anim.timer)
    anim.timer = nil
  end
  anim.mode = mode or 'thinking'
  anim.frame_idx = 1
  anim.spinner_idx = 1
  local frames = get_frames_for_mode(anim.mode)
  anim.status_text = frames[anim.frame_idx] .. ' ' .. get_mode_label(anim.mode)
  update_window_title()
  anim.timer = vim.fn.timer_start(120, function()
    local s = M._chat_state.animation
    if not s then return end
    s.frame_idx = (s.frame_idx % #get_frames_for_mode(s.mode)) + 1
    s.spinner_idx = ((s.spinner_idx or 1) % #spinner_frames) + 1
    local f = get_frames_for_mode(s.mode)[s.frame_idx]
    s.status_text = f .. ' ' .. get_mode_label(s.mode)
    vim.schedule(function()
      update_window_title()
      if M._chat_state and M._chat_state.bufnr and vim.api.nvim_buf_is_valid(M._chat_state.bufnr) then
        M._render_chat()
      end
    end)
  end, { ['repeat'] = -1 })
end

local function set_animation_mode(mode)
  local anim = M._chat_state.animation
  if not anim then return end
  if anim.mode == mode then return end
  anim.mode = mode
  anim.frame_idx = 1
  update_window_title()
end

local function stop_animation()
  local anim = M._chat_state.animation
  if anim and anim.timer then
    vim.fn.timer_stop(anim.timer)
    anim.timer = nil
  end
  if anim then
    anim.status_text = nil
  end
  if M._chat_state and M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    local cfg = vim.api.nvim_win_get_config(M._chat_state.winid)
    cfg.title = ' Caramba Chat '
    cfg.title_pos = cfg.title_pos or 'center'
    vim.api.nvim_win_set_config(M._chat_state.winid, cfg)
  end
end

-- Helper: stream an LLM section into a titled, foldable assistant message
local function stream_section(title, system_prompt, user_text, task, on_done)
  local idx = #M._chat_state.history + 1
  M._chat_state.history[idx] = { role = 'assistant', title = title, content = '', streaming = true, folded = false }
  M._render_chat()
  local messages = {
    { role = 'system', content = system_prompt },
    { role = 'user', content = user_text },
  }
  logger.info(title .. ' stream start')
  llm.request_stream(messages, { task = task or 'chat' }, function(delta)
    if type(delta) == 'string' and delta ~= '' then
      logger.debug(title .. ' chunk', delta:sub(1, 160))
      M._chat_state.history[idx].content = (M._chat_state.history[idx].content or '') .. delta
      M._render_chat()
    end
  end, function(_, err)
    logger.info(title .. ' stream complete', err or '')
    M._chat_state.history[idx].streaming = false
    M._chat_state.history[idx].folded = true
    M._render_chat()
    if on_done then on_done(M._chat_state.history[idx].content or '') end
  end)
end

-- Chat state (centralized via state.lua)
do
  local defaults = {
    history = {},
    bufnr = nil,
    winid = nil,
    input_bufnr = nil,
    input_winid = nil,
    code_blocks = {},
    streaming = false,
    current_response = "",
    tool_iterations = 0,
    max_tool_iterations = config.get().chat.max_tool_iterations,
    activity = {},
    animation = {},
  }
  local s = state.get().chat or {}
  for k, v in pairs(defaults) do
    if s[k] == nil then s[k] = v end
  end
  state.set_namespace('chat', s)
  M._chat_state = s
end



-- Parse special context commands from message
local function parse_context_commands(message)
  local contexts = {}
  local cleaned_message = message

  -- @buffer - include current buffer
  if message:match("@buffer") then
    local bufnr = vim.fn.bufnr("#") -- Last active buffer before chat
    if bufnr > 0 then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local filename = vim.api.nvim_buf_get_name(bufnr)
      table.insert(contexts, {
        type = "buffer",
        name = filename,
        content = table.concat(lines, "\n")
      })
    end
    cleaned_message = cleaned_message:gsub("@buffer", "")
  end

  -- @selection - include visual selection
  if message:match("@selection") then
    -- Get the last visual selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    if start_pos[2] > 0 then
      local bufnr = start_pos[1] == 0 and vim.fn.bufnr("#") or start_pos[1]
      local lines = vim.api.nvim_buf_get_lines(
        bufnr,
        start_pos[2] - 1,
        end_pos[2],
        false
      )
      table.insert(contexts, {
        type = "selection",
        content = table.concat(lines, "\n")
      })
    end
    cleaned_message = cleaned_message:gsub("@selection", "")
  end

  -- @file:path - include specific file
  for filepath in message:gmatch("@file:([^%s]+)") do
    local ok, content = pcall(vim.fn.readfile, vim.fn.expand(filepath))
    if ok then
      table.insert(contexts, {
        type = "file",
        name = filepath,
        content = table.concat(content, "\n")
      })
    end
    cleaned_message = cleaned_message:gsub("@file:" .. filepath, "")
  end

  -- @web:query - search the web
  for query in message:gmatch("@web:([^%s]+)") do
    -- This will be handled separately as it's async
    table.insert(contexts, {
      type = "web_search",
      query = query,
      pending = true,
    })
    cleaned_message = cleaned_message:gsub("@web:" .. query, "")
  end

  return cleaned_message:match("^%s*(.-)%s*$"), contexts
end

-- Format message for display
local function format_message(msg)
  local lines = {}

  -- Add role header
  if msg.title then
    local hdr = "## " .. msg.title
    if msg.folded then hdr = hdr .. " (folded)" end
    table.insert(lines, hdr)
  else
    if msg.role == "user" then
      table.insert(lines, "## You:")
    else
      table.insert(lines, "## Assistant:")
    end
  end

  table.insert(lines, "")

  -- Add content unless folded; ensure not nil
  if not msg.folded then
    local content = msg.content or ""
    for line in content:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
  end

  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")

  return lines
end

-- Extract code blocks from message using Tree-sitter
local function extract_code_blocks(content)
  local blocks = {}
  if not content then return blocks end

  local parser = vim.treesitter.get_string_parser(content, "markdown")
  if not parser then
    return blocks
  end

  local tree = parser:parse()[1]
  if not tree then
    return blocks
  end

  local root = tree:root()
  local query_string = [[
    (fenced_code_block
      (info_string (language) @language)?
      (code_fence_content) @code) @fenced_code
  ]]
  local query = vim.treesitter.query.parse("markdown", query_string)

  if not query then
    return blocks
  end

  for _, match, _ in query:iter_matches(root, content) do
    local captures = {}
    for cap_id, cap_node in pairs(match) do
      captures[query.captures[cap_id]] = cap_node
    end

    local fenced_node = captures.fenced_code
    local code_node = captures.code

    if code_node and fenced_node and fenced_node.range then
      local lang = "text"
      if captures.language then
        -- For string parsers, use Treesitter's get_node_text with source string
        lang = vim.treesitter.get_node_text(captures.language, content)
      end

      local start_line, _, _, _ = fenced_node:range()

      -- For string parsers, use Treesitter's get_node_text with source string
      local code_content = vim.treesitter.get_node_text(code_node, content)
      if code_content then
        table.insert(blocks, {
          language = lang,
          code = code_content,
          start_line = start_line + 1, -- 1-based line number for the start of the block
          line_count = #vim.split(code_content, "\n"),
        })
      end
    end
  end

  return blocks
end

-- Create chat window
M.open = function()
  if M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    vim.api.nvim_set_current_win(M._chat_state.winid)
    return
  end

  -- Create chat buffer if needed
  if not M._chat_state.bufnr or not vim.api.nvim_buf_is_valid(M._chat_state.bufnr) then
    M._chat_state.bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(M._chat_state.bufnr, "Caramba Chat")
    vim.api.nvim_buf_set_option(M._chat_state.bufnr, "filetype", "markdown")
    vim.api.nvim_buf_set_option(M._chat_state.bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(M._chat_state.bufnr, "modifiable", false)
  end

  -- Calculate window size using config (sidebar style)
  local ui = config.get().ui
  local width = math.floor(vim.o.columns * (ui.chat_sidebar_width or 0.4))
  local height = vim.o.lines - 4

  -- Create floating window
  M._chat_state.winid = vim.api.nvim_open_win(M._chat_state.bufnr, true, {
    relative = "editor",
    row = 1,
    col = vim.o.columns - width - 2,
    width = width,
    height = height,
    style = "minimal",
    border = ui.floating_window_border or "rounded",
    title = " Caramba Chat ",
    title_pos = "center",
  })

  -- Set window options
  vim.api.nvim_win_set_option(M._chat_state.winid, "wrap", true)
  vim.api.nvim_win_set_option(M._chat_state.winid, "linebreak", true)
  vim.api.nvim_win_set_option(M._chat_state.winid, "cursorline", true)

  -- Render existing history
  M._render_chat()

  -- Set up keymaps
  local opts = { buffer = M._chat_state.bufnr, silent = true }
  vim.keymap.set("n", "i", M.start_input, opts)
  vim.keymap.set("n", "I", M.start_input, opts)
  vim.keymap.set("n", "o", M.start_input, opts)
  vim.keymap.set("n", "O", M.start_input, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
  vim.keymap.set("n", "a", M._apply_code_at_cursor, opts)
  vim.keymap.set("n", "y", M._copy_code_at_cursor, opts)
  vim.keymap.set("n", "d", M.clear_history, opts)
  vim.keymap.set("n", "r", M._revert_last_change, opts)
  vim.keymap.set("n", "z", function()
    -- Toggle fold on the section under cursor (messages with a title)
    local cursor = vim.api.nvim_win_get_cursor(M._chat_state.winid)
    local row = cursor[1]
    local ranges = M._chat_state.msg_ranges or {}
    for _, r in ipairs(ranges) do
      if row >= r.start_line and row <= r.end_line then
        local m = M._chat_state.history[r.index]
        if m and m.title then
          m.folded = not m.folded
          M._render_chat()
        end
        break
      end
    end
  end, opts)
end

-- Close chat window
M.close = function()
  if M._chat_state.input_winid and vim.api.nvim_win_is_valid(M._chat_state.input_winid) then
    vim.api.nvim_win_close(M._chat_state.input_winid, true)
  end

  if M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    vim.api.nvim_win_close(M._chat_state.winid, true)
  end
end

-- Start input mode
M.start_input = function()
  -- Create input buffer
  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(input_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(input_buf, "modifiable", true)

  -- Create input window at bottom of chat
  local chat_config = vim.api.nvim_win_get_config(M._chat_state.winid)
  local input_height = 3

  M._chat_state.input_bufnr = input_buf
  local ui = config.get().ui
  M._chat_state.input_winid = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    row = chat_config.row + chat_config.height - input_height,
    col = chat_config.col,
    width = chat_config.width,
    height = input_height,
    style = "minimal",
    border = (ui and ui.floating_window_border == 'rounded' and 'single') or (ui and ui.floating_window_border or 'single'),
    title = " Type your message (Enter to send, Esc to cancel) ",
    title_pos = "center",
  })

  -- Set up input keymaps
  local opts = { buffer = input_buf, silent = true }
  vim.keymap.set("i", "<CR>", M._send_message, opts)
  vim.keymap.set("n", "<CR>", M._send_message, opts)
  vim.keymap.set("i", "<Esc>", M._cancel_input, opts)
  vim.keymap.set("n", "<Esc>", M._cancel_input, opts)

  -- Enter insert mode
  vim.cmd("startinsert")
end

-- Send message
M._send_message = function()
  if not M._chat_state.input_bufnr then return end

  -- Get message content
  local lines = vim.api.nvim_buf_get_lines(M._chat_state.input_bufnr, 0, -1, false)
  local message = table.concat(lines, "\n"):match("^%s*(.-)%s*$")

  if message == "" then
    M._cancel_input()
    logger.debug('Empty message ignored')
    return
  end

  -- Parse context commands
  local cleaned_message, contexts = parse_context_commands(message)

  -- Handle web searches asynchronously
  local pending_searches = 0
  local search_results = {}

  for i, ctx in ipairs(contexts) do
    if ctx.type == "web_search" and ctx.pending then
      pending_searches = pending_searches + 1

      require('caramba.websearch').search(ctx.query, {
        limit = 3,
        callback = function(results, err)
          pending_searches = pending_searches - 1

          if results then
            search_results[i] = {
              query = ctx.query,
              results = results,
            }
          end

          -- When all searches complete, continue with message
          if pending_searches == 0 then
            M._send_message_with_context(cleaned_message, contexts, search_results, message)
          end
        end,
      })
    end
  end

  -- If no web searches, send immediately
  if pending_searches == 0 then
    M._send_message_with_context(cleaned_message, contexts, {}, message)
  end
end

-- Helper to send message after web searches complete
M._send_message_with_context = function(cleaned_message, contexts, search_results, original_message)
  -- Debug logging
  if config.get().debug then
    vim.notify("Caramba: Sending message: " .. string.sub(cleaned_message, 1, 50) .. "...", vim.log.levels.INFO)
  end
  logger.info('Chat send', { preview = string.sub(cleaned_message, 1, 120) })

  -- If no context commands were used, automatically add smart context
  if #contexts == 0 and #search_results == 0 then
    local smart_context = context.collect()
    if smart_context and smart_context.content then
      table.insert(contexts, {
        type = "buffer",
        name = smart_context.filename or "[Current Buffer]",
        content = context.build_context_string(smart_context)
      })
      if config.get().debug then
        vim.notify("Caramba: Automatically added smart context.", vim.log.levels.INFO)
      end
    end
  end

  -- Get open buffers for automatic context
  local open_buffers_result = openai_tools.tool_functions.get_open_buffers({})
  local open_buffers = open_buffers_result.buffers or {}

  -- Search memory for relevant context
  local memory_results = memory.search_multi_angle(
    cleaned_message,
    { language = "lua", context = "neovim" },
    "caramba nvim plugin development"
  )

  -- Build full prompt with contexts
  local full_content = cleaned_message

  -- Orchestrator: prepend enriched prompt section
  push_activity('Preparing context and enrichment')
  local chat_cfg = (config.get().chat or {})
  if chat_cfg.enable_enrichment ~= false then
    local enrich = orchestrator.build_enriched_prompt(cleaned_message)
    if enrich and enrich ~= '' then
      local max_extra = chat_cfg.max_enrichment_chars or 12000
      if #enrich > max_extra then
        enrich = enrich:sub(1, max_extra) .. "\n\n[Enrichment truncated]"
      end
      full_content = full_content .. "\n\n" .. enrich
    end
  end

  -- Add open buffers context
  if #open_buffers > 0 then
    logger.debug('Including open buffers in context', { count = #open_buffers })
    full_content = full_content .. "\n\n## Open Files Context:\n"
    for _, buffer in ipairs(open_buffers) do
      local filename = buffer.path:match("([^/]+)$") or buffer.path
      full_content = full_content .. string.format("\n### %s (%s)%s\n```%s\n%s\n```\n",
        filename,
        buffer.filetype,
        buffer.modified and " [MODIFIED]" or "",
        buffer.filetype,
        buffer.content)
    end
  end

  -- Add memory context
  if #memory_results > 0 then
    logger.debug('Including memory results', { count = #memory_results })
    full_content = full_content .. "\n\n## Relevant Memory:\n"
    for _, result in ipairs(memory_results) do
      full_content = full_content .. string.format("\n- %s (relevance: %.2f)\n",
        result.entry.content, result.relevance)
    end
  end

  -- Add explicit contexts from commands
  if #contexts > 0 then
    full_content = full_content .. "\n\n## Additional Context:\n"
    for i, ctx in ipairs(contexts) do
      if ctx.type == "buffer" then
        full_content = full_content .. string.format("\n[Current Buffer: %s]\n```\n%s\n```\n",
          ctx.name, ctx.content)
      elseif ctx.type == "selection" then
        full_content = full_content .. "\n[Selected Code]\n```\n" .. ctx.content .. "\n```\n"
      elseif ctx.type == "file" then
        full_content = full_content .. string.format("\n[File: %s]\n```\n%s\n```\n",
          ctx.name, ctx.content)
      elseif ctx.type == "web_search" and search_results[i] then
        full_content = full_content .. string.format("\n[Web Search: %s]\n%s\n",
          search_results[i].query, search_results[i].results)
      end
    end
  end

  -- Add to history (store original message for display)
  table.insert(M._chat_state.history, {
    role = "user",
    content = original_message, -- Original message with @commands
    full_content = full_content, -- Full content for API
  })

  -- Context Discovery diagnostics (foldable, non-LLM)
  do
    local diag_lines = {}
    table.insert(diag_lines, "- Open buffers: " .. tostring(#open_buffers))
    if #open_buffers > 0 then
      for _, b in ipairs(open_buffers) do
        local mark = b.modified and "*" or ""
        table.insert(diag_lines, string.format("  - %s%s (%s)", b.path, mark, b.filetype))
      end
    end
    table.insert(diag_lines, "- Memory results: " .. tostring(#(memory_results or {})))
    if #memory_results > 0 then
      for i, r in ipairs(memory_results) do
        if i > 5 then break end
        table.insert(diag_lines, string.format("  - %.2f: %s", r.relevance or 0, (r.entry and r.entry.content) and r.entry.content:sub(1, 80) or ""))
      end
    end
    table.insert(M._chat_state.history, {
      role = 'assistant',
      title = 'Context Discovery',
      content = table.concat(diag_lines, "\n"),
      folded = true,
    })
  end

  -- Defer main agent until pre-stages complete
  local cfg = config.get() or {}
  local function start_main_with(improved)
    local full2 = full_content
    if improved and improved ~= '' then
      full2 = '## Improved Prompt\n' .. improved .. '\n\n' .. full2
    end
    push_activity('Updating plan (pre-send)')
    pcall(orchestrator.update_plan_from_prompt, improved and improved or cleaned_message)
    push_activity('Requesting model...')
    logger.info('Starting agentic response')
    M._start_agentic_response(full2)
  end

  local function run_memory_recall_then_start(improved)
    if (cfg.pipeline and cfg.pipeline.enable_self_reflection) == nil then end -- no-op keep cfg used
    -- Simple LLM-driven memory recall on top of local recall (already added separately)
    local sys = 'You are a memory manager. Given the user request, propose up to 5 brief context additions from long-term memory that would help. Use bullet points only.'
    stream_section('Memory Manager (Recall)', sys, improved or cleaned_message, 'chat', function(_)
      -- For complex tasks, add PM plan stage before main
      local lower_instruction = (improved or cleaned_message or ''):lower()
      local complex = false
      for _, kw in ipairs({ 'implement','create','build','design','refactor','migrate','convert','add','rewrite' }) do
        if lower_instruction:match('^%s*' .. kw) then complex = true break end
      end
      if complex then
        local sys_pm = 'You are a Project Manager. Update or create a concise plan (TODO/DOING/DONE) for the task. Return a short markdown summary with priorities.'
        stream_section('Project Manager (Plan)', sys_pm, improved or cleaned_message, 'plan', function(plan_md)
          pcall(orchestrator.update_plan_from_markdown, plan_md, improved or cleaned_message)
          start_main_with(improved)
        end)
      else
        start_main_with(improved)
      end
    end)
  end

  if (cfg.pipeline and cfg.pipeline.enable_prompt_engineering) ~= false then
    local sys = 'Rewrite the following request into a precise, concise engineering task. Keep semantics, remove fluff. Output only the improved prompt.'
    stream_section('Improved Prompt', sys, cleaned_message, 'chat', function(improved)
      run_memory_recall_then_start(improved)
    end)
  else
    run_memory_recall_then_start(nil)
  end

  -- Memory recall (vector store): stream a short note of recalled items
  do
    local idx = #M._chat_state.history + 1
    M._chat_state.history[idx] = { role = 'assistant', title = 'Memory Recall', content = '', streaming = true, folded = false }
    M._render_chat()
    -- Prefer binary vector store if available
    local vector_mod = require('caramba.memory_vector_bin')
    vector_mod.recall(cleaned_message, 5, function(items)
      local lines = {}
      for _, it in ipairs(items or {}) do
        table.insert(lines, string.format('- [%.2f] %s', it.score or 0, (it.meta and it.meta.snippet) or (it.meta and it.meta.content) or ''))
      end
      M._chat_state.history[idx].content = table.concat(lines, '\n')
      M._chat_state.history[idx].streaming = false
      M._chat_state.history[idx].folded = true
      M._render_chat()
    end)
  end

  -- Store user message in memory
  memory.store(
    original_message,
    {
      context = "user_message",
      timestamp = vim.fn.localtime(),
      open_files = vim.tbl_map(function(buf) return buf.path end, open_buffers)
    },
    { "caramba", "chat", "user_message" }
  )
  logger.debug('Stored user message to memory')

  -- Close input window
  M._cancel_input()

  -- Render immediately to show user message
  M._render_chat()

  -- Main agent start is now triggered after pre-stages

  -- If the instruction looks complex, stream a Plan Review helper (foldable) in background
  local lower_instruction = (cleaned_message or ''):lower()
  local complex = false
  for _, kw in ipairs({ 'implement','create','build','design','refactor','migrate','convert','add','rewrite' }) do
    if lower_instruction:match('^%s*' .. kw) then complex = true break end
  end
  if complex then
    local outline_prompt = {
      { role = 'system', content = 'You are a technical lead. Provide a concise plan review: risks, missing info, and a step-by-step outline (5-10 steps). Keep it actionable.' },
      { role = 'user', content = string.format('Task:\n%s\n\nContext summary (files open):\n%s', cleaned_message, table.concat(vim.tbl_map(function(b) return b.path end, open_buffers or {}), '\n')) },
    }
    local idx = #M._chat_state.history + 1
    M._chat_state.history[idx] = { role = 'assistant', title = 'Plan Review', content = '', streaming = true, folded = false }
    M._render_chat()
    logger.info('Plan Review stream start')
    llm.request_stream(outline_prompt, { task = 'plan' }, function(delta)
      if type(delta) == 'string' and delta ~= '' then
        logger.debug('Plan Review chunk', delta:sub(1, 120))
        M._chat_state.history[idx].content = (M._chat_state.history[idx].content or '') .. delta
        M._render_chat()
      end
    end, function(_, err)
      M._chat_state.history[idx].streaming = false
      M._chat_state.history[idx].folded = true
      logger.info('Plan Review stream complete', err or '')
      M._render_chat()
    end)
  end
end

M._start_agentic_response = function(full_content)
  -- Add placeholder for assistant response entry with empty content (no emoji)
  table.insert(M._chat_state.history, {
    role = "assistant",
    content = "",
    streaming = true,
  })
  start_animation('thinking')
  logger.debug('Agentic response placeholder added')
  M._render_chat()

  local initial_messages = {
    {
      role = "system",
      content = "You are a helpful AI coding assistant, integrated into the Neovim editor. Use the tools provided to help the user achieve their goals.",
    },
  }

  local chat_session = openai_tools.create_chat_session(initial_messages, openai_tools.available_tools)

  chat_session:send(
    full_content,
    function(chunk, err) -- on_chunk
      vim.schedule(function()
        if err then
          M._handle_response_error(err)
        else
          M._handle_chunk(chunk)
        end
      end)
    end,
    function(final_response, err) -- on_finish
      vim.schedule(function()
        if err then
          M._handle_response_error(err)
        else
          -- Post-execution pipeline: Self-Reflection -> Reviewer -> PM Update -> Memory Extract
          local last_user = ''
          for i = #M._chat_state.history - 1, 1, -1 do
            local msg = M._chat_state.history[i]
            if msg and msg.role == 'user' and msg.content then last_user = msg.content break end
          end
          local cfg = config.get() or {}
          local function write_recommendations(md)
            local dir = vim.fn.stdpath('data') .. '/caramba'
            vim.fn.mkdir(dir, 'p')
            local path = dir .. '/recommendations.md'
            local f = io.open(path, 'a')
            if f then
              f:write('\n\n# Review @ ' .. os.date('%Y-%m-%d %H:%M:%S') .. '\n\n')
              f:write(md)
              f:write('\n')
              f:close()
            end
          end
          local function memory_extract_and_finish(context_blob)
            local sys = 'Extract up to 5 short, independent memory items (facts, decisions, lessons). Output as simple bullets, no prose.'
            stream_section('Memory Extract', sys, context_blob, 'chat', function(mem_md)
              -- Store each bullet as memory and vector
              for line in string.gmatch(mem_md or '', '[^\n]+') do
                local s = line:gsub('^%s*[-*]%s*', '')
                if s ~= '' then
                  require('caramba.memory').store(s, { context = 'extracted_memory' }, { 'caramba','memory','extracted' })
                  require('caramba.memory_vector').add_from_text(s, { snippet = s, source = 'extract' })
                end
              end
              M._handle_response_complete(final_response)
            end)
          end
          local function pm_update_then_extract(context_blob)
            local sys = 'You are a Project Manager. Update the TODO/DOING/DONE plan based on the execution and review. Output a concise markdown board.'
            stream_section('Project Manager (Update)', sys, context_blob, 'plan', function(_)
              memory_extract_and_finish(context_blob)
            end)
          end
          local function reviewer_then_pm(context_blob)
            local sys = 'You are a Reviewer of the process (not just code). Provide actionable recommendations for Prompt Engineer, Memory Manager, Project Manager, and Developer roles. Use short bullets.'
            stream_section('Reviewer', sys, context_blob, 'chat', function(review_md)
              write_recommendations(review_md or '')
              pm_update_then_extract(context_blob)
            end)
          end
          local function start_post_sequence()
            local context_blob = string.format('User request:\n%s\n\nAssistant answer:\n%s', last_user or '', final_response or '')
            if (cfg.pipeline and cfg.pipeline.enable_self_reflection) ~= false then
              local sys = 'You are a strict code reviewer. In 5-8 bullet points, critique the assistant answer for correctness, safety, missing context, and propose 1-2 concrete improvements. Keep it concise.'
              stream_section('Self-Reflection', sys, context_blob, 'chat', function(reflect_md)
                local ctx2 = context_blob .. '\n\nSelf-Reflection:\n' .. (reflect_md or '')
                reviewer_then_pm(ctx2)
              end)
            else
              reviewer_then_pm(context_blob)
            end
          end
          start_post_sequence()
        end
      end)
    end
  )
  logger.debug('Chat session send initiated')
end

-- Handle incoming stream chunk
M._handle_chunk = function(chunk)
  local last_message = M._chat_state.history[#M._chat_state.history]
  if last_message and last_message.role == "assistant" and last_message.streaming then
    -- Ensure content is not nil
    if last_message.content == nil then
      last_message.content = ""
    end
    if chunk and chunk.is_tool_feedback and chunk.content then
      logger.debug('Tool feedback chunk', chunk.content)
      local one_line = (chunk.content or ''):gsub("\n", " "):gsub("%s+", " ")
      push_activity(one_line)
      if one_line:match('Using tool:') then
        set_animation_mode('tool')
      elseif one_line:match('Tool .* finished') or one_line:match('finished') then
        set_animation_mode('thinking')
      end
    elseif chunk and chunk.content then
      logger.trace('Content chunk', string.sub(chunk.content, 1, 200))
      -- Switch to writing mode when we start receiving normal content
      set_animation_mode('writing')
    end
    last_message.content = (last_message.content or "") .. (chunk.content or "")
    M._render_chat()
  end
end


-- Handle response completion
M._handle_response_complete = function(final_response)
  local last_message = M._chat_state.history[#M._chat_state.history]
  if last_message and last_message.role == "assistant" then
    last_message.content = final_response
    last_message.streaming = false
    -- Store to memory via orchestrator
    local user_text = ''
    for i = #M._chat_state.history - 1, 1, -1 do
      local msg = M._chat_state.history[i]
      if msg and msg.role == 'user' and msg.content then
        user_text = msg.content
        break
      end
    end
    push_activity('Storing memory and updating plan (post-response)')
    pcall(orchestrator.postprocess_response, user_text, final_response)
    logger.info('Response complete', { chars = #tostring(final_response or '') })
    stop_animation()
    M._render_chat()
  end
end

-- Handle response error
M._handle_response_error = function(err)
  local last_message = M._chat_state.history[#M._chat_state.history]
  if last_message and last_message.role == "assistant" then
    last_message.content = "I'm sorry, I encountered an error: " .. tostring(err)
    last_message.streaming = false
    logger.error('Response error', err)
    stop_animation()
    M._render_chat()
  end
end

-- Cancel input
M._cancel_input = function()
  if M._chat_state.input_winid and vim.api.nvim_win_is_valid(M._chat_state.input_winid) then
    vim.api.nvim_win_close(M._chat_state.input_winid, true)
    M._chat_state.input_winid = nil
    M._chat_state.input_bufnr = nil
  end

  -- Return focus to chat window and ensure we're in normal mode
  if M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    vim.api.nvim_set_current_win(M._chat_state.winid)
    -- Switch to normal mode to prevent staying in insert mode
    vim.cmd("stopinsert")
  end
end


-- Render chat history
M._render_chat = function()
  -- Debug logging
  if config.get().debug then
    vim.notify("Caramba: Rendering chat with " .. #M._chat_state.history .. " messages", vim.log.levels.INFO)
  end

  if not M._chat_state.bufnr or not vim.api.nvim_buf_is_valid(M._chat_state.bufnr) then
    return
  end

  vim.api.nvim_buf_set_option(M._chat_state.bufnr, "modifiable", true)

  local lines = {}
  local code_blocks = {}
  local msg_ranges = {}

  -- Add title
  table.insert(lines, "# Caramba Chat Session")
  table.insert(lines, "")
  table.insert(lines, "_Commands: (i)nput, (a)pply code, (y)ank code, (d)elete history, (r)evert changes, (q)uit_")
  table.insert(lines, "")

  -- Status line (animation)
  if M._chat_state.animation and M._chat_state.animation.status_text then
    table.insert(lines, "Status: " .. M._chat_state.animation.status_text)
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  -- Activity feed
  if M._chat_state.activity and #M._chat_state.activity > 0 then
    table.insert(lines, "## Activity")
    table.insert(lines, "")
    local from = math.max(1, #M._chat_state.activity - 10 + 1)
    for i = from, #M._chat_state.activity do
      table.insert(lines, "- " .. M._chat_state.activity[i])
    end
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")
  end

  -- Add messages
  for i_msg, msg in ipairs(M._chat_state.history) do
    local msg_lines = format_message(msg)
    local line_offset = #lines

    -- Track code blocks for this message
    if msg.role == "assistant" and msg.content then
      local blocks = extract_code_blocks(msg.content)
      for _, block in ipairs(blocks) do
        -- Adjust start line based on its position in the buffer.
        -- line_offset: lines from previous messages
        -- 2: lines from message header ("## Assistant:" and a blank line)
        block.start_line = line_offset + block.start_line + 2
        table.insert(code_blocks, block)
      end
    end

    vim.list_extend(lines, msg_lines)
    local end_line = #lines
    table.insert(msg_ranges, { index = i_msg, start_line = line_offset + 1, end_line = end_line })
  end

  -- Update buffer
  vim.api.nvim_buf_set_lines(M._chat_state.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M._chat_state.bufnr, "modifiable", false)

  -- Store code blocks for interaction
  M._chat_state.code_blocks = code_blocks
  M._chat_state.msg_ranges = msg_ranges

  -- Highlight sections
  vim.api.nvim_buf_clear_namespace(M._chat_state.bufnr, chat_hl_ns, 0, -1)
  local buf_lines = vim.api.nvim_buf_get_lines(M._chat_state.bufnr, 0, -1, false)
  for i, l in ipairs(buf_lines) do
    if l:match("^## ") or l:match("^Status:") then
      vim.api.nvim_buf_add_highlight(M._chat_state.bufnr, chat_hl_ns, 'Title', i - 1, 0, -1)
    elseif l:match("^%- ") then
      vim.api.nvim_buf_add_highlight(M._chat_state.bufnr, chat_hl_ns, 'DiagnosticHint', i - 1, 0, -1)
    end
  end

  -- Scroll to bottom
  if M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    local line_count = vim.api.nvim_buf_line_count(M._chat_state.bufnr)
    vim.api.nvim_win_set_cursor(M._chat_state.winid, {line_count, 0})
  end
end

-- Get code block at cursor
local function get_code_block_at_cursor()
  if not M._chat_state.code_blocks then return nil end

  local cursor = vim.api.nvim_win_get_cursor(M._chat_state.winid)
  local line = cursor[1]

  -- Find code block containing current line
  for _, block in ipairs(M._chat_state.code_blocks) do
    if block.start_line and line >= block.start_line then
      -- The block's start_line refers to the opening ```. The actual code content starts on the next line.
      local code_start_line = block.start_line + 1
      local code_end_line = code_start_line + block.line_count - 1

      -- Check if the cursor is within the code block boundaries:
      -- - On the opening fence line (block.start_line)
      -- - Within the code content (code_start_line to code_end_line)
      -- - On the closing fence line (code_end_line + 1)
      if line >= block.start_line and line <= code_end_line + 1 then
        return block
      end
    end
  end

  return nil
end

-- Apply code at cursor
M._apply_code_at_cursor = function()
  local block = get_code_block_at_cursor()
  if not block then
    vim.notify("No code block at cursor", vim.log.levels.WARN)
    return
  end

  -- Get the last active buffer before chat
  local target_buf = vim.fn.bufnr("#")
  if target_buf < 0 then
    vim.notify("No buffer to apply code to", vim.log.levels.WARN)
    return
  end

  -- Apply as a patch
  edit.apply_patch(target_buf, block.code, {
    validate = true,
    preview = true,
  })
end

-- Copy code at cursor
M._copy_code_at_cursor = function()
  local block = get_code_block_at_cursor()
  if not block then
    vim.notify("No code block at cursor", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", block.code)
  vim.notify("Code copied to clipboard", vim.log.levels.INFO)
end

-- Clear history
M.clear_history = function()
  M._chat_state.history = {}
  M._chat_state.code_blocks = {}
  M._render_chat()
  vim.notify("Chat history cleared", vim.log.levels.INFO)
end

-- Revert last AI change
M._revert_last_change = function()
  local edit = require('caramba.edit')
  edit.rollback(1)
  vim.notify("Reverted last AI change", vim.log.levels.INFO)
end

-- Toggle chat window
M.toggle = function()
  if M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    M.close()
  else
    M.open()
  end
end

-- Approve the last plan in the chat
M.approve_plan = function()
  local last_plan = nil
  -- Iterate backwards to find the last message with a plan
  for i = #M._chat_state.history, 1, -1 do
    if M._chat_state.history[i].plan then
      last_plan = M._chat_state.history[i].plan
      break
    end
  end

  if last_plan then
    vim.notify("Approving and executing the last plan.", vim.log.levels.INFO)
    require('caramba.planner').execute_plan(last_plan)
  else
    vim.notify("No plan found in the recent chat history to approve.", vim.log.levels.WARN)
  end
end

-- Setup commands for this module
M.setup_commands = function()
  local commands = require('caramba.core.commands')

  -- Open chat window
  commands.register('Chat', M.open, {
    desc = 'Open Caramba chat window',
  })

  -- Toggle chat window
  commands.register('ChatToggle', M.toggle, {
    desc = 'Toggle Caramba chat window',
  })

  -- Clear chat history
  commands.register('ChatClear', M.clear_history, {
    desc = 'Clear chat history',
  })

  -- Approve the last plan
  commands.register('ApprovePlan', M.approve_plan, {
    desc = 'Approve and execute the last plan proposed in the chat',
  })

  -- Test LLM connection
  commands.register('TestLLM', function()
    local messages = {
      { role = "user", content = "Say 'Hello, I am working!' if you can see this." }
    }

    vim.notify("Testing LLM connection...", vim.log.levels.INFO)

    llm.request(messages, {}, function(result, err)
      if err then
        vim.notify("LLM Error: " .. err, vim.log.levels.ERROR)
      elseif result then
        vim.notify("LLM Response: " .. result, vim.log.levels.INFO)
      else
        vim.notify("LLM returned no result", vim.log.levels.WARN)
      end
    end)
  end, {
    desc = 'Test LLM connection',
  })

  -- Test LLM streaming
  commands.register('TestLLMStream', function()
    local messages = {
      { role = "user", content = "Count from 1 to 10 slowly." }
    }

    vim.notify("Testing LLM streaming...", vim.log.levels.INFO)

    local chunks = {}
    llm.request_conversation(messages, { stream = true }, function(chunk, is_complete)
      if is_complete then
        vim.notify("Streaming complete. Total response: " .. table.concat(chunks, ""), vim.log.levels.INFO)
      elseif chunk then
        table.insert(chunks, chunk)
        vim.notify("Chunk: " .. chunk, vim.log.levels.INFO)
      else
        vim.notify("Streaming error occurred", vim.log.levels.ERROR)
      end
    end)
  end, {
    desc = 'Test LLM streaming',
  })

  -- Test OpenAI tools
  commands.register('TestOpenAITools', function()
    vim.notify("Testing OpenAI tools implementation...", vim.log.levels.INFO)

    local chat_session = openai_tools.create_chat_session({
      {
        role = "system",
        content = "You are a helpful assistant. Use tools when needed."
      }
    })

    chat_session:send("What files are currently open?", function(response, err)
      if err then
        vim.notify("OpenAI tools test FAILED: " .. err, vim.log.levels.ERROR)
      else
        vim.notify("OpenAI tools test SUCCESS: " .. response, vim.log.levels.INFO)
      end
    end)
  end, {
    desc = 'Test OpenAI tools implementation',
  })

  -- Test raw curl
  commands.register('TestCurl', function()
    vim.notify("Testing raw curl to OpenAI...", vim.log.levels.INFO)

    local api_key = config.get().api.openai.api_key
    if not api_key then
      vim.notify("No OpenAI API key set", vim.log.levels.ERROR)
      return
    end

    -- Simple non-streaming request first
    local payload = '{"model":"gpt-5-nano","messages":[{"role":"user","content":"Say hi"}],"max_completion_tokens":10}'
    local curl_cmd = string.format(
      'curl -sS -X POST https://api.openai.com/v1/chat/completions -H "Authorization: Bearer %s" -H "Content-Type: application/json" -d %s',
      api_key,
      vim.fn.shellescape(payload)
    )

    vim.fn.jobstart(curl_cmd, {
      on_stdout = function(_, data)
        vim.notify("Curl stdout: " .. vim.inspect(data), vim.log.levels.INFO)
      end,
      on_stderr = function(_, data)
        vim.notify("Curl stderr: " .. vim.inspect(data), vim.log.levels.ERROR)
      end,
      on_exit = function(_, code)
        vim.notify("Curl exited with code: " .. code, vim.log.levels.INFO)
      end,
    })
  end, {
    desc = 'Test raw curl to OpenAI',
  })

  -- Revert AI changes
  commands.register('RevertChanges', function(args)
    local edit = require('caramba.edit')
    local steps = tonumber(args.args) or 1
    edit.rollback(steps)
    vim.notify(string.format("Reverted %d change(s)", steps), vim.log.levels.INFO)
  end, {
    desc = 'Revert AI-made changes (specify number of steps, default 1)',
    nargs = '?',
  })
end

-- Setup function to initialize memory system
M.setup = function()
  memory.setup()
end

return M