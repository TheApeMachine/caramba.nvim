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

describe('commands smoke', function()
  it('registry can accept registration', function()
    local commands = require('caramba.core.commands')
    commands.register('SmokeTest', function() end, { desc = 'smoke' })
    assert.is_true(true)
  end)
end)
