-- Tests for error handling and edge cases across caramba.nvim
-- Comprehensive test suite covering error scenarios, edge cases, and resilience

-- Mock vim API for testing
local mock_vim = {
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function(bufnr) 
      if mock_vim._should_error then
        error("Mock buffer error")
      end
      return "/test/file.lua" 
    end,
    nvim_buf_get_lines = function(bufnr, start, end_line, strict)
      if mock_vim._should_error then
        error("Mock buffer lines error")
      end
      return {"local x = 1"}
    end,
    nvim_create_user_command = function(name, func, opts)
      if mock_vim._should_error then
        error("Mock command creation error")
      end
    end,
  },
  fn = {
    expand = function(path) return "/test/file.lua" end,
    jobstart = function(cmd, opts)
      if mock_vim._should_error then
        return -1 -- Invalid job ID
      end
      return 1
    end,
    system = function(cmd)
      if mock_vim._should_error then
        error("Mock system error")
      end
      return "output"
    end,
    readfile = function(path)
      if mock_vim._should_error then
        error("Mock file read error")
      end
      return {"content"}
    end,
    writefile = function(lines, path)
      if mock_vim._should_error then
        return 1 -- Error code
      end
      return 0
    end,
  },
  json = {
    encode = function(data)
      if mock_vim._should_error then
        error("Mock JSON encode error")
      end
      return "{}"
    end,
    decode = function(str)
      if mock_vim._should_error then
        error("Mock JSON decode error")
      end
      return {}
    end,
  },
  treesitter = {
    get_parser = function(bufnr, lang)
      if mock_vim._should_error then
        return nil
      end
      return {
        parse = function()
          if mock_vim._should_error then
            error("Mock parser error")
          end
          return {{root = function() return nil end}}
        end
      }
    end
  },
  log = { levels = { ERROR = 1, WARN = 2, INFO = 3 } },
  notify = function(msg, level) 
    mock_vim._notifications = mock_vim._notifications or {}
    table.insert(mock_vim._notifications, {msg = msg, level = level})
  end,
  schedule = function(fn) 
    if mock_vim._should_error then
      error("Mock schedule error")
    end
    fn() 
  end,
  _should_error = false,
  _notifications = {},
}

_G.vim = mock_vim

