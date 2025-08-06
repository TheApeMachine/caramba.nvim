-- Test Runner and Framework Integration
-- Manages test execution, coverage, and framework-specific logic

local M = {}

-- Supported test frameworks and their configurations
M.frameworks = {
  javascript = {
    jest = {
      patterns = { "**/__tests__/**/*.[jt]s?(x)", "**/?(*.)+(spec|test).[jt]s?(x)" },
      command = "npm test --",
      -- Other Jest-specific settings
    },
    mocha = {
      patterns = { "test/**/*.js" },
      command = "mocha",
    }
    -- Potentially other JS frameworks like Jasmine
  },
  python = {
    pytest = {
      patterns = { "test_*.py", "*_test.py" },
      command = "pytest",
    }
  },
  lua = {
    busted = {
      patterns = { "spec/*_spec.lua" },
      command = "busted",
    }
  },
  -- Other languages and frameworks
}

-- Detect if the current file is a test file and which framework it uses
-- @param bufnr: The buffer number to check
-- @return table: Information about the test file, e.g.,
-- { is_test_file = true, framework = "jest", language = "javascript", test_file = "path/to/file" }
function M.detect_test_framework(bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if not file_path or file_path == "" then
    return { is_test_file = false }
  end

  local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
  local language = M._get_language_from_filetype(filetype)

  if M.frameworks[language] then
    for framework, config in pairs(M.frameworks[language]) do
      for _, pattern in ipairs(config.patterns) do
        if file_path:match(vim.fn.glob2regpat(pattern)) then
          return {
            is_test_file = true,
            framework = framework,
            language = language,
            test_file = file_path,
          }
        end
      end
    end
  end

  return { is_test_file = false, test_file = file_path, language = language }
end

-- Helper to map filetype to a general language
function M._get_language_from_filetype(filetype)
  local filetype_map = {
    javascript = "javascript",
    typescript = "javascript",
    typescriptreact = "javascript",
    javascriptreact = "javascript",
    python = "python",
    lua = "lua",
  }
  return filetype_map[filetype] or filetype
end

-- Other test-related functions...
-- For example, running tests, parsing results, managing coverage, etc.

return M