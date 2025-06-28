-- AI Chat Panel Module
-- Provides an interactive chat interface with context awareness

local M = {}

local config = require('ai.config')
local context = require('ai.context')
local llm = require('ai.llm')
local edit = require('ai.edit')

-- Chat state
M._chat_state = {
  history = {},
  bufnr = nil,
  winid = nil,
  input_bufnr = nil,
  input_winid = nil,
  context_files = {},
}

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
  for query in message:gmatch("@web:([^\n]+)") do
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
  if msg.role == "user" then
    table.insert(lines, "## You:")
  else
    table.insert(lines, "## Assistant:")
  end
  
  table.insert(lines, "")
  
  -- Add content
  for line in msg.content:gmatch("[^\n]+") do
    table.insert(lines, line)
  end
  
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")
  
  return lines
end

-- Extract code blocks from message
local function extract_code_blocks(content)
  local blocks = {}
  local lines = vim.split(content, "\n")
  local in_code_block = false
  local current_block = nil
  local current_line = 1
  
  for i, line in ipairs(lines) do
    if line:match("^```") then
      if in_code_block then
        -- End of code block
        if current_block then
          table.insert(blocks, current_block)
          current_block = nil
        end
        in_code_block = false
      else
        -- Start of code block
        local lang = line:match("^```(%w*)")
        current_block = {
          language = lang ~= "" and lang or "text",
          code = {},
          start_line = i + 1, -- Next line is where code starts
        }
        in_code_block = true
      end
    elseif in_code_block and current_block then
      table.insert(current_block.code, line)
    end
  end
  
  -- Process blocks to join code lines
  for _, block in ipairs(blocks) do
    block.code = table.concat(block.code, "\n")
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
    vim.api.nvim_buf_set_name(M._chat_state.bufnr, "AI Chat")
    vim.api.nvim_buf_set_option(M._chat_state.bufnr, "filetype", "markdown")
    vim.api.nvim_buf_set_option(M._chat_state.bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(M._chat_state.bufnr, "modifiable", false)
  end
  
  -- Calculate window size (40% width, full height)
  local width = math.floor(vim.o.columns * 0.4)
  local height = vim.o.lines - 4
  
  -- Create floating window
  M._chat_state.winid = vim.api.nvim_open_win(M._chat_state.bufnr, true, {
    relative = "editor",
    row = 1,
    col = vim.o.columns - width - 2,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " AI Chat ",
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
  M._chat_state.input_winid = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    row = chat_config.row + chat_config.height - input_height,
    col = chat_config.col,
    width = chat_config.width,
    height = input_height,
    style = "minimal",
    border = "single",
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
      
      require('ai.websearch').search(ctx.query, {
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
  -- Build full prompt with contexts
  local full_content = cleaned_message
  if #contexts > 0 then
    full_content = full_content .. "\n\nContext:\n"
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
  
  -- Close input window
  M._cancel_input()
  
  -- Render immediately to show user message
  M._render_chat()
  
  -- Build conversation for API
  local conversation = {}
  for _, msg in ipairs(M._chat_state.history) do
    table.insert(conversation, {
      role = msg.role,
      content = msg.full_content or msg.content
    })
  end
  
  -- Request response
  llm.request_conversation(conversation, {
    temperature = 0.7,
    stream = true,
  }, function(chunk, is_complete)
    vim.schedule(function()
      if is_complete then
        -- Final message is complete
        M._render_chat()
      else
        -- Streaming update
        if #M._chat_state.history == 0 or 
           M._chat_state.history[#M._chat_state.history].role ~= "assistant" then
          -- Start new assistant message
          table.insert(M._chat_state.history, {
            role = "assistant",
            content = chunk,
          })
        else
          -- Append to existing assistant message
          M._chat_state.history[#M._chat_state.history].content = 
            M._chat_state.history[#M._chat_state.history].content .. chunk
        end
        M._render_chat()
      end
    end)
  end)
end

-- Cancel input
M._cancel_input = function()
  if M._chat_state.input_winid and vim.api.nvim_win_is_valid(M._chat_state.input_winid) then
    vim.api.nvim_win_close(M._chat_state.input_winid, true)
    M._chat_state.input_winid = nil
    M._chat_state.input_bufnr = nil
  end
  
  -- Return focus to chat window
  if M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    vim.api.nvim_set_current_win(M._chat_state.winid)
  end
end

-- Render chat history
M._render_chat = function()
  if not M._chat_state.bufnr or not vim.api.nvim_buf_is_valid(M._chat_state.bufnr) then
    return
  end
  
  vim.api.nvim_buf_set_option(M._chat_state.bufnr, "modifiable", true)
  
  local lines = {}
  local code_blocks = {}
  
  -- Add title
  table.insert(lines, "# AI Chat Session")
  table.insert(lines, "")
  table.insert(lines, "_Commands: (i)nput, (a)pply code, (y)ank code, (d)elete history, (q)uit_")
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")
  
  -- Add messages
  for _, msg in ipairs(M._chat_state.history) do
    local msg_lines = format_message(msg)
    local line_offset = #lines
    
    -- Track code blocks for this message
    if msg.role == "assistant" then
      local blocks = extract_code_blocks(msg.content)
      for _, block in ipairs(blocks) do
        -- Adjust start line based on current position in buffer
        block.start_line = line_offset + block.start_line + 6 -- Account for headers
        table.insert(code_blocks, block)
      end
    end
    
    vim.list_extend(lines, msg_lines)
  end
  
  -- Update buffer
  vim.api.nvim_buf_set_lines(M._chat_state.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M._chat_state.bufnr, "modifiable", false)
  
  -- Store code blocks for interaction
  M._chat_state.code_blocks = code_blocks
  
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
    if block.start_line and line >= block.start_line and 
       line <= block.start_line + #vim.split(block.code, "\n") + 2 then
      return block
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

-- Toggle chat window
M.toggle = function()
  if M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    M.close()
  else
    M.open()
  end
end

return M 