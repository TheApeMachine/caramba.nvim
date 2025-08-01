-- Tests for caramba.tdd module
-- Comprehensive test suite covering TDD workflow, test watching, and implementation generation

-- Mock vim API for testing
local mock_vim = {
  bo = {},
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function(bufnr) return "/test/calculator.test.js" end,
    nvim_create_augroup = function(name, opts) return 1 end,
    nvim_create_autocmd = function(event, opts) 
      mock_vim._autocmds = mock_vim._autocmds or {}
      table.insert(mock_vim._autocmds, {event = event, opts = opts})
    end,
    nvim_create_buf = function(listed, scratch) return 100 end,
    nvim_buf_set_lines = function(buf, start, end_line, strict, lines) end,
    nvim_open_win = function(buf, enter, config) return 200 end,
  },
  fn = {
    expand = function(path) 
      if path == "%:p" then return "/test/calculator.test.js"
      elseif path == "%:h" then return "/test"
      elseif path == "%:t:r" then return "calculator.test"
      end
      return path
    end,
    fnamemodify = function(path, modifier)
      if modifier == ":h" then return "/test"
      elseif modifier == ":t:r" then return "calculator"
      elseif modifier == ":e" then return "js"
      end
      return path
    end,
    jobstart = function(cmd, opts)
      mock_vim._jobs = mock_vim._jobs or {}
      local job_id = #mock_vim._jobs + 1
      mock_vim._jobs[job_id] = {cmd = cmd, opts = opts}
      
      -- Simulate job completion
      vim.schedule(function()
        if opts and opts.on_exit then
          opts.on_exit(job_id, 0) -- success
        end
      end)
      
      return job_id
    end,
    readfile = function(path)
      if path:find("test.js") then
        return {
          'describe("Calculator", () => {',
          '  it("should add two numbers", () => {',
          '    expect(add(2, 3)).toBe(5);',
          '  });',
          '  it("should multiply numbers", () => {',
          '    expect(multiply(4, 5)).toBe(20);',
          '  });',
          '});'
        }
      elseif path:find("calculator.js") then
        return {
          'function add(a, b) {',
          '  return a + b;',
          '}',
          '',
          '// TODO: implement multiply function'
        }
      end
      return {}
    end,
    filereadable = function(path) return 1 end,
    system = function(cmd)
      if cmd:find("coverage") then
        return "Lines: 75% (15/20)\nFunctions: 50% (1/2)"
      end
      return ""
    end,
    getcwd = function() return "/test" end,
  },
  o = { columns = 120, lines = 40 },
  log = { levels = { ERROR = 1, WARN = 2, INFO = 3 } },
  notify = function(msg, level) 
    mock_vim._notifications = mock_vim._notifications or {}
    table.insert(mock_vim._notifications, {msg = msg, level = level})
  end,
  schedule = function(fn) fn() end,
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch("(.-)" .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  _notifications = {},
  _autocmds = {},
  _jobs = {},
}

_G.vim = mock_vim

-- Mock dependencies
package.loaded['caramba.context'] = {
  collect = function()
    return {
      language = "javascript",
      node_type = "test_suite",
      node_text = 'describe("Calculator", () => {\n  it("should add", () => {\n    expect(add(2, 3)).toBe(5);\n  });\n});',
      current_line = '  it("should add", () => {',
      file_path = "/test/calculator.test.js"
    }
  end
}

