
-- Tree-sitter based Context Extraction
-- Provides intelligent context extraction using AST analysis

local M = {}
local ts = vim.treesitter
-- local ts_utils = require('nvim-treesitter.ts_utils') -- Defer loading
-- local ts_query = require('vim.treesitter.query') -- Already part of vim
-- local parsers = require('nvim-treesitter.parsers') -- Defer loading
local utils = require('caramba.utils')

-- Cache for parsed contexts
M._cache = {}
M._cursor_context = nil
M._warned_buffers = {} -- Track buffers that have already shown the warning
M._installing_parsers = {} -- Track parsers being installed

-- Common node types for different languages
M.node_types = {
  function_like = {
    "function_declaration", "function_definition", "method_definition",
    "arrow_function", "function_expression", "lambda_expression",
    "method_declaration", "constructor_declaration", "function_item"
  },
  class_like = {
    "class_declaration", "class_definition", "interface_declaration",
    "struct_declaration", "struct_item", "impl_item", "trait_item"
  },
  import_like = {
    "import_statement", "import_declaration", "import_from_statement",
    "use_declaration", "require_statement", "include_statement"
  },
  comment_like = {
    "comment", "line_comment", "block_comment", "documentation_comment"
  }
}

-- Auto-install Tree-sitter parser if missing
local function ensure_parser_installed(lang)
  -- Check if auto-install is enabled
  local config = require('caramba.config')
  if not config.get().features.auto_install_parsers then
    return false
  end
  
  -- Skip if already installing
  if M._installing_parsers[lang] then
    return
  end
  
  -- Check if nvim-treesitter is available
  local ok, configs = pcall(require, 'nvim-treesitter.parsers')
  if not ok then
    return false
  end
  
  -- Get available parsers
  local available_parsers = configs.get_parser_configs()
  if not available_parsers[lang] then
    return false
  end
  
  -- Check if parser is already installed
  if configs.has_parser(lang) then
    return true
  end
  
  -- Mark as installing
  M._installing_parsers[lang] = true
  
  -- Install the parser
  vim.notify("Installing Tree-sitter parser for " .. lang .. "...", vim.log.levels.INFO)
  
  -- Use vim.cmd to run TSInstall command
  vim.schedule(function()
    local install_ok = pcall(vim.cmd, "TSInstall " .. lang)
    
    vim.defer_fn(function()
      M._installing_parsers[lang] = nil
      
      if install_ok and configs.has_parser(lang) then
        vim.notify("Tree-sitter parser for " .. lang .. " installed successfully!", vim.log.levels.INFO)
        -- Clear the warning for all buffers of this filetype
        for bufnr, _ in pairs(M._warned_buffers) do
          if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == lang then
            M._warned_buffers[bufnr] = nil
          end
        end
      else
        vim.notify("Failed to install Tree-sitter parser for " .. lang, vim.log.levels.ERROR)
      end
    end, 5000) -- Wait 5 seconds for installation to complete
  end)
  
  return false
end

-- Get the current buffer's parser
function M.get_parser(bufnr)
  local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
  if not ok or not parsers then return nil end
  bufnr = tonumber(bufnr) or 0
  local lang = vim.bo[bufnr].filetype
  
  -- Try to auto-install if missing
  if lang and lang ~= "" and parsers and not parsers.has_parser(lang) then
    -- Check if this is a known language that has a parser available
    local configs = require('nvim-treesitter.parsers').get_parser_configs()
    if configs[lang] then
      ensure_parser_installed(lang)
    end
    return nil
  end
  
  if not parsers or not parsers.has_parser() then
    return nil
  end
  return parsers.get_parser(bufnr)
end

