-- Tests for caramba.core.commands module
-- Comprehensive test suite covering command registration, execution, and management

-- Mock vim API for testing
_G.vim = {
  api = {
    nvim_create_user_command = function(name, func, opts)
      -- Store created commands for verification
      _G.vim._created_commands = _G.vim._created_commands or {}
      _G.vim._created_commands[name] = {func = func, opts = opts}
    end,
    nvim_del_user_command = function(name)
      if _G.vim._created_commands then
        _G.vim._created_commands[name] = nil
      end
    end,
  },
  log = {
    levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 }
  },
  notify = function(msg, level) 
    _G.vim._notifications = _G.vim._notifications or {}
    table.insert(_G.vim._notifications, {msg = msg, level = level})
  end,
  _created_commands = {},
  _notifications = {},
}

-- Mock debug module
_G.debug = {
  getinfo = function(level, what)
    return {
      source = "@test_file.lua"
    }
  end
}

-- Load the commands module
local commands = require('caramba.core.commands')

describe("caramba.core.commands", function()
  
  -- Reset state before each test
  local function reset_state()
    commands.clear()
    _G.vim._created_commands = {}
    _G.vim._notifications = {}
  end
  
  it("should register a command", function()
    reset_state()
    
    local test_func = function() return "test executed" end
    commands.register("Test", test_func, {desc = "Test command"})
    
    local command_list = commands.list()
    assert.equals(#command_list, 1, "Should have one registered command")
    assert.equals(command_list[1].name, "CarambaTest", "Should prefix with Caramba")
    assert.equals(command_list[1].desc, "Test command", "Should store description")
  end)
  
  it("should automatically prefix command names with Caramba", function()
    reset_state()
    
    local test_func = function() end
    commands.register("MyCommand", test_func)
    
    local command_list = commands.list()
    assert.equals(command_list[1].name, "CarambaMyCommand", "Should prefix with Caramba")
  end)
  
  it("should not double-prefix commands that already start with Caramba", function()
    reset_state()
    
    local test_func = function() end
    commands.register("CarambaExisting", test_func)
    
    local command_list = commands.list()
    assert.equals(command_list[1].name, "CarambaExisting", "Should not double-prefix")
  end)
  
  it("should warn when overwriting existing commands", function()
    reset_state()
    
    local func1 = function() return "first" end
    local func2 = function() return "second" end
    
    commands.register("Duplicate", func1)
    commands.register("Duplicate", func2)
    
    assert.equals(#_G.vim._notifications, 1, "Should have one warning notification")
    assert.is_true(_G.vim._notifications[1].msg:find("already defined"), "Should warn about overwrite")
  end)
  
  it("should setup all registered commands", function()
    reset_state()
    
    commands.register("First", function() end, {desc = "First command"})
    commands.register("Second", function() end, {desc = "Second command"})
    
    commands.setup()
    
    assert.is_not_nil(_G.vim._created_commands["CarambaFirst"], "Should create first command")
    assert.is_not_nil(_G.vim._created_commands["CarambaSecond"], "Should create second command")
  end)
  
  it("should unregister commands", function()
    reset_state()
    
    commands.register("ToRemove", function() end)
    commands.setup()
    
    local success = commands.unregister("ToRemove")
    assert.is_true(success, "Should successfully unregister")
    
    local command_list = commands.list()
    assert.equals(#command_list, 0, "Should have no commands after unregister")
  end)
  
  it("should handle unregistering non-existent commands", function()
    reset_state()
    
    local success = commands.unregister("NonExistent")
    assert.is_false(success, "Should return false for non-existent command")
  end)
  
  it("should list commands in alphabetical order", function()
    reset_state()
    
    commands.register("Zebra", function() end, {desc = "Z command"})
    commands.register("Alpha", function() end, {desc = "A command"})
    commands.register("Beta", function() end, {desc = "B command"})
    
    local command_list = commands.list()
    
    assert.equals(command_list[1].name, "CarambaAlpha", "First should be Alpha")
    assert.equals(command_list[2].name, "CarambaBeta", "Second should be Beta")
    assert.equals(command_list[3].name, "CarambaZebra", "Third should be Zebra")
  end)
  
  it("should include source information in command list", function()
    reset_state()
    
    commands.register("WithSource", function() end, {desc = "Test command"})
    
    local command_list = commands.list()
    assert.is_not_nil(command_list[1].source, "Should have source information")
    assert.is_true(command_list[1].source:find("test_file"), "Should include source file")
  end)
  
  it("should clear all commands", function()
    reset_state()
    
    commands.register("First", function() end)
    commands.register("Second", function() end)
    commands.setup()
    
    commands.clear()
    
    local command_list = commands.list()
    assert.equals(#command_list, 0, "Should have no commands after clear")
  end)
  
  it("should handle commands with no description", function()
    reset_state()
    
    commands.register("NoDesc", function() end)
    
    local command_list = commands.list()
    assert.equals(command_list[1].desc, "No description", "Should provide default description")
  end)
  
  it("should preserve command options", function()
    reset_state()
    
    local test_opts = {
      desc = "Test command",
      nargs = "*",
      complete = "file",
    }
    
    commands.register("WithOpts", function() end, test_opts)
    commands.setup()
    
    local created_cmd = _G.vim._created_commands["CarambaWithOpts"]
    assert.is_not_nil(created_cmd, "Command should be created")
    assert.equals(created_cmd.opts.desc, "Test command", "Should preserve description")
    assert.equals(created_cmd.opts.nargs, "*", "Should preserve nargs")
    assert.equals(created_cmd.opts.complete, "file", "Should preserve completion")
  end)
  
  it("should execute registered command function", function()
    reset_state()
    
    local executed = false
    local test_func = function() executed = true end
    
    commands.register("Execute", test_func)
    commands.setup()
    
    local created_cmd = _G.vim._created_commands["CarambaExecute"]
    created_cmd.func()
    
    assert.is_true(executed, "Command function should be executed")
  end)
  
  it("should handle command registration errors gracefully", function()
    reset_state()
    
    -- Mock vim.api.nvim_create_user_command to throw error
    local original_create = _G.vim.api.nvim_create_user_command
    _G.vim.api.nvim_create_user_command = function(name, func, opts)
      error("Mock command creation error")
    end
    
    commands.register("ErrorTest", function() end)
    
    -- Should not throw error during setup
    local success, err = pcall(commands.setup)
    assert.is_true(success, "Setup should handle command creation errors")
    
    -- Restore original function
    _G.vim.api.nvim_create_user_command = original_create
  end)
  
  it("should handle command deletion errors gracefully", function()
    reset_state()
    
    commands.register("DeleteTest", function() end)
    
    -- Mock vim.api.nvim_del_user_command to throw error
    local original_delete = _G.vim.api.nvim_del_user_command
    _G.vim.api.nvim_del_user_command = function(name)
      error("Mock command deletion error")
    end
    
    -- Should not throw error during unregister
    local success, err = pcall(commands.unregister, "DeleteTest")
    assert.is_true(success, "Unregister should handle deletion errors")
    
    -- Restore original function
    _G.vim.api.nvim_del_user_command = original_delete
  end)
  
  it("should maintain command registry state", function()
    reset_state()
    
    commands.register("Persistent", function() end, {desc = "Persistent command"})
    
    -- Simulate plugin reload
    local command_list_before = commands.list()
    
    -- Commands should still be registered
    local command_list_after = commands.list()
    
    assert.equals(#command_list_before, #command_list_after, "Command count should be preserved")
    assert.equals(command_list_before[1].name, command_list_after[1].name, "Command name should be preserved")
  end)
  
  it("should support command function with arguments", function()
    reset_state()
    
    -- Ensure the mock function is working properly
    _G.vim.api.nvim_create_user_command = function(name, func, opts)
      _G.vim._created_commands = _G.vim._created_commands or {}
      _G.vim._created_commands[name] = {func = func, opts = opts}
    end
    
    local received_args = nil
    local test_func = function(args) received_args = args end
    
    commands.register("WithArgs", test_func, {nargs = "*"})
    commands.setup()
    
    local created_cmd = _G.vim._created_commands["CarambaWithArgs"]
    created_cmd.func({args = "test arguments"})
    
    assert.is_not_nil(received_args, "Function should receive arguments")
  end)
  
end)
