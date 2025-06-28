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

-- Initialize the module
function M.setup(opts)
  -- Merge user options with defaults
  M.config.setup(opts)
  
  -- Setup planner
  M.planner.setup()
  
  -- Setup commands
  M.commands.setup()
  
  -- Initialize search index if enabled
  local search = require('caramba.search')
  if M.config.get().search.index_on_startup then
    vim.defer_fn(function()
      search.index_workspace()
    end, 1000) -- Wait 1 second after startup
  end
  
  -- Set up autocommands
  local context = require('caramba.context')
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "BufEnter"}, {
    group = vim.api.nvim_create_augroup("AIContext", { clear = true }),
    callback = function()
      -- Update cursor context in the background
      vim.defer_fn(function()
        context.update_cursor_context()
      end, 100) -- Small delay to avoid too frequent updates
    end,
  })
  
  -- Initialize sub-modules that have setup functions
  if M.consistency.setup then
    M.consistency.setup()
  end
  
  -- Create WhichKey mappings
  local ok, which_key = pcall(require, 'which-key')
  if ok then
    which_key.register({
      ['<leader>a'] = {
        name = '+AI',
        c = { '<cmd>AIComplete<cr>', 'Complete code' },
        e = { '<cmd>AIExplain<cr>', 'Explain code' },
        r = { '<cmd>AIRefactor<cr>', 'Refactor code' },
        s = { '<cmd>AISearch<cr>', 'Search code' },
        p = { '<cmd>AIPlan<cr>', 'Plan implementation' },
        t = { '<cmd>AIChat<cr>', 'Open chat' },
        g = { '<cmd>AIGenerateTests<cr>', 'Generate tests' },
        d = { '<cmd>AIDebugError<cr>', 'Debug error' },
        m = { '<cmd>AICommitMessage<cr>', 'Generate commit message' },
        w = { '<cmd>AIWebSearch<cr>', 'Web search' },
        q = { '<cmd>AIQuery<cr>', 'Query with tools' },
        x = { '<cmd>AITransform<cr>', 'Transform code' },
        i = { '<cmd>AIImplementFromTest<cr>', 'Implement from test' },
        o = { '<cmd>AICheckConsistency<cr>', 'Check consistency' },
      }
    }, { mode = 'n' })
  end
  
  vim.notify("AI Assistant initialized", vim.log.levels.INFO)
end

return M 