-- Project-Wide Consistency Enforcer
-- Learns and enforces coding patterns across the codebase

local M = {}

local intelligence = require('caramba.intelligence')
local llm = require('caramba.llm')
local pair = require('caramba.pair')

-- Pattern database
M.patterns = {
  naming = {
    functions = {},
    variables = {},
    classes = {},
    files = {},
  },
  structure = {
    file_organization = {},
    import_order = {},
    export_patterns = {},
  },
  style = {
    indentation = {},
    line_length = {},
    comment_style = {},
  },
  architecture = {
    layer_rules = {},
    dependency_rules = {},
    module_boundaries = {},
  },
  performance = {
    common_patterns = {},
    anti_patterns = {},
  },
  security = {
    vulnerabilities = {},
    best_practices = {},
  },
}

-- Learn patterns from codebase
M.learn_patterns = function(opts)
  opts = opts or {}
  local root = opts.root or vim.fn.getcwd()
  
  vim.notify("Learning project patterns...", vim.log.levels.INFO)
  
  -- Learn naming conventions
  M._learn_naming_conventions(root)
  
  -- Learn file structure
  M._learn_file_structure(root)
  
  -- Learn architectural patterns
  M._learn_architecture(root)
  
  -- Learn style patterns
  M._learn_style_patterns(root)
  
  -- Save learned patterns
  M._save_patterns()
  
  vim.notify("Pattern learning complete!", vim.log.levels.INFO)
end

-- Learn naming conventions
M._learn_naming_conventions = function(root)
  -- Get all symbols from intelligence engine
  if not intelligence.db.symbols then
    vim.notify("Please run :AIIndexProject first", vim.log.levels.WARN)
    return
  end
  
  -- Analyze function names
  local function_names = {}
  local variable_names = {}
  local class_names = {}
  
  for symbol_name, locations in pairs(intelligence.db.symbols) do
    for _, loc in ipairs(locations) do
      if loc.type == "function" then
        table.insert(function_names, symbol_name)
      elseif loc.type == "variable" then
        table.insert(variable_names, symbol_name)
      elseif loc.type == "class" then
        table.insert(class_names, symbol_name)
      end
    end
  end
  
  -- Detect patterns
  M.patterns.naming.functions = M._analyze_naming_pattern(function_names, "function")
  M.patterns.naming.variables = M._analyze_naming_pattern(variable_names, "variable")
  M.patterns.naming.classes = M._analyze_naming_pattern(class_names, "class")
end

