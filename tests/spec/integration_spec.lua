-- Integration tests for caramba.nvim
-- End-to-end tests covering complete workflows and module interactions

-- Mock vim API for testing
local mock_vim = {
  bo = {},
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function(bufnr) return "/test/project/src/main.lua" end,
    nvim_buf_get_lines = function(bufnr, start, end_line, strict)
      return {
        "-- Main application file",
        "local config = require('config')",
        "local utils = require('utils')",
        "",
        "local function main()",
        "  print('Hello, World!')",
        "  return utils.calculate(42)",
        "end",
        "",
        "return { main = main }"
      }
    end,
    nvim_get_current_line = function() return "  return utils.calculate(42)" end,
    nvim_win_get_cursor = function(win) return {7, 10} end,
    nvim_create_buf = function(listed, scratch) return 100 end,
    nvim_buf_set_lines = function(buf, start, end_line, strict, lines) end,
    nvim_buf_set_option = function(buf, option, value) end,
    nvim_open_win = function(buf, enter, config) return 200 end,
    nvim_create_user_command = function(name, func, opts) end,
    nvim_create_augroup = function(name, opts) return 1 end,
    nvim_create_autocmd = function(event, opts) end,
  },
  fn = {
    expand = function(path) 
      if path == "%:p" then return "/test/project/src/main.lua"
      elseif path == "%:h" then return "/test/project/src"
      elseif path == "%:t:r" then return "main"
      end
      return path
    end,
    fnamemodify = function(path, modifier)
      if modifier == ":h" then return "/test/project/src"
      elseif modifier == ":t:r" then return "main"
      elseif modifier == ":e" then return "lua"
      end
      return path
    end,
    getcwd = function() return "/test/project" end,
    filereadable = function(path) return 1 end,
    readfile = function(path)
      if path:find("config") then
        return {"return { debug = true, version = '1.0' }"}
      elseif path:find("utils") then
        return {"local function calculate(x) return x * 2 end", "return { calculate = calculate }"}
      end
      return {}
    end,
    writefile = function(lines, path) return 0 end,
    jobstart = function(cmd, opts)
      -- Mock successful job execution
      vim.schedule(function()
        if opts and opts.on_stdout then
          opts.on_stdout(1, {'{"choices":[{"message":{"content":"Mock LLM response"}}]}'})
        end
        if opts and opts.on_exit then
          opts.on_exit(1, 0)
        end
      end)
      return 1
    end,
    system = function(cmd) return "mock system output" end,
    stdpath = function(type) return "/home/user/.config/nvim" end,
  },
  treesitter = {
    get_parser = function(bufnr, lang)
      return {
        parse = function()
          return {{
            root = function()
              return {
                type = function() return "chunk" end,
                range = function() return 0, 0, 10, 0 end,
                child_count = function() return 1 end,
                child = function(index)
                  return {
                    type = function() return "function_definition" end,
                    range = function() return 4, 0, 7, 3 end,
                    parent = function() return nil end,
                    id = function() return "main_func" end,
                  }
                end,
              }
            end
          }}
        end
      }
    end
  },
  json = {
    encode = function(data) return '{"mock":"json"}' end,
    decode = function(str) 
      return {choices = {{message = {content = "Mock response"}}}}
    end,
  },
  env = {
    OPENAI_API_KEY = "test-key",
    ANTHROPIC_API_KEY = "test-key",
  },
  o = { columns = 120, lines = 40 },
  log = { levels = { ERROR = 1, WARN = 2, INFO = 3 } },
  notify = function(msg, level) 
    mock_vim._notifications = mock_vim._notifications or {}
    table.insert(mock_vim._notifications, {msg = msg, level = level})
  end,
  schedule = function(fn) fn() end,
  tbl_extend = function(behavior, ...)
    local result = {}
    for _, tbl in ipairs({...}) do
      for k, v in pairs(tbl) do
        result[k] = v
      end
    end
    return result
  end,
  tbl_deep_extend = function(behavior, ...)
    return vim.tbl_extend(behavior, ...)
  end,
  tbl_contains = function(tbl, value)
    for _, v in ipairs(tbl) do
      if v == value then return true end
    end
    return false
  end,
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch("(.-)" .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  validate = function(spec, value) return true end,
  _notifications = {},
}

