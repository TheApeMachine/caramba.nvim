-- Simple file logger for Caramba
-- Writes to a log file in the project root when enabled

local M = {}

-- luacheck: globals vim
local vim = vim

local config = require('caramba.config')
local utils = require('caramba.utils')

local function is_enabled()
  local cfg = config.get() or {}
  if cfg.logging and cfg.logging.file ~= nil then
    return cfg.logging.file
  end
  return cfg.debug == true
end

local function log_path()
  local root = utils.get_project_root()
  return root .. '/.caramba-debug.log'
end

local function timestamp()
  return os.date('%Y-%m-%d %H:%M:%S')
end

function M.log(tag, msg)
  if not is_enabled() then return end
  local ok, fh = pcall(io.open, log_path(), 'a')
  if not ok or not fh then return end
  local line = string.format('[%s] [%s] %s\n', timestamp(), tag or 'log', tostring(msg))
  pcall(function()
    fh:write(line)
    fh:close()
  end)
end

function M.log_table(tag, tbl)
  if not is_enabled() then return end
  local ok, serialized = pcall(vim.inspect, tbl)
  if ok then
    M.log(tag, serialized)
  else
    M.log(tag, '<inspect failed>')
  end
end

return M
