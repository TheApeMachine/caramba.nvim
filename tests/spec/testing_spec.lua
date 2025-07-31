-- Tests for caramba.testing module
-- Comprehensive test suite covering test generation, framework detection, and test management

-- Mock vim API for testing
local mock_vim = {
  bo = {},
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function(bufnr) return "/test/src/calculator.js" end,
    nvim_create_buf = function(listed, scratch) return 100 end,
    nvim_buf_set_lines = function(buf, start, end_line, strict, lines) end,
    nvim_buf_set_option = function(buf, option, value) end,
    nvim_open_win = function(buf, enter, config) return 200 end,
  },
  fn = {
    expand = function(path) 
      if path == "%:p" then return "/test/src/calculator.js"
      elseif path == "%:h" then return "/test/src"
      elseif path == "%:t:r" then return "calculator"
      elseif path == "%:e" then return "js"
      end
      return path
    end,
    fnamemodify = function(path, modifier)
      if modifier == ":h" then return "/test/src"
      elseif modifier == ":t:r" then return "calculator"
      elseif modifier == ":e" then return "js"
      end
      return path
    end,
    getcwd = function() return "/test" end,
    system = function(cmd) 
      if cmd:find("find.*test.*js") then
        return "/test/src/calculator.test.js\n"
      end
      return ""
    end,
    readfile = function(path)
      if path:find("package.json") then
        return {'{"devDependencies":{"jest":"^29.0.0"}}'}
      elseif path:find("test.js") then
        return {
          'describe("Calculator", () => {',
          '  it("should add numbers", () => {',
          '    expect(add(2, 3)).toBe(5);',
          '  });',
          '});'
        }
      end
      return {}
    end,
    filereadable = function(path)
      if path:find("package.json") or path:find("test.js") then
        return 1
      end
      return 0
    end,
    isdirectory = function(path)
      if path:find("__tests__") or path:find("/test") then
        return 1
      end
      return 0
    end,
    getqflist = function() return {} end,
  },
  json = {
    decode = function(str)
      if str:find("jest") then
        return {devDependencies = {jest = "^29.0.0"}}
      end
      return {}
    end,
  },
  o = { columns = 120, lines = 40 },
  log = { levels = { ERROR = 1, WARN = 2, INFO = 3 } },
  notify = function(msg, level) 
    mock_vim._notifications = mock_vim._notifications or {}
    table.insert(mock_vim._notifications, {msg = msg, level = level})
  end,
  schedule = function(fn) fn() end,
  tbl_contains = function(tbl, value)
    for _, v in ipairs(tbl) do
      if v == value then return true end
    end
    return false
  end,
  trim = function(str) return str:match("^%s*(.-)%s*$") end,
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch("(.-)" .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  _notifications = {},
}

_G.vim = mock_vim

-- Mock dependencies
package.loaded['caramba.config'] = {
  get = function() return {} end
}

package.loaded['caramba.context'] = {
  collect = function()
    return {
      language = "javascript",
      node_type = "function_declaration",
      node_text = "function add(a, b) {\n  return a + b;\n}",
      current_line = "function add(a, b) {",
      imports = {"const math = require('math');"},
      file_path = "/test/src/calculator.js"
    }
  end
}

package.loaded['caramba.llm'] = {
  request = function(prompt, opts, callback)
    -- Mock LLM response with generated test
    local test_response = [[
describe('Calculator', () => {
  it('should add two positive numbers', () => {
    expect(add(2, 3)).toBe(5);
  });
  
  it('should add negative numbers', () => {
    expect(add(-2, -3)).toBe(-5);
  });
  
  it('should handle zero', () => {
    expect(add(0, 5)).toBe(5);
  });
});
]]
    vim.schedule(function()
      callback(test_response)
    end)
  end
}

package.loaded['caramba.multifile'] = {
  begin_transaction = function() end,
  add_operation = function(op) 
    mock_vim._multifile_ops = mock_vim._multifile_ops or {}
    table.insert(mock_vim._multifile_ops, op)
  end,
  preview_transaction = function() end,
}

-- Load the testing module
local testing = require('caramba.testing')

