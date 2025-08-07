-- Caramba Chat Panel Module
-- Provides an interactive chat interface with context awareness

local M = {}

-- Dependencies
local llm = require('caramba.llm')
local edit = require('caramba.edit')
local config = require('caramba.config')
local context = require('caramba.context')
local planner = require('caramba.planner')
local utils = require('caramba.utils')
local memory = require('caramba.memory')

local openai_tools = require('caramba.openai_tools')

-- Chat state
M._chat_state = {
  history = {},
  bufnr = nil,
  winid = nil,
  input_bufnr = nil,
  input_winid = nil,
  code_blocks = {},
  streaming = false,
  current_response = "",
  tool_iterations = 0,
  max_tool_iterations = 5,
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
  if msg.role == "user" then
    table.insert(lines, "## You:")
  else
    table.insert(lines, "## Assistant:")
  end
  
  table.insert(lines, "")
  
  -- Add content, ensuring it's not nil
  local content = msg.content or ""
  for line in content:gmatch("[^\n]+") do
    table.insert(lines, line)
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
    
    if code_node and fenced_node then
      local lang = "text"
      if captures.language then
        lang = utils.get_node_text(captures.language, content)
      end
      
      local start_line, _, _, _ = fenced_node:range()
      
      local code_content = utils.get_node_text(code_node, content)
      table.insert(blocks, {
        language = lang,
        code = code_content,
        start_line = start_line + 1, -- 1-based line number for the start of the block
        line_count = #vim.split(code_content, "\n"),
      })
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

  -- Add open buffers context
  if #open_buffers > 0 then
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

  -- Close input window
  M._cancel_input()

  -- Render immediately to show user message
  M._render_chat()

  -- Start agentic response directly
  M._start_agentic_response(full_content)
end

M._start_agentic_response = function(full_content)
  -- Add placeholder for assistant response
  table.insert(M._chat_state.history, {
    role = "assistant",
    content = "🤔",
    streaming = true,
  })
  M._render_chat()

  local initial_messages = {
    {
      role = "system",
      content = "You are a helpful assistant. Use the tools provided to answer the user's question.",
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
          M._handle_response_complete(final_response)
        end
      end)
    end
  )
end

-- Handle incoming stream chunk
M._handle_chunk = function(chunk)
  local last_message = M._chat_state.history[#M._chat_state.history]
  if last_message and last_message.role == "assistant" and last_message.streaming then
    -- Ensure content is not nil
    if last_message.content == "🤔" then
      last_message.content = ""
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
    M._render_chat()
  end
end

-- Handle response error
M._handle_response_error = function(err)
  local last_message = M._chat_state.history[#M._chat_state.history]
  if last_message and last_message.role == "assistant" then
    last_message.content = "I'm sorry, I encountered an error: " .. tostring(err)
    last_message.streaming = false
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
  
  -- Add title
  table.insert(lines, "# Caramba Chat Session")
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
    local curl_cmd = string.format(
      'curl -sS -X POST https://api.openai.com/v1/chat/completions ' ..
      '-H "Authorization: Bearer %s" ' ..
      '-H "Content-Type: application/json" ' ..
      '-d \'{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Say hi"}],"max_tokens":10}\'',
      api_key
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
end

-- Setup function to initialize memory system
M.setup = function()
  memory.setup()
end

return M