-- Test-Driven Development Assistant
-- Implements code from tests and supports property-based testing

local M = {}

local llm = require('ai.llm')
local testing = require('ai.testing')
local context = require('ai.context')
local edit = require('ai.edit')

-- TDD workflow states
M.state = {
  active_specs = {},
  implementation_history = {},
  coverage_tracking = {},
}

-- Implement code from test specification
M.implement_from_test = function(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  
  -- Detect test file and framework
  local test_info = testing.detect_test_framework(bufnr)
  if not test_info.is_test_file then
    vim.notify("Not in a test file. Please run from a test file.", vim.log.levels.WARN)
    return
  end
  
  -- Extract test specifications
  local specs = M._extract_test_specs(bufnr, test_info.framework)
  if #specs == 0 then
    vim.notify("No test specifications found", vim.log.levels.WARN)
    return
  end
  
  -- Let user select which test to implement
  if #specs > 1 then
    local choices = {}
    for _, spec in ipairs(specs) do
      table.insert(choices, spec.name)
    end
    
    vim.ui.select(choices, {
      prompt = "Select test to implement:",
    }, function(choice, idx)
      if choice then
        M._implement_single_test(specs[idx], test_info)
      end
    end)
  else
    M._implement_single_test(specs[1], test_info)
  end
end

-- Extract test specifications from buffer
M._extract_test_specs = function(bufnr, framework)
  local specs = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')
  
  -- Framework-specific patterns
  local patterns = {
    jest = {
      test = "it%s*%(s*['\"]([^'\"]+)['\"]",
      describe = "describe%s*%(s*['\"]([^'\"]+)['\"]",
    },
    pytest = {
      test = "def%s+(test_%w+)%s*%(",
      class = "class%s+(Test%w+)%s*:",
    },
    mocha = {
      test = "it%s*%(s*['\"]([^'\"]+)['\"]",
      describe = "describe%s*%(s*['\"]([^'\"]+)['\"]",
    },
  }
  
  local framework_patterns = patterns[framework] or patterns.jest
  
  -- Find test cases
  local current_describe = nil
  for i, line in ipairs(lines) do
    -- Check for describe/class blocks
    local describe_match = line:match(framework_patterns.describe or framework_patterns.class)
    if describe_match then
      current_describe = describe_match
    end
    
    -- Check for test cases
    local test_match = line:match(framework_patterns.test)
    if test_match then
      -- Extract test body
      local test_start = i
      local test_end = M._find_test_end(lines, i, framework)
      
      local test_body = {}
      for j = test_start, test_end do
        table.insert(test_body, lines[j])
      end
      
      table.insert(specs, {
        name = test_match,
        describe = current_describe,
        line = i,
        body = table.concat(test_body, '\n'),
        framework = framework,
      })
    end
  end
  
  return specs
end

-- Find end of test case
M._find_test_end = function(lines, start_line, framework)
  local depth = 0
  local in_test = false
  
  for i = start_line, #lines do
    local line = lines[i]
    
    -- Count braces/indentation
    if line:match("{") then
      depth = depth + 1
      in_test = true
    end
    if line:match("}") then
      depth = depth - 1
      if in_test and depth == 0 then
        return i
      end
    end
    
    -- Python: check indentation
    if framework == "pytest" then
      if i > start_line and line:match("^def%s+") then
        return i - 1
      end
    end
  end
  
  return #lines
end

-- Implement a single test
M._implement_single_test = function(spec, test_info)
  -- Analyze test to understand requirements
  local analysis = M._analyze_test_spec(spec)
  
  -- Find or create implementation file
  local impl_file = M._find_implementation_file(test_info.test_file)
  
  -- Generate implementation
  local prompt = string.format([[
Based on this test specification, implement the code to make it pass:

Test: %s
Framework: %s
%s

Test Body:
```%s
%s
```

Requirements identified:
%s

Generate ONLY the implementation code that will make this test pass.
Follow these rules:
1. Implement the minimal code needed to pass the test
2. Use appropriate types and error handling
3. Follow the coding style evident in the test
4. Include necessary imports
5. Make the code production-ready, not just test-passing

Return only the code to be added/modified, no explanations.
]], spec.name, spec.framework, 
    spec.describe and ("In describe block: " .. spec.describe) or "",
    test_info.language, spec.body,
    M._format_requirements(analysis))
  
  llm.request(prompt, { temperature = 0.1 }, function(response)
    if response then
      vim.schedule(function()
        M._apply_implementation(impl_file, response, spec)
      end)
    end
  end)
end

-- Analyze test specification to extract requirements
M._analyze_test_spec = function(spec)
  local analysis = {
    inputs = {},
    outputs = {},
    function_name = nil,
    class_name = nil,
    assertions = {},
    edge_cases = {},
  }
  
  -- Extract function/class being tested
  local function_pattern = "(%w+)%s*%("
  local class_pattern = "new%s+(%w+)"
  
  -- Simple pattern matching for now
  -- In production, would use Tree-sitter for accuracy
  local func_match = spec.body:match(function_pattern)
  if func_match and not func_match:match("^test") and not func_match:match("^it") then
    analysis.function_name = func_match
  end
  
  local class_match = spec.body:match(class_pattern)
  if class_match then
    analysis.class_name = class_match
  end
  
  -- Extract assertions
  for assertion in spec.body:gmatch("expect%((.-)%)") do
    table.insert(analysis.assertions, assertion)
  end
  
  -- Look for edge cases
  if spec.body:match("null") or spec.body:match("undefined") then
    table.insert(analysis.edge_cases, "null/undefined handling")
  end
  if spec.body:match("empty") then
    table.insert(analysis.edge_cases, "empty input handling")
  end
  if spec.body:match("throw") or spec.body:match("error") then
    table.insert(analysis.edge_cases, "error handling")
  end
  
  return analysis
end

-- Format requirements for prompt
M._format_requirements = function(analysis)
  local parts = {}
  
  if analysis.function_name then
    table.insert(parts, "- Function name: " .. analysis.function_name)
  end
  if analysis.class_name then
    table.insert(parts, "- Class name: " .. analysis.class_name)
  end
  
  if #analysis.assertions > 0 then
    table.insert(parts, "- Assertions: " .. table.concat(analysis.assertions, ", "))
  end
  
  if #analysis.edge_cases > 0 then
    table.insert(parts, "- Edge cases: " .. table.concat(analysis.edge_cases, ", "))
  end
  
  return table.concat(parts, "\n")
end

-- Find implementation file for test file
M._find_implementation_file = function(test_file)
  -- Remove test indicators from filename
  local impl_file = test_file
    :gsub("%.test%.", ".")
    :gsub("%.spec%.", ".")
    :gsub("_test%.", ".")
    :gsub("^test_", "")
    :gsub("/tests?/", "/src/")
    :gsub("/__tests__/", "/")
  
  -- Check if file exists
  if vim.fn.filereadable(impl_file) == 1 then
    return impl_file
  end
  
  -- Try common variations
  local variations = {
    impl_file:gsub("/src/", "/lib/"),
    impl_file:gsub("/src/", "/"),
    impl_file:gsub("%.ts$", ".js"),
    impl_file:gsub("%.js$", ".ts"),
  }
  
  for _, variant in ipairs(variations) do
    if vim.fn.filereadable(variant) == 1 then
      return variant
    end
  end
  
  -- File doesn't exist, will create it
  return impl_file
end

-- Apply implementation to file
M._apply_implementation = function(file_path, implementation, spec)
  -- Check if file exists
  local exists = vim.fn.filereadable(file_path) == 1
  
  if not exists then
    -- Create new file
    local dir = vim.fn.fnamemodify(file_path, ':h')
    vim.fn.mkdir(dir, 'p')
    
    -- Write implementation
    vim.fn.writefile(vim.split(implementation, '\n'), file_path)
    vim.notify("Created: " .. file_path, vim.log.levels.INFO)
    
    -- Open in split
    vim.cmd('split ' .. file_path)
  else
    -- Add to existing file
    local buf = vim.fn.bufadd(file_path)
    vim.fn.bufload(buf)
    
    -- Find insertion point
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local insert_line = M._find_insertion_point(lines, spec)
    
    -- Insert implementation
    local impl_lines = vim.split(implementation, '\n')
    vim.api.nvim_buf_set_lines(buf, insert_line, insert_line, false, impl_lines)
    
    -- Open file
    vim.cmd('split | buffer ' .. buf)
  end
  
  -- Record implementation
  table.insert(M.state.implementation_history, {
    test = spec.name,
    file = file_path,
    timestamp = os.time(),
    implementation = implementation,
  })
  
  vim.notify("Implementation added. Run tests to verify.", vim.log.levels.INFO)
end

-- Find where to insert new code
M._find_insertion_point = function(lines, spec)
  -- Look for end of imports
  local last_import = 0
  for i, line in ipairs(lines) do
    if line:match("^import") or line:match("^const.*require") then
      last_import = i
    end
  end
  
  -- Look for class definition if implementing method
  if spec.describe and spec.describe:match("^%u") then
    for i, line in ipairs(lines) do
      if line:match("class%s+" .. spec.describe) then
        -- Find end of class
        for j = i, #lines do
          if lines[j]:match("^}") then
            return j - 1
          end
        end
      end
    end
  end
  
  -- Default: after imports
  return last_import + 2
end

-- Generate property-based tests
M.generate_property_tests = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  
  -- Get function at cursor
  local ctx = context.get_context(bufnr, cursor[1])
  if not ctx.current_function then
    vim.notify("Place cursor on a function to generate property tests", vim.log.levels.WARN)
    return
  end
  
  local prompt = string.format([[
Generate property-based tests for this function:

```%s
%s
```

Create tests that:
1. Test invariants (properties that should always hold)
2. Test with generated random inputs
3. Test edge cases systematically
4. Use appropriate property testing library (fast-check, hypothesis, etc.)
5. Include shrinking for minimal failing cases

Generate comprehensive property-based tests.
]], vim.bo.filetype, ctx.current_function_text)
  
  llm.request(prompt, { temperature = 0.3 }, function(response)
    if response then
      vim.schedule(function()
        -- Show in new buffer
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, '\n'))
        vim.api.nvim_buf_set_option(buf, 'filetype', vim.bo.filetype)
        
        vim.cmd('split')
        vim.api.nvim_set_current_buf(buf)
      end)
    end
  end)
