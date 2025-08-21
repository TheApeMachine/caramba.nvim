-- Agent Tools Registry
-- Small, focused tool modules that expose non-LLM side effects/data for chat-first workflows

local M = {}

-- Each submodule returns { tools = <openai tool schemas>, fns = <name->impl> }
local function safe_require(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
  return { tools = {}, fns = {} }
end

function M.collect_all()
  local modules = {
    safe_require('caramba.agent_tools.git'),
    safe_require('caramba.agent_tools.testing'),
    safe_require('caramba.agent_tools.files'),
  }

  local tools = {}
  local fns = {}
  for _, m in ipairs(modules) do
    if type(m.tools) == 'table' then
      for _, t in ipairs(m.tools) do table.insert(tools, t) end
    end
    if type(m.fns) == 'table' then
      for k, v in pairs(m.fns) do fns[k] = v end
    end
  end
  return tools, fns
end

return M


