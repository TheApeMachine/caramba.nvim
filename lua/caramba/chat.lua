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
local agent = require('caramba.agent')

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
}

-- Get open buffers for context
local function get_open_buffers_context()
  local buffers = {}

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'buflisted') then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name and name ~= "" and not name:match("caramba") then -- Exclude caramba buffers
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        table.insert(buffers, {
          name = name,
          content = table.concat(lines, "\n"),
          filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype'),
          modified = vim.api.nvim_buf_get_option(bufnr, 'modified')
        })
      end
    end
  end

  return buffers
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
  if msg.role == "user" then
    table.insert(lines, "## You:")
  else
    table.insert(lines, "## Assistant:")
  end
  
  table.insert(lines, "")
  
  -- Add content
  for line in msg.content:gmatch("[^%s]+") do
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
  local open_buffers = get_open_buffers_context()

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
      local filename = buffer.name:match("([^/]+)$") or buffer.name
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

  -- Add agent tools information
  full_content = full_content .. "\n\n" .. agent.get_tools_prompt()
  
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
      open_files = vim.tbl_map(function(buf) return buf.name end, open_buffers)
    },
    { "caramba", "chat", "user_message" }
  )

  -- Close input window
  M._cancel_input()

  -- Render immediately to show user message
  M._render_chat()

  -- First, use the planner to create/update the plan, then start agentic response
  -- Use a chat-specific planning session that doesn't show popups
  M._chat_planning_session(cleaned_message, full_content, function(plan, review, err)
    if err then
      vim.schedule(function()
        table.insert(M._chat_state.history, {
          role = "assistant",
          content = "I'm sorry, I encountered an error during planning: " .. tostring(err),
        })
        M._render_chat()
      end)
      return
    end

    vim.schedule(function()
      -- First, show the plan to the user
      local plan_display = M._format_plan_for_display(plan, review)
      table.insert(M._chat_state.history, {
        role = "assistant",
        content = plan_display,
        plan = plan,
        type = "plan"
      })
      M._render_chat()

      -- Then store the plan for context and start agentic response
      local plan_context = M._format_plan_for_context(plan, review)
      M._start_agentic_response(full_content, plan_context, plan)
    end)
  end)
end

-- Chat-specific planning session (no popups)
M._chat_planning_session = function(task_description, context_info, callback)
  -- Create initial plan without showing popups
  planner.create_task_plan(task_description, context_info, function(plan_result, plan_err)
    if plan_err then
      if callback then callback(nil, nil, plan_err) end
      return
    end

    local ok, plan = pcall(vim.json.decode, plan_result)
    if not ok then
      if callback then callback(nil, nil, "Failed to parse plan: " .. plan_result) end
      return
    end

    -- Review the plan
    planner.review_plan(vim.json.encode(plan), task_description, function(review_result, review_err)
      local review = nil
      if not review_err then
        local review_ok, parsed_review = pcall(vim.json.decode, review_result)
        if review_ok then
          review = parsed_review
        end
      end

      -- Call callback with plan and review (no popups)
      if callback then callback(plan, review, nil) end
    end)
  end)
end

-- Chat-specific planning session (no popups)
M._chat_planning_session = function(task_description, context_info, callback)
  -- Create initial plan without showing popups
  planner.create_task_plan(task_description, context_info, function(plan_result, plan_err)
    if plan_err then
      if callback then callback(nil, nil, plan_err) end
      return
    end

    local ok, plan = pcall(vim.json.decode, plan_result)
    if not ok then
      if callback then callback(nil, nil, "Failed to parse plan: " .. plan_result) end
      return
    end

    -- Review the plan
    planner.review_plan(vim.json.encode(plan), task_description, function(review_result, review_err)
      local review = nil
      if not review_err then
        local review_ok, parsed_review = pcall(vim.json.decode, review_result)
        if review_ok then
          review = parsed_review
        end
      end

      -- Call callback with plan and review (no popups)
      if callback then callback(plan, review, nil) end
    end)
  end)
end

