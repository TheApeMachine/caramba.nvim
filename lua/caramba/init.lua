-- AI Assistant for Neovim
local M = {}

-- Health check support
M.health = require('caramba.health')

-- Load all modules
local modules = {
  'caramba.config',
  'caramba.context', 
  'caramba.llm',
  'caramba.edit',
  'caramba.refactor',
  'caramba.search',
  'caramba.embeddings',
  'caramba.planner',
  'caramba.commands',
  'caramba.chat',
  'caramba.multifile',
  'caramba.testing',
  'caramba.debug',
  'caramba.websearch',
  'caramba.tools',
  'caramba.ast_transform',
  'caramba.intelligence',
  'caramba.pair',
  'caramba.git',
  'caramba.tdd',
  'caramba.consistency',
}

for _, module in ipairs(modules) do
  local ok, err = pcall(require, module)
  if not ok then
    vim.notify('Failed to load ' .. module .. ': ' .. err, vim.log.levels.ERROR)
  end
end

-- Export modules
M.config = require('caramba.config')
M.context = require('caramba.context')
M.llm = require('caramba.llm')
M.edit = require('caramba.edit')
M.refactor = require('caramba.refactor')
M.search = require('caramba.search')
M.planner = require('caramba.planner')
M.embeddings = require('caramba.embeddings')
M.chat = require('caramba.chat')
M.multifile = require('caramba.multifile')
M.testing = require('caramba.testing')
M.debug = require('caramba.debug')
M.websearch = require('caramba.websearch')
M.tools = require('caramba.tools')
M.ast_transform = require('caramba.ast_transform')
M.intelligence = require('caramba.intelligence')
M.pair = require('caramba.pair')
M.git = require('caramba.git')
M.commands = require('caramba.commands')
M.tdd = require('caramba.tdd')
M.consistency = require('caramba.consistency')

-- Main setup function
function M.setup(opts)
  -- Load configuration
  require('caramba.config').setup(opts)
  
  -- Load all commands
  local commands = require('caramba.core.commands')
  commands.load_all()
  commands.setup()
  
  -- Initialize other modules as needed
  require('caramba.planner').setup()
  require('caramba.consistency').setup()
  
  vim.notify("Caramba.nvim is ready!", vim.log.levels.INFO)
end

return M 