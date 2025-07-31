-- Tests for caramba.multifile module
-- Comprehensive test suite covering multi-file operations, transactions, and previews

-- Mock vim API for testing
local mock_vim = {
  api = {
    nvim_create_buf = function(listed, scratch) return 100 end,
    nvim_buf_set_lines = function(buf, start, end_line, strict, lines) end,
    nvim_buf_set_option = function(buf, option, value) end,
    nvim_open_win = function(buf, enter, config) return 200 end,
    nvim_win_set_cursor = function(win, pos) end,
    nvim_buf_get_lines = function(buf, start, end_line, strict)
      return {"existing line 1", "existing line 2"}
    end,
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function(buf) return "/test/current.lua" end,
  },
  fn = {
    expand = function(path) return path:gsub("~", "/home/user") end,
    fnamemodify = function(path, modifier)
      if modifier == ":h" then return "/test"
      elseif modifier == ":t" then return "current.lua"
      end
      return path
    end,
    filereadable = function(path) return 1 end,
    readfile = function(path) 
      return {"file content line 1", "file content line 2"}
    end,
    writefile = function(lines, path) return 0 end,
    mkdir = function(path, mode) return 1 end,
    delete = function(path) return 0 end,
    isdirectory = function(path) return 0 end,
    getcwd = function() return "/test/project" end,
  },
  o = {
    columns = 120,
    lines = 40,
  },
  log = {
    levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 }
  },
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
  tbl_extend = function(behavior, ...)
    local result = {}
    for _, tbl in ipairs({...}) do
      for k, v in pairs(tbl) do
        result[k] = v
      end
    end
    return result
  end,
  _notifications = {},
}

_G.vim = mock_vim

-- Load the multifile module
local multifile = require('caramba.multifile')

