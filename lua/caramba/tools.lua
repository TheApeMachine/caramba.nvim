-- AI Tools Module
-- Provides tool-calling capabilities for the AI assistant

local M = {}

local llm = require('caramba.llm')
local websearch = require('caramba.websearch')
local config = require('caramba.config')

-- Available tools registry
M.tools = {
  web_search = {
    name = "web_search",
    description = "Search the web for current information",
    parameters = {
      query = {
        type = "string",
        description = "The search query",
        required = true,
      },
      limit = {
        type = "number",
        description = "Number of results to return (default: 3)",
        required = false,
      },
    },
    execute = function(params, callback)
      websearch.search(params.query, {
        limit = params.limit or 3,
        callback = function(results, err)
          if err then
            callback(nil, err)
          else
            callback(results, nil)
          end
        end,
      })
    end,
  },
  
  fetch_url = {
    name = "fetch_url",
    description = "Fetch and extract text content from a URL",
    parameters = {
      url = {
        type = "string",
        description = "The URL to fetch",
        required = true,
      },
    },
    execute = function(params, callback)
      websearch.fetch_url(params.url, callback)
    end,
  },
  
  read_file = {
    name = "read_file",
    description = "Read contents of a local file",
    parameters = {
      path = {
        type = "string",
        description = "Path to the file",
        required = true,
      },
    },
    execute = function(params, callback)
      local ok, content = pcall(vim.fn.readfile, vim.fn.expand(params.path))
      if ok then
        callback(table.concat(content, "\n"), nil)
      else
        callback(nil, "Failed to read file: " .. params.path)
      end
    end,
  },
  
  list_files = {
    name = "list_files",
    description = "List files in a directory",
    parameters = {
      path = {
        type = "string",
        description = "Directory path (default: current directory)",
        required = false,
      },
      pattern = {
        type = "string",
        description = "File pattern to match (e.g., '*.lua')",
        required = false,
      },
    },
    execute = function(params, callback)
      local path = params.path or "."
      local pattern = params.pattern or "*"
      
      local cmd = string.format("find %s -name '%s' -type f | head -50",
        vim.fn.shellescape(path), pattern)
      
      local result = vim.fn.system(cmd)
      callback(result, nil)
    end,
  },
}

-- Build tool descriptions for the AI
M.get_tool_descriptions = function()
  local descriptions = {}
  
  for name, tool in pairs(M.tools) do
    local params_desc = {}
    for param_name, param_info in pairs(tool.parameters) do
      table.insert(params_desc, string.format(
        "- %s (%s%s): %s",
        param_name,
        param_info.type,
        param_info.required and ", required" or "",
        param_info.description
      ))
    end
    
    table.insert(descriptions, string.format(
      "Tool: %s\nDescription: %s\nParameters:\n%s",
      tool.name,
      tool.description,
      table.concat(params_desc, "\n")
    ))
  end
  
  return table.concat(descriptions, "\n\n")
end

-- Parse tool calls from AI response
M.parse_tool_calls = function(response)
  local tool_calls = {}
  
  -- Look for tool call patterns
  -- Format: <tool>function_name(params)</tool>
  for tool_call in response:gmatch("<tool>(.-)</tool>") do
    local name, params_str = tool_call:match("([%w_]+)%((.*)%)")
    if name and params_str then
      -- Try to parse parameters as JSON
      local ok, params = pcall(vim.json.decode, "{" .. params_str .. "}")
      if ok then
        table.insert(tool_calls, {
          name = name,
          parameters = params,
        })
      else
        -- Try simple key=value parsing
        local params = {}
        for key, value in params_str:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
          params[key] = value
        end
        if next(params) then
          table.insert(tool_calls, {
            name = name,
            parameters = params,
          })
        end
      end
    end
  end
  
  return tool_calls
end

-- Execute tool calls
M.execute_tool_calls = function(tool_calls, callback)
  local results = {}
  local pending = #tool_calls
  
  if pending == 0 then
    callback({})
    return
  end
  
  for i, call in ipairs(tool_calls) do
    local tool = M.tools[call.name]
    if tool then
      tool.execute(call.parameters, function(result, err)
        results[i] = {
          tool = call.name,
          parameters = call.parameters,
          result = result,
          error = err,
        }
        
        pending = pending - 1
        if pending == 0 then
          callback(results)
        end
      end)
    else
      results[i] = {
        tool = call.name,
        error = "Unknown tool: " .. call.name,
      }
      pending = pending - 1
      if pending == 0 then
        callback(results)
      end
    end
  end
end

-- Request with tool support
M.request_with_tools = function(prompt, opts, callback)
  opts = opts or {}
  
  -- Build system prompt with tool descriptions
  local system_prompt = [[
You are an AI assistant with access to the following tools:

]] .. M.get_tool_descriptions() .. [[

When you need to use a tool, use this format:
<tool>tool_name(parameter1="value1", parameter2="value2")</tool>

You can use multiple tools in your response. After using tools, provide your analysis or answer based on the tool results.
]]

  -- Initial request
  local messages = {
    { role = "system", content = system_prompt },
    { role = "user", content = prompt },
  }
  
  llm.request(messages, opts, function(response)
    if not response then
      callback(nil, "Failed to get AI response")
      return
    end
    
    -- Check for tool calls
    local tool_calls = M.parse_tool_calls(response)
    
    if #tool_calls == 0 then
      -- No tools used, return response directly
      callback(response, nil)
      return
    end
    
    -- Execute tools
    M.execute_tool_calls(tool_calls, function(results)
      -- Build follow-up prompt with results
      local follow_up = "Tool results:\n\n"
      
      for _, result in ipairs(results) do
        if result then
          follow_up = follow_up .. string.format(
            "Tool: %s\nParameters: %s\n%s\n\n",
            result.tool,
            vim.inspect(result.parameters),
            result.error and ("Error: " .. result.error) or ("Result: " .. vim.inspect(result.result))
          )
        end
      end
      
      -- Add tool results to conversation
      table.insert(messages, { role = "assistant", content = response })
      table.insert(messages, { role = "user", content = follow_up .. "\nPlease provide your final response based on these results." })
      
      -- Get final response
      llm.request(messages, opts, callback)
    end)
  end)
end

-- Interactive tool-assisted query
M.query_with_tools = function(query)
  vim.notify("Processing query with tools...", vim.log.levels.INFO)
  
  M.request_with_tools(query, { temperature = 0.3 }, function(response, err)
    if err then
      vim.notify("Error: " .. err, vim.log.levels.ERROR)
      return
    end
    
    vim.schedule(function()
      -- Show response in a buffer
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
      
      vim.cmd('split')
      vim.api.nvim_set_current_buf(buf)
    end)
  end)
end

return M 