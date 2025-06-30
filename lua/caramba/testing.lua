-- AI Testing Module
-- Generates comprehensive unit tests for functions and classes

local M = {}

local config = require('caramba.config')
local context = require('caramba.context')
local llm = require('caramba.llm')
local multifile = require('caramba.multifile')

-- Test framework detection patterns
local test_frameworks = {
  lua = {
    busted = { pattern = "describe%(", file_pattern = "_spec%.lua$" },
    luaunit = { pattern = "TestCase", file_pattern = "_test%.lua$" },
  },
  python = {
    pytest = { pattern = "def test_", file_pattern = "test_.*%.py$" },
    unittest = { pattern = "class.*%(unittest%.TestCase%)", file_pattern = "test_.*%.py$" },
  },
  javascript = {
    jest = { pattern = "describe%(", file_pattern = "%.test%.js$" },
    mocha = { pattern = "describe%(", file_pattern = "%.spec%.js$" },
    vitest = { pattern = "describe%(", file_pattern = "%.test%.ts$" },
  },
  typescript = {
    jest = { pattern = "describe%(", file_pattern = "%.test%.ts$" },
    vitest = { pattern = "describe%(", file_pattern = "%.test%.ts$" },
  },
  go = {
    gotest = { pattern = "func Test", file_pattern = "_test%.go$" },
  },
  rust = {
    cargo = { pattern = "#%[test%]", file_pattern = "%.rs$" },
  },
}

-- Detect test framework for a language
local function detect_test_framework(language)
  local frameworks = test_frameworks[language]
  if not frameworks then
    return nil
  end
  
  -- Look for test files in the project
  local cwd = vim.fn.getcwd()
  for name, framework in pairs(frameworks) do
    local find_cmd = string.format("find %s -name '*' | grep -E '%s' | head -1", 
      cwd, framework.file_pattern)
    local result = vim.fn.system(find_cmd)
    
    if result and result ~= "" then
      -- Found test files, check for framework pattern
      local test_file = vim.trim(result)
      local content = vim.fn.readfile(test_file)
      if content then
        local text = table.concat(content, "\n")
        if text:match(framework.pattern) then
          return name
        end
      end
    end
  end
  
  -- Check package files for test dependencies
  if language == "javascript" or language == "typescript" then
    local ok, package = pcall(vim.fn.readfile, "package.json")
    if ok then
      local json_ok, pkg = pcall(vim.json.decode, table.concat(package, "\n"))
      if json_ok then
        local deps = vim.tbl_extend("force", 
          pkg.dependencies or {}, 
          pkg.devDependencies or {}
        )
        
        if deps.jest then return "jest" end
        if deps.vitest then return "vitest" end
        if deps.mocha then return "mocha" end
      end
    end
  elseif language == "python" then
    -- Check for pytest.ini, setup.cfg, or pyproject.toml
    if vim.fn.filereadable("pytest.ini") == 1 then
      return "pytest"
    end
    if vim.fn.filereadable("setup.cfg") == 1 then
      local content = vim.fn.readfile("setup.cfg")
      if vim.tbl_contains(content, "[tool:pytest]") then
        return "pytest"
      end
    end
  end
  
  -- Default frameworks by language
  local defaults = {
    lua = "busted",
    python = "pytest",
    javascript = "jest",
    typescript = "jest",
    go = "gotest",
    rust = "cargo",
  }
  
  return defaults[language]
end

-- Get test file path for a source file
local function get_test_file_path(source_path, language, framework)
  local dir = vim.fn.fnamemodify(source_path, ":h")
  local name = vim.fn.fnamemodify(source_path, ":t:r")
  local ext = vim.fn.fnamemodify(source_path, ":e")
  
  -- Common patterns for test file locations
  local patterns = {
    -- Same directory with suffix
    { path = dir, name = name .. "_test." .. ext },
    { path = dir, name = name .. "_spec." .. ext },
    { path = dir, name = name .. ".test." .. ext },
    { path = dir, name = name .. ".spec." .. ext },
    
    -- Test subdirectory
    { path = dir .. "/test", name = name .. "_test." .. ext },
    { path = dir .. "/tests", name = name .. "_test." .. ext },
    { path = dir .. "/__tests__", name = name .. ".test." .. ext },
    
    -- Parallel test directory structure
    { path = "test/" .. dir, name = name .. "_test." .. ext },
    { path = "tests/" .. dir, name = name .. "_test." .. ext },
    { path = "spec/" .. dir, name = name .. "_spec." .. ext },
  }
  
  -- Language/framework specific patterns
  if language == "go" then
    return dir .. "/" .. name .. "_test.go"
  elseif language == "python" then
    if framework == "pytest" then
      return dir .. "/test_" .. name .. ".py"
    else
      return dir .. "/" .. name .. "_test.py"
    end
  elseif framework == "jest" or framework == "vitest" then
    -- Check if __tests__ directory exists
    if vim.fn.isdirectory(dir .. "/__tests__") == 1 then
      return dir .. "/__tests__/" .. name .. ".test." .. ext
    else
      return dir .. "/" .. name .. ".test." .. ext
    end
  end
  
  -- Try to find existing test directory pattern
  for _, pattern in ipairs(patterns) do
    if vim.fn.isdirectory(pattern.path) == 1 then
      return pattern.path .. "/" .. pattern.name
    end
  end
  
  -- Default: same directory with _test suffix
  return dir .. "/" .. name .. "_test." .. ext