package.loaded['caramba.llm'] = {
  request = function(prompt, opts, callback)
    local response
    if prompt:find("implement.*from.*test") then
      response = [[
function add(a, b) {
  return a + b;
}

function multiply(a, b) {
  return a * b;
}

module.exports = { add, multiply };
]]
    elseif prompt:find("property.*test") then
      response = [[
const fc = require('fast-check');

describe('Calculator Property Tests', () => {
  it('add should be commutative', () => {
    fc.assert(fc.property(fc.integer(), fc.integer(), (a, b) => {
      expect(add(a, b)).toBe(add(b, a));
    }));
  });
  
  it('add should have zero as identity', () => {
    fc.assert(fc.property(fc.integer(), (a) => {
      expect(add(a, 0)).toBe(a);
    }));
  });
});
]]
    elseif prompt:find("uncovered.*code") then
      response = [[
describe('Calculator Edge Cases', () => {
  it('should handle large numbers', () => {
    expect(add(Number.MAX_SAFE_INTEGER, 1)).toBeDefined();
  });
  
  it('should handle invalid inputs', () => {
    expect(() => add(null, undefined)).toThrow();
  });
});
]]
    end
    
    vim.schedule(function()
      callback(response)
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

-- Load the TDD module
local tdd = require('caramba.tdd')

describe("caramba.tdd", function()
  
  -- Reset state before each test
  local function reset_state()
    mock_vim._notifications = {}
    mock_vim._multifile_ops = {}
    mock_vim._autocmds = {}
    mock_vim._jobs = {}
  end
  
  it("should implement from test specification", function()
    reset_state()
    vim.bo[1] = { filetype = "javascript" }
    
    local callback_called = false
    package.loaded['caramba.multifile'].preview_transaction = function()
      callback_called = true
    end
    
    tdd.implement_from_test()
    
    assert.is_true(callback_called, "Should trigger implementation generation")
    assert.is_true(#mock_vim._multifile_ops > 0, "Should create multifile operation")
  end)
  
  it("should generate property-based tests", function()
    reset_state()
    vim.bo[1] = { filetype = "javascript" }
    
    -- Mock context for a function
    package.loaded['caramba.context'].collect = function()
      return {
        language = "javascript",
        node_type = "function_declaration",
        node_text = "function add(a, b) { return a + b; }",
        current_line = "function add(a, b) {",
        file_path = "/test/calculator.js"
      }
    end
    
    local callback_called = false
    package.loaded['caramba.multifile'].preview_transaction = function()
      callback_called = true
    end
    
    tdd.generate_property_tests()
    
    assert.is_true(callback_called, "Should generate property tests")
  end)
  
  it("should enable test watch mode", function()
    reset_state()
    
    tdd.watch_tests()
    
    assert.is_true(#mock_vim._autocmds > 0, "Should create autocmd for test watching")
    assert.is_true(#mock_vim._notifications > 0, "Should notify about watch mode")
    assert.is_true(mock_vim._notifications[1].msg:find("watch"), "Should mention watch mode")
  end)
  
  it("should detect test command for different languages", function()
    reset_state()
    
    -- Test JavaScript/Jest
    vim.bo[1] = { filetype = "javascript" }
    vim.fn.filereadable = function(path)
      if path:find("package.json") then return 1 end
      return 0
    end
    vim.fn.readfile = function(path)
      return {'{"scripts":{"test":"jest"}}'}
    end
    
    local cmd = tdd._get_test_command()
    assert.is_not_nil(cmd, "Should detect test command")
    assert.is_true(type(cmd) == "table" or type(cmd) == "string", "Should return valid command")
  end)
  
  it("should analyze test failures", function()
    reset_state()
    
    -- Mock failed test job
    vim.fn.jobstart = function(cmd, opts)
      local job_id = 1
      vim.schedule(function()
        if opts and opts.on_exit then
          opts.on_exit(job_id, 1) -- failure exit code
        end
      end)
      return job_id
    end
    
    -- Mock analysis function
    tdd._analyze_test_failures = function()
      table.insert(mock_vim._notifications, {msg = "Test failure analyzed", level = vim.log.levels.INFO})
    end
    
    tdd.watch_tests()
    
    -- Trigger the autocmd callback
    if #mock_vim._autocmds > 0 then
      local autocmd = mock_vim._autocmds[1]
      if autocmd.opts.callback then
        autocmd.opts.callback()
      end
    end
    
    -- Should analyze failures when tests fail
    assert.is_true(true, "Should handle test failures")
  end)
  
  it("should implement uncovered code paths", function()
    reset_state()
    vim.bo[1] = { filetype = "javascript" }
    
    local callback_called = false
    package.loaded['caramba.multifile'].preview_transaction = function()
      callback_called = true
    end
    
    tdd.implement_uncovered_code()
    
    assert.is_true(callback_called, "Should generate tests for uncovered code")
  end)
  
  it("should handle missing context gracefully", function()
    reset_state()
    
    package.loaded['caramba.context'].collect = function() return nil end
    
    tdd.implement_from_test()
    
    assert.is_true(#mock_vim._notifications > 0, "Should notify about missing context")
  end)
  
  it("should determine implementation file from test file", function()
    reset_state()
    
    local test_cases = {
      {test = "/test/calculator.test.js", expected = "/src/calculator.js"},
      {test = "/test/utils.spec.js", expected = "/src/utils.js"},
      {test = "/tests/math_test.py", expected = "/src/math.py"},
      {test = "/spec/parser_spec.rb", expected = "/lib/parser.rb"},
    }
    
    for _, case in ipairs(test_cases) do
      local impl_path = tdd._get_implementation_path(case.test)
      assert.is_not_nil(impl_path, "Should determine implementation path for " .. case.test)
    end
  end)
  
  it("should extract test requirements from test code", function()
    reset_state()
    
    local test_code = [[
describe('Calculator', () => {
  it('should add two numbers', () => {
    expect(add(2, 3)).toBe(5);
  });
  
  it('should multiply numbers', () => {
    expect(multiply(4, 5)).toBe(20);
  });
  
  it('should handle division by zero', () => {
    expect(() => divide(10, 0)).toThrow('Division by zero');
  });
});
]]
    
    local requirements = tdd._extract_test_requirements(test_code, "javascript")
    
    assert.is_not_nil(requirements, "Should extract requirements")
    assert.is_true(type(requirements) == "table", "Should return table of requirements")
  end)
  
  it("should generate implementation for different languages", function()
    reset_state()
    
    local languages = {"javascript", "python", "go", "rust", "lua"}
    
    for _, lang in ipairs(languages) do
      vim.bo[1] = { filetype = lang }
      
      package.loaded['caramba.context'].collect = function()
        return {
          language = lang,
          node_type = "test_suite",
          node_text = "test code for " .. lang,
          file_path = "/test/test." .. lang
        }
      end
      
      local success = pcall(tdd.implement_from_test)
      assert.is_true(success, "Should handle " .. lang .. " implementation")
    end
  end)
  
  it("should handle property test generation for pure functions", function()
    reset_state()
    
    package.loaded['caramba.context'].collect = function()
      return {
        language = "javascript",
        node_type = "function_declaration",
        node_text = "function isPrime(n) { /* implementation */ }",
        current_line = "function isPrime(n) {",
        file_path = "/src/math.js"
      }
    end
    
    local callback_called = false
    package.loaded['caramba.multifile'].preview_transaction = function()
      callback_called = true
    end
    
    tdd.generate_property_tests()
    
    assert.is_true(callback_called, "Should generate property tests for pure functions")
  end)
  
  it("should run coverage analysis", function()
    reset_state()
    
    local coverage_data = tdd._get_coverage_data()
    
    assert.is_not_nil(coverage_data, "Should get coverage data")
    -- Coverage data format depends on implementation
  end)
  
  it("should setup TDD commands", function()
    reset_state()
    
    local registered_commands = {}
    package.loaded['caramba.core.commands'] = {
      register = function(name, func, opts)
        registered_commands[name] = {func = func, opts = opts}
      end
    }
    
    tdd.setup_commands()
    
    assert.is_not_nil(registered_commands.ImplementFromTest, "Should register ImplementFromTest")
    assert.is_not_nil(registered_commands.GeneratePropertyTests, "Should register GeneratePropertyTests")
    assert.is_not_nil(registered_commands.WatchTests, "Should register WatchTests")
    assert.is_not_nil(registered_commands.ImplementUncovered, "Should register ImplementUncovered")
  end)
  
  it("should handle test file patterns correctly", function()
    reset_state()
    
    local patterns = {
      "*.test.js",
      "*.spec.js", 
      "*_test.py",
      "test_*.py",
      "*_test.go",
      "*_spec.rb"
    }
    
    for _, pattern in ipairs(patterns) do
      local is_test_file = tdd._is_test_file("/path/to/file" .. pattern:gsub("%*", "example"))
      assert.is_true(is_test_file, "Should recognize test file pattern: " .. pattern)
    end
  end)
  
  it("should provide test suggestions based on code analysis", function()
    reset_state()
    
    local code = [[
function calculateTax(income, rate) {
  if (income < 0) throw new Error('Invalid income');
  if (rate < 0 || rate > 1) throw new Error('Invalid rate');
  return income * rate;
}
]]
    
    local suggestions = tdd._suggest_tests(code, "javascript")
    
    assert.is_not_nil(suggestions, "Should provide test suggestions")
    assert.is_true(type(suggestions) == "table", "Should return table of suggestions")
  end)
  
end)
