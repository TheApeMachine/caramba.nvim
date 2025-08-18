-- Caramba for Neovim
local M = {}

-- Health check support
M.health = require('caramba.health')

-- All modules to be loaded
local modules = {
  "ast_transform",
  "chat",
  "config",
  "consistency",
  "context",
  "core.commands",
  "debug",
  "edit",
  "embeddings",
  "git",
  "health",
  "logger",
  "intelligence",
  "llm",
  "multifile",
  "pair",
  "planner",
  "refactor",
  "search",
  "tdd",
  "testing",
  "tools",
  "utils",
  "websearch",
  "commands",
}

-- Main setup function
function M.setup(opts)
  -- 1. Setup configuration first
  require('caramba.config').setup(opts)
  -- Initialize logger early so other modules can use it
  pcall(function() require('caramba.logger').setup() end)
  -- Initialize global state namespace for easy debugging
  _G.caramba = _G.caramba or {}
  _G.caramba.state = require('caramba.state').get()

  -- 2. Load all modules and register their commands
  for _, name in ipairs(modules) do
    local ok, mod = pcall(require, "caramba." .. name)
    if ok and mod and mod.setup_commands then
      pcall(mod.setup_commands)
    elseif not ok then
      vim.notify("Failed to load module: " .. name .. "\n" .. tostring(mod), vim.log.levels.ERROR)
    end
  end

  -- 3. Create the user commands from the registry
  require('caramba.core.commands').setup()

  -- 4. Initialize other modules that require it
  require('caramba.planner').setup()
  require('caramba.consistency').setup()
  require('caramba.chat').setup()
  -- Optional: Telescope helpers (registered as commands even if Telescope absent)
  pcall(function()
    require('caramba.telescope').setup_commands()
  end)

  vim.notify("Caramba.nvim is ready!", vim.log.levels.INFO)
end

-- Canonicalize module aliases to avoid duplicate-require warnings
package.loaded['caramba'] = M
package.loaded['caramba.init'] = M

return M