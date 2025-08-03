-- Caramba.nvim plugin initialization
-- Sets up default keymaps and integrations

-- Prevent loading twice
if vim.g.loaded_caramba then
  return
end
vim.g.loaded_caramba = 1

-- Set up default keymaps under <leader>a prefix
local function setup_default_keymaps()
  local opts = { noremap = true, silent = true }
  
  -- Core commands
  vim.keymap.set('n', '<leader>ac', ':CarambaComplete<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Complete code' }))
  vim.keymap.set('v', '<leader>ae', ':CarambaExplain<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Explain code' }))
  vim.keymap.set('n', '<leader>ar', ':CarambaRefactor<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Refactor code' }))
  vim.keymap.set('n', '<leader>as', ':CarambaSearch<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Search code' }))
  vim.keymap.set('n', '<leader>ap', ':CarambaPlan<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Plan implementation' }))
  vim.keymap.set('n', '<leader>at', ':CarambaChat<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Open chat' }))
  
  -- Testing & TDD
  vim.keymap.set('n', '<leader>ag', ':CarambaGenerateTests<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Generate tests' }))
  vim.keymap.set('n', '<leader>ai', ':CarambaImplementFromTest<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Implement from test' }))
  
  -- Git integration
  vim.keymap.set('n', '<leader>am', ':CarambaCommitMessage<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Generate commit message' }))
  
  -- Web search & tools
  vim.keymap.set('n', '<leader>aw', ':CarambaWebSearch<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Web search' }))
  vim.keymap.set('n', '<leader>aq', ':CarambaQuery<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Query with tools' }))
  
  -- Code intelligence
  vim.keymap.set('n', '<leader>ax', ':CarambaTransform<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Transform code' }))
  vim.keymap.set('n', '<leader>ao', ':CarambaCheckConsistency<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Check consistency' }))
  
  -- Project intelligence
  vim.keymap.set('n', '<leader>aI', ':CarambaIndexProject<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Index project' }))
  vim.keymap.set('n', '<leader>aF', ':CarambaFindSymbol<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Find symbol' }))
  vim.keymap.set('n', '<leader>aM', ':CarambaProjectMap<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Show project map' }))
  
  -- Utility commands
  vim.keymap.set('n', '<leader>aC', ':CarambaCancel<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Cancel operations' }))
  vim.keymap.set('n', '<leader>aS', ':CarambaShowCommands<CR>', vim.tbl_extend('force', opts, { desc = 'Caramba: Show all commands' }))
end

-- Set up WhichKey integration if available
local function setup_which_key()
  local ok, wk = pcall(require, 'which-key')
  if not ok then
    return
  end
  
  wk.register({
    a = {
      name = "Caramba AI Assistant",
      c = { ':CarambaComplete<CR>', 'Complete code' },
      e = { ':CarambaExplain<CR>', 'Explain code' },
      r = { ':CarambaRefactor<CR>', 'Refactor code' },
      s = { ':CarambaSearch<CR>', 'Search code' },
      p = { ':CarambaPlan<CR>', 'Plan implementation' },
      t = { ':CarambaChat<CR>', 'Open chat' },
      g = { ':CarambaGenerateTests<CR>', 'Generate tests' },
      i = { ':CarambaImplementFromTest<CR>', 'Implement from test' },
      m = { ':CarambaCommitMessage<CR>', 'Generate commit message' },
      w = { ':CarambaWebSearch<CR>', 'Web search' },
      q = { ':CarambaQuery<CR>', 'Query with tools' },
      x = { ':CarambaTransform<CR>', 'Transform code' },
      o = { ':CarambaCheckConsistency<CR>', 'Check consistency' },
      I = { ':CarambaIndexProject<CR>', 'Index project' },
      F = { ':CarambaFindSymbol<CR>', 'Find symbol' },
      M = { ':CarambaProjectMap<CR>', 'Show project map' },
      C = { ':CarambaCancel<CR>', 'Cancel operations' },
      S = { ':CarambaShowCommands<CR>', 'Show all commands' },
    }
  }, { prefix = '<leader>' })
end

-- Set up health check command
vim.api.nvim_create_user_command('CarambaHealth', function()
  vim.cmd('checkhealth caramba')
end, { desc = 'Run Caramba health check' })

-- Auto-setup keymaps when plugin loads
vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    setup_default_keymaps()
    setup_which_key()
  end,
  desc = 'Setup Caramba keymaps'
})
