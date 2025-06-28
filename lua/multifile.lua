-- Multi-file Operations Module
-- Handles complex edits across multiple files with transaction support

local M = {}

local config = require('ai.config')
local edit = require('ai.edit')
local llm = require('ai.llm')
local context = require('ai.context')

-- Transaction state
M._transaction = {
  active = false,
  operations = {},
  backup = {},
  preview_buffers = {},
}

-- Operation types
M.OpType = {
  CREATE = "create",
  MODIFY = "modify",
  DELETE = "delete",
  RENAME = "rename",
}

-- Create a backup of a file
local function backup_file(filepath)
  local ok, content = pcall(vim.fn.readfile, filepath)
  if ok then
    return {
      path = filepath,
      content = table.concat(content, "\n"),
      exists = true,
    }
  else
    return {
      path = filepath,
      exists = false,
    }
  end
end

-- Restore a file from backup
local function restore_file(backup)
  if backup.exists then
    vim.fn.writefile(vim.split(backup.content, "\n"), backup.path)
  else
    -- File didn't exist before, delete it
    vim.fn.delete(backup.path)
  end
end

-- Start a new transaction
M.begin_transaction = function()
  if M._transaction.active then
    error("Transaction already in progress")
  end
  
  M._transaction = {
    active = true,
    operations = {},
    backup = {},
    preview_buffers = {},
  }
end

-- Add an operation to the transaction
M.add_operation = function(op)
  if not M._transaction.active then
    error("No active transaction")
  end
  
  -- Validate operation
  if not op.type or not M.OpType[op.type:upper()] then
    error("Invalid operation type: " .. tostring(op.type))
  end
  
  if not op.path then
    error("Operation must specify a path")
  end
  
  -- Normalize the operation
  op.type = op.type:lower()
  op.path = vim.fn.expand(op.path)
  
  -- Add to transaction
  table.insert(M._transaction.operations, op)
  
  -- Create backup if file exists and we haven't backed it up yet
  if not M._transaction.backup[op.path] and 
     (op.type == M.OpType.MODIFY or op.type == M.OpType.DELETE or op.type == M.OpType.RENAME) then
    M._transaction.backup[op.path] = backup_file(op.path)
  end
end

-- Preview the transaction changes
M.preview_transaction = function()
  if not M._transaction.active then
    vim.notify("No active transaction", vim.log.levels.WARN)
    return
  end
  
  -- Create a preview buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'diff')
  
  local lines = {
    "# Multi-file Operation Preview",
    "",
    string.format("Operations: %d", #M._transaction.operations),
    "",
  }
  
  -- Group operations by file
  local by_file = {}
  for _, op in ipairs(M._transaction.operations) do
    by_file[op.path] = by_file[op.path] or {}
    table.insert(by_file[op.path], op)
  end
  
  -- Show each file's changes
  for filepath, ops in pairs(by_file) do
    table.insert(lines, string.format("## %s", filepath))
    
    for _, op in ipairs(ops) do
      if op.type == M.OpType.CREATE then
        table.insert(lines, "  [CREATE] New file")
        if op.content then
          table.insert(lines, "  Preview:")
          for line in op.content:gmatch("[^\n]+") do
            table.insert(lines, "  + " .. line)
          end
        end
      elseif op.type == M.OpType.MODIFY then
        table.insert(lines, "  [MODIFY] " .. (op.description or "Edit file"))
        if op.hunks then
          for _, hunk in ipairs(op.hunks) do
            table.insert(lines, string.format("  @@ -%d,%d +%d,%d @@",
              hunk.old_start, hunk.old_lines,
              hunk.new_start, hunk.new_lines))
            for _, line in ipairs(hunk.lines) do
              table.insert(lines, "  " .. line)
            end
          end
        end
      elseif op.type == M.OpType.DELETE then
        table.insert(lines, "  [DELETE] Remove file")
      elseif op.type == M.OpType.RENAME then
        table.insert(lines, string.format("  [RENAME] → %s", op.new_path))
      end
    end
    
    table.insert(lines, "")
  end
  
  -- Add instructions
  table.insert(lines, "---")
  table.insert(lines, "Press 'a' to apply, 'q' to cancel")
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Open in a floating window
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' Multi-file Operation Preview ',
    title_pos = 'center',
  })
  
  -- Set up keymaps
  local opts = { buffer = buf, silent = true }
  vim.keymap.set('n', 'a', function()
    vim.api.nvim_win_close(win, true)
    M.commit_transaction()
  end, opts)
  
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
    M.rollback_transaction()
  end, opts)
  
  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(win, true)
    M.rollback_transaction()
  end, opts)
