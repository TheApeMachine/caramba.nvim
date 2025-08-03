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

  -- Use the new which-key v3 API (recommended)
  if wk.add then
    -- Only add if not already registered to avoid duplicates
    local success, _ = pcall(wk.add, {
      { "<leader>a", group = "Caramba" },
      { "<leader>ac", ":CarambaComplete<CR>", desc = "Complete code" },
      { "<leader>ae", ":CarambaExplain<CR>", desc = "Explain code" },
      { "<leader>ar", ":CarambaRefactor<CR>", desc = "Refactor code" },
      { "<leader>as", ":CarambaSearch<CR>", desc = "Search code" },
      { "<leader>ap", ":CarambaPlan<CR>", desc = "Plan implementation" },
      { "<leader>at", ":CarambaChat<CR>", desc = "Open chat" },
      { "<leader>ag", ":CarambaGenerateTests<CR>", desc = "Generate tests" },
      { "<leader>ai", ":CarambaImplementFromTest<CR>", desc = "Implement from test" },
      { "<leader>am", ":CarambaCommitMessage<CR>", desc = "Generate commit message" },
      { "<leader>aw", ":CarambaWebSearch<CR>", desc = "Web search" },
      { "<leader>aq", ":CarambaQuery<CR>", desc = "Query with tools" },
      { "<leader>ax", ":CarambaTransform<CR>", desc = "Transform code" },
      { "<leader>ao", ":CarambaCheckConsistency<CR>", desc = "Check consistency" },
      { "<leader>aI", ":CarambaIndexProject<CR>", desc = "Index project" },
      { "<leader>aF", ":CarambaFindSymbol<CR>", desc = "Find symbol" },
      { "<leader>aM", ":CarambaProjectMap<CR>", desc = "Show project map" },
      { "<leader>aC", ":CarambaCancel<CR>", desc = "Cancel operations" },
      { "<leader>aS", ":CarambaShowCommands<CR>", desc = "Show all commands" },
    })

    if not success then
      -- Fallback: just register individual commands without group
      pcall(wk.add, {
        { "<leader>ac", ":CarambaComplete<CR>", desc = "Caramba: Complete code" },
        { "<leader>ae", ":CarambaExplain<CR>", desc = "Caramba: Explain code" },
        { "<leader>ar", ":CarambaRefactor<CR>", desc = "Caramba: Refactor code" },
        { "<leader>as", ":CarambaSearch<CR>", desc = "Caramba: Search code" },
        { "<leader>ap", ":CarambaPlan<CR>", desc = "Caramba: Plan implementation" },
        { "<leader>at", ":CarambaChat<CR>", desc = "Caramba: Open chat" },
        { "<leader>ag", ":CarambaGenerateTests<CR>", desc = "Caramba: Generate tests" },
        { "<leader>ai", ":CarambaImplementFromTest<CR>", desc = "Caramba: Implement from test" },
        { "<leader>am", ":CarambaCommitMessage<CR>", desc = "Caramba: Generate commit message" },
        { "<leader>aw", ":CarambaWebSearch<CR>", desc = "Caramba: Web search" },
        { "<leader>aq", ":CarambaQuery<CR>", desc = "Caramba: Query with tools" },
        { "<leader>ax", ":CarambaTransform<CR>", desc = "Caramba: Transform code" },
        { "<leader>ao", ":CarambaCheckConsistency<CR>", desc = "Caramba: Check consistency" },
        { "<leader>aI", ":CarambaIndexProject<CR>", desc = "Caramba: Index project" },
        { "<leader>aF", ":CarambaFindSymbol<CR>", desc = "Caramba: Find symbol" },
        { "<leader>aM", ":CarambaProjectMap<CR>", desc = "Caramba: Show project map" },
        { "<leader>aC", ":CarambaCancel<CR>", desc = "Caramba: Cancel operations" },
        { "<leader>aS", ":CarambaShowCommands<CR>", desc = "Caramba: Show all commands" },
      })
    end
  end
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