end

-- Generate tests for a function or class
M.generate_tests = function(opts)
  opts = opts or {}
  
  -- Get current context
  local ctx = context.collect()
  if not ctx then
    vim.notify("Could not extract context", vim.log.levels.ERROR)
    return
  end
  
  local language = ctx.language
  local framework = opts.framework or detect_test_framework(language)
  
  if not framework then
    vim.notify("Could not detect test framework for " .. language, vim.log.levels.WARN)
    framework = "generic"
  end
  
  -- Build prompt based on context
  local prompt = string.format([[
Generate comprehensive unit tests for the following %s code using %s framework.

The tests should cover:
1. Happy path - normal expected usage
2. Edge cases - boundary conditions, empty inputs, maximum values
3. Error cases - invalid inputs, exceptions, error handling
4. Type checking (if applicable)
5. Side effects and state changes (if applicable)

Code to test:
```%s
%s
```

Additional context:
- Language: %s
- Test framework: %s
- File: %s

Generate complete, runnable test code with:
- Proper imports and setup
- Clear test names describing what is being tested
- Assertions that verify both return values and side effects
- Comments explaining complex test scenarios
- Any necessary mocks or fixtures

Respond with the complete test file content.
]], 
    ctx.node_type or "code",
    framework,
    language,
    ctx.node_text or ctx.current_line,
    language,
    framework,
    vim.fn.expand("%:p")
  )
  
  -- Add imports context if available
  if ctx.imports and #ctx.imports > 0 then
    prompt = prompt .. "\n\nImports in source file:\n"
    for _, import in ipairs(ctx.imports) do
      prompt = prompt .. import .. "\n"
    end
  end
  
  -- Request test generation
  llm.request(prompt, { temperature = 1 }, function(response)
    if not response then
      vim.notify("Failed to generate tests", vim.log.levels.ERROR)
      return
    end
    
    vim.schedule(function()
      -- Determine test file path
      local source_path = vim.fn.expand("%:p")
      local test_path = opts.output or get_test_file_path(source_path, language, framework)
      
      -- Start multi-file transaction
      multifile.begin_transaction()
      
      -- Check if test file exists
      local test_exists = vim.fn.filereadable(test_path) == 1
      
      if test_exists and not opts.replace then
        -- Append to existing test file
        local existing = vim.fn.readfile(test_path)
        local existing_content = table.concat(existing, "\n")
        
        -- Try to intelligently merge
        local merged = M._merge_test_content(existing_content, response, language, framework)
        
        multifile.add_operation({
          type = multifile.OpType.MODIFY,
          path = test_path,
          content = merged,
          description = "Add new tests",
        })
      else
        -- Create new test file
        multifile.add_operation({
          type = multifile.OpType.CREATE,
          path = test_path,
          content = response,
          description = "Create test file",
        })
      end
      
      -- Preview the changes
      multifile.preview_transaction()
    end)
  end)
end

