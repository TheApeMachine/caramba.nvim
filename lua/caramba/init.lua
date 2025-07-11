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
  
  vim.notify("Caramba.nvim is ready!", vim.log.levels.INFO)
end

return M 