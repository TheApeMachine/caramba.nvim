-- Centralized state store for Caramba

local M = {}

M.store = {
  chat = {},
  planner = {},
  pair = {},
  intelligence = {},
  memory = {},
}

function M.get()
  return M.store
end

function M.set_namespace(ns, tbl)
  M.store[ns] = tbl
end

function M.update(ns, key, value)
  M.store[ns] = M.store[ns] or {}
  M.store[ns][key] = value
end

return M


