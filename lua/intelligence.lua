-- Local Code Intelligence Engine
-- Provides advanced code analysis without external dependencies

local M = {}

local parsers = require('nvim-treesitter.parsers')
local ts_utils = require('nvim-treesitter.ts_utils')
local Path = require('plenary.path')

-- Initialize the intelligence database
M.db = {
  symbols = {},      -- Global symbol index
  types = {},        -- Type information
  dependencies = {}, -- Dependency graph
  usage = {},        -- Usage patterns
  impacts = {},      -- Impact analysis cache
}

-- Symbol types
M.symbol_types = {
  FUNCTION = "function",
  CLASS = "class",
  METHOD = "method",
  VARIABLE = "variable",
  CONSTANT = "constant",
  TYPE = "type",
  INTERFACE = "interface",
  MODULE = "module",
}

-- Extract symbols from a buffer
M.extract_symbols = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local parser = parsers.get_parser(bufnr)
  if not parser then return {} end
  
  local symbols = {}
  local lang = parser:lang()
  
  -- Language-specific queries
  local queries = {
    javascript = [[
      (function_declaration name: (identifier) @function.name)
      (variable_declarator 
        name: (identifier) @variable.name
        value: (arrow_function))
      (class_declaration name: (identifier) @class.name)
      (method_definition key: (property_identifier) @method.name)
    ]],
    
    typescript = [[
      (function_declaration name: (identifier) @function.name)
      (variable_declarator 
        name: (identifier) @variable.name
        value: (arrow_function))
      (class_declaration name: (identifier) @class.name)
      (method_definition key: (property_identifier) @method.name)
      (interface_declaration name: (type_identifier) @interface.name)
      (type_alias_declaration name: (type_identifier) @type.name)
    ]],
    
    python = [[
      (function_definition name: (identifier) @function.name)
      (class_definition name: (identifier) @class.name)
    ]],
    
    lua = [[
      (function_declaration name: (identifier) @function.name)
      (assignment_statement
        (variable_list name: (identifier) @variable.name)
        (expression_list value: (function_definition)))
    ]],
  }
  
  local query_string = queries[lang]
  if not query_string then return symbols end
  
  local query = vim.treesitter.query.parse(lang, query_string)
  local tree = parser:parse()[1]
  local root = tree:root()
  
  -- Extract symbols
  for pattern, match, metadata in query:iter_matches(root, bufnr) do
    for id, node in pairs(match) do
      local name = vim.treesitter.get_node_text(node, bufnr)
      local capture_name = query.captures[id]
      local symbol_type = capture_name:match("^(%w+)")
      
      -- Get location info
      local start_row, start_col, end_row, end_col = node:range()
      
      table.insert(symbols, {
        name = name,
        type = symbol_type,
        file = vim.api.nvim_buf_get_name(bufnr),
        line = start_row + 1,
        col = start_col + 1,
        end_line = end_row + 1,
        end_col = end_col + 1,
        node = node,
      })
    end
  end
  
  return symbols
end

-- Build project-wide symbol index
M.index_project = function(opts)
  opts = opts or {}
  local root = opts.root or vim.fn.getcwd()
  
  M.db.symbols = {}
  
  -- Find all source files
  local files = vim.fn.systemlist("find " .. root .. " -type f -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.lua' | grep -v node_modules | grep -v .git")
  
  local total = #files
  local processed = 0
  
  for _, file in ipairs(files) do
    -- Load file into temporary buffer
    local lines = vim.fn.readfile(file)
    if #lines > 0 then
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      
      -- Set filetype for proper parsing
      local ext = vim.fn.fnamemodify(file, ':e')
      local ft = M._ext_to_filetype(ext)
      vim.api.nvim_buf_set_option(buf, 'filetype', ft)
      
      -- Extract symbols
      local symbols = M.extract_symbols(buf)
      for _, symbol in ipairs(symbols) do
        symbol.file = file -- Ensure absolute path
        M.db.symbols[symbol.name] = M.db.symbols[symbol.name] or {}
        table.insert(M.db.symbols[symbol.name], symbol)
      end
      
      -- Clean up
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    
    processed = processed + 1
    if processed % 10 == 0 then
      vim.notify(string.format("Indexing: %d/%d files", processed, total))
    end
  end
  
  vim.notify(string.format("Indexed %d symbols from %d files", vim.tbl_count(M.db.symbols), total))
  
  -- Build dependency graph
  M._build_dependency_graph()