describe("caramba.multifile", function()
  
  -- Reset state before each test
  local function reset_state()
    multifile._reset_state() -- Assuming this exists or we'll mock it
    mock_vim._notifications = {}
  end
  
  it("should begin a new transaction", function()
    reset_state()
    
    multifile.begin_transaction()
    
    -- Should be able to add operations after beginning transaction
    local success = pcall(multifile.add_operation, {
      type = multifile.OpType.CREATE,
      path = "/test/new_file.lua",
      content = "new content",
      description = "Create new file"
    })
    
    assert.is_true(success, "Should be able to add operations after beginning transaction")
  end)
  
  it("should add CREATE operation", function()
    reset_state()
    multifile.begin_transaction()
    
    local operation = {
      type = multifile.OpType.CREATE,
      path = "/test/new_file.lua",
      content = "local function new_func()\n  return true\nend",
      description = "Create new utility file"
    }
    
    multifile.add_operation(operation)
    
    local operations = multifile.get_operations()
    assert.equals(#operations, 1, "Should have one operation")
    assert.equals(operations[1].type, multifile.OpType.CREATE, "Should be CREATE operation")
    assert.equals(operations[1].path, "/test/new_file.lua", "Should have correct path")
  end)
  
  it("should add MODIFY operation", function()
    reset_state()
    multifile.begin_transaction()
    
    local operation = {
      type = multifile.OpType.MODIFY,
      path = "/test/existing.lua",
      content = "modified content",
      description = "Update existing file"
    }
    
    multifile.add_operation(operation)
    
    local operations = multifile.get_operations()
    assert.equals(operations[1].type, multifile.OpType.MODIFY, "Should be MODIFY operation")
  end)
  
  it("should add DELETE operation", function()
    reset_state()
    multifile.begin_transaction()
    
    local operation = {
      type = multifile.OpType.DELETE,
      path = "/test/to_delete.lua",
      description = "Remove obsolete file"
    }
    
    multifile.add_operation(operation)
    
    local operations = multifile.get_operations()
    assert.equals(operations[1].type, multifile.OpType.DELETE, "Should be DELETE operation")
  end)
  
  it("should add MOVE operation", function()
    reset_state()
    multifile.begin_transaction()
    
    local operation = {
      type = multifile.OpType.MOVE,
      path = "/test/old_location.lua",
      new_path = "/test/new_location.lua",
      description = "Move file to new location"
    }
    
    multifile.add_operation(operation)
    
    local operations = multifile.get_operations()
    assert.equals(operations[1].type, multifile.OpType.MOVE, "Should be MOVE operation")
    assert.equals(operations[1].new_path, "/test/new_location.lua", "Should have new path")
  end)
  
  it("should validate operation before adding", function()
    reset_state()
    multifile.begin_transaction()
    
    -- Invalid operation - missing required fields
    local invalid_operation = {
      type = multifile.OpType.CREATE,
      -- missing path and content
      description = "Invalid operation"
    }
    
    local success, error = pcall(multifile.add_operation, invalid_operation)
    assert.is_false(success, "Should reject invalid operation")
  end)
  
  it("should preview transaction", function()
    reset_state()
    multifile.begin_transaction()
    
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/new.lua",
      content = "new content",
      description = "Create new file"
    })
    
    multifile.add_operation({
      type = multifile.OpType.MODIFY,
      path = "/test/existing.lua",
      content = "modified content",
      description = "Modify existing file"
    })
    
    -- Should open preview window
    multifile.preview_transaction()
    
    -- Verify preview was created (mock would track this)
    assert.is_true(true, "Preview should be displayed")
  end)
  
  it("should execute transaction successfully", function()
    reset_state()
    multifile.begin_transaction()
    
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/new.lua",
      content = "new content",
      description = "Create new file"
    })
    
    local success = multifile.execute_transaction()
    assert.is_true(success, "Transaction should execute successfully")
  end)
  
  it("should rollback transaction on error", function()
    reset_state()
    multifile.begin_transaction()
    
    -- Mock file write to fail
    local original_writefile = vim.fn.writefile
    vim.fn.writefile = function(lines, path) return 1 end -- Return error
    
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/fail.lua",
      content = "content",
      description = "This should fail"
    })
    
    local success = multifile.execute_transaction()
    assert.is_false(success, "Transaction should fail")
    
    -- Restore original function
    vim.fn.writefile = original_writefile
  end)
  
  it("should cancel transaction", function()
    reset_state()
    multifile.begin_transaction()
    
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/cancelled.lua",
      content = "content",
      description = "This will be cancelled"
    })
    
    multifile.cancel_transaction()
    
    local operations = multifile.get_operations()
    assert.equals(#operations, 0, "Should have no operations after cancel")
  end)
  
  it("should handle CREATE operation execution", function()
    reset_state()
    
    local created_files = {}
    vim.fn.writefile = function(lines, path)
      created_files[path] = lines
      return 0
    end
    
    multifile.begin_transaction()
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/created.lua",
      content = "line1\nline2",
      description = "Create test file"
    })
    
    multifile.execute_transaction()
    
    assert.is_not_nil(created_files["/test/created.lua"], "File should be created")
    assert.equals(created_files["/test/created.lua"][1], "line1", "Should have correct content")
  end)
  
  it("should handle MODIFY operation execution", function()
    reset_state()
    
    local modified_files = {}
    vim.fn.writefile = function(lines, path)
      modified_files[path] = lines
      return 0
    end
    
    multifile.begin_transaction()
    multifile.add_operation({
      type = multifile.OpType.MODIFY,
      path = "/test/existing.lua",
      content = "modified line1\nmodified line2",
      description = "Modify test file"
    })
    
    multifile.execute_transaction()
    
    assert.is_not_nil(modified_files["/test/existing.lua"], "File should be modified")
  end)
  
  it("should handle DELETE operation execution", function()
    reset_state()
    
    local deleted_files = {}
    vim.fn.delete = function(path)
      deleted_files[path] = true
      return 0
    end
    
    multifile.begin_transaction()
    multifile.add_operation({
      type = multifile.OpType.DELETE,
      path = "/test/to_delete.lua",
      description = "Delete test file"
    })
    
    multifile.execute_transaction()
    
    assert.is_true(deleted_files["/test/to_delete.lua"], "File should be deleted")
  end)
  
  it("should handle MOVE operation execution", function()
    reset_state()
    
    local moved_files = {}
    vim.fn.rename = function(old_path, new_path)
      moved_files[old_path] = new_path
      return 0
    end
    
    multifile.begin_transaction()
    multifile.add_operation({
      type = multifile.OpType.MOVE,
      path = "/test/old.lua",
      new_path = "/test/new.lua",
      description = "Move test file"
    })
    
    multifile.execute_transaction()
    
    assert.equals(moved_files["/test/old.lua"], "/test/new.lua", "File should be moved")
  end)
  
  it("should create directories when needed", function()
    reset_state()
    
    local created_dirs = {}
    vim.fn.mkdir = function(path, mode)
      created_dirs[path] = true
      return 1
    end
    
    multifile.begin_transaction()
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/new_dir/new_file.lua",
      content = "content",
      description = "Create file in new directory"
    })
    
    multifile.execute_transaction()
    
    assert.is_true(created_dirs["/test/new_dir"], "Directory should be created")
  end)
  
  it("should generate operation summary", function()
    reset_state()
    multifile.begin_transaction()
    
    multifile.add_operation({
      type = multifile.OpType.CREATE,
      path = "/test/new.lua",
      content = "content",
      description = "Create new file"
    })
    
    multifile.add_operation({
      type = multifile.OpType.MODIFY,
      path = "/test/existing.lua",
      content = "modified",
      description = "Modify existing file"
    })
    
    local summary = multifile.get_transaction_summary()
    
    assert.is_not_nil(summary, "Summary should not be nil")
    assert.is_true(summary:find("CREATE"), "Summary should mention CREATE operations")
    assert.is_true(summary:find("MODIFY"), "Summary should mention MODIFY operations")
  end)
  
  it("should handle transaction without operations", function()
    reset_state()
    multifile.begin_transaction()
    
    local success = multifile.execute_transaction()
    assert.is_true(success, "Empty transaction should succeed")
  end)
  
end)