end

-- Apply a single operation
local function apply_operation(op)
  if op.type == M.OpType.CREATE then
    -- Ensure directory exists
    local dir = vim.fn.fnamemodify(op.path, ':h')
    vim.fn.mkdir(dir, 'p')
    
    -- Write content
    if op.content then
      vim.fn.writefile(vim.split(op.content, "\n"), op.path)
    else
      vim.fn.writefile({}, op.path)
    end
    
  elseif op.type == M.OpType.MODIFY then
    -- Read current content
    local ok, lines = pcall(vim.fn.readfile, op.path)
    if not ok then
      error("Failed to read file: " .. op.path)
    end
    
    local content = table.concat(lines, "\n")
    
    -- Apply the modification
    if op.content then
      -- Full replacement
      vim.fn.writefile(vim.split(op.content, "\n"), op.path)
    elseif op.patch then
      -- Apply patch
      local new_content = edit._apply_patch_to_content(content, op.patch)
      vim.fn.writefile(vim.split(new_content, "\n"), op.path)
    elseif op.callback then
      -- Custom modification function
      local new_content = op.callback(content)
      vim.fn.writefile(vim.split(new_content, "\n"), op.path)
    end
    
  elseif op.type == M.OpType.DELETE then
    vim.fn.delete(op.path)
    
  elseif op.type == M.OpType.RENAME then
    if not op.new_path then
      error("Rename operation must specify new_path")
    end
    
    -- Ensure target directory exists
    local dir = vim.fn.fnamemodify(op.new_path, ':h')
    vim.fn.mkdir(dir, 'p')
    
    -- Rename the file
    vim.fn.rename(op.path, op.new_path)
    
    -- Update any open buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf) == op.path then
        vim.api.nvim_buf_set_name(buf, op.new_path)
      end
    end
  end
end