end

-- Watch tests and suggest implementation changes
M.watch_tests = function()
  -- Set up autocmd to run on save
  local group = vim.api.nvim_create_augroup("TDDWatch", { clear = true })
  
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = {"*.test.*", "*.spec.*", "*_test.*", "test_*"},
    callback = function()
      -- Run tests
      local test_cmd = M._get_test_command()
      if test_cmd then
        vim.fn.jobstart(test_cmd, {
          on_exit = function(_, exit_code)
            if exit_code ~= 0 then
              -- Tests failed, analyze and suggest fixes
              M._analyze_test_failures()
            else
              vim.notify("All tests passing!", vim.log.levels.INFO)
            end
          end,
        })
      end
    end,
  })
  
  vim.notify("TDD watch mode enabled", vim.log.levels.INFO)
end

-- Get test command for current project
M._get_test_command = function()
  -- Check for test scripts in package.json
  if vim.fn.filereadable("package.json") == 1 then
    return "npm test"
  elseif vim.fn.filereadable("Cargo.toml") == 1 then
    return "cargo test"
  elseif vim.fn.filereadable("go.mod") == 1 then
    return "go test ./..."
  elseif vim.fn.filereadable("pytest.ini") == 1 or vim.fn.filereadable("setup.py") == 1 then
    return "pytest"
  end
  
  return nil
