-- Minimal init for testing - avoid all Neovim internals
vim.opt.runtimepath:prepend('.')
vim.opt.packpath = ''

-- Disable all built-in plugins
local disabled_built_ins = {
  "netrw", "netrwPlugin", "netrwSettings", "netrwFileHandlers",
  "gzip", "zip", "zipPlugin", "tar", "tarPlugin", "getscript", "getscriptPlugin",
  "vimball", "vimballPlugin", "2html_plugin", "logipat", "rrhelper",
  "spellfile_plugin", "matchit", "matchparen", "shada_plugin", "tutor_mode_plugin"
}

for _, plugin in pairs(disabled_built_ins) do
  vim.g["loaded_" .. plugin] = 1
end

-- Set up paths
local current_dir = vim.fn.getcwd()
package.path = package.path .. ";" .. current_dir .. "/lua/?.lua"
package.path = package.path .. ";" .. current_dir .. "/tests/?.lua"