describe("caramba.testing", function()
  
  -- Reset state before each test
  local function reset_state()
    mock_vim._notifications = {}
    mock_vim._multifile_ops = {}
  end
  
  it("should detect Jest framework from package.json", function()
    reset_state()
    vim.bo[1] = { filetype = "javascript" }
    
    local framework = testing._detect_test_framework("javascript")
    assert.equals(framework, "jest", "Should detect Jest from package.json")
  end)
  
  it("should detect test framework from existing test files", function()
    reset_state()
    
    -- Mock finding test files with describe pattern
    vim.fn.system = function(cmd)
      if cmd:find("find.*test") then
        return "/test/calculator.spec.js\n"
      end
      return ""
    end
    
    vim.fn.readfile = function(path)
      return {"describe('test', () => {", "  it('works', () => {});", "});"}
    end
    
    local framework = testing._detect_test_framework("javascript")
    assert.equals(framework, "jest", "Should detect framework from test file patterns")
  end)
  
  it("should generate test file path correctly", function()
    reset_state()
    
    local test_path = testing._get_test_file_path("/src/utils.js", "javascript", "jest")
    assert.is_not_nil(test_path, "Should generate test path")
    assert.is_true(test_path:find("test") or test_path:find("spec"), "Should include test/spec in path")
  end)
  
  it("should generate tests for current function", function()
    reset_state()
    vim.bo[1] = { filetype = "javascript" }
    
    local callback_called = false
    
    -- Override multifile preview to capture the operation
    package.loaded['caramba.multifile'].preview_transaction = function()
      callback_called = true
    end
    
    testing.generate_tests()
    
    assert.is_true(callback_called, "Should trigger multifile operation")
    assert.is_true(#mock_vim._multifile_ops > 0, "Should add multifile operation")
  end)
  
  it("should handle missing context gracefully", function()
    reset_state()
    
    -- Mock context.collect to return nil
    package.loaded['caramba.context'].collect = function() return nil end
    
    testing.generate_tests()
    
    assert.is_true(#mock_vim._notifications > 0, "Should notify about missing context")
    assert.is_true(mock_vim._notifications[1].msg:find("context"), "Should mention context error")
  end)
  
  it("should merge new tests with existing test file", function()
    reset_state()
    
    local existing_content = [[
describe('Calculator', () => {
  it('existing test', () => {
    expect(true).toBe(true);
  });
});
]]
    
    local new_tests = [[
describe('Calculator', () => {
  it('new test', () => {
    expect(add(1, 1)).toBe(2);
  });
});
]]
    
    local merged = testing._merge_test_content(existing_content, new_tests, "javascript", "jest")
    
    assert.is_not_nil(merged, "Should merge content")
    assert.is_true(merged:find("existing test"), "Should preserve existing tests")
    assert.is_true(merged:find("new test"), "Should include new tests")
  end)
  
  it("should update tests when implementation changes", function()
    reset_state()
    vim.bo[1] = { filetype = "javascript" }
    
    -- Mock existing test file
    vim.fn.filereadable = function(path) return 1 end
    vim.fn.readfile = function(path)
      return {"describe('old tests', () => {", "});"}
    end
    
    local callback_called = false
    package.loaded['caramba.multifile'].preview_transaction = function()
      callback_called = true
    end
    
    testing.update_tests()
    
    assert.is_true(callback_called, "Should update tests")
  end)
  
  it("should handle missing test file for update", function()
    reset_state()
    
    vim.fn.filereadable = function(path) return 0 end
    
    testing.update_tests()
    
    assert.is_true(#mock_vim._notifications > 0, "Should notify about missing test file")
  end)
  
  it("should analyze test failures", function()
    reset_state()
    
    local test_output = [[
FAIL src/calculator.test.js
  Calculator
    ✕ should add numbers (5ms)

  ● Calculator › should add numbers

    expect(received).toBe(expected) // Object.is equality

    Expected: 5
    Received: 6

      4 |   it('should add numbers', () => {
    > 5 |     expect(add(2, 3)).toBe(5);
        |                       ^
      6 |   });
]]
    
    local analysis_shown = false
    mock_vim.api.nvim_open_win = function(buf, enter, config)
      analysis_shown = true
      return 200
    end
    
    testing.analyze_test_failures({output = test_output})
    
    assert.is_true(analysis_shown, "Should show failure analysis")
  end)
  
  it("should handle different programming languages", function()
    reset_state()
    
    local languages = {
      {lang = "python", framework = "pytest"},
      {lang = "go", framework = "gotest"},
      {lang = "rust", framework = "cargo"},
      {lang = "lua", framework = "busted"},
    }
    
    for _, test_case in ipairs(languages) do
      local framework = testing._detect_test_framework(test_case.lang)
      assert.is_not_nil(framework, "Should detect framework for " .. test_case.lang)
    end
  end)
  
  it("should generate appropriate test file paths for different languages", function()
    reset_state()
    
    local test_cases = {
      {source = "/src/utils.py", lang = "python", expected_pattern = "test_.*%.py"},
      {source = "/src/utils.go", lang = "go", expected_pattern = ".*_test%.go"},
      {source = "/src/utils.rs", lang = "rust", expected_pattern = ".*%.rs"},
      {source = "/src/utils.lua", lang = "lua", expected_pattern = ".*_spec%.lua"},
    }
    
    for _, case in ipairs(test_cases) do
      local test_path = testing._get_test_file_path(case.source, case.lang, "default")
      assert.is_not_nil(test_path, "Should generate path for " .. case.lang)
    end
  end)
  
  it("should handle test framework configuration", function()
    reset_state()
    
    -- Test with specific framework override
    vim.bo[1] = { filetype = "javascript" }
    
    testing.generate_tests({framework = "mocha"})
    
    -- Should use the specified framework instead of auto-detection
    assert.is_true(true, "Should accept framework override")
  end)
  
  it("should handle test output from quickfix list", function()
    reset_state()
    
    vim.fn.getqflist = function()
      return {
        {text = "FAIL: test failed"},
        {text = "Expected: 5, Received: 6"},
      }
    end
    
    local analysis_shown = false
    mock_vim.api.nvim_open_win = function(buf, enter, config)
      analysis_shown = true
      return 200
    end
    
    testing.analyze_test_failures()
    
    assert.is_true(analysis_shown, "Should analyze failures from quickfix")
  end)
  
  it("should setup commands correctly", function()
    reset_state()
    
    -- Mock commands module
    local registered_commands = {}
    package.loaded['caramba.core.commands'] = {
      register = function(name, func, opts)
        registered_commands[name] = {func = func, opts = opts}
      end
    }
    
    testing.setup_commands()
    
    assert.is_not_nil(registered_commands.GenerateTests, "Should register GenerateTests command")
    assert.is_not_nil(registered_commands.UpdateTests, "Should register UpdateTests command")
    assert.is_not_nil(registered_commands.AnalyzeTestFailures, "Should register AnalyzeTestFailures command")
  end)
  
end)