end

-- Analyze test failures and suggest fixes
M._analyze_test_failures = function()
  -- Get test output from quickfix
  local qflist = vim.fn.getqflist()
  if #qflist == 0 then
    return
  end
  
  -- Group failures by file
  local failures = {}
  for _, item in ipairs(qflist) do
    if item.valid == 1 then
      local file = item.filename
      if not failures[file] then
        failures[file] = {}
      end
      table.insert(failures[file], {
        line = item.lnum,
        text = item.text,
      })
    end
  end
  
  -- Analyze each failure
  for file, file_failures in pairs(failures) do
    M._suggest_fix_for_failure(file, file_failures)
  end
end

-- Suggest fix for test failure
M._suggest_fix_for_failure = function(file, failures)
  -- Read file content
  local lines = vim.fn.readfile(file)
  local content = table.concat(lines, '\n')
  
  -- Build failure context
  local failure_desc = {}
  for _, failure in ipairs(failures) do
    table.insert(failure_desc, string.format("Line %d: %s", failure.line, failure.text))
  end
  
  local prompt = string.format([[
The following test failures occurred:

File: %s
Failures:
%s

Current implementation:
```
%s
```

Analyze the failures and suggest minimal changes to make the tests pass.
Focus on fixing the actual issues, not just making tests pass artificially.

Provide the specific code changes needed.
]], file, table.concat(failure_desc, '\n'), content)
  
  llm.request(prompt, { temperature = 0.1 }, function(response)
    if response then
      vim.schedule(function()
        -- Show suggestions
        local buf = vim.api.nvim_create_buf(false, true)
        
        local lines = {
          "# Test Failure Analysis",
          "",
          "## Failures:",
        }
        
        vim.list_extend(lines, failure_desc)
        table.insert(lines, "")
        table.insert(lines, "## Suggested Fixes:")
        vim.list_extend(lines, vim.split(response, '\n'))
        
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
        
        vim.cmd('split')
        vim.api.nvim_set_current_buf(buf)
      end)
    end
  end)