-- Format plan for display to user
M._format_plan_for_display = function(plan, review)
  local lines = {}

  if not plan then
    return "📋 Failed to generate a plan."
  end

  table.insert(lines, "📋 **Plan Created**")
  table.insert(lines, "")
  table.insert(lines, "**Understanding:** " .. (plan.understanding or "N/A"))
  table.insert(lines, "**Complexity:** " .. (plan.estimated_complexity or "N/A"))
  table.insert(lines, "")

  if review and review.decision ~= "APPROVE" then
    table.insert(lines, "### ⚠️ Plan Review Feedback")
    table.insert(lines, "**Decision:** " .. review.decision)
    if review.feedback then
      for _, fb in ipairs(review.feedback) do table.insert(lines, "- " .. fb) end
    end
    table.insert(lines, "")
  end

  table.insert(lines, "### Implementation Steps")
  if plan.implementation_steps and #plan.implementation_steps > 0 then
    for _, step in ipairs(plan.implementation_steps) do
      table.insert(lines, string.format("- **%s** (`%s`)", step.action, step.file or "N/A"))
    end
  else
    table.insert(lines, "_No specific implementation steps were generated._")
  end

  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, "_Now gathering context and preparing response..._")

  return table.concat(lines, "\n")
end

-- Format plan for context (not display)
M._format_plan_for_context = function(plan, review)
  if not plan then return "" end

  local context_parts = {}
  table.insert(context_parts, "## Current Plan Context:")
  table.insert(context_parts, "**Understanding:** " .. (plan.understanding or "N/A"))
  table.insert(context_parts, "**Complexity:** " .. (plan.estimated_complexity or "N/A"))

  if plan.implementation_steps and #plan.implementation_steps > 0 then
    table.insert(context_parts, "**Implementation Steps:**")
    for _, step in ipairs(plan.implementation_steps) do
      table.insert(context_parts, string.format("- %s (%s)", step.action, step.file or "N/A"))
    end
  end

  if review and review.decision ~= "APPROVE" then
    table.insert(context_parts, "**Review Status:** " .. review.decision)
    if review.feedback then
      table.insert(context_parts, "**Feedback:** " .. table.concat(review.feedback, "; "))
    end
  end

  return table.concat(context_parts, "\n")
end

-- Start agentic response with streaming
M._start_agentic_response = function(full_content, plan_context, plan)
  -- Initialize streaming response
  M._chat_state.streaming = true
  M._chat_state.current_response = ""

  -- Add placeholder for assistant response
  table.insert(M._chat_state.history, {
    role = "assistant",
    content = "🤔 Analyzing request and gathering context...",
    streaming = true,
    plan = plan -- Store plan for later reference
  })
  M._render_chat()

  -- Build system prompt for agentic behavior
  local system_prompt = [[You are Caramba, an autonomous AI assistant for Neovim. You have access to tools that let you read files, search memory, and analyze code.

Key behaviors:
1. Be proactive - use tools to gather information before responding
2. When you see open files, analyze them to understand the codebase
3. Use memory search to find relevant past conversations
4. Follow the current plan context when provided
5. Provide specific, actionable responses
6. If you need to use tools, do so and then provide a comprehensive response

You can use tools by responding with JSON, then continue with your actual response.]]

  -- Combine content with plan context
  local enhanced_content = full_content
  if plan_context and plan_context ~= "" then
    enhanced_content = enhanced_content .. "\n\n" .. plan_context
  end

  -- Call LLM with streaming using existing request_stream function
  llm.request_stream({
    {
      role = "system",
      content = system_prompt
    },
    {
      role = "user",
      content = enhanced_content
    }
  }, {}, -- opts
  function(chunk) -- on_chunk
    M._handle_response_chunk(chunk)
  end,
  function(full_response, err) -- on_complete
    if err then
      M._handle_response_error(err)
    else
      M._handle_response_complete(full_response)
    end
  end)
end