-- Find the node at cursor position
function M.get_node_at_cursor(winnr)
  local cursor = vim.api.nvim_win_get_cursor(winnr or 0)
  local row, col = cursor[1] - 1, cursor[2]
  
  local parser = M.get_parser()
  if not parser then 
    local bufnr = vim.api.nvim_get_current_buf()
    local lang = vim.bo[bufnr].filetype
    
    -- Only warn once per buffer and not for special buffers
    if not M._warned_buffers[bufnr] and vim.bo[bufnr].buftype == "" then
      M._warned_buffers[bufnr] = true
      
      -- Check if parser is available but not installed
      local ok, configs = pcall(require, 'nvim-treesitter.parsers')
      if ok and lang and configs[lang] and not M._installing_parsers[lang] then
        -- Parser is available, will be auto-installed
        vim.notify("Tree-sitter parser for " .. lang .. " will be installed automatically", vim.log.levels.INFO)
      elseif lang and lang ~= "" then
        -- Parser not available
        vim.notify("No Tree-sitter parser available for " .. lang, vim.log.levels.WARN)
      end
    end
    return nil 
  end
  
  local trees = parser:parse()
  if not trees or #trees == 0 then
    vim.notify("Failed to parse buffer with Tree-sitter", vim.log.levels.ERROR)
    return nil
  end
  
  local tree = trees[1]
  if not tree then return nil end
  
  local root = tree:root()
  if not root then return nil end
  
  return root:descendant_for_range(row, col, row, col)
end

-- Find parent node of specific types
function M.find_parent_node(node, node_types)
  if not node then return nil end
  
  local parent = node:parent()
  while parent do
    if vim.tbl_contains(node_types, parent:type()) then
      return parent
    end
    parent = parent:parent()
  end
  
  return nil
end

-- Extract imports from the buffer
function M.extract_imports(bufnr, max_lines)
  bufnr = tonumber(bufnr) or 0
  max_lines = max_lines or 50
  
  local parser = M.get_parser(bufnr)
  if not parser then return {} end
  
  local tree = parser:parse()[1]
  if not tree then return {} end
  
  local imports = {}
  local root = tree:root()
  
  -- Use Tree-sitter query to find imports
  local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
  if not ok or not parsers then return {} end
  local lang = parsers.get_buf_lang(bufnr)
  local query_string = ""
  
  -- Language-specific queries
  if lang == "python" then
    query_string = [[
      (import_statement) @import
      (import_from_statement) @import
    ]]
  elseif lang == "javascript" or lang == "typescript" or lang == "tsx" then
    query_string = [[
      (import_statement) @import
      (import_declaration) @import
    ]]
  elseif lang == "rust" then
    query_string = [[
      (use_declaration) @import
    ]]
  elseif lang == "go" then
    query_string = [[
      (import_declaration) @import
    ]]
  else
    -- Fallback: Look for common import patterns in top-level nodes
    local children = root:named_children()
    for _, child in ipairs(children) do
      local start_row = child:start()
      if start_row >= max_lines then
        break
      end
      
      for _, import_type in ipairs(M.node_types.import_like) do
        if child:type() == import_type then
          table.insert(imports, utils.get_node_text(child, bufnr))
          break
        end
      end
    end
    return imports
  end
  
  -- Execute query
  local ts_query = vim.treesitter.query
  local ok, query = pcall(ts_query.parse, lang, query_string)
  if ok and query then
    for _, match, _ in query:iter_matches(root, bufnr, 0, max_lines) do
      for _, node in pairs(match) do
        if node then
          local text = utils.get_node_text(node, bufnr)
          if text and text ~= "" then
            table.insert(imports, text)
          end
        end
      end
    end
  end
  
  return imports
end

-- Extract documentation comments
function M.extract_documentation(node, bufnr)
  if not node then return nil end
  
  bufnr = tonumber(bufnr) or 0
  local start_row = node:start()
  
  -- Look for comments immediately before the node
  local doc_lines = {}
  for row = start_row - 1, math.max(0, start_row - 10), -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if line then
      -- Check for comment patterns
      if line:match("^%s*//") or line:match("^%s*#") or 
         line:match("^%s*%-%-") or line:match("^%s*/%*") then
        table.insert(doc_lines, 1, line)
      elseif line:match("^%s*%*/") then
        table.insert(doc_lines, 1, line)
        -- Continue to get the full block comment
      elseif #doc_lines > 0 and line:match("^%s*%*") then
        table.insert(doc_lines, 1, line)
      elseif line:match("^%s*$") and #doc_lines == 0 then
        -- Empty line, continue looking
      else
        -- Non-comment, non-empty line
        break
      end
    end
  end
  
  return #doc_lines > 0 and table.concat(doc_lines, "\n") or nil
