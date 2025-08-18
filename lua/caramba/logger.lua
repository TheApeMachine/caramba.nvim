-- Caramba file-based logger
-- Minimal dependency, append-only with simple rotation

local M = {}

local utils = require('caramba.utils')
local config = require('caramba.config')

M._initialized = false
M._level_map = { trace = 1, debug = 2, info = 3, warn = 4, error = 5 }
M._level = 2 -- default debug
M._path = nil
M._max_size = 1024 * 1024 * 2 -- 2MB

local function ensure_parent_dir(path)
  local dir = path:match("^(.*)/[^/]+$")
  if dir and not utils.dir_exists(dir) then
    vim.fn.mkdir(dir, 'p')
  end
end

local function rotate_if_needed()
  if not M._path then return end
  local stat = vim.loop.fs_stat(M._path)
  if stat and stat.size and stat.size > M._max_size then
    local backup = M._path .. ".1"
    pcall(vim.loop.fs_unlink, backup)
    pcall(vim.loop.fs_rename, M._path, backup)
  end
end

local function timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

function M.setup()
  local cfg = config.get() or {}
  local log_cfg = (cfg.logging or {})

  M._level = M._level_map[(log_cfg.level or (cfg.debug and 'debug' or 'info'))] or 2
  M._max_size = tonumber(log_cfg.max_size_bytes or M._max_size)

  if log_cfg.path and #tostring(log_cfg.path) > 0 then
    M._path = log_cfg.path
  else
    local root = utils.get_project_root()
    M._path = root .. '/.caramba-debug.log'
  end

  ensure_parent_dir(M._path)
  M._initialized = true

  -- Initial banner
  M.info('Logger initialized', { path = M._path, level = log_cfg.level or 'debug' })
end

local function to_string(v)
  if v == nil then return '' end
  if type(v) == 'string' then return v end
  local ok, s = pcall(vim.inspect, v)
  return ok and s or tostring(v)
end

local function write_line(line)
  if not M._initialized then return end
  local ok, f = pcall(io.open, M._path, 'a')
  if not ok or not f then return end
  f:write(line .. "\n")
  f:close()
end

function M._log(level_name, msg, data)
  if not M._initialized then return end
  local lvl = M._level_map[level_name] or 3
  if lvl < M._level then return end
  rotate_if_needed()
  local line = string.format('[%s] %-5s %s', timestamp(), level_name:upper(), tostring(msg or ''))
  if data ~= nil then
    line = line .. ' | ' .. to_string(data)
  end
  write_line(line)
end

function M.trace(msg, data) M._log('trace', msg, data) end
function M.debug(msg, data) M._log('debug', msg, data) end
function M.info(msg, data)  M._log('info',  msg, data) end
function M.warn(msg, data)  M._log('warn',  msg, data) end
function M.error(msg, data) M._log('error', msg, data) end

return M