-- Handle streaming response chunk
M._handle_response_chunk = function(chunk)
  if not M._chat_state.streaming then return end

  M._chat_state.current_response = M._chat_state.current_response .. chunk

  -- Update the last assistant message
  if #M._chat_state.history > 0 and M._chat_state.history[#M._chat_state.history].role == "assistant" then
    M._chat_state.history[#M._chat_state.history].content = M._chat_state.current_response
    M._render_chat()
  end
end

-- Handle response completion
M._handle_response_complete = function(full_response)
  M._chat_state.streaming = false

  -- Check if response contains tool usage
  local tool_usage = M._extract_tool_usage(full_response)
  if tool_usage then
    M._execute_tools_and_continue(tool_usage, full_response)
  else
    -- Store final response and save to memory
    if #M._chat_state.history > 0 and M._chat_state.history[#M._chat_state.history].role == "assistant" then
      M._chat_state.history[#M._chat_state.history].content = full_response
      M._chat_state.history[#M._chat_state.history].streaming = false
      M._render_chat()

      -- Save to memory with plan context
      local memory_context = {
        context = "chat_response",
        timestamp = vim.fn.localtime()
      }

      -- Include plan information if available
      if M._chat_state.history[#M._chat_state.history].plan then
        memory_context.plan_understanding = M._chat_state.history[#M._chat_state.history].plan.understanding
        memory_context.plan_complexity = M._chat_state.history[#M._chat_state.history].plan.estimated_complexity
      end

      memory.store(
        full_response,
        memory_context,
        { "caramba", "chat", "response" }
      )
    end
  end
end

-- Handle response error
M._handle_response_error = function(err)
  M._chat_state.streaming = false

  if #M._chat_state.history > 0 and M._chat_state.history[#M._chat_state.history].role == "assistant" then
    M._chat_state.history[#M._chat_state.history].content = "I'm sorry, I encountered an error: " .. tostring(err)
    M._chat_state.history[#M._chat_state.history].streaming = false
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

  -- Return focus to chat window
  if M._chat_state.winid and vim.api.nvim_win_is_valid(M._chat_state.winid) then
    vim.api.nvim_set_current_win(M._chat_state.winid)
  end
end

-- Extract tool usage from response
M._extract_tool_usage = function(response)
  local tool_pattern = '```json%s*(%{.-%})%s*```'
  local json_match = response:match(tool_pattern)

  if json_match then
    local ok, tool_data = pcall(vim.json.decode, json_match)
    if ok and tool_data.tool then
      return tool_data
    end
  end

  return nil
end

-- Execute tools and continue conversation
M._execute_tools_and_continue = function(tool_usage, original_response)
  local tool_result = agent.execute_tool(tool_usage.tool, tool_usage.parameters or {})

  -- Format tool result for display
  local tool_display = string.format("🔧 **Used tool: %s**\n```json\n%s\n```\n\n",
    tool_usage.tool, vim.json.encode(tool_result))

  -- Update the assistant message with tool usage
  if #M._chat_state.history > 0 and M._chat_state.history[#M._chat_state.history].role == "assistant" then
    M._chat_state.history[#M._chat_state.history].content = tool_display .. original_response
    M._render_chat()
  end

  -- Continue conversation with tool result
  local follow_up_prompt = string.format([[
Previous response: %s

Tool result: %s

Please provide a comprehensive response based on the tool results and original request.]],
    original_response, vim.json.encode(tool_result))

  -- Start new streaming response
  M._start_follow_up_response(follow_up_prompt)
end

-- Start follow-up response after tool usage
M._start_follow_up_response = function(prompt)
  M._chat_state.streaming = true
  M._chat_state.current_response = ""

  llm.request_stream({
    {
      role = "user",
      content = prompt
    }
  }, {}, -- opts
  function(chunk) -- on_chunk
    if M._chat_state.streaming then
      M._chat_state.current_response = M._chat_state.current_response .. chunk
      if #M._chat_state.history > 0 and M._chat_state.history[#M._chat_state.history].role == "assistant" then
        local current_content = M._chat_state.history[#M._chat_state.history].content
        local tool_part = current_content:match("^(🔧.-\n\n)")
        if tool_part then
          M._chat_state.history[#M._chat_state.history].content = tool_part .. M._chat_state.current_response
        else
          M._chat_state.history[#M._chat_state.history].content = M._chat_state.current_response
        end
        M._render_chat()
      end
    end
  end,
  function(full_response, err) -- on_complete
    if err then
      M._handle_response_error(err)
    else
      M._handle_response_complete(full_response)
    end
  end)
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
    if msg.role == "assistant" then
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
 