end

-- Clear cache for a buffer
local function clear_buffer_cache(bufnr)
  bufnr = tonumber(bufnr) or vim.api.nvim_get_current_buf()
  -- Clear all cache entries for this buffer
  for key, _ in pairs(M._cache) do
    if key:match("^" .. tostring(bufnr) .. ":") then
      M._cache[key] = nil
    end
  end
  -- Also clear warning status when buffer changes
  M._warned_buffers[bufnr] = nil
end

-- Set up cache invalidation
vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI", "TextChangedP"}, {
  group = vim.api.nvim_create_augroup("CarambaContextCache", { clear = true }),
  callback = function(args)
    clear_buffer_cache(args.buf)
  end,
})

-- Collect context information around cursor
M.collect = function(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local from_visual_selection = opts.start_row and opts.end_row

  -- If no specific range is provided, check for a visual selection
  if not from_visual_selection then
    local start_pos, end_pos = utils.get_visual_selection_pos()
    if start_pos and end_pos then
      opts.start_row, opts.start_col = start_pos[1], start_pos[2]
      opts.end_row, opts.end_col = end_pos[1], end_pos[2]
      from_visual_selection = true
    end
  end

  -- Ensure bufnr is always a number
  if opts.bufnr then
    bufnr = tonumber(opts.bufnr)
    if not bufnr then
      vim.notify("Invalid buffer number: " .. tostring(opts.bufnr), vim.log.levels.ERROR)
      bufnr = vim.api.nvim_get_current_buf()
    end
  else
    bufnr = vim.api.nvim_get_current_buf()
  end
  
  -- Get buffer info
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local filename = vim.api.nvim_buf_get_name(bufnr)
  
  local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
  if not ok or not parsers then return {} end
  local parser = parsers.get_parser(bufnr)
  
  -- If there's a selection, prioritize it
  if from_visual_selection then
    local lines = vim.api.nvim_buf_get_lines(bufnr, opts.start_row - 1, opts.end_row, false)
    if #lines > 0 then
        -- Trim the first and last lines according to column selection
        lines[#lines] = lines[#lines]:sub(1, opts.end_col)
        lines[1] = lines[1]:sub(opts.start_col)
    end
    
    return {
      language = vim.bo[bufnr].filetype,
      file_path = vim.api.nvim_buf_get_name(bufnr),
      content = table.concat(lines, "\n"),
      imports = M.extract_imports(bufnr),
    }
  end

  if not parser then
    return nil
  end
  
  local tree = parser:parse()[1]
  local root = tree:root()
  
  -- Get the node at cursor for cache key
  local node = M.get_node_at_cursor()
  if not node then
    -- Fallback: If no node at cursor but we want context, use the whole buffer
    return {
      language = vim.bo[bufnr].filetype,
      file_path = vim.api.nvim_buf_get_name(bufnr),
      content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"),
      imports = M.extract_imports(bufnr),
    }
  end
  
  -- Generate cache key based on buffer, node ID, and whether we want full context
  local cache_key = string.format("%d:%s:%s", bufnr, tostring(node:id()), opts.full and "full" or "partial")
  
  -- Check cache unless forced refresh
  if not opts.force and M._cache[cache_key] then
    return M._cache[cache_key]
  end
  
  local context = {
    language = vim.bo[bufnr].filetype,
    current_function = nil,
    current_class = nil,
    imports = {},
    local_variables = {},
    current_line = vim.api.nvim_get_current_line(),
    cursor_pos = vim.api.nvim_win_get_cursor(0),
    file_path = vim.api.nvim_buf_get_name(bufnr),
  }
  
  -- Find the appropriate context node
  local context_node = M.find_context_node(node)
  if not context_node then
    -- If tree-sitter fails to find a specific node, use the whole buffer as context
    return {
      language = vim.bo[bufnr].filetype,
      file_path = vim.api.nvim_buf_get_name(bufnr),
      content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"),
      imports = M.extract_imports(bufnr),
    }
  end
  
  -- Get the name of the context node
  context.name = M.get_node_name(context_node, bufnr)
  
  -- Extract imports
  context.imports = M.extract_imports(bufnr) or {}
  
  -- Get the text content of the context node
  local start_row, start_col, end_row, end_col = context_node:range()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  
  -- Adjust first and last lines for partial content
  if #lines > 0 then
    lines[1] = lines[1]:sub(start_col + 1)
    if #lines > 1 then
      lines[#lines] = lines[#lines]:sub(1, end_col)
    end
  end
  
  context.content = table.concat(lines, '\n')
  context.node_type = context_node:type()
  context.range = {start_row, start_col, end_row, end_col}
  
  -- Get surrounding context if requested
  if opts.include_siblings then
    context.siblings = M.extract_siblings(context_node, bufnr)
  end
  
  -- Update current function and class
  local parent = context_node:parent()
  while parent do
    if vim.tbl_contains(M.node_types.function_like, parent:type()) and not context.current_function then
      context.current_function = utils.get_node_text(parent, bufnr):match("^[^\n]+")
    elseif vim.tbl_contains(M.node_types.class_like, parent:type()) and not context.current_class then
      context.current_class = utils.get_node_text(parent, bufnr):match("^[^\n]+")
    end
    parent = parent:parent()
  end
  
  -- Cache the context
  M._cache[cache_key] = context
  
  return context
end

-- Extract sibling nodes (functions/methods at the same level)
function M.extract_siblings(node, bufnr)
  local siblings = {}
  local parent = node:parent()
  if not parent then return siblings end
  
  for child in parent:iter_children() do
    if child ~= node and vim.tbl_contains(M.node_types.function_like, child:type()) then
      table.insert(siblings, {
        type = child:type(),
        name = M.get_node_name(child, bufnr),
        range = {child:range()},
      })
    end
  end
  
  return siblings
end

-- Try to extract the name of a node (function name, class name, etc.)
function M.get_node_name(node, bufnr)
  if not node then return nil end

  local ok, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
  if not ok or not ts_utils then return nil end
  -- Look for identifier child nodes
  for child in node:iter_children() do
    if child:type() == "identifier" or child:type() == "name" then
      return ts_utils.get_node_text(child, bufnr)
    end
  end
  
  -- Fallback: get first line and try to extract name
  local text = ts_utils.get_node_text(node, bufnr)
  local first_line = vim.split(text, "\n")[1]
  
  -- Common patterns
  local patterns = {
    "function%s+([%w_]+)",
    "def%s+([%w_]+)",
    "class%s+([%w_]+)",
    "struct%s+([%w_]+)",
    "interface%s+([%w_]+)",
  }
  
  for _, pattern in ipairs(patterns) do
    local name = first_line:match(pattern)
    if name then return name end
  end
  
  return nil
end

-- Update cursor context (called on cursor movement)
function M.update_cursor_context()
  local ok, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
  if not ok or not ts_utils then return end
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Skip special buffers that don't need Tree-sitter
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    -- Special buffer types like 'help', 'terminal', 'quickfix', etc.
    M._cursor_context = nil
    return
  end
  
  -- Skip if filetype is empty or known to not have Tree-sitter support
  local filetype = vim.bo[bufnr].filetype
  if filetype == "" or filetype == "text" or filetype == "conf" then
    M._cursor_context = nil
    return
  end
  
  local node = M.get_node_at_cursor()
  if not node then
    M._cursor_context = nil
    return
  end
  
  -- Find the smallest interesting node
  local context_node = node
  while context_node do
    local node_type = context_node:type()
    if vim.tbl_contains(M.node_types.function_like, node_type) or
       vim.tbl_contains(M.node_types.class_like, node_type) then
      break
    end
    context_node = context_node:parent()
  end
  
  if context_node then
    M._cursor_context = {
      node = context_node,
      type = context_node:type(),
      name = M.get_node_name(context_node),
      range = {context_node:range()},
    }
  else
    M._cursor_context = nil
  end
end

-- Get current cursor context
function M.get_cursor_context()
  return M._cursor_context
end

-- Build a context string for LLM consumption
function M.build_context_string(context)
  if not context then return "" end
  
  local parts = {}
  
  -- File information
  table.insert(parts, string.format("File: %s", context.file_path or "unknown"))
  table.insert(parts, string.format("Language: %s", context.language or "unknown"))
  
  -- Documentation
  if context.documentation then
    table.insert(parts, "\nDocumentation:")
    table.insert(parts, context.documentation)
  end
  
  -- Imports
  if context.imports and #context.imports > 0 then
    table.insert(parts, "\nImports:")
    for _, import in ipairs(context.imports) do
      table.insert(parts, import)
    end
  end
  
  -- Parent context
  if context.parent then
    table.insert(parts, string.format("\nParent: %s %s", 
      context.parent.type, context.parent.name or ""))
  end
  
  -- Main content
  table.insert(parts, "\nCode:")
  table.insert(parts, context.content)
  
  -- Siblings
  if context.siblings and #context.siblings > 0 then
    table.insert(parts, "\nSibling functions/methods:")
    for _, sibling in ipairs(context.siblings) do
      table.insert(parts, string.format("- %s %s", 
        sibling.type, sibling.name or "unnamed"))
    end
  end
  
  return table.concat(parts, "\n")
end

-- Build context specifically for code completion
function M.build_completion_context(opts)
  opts = opts or {}
  local bufnr = tonumber(opts.bufnr) or vim.api.nvim_get_current_buf()
  
  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  
  -- Get lines around cursor (before and current line up to cursor)
  local context_lines = math.min(row + 1, 50) -- Last 50 lines or less
  local start_line = math.max(0, row - context_lines + 1)
  
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, row + 1, false)
  
  -- Truncate the last line at cursor position
  if #lines > 0 then
    lines[#lines] = lines[#lines]:sub(1, col)
  end
  
  -- Get the current scope context
  local ctx = M.collect(opts)
  
  -- Build a focused context
  local parts = {}
  
  -- Add file and language info
  table.insert(parts, string.format("File: %s", vim.fn.expand("%:~")))
  table.insert(parts, string.format("Language: %s", vim.bo.filetype))
  
  -- Add imports if available
  if ctx and ctx.imports and #ctx.imports > 0 then
    table.insert(parts, "\nImports:")
    for _, import in ipairs(ctx.imports) do
      table.insert(parts, import)
    end
  end
  
  -- Add current function/class context if available
  if ctx and ctx.node_type then
    table.insert(parts, string.format("\nCurrent scope: %s %s", 
      ctx.node_type, 
      ctx.name or "anonymous"))
  end
  
  -- Add the code leading up to cursor
  table.insert(parts, "\nCode context (cursor at end):")
  table.insert(parts, table.concat(lines, "\n"))
  
  return table.concat(parts, "\n")
end

-- Clear cache
function M.clear_cache()
  M._cache = {}
end

-- Find the most relevant context node (function, class, etc.)
function M.find_context_node(node)
  if not node then return nil end
  
  local current = node
  
  -- Walk up the tree to find the first function or class-like node
  while current do
    local node_type = current:type()
    
    -- Check if this is a function-like node
    if vim.tbl_contains(M.node_types.function_like, node_type) then
      return current
    end
    
    -- Check if this is a class-like node
    if vim.tbl_contains(M.node_types.class_like, node_type) then
      return current
    end
    
    -- Move to parent
    current = current:parent()
  end
  
  -- If no function or class found, return the original node
  return node
end

return M 
