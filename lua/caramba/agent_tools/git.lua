-- Git-related tools exposed to the agent

local M = {}

local Job = require('plenary.job')
local logger = require('caramba.logger')
local utils = require('caramba.utils')
local edit = require('caramba.edit')

local function run(cmd, args, cwd, timeout_ms)
  local output, stderr, code = {}, {}, 0
  local job = Job:new({
    command = cmd,
    args = args,
    cwd = cwd or utils.get_project_root(),
    on_stdout = function(_, line)
      if line and line ~= '' then table.insert(output, line) end
    end,
    on_stderr = function(_, line)
      if line and line ~= '' then table.insert(stderr, line) end
    end,
    on_exit = function(_, c) code = c end,
  })
  local ok, err = pcall(function() job:sync(timeout_ms or 10000) end)
  if not ok then return nil, 'timeout' end
  if code ~= 0 then return nil, table.concat(stderr, '\n') end
  return table.concat(output, '\n'), nil
end

-- Tool schemas
M.tools = {
  {
    type = 'function',
    ["function"] = {
      name = 'git_diff_cached',
      description = 'Return current staged diff (git diff --cached)',
      parameters = { type = 'object', properties = {}, required = {} },
    },
  },
  {
    type = 'function',
    ["function"] = {
      name = 'git_branch_info',
      description = 'Return current and default origin branch names',
      parameters = { type = 'object', properties = {}, required = {} },
    },
  },
}

-- Implementations
M.fns = {
  git_diff_cached = function()
    local out, err = run('git', { 'diff', '--cached' })
    if err then return { error = err } end
    return { diff = out or '' }
  end,

  git_branch_info = function()
    local origin_head, err1 = run('sh', { '-c', "git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'" })
    if err1 then return { error = err1 } end
    local current, err2 = run('git', { 'branch', '--show-current' })
    if err2 then return { error = err2 } end
    return { base_branch = origin_head or '', current_branch = (current or ''):gsub('\n','') }
  end,
}

return M