-- Analyze naming patterns
M._analyze_naming_pattern = function(names, type)
  local patterns = {
    style = nil, -- camelCase, snake_case, PascalCase
    prefixes = {},
    suffixes = {},
    common_words = {},
    average_length = 0,
  }
  
  if #names == 0 then return patterns end
  
  -- Detect case style
  local camelCase = 0
  local snake_case = 0
  local PascalCase = 0
  
  for _, name in ipairs(names) do
    if name:match("^[a-z]") and name:match("[A-Z]") then
      camelCase = camelCase + 1
    elseif name:match("_") then
      snake_case = snake_case + 1
    elseif name:match("^[A-Z]") and not name:match("_") then
      PascalCase = PascalCase + 1
    end
    
    -- Track length
    patterns.average_length = patterns.average_length + #name
  end
  
  patterns.average_length = math.floor(patterns.average_length / #names)
  
  -- Determine dominant style
  if camelCase > snake_case and camelCase > PascalCase then
    patterns.style = "camelCase"
  elseif snake_case > camelCase and snake_case > PascalCase then
    patterns.style = "snake_case"
  elseif PascalCase > camelCase and PascalCase > snake_case then
    patterns.style = "PascalCase"
  end
  
  -- Find common prefixes/suffixes
  local prefix_count = {}
  local suffix_count = {}
  
  for _, name in ipairs(names) do
    -- Check common prefixes
    local prefixes = {"get", "set", "is", "has", "can", "should", "will", "did", "handle", "on"}
    for _, prefix in ipairs(prefixes) do
      if name:match("^" .. prefix) then
        prefix_count[prefix] = (prefix_count[prefix] or 0) + 1
      end
    end
    
    -- Check common suffixes
    local suffixes = {"Handler", "Controller", "Service", "Manager", "Helper", "Utils", "Config"}
    for _, suffix in ipairs(suffixes) do
      if name:match(suffix .. "$") then
        suffix_count[suffix] = (suffix_count[suffix] or 0) + 1
      end
    end
  end
  
  -- Store frequent patterns
  for prefix, count in pairs(prefix_count) do
    if count > #names * 0.1 then -- More than 10% usage
      table.insert(patterns.prefixes, prefix)
    end
  end
  
  for suffix, count in pairs(suffix_count) do
    if count > #names * 0.1 then
      table.insert(patterns.suffixes, suffix)
    end
  end
  
  return patterns
end

-- Learn file structure patterns
M._learn_file_structure = function(root)
  -- Analyze directory structure
  local structure = {}
  
  -- Common directories
  local common_dirs = {
    "src", "lib", "components", "utils", "helpers", "services",
    "models", "controllers", "views", "tests", "spec", "__tests__",
  }
  
  for _, dir in ipairs(common_dirs) do
    if vim.fn.isdirectory(root .. "/" .. dir) == 1 then
      structure[dir] = true
    end
  end
  
  M.patterns.structure.file_organization = structure
  
  -- Analyze import patterns
  M._analyze_import_patterns(root)
end

-- Analyze import ordering
M._analyze_import_patterns = function(root)
  local files = vim.fn.systemlist("find " .. root .. " -name '*.js' -o -name '*.ts' -o -name '*.py' | head -20")
  
  local import_orders = {}
  
  for _, file in ipairs(files) do
    local lines = vim.fn.readfile(file, '', 50) -- First 50 lines
    local imports = {}
    
    for _, line in ipairs(lines) do
      if line:match("^import") or line:match("^from.*import") then
        local category = M._categorize_import(line)
        table.insert(imports, category)
      elseif line ~= "" and not line:match("^%s*$") and not line:match("^%s*//") then
        -- Non-import, non-comment line - imports section ended
        break
      end
    end
    
    if #imports > 0 then
      table.insert(import_orders, imports)
    end
  end
  
  -- Find most common pattern
  M.patterns.structure.import_order = M._find_common_import_order(import_orders)
end

-- Categorize import statement
M._categorize_import = function(import_line)
  if import_line:match("^import.*from%s+['\"]react") then
    return "react"
  elseif import_line:match("^import.*from%s+['\"]%.") then
    return "relative"
  elseif import_line:match("^import.*from%s+['\"]@") then
    return "alias"
  elseif import_line:match("^import.*from%s+['\"][^./]") then
    return "external"
  else
    return "other"
  end
end

-- Find common import order
M._find_common_import_order = function(orders)
  -- Simplified: return most frequent first category
  local first_categories = {}
  
  for _, order in ipairs(orders) do
    if order[1] then
      first_categories[order[1]] = (first_categories[order[1]] or 0) + 1
    end
  end
  
  -- Find most common
  local max_count = 0
  local common_first = "external"
  
  for category, count in pairs(first_categories) do
    if count > max_count then
      max_count = count
      common_first = category
    end
  end
  
  -- Typical order
  local typical_order = {
    external = {"external", "react", "alias", "relative"},
    react = {"react", "external", "alias", "relative"},
    relative = {"external", "react", "alias", "relative"},
  }
  
  return typical_order[common_first] or typical_order.external
end

-- Learn architectural patterns
M._learn_architecture = function(root)
  -- Detect layer violations
  local violations = M._detect_layer_violations(root)
  
  -- Learn module boundaries
  M._learn_module_boundaries(root)
  
  -- Store rules
  M.patterns.architecture.layer_rules = {
    violations_found = violations,
    strict_layers = #violations == 0,
  }
end

-- Detect layer violations
M._detect_layer_violations = function(root)
  local violations = {}
  
  -- Common architectural layers
  local layers = {
    { name = "controllers", forbidden_imports = {"models", "database"} },
    { name = "services", forbidden_imports = {"controllers", "routes"} },
    { name = "models", forbidden_imports = {"controllers", "services", "views"} },
    { name = "utils", forbidden_imports = {"controllers", "services", "models"} },
  }
  
  -- Check each layer
  for _, layer in ipairs(layers) do
    local layer_files = vim.fn.systemlist("find " .. root .. " -path '*/" .. layer.name .. "/*' -name '*.js' -o -name '*.ts' 2>/dev/null")
    
    for _, file in ipairs(layer_files) do
      local content = table.concat(vim.fn.readfile(file), '\n')
      
      -- Check for forbidden imports
      for _, forbidden in ipairs(layer.forbidden_imports) do
        if content:match("from.*/" .. forbidden .. "/") then
          table.insert(violations, {
            file = file,
            layer = layer.name,
            forbidden_import = forbidden,
          })
        end
      end
    end
  end
  
  return violations
end

-- Learn module boundaries
M._learn_module_boundaries = function(root)
  -- Detect if using module pattern
  local has_modules = vim.fn.isdirectory(root .. "/modules") == 1 or
                     vim.fn.isdirectory(root .. "/features") == 1
  
  if has_modules then
    M.patterns.architecture.module_boundaries = {
      enforced = true,
      pattern = "modular",
    }
  else
    M.patterns.architecture.module_boundaries = {
      enforced = false,
      pattern = "traditional",
    }
  end
end

-- Learn style patterns
M._learn_style_patterns = function(root)
  -- Sample some files
  local files = vim.fn.systemlist("find " .. root .. " -name '*.js' -o -name '*.ts' -o -name '*.py' | head -10")
  
  local indentations = {}
  local line_lengths = {}
  
  for _, file in ipairs(files) do
    local lines = vim.fn.readfile(file, '', 100)
    
    for _, line in ipairs(lines) do
      -- Detect indentation
      local indent = line:match("^(%s+)")
      if indent and #indent > 0 then
        table.insert(indentations, #indent)
      end
      
      -- Track line length
      if #line > 0 then
        table.insert(line_lengths, #line)
      end
    end
  end
  
  -- Analyze patterns
  if #indentations > 0 then
    -- Find most common indentation
    local indent_counts = {}
    for _, indent in ipairs(indentations) do
      indent_counts[indent] = (indent_counts[indent] or 0) + 1
    end
    
    local max_count = 0
    local common_indent = 2
    
    for indent, count in pairs(indent_counts) do
      if count > max_count and (indent == 2 or indent == 4) then
        max_count = count
        common_indent = indent
      end
    end
    
    M.patterns.style.indentation = {
      size = common_indent,
      type = common_indent == 2 and "spaces" or "spaces", -- Simplified
    }
  end
  
  -- Average line length
  if #line_lengths > 0 then
    local total = 0
    local max_length = 0
    
    for _, length in ipairs(line_lengths) do
      total = total + length
      max_length = math.max(max_length, length)
    end
    
    M.patterns.style.line_length = {
      average = math.floor(total / #line_lengths),
      max_observed = max_length,
      recommended = max_length > 100 and 100 or max_length,
    }
  end
end

-- Check file consistency
M.check_file = function(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  
  -- Ensure patterns are loaded
  if not M.patterns or not M.patterns.style or not M.patterns.naming then
    vim.notify("No consistency patterns found. Run :AILearnPatterns first to analyze your project.", vim.log.levels.WARN)
    return {}
  end
  
  local issues = {}
  
  -- Check naming conventions
  local naming_issues = M._check_naming_conventions(bufnr)
  vim.list_extend(issues, naming_issues)
  
  -- Check import order
  local import_issues = M._check_import_order(bufnr)
  vim.list_extend(issues, import_issues)
  
  -- Check architectural compliance
  local arch_issues = M._check_architecture_compliance(filename)
  vim.list_extend(issues, arch_issues)
  
  -- Check style consistency
  local style_issues = M._check_style_consistency(bufnr)
  vim.list_extend(issues, style_issues)
  
  -- Show results
  if #issues > 0 then
    M._show_consistency_report(issues)
  else
    vim.notify("No consistency issues found!", vim.log.levels.INFO)
  end
  
  return issues
end

-- Check naming conventions
M._check_naming_conventions = function(bufnr)
  local issues = {}
  local symbols = intelligence.extract_symbols(bufnr)
  
  for _, symbol in ipairs(symbols) do
    local expected_style = nil
    
    if symbol.type == "function" then
      expected_style = M.patterns.naming.functions.style
    elseif symbol.type == "class" then
      expected_style = M.patterns.naming.classes.style or "PascalCase"
    elseif symbol.type == "variable" then
      expected_style = M.patterns.naming.variables.style
    end
    
    if expected_style then
      local matches = M._matches_naming_style(symbol.name, expected_style)
      
      if not matches then
        table.insert(issues, {
          type = "naming",
          severity = "warning",
          line = symbol.line,
          message = string.format("%s '%s' doesn't follow %s convention",
            symbol.type, symbol.name, expected_style),
          symbol = symbol,
          expected_style = expected_style,
        })
      end
    end
  end
  
  return issues
end

-- Check if name matches style
M._matches_naming_style = function(name, style)
  if style == "camelCase" then
    return name:match("^[a-z]") and not name:match("_")
  elseif style == "snake_case" then
    return name:match("_") or (name:match("^[a-z]") and not name:match("[A-Z]"))
  elseif style == "PascalCase" then
    return name:match("^[A-Z]") and not name:match("_")
  end
  
  return true -- Unknown style, allow
end

-- Check import order
M._check_import_order = function(bufnr)
  local issues = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  local imports = {}
  local import_lines = {}
  
  for i, line in ipairs(lines) do
    if line:match("^import") or line:match("^from.*import") then
      local category = M._categorize_import(line)
      table.insert(imports, category)
      table.insert(import_lines, i)
    elseif line ~= "" and not line:match("^%s*$") and not line:match("^%s*//") then
      break
    end
  end
  
  -- Check order
  local expected_order = M.patterns.structure.import_order
  if expected_order and #imports > 1 then
    local last_index = 0
    
    for i, category in ipairs(imports) do
      local expected_index = vim.tbl_contains(expected_order, category) and
                           vim.fn.index(expected_order, category) or 999
      
      if expected_index < last_index then
        table.insert(issues, {
          type = "import_order",
          severity = "hint",
          line = import_lines[i],
          message = string.format("Import '%s' should come before '%s' imports",
            category, imports[i-1]),
        })
      end
      
      last_index = math.max(last_index, expected_index)
    end
  end
  
  return issues
end

-- Check architecture compliance
M._check_architecture_compliance = function(filename)
  local issues = {}
  
  -- Check layer violations
  if M.patterns.architecture.layer_rules.strict_layers then
    -- Determine current layer
    local current_layer = nil
    for layer in filename:gmatch("/(%w+)/") do
      if vim.tbl_contains({"controllers", "services", "models", "views", "utils"}, layer) then
        current_layer = layer
        break
      end
    end
    
    if current_layer then
      -- Read file content
      local content = table.concat(vim.fn.readfile(filename), '\n')
      
      -- Check for violations based on layer
      local forbidden = {
        controllers = {"models", "database"},
        services = {"controllers", "routes"},
        models = {"controllers", "services", "views"},
        utils = {"controllers", "services", "models"},
      }
      
      local forbidden_imports = forbidden[current_layer] or {}
      
      for _, forbidden_layer in ipairs(forbidden_imports) do
        if content:match("from.*/" .. forbidden_layer .. "/") or
           content:match("require.*/" .. forbidden_layer .. "/") then
          table.insert(issues, {
            type = "architecture",
            severity = "error",
            line = 1, -- Would need to find actual line
            message = string.format("Layer violation: %s should not import from %s",
              current_layer, forbidden_layer),
          })
        end
      end
    end
  end
  
  return issues
end

-- Check style consistency
M._check_style_consistency = function(bufnr)
  local issues = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  for i, line in ipairs(lines) do
    -- Check line length
    if M.patterns.style.line_length and M.patterns.style.line_length.recommended and #line > M.patterns.style.line_length.recommended then
      table.insert(issues, {
        type = "style",
        severity = "hint",
        line = i,
        message = string.format("Line too long (%d > %d characters)",
          #line, M.patterns.style.line_length.recommended),
      })
    end
    
    -- Check indentation
    if M.patterns.style.indentation and M.patterns.style.indentation.size then
      local indent = line:match("^(%s+)")
      if indent and #indent % M.patterns.style.indentation.size ~= 0 then
        table.insert(issues, {
          type = "style",
          severity = "warning",
          line = i,
          message = string.format("Inconsistent indentation (expected multiples of %d)",
            M.patterns.style.indentation.size),
        })
      end
    end
  end
  
  return issues
end

-- Show consistency report
M._show_consistency_report = function(issues)
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Group issues by type
  local by_type = {}
  for _, issue in ipairs(issues) do
    if not by_type[issue.type] then
      by_type[issue.type] = {}
    end
    table.insert(by_type[issue.type], issue)
  end
  
  local lines = {
    "# Consistency Report",
    "",
    string.format("Found %d consistency issues", #issues),
    "",
  }
  
  -- Show each type
  for type, type_issues in pairs(by_type) do
    table.insert(lines, "## " .. type:gsub("_", " "):gsub("^%l", string.upper))
    table.insert(lines, "")
    
    for _, issue in ipairs(type_issues) do
      local severity_icon = {
        error = "❌",
        warning = "⚠️",
        hint = "💡",
      }
      
      table.insert(lines, string.format("%s Line %d: %s",
        severity_icon[issue.severity] or "•",
        issue.line,
        issue.message))
    end
    
    table.insert(lines, "")
  end
  
  -- Add fix suggestions
  table.insert(lines, "## Quick Actions")
  table.insert(lines, "")
  table.insert(lines, "- Press `f` to auto-fix issues")
  table.insert(lines, "- Press `i` to ignore an issue")
  table.insert(lines, "- Press `a` to apply all fixes")
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  -- Store issues for fixes
  vim.b[buf].consistency_issues = issues
  
  -- Add keymaps
  vim.keymap.set('n', 'f', function()
    M._fix_issue_at_cursor(buf)
  end, { buffer = buf, desc = "Fix issue at cursor" })
  
  vim.keymap.set('n', 'a', function()
    M._fix_all_issues(issues)
  end, { buffer = buf, desc = "Fix all issues" })
  
  vim.cmd('split')
  vim.api.nvim_set_current_buf(buf)
end

-- Fix issue at cursor
M._fix_issue_at_cursor = function(report_buf)
  local line = vim.fn.line('.')
  local issues = vim.b[report_buf].consistency_issues
  
  -- Find issue for this line
  -- (Would need more sophisticated mapping in production)
  
  vim.notify("Auto-fix not yet implemented for individual issues", vim.log.levels.INFO)
end

-- Fix all issues
M._fix_all_issues = function(issues)
  -- Group by file
  local by_file = {}
  
  for _, issue in ipairs(issues) do
    local file = issue.file or vim.api.nvim_buf_get_name(0)
    if not by_file[file] then
      by_file[file] = {}
    end
    table.insert(by_file[file], issue)
  end
  
  -- Generate fixes
  for file, file_issues in pairs(by_file) do
    M._generate_fixes_for_file(file, file_issues)
  end
end

-- Generate fixes for a file
M._generate_fixes_for_file = function(file, issues)
  local content = table.concat(vim.fn.readfile(file), '\n')
  
  -- Build issue description
  local issue_desc = {}
  for _, issue in ipairs(issues) do
    table.insert(issue_desc, string.format("- Line %d: %s", issue.line, issue.message))
  end
  
  local prompt = string.format([[
Fix the following consistency issues in this code:

File: %s

Issues:
%s

Current code:
```
%s
```

Fix all issues while preserving functionality. Return only the fixed code.
]], file, table.concat(issue_desc, '\n'), content)
  
  llm.request(prompt, { temperature = 1 }, function(response)
    if response then
      vim.schedule(function()
        -- Show preview
        local preview_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, vim.split(response, '\n'))
        vim.api.nvim_buf_set_option(preview_buf, 'filetype', vim.fn.fnamemodify(file, ':e'))
        
        vim.cmd('tabnew')
        vim.api.nvim_set_current_buf(preview_buf)
        
        vim.keymap.set('n', 'a', function()
          vim.fn.writefile(vim.split(response, '\n'), file)
          vim.cmd('tabclose')
          vim.notify("Consistency fixes applied to " .. file, vim.log.levels.INFO)
        end, { buffer = preview_buf, desc = "Apply fixes" })
        
        vim.notify("Review fixes and press 'a' to apply", vim.log.levels.INFO)
      end)
    end
  end)
end

-- Save learned patterns
M._save_patterns = function()
  local path = vim.fn.stdpath('data') .. '/ai_consistency_patterns.json'
  local json = vim.json.encode(M.patterns)
  vim.fn.writefile({json}, path)
end

-- Load patterns
M.load_patterns = function()
  local path = vim.fn.stdpath('data') .. '/ai_consistency_patterns.json'
  if vim.fn.filereadable(path) == 1 then
    local lines = vim.fn.readfile(path)
    if #lines > 0 then
      local ok, data = pcall(vim.json.decode, lines[1])
      if ok then
        M.patterns = data
      end
    end
  end
end

-- Auto-check on save
M.enable_auto_check = function()
  local group = vim.api.nvim_create_augroup("ConsistencyCheck", { clear = true })
  
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = {"*.js", "*.ts", "*.jsx", "*.tsx", "*.py", "*.lua"},
    callback = function()
      local issues = M.check_file({ bufnr = vim.api.nvim_get_current_buf() })
      
      if #issues > 0 then
        -- Show as diagnostics
        local diagnostics = {}
        
        for _, issue in ipairs(issues) do
          table.insert(diagnostics, {
            lnum = issue.line - 1,
            col = 0,
            severity = vim.diagnostic.severity[issue.severity:upper()] or
                      vim.diagnostic.severity.HINT,
            message = issue.message,
            source = "consistency",
          })
        end
        
        vim.diagnostic.set(
          vim.api.nvim_create_namespace("consistency"),
          vim.api.nvim_get_current_buf(),
          diagnostics
        )
      end
    end,
  })
  
  vim.notify("Auto consistency checking enabled", vim.log.levels.INFO)
end

-- Initialize
M.setup = function()
  M.load_patterns()
end

-- Setup commands for this module
M.setup_commands = function()
  local commands = require('caramba.core.commands')
  
  -- Learn patterns from codebase
  commands.register('LearnPatterns', M.learn_patterns, {
    desc = 'Learn coding patterns from the current project',
  })
  
  -- Check current file consistency
  commands.register('CheckConsistency', M.check_file, {
    desc = 'Check current file for consistency issues',
  })
  
  -- Enable auto-check on save
  commands.register('EnableConsistencyCheck', M.enable_auto_check, {
    desc = 'Enable automatic consistency checking on file save',
  })
  
  -- Disable auto-check
  commands.register('DisableConsistencyCheck', function()
    vim.api.nvim_del_augroup_by_name("ConsistencyCheck")
    vim.notify("Auto consistency checking disabled", vim.log.levels.INFO)
  end, {
    desc = 'Disable automatic consistency checking',
  })
  
  -- Fix all issues in current file
  commands.register('FixConsistencyIssues', function()
    local issues = M.check_file({ bufnr = vim.api.nvim_get_current_buf() })
    if #issues > 0 then
      M._fix_all_issues(issues)
    else
      vim.notify("No consistency issues found!", vim.log.levels.INFO)
    end
  end, {
    desc = 'Automatically fix consistency issues in current file',
  })
end

return M 