end

-- Build dependency graph
M._build_dependency_graph = function()
  M.db.dependencies = {}
  
  -- Analyze each file for imports/requires
  local processed_files = {}
  
  for symbol_name, locations in pairs(M.db.symbols) do
    for _, location in ipairs(locations) do
      local file = location.file
      
      if not processed_files[file] then
        processed_files[file] = true
        
        -- Extract dependencies based on file type
        local ext = vim.fn.fnamemodify(file, ':e')
        local deps = M._extract_dependencies(file, ext)
        
        M.db.dependencies[file] = deps
      end
    end
  end
end

-- Extract dependencies from a file
M._extract_dependencies = function(file, ext)
  local content = table.concat(vim.fn.readfile(file), '\n')
  local deps = {}
  
  -- Pattern matching for different languages
  local patterns = {
    js = {
      "import%s+.-%s+from%s+['\"]([^'\"]+)['\"]",
      "require%s*%(s*['\"]([^'\"]+)['\"]%s*%)",
    },
    ts = {
      "import%s+.-%s+from%s+['\"]([^'\"]+)['\"]",
      "require%s*%(s*['\"]([^'\"]+)['\"]%s*%)",
    },
    py = {
      "from%s+([%w%.]+)%s+import",
      "import%s+([%w%.]+)",
    },
    lua = {
      "require%s*%(s*['\"]([^'\"]+)['\"]%s*%)",
      "require%s*'([^']+)'",
    },
  }
  
  local lang_patterns = patterns[ext] or {}
  
  for _, pattern in ipairs(lang_patterns) do
    for match in content:gmatch(pattern) do
      table.insert(deps, match)
    end
  end
  
  return deps
end

-- Type flow analysis
M.analyze_type_flow = function(symbol_name)
  local locations = M.db.symbols[symbol_name]
  if not locations then
    return { error = "Symbol not found" }
  end
  
  local flow = {
    symbol = symbol_name,
    definitions = {},
    usages = {},
    type_hints = {},
  }
  
  -- Find all usages of the symbol
  local usage_cmd = string.format("rg -n '\\b%s\\b' --type-add 'code:*.{js,ts,py,lua}' -t code", 
    vim.fn.escape(symbol_name, '\\'))
  local usages = vim.fn.systemlist(usage_cmd)
  
  for _, usage_line in ipairs(usages) do
    local file, line, content = usage_line:match("([^:]+):(%d+):(.+)")
    if file and line then
      table.insert(flow.usages, {
        file = file,
        line = tonumber(line),
        content = content,
      })
      
      -- Try to infer type from usage context
      local type_hint = M._infer_type_from_context(content, symbol_name)
      if type_hint then
        flow.type_hints[type_hint] = (flow.type_hints[type_hint] or 0) + 1
      end
    end
  end
  
  -- Determine most likely type
  local max_count = 0
  local likely_type = "unknown"
  for type_hint, count in pairs(flow.type_hints) do
    if count > max_count then
      max_count = count
      likely_type = type_hint
    end
  end
  
  flow.likely_type = likely_type
  return flow
end

-- Infer type from usage context
M._infer_type_from_context = function(line, symbol)
  -- Simple heuristics for type inference
  local patterns = {
    { pattern = symbol .. "%.length", type = "array/string" },
    { pattern = symbol .. "%.push%(", type = "array" },
    { pattern = symbol .. "%.map%(", type = "array" },
    { pattern = symbol .. "%.charAt%(", type = "string" },
    { pattern = symbol .. "%.toUpperCase%(", type = "string" },
    { pattern = symbol .. "%s*%+%s*%d", type = "number" },
    { pattern = symbol .. "%s*%-%s*%d", type = "number" },
    { pattern = symbol .. "%s*%*%s*%d", type = "number" },
    { pattern = symbol .. "%s*/%s*%d", type = "number" },
    { pattern = symbol .. "%(", type = "function" },
    { pattern = "new%s+" .. symbol, type = "class" },
  }
  
  for _, rule in ipairs(patterns) do
    if line:match(rule.pattern) then
      return rule.type
    end
  end
  
  return nil
end

