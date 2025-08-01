-- This is a rockspec for Caramba.nvim, used for development and testing.
-- It's not intended for package distribution on LuaRocks.

rockspec_format = "3.0"

package = "caramba-nvim"
version = "dev-1"
source = {
  url = "git://github.com/theapemachine/caramba.nvim",
}
description = {
  summary = "AI-powered development assistant for Neovim",
  homepage = "https://github.com/theapemachine/caramba.nvim",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
}
test_dependencies = {
  "busted",
  "luacheck",
  "lua-cjson",
}
build = {
  type = "builtin",
  modules = {},
} 