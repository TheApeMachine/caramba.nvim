-- File system helper tools for the agent (read-only, safe)

local M = {}
local utils = require('caramba.utils')

local function glob(pattern, limit)
  local root = utils.get_project_root()
  local matches = vim.fn.glob(root .. '/' .. (pattern or '**/*'), true, true)
  local out = {}
  local n = 0
  for _, p in ipairs(matches or {}) do
    if p and p ~= '' then
      table.insert(out, p)
      n = n + 1
      if limit and n >= limit then break end
    end
  end
  return out
end

M.tools = {
  {
    type = 'function',
    ["function"] = {
      name = 'list_files',
      description = 'List files by glob pattern relative to project root',
      parameters = {
        type = 'object',
        properties = {
          pattern = { type = 'string', description = 'Glob like **/*.lua' },
          limit   = { type = 'integer', description = 'Max results (default 200)' },
        },
        required = {},
      },
    },
  },
  {
    type = 'function',
    ["function"] = {
      name = 'read_file_head',
      description = 'Read the first N lines of a file for preview',
      parameters = {
        type = 'object',
        properties = {
          file_path = { type = 'string' },
          lines     = { type = 'integer', description = 'How many lines (default 120)' },
        },
        required = { 'file_path' },
      },
    },
  },
}

M.fns = {
  list_files = function(args)
    local pattern = args.pattern or '**/*'
    local limit = args.limit or 200
    local results = glob(pattern, limit)
    return { results = results, count = #results }
  end,

  read_file_head = function(args)
    local path = vim.fn.expand(args.file_path)
    if vim.fn.filereadable(path) == 0 then
      return { error = 'File not readable: ' .. path }
    end
    local max = math.max(1, tonumber(args.lines or 120))
    -- Read full file and slice the first N lines to avoid passing extra args to readfile
    local all = vim.fn.readfile(path)
    local lines = {}
    for i = 1, math.min(#all, max) do lines[i] = all[i] end
    return { path = path, preview = table.concat(lines or {}, '\n'), line_count = #lines }
  end,
}

return M