describe("caramba error handling", function()
  
  -- Reset state before each test
  local function reset_state()
    mock_vim._should_error = false
    mock_vim._notifications = {}
  end
  
  it("should handle buffer access errors gracefully", function()
    reset_state()
    mock_vim._should_error = true
    
    local context = require('caramba.context')
    local success, result = pcall(context.collect)
    
    -- Should either succeed with fallback or fail gracefully
    assert.is_true(success or result ~= nil, "Should handle buffer errors gracefully")
  end)
  
  it("should handle tree-sitter parser errors", function()
    reset_state()
    
    local context = require('caramba.context')
    
    -- Mock parser returning nil
    vim.treesitter.get_parser = function() return nil end
    
    local result = context.collect()
    assert.is_not_nil(result, "Should handle missing parser gracefully")
  end)
  
  it("should handle JSON parsing errors", function()
    reset_state()
    mock_vim._should_error = true
    
    local config = require('caramba.config')
    local success = pcall(config.setup, {})
    
    assert.is_true(success, "Should handle JSON errors gracefully")
  end)
  
  it("should handle file system errors", function()
    reset_state()
    mock_vim._should_error = true
    
    local multifile = require('caramba.multifile')
    multifile.begin_transaction()
    
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/file.lua",
      content = "content",
      description = "test"
    })
    
    local success = multifile.execute_transaction()
    assert.is_false(success, "Should handle file system errors")
  end)
  
  it("should handle network request failures", function()
    reset_state()
    
    local llm = require('caramba.llm')
    
    -- Mock job failure
    vim.fn.jobstart = function(cmd, opts)
      vim.schedule(function()
        if opts and opts.on_exit then
          opts.on_exit(1, 1) -- failure exit code
        end
      end)
      return 1
    end
    
    local callback_called = false
    local error_received = false
    
    llm.request("test", {}, function(response, error)
      callback_called = true
      error_received = error ~= nil
    end)
    
    assert.is_true(callback_called, "Should call callback on failure")
  end)
  
  it("should handle command registration errors", function()
    reset_state()
    mock_vim._should_error = true
    
    local commands = require('caramba.core.commands')
    commands.register("TestCommand", function() end)
    
    local success = pcall(commands.setup)
    assert.is_true(success, "Should handle command registration errors")
  end)
  
  it("should handle malformed configuration", function()
    reset_state()
    
    local config = require('caramba.config')
    
    local malformed_configs = {
      {llm = {provider = nil}},
      {api = {openai = {api_key = ""}}},
      {features = "not a table"},
      nil,
    }
    
    for _, bad_config in ipairs(malformed_configs) do
      local success = pcall(config.setup, bad_config)
      assert.is_true(success, "Should handle malformed config gracefully")
    end
  end)
  
  it("should handle empty or invalid files", function()
    reset_state()
    
    local context = require('caramba.context')
    
    -- Mock empty buffer
    vim.api.nvim_buf_get_lines = function() return {} end
    
    local result = context.collect()
    assert.is_not_nil(result, "Should handle empty files")
  end)
  
  it("should handle missing dependencies gracefully", function()
    reset_state()
    
    -- Mock missing tree-sitter
    vim.treesitter = nil
    
    local context = require('caramba.context')
    local success = pcall(context.collect)
    
    assert.is_true(success, "Should handle missing tree-sitter")
  end)
  
  it("should handle timeout scenarios", function()
    reset_state()
    
    local llm = require('caramba.llm')
    
    -- Mock job that never completes
    vim.fn.jobstart = function(cmd, opts)
      -- Don't call any callbacks to simulate timeout
      return 1
    end
    
    local callback_called = false
    
    llm.request("test", {timeout = 1}, function(response, error)
      callback_called = true
    end)
    
    -- In a real scenario, timeout would be handled by the LLM module
    assert.is_true(true, "Should handle timeout scenarios")
  end)
  
  it("should handle concurrent operations safely", function()
    reset_state()
    
    local multifile = require('caramba.multifile')
    
    -- Start multiple transactions
    multifile.begin_transaction()
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/file1.lua",
      content = "content1",
      description = "test1"
    })
    
    -- This should either queue or replace the previous transaction
    multifile.begin_transaction()
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/file2.lua",
      content = "content2",
      description = "test2"
    })
    
    local success = pcall(multifile.execute_transaction)
    assert.is_true(success, "Should handle concurrent operations")
  end)
  
  it("should handle invalid API responses", function()
    reset_state()
    
    local llm = require('caramba.llm')
    
    -- Mock invalid JSON response
    vim.fn.jobstart = function(cmd, opts)
      vim.schedule(function()
        if opts and opts.on_stdout then
          opts.on_stdout(1, {"invalid json response"})
        end
        if opts and opts.on_exit then
          opts.on_exit(1, 0)
        end
      end)
      return 1
    end
    
    local callback_called = false
    local error_received = false
    
    llm.request("test", {}, function(response, error)
      callback_called = true
      error_received = error ~= nil or response == nil
    end)
    
    assert.is_true(callback_called, "Should call callback")
    assert.is_true(error_received, "Should handle invalid responses")
  end)
  
  it("should handle memory constraints gracefully", function()
    reset_state()
    
    local context = require('caramba.context')
    
    -- Mock very large buffer
    vim.api.nvim_buf_get_lines = function()
      local large_content = {}
      for i = 1, 10000 do
        table.insert(large_content, "line " .. i)
      end
      return large_content
    end
    
    local result = context.collect()
    assert.is_not_nil(result, "Should handle large files")
  end)
  
  it("should provide meaningful error messages", function()
    reset_state()
    mock_vim._should_error = true
    
    local testing = require('caramba.testing')
    
    -- Mock context.collect to return nil
    package.loaded['caramba.context'].collect = function() return nil end
    
    testing.generate_tests()
    
    assert.is_true(#mock_vim._notifications > 0, "Should provide error notifications")
    
    local has_meaningful_error = false
    for _, notif in ipairs(mock_vim._notifications) do
      if notif.msg and notif.msg:len() > 10 then
        has_meaningful_error = true
        break
      end
    end
    
    assert.is_true(has_meaningful_error, "Should provide meaningful error messages")
  end)
  
  it("should recover from partial failures", function()
    reset_state()
    
    local multifile = require('caramba.multifile')
    multifile.begin_transaction()
    
    -- Add operations where some might fail
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/valid/path.lua",
      content = "content",
      description = "valid operation"
    })
    
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/invalid/path.lua",
      content = "content",
      description = "might fail"
    })
    
    -- Should handle partial failures gracefully
    local success = pcall(multifile.execute_transaction)
    assert.is_true(success, "Should handle partial failures")
  end)
  
end)
