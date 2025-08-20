-- UI helper components for Caramba

local M = {}

local config = require('caramba.config')
local utils = require('caramba.utils')

--- Show lines in a centered floating window
---@param lines string[]
---@param opts table|nil { title?: string, filetype?: string, width_ratio?: number, height_ratio?: number }
---@return number bufnr, number winid
function M.show_lines_centered(lines, opts)
  opts = opts or {}

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  if opts.filetype then
    vim.api.nvim_buf_set_option(bufnr, 'filetype', opts.filetype)
  end

  -- Determine dimensions
  local cfg = config.get()
  local width_ratio = opts.width_ratio or (cfg.ui and cfg.ui.preview_window_width) or 0.6
  local height_ratio = opts.height_ratio or (cfg.ui and cfg.ui.preview_window_height) or 0.8

  local max_line_len = 0
  for _, l in ipairs(lines) do
    max_line_len = math.max(max_line_len, #l)
  end

  local suggested_width = math.min(vim.o.columns - 4, max_line_len + 4)
  local width = math.floor(math.min(vim.o.columns * width_ratio, suggested_width))
  if width < 40 then width = math.min(80, suggested_width) end

  local suggested_height = #lines + 2
  local height = math.min(suggested_height, math.floor(vim.o.lines * height_ratio))
  if height < 10 then height = math.min(20, suggested_height) end

  local winid = utils.create_centered_window(bufnr, width, height, { title = opts.title })
  -- Soft aesthetics: no signcolumn, linebreak, minimal win highlight
  pcall(vim.api.nvim_win_set_option, winid, 'signcolumn', 'no')
  pcall(vim.api.nvim_win_set_option, winid, 'wrap', true)
  pcall(vim.api.nvim_win_set_option, winid, 'linebreak', true)
  -- Subtle border title spacing
  local cfg = vim.api.nvim_win_get_config(winid)
  cfg.title_pos = 'center'
  vim.api.nvim_win_set_config(winid, cfg)
  return bufnr, winid
end

--- Show markdown content in a centered window
---@param title string
---@param markdown string
---@return number bufnr, number winid
function M.show_markdown_centered(title, markdown)
  local lines = vim.split(markdown or "", '\n')
  return M.show_lines_centered(lines, { title = title, filetype = 'markdown' })
end

--- Simple confirm dialog with centered window
---@param title string
---@param message string|string[]
---@param on_yes function|nil
---@param on_no function|nil
function M.confirm(title, message, on_yes, on_no)
  local lines = type(message) == 'table' and message or vim.split(message or '', '\n')
  table.insert(lines, '')
  table.insert(lines, "Press 'y' to confirm, 'n' or 'q' to cancel")

  local bufnr, win = M.show_lines_centered(lines, { title = ' ' .. title .. ' ', filetype = 'markdown' })

  local opts = { buffer = bufnr, silent = true, nowait = true }
  vim.keymap.set('n', 'y', function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if on_yes then on_yes() end
  end, opts)
  vim.keymap.set('n', 'n', function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if on_no then on_no() end
  end, opts)
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if on_no then on_no() end
  end, opts)
end

--- Simple select list dialog (1-9)
---@param title string
---@param items string[]
---@param on_select function
function M.select(title, items, on_select)
  local lines = { '# ' .. title, '' }
  for i, item in ipairs(items) do
    table.insert(lines, string.format('%d. %s', i, item))
  end
  table.insert(lines, '')
  table.insert(lines, 'Press number to select, q to cancel')

  local bufnr, win = M.show_lines_centered(lines, { title = ' ' .. title .. ' ', filetype = 'markdown' })
  local opts = { buffer = bufnr, silent = true, nowait = true }
  for i = 1, math.min(#items, 9) do
    vim.keymap.set('n', tostring(i), function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      on_select(i, items[i])
    end, opts)
  end
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, opts)
end

return M

