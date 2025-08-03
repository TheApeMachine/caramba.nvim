-- Core command registration utility
-- Provides a centralized way to register commands and prevent duplicates.

local M = {}

M.commands = {}

--- Register a new command definition.
-- This function now just adds to a table, to be set up later.
-- @param name string The command name (e.g., "Chat", which becomes "CarambaChat").
-- @param func function The function to execute.
-- @param opts table? Optional vim.api.nvim_create_user_command options.
function M.register(name, func, opts)
  opts = opts or {}

  -- Ensure command starts with "Caramba"
  if not name:match("^Caramba") then
    name = "Caramba" .. name
  end

  if M.commands[name] then
    vim.notify(
      string.format("Command %s is already defined, overwriting. Original source: %s", name, M.commands[name].source),
      vim.log.levels.WARN
    )
  end

  M.commands[name] = {
    func = func,
    opts = opts,
    source = debug.getinfo(2, "S").source,
  }
end

--- Unregister a command by removing it from the registry and deleting the user command.
--- @param name string The command name (e.g., "CarambaChat").
function M.unregister(name)
  if not name:match("^Caramba") then
    name = "Caramba" .. name
  end

  if M.commands[name] then
    pcall(vim.api.nvim_del_user_command, name)
    M.commands[name] = nil
    return true
  end
  return false
end

--- Setup all registered commands.
-- This should be called once during plugin initialization.
M.setup = function()
  for name, cmd in pairs(M.commands) do
    local success, err = pcall(vim.api.nvim_create_user_command, name, cmd.func, cmd.opts or {})
    if not success then
      vim.notify(
        string.format("Failed to create command %s: %s", name, err),
        vim.log.levels.ERROR
      )
    end
  end
end

--- Get a list of all registered command definitions.
--- @return table
function M.list()
  local command_list = {}
  for name, info in pairs(M.commands) do
    table.insert(command_list, {
      name = name,
      desc = (info.opts and info.opts.desc) or "No description",
      source = info.source,
    })
  end
  table.sort(command_list, function(a, b)
    return a.name < b.name
  end)
  return command_list
end

--- Clear all registered commands.
-- Deletes the user commands and clears the internal registry.
-- Useful for hot-reloading and testing.
function M.clear()
  for name, _ in pairs(M.commands) do
    pcall(vim.api.nvim_del_user_command, name)
  end
  M.commands = {}
end

--- Print a formatted list of all registered commands for debugging.
function M.debug()
  local command_list = M.list()
  vim.notify(string.format("=== Registered Caramba Commands (%d) ===", #command_list))
  local lines = {}
  for _, cmd in ipairs(command_list) do
    table.insert(lines, string.format("%-30s %s", cmd.name, cmd.desc))
    table.insert(lines, string.format("  Source: %s", cmd.source))
  end
  print(table.concat(lines, "\n"))
end

return M