end

-- Coverage-guided implementation
M.implement_uncovered_code = function()
  -- Look for coverage report
  local coverage_file = M._find_coverage_file()
  if not coverage_file then
    vim.notify("No coverage report found. Run tests with coverage first.", vim.log.levels.WARN)
    return
  end
  
  -- Parse coverage data
  local uncovered = M._parse_coverage(coverage_file)
  if #uncovered == 0 then
    vim.notify("No uncovered code found!", vim.log.levels.INFO)
    return
  end
  
  -- Show uncovered code and suggest tests
  M._suggest_tests_for_uncovered(uncovered)
end

-- Find coverage report file
M._find_coverage_file = function()
  local coverage_files = {
    "coverage/lcov.info",
    "coverage/coverage-final.json",
    "htmlcov/index.html",
    "coverage.xml",
    ".coverage",
  }
  
  for _, file in ipairs(coverage_files) do
    if vim.fn.filereadable(file) == 1 then
      return file
    end
  end
  
  return nil
end

-- Parse coverage report
M._parse_coverage = function(coverage_file)
  -- Simplified parsing - in production would handle multiple formats
  local uncovered = {}
  
  if coverage_file:match("%.json$") then
    -- Parse JSON coverage
    local content = table.concat(vim.fn.readfile(coverage_file), '\n')
    local ok, data = pcall(vim.json.decode, content)
    
    if ok then
      for file, file_data in pairs(data) do
        if file_data.statementMap then
          for id, statement in pairs(file_data.statementMap) do
            if not file_data.s[id] or file_data.s[id] == 0 then
              table.insert(uncovered, {
                file = file,
                line = statement.start.line,
                type = "statement",
              })
            end
          end
        end
      end
    end
  end
  
  return uncovered
end

-- Suggest tests for uncovered code
M._suggest_tests_for_uncovered = function(uncovered)
  -- Group by file
  local by_file = {}
  for _, item in ipairs(uncovered) do
    if not by_file[item.file] then
      by_file[item.file] = {}
    end
    table.insert(by_file[item.file], item)
  end
  
  -- Generate test suggestions
  local suggestions = {}
  
  for file, items in pairs(by_file) do
    -- Read file to understand context
    if vim.fn.filereadable(file) == 1 then
      local lines = vim.fn.readfile(file)
      
      -- Extract uncovered functions
      for _, item in ipairs(items) do
        local line = lines[item.line]
        if line and line:match("function") then
          table.insert(suggestions, {
            file = file,
            line = item.line,
            code = line,
          })
        end
      end
    end
  end
  
  -- Show suggestions
  if #suggestions > 0 then
    M._show_coverage_suggestions(suggestions)
  end
end

-- Show coverage suggestions
M._show_coverage_suggestions = function(suggestions)
  local buf = vim.api.nvim_create_buf(false, true)
  
  local lines = {
    "# Uncovered Code - Test Suggestions",
    "",
    "The following code lacks test coverage:",
    "",
  }
  
  for _, suggestion in ipairs(suggestions) do
    table.insert(lines, string.format("## %s:%d", suggestion.file, suggestion.line))
    table.insert(lines, "```")
    table.insert(lines, suggestion.code)
    table.insert(lines, "```")
    table.insert(lines, "")
  end
  
  table.insert(lines, "Run :AIGenerateTests on each function to create tests.")
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  vim.cmd('tabnew')
  vim.api.nvim_set_current_buf(buf)
end

return M 