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
  {
    type = 'function',
    ["function"] = {
      name = 'git_status',
      description = 'Return porcelain git status for the repo',
      parameters = { type = 'object', properties = {}, required = {} },
    },
  },
  {
    type = 'function',
    ["function"] = {
      name = 'git_diff_range',
      description = 'Return diff for base..head (optionally limited to a path)',
      parameters = {
        type = 'object',
        properties = {
          base = { type = 'string', description = 'Base ref (default: origin/HEAD)' },
          head = { type = 'string', description = 'Head ref (default: HEAD)' },
          path = { type = 'string', description = 'Optional path to limit diff' },
        },
        required = {},
      },
    },
  },
  {
    type = 'function',
    ["function"] = {
      name = 'git_stage_files',
      description = 'Stage a list of files (git add)',
      parameters = {
        type = 'object',
        properties = {
          files = { type = 'array', items = { type = 'string' }, description = 'Files to stage' },
        },
        required = { 'files' },
      },
    },
  },
  {
    type = 'function',
    ["function"] = {
      name = 'git_commit',
      description = 'Create a commit with message (git commit -m)',
      parameters = {
        type = 'object',
        properties = {
          message = { type = 'string', description = 'Commit message' },
        },
        required = { 'message' },
      },
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

  git_status = function()
    local out, err = run('git', { 'status', '--porcelain' })
    if err then return { error = err } end
    return { status = out or '' }
  end,

  git_diff_range = function(args)
    local base = args.base
    if not base or base == '' then
      local oh = run('sh', { '-c', "git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'" })
      base = (type(oh) == 'table' and oh[1]) or oh or 'HEAD'
    end
    local head = args.head or 'HEAD'
    local range = tostring(base) .. '..' .. tostring(head)
    local cmd = 'git'
    local cmd_args = { 'diff', range }
    if args.path and args.path ~= '' then table.insert(cmd_args, args.path) end
    local out, err = run(cmd, cmd_args)
    if err then return { error = err } end
    return { diff = out or '', range = range }
  end,

  git_stage_files = function(args)
    local files = args.files or {}
    if type(files) ~= 'table' or #files == 0 then return { error = 'files[] is required' } end
    local root = utils.get_project_root()
    for _, f in ipairs(files) do
      local ok, err = run('git', { 'add', f }, root)
      if err then return { error = 'Failed to stage: ' .. f .. ' (' .. tostring(err) .. ')' } end
    end
    local status = M.fns.git_status()
    return { success = true, status = status.status }
  end,

  git_commit = function(args)
    local msg = args.message or ''
    if msg == '' then return { error = 'message is required' } end
    local out, err = run('git', { 'commit', '-m', msg })
    if err then return { error = err } end
    -- get new HEAD short hash
    local rev, err2 = run('git', { 'rev-parse', '--short', 'HEAD' })
    return { success = true, output = out or '', commit = (rev or ''):gsub('\n','') or '' }
  end,
}

return M


