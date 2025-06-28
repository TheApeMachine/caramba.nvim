-- Common utility functions for caramba
-- Shared helpers to avoid duplication across modules

local M = {}

--- Show result in a floating window
---@param content string The content to display
---@param title string? Optional window title
function M.show_result_window(content, title)
  title = title or "AI Result"
  
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Set content
  local lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Calculate window size
  local width = math.min(80, math.max(40, vim.o.columns - 20))
  local height = math.min(30, math.max(10, #lines + 2))
  
  -- Calculate position (centered)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })
  
  -- Set options
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)
  
  -- Add keymaps
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<esc>", "<cmd>close<cr>", { noremap = true, silent = true })
  
  -- Syntax highlighting for markdown
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
end

--- Get file extension to language mapping
---@param ext string File extension
---@return string? Language name
function M.ext_to_lang(ext)
  -- Remove leading dot if present
  ext = ext:gsub("^%.", "")
  
  local mappings = {
    js = "javascript",
    jsx = "javascript",
    ts = "typescript", 
    tsx = "typescript",
    py = "python",
    rb = "ruby",
    go = "go",
    rs = "rust",
    java = "java",
    cpp = "cpp",
    c = "c",
    h = "c",
    hpp = "cpp",
    cs = "csharp",
    php = "php",
    swift = "swift",
    kt = "kotlin",
    scala = "scala",
    r = "r",
    lua = "lua",
    vim = "vim",
    sh = "bash",
    bash = "bash",
    zsh = "bash",
    fish = "fish",
    ps1 = "powershell",
    sql = "sql",
    html = "html",
    css = "css",
    scss = "scss",
    sass = "sass",
    less = "less",
    xml = "xml",
    json = "json",
    yaml = "yaml",
    yml = "yaml",
    toml = "toml",
    ini = "ini",
    cfg = "ini",
    conf = "ini",
    md = "markdown",
    tex = "latex",
    rst = "rst",
  }
  
  return mappings[ext:lower()]
end

--- Get visual selection text
---@return string? Selected text
function M.get_visual_selection()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(
    0, start_pos[2] - 1, end_pos[2], false
  )
  
  if #lines == 0 then
    return nil
  end
  
  -- Handle single line selection
  if #lines == 1 then
    local line = lines[1]
    local start_col = start_pos[3]
    local end_col = end_pos[3]
    return line:sub(start_col, end_col)
  end
  
  -- Handle multi-line selection
  lines[1] = lines[1]:sub(start_pos[3])
  lines[#lines] = lines[#lines]:sub(1, end_pos[3])
  
  return table.concat(lines, "\n")
end

--- Create a scratch buffer with content
---@param content string Content to display
---@param filetype string? Optional filetype for syntax highlighting
---@return number Buffer number
function M.create_scratch_buffer(content, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Set content
  local lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Set options
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  
  if filetype then
    vim.api.nvim_buf_set_option(buf, "filetype", filetype)
  end
  
  return buf
end

--- Show search results in quickfix or location list
---@param results table List of search results
---@param title string Title for the list
---@param use_loclist boolean? Use location list instead of quickfix
function M.show_search_results(results, title, use_loclist)
  if #results == 0 then
    vim.notify("No results found", vim.log.levels.INFO)
    return
  end
  
  -- Convert results to quickfix format
  local qf_list = {}
  for _, result in ipairs(results) do
    table.insert(qf_list, {
      filename = result.file or result.filepath,  -- Handle both file and filepath keys
      lnum = result.line or 1,
      col = result.col or 1,
      text = result.text or result.content or "",
    })
  end
  
  -- Set the list
  if use_loclist then
    vim.fn.setloclist(0, qf_list)
    vim.fn.setloclist(0, {}, "a", { title = title })
    vim.cmd("lopen")
  else
    vim.fn.setqflist(qf_list)
    vim.fn.setqflist({}, "a", { title = title })
    vim.cmd("copen")
  end
end

--- Jump to a file location
---@param location table Location with file, line, and optional column
function M.jump_to_location(location)
  if not location or not location.file then
    vim.notify("Invalid location", vim.log.levels.ERROR)
    return
  end
  
  -- Open the file
  vim.cmd("edit " .. vim.fn.fnameescape(location.file))
  
  -- Jump to line and column
  if location.line then
    vim.api.nvim_win_set_cursor(0, { location.line, location.col or 0 })
  end
  
  -- Center the screen
  vim.cmd("normal! zz")
end

--- Debounce a function
---@param fn function Function to debounce
---@param delay number Delay in milliseconds
---@return function Debounced function
function M.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      vim.fn.timer_stop(timer)
    end
    timer = vim.fn.timer_start(delay, function()
      fn(unpack(args))
    end)
  end
end

--- Check if a file exists
---@param path string File path
---@return boolean
function M.file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file"
end

--- Check if a directory exists
---@param path string Directory path
---@return boolean
function M.dir_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "directory"
end

--- Read file contents
---@param path string File path
---@return string? Content or nil if error
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()
  return content
end

--- Write file contents
---@param path string File path
---@param content string Content to write
---@return boolean Success
function M.write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  file:write(content)
  file:close()
  return true
end

--- Get project root directory
---@return string Project root path
function M.get_project_root()
  -- Try to find git root
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
  if vim.v.shell_error == 0 and git_root ~= "" then
    return git_root
  end
  
  -- Fall back to current working directory
  return vim.fn.getcwd()
end

--- Format file size
---@param bytes number Size in bytes
---@return string Formatted size
function M.format_file_size(bytes)
  if bytes < 1024 then
    return string.format("%d B", bytes)
  elseif bytes < 1024 * 1024 then
    return string.format("%.1f KB", bytes / 1024)
  elseif bytes < 1024 * 1024 * 1024 then
    return string.format("%.1f MB", bytes / (1024 * 1024))
  else
    return string.format("%.1f GB", bytes / (1024 * 1024 * 1024))
  end
end

--- Deep copy a table
---@param orig table Original table
---@return table Copy
function M.deep_copy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == "table" then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[M.deep_copy(orig_key)] = M.deep_copy(orig_value)
    end
    setmetatable(copy, M.deep_copy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end

return M 