-- Impact analysis
M.analyze_impact = function(file, line)
  local key = file .. ":" .. line
  
  -- Check cache
  if M.db.impacts[key] then
    return M.db.impacts[key]
  end
  
  local impact = {
    direct = {},    -- Directly affected files
    indirect = {},  -- Indirectly affected files
    critical = {},  -- Critical paths
  }
  
  -- Find what symbol is at this location
  local symbol = M._find_symbol_at_location(file, line)
  if not symbol then
    return impact
  end
  
  -- Find direct dependencies
  local direct_deps = M._find_direct_dependents(symbol.name)
  impact.direct = direct_deps
  
  -- Find indirect dependencies (transitive)
  local visited = {}
  local function find_indirect(deps, level)
    if level > 3 then return end -- Limit depth
    
    for _, dep in ipairs(deps) do
      if not visited[dep.file] then
        visited[dep.file] = true
        table.insert(impact.indirect, dep)
        
        local sub_deps = M._find_direct_dependents(dep.name)
        find_indirect(sub_deps, level + 1)
      end
    end
  end
  
  find_indirect(direct_deps, 1)
  
  -- Identify critical paths
  for _, dep in ipairs(impact.direct) do
    if dep.file:match("test") or dep.file:match("spec") then
      table.insert(impact.critical, {
        file = dep.file,
        reason = "Test file affected",
      })
    elseif dep.file:match("api") or dep.file:match("route") then
      table.insert(impact.critical, {
        file = dep.file,
        reason = "API endpoint affected",
      })
    end
  end
  
  -- Cache result
  M.db.impacts[key] = impact
  
  return impact
end

-- Find direct dependents of a symbol
M._find_direct_dependents = function(symbol_name)
  local dependents = {}
  
  -- Search for files that use this symbol
  local cmd = string.format("rg -l '\\b%s\\b' --type-add 'code:*.{js,ts,py,lua}' -t code", 
    vim.fn.escape(symbol_name, '\\'))
  local files = vim.fn.systemlist(cmd)
  
  for _, file in ipairs(files) do
    -- Check if this file imports/requires the symbol's file
    local deps = M.db.dependencies[file] or {}
    
    -- Get symbol's file
    local symbol_locations = M.db.symbols[symbol_name] or {}
    for _, loc in ipairs(symbol_locations) do
      local symbol_file = loc.file
      local symbol_module = vim.fn.fnamemodify(symbol_file, ':t:r')
      
      for _, dep in ipairs(deps) do
        if dep:match(symbol_module) then
          table.insert(dependents, {
            file = file,
            name = symbol_name,
            type = "import",
          })
          break
        end
      end
    end
  end
  
  return dependents
end

-- Find symbol at specific location
M._find_symbol_at_location = function(file, line)
  for symbol_name, locations in pairs(M.db.symbols) do
    for _, loc in ipairs(locations) do
      if loc.file == file and loc.line <= line and line <= loc.end_line then
        return {
          name = symbol_name,
          type = loc.type,
          location = loc,
        }
      end
    end
  end
  return nil
end

-- Dead code detection
M.find_dead_code = function()
  local dead_code = {
    unused_functions = {},
    unused_variables = {},
    unused_imports = {},
  }
  
  -- Find all symbols
  for symbol_name, locations in pairs(M.db.symbols) do
    for _, loc in ipairs(locations) do
      -- Skip test files
      if not loc.file:match("test") and not loc.file:match("spec") then
        -- Check if symbol is used anywhere
        local usage_cmd = string.format("rg -c '\\b%s\\b' --type-add 'code:*.{js,ts,py,lua}' -t code | grep -v '%s'", 
          vim.fn.escape(symbol_name, '\\'), loc.file)
        local usage_output = vim.fn.system(usage_cmd)
        
        if vim.v.shell_error ~= 0 or usage_output == "" then
          -- No usage found
          local category = "unused_" .. loc.type .. "s"
          if dead_code[category] then
            table.insert(dead_code[category], {
              name = symbol_name,
              file = loc.file,
              line = loc.line,
              confidence = M._calculate_dead_code_confidence(loc),
            })
          end
        end
      end
    end
  end
  
  -- Sort by confidence
  for category, items in pairs(dead_code) do
    table.sort(items, function(a, b)
      return a.confidence > b.confidence
    end)
  end
  
  return dead_code
end

