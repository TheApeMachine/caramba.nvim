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

  -- 2. Load all modules and register their commands (chat-first; optionally restrict command surface)
  local cfg = require('caramba.config').get()
  local allowlist = {}
  if cfg.commands and cfg.commands.allowed then
    for _, n in ipairs(cfg.commands.allowed) do allowlist[n] = true end
  end

  for _, name in ipairs(modules) do
    local ok, mod = pcall(require, "caramba." .. name)
    if ok and mod and mod.setup_commands then
      if cfg.commands and cfg.commands.enable_legacy_commands == false then
        -- Wrap registration to enforce allowlist
        local core = require('caramba.core.commands')
        local original_register = core.register
        core.register = function(cmd_name, func, opts)
          -- Normalize to Caramba* prefix per core.commands
          local normalized = cmd_name
          if not normalized:match("^Caramba") then normalized = "Caramba" .. normalized end
          if allowlist[normalized] then
            return original_register(cmd_name, func, opts)
          else
            -- Skip registering this command
            return
          end
        end
        pcall(mod.setup_commands)
        core.register = original_register
      else
        pcall(mod.setup_commands)
      end
    elseif not ok then
      vim.notify("Failed to load module: " .. name .. "\n" .. tostring(mod), vim.log.levels.ERROR)
    end
  end

  -- 3. Create the user commands from the registry
  require('caramba.core.commands').setup()

  -- 4. Initialize other modules that require it
  require('caramba.planner').setup()
  require('caramba.consistency').setup()
  -- Warm vector store on startup (non-blocking)
  pcall(function() require('caramba.orchestrator').warm_vector_store() end)
  require('caramba.chat').setup()
  -- Optional: Telescope helpers (registered as commands even if Telescope absent)
  pcall(function()
    require('caramba.telescope').setup_commands()
  end)

  -- Create a root alias :Caramba to open chat directly
  local core = require('caramba.core.commands')
  core.register('Caramba', function()
    require('caramba.chat').open()
  end, { desc = 'Open Caramba chat' })

  vim.notify("Caramba.nvim is ready!", vim.log.levels.INFO)
end

-- Canonicalize module aliases to avoid duplicate-require warnings
package.loaded['caramba'] = M
package.loaded['caramba.init'] = M

return M