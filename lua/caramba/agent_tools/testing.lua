-- Testing-related tools (shell out to user test runner)

local M = {}
local Job = require('plenary.job')
local utils = require('caramba.utils')

local function run(cmdline, timeout_ms)
  local output, stderr, code = {}, {}, 0
  local job = Job:new({
    command = 'sh',
    args = { '-c', cmdline },
    cwd = utils.get_project_root(),
    on_stdout = function(_, line) if line and line ~= '' then table.insert(output, line) end end,
    on_stderr = function(_, line) if line and line ~= '' then table.insert(stderr, line) end end,
    on_exit   = function(_, c) code = c end,
  })
  local ok = pcall(function() job:sync(timeout_ms or 20000) end)
  if not ok then return nil, 'timeout' end
  if code ~= 0 then return nil, table.concat(stderr, '\n') end
  return table.concat(output, '\n'), nil
end

M.tools = {
  {
    type = 'function',
    ["function"] = {
      name = 'run_tests_quick',
      description = 'Run quick tests (project-specific fast suite)',
      parameters = { type = 'object', properties = {}, required = {} },
    }
  },
}

M.fns = {
  run_tests_quick = function()
    -- Heuristic: prefer repo script if present, else try `npm test -s` or `pytest -q`
    local root = utils.get_project_root()
    local script = nil
    if vim.fn.filereadable(root .. '/test.sh') == 1 then
      script = './test.sh'
    elseif vim.fn.filereadable(root .. '/package.json') == 1 then
      script = 'npm test -s'
    else
      script = 'pytest -q'
    end
    local out, err = run(script)
    if err then return { error = err } end
    return { output = out or '' }
  end,
}

return M


