-- Core command registration utility
-- Provides a centralized way to register commands and prevent duplicates

local M = {}

-- Track registered commands to prevent duplicates
M.registered_commands = {}

--- Register a user command with duplicate prevention
---@param name string The command name (without "AI" prefix)
---@param handler function The function to call when the command is executed
---@param opts table? Optional vim.api.nvim_create_user_command options
function M.register(name, handler, opts)
  -- Ensure command starts with "AI"
  if not name:match("^AI") then
    name = "AI" .. name
  end
  
  -- Check if command is already registered
  if M.registered_commands[name] then
    vim.notify(string.format("Command %s is already registered, skipping duplicate registration", name), vim.log.levels.WARN)
    return false
  end
  
  -- Default options
  opts = opts or {}
  
  -- Register the command
  local ok, err = pcall(vim.api.nvim_create_user_command, name, handler, opts)
  if ok then
    M.registered_commands[name] = {
      handler = handler,
      opts = opts,
      source = debug.getinfo(2, "S").source
    }
    return true
  else
    vim.notify(string.format("Failed to register command %s: %s", name, err), vim.log.levels.ERROR)
    return false
  end
end

--- Unregister a command
---@param name string The command name
function M.unregister(name)
  if not name:match("^AI") then
    name = "AI" .. name
  end
  
  if M.registered_commands[name] then
    pcall(vim.api.nvim_del_user_command, name)
    M.registered_commands[name] = nil
    return true
  end
  return false
end

--- Get list of all registered commands
---@return table
function M.list()
  local commands = {}
  for name, info in pairs(M.registered_commands) do
    table.insert(commands, {
      name = name,
      desc = info.opts.desc or "No description",
      source = info.source
    })
  end
  table.sort(commands, function(a, b) return a.name < b.name end)
  return commands
end

--- Clear all registered commands (useful for testing)
function M.clear()
  for name, _ in pairs(M.registered_commands) do
    pcall(vim.api.nvim_del_user_command, name)
  end
  M.registered_commands = {}
end

--- Debug: Show all registered commands
function M.debug()
  local commands = M.list()
  print(string.format("=== Registered AI Commands (%d) ===", #commands))
  for _, cmd in ipairs(commands) do
    print(string.format("%-30s %s", cmd.name, cmd.desc))
    print(string.format("  Source: %s", cmd.source))
  end
end

-- Centralized Command Registry

M.commands = {}

-- Register a new command
M.register = function(name, func, opts)
  opts = opts or {}
  
  M.commands[name] = {
    func = func,
    opts = {
      desc = opts.desc,
      nargs = opts.nargs,
      range = opts.range,
      complete = opts.complete,
    }
  }
end

-- Setup all registered commands
M.setup = function()
  for name, cmd in pairs(M.commands) do
    vim.api.nvim_create_user_command(name, cmd.func, cmd.opts)
  end
end

-- Function to load all command definitions
M.load_all = function()
  -- Core commands
  require('caramba.llm').setup_commands()
  require('caramba.chat').setup_commands()
  require('caramba.refactor').setup_commands()
  require('caramba.planner').setup_commands()
  require('caramba.pair').setup_commands()
  require('caramba.consistency').setup_commands()
  -- Add other modules with commands here
end

return M 