-- Calculate confidence for dead code detection
M._calculate_dead_code_confidence = function(symbol)
  local confidence = 100
  
  -- Reduce confidence for certain patterns
  if symbol.name:match("^_") then
    confidence = confidence - 30 -- Private symbols
  end
  
  if symbol.name:match("^on[A-Z]") or symbol.name:match("^handle[A-Z]") then
    confidence = confidence - 20 -- Event handlers
  end
  
  if symbol.file:match("index") then
    confidence = confidence - 20 -- Index files often export
  end
  
  if symbol.type == "class" then
    confidence = confidence - 10 -- Classes might be instantiated dynamically
  end
  
  return math.max(0, confidence)
end

-- Generate API documentation from usage
M.generate_api_docs = function(symbol_name)
  local flow = M.analyze_type_flow(symbol_name)
  local locations = M.db.symbols[symbol_name] or {}
  
  if #locations == 0 then
    return "Symbol not found"
  end
  
  local doc = {
    "# " .. symbol_name,
    "",
    "## Type Information",
    "Inferred type: `" .. flow.likely_type .. "`",
    "",
    "## Definitions",
  }
  
  for _, loc in ipairs(locations) do
    table.insert(doc, string.format("- %s:%d (type: %s)", loc.file, loc.line, loc.type))
  end
  
  table.insert(doc, "")
  table.insert(doc, "## Usage Examples")
  
  -- Get usage examples
  local examples_shown = 0
  for _, usage in ipairs(flow.usages) do
    if examples_shown < 5 then
      table.insert(doc, string.format("```\n%s\n// %s:%d\n```", 
        vim.trim(usage.content), usage.file, usage.line))
      examples_shown = examples_shown + 1
    end
  end
  
  -- Add impact analysis
  local impact = M.analyze_impact(locations[1].file, locations[1].line)
  
  table.insert(doc, "")
  table.insert(doc, "## Impact Analysis")
  table.insert(doc, string.format("- Direct dependents: %d", #impact.direct))
  table.insert(doc, string.format("- Indirect dependents: %d", #impact.indirect))
  
  if #impact.critical > 0 then
    table.insert(doc, "")
    table.insert(doc, "### Critical Dependencies")
    for _, crit in ipairs(impact.critical) do
      table.insert(doc, string.format("- %s (%s)", crit.file, crit.reason))
    end
  end
  
  return table.concat(doc, "\n")
end

-- Helper to map file extensions to filetypes
M._ext_to_filetype = function(ext)
  local map = {
    js = "javascript",
    ts = "typescript",
    jsx = "javascriptreact",
    tsx = "typescriptreact",
    py = "python",
    lua = "lua",
  }
  return map[ext] or ext
end

-- Show intelligence report
M.show_report = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  local lines = {
    "# Code Intelligence Report",
    "",
    string.format("## Project Overview"),
    string.format("- Total symbols indexed: %d", vim.tbl_count(M.db.symbols)),
    string.format("- Files with dependencies: %d", vim.tbl_count(M.db.dependencies)),
    "",
    "## Symbol Distribution",
  }
  
  -- Count symbols by type
  local type_counts = {}
  for _, locations in pairs(M.db.symbols) do
    for _, loc in ipairs(locations) do
      type_counts[loc.type] = (type_counts[loc.type] or 0) + 1
    end
  end
  
  for type, count in pairs(type_counts) do
    table.insert(lines, string.format("- %s: %d", type, count))
  end
  
  -- Find most used symbols
  table.insert(lines, "")
  table.insert(lines, "## Most Referenced Symbols")
  
  local usage_counts = {}
  for symbol_name, _ in pairs(M.db.symbols) do
    local cmd = string.format("rg -c '\\b%s\\b' --type-add 'code:*.{js,ts,py,lua}' -t code", 
      vim.fn.escape(symbol_name, '\\'))
    local output = vim.fn.system(cmd)
    local total = 0
    for count in output:gmatch(":(%d+)") do
      total = total + tonumber(count)
    end
    if total > 1 then
      usage_counts[symbol_name] = total
    end
  end
  
  -- Sort by usage
  local sorted_symbols = {}
  for symbol, count in pairs(usage_counts) do
    table.insert(sorted_symbols, {symbol = symbol, count = count})
  end
  table.sort(sorted_symbols, function(a, b) return a.count > b.count end)
  
  -- Show top 10
  for i = 1, math.min(10, #sorted_symbols) do
    local item = sorted_symbols[i]
    table.insert(lines, string.format("%d. %s (%d references)", i, item.symbol, item.count))
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  vim.cmd('tabnew')
  vim.api.nvim_set_current_buf(buf)
end

return M 