-- Commit the transaction
M.commit_transaction = function()
  if not M._transaction.active then
    vim.notify("No active transaction", vim.log.levels.WARN)
    return
  end
  
  local success = true
  local applied = {}
  
  -- Try to apply all operations
  for i, op in ipairs(M._transaction.operations) do
    local ok, err = pcall(apply_operation, op)
    if not ok then
      success = false
      vim.notify(string.format("Failed to apply operation %d: %s", i, err), vim.log.levels.ERROR)
      
      -- Rollback already applied operations
      for j = i-1, 1, -1 do
        local rollback_op = applied[j]
        if rollback_op then
          pcall(restore_file, M._transaction.backup[rollback_op.path])
        end
      end
      
      break
    else
      applied[i] = op
    end
  end
  
  if success then
    vim.notify(string.format("Successfully applied %d operations", #M._transaction.operations), vim.log.levels.INFO)
  end
  
  -- Clear transaction
  M._transaction = {
    active = false,
    operations = {},
    backup = {},
    preview_buffers = {},
  }
  
  return success
end

-- Rollback the transaction
M.rollback_transaction = function()
  if not M._transaction.active then
    return
  end
  
  vim.notify("Transaction cancelled", vim.log.levels.INFO)
  
  -- Clear transaction
  M._transaction = {
    active = false,
    operations = {},
    backup = {},
    preview_buffers = {},
  }
end

-- Parse AI response into operations
M.parse_ai_operations = function(response)
  local operations = {}
  
  -- Try to parse as JSON first
  local ok, json_ops = pcall(vim.json.decode, response)
  if ok and type(json_ops) == "table" then
    if json_ops.operations then
      return json_ops.operations
    elseif json_ops[1] then
      return json_ops
    end
  end
  
  -- Fallback: Parse structured text format
  local current_op = nil
  local in_content = false
  local content_lines = {}
  
  for line in response:gmatch("[^\n]+") do
    if line:match("^FILE:") then
      -- Save previous operation
      if current_op then
        if #content_lines > 0 then
          current_op.content = table.concat(content_lines, "\n")
        end
        table.insert(operations, current_op)
      end
      
      -- Start new operation
      local path = line:match("^FILE:%s*(.+)$")
      current_op = { path = path }
      content_lines = {}
      in_content = false
      
    elseif line:match("^ACTION:") then
      if current_op then
        local action = line:match("^ACTION:%s*(.+)$"):lower()
        current_op.type = action
      end
      
    elseif line:match("^NEW_PATH:") then
      if current_op then
        current_op.new_path = line:match("^NEW_PATH:%s*(.+)$")
      end
      
    elseif line:match("^CONTENT:") then
      in_content = true
      
    elseif line:match("^END_CONTENT") then
      in_content = false
      
    elseif in_content then
      table.insert(content_lines, line)
    end
  end
  
  -- Save last operation
  if current_op then
    if #content_lines > 0 then
      current_op.content = table.concat(content_lines, "\n")
    end
    table.insert(operations, current_op)
  end
  
  return operations
end

-- High-level refactoring functions

-- Rename a symbol across multiple files
M.rename_symbol = function(old_name, new_name, opts)
  opts = opts or {}
  
  -- Find all occurrences
  local grep_job = require('plenary.job'):new({
    command = 'rg',
    args = {
      '--vimgrep',
      '--word-regexp',
      old_name,
      opts.directory or vim.fn.getcwd()
    },
  })
  
  local results = grep_job:sync()
  
  -- Group by file
  local by_file = {}
  for _, line in ipairs(results) do
    local file, lnum, col, text = line:match("([^:]+):(%d+):(%d+):(.*)$")
    if file then
      by_file[file] = by_file[file] or {}
      table.insert(by_file[file], {
        line = tonumber(lnum),
        col = tonumber(col),
        text = text,
      })
    end
  end
  
  -- Start transaction
  M.begin_transaction()
  
  -- Create modifications for each file
  for filepath, occurrences in pairs(by_file) do
    M.add_operation({
      type = M.OpType.MODIFY,
      path = filepath,
      description = string.format("Rename %s to %s", old_name, new_name),
      callback = function(content)
        -- Simple word boundary replacement
        return content:gsub("([^%w_])" .. old_name .. "([^%w_])", "%1" .. new_name .. "%2")
      end,
    })
  end
  
  -- Preview changes
  M.preview_transaction()
end

-- Extract a module from multiple files
M.extract_module = function(module_name, opts)
  opts = opts or {}
  
  local prompt = string.format([[
I need to extract functionality into a new module called '%s'.

Please analyze the codebase and identify:
1. Which functions/classes should be moved to the new module
2. Which files need to import the new module
3. Any necessary refactoring to make the extraction clean

Respond with a structured list of file operations in this format:

FILE: path/to/new/module.lua
ACTION: create
CONTENT:
-- Module content here
END_CONTENT

FILE: path/to/existing/file.lua  
ACTION: modify
CONTENT:
-- Modified content
END_CONTENT

Be precise and include all necessary changes.
]], module_name)

  -- Get context from current buffer and related files
  local ctx = context.collect()
  if ctx then
    prompt = prompt .. "\n\nCurrent file context:\n" .. vim.inspect(ctx)
  end
  
  -- Request AI assistance
  llm.request(prompt, { temperature = 0.1 }, function(response)
    if not response then
      vim.notify("Failed to get AI response", vim.log.levels.ERROR)
      return
    end
    
    vim.schedule(function()
      -- Parse operations
      local operations = M.parse_ai_operations(response)
      
      if #operations == 0 then
        vim.notify("No operations found in AI response", vim.log.levels.WARN)
        return
      end
      
      -- Start transaction
      M.begin_transaction()
      
      -- Add all operations
      for _, op in ipairs(operations) do
        M.add_operation(op)
      end
      
      -- Preview
      M.preview_transaction()
    end)
  end)
end

return M 