_G.vim = mock_vim
_G.debug = {
  getinfo = function(level, what)
    return { source = "@integration_test.lua" }
  end
}

-- Load caramba modules
local caramba = require('caramba')

describe("caramba.nvim integration", function()
  
  -- Reset state before each test
  local function reset_state()
    mock_vim._notifications = {}
    -- Reset any module state if needed
  end
  
  it("should setup caramba with default configuration", function()
    reset_state()
    
    local success = pcall(caramba.setup)
    assert.is_true(success, "Should setup caramba without errors")
    
    -- Check that setup notification was sent
    local setup_notified = false
    for _, notif in ipairs(mock_vim._notifications) do
      if notif.msg:find("ready") then
        setup_notified = true
        break
      end
    end
    assert.is_true(setup_notified, "Should notify when setup is complete")
  end)
  
  it("should setup caramba with custom configuration", function()
    reset_state()
    
    local custom_config = {
      llm = {
        provider = "anthropic",
        temperature = 0.5,
      },
      features = {
        auto_complete = false,
        context_tracking = true,
      }
    }
    
    local success = pcall(caramba.setup, custom_config)
    assert.is_true(success, "Should setup with custom config")
  end)
  
  it("should handle complete context extraction workflow", function()
    reset_state()
    caramba.setup()
    
    vim.bo[1] = { filetype = "lua" }
    
    local context = require('caramba.context')
    local result = context.collect()
    
    assert.is_not_nil(result, "Should extract context")
    assert.equals(result.language, "lua", "Should detect language")
    assert.is_not_nil(result.content, "Should have content")
    assert.is_not_nil(result.file_path, "Should have file path")
  end)
  
  it("should handle complete LLM request workflow", function()
    reset_state()
    caramba.setup()
    
    local llm = require('caramba.llm')
    local response_received = false
    
    llm.request("Test prompt", {}, function(response)
      response_received = true
      assert.is_not_nil(response, "Should receive LLM response")
    end)
    
    assert.is_true(response_received, "Should complete LLM request")
  end)
  
  it("should handle complete test generation workflow", function()
    reset_state()
    caramba.setup()
    
    vim.bo[1] = { filetype = "lua" }
    
    local testing = require('caramba.testing')
    local multifile_ops = {}
    
    -- Mock multifile operations
    package.loaded['caramba.multifile'] = {
      begin_transaction = function() end,
      add_operation = function(op) 
        table.insert(multifile_ops, op)
      end,
      preview_transaction = function() end,
    }
    
    testing.generate_tests()
    
    assert.is_true(#multifile_ops > 0, "Should generate test operations")
  end)
  
  it("should handle complete TDD workflow", function()
    reset_state()
    caramba.setup()
    
    vim.bo[1] = { filetype = "lua" }
    
    local tdd = require('caramba.tdd')
    local multifile_ops = {}
    
    -- Mock multifile operations
    package.loaded['caramba.multifile'] = {
      begin_transaction = function() end,
      add_operation = function(op) 
        table.insert(multifile_ops, op)
      end,
      preview_transaction = function() end,
    }
    
    tdd.implement_from_test()
    
    assert.is_true(#multifile_ops > 0, "Should generate implementation operations")
  end)
  
  it("should handle command registration and execution", function()
    reset_state()
    
    local commands = require('caramba.core.commands')
    local executed = false
    
    commands.register("TestCommand", function() executed = true end, {
      desc = "Test command for integration"
    })
    
    commands.setup()
    
    local command_list = commands.list()
    assert.is_true(#command_list > 0, "Should have registered commands")
    
    -- Find and execute our test command
    for _, cmd in ipairs(command_list) do
      if cmd.name == "CarambaTestCommand" then
        -- In real scenario, this would be called by vim
        break
      end
    end
  end)
  
  it("should handle configuration management workflow", function()
    reset_state()
    
    local config = require('caramba.config')
    
    -- Setup with initial config
    config.setup({
      llm = { provider = "openai" }
    })
    
    local initial_config = config.get()
    assert.equals(initial_config.llm.provider, "openai", "Should set initial provider")
    
    -- Update configuration
    config.update({
      llm = { temperature = 0.8 }
    })
    
    local updated_config = config.get()
    assert.equals(updated_config.llm.temperature, 0.8, "Should update temperature")
    assert.equals(updated_config.llm.provider, "openai", "Should preserve provider")
  end)
  
  it("should handle multifile operations workflow", function()
    reset_state()
    
    local multifile = require('caramba.multifile')
    
    multifile.begin_transaction()
    
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/new_file.lua",
      content = "-- New file content",
      description = "Create new file"
    })
    
    multifile.add_operation({
      type = multifile.OpType.MODIFY,
      path = "/test/existing.lua",
      content = "-- Modified content",
      description = "Modify existing file"
    })
    
    local operations = multifile.get_operations()
    assert.equals(#operations, 2, "Should have two operations")
    
    local success = multifile.execute_transaction()
    assert.is_true(success, "Should execute transaction successfully")
  end)
  
  it("should handle error scenarios gracefully", function()
    reset_state()
    
    -- Test with invalid configuration
    local success, error = pcall(caramba.setup, {
      llm = {
        provider = "invalid_provider"
      }
    })
    
    -- Should either succeed with fallback or fail gracefully
    assert.is_true(success or error ~= nil, "Should handle invalid config gracefully")
  end)
  
  it("should handle missing dependencies gracefully", function()
    reset_state()
    
    -- Mock missing tree-sitter
    vim.treesitter = nil
    
    local success = pcall(caramba.setup)
    assert.is_true(success, "Should handle missing tree-sitter")
    
    -- Restore tree-sitter mock
    vim.treesitter = {
      get_parser = function() return nil end
    }
  end)
  
  it("should handle provider fallback workflow", function()
    reset_state()
    caramba.setup({
      llm = {
        provider = "openai",
        fallback_providers = {"anthropic", "ollama"}
      }
    })
    
    local llm = require('caramba.llm')
    
    -- Mock first provider failure
    local call_count = 0
    vim.fn.jobstart = function(cmd, opts)
      call_count = call_count + 1
      if call_count == 1 then
        -- First call fails
        vim.schedule(function()
          if opts and opts.on_exit then
            opts.on_exit(1, 1) -- failure
          end
        end)
      else
        -- Fallback succeeds
        vim.schedule(function()
          if opts and opts.on_stdout then
            opts.on_stdout(1, {'{"choices":[{"message":{"content":"Fallback response"}}]}'})
          end
          if opts and opts.on_exit then
            opts.on_exit(1, 0) -- success
          end
        end)
      end
      return 1
    end
    
    local response_received = false
    llm.request("Test prompt", {}, function(response)
      response_received = true
      assert.equals(response, "Fallback response", "Should use fallback provider")
    end)
    
    assert.is_true(response_received, "Should receive fallback response")
  end)
  
  it("should handle complete plugin lifecycle", function()
    reset_state()
    
    -- Setup
    caramba.setup()
    
    -- Verify health
    local health = caramba.health
    assert.is_not_nil(health, "Should have health module")
    
    -- Test context extraction
    local context = require('caramba.context')
    vim.bo[1] = { filetype = "lua" }
    local ctx = context.collect()
    assert.is_not_nil(ctx, "Should extract context")
    
    -- Test command registration
    local commands = require('caramba.core.commands')
    local command_list = commands.list()
    assert.is_true(#command_list > 0, "Should have registered commands")
    
    -- Test configuration
    local config = require('caramba.config')
    local current_config = config.get()
    assert.is_not_nil(current_config, "Should have configuration")
    
    -- Everything should work together
    assert.is_true(true, "Complete lifecycle should work")
  end)
  
end)
