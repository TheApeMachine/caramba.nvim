-- Plenary+busted Neovim init for reliable tests

-- Ensure plugin and bundled plenary are on runtimepath
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.runtimepath:prepend(root)

-- Use bundled plenary if available (tests/plenary.nvim)
local bundled_plenary = root .. "/tests/plenary.nvim"
if vim.fn.isdirectory(bundled_plenary) == 1 then
  vim.opt.runtimepath:append(bundled_plenary)
end

-- Basic settings to keep headless stable
vim.o.swapfile = false
vim.o.shadafile = 'NONE'
vim.cmd('filetype plugin indent on')

-- Provide a stub for nvim-treesitter.parsers to avoid hard dependency in CI
do
  local stub = {
    has_parser = function() return false end,
    get_parser = function() return nil end,
    get_parser_configs = function() return {} end,
    available_parsers = function() return {} end,
    get_buf_lang = function() return vim.bo.filetype or 'lua' end,
  }
  package.loaded['nvim-treesitter.parsers'] = package.loaded['nvim-treesitter.parsers'] or stub
  package.preload['nvim-treesitter.parsers'] = package.preload['nvim-treesitter.parsers'] or function() return stub end
  -- Also stub the top-level nvim-treesitter module if referenced
  package.loaded['nvim-treesitter'] = package.loaded['nvim-treesitter'] or {}
  package.preload['nvim-treesitter'] = package.preload['nvim-treesitter'] or function() return {} end
end

-- Polyfills for older Neovim versions used in CI
if not vim.deepcopy then
  local function _deepcopy(val, visited)
    if type(val) ~= 'table' then return val end
    if visited[val] then return visited[val] end
    local copy = {}
    visited[val] = copy
    for k, v in pairs(val) do
      copy[_deepcopy(k, visited)] = _deepcopy(v, visited)
    end
    return copy
  end
  vim.deepcopy = function(t) return _deepcopy(t, {}) end
end
if not vim.api.nvim__get_runtime then
  vim.api.nvim__get_runtime = function(path, all, _)
    return vim.api.nvim_get_runtime_file(path or '', all ~= false)
  end
end

-- Minimal Caramba setup for commands only (avoid heavy module init)
local ok_cfg, cfg = pcall(require, 'caramba.config')
if ok_cfg and cfg and cfg.setup then
  cfg.setup({
    debug = false,
    features = { auto_install_parsers = false },
    ui = { stream_window = false },
    api = { openai = { api_key = 'test', model = 'gpt-4o-mini' } },
  })
end

-- Register only the commands needed by integration tests
pcall(function() require('caramba.commands').setup_commands() end)
pcall(function() require('caramba.chat').setup_commands() end)
pcall(function() require('caramba.core.commands').setup() end)

-- Silence notifications during tests
vim.notify = function(_) end


