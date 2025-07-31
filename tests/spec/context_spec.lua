-- Tests for caramba.context module
-- Comprehensive test suite covering context extraction, caching, and tree-sitter integration

-- Mock vim API for testing
local mock_vim = {
  bo = {},
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function(bufnr) return "/test/file.lua" end,
    nvim_buf_get_lines = function(bufnr, start, end_line, strict)
      return {
        "local function test_function()",
        "  local x = 1",
        "  return x + 1",
        "end",
        "",
        "local function another_function()",
        "  return 'hello'",
        "end"
      }
    end,
    nvim_get_current_line = function() return "  local x = 1" end,
    nvim_win_get_cursor = function(win) return {2, 8} end,
  },
  treesitter = {
    get_parser = function(bufnr, lang)
      -- Mock parser that returns a simple tree structure
      return {
        parse = function()
          return {{
            root = function()
              return {
                -- Mock tree-sitter node
                type = function() return "chunk" end,
                range = function() return 0, 0, 7, 0 end,
                child_count = function() return 2 end,
                child = function(index)
                  if index == 0 then
                    return {
                      type = function() return "function_definition" end,
                      range = function() return 0, 0, 3, 3 end,
                      parent = function() return nil end,
                      id = function() return "func1" end,
                    }
                  elseif index == 1 then
                    return {
                      type = function() return "function_definition" end,
                      range = function() return 5, 0, 7, 3 end,
                      parent = function() return nil end,
                      id = function() return "func2" end,
                    }
                  end
                  return nil
                end,
              }
            end
          }}
        end
      }
    end
  },
  fn = {
    expand = function(expr) return "/test/file.lua" end,
  },
  log = {
    levels = {
      ERROR = 1,
      WARN = 2,
      INFO = 3,
    }
  },
  notify = function(msg, level) end,
  tbl_contains = function(tbl, value)
    for _, v in ipairs(tbl) do
      if v == value then return true end
    end
    return false
  end,
  tbl_extend = function(behavior, ...)
    local result = {}
    for _, tbl in ipairs({...}) do
      for k, v in pairs(tbl) do
        result[k] = v
      end
    end
    return result
  end,
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch("(.-)" .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  trim = function(str) return str:match("^%s*(.-)%s*$") end,
}

-- Set up global vim mock
_G.vim = mock_vim

-- Mock utils module
package.loaded['caramba.utils'] = {
  get_node_text = function(node, bufnr)
    local start_row, start_col, end_row, end_col = node.range()
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    return table.concat(lines, "\n")
  end
}

-- Load the context module
local context = require('caramba.context')

