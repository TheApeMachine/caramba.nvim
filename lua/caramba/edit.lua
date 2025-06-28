-- Safe Editing Module
-- Validates edits using Tree-sitter before applying them

local M = {}
local ts = vim.treesitter
local parsers = require("nvim-treesitter.parsers")
local config = require("caramba.config")

-- Edit history for rollback
M._history = {}
M._max_history = 10

-- Apply an edit with syntax validation
function M.apply_edit(bufnr, start_row, start_col, end_row, end_col, new_text, opts)
  opts = opts or {}
  bufnr = bufnr or 0
  
  -- Convert to 0-based indexing if needed
  if opts.one_based then
    start_row = start_row - 1
    start_col = start_col - 1
    end_row = end_row - 1
    end_col = end_col - 1
  end
  
  -- Get current content for rollback
  local old_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  
  -- Store history
  table.insert(M._history, 1, {
    bufnr = bufnr,
    start_row = start_row,
    end_row = end_row,
    old_lines = old_lines,
    timestamp = os.time(),
  })
  
  -- Limit history size
  while #M._history > M._max_history do
    table.remove(M._history)
  end
  
  -- Prepare new lines
  local new_lines = vim.split(new_text, "\n", { plain = true })
  
  -- Apply the edit
  if start_row == end_row and start_col > 0 then
    -- Mid-line edit
    local line = old_lines[1] or ""
    local before = string.sub(line, 1, start_col)
    local after = string.sub(line, end_col + 1)
    
    if #new_lines == 1 then
      new_lines[1] = before .. new_lines[1] .. after
    else
      new_lines[1] = before .. new_lines[1]
      new_lines[#new_lines] = new_lines[#new_lines] .. after
    end
  end
  
  -- Set the new content
  vim.api.nvim_buf_set_lines(bufnr, start_row, end_row + 1, false, new_lines)
  
  -- Validate if requested
  if config.get().editing.validate_syntax then
    local valid, error_msg = M.validate_syntax(bufnr)
    if not valid then
      -- Rollback
      vim.api.nvim_buf_set_lines(bufnr, start_row, start_row + #new_lines, false, old_lines)
      table.remove(M._history, 1) -- Remove from history
      return false, error_msg
    end
  end
  
  -- Auto-format if requested
  if config.get().editing.auto_format and not opts.skip_format then
    M.format_range(bufnr, start_row, start_row + #new_lines - 1)
  end
  
  return true, nil
end

-- Apply a patch (full buffer replacement) with validation
function M.apply_patch(bufnr, new_content, opts)
  opts = opts or {}
  bufnr = bufnr or 0
  
  -- Get current content
  local old_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  -- Store in history
  table.insert(M._history, 1, {
    bufnr = bufnr,
    start_row = 0,
    end_row = #old_lines - 1,
    old_lines = old_lines,
    timestamp = os.time(),
    is_patch = true,
  })
  
  -- Limit history
  while #M._history > M._max_history do
    table.remove(M._history)
  end
  
  -- Apply new content
  local new_lines = vim.split(new_content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
  
  -- Validate
  if config.get().editing.validate_syntax then
    local valid, error_msg = M.validate_syntax(bufnr)
    if not valid then
      -- Rollback
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, old_lines)
      table.remove(M._history, 1)
      return false, error_msg
    end
  end
  
  -- Format if requested
  if config.get().editing.auto_format and not opts.skip_format then
    M.format_buffer(bufnr)
  end
  
  return true, nil
end

-- Validate syntax using Tree-sitter
function M.validate_syntax(bufnr)
  bufnr = bufnr or 0
  
  -- Check if parser is available
  if not parsers.has_parser() then
    return true, nil -- Can't validate, assume OK
  end
  
  local parser = parsers.get_parser(bufnr)
  if not parser then
    return true, nil
  end
  
  -- Parse and check for errors
  local ok, tree = pcall(function()
    return parser:parse()[1]
  end)
  
  if not ok then
    return false, "Parse error: " .. tostring(tree)
  end
  
  if not tree then
    return false, "Failed to parse buffer"
  end
  
  -- Check for ERROR nodes
  local error_nodes = {}
  local function check_errors(node)
    if node:type() == "ERROR" or node:has_error() then
      table.insert(error_nodes, node)
    end
    for child in node:iter_children() do
      check_errors(child)
    end
  end
  
  check_errors(tree:root())
  
  if #error_nodes > 0 then
    -- Get details of first error
    local error_node = error_nodes[1]
    local start_row, start_col, end_row, end_col = error_node:range()
    local error_text = vim.api.nvim_buf_get_text(
      bufnr, start_row, start_col, end_row, end_col, {}
    )[1] or ""
    
    return false, string.format(
      "Syntax error at line %d: %s",
      start_row + 1,
      error_text:sub(1, 50)
    )
  end
  
  return true, nil
end

-- Format a range using LSP
function M.format_range(bufnr, start_row, end_row)
  bufnr = bufnr or 0
  
  -- Try LSP formatting first
  local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    if client.server_capabilities.documentRangeFormattingProvider then
      vim.lsp.buf.format({
        bufnr = bufnr,
        range = {
          ["start"] = { start_row, 0 },
          ["end"] = { end_row + 1, 0 },
        },
        async = false,
      })
      return
    end
  end
  
  -- Fallback to buffer formatting
  M.format_buffer(bufnr)
end

-- Format entire buffer
function M.format_buffer(bufnr)
  bufnr = bufnr or 0
  vim.lsp.buf.format({ bufnr = bufnr, async = false })
end

-- Rollback last edit
function M.rollback(steps)
  steps = steps or 1
  
  for i = 1, math.min(steps, #M._history) do
    local entry = M._history[1]
    if entry then
      vim.api.nvim_buf_set_lines(
        entry.bufnr,
        entry.start_row,
        entry.is_patch and -1 or (entry.start_row + 
          vim.api.nvim_buf_line_count(entry.bufnr) - #entry.old_lines),
        false,
        entry.old_lines
      )
      table.remove(M._history, 1)
    end
  end
end

-- Create a diff preview
function M.create_diff_preview(bufnr, start_row, end_row, new_text)
  bufnr = bufnr or 0
  
  -- Get current lines
  local old_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  local new_lines = vim.split(new_text, "\n", { plain = true })
  
  -- Create diff
  local diff_lines = {}
  
  -- Simple line-by-line diff
  local max_lines = math.max(#old_lines, #new_lines)
  for i = 1, max_lines do
    local old_line = old_lines[i]
    local new_line = new_lines[i]
    
    if old_line and not new_line then
      table.insert(diff_lines, "- " .. old_line)
    elseif new_line and not old_line then
      table.insert(diff_lines, "+ " .. new_line)
    elseif old_line ~= new_line then
      if old_line then
        table.insert(diff_lines, "- " .. old_line)
      end
      if new_line then
        table.insert(diff_lines, "+ " .. new_line)
      end
    else
      table.insert(diff_lines, "  " .. (old_line or ""))
    end
  end
  
  return diff_lines
end

-- Show diff in a floating window
function M.show_diff_preview(bufnr, start_row, end_row, new_text, on_accept)
  local diff_lines = M.create_diff_preview(bufnr, start_row, end_row, new_text)
  
  -- Create preview buffer
  local preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, diff_lines)
  vim.api.nvim_buf_set_option(preview_buf, "filetype", "diff")
  vim.api.nvim_buf_set_option(preview_buf, "bufhidden", "wipe")
  
  -- Calculate window size
  local width = math.floor(vim.o.columns * config.get().ui.preview_window_width)
  local height = math.min(
    #diff_lines + 4,
    math.floor(vim.o.lines * config.get().ui.preview_window_height)
  )
  
  -- Create floating window
  local win = vim.api.nvim_open_win(preview_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = config.get().ui.floating_window_border,
    title = " Diff Preview ",
    title_pos = "center",
  })
  
  -- Set up keymaps
  local opts = { buffer = preview_buf, silent = true }
  
  -- Accept
  vim.keymap.set("n", "<CR>", function()
    vim.api.nvim_win_close(win, true)
    if on_accept then
      on_accept()
    end
  end, opts)
  
  -- Reject
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, opts)
  
  -- Add help text
  vim.api.nvim_buf_set_lines(preview_buf, 0, 0, false, {
    "Press <Enter> to accept, <Esc> or 'q' to cancel",
    "---",
  })
end

-- Clear edit history
function M.clear_history()
  M._history = {}
end

-- Insert code at cursor with validation
function M.insert_at_cursor(text, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  
  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  
  -- Get current line
  local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
  local current_line = lines[1] or ""
  
  -- Split the current line at cursor
  local before = current_line:sub(1, col)
  local after = current_line:sub(col + 1)
  
  -- Prepare new content
  local new_lines = vim.split(text, "\n")
  
  -- Handle insertion
  if #new_lines == 1 then
    -- Single line insertion
    new_lines[1] = before .. new_lines[1] .. after
    vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, new_lines)
  else
    -- Multi-line insertion
    new_lines[1] = before .. new_lines[1]
    new_lines[#new_lines] = new_lines[#new_lines] .. after
    vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, new_lines)
  end
  
  -- Validate if requested
  if config.get().editing.validate_syntax then
    local valid, error_msg = M.validate_syntax(bufnr)
    if not valid then
      -- Rollback by restoring original line
      vim.api.nvim_buf_set_lines(bufnr, row, row + #new_lines, false, lines)
      return false, error_msg
    end
  end
  
  -- Move cursor to end of insertion
  local new_row = row + #new_lines - 1
  local new_col = #new_lines[#new_lines] - #after
  vim.api.nvim_win_set_cursor(0, {new_row + 1, new_col})
  
  return true, nil
end

-- Apply a patch to content (exposed for multifile operations)
M._apply_patch_to_content = function(content, patch)
  -- Simple line-based patching
  local lines = vim.split(content, "\n")
  local result = {}
  local i = 1
  
  for line in patch:gmatch("[^\n]+") do
    if line:match("^@@") then
      -- Parse hunk header: @@ -start,count +start,count @@
      local old_start, old_count, new_start, new_count = 
        line:match("^@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")
      
      if old_start then
        old_start = tonumber(old_start)
        old_count = tonumber(old_count)
        
        -- Copy lines before the hunk
        while i < old_start do
          table.insert(result, lines[i])
          i = i + 1
        end
        
        -- Skip old lines
        i = i + old_count
      end
    elseif line:match("^%+") then
      -- Add new line
      table.insert(result, line:sub(2))
    elseif line:match("^%-") then
      -- Remove line (already skipped)
    elseif line:match("^ ") then
      -- Context line
      table.insert(result, line:sub(2))
    end
  end
  
  -- Copy remaining lines
  while i <= #lines do
    table.insert(result, lines[i])
    i = i + 1
  end
  
  return table.concat(result, "\n")
end

-- Setup commands for this module
M.setup_commands = function()
  local commands = require('caramba.core.commands')
  
  -- Apply patch command
  commands.register('ApplyPatch', function(args)
    local patch = args.args
    if patch == "" then
      vim.notify("Please provide patch content", vim.log.levels.ERROR)
      return
    end
    M.apply_patch(vim.api.nvim_get_current_buf(), patch)
  end, {
    desc = 'Apply code patch to current buffer',
    nargs = '+',
  })
  
  -- Show diff preview
  commands.register('DiffPreview', function()
    -- This would need to be integrated with current editing context
    vim.notify("Use diff preview within edit operations", vim.log.levels.INFO)
  end, {
    desc = 'Show diff preview for pending changes',
  })
end

return M 