-- Merge new tests into existing test file
M._merge_test_content = function(existing, new_tests, language, framework)
  -- Simple strategy: append new tests before the last closing brace/end
  
  -- Find the main test suite/describe block
  local insert_point = #existing
  
  if framework == "jest" or framework == "mocha" or framework == "vitest" then
    -- Find last });
    local last_close = existing:match(".*()%s*}%s*%)%s*;?%s*$")
    if last_close then
      insert_point = last_close - 1
    end
  elseif framework == "pytest" then
    -- Just append at the end for pytest
    insert_point = #existing
  elseif framework == "busted" then
    -- Find last end)
    local last_close = existing:match(".*()%s*end%s*%)%s*$")
    if last_close then
      insert_point = last_close - 1
    end
  end
  
  -- Extract just the test functions from new_tests
  -- This is a simplified approach - in practice you'd want more sophisticated parsing
  local tests_only = new_tests
  
  -- Remove duplicate imports (simple approach)
  local import_patterns = {
    python = "^import%s+",
    javascript = "^import%s+",
    typescript = "^import%s+",
  }
  
  local pattern = import_patterns[language]
  if pattern then
    -- Remove lines that look like imports we already have
    local lines = vim.split(tests_only, "\n")
    local filtered = {}
    for _, line in ipairs(lines) do
      if not line:match(pattern) or not existing:match(line) then
        table.insert(filtered, line)
      end
    end
    tests_only = table.concat(filtered, "\n")
  end
  
  -- Insert new tests
  return existing:sub(1, insert_point) .. "\n\n" .. tests_only .. "\n" .. existing:sub(insert_point + 1)
end

-- Update tests when implementation changes
M.update_tests = function(opts)
  opts = opts or {}
  
  -- Find associated test file
  local source_path = vim.fn.expand("%:p")
  local language = vim.bo.filetype
  local framework = detect_test_framework(language)
  local test_path = get_test_file_path(source_path, language, framework)
  
  if vim.fn.filereadable(test_path) ~= 1 then
    vim.notify("No test file found at " .. test_path, vim.log.levels.WARN)
    return
  end
  
  -- Get current implementation
  local ctx = context.collect()
  if not ctx then
    vim.notify("Could not extract context", vim.log.levels.ERROR)
    return
  end
  
  -- Read existing tests
  local test_content = table.concat(vim.fn.readfile(test_path), "\n")
  
  local prompt = string.format([[
The implementation has changed. Update the tests to match the new implementation.

Current implementation:
```%s
%s
```

Existing tests:
```%s
%s
```

Update the tests to:
1. Match any API changes in the implementation
2. Add tests for new functionality
3. Remove tests for deleted functionality
4. Update assertions to match new behavior
5. Keep all tests that are still valid

Respond with the complete updated test file.
]],
    language,
    ctx.node_text or ctx.current_line,
    language,
    test_content
  )
  
  llm.request(prompt, { temperature = 0.2 }, function(response)
    if not response then
      vim.notify("Failed to update tests", vim.log.levels.ERROR)
      return
    end
    
    vim.schedule(function()
      multifile.begin_transaction()
      
      multifile.add_operation({
        type = multifile.OpType.MODIFY,
        path = test_path,
        content = response,
        description = "Update tests to match implementation",
      })
      
      multifile.preview_transaction()
    end)
  end)
end

-- Run tests and analyze failures
M.analyze_test_failures = function(opts)
  opts = opts or {}
  
  local test_output = opts.output
  if not test_output then
    -- Try to get from quickfix
    local qflist = vim.fn.getqflist()
    if #qflist > 0 then
      test_output = {}
      for _, item in ipairs(qflist) do
        table.insert(test_output, item.text)
      end
      test_output = table.concat(test_output, "\n")
    else
      vim.notify("No test output provided", vim.log.levels.ERROR)
      return
    end
  end
  
  local prompt = [[
Analyze these test failures and suggest fixes:

Test output:
```
]] .. test_output .. [[
```

For each failure:
1. Identify the root cause
2. Determine if it's an implementation bug or test bug  
3. Suggest specific code changes to fix it
4. Explain why the test is failing

Provide actionable fixes that can be applied to the code.
]]

  llm.request(prompt, { temperature = 1 }, function(response)
    if not response then
      vim.notify("Failed to analyze test failures", vim.log.levels.ERROR)
      return
    end
    
    vim.schedule(function()
      -- Show analysis in a floating window
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
      vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
      
      local width = math.floor(vim.o.columns * 0.8)
      local height = math.floor(vim.o.lines * 0.8)
      
      vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = 'minimal',
        border = 'rounded',
        title = ' Test Failure Analysis ',
        title_pos = 'center',
      })
    end)
  end)
end

-- Setup commands for this module
M.setup_commands = function()
  local commands = require('caramba.core.commands')
  
  -- Generate tests command
  commands.register('GenerateTests', M.generate_tests, {
    desc = 'Generate unit tests for current function/class',
  })
  
  -- Update tests command
  commands.register('UpdateTests', M.update_tests, {
    desc = 'Update tests to match implementation changes',
  })
  
  -- Analyze test failures
  commands.register('AnalyzeTestFailures', M.analyze_test_failures, {
    desc = 'Analyze test failures and suggest fixes',
  })
end

return M 