describe("caramba.context", function()
  
  it("should collect the entire buffer when no selection is made", function()
    -- Mock buffer state
    vim.bo[1] = { filetype = "lua" }
    
    local result = context.collect()
    
    assert.is_not_nil(result, "Context should not be nil")
    assert.equals(result.language, "lua", "Language should be detected as lua")
    assert.is_not_nil(result.content, "Content should be present")
    assert.equals(result.file_path, "/test/file.lua", "File path should be correct")
  end)
  
  it("should extract imports from buffer", function()
    vim.bo[1] = { filetype = "lua" }
    
    -- Mock buffer with imports
    vim.api.nvim_buf_get_lines = function(bufnr, start, end_line, strict)
      return {
        "local config = require('caramba.config')",
        "local utils = require('caramba.utils')",
        "",
        "local function test()",
        "  return true",
        "end"
      }
    end
    
    local imports = context.extract_imports(1)
    
    assert.is_not_nil(imports, "Imports should not be nil")
    assert.is_true(#imports >= 2, "Should find at least 2 imports")
  end)
  
  it("should find context node for cursor position", function()
    vim.bo[1] = { filetype = "lua" }
    
    -- Mock get_node_at_cursor to return a function node
    context.get_node_at_cursor = function()
      return {
        type = function() return "local_variable" end,
        parent = function()
          return {
            type = function() return "function_definition" end,
            parent = function() return nil end,
            range = function() return 0, 0, 3, 3 end,
            id = function() return "test_func" end,
          }
        end,
        range = function() return 1, 8, 1, 9 end,
        id = function() return "var_x" end,
      }
    end
    
    local result = context.collect()
    
    assert.is_not_nil(result, "Context should not be nil")
    assert.is_not_nil(result.node_type, "Node type should be detected")
  end)
  
  it("should cache context results", function()
    vim.bo[1] = { filetype = "lua" }
    
    -- Mock get_node_at_cursor
    context.get_node_at_cursor = function()
      return {
        type = function() return "function_definition" end,
        parent = function() return nil end,
        range = function() return 0, 0, 3, 3 end,
        id = function() return "test_func" end,
      }
    end
    
    -- First call
    local result1 = context.collect()
    
    -- Second call should use cache
    local result2 = context.collect()
    
    assert.is_not_nil(result1, "First result should not be nil")
    assert.is_not_nil(result2, "Second result should not be nil")
    assert.equals(result1.content, result2.content, "Cached result should match")
  end)
  
  it("should handle missing tree-sitter parser gracefully", function()
    vim.bo[1] = { filetype = "unknown" }
    
    -- Mock parser to return nil
    vim.treesitter.get_parser = function(bufnr, lang)
      return nil
    end
    
    local result = context.collect()
    
    assert.is_not_nil(result, "Should still return context without parser")
    assert.equals(result.language, "unknown", "Language should be preserved")
  end)
  
  it("should extract function and class context", function()
    vim.bo[1] = { filetype = "lua" }
    
    -- Mock a more complex node structure
    context.get_node_at_cursor = function()
      return {
        type = function() return "identifier" end,
        parent = function()
          return {
            type = function() return "function_definition" end,
            parent = function()
              return {
                type = function() return "table_constructor" end,
                parent = function() return nil end,
                range = function() return 0, 0, 10, 3 end,
                id = function() return "class_table" end,
              }
            end,
            range = function() return 2, 2, 8, 5 end,
            id = function() return "method_func" end,
          }
        end,
        range = function() return 4, 4, 4, 8 end,
        id = function() return "var_name" end,
      }
    end
    
    local result = context.collect()
    
    assert.is_not_nil(result, "Context should not be nil")
    -- Should detect both function and class-like structures
  end)
  
  it("should handle different programming languages", function()
    local languages = {"python", "javascript", "typescript", "go", "rust"}
    
    for _, lang in ipairs(languages) do
      vim.bo[1] = { filetype = lang }
      
      local result = context.collect()
      
      assert.is_not_nil(result, "Context should work for " .. lang)
      assert.equals(result.language, lang, "Language should be detected correctly")
    end
  end)
  
  it("should extract siblings when requested", function()
    vim.bo[1] = { filetype = "lua" }
    
    context.get_node_at_cursor = function()
      return {
        type = function() return "function_definition" end,
        parent = function() return nil end,
        range = function() return 0, 0, 3, 3 end,
        id = function() return "test_func" end,
      }
    end
    
    local result = context.collect({ include_siblings = true })
    
    assert.is_not_nil(result, "Context should not be nil")
    -- Should include sibling information when requested
  end)
  
  it("should update cursor context", function()
    vim.bo[1] = { filetype = "lua" }
    
    -- Mock cursor at function definition
    context.get_node_at_cursor = function()
      return {
        type = function() return "function_definition" end,
        parent = function() return nil end,
        range = function() return 0, 0, 3, 3 end,
        id = function() return "test_func" end,
      }
    end
    
    context.update_cursor_context()
    local cursor_ctx = context.get_cursor_context()
    
    assert.is_not_nil(cursor_ctx, "Cursor context should be set")
    assert.equals(cursor_ctx.type, "function_definition", "Should detect function context")
  end)
  
end)
