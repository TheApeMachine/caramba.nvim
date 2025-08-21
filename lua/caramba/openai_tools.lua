-- OpenAI Tools Implementation for Caramba
-- Implements proper OpenAI functions/tools API using existing HTTP infrastructure

local M = {}

-- Dependencies
local config = require('caramba.config')
local Job = require('plenary.job')
local logger = require('caramba.logger')
local utils = require('caramba.utils')

-- Optional reporter for fine-grained tool steps
M._tool_reporter = nil
local function report(text)
  if M._tool_reporter then M._tool_reporter(text) end
end

M.available_tools = {
  {
    type = "function",
    ["function"] = {
      name = "get_open_buffers",
      description = "Get a list of currently open buffers with their file paths and content",
      parameters = {
        type = "object",
        properties = vim.empty_dict(),
        required = {},
        additionalProperties = false
      }
    }
  },
  {
    type = "function",
    ["function"] = {
      name = "read_file",
      description = "Read the contents of a specific file",
      parameters = {
        type = "object",
        properties = {
          file_path = {
            type = "string",
            description = "The path to the file to read",
          },
        },
        required = { "file_path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "search_files",
      description = "Search for files or content in the codebase",
      parameters = {
        type = "object",
        properties = {
          query = {
            type = "string",
            description = "The search query",
          },
          file_pattern = {
            type = "string",
            description = "Optional file pattern to limit search",
          },
        },
        required = { "query" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "write_file",
      description = "Write content to a file, creating or overwriting it completely",
      parameters = {
        type = "object",
        properties = {
          file_path = {
            type = "string",
            description = "The path to the file to write",
          },
          content = {
            type = "string",
            description = "The complete content to write to the file",
          },
        },
        required = { "file_path", "content" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "edit_file",
      description = "Apply targeted edits to a specific range in a file",
      parameters = {
        type = "object",
        properties = {
          file_path = {
            type = "string",
            description = "The path to the file to edit",
          },
          start_line = {
            type = "integer",
            description = "Starting line number (1-based)",
          },
          end_line = {
            type = "integer",
            description = "Ending line number (1-based)",
          },
          new_content = {
            type = "string",
            description = "The new content to replace the specified range",
          },
        },
        required = { "file_path", "start_line", "end_line", "new_content" },
      },
    },
  },
}

-- Tool implementations
M.tool_functions = {
  get_open_buffers = function(args)
    args = args or {}
    report('Tool get_open_buffers: scanning listed buffers')
    local buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_option(buf, 'buflisted') then
        local name = vim.api.nvim_buf_get_name(buf)
        local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
        if name and name ~= "" and buftype ~= 'nofile' then
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          table.insert(buffers, {
            path = name,
            content = table.concat(lines, "\n"),
            filetype = vim.api.nvim_buf_get_option(buf, 'filetype'),
            modified = vim.api.nvim_buf_get_option(buf, 'modified'),
            line_count = #lines
          })
        end
      end
    end
    report(string.format('Tool get_open_buffers: found %d buffers', #buffers))
    return { buffers = buffers, count = #buffers }
  end,

  read_file = function(args)
    local file_path = args.file_path
    if not file_path then
      return { error = "file_path is required" }
    end
    report('Tool read_file: reading ' .. file_path)
    local ok, lines = pcall(vim.fn.readfile, file_path)
    if not ok then
      report('Tool read_file: failed')
      return { error = "Could not read file: " .. file_path }
    end
    report('Tool read_file: success')
    return {
      path = file_path,
      content = table.concat(lines, "\n")
    }
  end,

  search_files = function(args)
    local query = args.query
    local file_pattern = args.file_pattern or "*"

    if not query then
      return { error = "query is required" }
    end

    report('Tool search_files: running ripgrep/grep for "' .. query .. '"')
    logger.debug('tool.search_files.start', { query = query, file_pattern = file_pattern })
    local cmd = "rg"
    local cmd_args = {"-n", "--type-add", "code:*.{lua,py,js,ts,jsx,tsx,go,rs,java,c,cpp,h,hpp}", "-t", "code", "-m", "200", query}
    if file_pattern and file_pattern ~= "*" then
      table.insert(cmd_args, "--glob")
      table.insert(cmd_args, file_pattern)
    end

    local rg_available = vim.fn.executable("rg") == 1
    if not rg_available then
      cmd = "grep"
      cmd_args = {"-rn", "-m", "200", query, "."}
    end

    local results = {}
    local root = utils.get_project_root()
    local stderr_lines = {}
    local job = Job:new({
      command = cmd,
      args = cmd_args,
      cwd = root,
      on_stderr = function(_, data)
        if data and #data > 0 then table.insert(stderr_lines, data) end
      end,
      on_exit = function(j, return_val)
        if return_val == 0 then
          local output = j:result()
          for _, line in ipairs(output) do
            table.insert(results, line)
          end
        end
      end,
    })

    local timeout_ms = 12000
    local ok, err = pcall(function() job:sync(timeout_ms) end)
    if not ok then
      report('Tool search_files: timed out at ' .. tostring(timeout_ms) .. 'ms')
      logger.warn('tool.search_files.timeout', { query = query, timeout_ms = timeout_ms })
      return { query = query, results = {}, error = 'timeout' }
    end
    report('Tool search_files: results ' .. tostring(#results))
    logger.debug('tool.search_files.results', { count = #results, stderr = table.concat(stderr_lines, '\n') })
    return { query = query, results = results }
  end,

  write_file = function(args)
    local file_path = args.file_path
    local content = args.content

    if not file_path then
      return { error = "file_path is required" }
    end

    if not content then
      return { error = "content is required" }
    end

    report('Tool write_file: writing ' .. file_path)
    local expanded_path = vim.fn.expand(file_path)
    local dir = vim.fn.fnamemodify(expanded_path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end

    -- Always route through buffer patch with preview for user awareness
    local bufnr = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf) == expanded_path then bufnr = buf break end
    end
    if not bufnr then bufnr = vim.fn.bufadd(expanded_path) end
    vim.fn.bufload(bufnr)
    report('Tool write_file: presenting diff for approval')
    local edit_mod = require('caramba.edit')
    vim.schedule(function()
      edit_mod.apply_patch_with_preview(bufnr, content)
    end)
    return { success = true, path = expanded_path, via = 'buffer_patch' }
  end,

  edit_file = function(args)
    local file_path = args.file_path
    local start_line = args.start_line
    local end_line = args.end_line
    local new_content = args.new_content

    if not file_path then
      return { error = "file_path is required" }
    end

    if not start_line or not end_line then
      return { error = "start_line and end_line are required" }
    end

    if not new_content then
      return { error = "new_content is required" }
    end

    local expanded_path = vim.fn.expand(file_path)

    if vim.fn.filereadable(expanded_path) == 0 then
      return { error = "File does not exist: " .. expanded_path }
    end

    report('Tool edit_file: opening ' .. expanded_path)
    logger.debug('tool.edit_file.open', { path = expanded_path, start_line = start_line, end_line = end_line })
    local bufnr = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf) == expanded_path then bufnr = buf break end
    end
    if not bufnr then bufnr = vim.fn.bufadd(expanded_path) end
    vim.fn.bufload(bufnr)

    report('Tool edit_file: applying edit lines ' .. tostring(start_line) .. '-' .. tostring(end_line))
    local edit_mod = require('caramba.edit')
    local cfg = require('caramba.config').get()
    local want_preview = (cfg.editing and cfg.editing.diff_preview) ~= false
    local success, error_msg = edit_mod.apply_edit(
      bufnr,
      start_line - 1,
      0,
      end_line - 1,
      -1,
      new_content,
      { one_based = false, preview = want_preview }
    )

    if not success then
      report('Tool edit_file: failed to apply edit')
      logger.error('tool.edit_file.failed', error_msg)
      return { error = "Edit failed: " .. (error_msg or "unknown error") }
    end

    report('Tool edit_file: saving buffer')
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("write")
    end)

    report('Tool edit_file: success')
    logger.info('tool.edit_file.success', { path = expanded_path })
    return {
      success = true,
      path = expanded_path,
      start_line = start_line,
      end_line = end_line,
      buffer_id = bufnr
    }
  end
}

-- Merge in agent tool modules (git/testing/etc.) without bloating this file
do
  local collector = require('caramba.agent_tools')
  local extra_tools, extra_fns = collector.collect_all()
  for _, t in ipairs(extra_tools or {}) do table.insert(M.available_tools, t) end
  for name, fn in pairs(extra_fns or {}) do M.tool_functions[name] = fn end
end

-- Execute a tool function
M.execute_tool = function(tool_function)
  local function_name = tool_function.name
  local arguments = tool_function.arguments

  -- Parse arguments if they're a string
  if type(arguments) == "string" then
    local ok, parsed = pcall(vim.json.decode, arguments)
    if ok then
      arguments = parsed
    else
      return { error = "Invalid JSON arguments: " .. arguments }
    end
  end

  -- Ensure arguments is a table for function execution
  if type(arguments) ~= "table" then
    arguments = {}
  end

  local tool_impl = M.tool_functions[function_name]
  if not tool_impl then
    return { error = "Unknown tool: " .. function_name }
  end

  local ok, result = pcall(tool_impl, arguments)
  if not ok then
    return { error = "Function execution failed: " .. tostring(result) }
  end

  return result
end

-- Create a chat session with tools
M.create_chat_session = function(initial_messages, tools)
  return {
    messages = initial_messages or {},
    tools = tools or {},

    -- Add a message to the conversation
    add_message = function(self, role, content, tool_calls, tool_call_id)
      local message = {
        role = role,
        content = content
      }

      if tool_calls then
        message.tool_calls = tool_calls
      end

      if tool_call_id then
        message.tool_call_id = tool_call_id
      end

      table.insert(self.messages, message)
    end,

    -- Send a message and handle tool calls
    send = function(self, user_message, on_chunk, on_finish)
      -- Add user message
      self:add_message("user", user_message)

      local function continue_conversation()
        local request_data = M._prepare_request(self.messages, self.tools, true)

        M._make_request(request_data, function(chunk, err)
          vim.schedule(function()
            if err then
              if on_finish then on_finish(nil, err) end
              return
            end

            if chunk and on_chunk then
              on_chunk(chunk)
            end
          end)
        end, function(final_message, err)
            vim.schedule(function()
                if err then
                    if on_finish then on_finish(nil, err) end
                    return
                end

                self:add_message("assistant", final_message.content, final_message.tool_calls)

                if final_message.tool_calls then
                    for _, tool_call in ipairs(final_message.tool_calls) do
                        -- Show tool usage feedback
                        if on_chunk then
                            on_chunk({
                                content = "\n\n🔧 Using tool: `" .. tool_call["function"].name .. "`...\n\n",
                                is_tool_feedback = true
                            })
                        end
                        -- Install step reporter for fine-grained activity
                        M._tool_reporter = function(text)
                          if on_chunk then
                            on_chunk({ content = "\n\n" .. text .. "\n\n", is_tool_feedback = true })
                          end
                        end
                        local result = M.execute_tool(tool_call["function"])
                        M._tool_reporter = nil
                        -- Push completion feedback
                        if on_chunk then
                            local status = result and not result.error and "✅" or "❌"
                            on_chunk({
                              content = string.format("%s Tool `%s` finished. %s\n\n", status, tool_call["function"].name, result.error and ("Error: " .. result.error) or ""),
                              is_tool_feedback = true
                            })
                        end
                        self:add_message("tool", vim.json.encode(result), nil, tool_call.id)
                    end
                    -- Continue conversation with tool results
                    continue_conversation()
                else
                    -- No more tool calls, return final response
                    if on_finish then on_finish(final_message.content, nil) end
                end
            end)
        end)
      end

      continue_conversation()
    end
  }
end

-- Prepare OpenAI request with tools
M._prepare_request = function(messages, tools, stream)
  local api_config = config.get().api.openai

  local body = {
    model = api_config.model,
    messages = messages,
    tools = tools,
    temperature = api_config.temperature,
    max_completion_tokens = api_config.max_tokens,
    stream = stream or false,
  }

  local url = api_config.endpoint or ((api_config.base_url or "https://api.openai.com/v1") .. "/chat/completions")

  return {
    url = url,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_config.api_key,
    },
    body = vim.json.encode(body),
  }
end

-- Make HTTP request with streaming
M._make_request = function(request_data, on_chunk, on_finish)
  local idle_timeout_ms = (config.get().performance and config.get().performance.request_idle_timeout_ms) or 120000

  -- Assign a request id for correlation in logs
  local request_id = tostring(os.time()) .. "_tools_" .. math.random(10000)

  -- Log request (redacted)
  local function sanitize_headers(h)
    local out = {}
    for k, v in pairs(h or {}) do
      if type(k) == "string" and k:lower() == "authorization" then
        out[k] = "Bearer ***"
      else
        out[k] = v
      end
    end
    return out
  end
  local ok_body, body_tbl = pcall(vim.json.decode, request_data.body)
  logger.info("OpenAI tools request", {
    id = request_id,
    url = request_data.url,
    headers = sanitize_headers(request_data.headers),
    body = ok_body and body_tbl or request_data.body,
  })

  local curl_args = {
    "-sS",
    "-N",
    "--no-buffer",
    request_data.url,
    "-X", "POST",
    "--max-time", "45",
  }

  for header, value in pairs(request_data.headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, header .. ": " .. value)
  end

  table.insert(curl_args, "-d")
  table.insert(curl_args, request_data.body)

  local full_response = ""
  local tool_calls = {}
  local stream_finished = false

  -- Idle timeout handling: kill the job if no chunks within idle_timeout_ms
  local job = nil
  local idle_timer = nil
  local function safe_timer_stop()
    if idle_timer then
      vim.schedule(function()
        pcall(vim.fn.timer_stop, idle_timer)
      end)
    end
  end
  local function safe_timer_start()
    vim.schedule(function()
      if idle_timer then pcall(vim.fn.timer_stop, idle_timer) end
      idle_timer = vim.fn.timer_start(idle_timeout_ms, function()
        vim.schedule(function()
          if job then job:shutdown() end
          if not stream_finished and on_finish then
            stream_finished = true
            on_finish(nil, "Idle timeout: no data received for " .. tostring(idle_timeout_ms) .. "ms")
          end
        end)
      end)
    end)
  end

  job = Job:new({
    command = "curl",
    args = curl_args,
    on_stdout = function(_, data)
        if data then
            safe_timer_start()
            local function handle_line(line)
                if line:match("^data: ") then
                    local json_str = line:sub(7)

                    if json_str == "[DONE]" then
                        stream_finished = true
                        safe_timer_stop()
                        local final_message = {
                            role = "assistant",
                            content = full_response,
                            tool_calls = #tool_calls > 0 and tool_calls or nil,
                        }
                        logger.info("OpenAI tools response", { id = request_id, content_preview = full_response:sub(1, 4000) })
                        if on_finish then vim.schedule(function() on_finish(final_message, nil) end) end
                        return
                    end

                    local ok, chunk = pcall(vim.json.decode, json_str)
                    if ok then
                        if chunk.choices and chunk.choices[1] and chunk.choices[1].delta then
                            local delta = chunk.choices[1].delta
                            local content = delta.content
                            if type(content) == "string" then
                                full_response = full_response .. content
                                if on_chunk then vim.schedule(function() on_chunk({ content = content }, nil) end) end
                            end

                            if delta.tool_calls then
                                for _, tool_call_delta in ipairs(delta.tool_calls) do
                                    local index = tool_call_delta.index + 1 -- Lua is 1-based
                                    if not tool_calls[index] then
                                        tool_calls[index] = {
                                            id = tool_call_delta.id,
                                            type = "function",
                                            ["function"] = { name = "", arguments = "" }
                                        }
                                    end

                                    if tool_call_delta.id then
                                        tool_calls[index].id = tool_call_delta.id
                                    end
                                    if tool_call_delta.type then
                                        tool_calls[index].type = tool_call_delta.type
                                    end
                                    if tool_call_delta["function"] then
                                        if tool_call_delta["function"].name then
                                            tool_calls[index]["function"].name = tool_calls[index]["function"].name .. tool_call_delta["function"].name
                                        end
                                        if tool_call_delta["function"].arguments then
                                            tool_calls[index]["function"].arguments = tool_calls[index]["function"].arguments .. tool_call_delta["function"].arguments
                                        end
                                    end
                                 end
                            end
                        end
                    end
                end
            end
            if type(data) == 'table' then
              for _, line in ipairs(data) do
                if line and line ~= '' then handle_line(line) end
              end
            elseif type(data) == 'string' then
              for line in string.gmatch(data, "[^\r\n]+") do
                handle_line(line)
              end
            end
        end
    end,
    on_stderr = function(_, data)
        if data and not stream_finished then
            -- Only abort on clear error signals; OpenAI may write keep-alives
            if data:match("error") or data:find("{", 1, true) then
              stream_finished = true
              safe_timer_stop()
              logger.error("OpenAI tools error", { id = request_id, stderr = data })
              if on_finish then vim.schedule(function() on_finish(nil, "Request error: " .. data) end) end
            end
        end
    end,
    on_exit = function(_, return_val)
        if not stream_finished then
            safe_timer_stop()
            if return_val ~= 0 then
                logger.error("OpenAI tools exit", { id = request_id, code = return_val })
                if on_finish then vim.schedule(function() on_finish(nil, "Request exited with code: " .. return_val) end) end
            else
                logger.info("OpenAI tools response", { id = request_id, content_preview = full_response:sub(1, 4000) })
                if on_finish then vim.schedule(function() on_finish({ role = "assistant", content = full_response }, nil) end) end
            end
        end
    end,
  })

  job:start()
end


return M