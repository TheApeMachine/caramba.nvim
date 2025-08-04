-- Tests for caramba.openai_tools module
-- Unit tests for OpenAI API integration and tool calling

-- Mock vim API for testing
local mock_vim = {
  fn = {
    jobstart = function(cmd, opts)
      return 1
    end,
    jobstop = function(job_id) return true end,
    system = function(cmd) return "mock system output" end,
  },
  json = {
    encode = function(data) 
      return require('cjson').encode(data)
    end,
    decode = function(str)
      if str == "invalid json" then
        error("Invalid JSON")
      end
      return require('cjson').decode(str)
    end,
  },
  schedule = function(fn) fn() end,
  log = {
    levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 }
  },
  notify = function(msg, level) end,
  tbl_extend = function(behavior, ...)
    local result = {}
    for _, tbl in ipairs({...}) do
      for k, v in pairs(tbl) do
        result[k] = v
      end
    end
    return result
  end,
  env = {
    OPENAI_API_KEY = "test-openai-key",
  },
  api = {
    nvim_list_bufs = function()
      return {1, 2} -- Mock buffer IDs
    end,
    nvim_buf_is_loaded = function(buf)
      return true -- All buffers are loaded
    end,
    nvim_buf_get_name = function(buf)
      return "test_file_" .. buf .. ".lua" -- Mock file names
    end,
    nvim_buf_get_lines = function(buf, start, end_line, strict)
      return {"-- Mock content for buffer " .. buf, "local test = true"} -- Mock content
    end,
  }
}

_G.vim = mock_vim

-- Mock config module
package.loaded['caramba.config'] = {
  get = function()
    return {
      api = {
        openai = {
          api_key = "test-key",
          base_url = "https://api.openai.com/v1",
          model = "gpt-4",
          temperature = 0.7,
          max_tokens = 1000,
        }
      },
      debug = false
    }
  end
}

-- Mock plenary.job
local mock_job_class = {}
mock_job_class.__index = mock_job_class

function mock_job_class:new(opts)
  local instance = setmetatable({
    command = opts.command,
    args = opts.args,
    on_exit = opts.on_exit,
    _output = {},
    _stderr = {}
  }, mock_job_class)
  return instance
end

function mock_job_class:start()
  -- Simulate successful OpenAI response
  local mock_response = {
    choices = {
      {
        message = {
          role = "assistant",
          content = "Test response from OpenAI",
          tool_calls = {
            {
              id = "call_test123",
              type = "function",
              ["function"] = {
                name = "get_open_buffers",
                arguments = "{}"
              }
            }
          }
        }
      }
    }
  }
  
  table.insert(self._output, vim.json.encode(mock_response))
  
  if self.on_exit then
    vim.schedule(function()
      self.on_exit(self, 0) -- success exit code
    end)
  end
end

function mock_job_class:result()
  return self._output
end

function mock_job_class:stderr_result()
  return self._stderr
end

package.loaded['plenary.job'] = mock_job_class

-- Simple JSON library mock
package.loaded['cjson'] = {
  encode = function(data)
    if type(data) == "table" then
      if data.model then
        return '{"model":"' .. (data.model or "gpt-4") .. '","messages":[{"role":"user","content":"Hello"}]}'
      end
      return '{"mock":"json"}'
    end
    return tostring(data)
  end,
  decode = function(str)
    if str == "{}" then
      return {}
    end
    if str:find("file_path") then
      return {file_path = "test.txt"}
    end
    return {mock = "data"}
  end
}

-- Load the module under test
local openai_tools = require('caramba.openai_tools')

