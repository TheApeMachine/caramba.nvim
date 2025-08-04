-- OpenAI Tools Implementation for Caramba
-- Implements proper OpenAI functions/tools API using existing HTTP infrastructure

local M = {}

-- Dependencies
local config = require('caramba.config')
local Job = require('plenary.job')

-- Available tools for the AI
M.available_tools = {
  {
    type = "function",
    ["function"] = {
      name = "get_open_buffers",
      description = "Get a list of currently open buffers with their file paths and content",
      parameters = {
        type = "object",
        properties = {}
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
            description = "The path to the file to read"
          }
        },
        required = {"file_path"}
      }
    }
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
            description = "The search query"
          },
          file_pattern = {
            type = "string",
            description = "Optional file pattern to limit search"
          }
        },
        required = {"query"}
      }
    }
  }
}

-- Tool implementations
M.tool_functions = {
  get_open_buffers = function(args)
    local buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name and name ~= "" then
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          table.insert(buffers, {
            path = name,
            content = table.concat(lines, "\n")
          })
        end
      end
    end
    return buffers
  end,

  read_file = function(args)
    local file_path = args.file_path
    if not file_path then
      return { error = "file_path is required" }
    end
    
    local ok, lines = pcall(vim.fn.readfile, file_path)
    if not ok then
      return { error = "Could not read file: " .. file_path }
    end
    
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
    
    -- Use ripgrep if available, otherwise fallback to grep
    local cmd = "rg"
    local cmd_args = {"-n", "--type-add", "code:*.{lua,py,js,ts,jsx,tsx,go,rs,java,c,cpp,h,hpp}", "-t", "code", query}
    
    -- Check if rg is available
    local rg_available = vim.fn.executable("rg") == 1
    if not rg_available then
      cmd = "grep"
      cmd_args = {"-rn", query, "."}
    end
    
    local results = {}
    local job = Job:new({
      command = cmd,
      args = cmd_args,
      on_exit = function(j, return_val)
        if return_val == 0 then
          local output = j:result()
          for _, line in ipairs(output) do
            table.insert(results, line)
          end
        end
      end,
    })
    
    job:sync(5000) -- 5 second timeout
    
    return {
      query = query,
      results = results
    }
  end
}

-- Execute a tool function
M.execute_tool = function(tool_call)
  local function_name = tool_call.name
  local arguments = tool_call.arguments
  
  -- Parse arguments if they're a string
  if type(arguments) == "string" then
    local ok, parsed = pcall(vim.json.decode, arguments)
    if ok then
      arguments = parsed
    else
      return { error = "Invalid JSON arguments: " .. arguments }
    end
  end
  
  local tool_function = M.tool_functions[function_name]
  if not tool_function then
    return { error = "Unknown function: " .. function_name }
  end
  
  local ok, result = pcall(tool_function, arguments)
  if not ok then
    return { error = "Function execution failed: " .. tostring(result) }
  end
  
  return result
end

-- Create a chat session with tools
M.create_chat_session = function(initial_messages)
  return {
    messages = initial_messages or {},
    
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
    send = function(self, user_message, callback)
      -- Add user message
      self:add_message("user", user_message)
      
      -- Continue conversation until no more tool calls
      local function continue_conversation()
        local request_data = M._prepare_request(self.messages)
        
        M._make_request(request_data, function(response, err)
          vim.schedule(function()
            if err then
              callback(nil, err)
              return
            end

            local message = response.choices[1].message

            -- Add assistant message
            self:add_message("assistant", message.content, message.tool_calls)

            -- Check if there are tool calls to execute
            if message.tool_calls then
              -- Execute each tool call
              for _, tool_call in ipairs(message.tool_calls) do
                local result = M.execute_tool(tool_call["function"])

                -- Add tool result message
                self:add_message("tool", vim.json.encode(result), nil, tool_call.id)
              end

              -- Continue conversation with tool results
              continue_conversation()
            else
              -- No more tool calls, return final response
              callback(message.content, nil)
            end
          end)
        end)
      end
      
      continue_conversation()
    end
  }
end

-- Prepare OpenAI request with tools
M._prepare_request = function(messages)
  local api_config = config.get().api.openai
  
  local body = {
    model = api_config.model,
    messages = messages,
    tools = M.available_tools,
    temperature = api_config.temperature,
    max_completion_tokens = api_config.max_tokens,
  }
  
  return {
    url = api_config.endpoint,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_config.api_key,
    },
    body = vim.json.encode(body),
  }
end

-- Make HTTP request
M._make_request = function(request_data, callback)
  local curl_args = {
    "-sS",
    request_data.url,
    "-X", "POST",
    "--max-time", "30",
  }
  
  for header, value in pairs(request_data.headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, header .. ": " .. value)
  end
  
  table.insert(curl_args, "-d")
  table.insert(curl_args, request_data.body)
  
  local job = Job:new({
    command = "curl",
    args = curl_args,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          callback(nil, "Request failed with code: " .. tostring(return_val))
          return
        end

        local response_text = table.concat(j:result(), "\n")
        local ok, response = pcall(vim.json.decode, response_text)

        if not ok then
          callback(nil, "Failed to parse response: " .. response_text)
          return
        end

        if response.error then
          callback(nil, response.error.message or "API error")
          return
        end

        callback(response, nil)
      end)
    end,
  })
  
  job:start()
end

return M
