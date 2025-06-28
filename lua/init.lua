-- AI Assistant for Neovim
local M = {}

-- Health check support
M.health = require('ai.health')

-- Load all modules
local modules = {
  'ai.config',
  'ai.context', 
  'ai.llm',
  'ai.edit',
  'ai.refactor',
  'ai.search',
  'ai.embeddings',
  'ai.planner',
  'ai.commands',
  'ai.chat',
  'ai.multifile',
  'ai.testing',
  'ai.debug',
  'ai.websearch',
  'ai.tools',
  'ai.ast_transform',
  'ai.intelligence',
  'ai.pair',
  'ai.git',
  'ai.tdd',
  'ai.consistency',
}

for _, module in ipairs(modules) do
  local ok, err = pcall(require, module)
  if not ok then
    vim.notify('Failed to load ' .. module .. ': ' .. err, vim.log.levels.ERROR)
  end
end

-- Export modules
M.config = require('ai.config')
M.context = require('ai.context')
M.llm = require('ai.llm')
M.edit = require('ai.edit')
M.refactor = require('ai.refactor')
M.search = require('ai.search')
M.planner = require('ai.planner')
M.embeddings = require('ai.embeddings')
M.chat = require('ai.chat')
M.multifile = require('ai.multifile')
M.testing = require('ai.testing')
M.debug = require('ai.debug')
M.websearch = require('ai.websearch')
M.tools = require('ai.tools')
M.ast_transform = require('ai.ast_transform')
M.intelligence = require('ai.intelligence')
M.pair = require('ai.pair')
M.git = require('ai.git')
M.commands = require('ai.commands')
M.tdd = require('ai.tdd')
M.consistency = require('ai.consistency')

-- Initialize the module
function M.setup(opts)
  -- Merge user options with defaults
  M.config.setup(opts)
  
  -- Setup planner
  M.planner.setup()
  
  -- Setup commands
  M.commands.setup()
  
  -- Initialize search index if enabled
  local search = require('ai.search')
  if M.config.get().search.index_on_startup then
    vim.defer_fn(function()
      search.index_workspace()
    end, 1000) -- Wait 1 second after startup
  end
  
  -- Set up autocommands
  local context = require('ai.context')
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