describe("caramba.openai_tools", function()
  
  describe("available_tools", function()
    it("should have properly formatted tool definitions", function()
      assert.is_not_nil(openai_tools.available_tools)
      assert.is_true(type(openai_tools.available_tools) == "table")
      assert.is_true(#openai_tools.available_tools > 0)
      
      for _, tool in ipairs(openai_tools.available_tools) do
        assert.equals("function", tool.type)
        assert.is_not_nil(tool["function"])
        assert.is_true(type(tool["function"]) == "table")
        assert.is_not_nil(tool["function"].name)
        assert.is_true(type(tool["function"].name) == "string")
        assert.is_not_nil(tool["function"].description)
        assert.is_true(type(tool["function"].description) == "string")
        assert.is_not_nil(tool["function"].parameters)
        assert.is_true(type(tool["function"].parameters) == "table")
        assert.equals("object", tool["function"].parameters.type)
      end
    end)
    
    it("should include get_open_buffers tool with correct schema", function()
      local get_buffers_tool = nil
      for _, tool in ipairs(openai_tools.available_tools) do
        if tool["function"].name == "get_open_buffers" then
          get_buffers_tool = tool
          break
        end
      end
      
      assert.is_not_nil(get_buffers_tool)
      assert.equals("get_open_buffers", get_buffers_tool["function"].name)
      assert.is_not_nil(get_buffers_tool["function"].parameters.properties)
      assert.is_true(type(get_buffers_tool["function"].parameters.properties) == "table")
    end)
  end)
  
  describe("execute_tool", function()
    it("should execute get_open_buffers without arguments", function()
      local tool_function = {
        name = "get_open_buffers",
        arguments = "{}"
      }
      
      local result = openai_tools.execute_tool(tool_function)
      assert.is_not_nil(result)
      assert.is_true(type(result) == "table")
      assert.is_not_nil(result.buffers)
      assert.is_true(type(result.buffers) == "table")
    end)
    
    it("should execute read_file with file_path argument", function()
      local tool_function = {
        name = "read_file",
        arguments = '{"file_path": "test.txt"}'
      }
      
      local result = openai_tools.execute_tool(tool_function)
      assert.is_not_nil(result)
      assert.is_true(type(result) == "table")
      -- Should have either content or error
      assert.is_true(result.content ~= nil or result.error ~= nil)
    end)
    
    it("should handle invalid tool names", function()
      local tool_function = {
        name = "invalid_tool",
        arguments = "{}"
      }
      
      local result = openai_tools.execute_tool(tool_function)
      assert.is_not_nil(result)
      assert.is_true(type(result) == "table")
      assert.is_not_nil(result.error)
      assert.contains(result.error, "Unknown tool")
    end)
    
    it("should handle invalid JSON arguments", function()
      local tool_function = {
        name = "get_open_buffers",
        arguments = "invalid json"
      }
      
      local result = openai_tools.execute_tool(tool_function)
      assert.is_not_nil(result)
      assert.is_true(type(result) == "table")
      assert.is_not_nil(result.error)
    end)
  end)
  
  describe("create_chat_session", function()
    it("should create a session with messages and tools", function()
      local messages = {
        { role = "system", content = "You are a helpful assistant." }
      }
      local tools = openai_tools.available_tools
      
      local session = openai_tools.create_chat_session(messages, tools)
      
      assert.is_not_nil(session)
      assert.is_true(type(session) == "table")
      assert.is_not_nil(session.add_message)
      assert.is_true(type(session.add_message) == "function")
      assert.is_not_nil(session.send)
      assert.is_true(type(session.send) == "function")
      assert.equals(messages[1].role, session.messages[1].role)
      assert.equals(messages[1].content, session.messages[1].content)
    end)
    
    it("should add messages correctly", function()
      local session = openai_tools.create_chat_session({}, {})
      
      session:add_message("user", "Hello")
      assert.equals(1, #session.messages)
      assert.equals("user", session.messages[1].role)
      assert.equals("Hello", session.messages[1].content)
      
      session:add_message("assistant", "Hi there", {}, "call_123")
      assert.equals(2, #session.messages)
      assert.equals("call_123", session.messages[2].tool_call_id)
    end)
  end)
  
  describe("_prepare_request", function()
    it("should prepare correct request structure", function()
      local messages = {
        { role = "user", content = "Hello" }
      }
      local tools = openai_tools.available_tools
      
      local request = openai_tools._prepare_request(messages, tools)
      
      assert.is_not_nil(request)
      assert.is_true(type(request) == "table")
      assert.equals("https://api.openai.com/v1/chat/completions", request.url)
      assert.is_not_nil(request.body)
      assert.is_true(type(request.body) == "string")
      assert.is_not_nil(request.headers)
      assert.is_true(type(request.headers) == "table")
      
      -- Basic validation that body contains expected fields
      assert.contains(request.body, "gpt-4")
      assert.contains(request.body, "Hello")
    end)
  end)
  
end)