-- AI Pair Programming Mode
-- Provides real-time, anticipatory coding assistance

local M = {}

local context = require('caramba.context')
local llm = require('caramba.llm')
local intelligence = require('caramba.intelligence')
local config = require('caramba.config')
local utils = require('caramba.utils')
local state_store = require('caramba.state')

-- State management
M.state = state_store.get().pair or {
  enabled = false,
  mode = "normal", -- normal, focused, learning
  last_edit_time = 0,
  edit_history = {},
  suggestions = {},
  patterns = {},
  current_context = nil,
  suggestion_window = nil,
  inline_virtual_text = {},
  active = false,
  session_start = 0,
  suggestions_shown = 0,
  suggestions_accepted = 0,
  learned_patterns = {},
}

state_store.set_namespace('pair', M.state)

-- Pattern learning
M.pattern_db = {
  -- Learned patterns from user's coding style
  naming_conventions = {},
  common_snippets = {},
  error_fixes = {},
  refactoring_patterns = {},
}

-- Enable pair programming mode
M.enable = function(opts)
  opts = opts or {}
  M.state.enabled = true
  M.state.mode = opts.mode or "normal"
  
  -- Set up autocmds
  M._setup_autocmds()
  
  -- Load learned patterns
  M._load_patterns()
  
  -- Start monitoring
  M._start_monitoring()
  
  vim.notify("AI Pair Programming Mode enabled", vim.log.levels.INFO)
end

-- Disable pair programming mode
M.disable = function()
  M.state.enabled = false
  
  -- Clean up autocmds
  if M.autocmd_group then
    vim.api.nvim_del_augroup_by_id(M.autocmd_group)
  end
  
  -- Clear suggestions
  M._clear_suggestions()
  
  vim.notify("AI Pair Programming Mode disabled", vim.log.levels.INFO)
end

-- Toggle pair programming mode
M.toggle = function()
  if M.state.enabled then
    M.disable()
  else
    M.enable()
  end
end

-- Set up autocmds for monitoring
M._setup_autocmds = function()
  M.autocmd_group = vim.api.nvim_create_augroup("AIPairProgramming", { clear = true })
  
  -- Monitor text changes
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    group = M.autocmd_group,
    callback = function()
      if M.state.enabled then
        M._on_text_changed()
      end
    end,
  })
  
  -- Monitor cursor movement
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = M.autocmd_group,
    callback = function()
      if M.state.enabled then
        M._on_cursor_moved()
      end
    end,
  })
  
  -- Monitor mode changes
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = M.autocmd_group,
    callback = function()
      if M.state.enabled then
        M._on_mode_changed()
      end
    end,
  })
  
  -- Learn from accepted completions
  vim.api.nvim_create_autocmd("CompleteDone", {
    group = M.autocmd_group,
    callback = function()
      if M.state.enabled then
        M._learn_from_completion()
      end
    end,
  })
end

-- Handle text changes
M._on_text_changed = function()
  local current_time = vim.loop.now()
  M.state.last_edit_time = current_time
  
  -- Debounce to avoid too many requests
  local debounce_ms = require('caramba.config').get().pair.debounce_ms or 500
  vim.defer_fn(function()
    if vim.loop.now() - M.state.last_edit_time >= debounce_ms then
      M._analyze_current_context()
    end
  end, debounce_ms)
end

-- Handle cursor movement
M._on_cursor_moved = function()
  -- Update inline suggestions based on cursor position
  if M.state.mode == "focused" then
    M._update_inline_suggestions()
  end
end

-- Handle mode changes
M._on_mode_changed = function()
  local mode = vim.fn.mode()
  
  if mode == "i" then
    -- Entering insert mode - prepare suggestions
    M._prepare_suggestions()
  elseif mode == "n" then
    -- Leaving insert mode - learn from edits
    M._learn_from_edits()
  end
end

-- Analyze current context and generate suggestions
M._analyze_current_context = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  
  -- Get comprehensive context
  local ctx = context.get_context(bufnr, cursor[1])
  M.state.current_context = ctx
  
  -- Analyze what the user is trying to do
  local intent = M._infer_intent(ctx)
  
  -- Generate appropriate suggestions
  if intent then
    M._generate_suggestions(intent, ctx)
  end
end

-- Infer user's intent from context
M._infer_intent = function(ctx)
  local current_line = vim.api.nvim_get_current_line()
  local cursor_col = vim.fn.col('.')
  
  -- Pattern matching for common scenarios
  local patterns = {
    -- Starting a function
    { pattern = "^%s*function%s+$", intent = "function_definition" },
    { pattern = "^%s*def%s+$", intent = "function_definition" },
    { pattern = "^%s*const%s+%w+%s*=%s*%(", intent = "arrow_function" },
    
    -- Writing a comment
    { pattern = "^%s*//", intent = "comment" },
    { pattern = "^%s*#", intent = "comment" },
    { pattern = "^%s*/%*", intent = "block_comment" },
    
    -- Import/require statements
    { pattern = "^%s*import%s+", intent = "import" },
    { pattern = "^%s*from%s+", intent = "import" },
    { pattern = "^%s*require%(", intent = "require" },
    
    -- Control flow
    { pattern = "^%s*if%s*%(", intent = "condition" },
    { pattern = "^%s*for%s*%(", intent = "loop" },
    { pattern = "^%s*while%s*%(", intent = "loop" },
    
    -- Error handling
    { pattern = "^%s*try%s*{", intent = "try_catch" },
    { pattern = "^%s*catch%s*%(", intent = "catch_block" },
    
    -- Testing
    { pattern = "^%s*it%(", intent = "test_case" },
    { pattern = "^%s*describe%(", intent = "test_suite" },
    { pattern = "^%s*test%(", intent = "test_case" },
  }
  
  for _, p in ipairs(patterns) do
    if current_line:match(p.pattern) then
      return {
        type = p.intent,
        line = current_line,
        context = ctx,
      }
    end
  end
  
  -- Check for incomplete code
  if current_line:match("%.%s*$") then
    return { type = "method_completion", context = ctx }
  end
  
  -- Check if we're in a function body
  if ctx.current_function then
    -- Look for patterns in function
    if current_line:match("^%s*return%s*$") then
      return { type = "return_statement", context = ctx }
    end
  end
  
  return nil
end

-- Generate suggestions based on intent
M._generate_suggestions = function(intent, ctx)
  local suggestions = {}
  
  if intent.type == "function_definition" then
    -- Suggest function names based on context
    suggestions = M._suggest_function_names(ctx)
  elseif intent.type == "import" then
    -- Suggest imports based on usage
    suggestions = M._suggest_imports(ctx)
  elseif intent.type == "method_completion" then
    -- Suggest methods based on object type
    suggestions = M._suggest_methods(ctx)
  elseif intent.type == "test_case" then
    -- Suggest test cases based on function
    suggestions = M._suggest_test_cases(ctx)
  end
  
  M.state.suggestions = suggestions
  
  -- Show suggestions
  if #suggestions > 0 then
    M._show_suggestions(suggestions)
  end
end

-- Suggest function names based on context
M._suggest_function_names = function(ctx)
  local suggestions = {}
  
  -- Look at recent edits and file context
  local prompt = string.format([[
Based on this code context, suggest 3 appropriate function names:

File: %s
Current class/module: %s
Recent code:
%s

Suggest function names that follow the project's naming conventions.
Return only the function names, one per line.
]], ctx.filename or "unknown", ctx.current_class or "global", ctx.before)
  
  llm.request(prompt, { temperature = 1 }, function(response)
    if response then
      local names = vim.split(response, '\n')
      for _, name in ipairs(names) do
        if name ~= "" then
          table.insert(suggestions, {
            text = name,
            type = "function_name",
            confidence = 0.8,
          })
        end
      end
      M._update_suggestions_display(suggestions)
    end
  end)
  
  return suggestions
end

-- Suggest imports based on undefined symbols
M._suggest_imports = function(ctx)
  local suggestions = {}
  
  -- Find undefined symbols in current buffer
  local undefined = M._find_undefined_symbols()
  
  -- Look up in project intelligence
  for _, symbol in ipairs(undefined) do
    local locations = intelligence.db.symbols[symbol]
    if locations then
      for _, loc in ipairs(locations) do
        -- Generate import statement
        local import_stmt = M._generate_import(symbol, loc.file, ctx.filename)
        if import_stmt then
          table.insert(suggestions, {
            text = import_stmt,
            type = "import",
            symbol = symbol,
            source = loc.file,
          })
        end
      end
    end
  end
  
  return suggestions
end

-- Real-time code review
M.review_as_you_type = function()
  if not M.state.enabled then return end
  
  local bufnr = vim.api.nvim_get_current_buf()
  local diagnostics = {}
  
  -- Get current function or block
  local ctx = context.get_context(bufnr)
  if not ctx.current_function then return end
  
  -- Quick checks
  local issues = {}
  
  -- Check for common issues
  local function_text = ctx.current_function_text
  
  -- Long function
  local line_count = #vim.split(function_text, '\n')
  if line_count > 50 then
    table.insert(issues, {
      line = ctx.current_function_start,
      message = "Function is getting long. Consider breaking it up.",
      severity = vim.diagnostic.severity.HINT,
    })
  end
  
  -- Deep nesting
  local max_indent = 0
  for line in function_text:gmatch("[^\n]+") do
    local indent = #line:match("^%s*")
    max_indent = math.max(max_indent, indent)
  end
  
  if max_indent > 16 then -- 4 levels of nesting
    table.insert(issues, {
      message = "Deep nesting detected. Consider extracting logic.",
      severity = vim.diagnostic.severity.HINT,
    })
  end
  
  -- Show issues as virtual text
  for _, issue in ipairs(issues) do
    M._show_inline_hint(issue.message, issue.line)
  end
end

-- Learn from user's edits
M._learn_from_edits = function()
  -- Track edit patterns
  local current_line = vim.api.nvim_get_current_line()
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Record edit in history
  table.insert(M.state.edit_history, {
    line = current_line,
    timestamp = vim.loop.now(),
    buffer = bufnr,
    filetype = vim.bo[bufnr].filetype,
  })
  
  -- Keep history size manageable
  if #M.state.edit_history > 1000 then
    table.remove(M.state.edit_history, 1)
  end
  
  -- Extract patterns
  M._extract_patterns()
end

-- Extract coding patterns from history
M._extract_patterns = function()
  -- Analyze naming conventions
  local function_names = {}
  local variable_names = {}
  
  for _, edit in ipairs(M.state.edit_history) do
    -- Extract function names
    local func_name = edit.line:match("function%s+([%w_]+)")
    if func_name then
      table.insert(function_names, func_name)
    end
    
    -- Extract variable names
    local var_name = edit.line:match("(%w+)%s*=")
    if var_name then
      table.insert(variable_names, var_name)
    end
  end
  
  -- Detect naming patterns
  M.pattern_db.naming_conventions = M._analyze_naming_patterns(function_names, variable_names)
end

-- Voice coding support (requires external tool)
M.voice_command = function(command)
  -- Parse voice command
  local action, target = M._parse_voice_command(command)
  
  if action == "create" then
    if target == "function" then
      M._create_function_from_voice()
    elseif target == "class" then
      M._create_class_from_voice()
    end
  elseif action == "refactor" then
    M._refactor_from_voice(target)
  elseif action == "navigate" then
    M._navigate_from_voice(target)
  end
end

-- Show inline hints
M._show_inline_hint = function(text, line)
  line = line or vim.fn.line('.')
  
  -- Create virtual text
  local ns_id = vim.api.nvim_create_namespace('ai_pair_hints')
  
  vim.api.nvim_buf_set_extmark(0, ns_id, line - 1, 0, {
    virt_text = {{" 💡 " .. text, "Comment"}},
    virt_text_pos = "eol",
    priority = 100,
  })
  
  -- Auto-clear after delay
  vim.defer_fn(function()
    vim.api.nvim_buf_clear_namespace(0, ns_id, line - 1, line)
  end, 5000)
end

-- Show suggestion window
M._show_suggestions = function(suggestions)
  -- Create floating window for suggestions
  local width = 50
  local height = math.min(#suggestions + 2, 10)
  
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Format suggestions
  local lines = {"💡 AI Suggestions:"}
  for i, suggestion in ipairs(suggestions) do
    table.insert(lines, string.format("%d. %s", i, suggestion.text))
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Calculate position (near cursor)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local win_height = vim.api.nvim_win_get_height(0)
  local row = cursor[1] + 1
  
  if row + height > win_height then
    row = cursor[1] - height - 1
  end
  
  local opts = {
    relative = 'win',
    row = row,
    col = cursor[2],
    width = width,
    height = height,
    style = 'minimal',
    border = require('caramba.config').get().ui.floating_window_border or 'rounded',
  }
  
  M.state.suggestion_window = vim.api.nvim_open_win(buf, false, opts)
  
  -- Add keymaps for accepting suggestions
  for i = 1, math.min(#suggestions, 9) do
    vim.keymap.set('n', tostring(i), function()
      M._accept_suggestion(suggestions[i])
    end, { buffer = buf })
  end
  
  -- Auto-close after delay
  local auto_close = require('caramba.config').get().pair.suggestion_auto_close_ms or 10000
  vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(M.state.suggestion_window) then
      vim.api.nvim_win_close(M.state.suggestion_window, true)
    end
  end, auto_close)
end

-- Accept a suggestion
M._accept_suggestion = function(suggestion)
  -- Close suggestion window
  if M.state.suggestion_window and vim.api.nvim_win_is_valid(M.state.suggestion_window) then
    vim.api.nvim_win_close(M.state.suggestion_window, true)
  end
  
  -- Apply suggestion
  if suggestion.type == "function_name" then
    vim.api.nvim_put({suggestion.text}, 'c', true, true)
  elseif suggestion.type == "import" then
    -- Add import at top of file
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local insert_line = M._find_import_position(lines)
    vim.api.nvim_buf_set_lines(0, insert_line, insert_line, false, {suggestion.text})
  end
  
  -- Learn from acceptance
  M._learn_from_acceptance(suggestion)
end

-- Learn from accepted suggestions
M._learn_from_acceptance = function(suggestion)
  -- Record what was accepted
  if not M.pattern_db.accepted_suggestions then
    M.pattern_db.accepted_suggestions = {}
  end
  
  table.insert(M.pattern_db.accepted_suggestions, {
    type = suggestion.type,
    text = suggestion.text,
    context = M.state.current_context,
    timestamp = vim.loop.now(),
  })
  
  -- Save patterns
  M._save_patterns()
end

-- Save learned patterns
M._save_patterns = function()
  local path = vim.fn.stdpath('data') .. '/ai_pair_patterns.json'
  local json = vim.json.encode(M.pattern_db)
  vim.fn.writefile({json}, path)
end

-- Load learned patterns
M._load_patterns = function()
  local path = vim.fn.stdpath('data') .. '/ai_pair_patterns.json'
  if vim.fn.filereadable(path) == 1 then
    local lines = vim.fn.readfile(path)
    if #lines > 0 then
      local ok, data = pcall(vim.json.decode, lines[1])
      if ok then
        M.pattern_db = data
      end
    end
  end
end

-- Clear all suggestions
M._clear_suggestions = function()
  if M.state.suggestion_window and vim.api.nvim_win_is_valid(M.state.suggestion_window) then
    vim.api.nvim_win_close(M.state.suggestion_window, true)
  end
  
  -- Clear virtual text
  local ns_id = vim.api.nvim_create_namespace('ai_pair_hints')
  vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
end

-- Set pair programming mode
M.set_mode = function(mode)
  if mode == "normal" or mode == "focused" or mode == "learning" then
    M.state.mode = mode
    vim.notify("AI Pair mode: " .. mode, vim.log.levels.INFO)
  end
end

-- Start monitoring (placeholder for future enhancements)
M._start_monitoring = function()
  -- Future: Could add performance monitoring, error tracking, etc.
end

-- Prepare suggestions when entering insert mode
M._prepare_suggestions = function()
  -- Analyze context for potential suggestions
  M._analyze_current_context()
end

-- Update inline suggestions
M._update_inline_suggestions = function()
  -- Future: Show ghost text or inline completions
end

-- Learn from completion
M._learn_from_completion = function()
  local completed = vim.v.completed_item
  if completed and completed.word then
    -- Track what completions are accepted
    if not M.pattern_db.accepted_completions then
      M.pattern_db.accepted_completions = {}
    end
    table.insert(M.pattern_db.accepted_completions, {
      word = completed.word,
      kind = completed.kind,
      timestamp = vim.loop.now(),
    })
  end
end

-- Find undefined symbols in buffer
M._find_undefined_symbols = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  local lang = require("nvim-treesitter.language").get_lang(ft)

  if not lang then
    return {}
  end

  -- Language-specific queries
  local queries = {
    javascript = {
      declarations = [[
        (variable_declarator name: (identifier) @variable.name)
        (function_declaration name: (identifier) @function.name)
        (class_declaration name: (identifier) @class.name)
        (import_specifier name: (identifier) @import.name)
        (namespace_import (identifier) @import.name)
        (formal_parameters (identifier) @param.name)
      ]],
      usage = "(identifier) @usage",
    },
    typescript = {
      declarations = [[
        (variable_declarator name: (identifier) @variable.name)
        (function_declaration name: (identifier) @function.name)
        (class_declaration name: (identifier) @class.name)
        (import_specifier name: (identifier) @import.name)
        (namespace_import (identifier) @import.name)
        (formal_parameters (identifier) @param.name)
      ]],
      usage = "(identifier) @usage",
    },
    lua = {
      declarations = [[
        (variable_declaration name: (identifier) @variable.name)
        (function_declaration name: (identifier) @function.name)
        (parameter (identifier) @param.name)
      ]],
      usage = "(identifier) @usage",
    },
    python = {
      declarations = [[
        (assignment left: (identifier) @variable.name)
        (function_definition name: (identifier) @function.name)
        (class_definition name: (identifier) @class.name)
        (aliased_import (dotted_name (identifier) @import.name))
        (parameters (identifier) @param.name)
      ]],
      usage = "(identifier) @usage",
    },
    -- Add more languages as needed
  }

  local lang_queries = queries[ft]
  if not lang_queries then
    -- Silently fail if language is not supported for this feature
    return {}
  end

  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local parser = vim.treesitter.get_string_parser(content, lang)
  local tree = parser:parse()[1]
  if not tree then
    return {}
  end

  local root = tree:root()
  local declared_symbols = {}
  local used_symbols = {}

  -- Query for all declarations
  local declaration_query = vim.treesitter.query.parse(lang, lang_queries.declarations)
  if declaration_query then
    for _, node in declaration_query:iter_captures(root, content) do
      declared_symbols[utils.get_node_text(node, content)] = true
    end
  end

  -- Query for all identifiers being used
  local usage_query = vim.treesitter.query.parse(lang, lang_queries.usage)
  if usage_query then
    for _, match in usage_query:iter_matches(root, content) do
      local node = match[1] -- The first capture in a simple query is the node itself
      if node then
        -- Check parent to avoid capturing property names etc.
        local parent = node:parent()
        if parent then
          local parent_type = parent:type()
          if parent_type ~= 'property_identifier' and parent_type ~= 'field_identifier' then
            used_symbols[utils.get_node_text(node, content)] = true
          end
        end
      end
    end
  end

  -- Find symbols that are used but not declared
  local undefined = {}
  for symbol, _ in pairs(used_symbols) do
    if not declared_symbols[symbol] then
      table.insert(undefined, symbol)
    end
  end

  return undefined
end

-- Generate import statement
M._generate_import = function(symbol, source_file, target_file)
  local ext = vim.fn.fnamemodify(target_file, ':e')
  
  -- Calculate relative path
  local source_dir = vim.fn.fnamemodify(source_file, ':h')
  local target_dir = vim.fn.fnamemodify(target_file, ':h')
  local relative_path = M._calculate_relative_path(target_dir, source_file)
  
  -- Generate based on file type
  if ext == "js" or ext == "ts" or ext == "jsx" or ext == "tsx" then
    -- ES6 import
    return string.format("import { %s } from '%s';", symbol, relative_path)
  elseif ext == "py" then
    -- Python import
    local module = vim.fn.fnamemodify(source_file, ':t:r')
    return string.format("from %s import %s", module, symbol)
  elseif ext == "lua" then
    -- Lua require
    local module = vim.fn.fnamemodify(source_file, ':t:r')
    return string.format("local %s = require('%s')", symbol, module)
  end
  
  return nil
end

-- Calculate relative path between files
M._calculate_relative_path = function(from_dir, to_file)
  -- Simple implementation - in production would be more robust
  local to_dir = vim.fn.fnamemodify(to_file, ':h')
  local to_name = vim.fn.fnamemodify(to_file, ':t:r')
  
  if from_dir == to_dir then
    return "./" .. to_name
  else
    -- For now, just use the module name
    return to_name
  end
end

-- Suggest methods based on object type
M._suggest_methods = function(ctx)
  -- This would integrate with type information
  -- For now, return empty
  return {}
end

-- Suggest test cases
M._suggest_test_cases = function(ctx)
  -- This would analyze the function being tested
  -- For now, return empty
  return {}
end

-- Update suggestions display
M._update_suggestions_display = function(suggestions)
  M.state.suggestions = suggestions
  if #suggestions > 0 then
    M._show_suggestions(suggestions)
  end
end

-- Find import position in file
M._find_import_position = function(lines)
  -- Find where to insert import
  local last_import = 0
  
  for i, line in ipairs(lines) do
    if line:match("^import") or line:match("^from.*import") or line:match("^const.*require") then
      last_import = i
    elseif last_import > 0 and line ~= "" then
      -- Found first non-import line after imports
      break
    end
  end
  
  if last_import > 0 then
    return last_import + 1
  else
    -- No imports found, add at top
    return 0
  end
end

-- Analyze naming patterns
M._analyze_naming_patterns = function(function_names, variable_names)
  local patterns = {
    functions = {},
    variables = {},
  }
  
  -- Detect function naming patterns
  local camelCase = 0
  local snake_case = 0
  
  for _, name in ipairs(function_names) do
    if name:match("^[a-z]") and name:match("[A-Z]") then
      camelCase = camelCase + 1
    elseif name:match("_") then
      snake_case = snake_case + 1
    end
  end
  
  patterns.functions.style = camelCase > snake_case and "camelCase" or "snake_case"
  
  -- Similar for variables
  camelCase = 0
  snake_case = 0
  
  for _, name in ipairs(variable_names) do
    if name:match("^[a-z]") and name:match("[A-Z]") then
      camelCase = camelCase + 1
    elseif name:match("_") then
      snake_case = snake_case + 1
    end
  end
  
  patterns.variables.style = camelCase > snake_case and "camelCase" or "snake_case"
  
  return patterns
end

-- Parse voice command
M._parse_voice_command = function(command)
  -- Simple keyword matching
  local action = nil
  local target = nil
  
  if command:match("create") then
    action = "create"
  elseif command:match("refactor") then
    action = "refactor"
  elseif command:match("go to") or command:match("navigate") then
    action = "navigate"
  end
  
  if command:match("function") then
    target = "function"
  elseif command:match("class") then
    target = "class"
  elseif command:match("variable") then
    target = "variable"
  end
  
  return action, target
end

-- Create function from voice
M._create_function_from_voice = function()
  -- Would integrate with voice recognition
  vim.notify("Voice function creation not yet implemented", vim.log.levels.INFO)
end

-- Create class from voice
M._create_class_from_voice = function()
  -- Would integrate with voice recognition
  vim.notify("Voice class creation not yet implemented", vim.log.levels.INFO)
end

-- Refactor from voice
M._refactor_from_voice = function(target)
  -- Would integrate with voice recognition
  vim.notify("Voice refactoring not yet implemented", vim.log.levels.INFO)
end

-- Voice navigation
M._navigate_from_voice = function(target)
  -- Would integrate with voice recognition
  vim.notify("Voice navigation not yet implemented", vim.log.levels.INFO)
end

-- Start pair programming session
M.start_session = function()
  M.state.active = true
  M.state.session_start = os.time()
  M.enable()
  vim.notify("AI Pair Programming session started", vim.log.levels.INFO)
end

-- End pair programming session  
M.end_session = function()
  if M.state.active then
    local duration = os.time() - M.state.session_start
    local minutes = math.floor(duration / 60)
    vim.notify(string.format("AI Pair Programming session ended. Duration: %d minutes", minutes), vim.log.levels.INFO)
  end
  M.state.active = false
  M.disable()
end

-- Show pair programming statistics
M.show_stats = function()
  local stats = {
    suggestions_shown = M.state.suggestions_shown,
    suggestions_accepted = M.state.suggestions_accepted,
    patterns_learned = vim.tbl_count(M.state.learned_patterns),
  }
  
  local lines = {
    "# AI Pair Programming Statistics",
    "",
    string.format("Suggestions shown: %d", stats.suggestions_shown),
    string.format("Suggestions accepted: %d", stats.suggestions_accepted),
    string.format("Acceptance rate: %.1f%%", 
      stats.suggestions_shown > 0 and (stats.suggestions_accepted / stats.suggestions_shown * 100) or 0),
    string.format("Patterns learned: %d", stats.patterns_learned),
    "",
    "## Learned Patterns",
    "",
  }
  
  -- Show some learned patterns
  local pattern_count = 0
  for pattern_type, patterns in pairs(M.state.learned_patterns) do
    if pattern_count < 10 then
      table.insert(lines, "### " .. pattern_type)
      for pattern, count in pairs(patterns) do
        if pattern_count < 10 then
          table.insert(lines, string.format("- %s (used %d times)", pattern, count))
          pattern_count = pattern_count + 1
        end
      end
      table.insert(lines, "")
    end
  end
  
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  vim.cmd('split')
  vim.api.nvim_set_current_buf(buf)
end

-- Setup commands for this module
M.setup_commands = function()
  local commands = require('caramba.core.commands')
  
  -- Start pair programming session
  commands.register('PairStart', M.start_session, {
    desc = 'Start AI pair programming session',
  })
  
  -- End pair programming session
  commands.register('PairEnd', M.end_session, {
    desc = 'End AI pair programming session',
  })
  
  -- Toggle pair mode
  commands.register('PairToggle', M.toggle, {
    desc = 'Toggle AI pair programming mode',
  })
  
  -- Show pair stats
  commands.register('PairStats', M.show_stats, {
    desc = 'Show pair programming statistics',
  })
  
  -- Enable pair mode
  commands.register('PairEnable', M.enable, {
    desc = 'Enable AI pair programming mode',
  })
  
  -- Disable pair mode
  commands.register('PairDisable', M.disable, {
    desc = 'Disable AI pair programming mode',
  })
  
  -- Set pair mode
  commands.register('PairMode', function(args)
    local mode = args.args
    if mode == "" then
      vim.ui.select({"proactive", "reactive", "silent"}, {
        prompt = "Select pair programming mode:",
      }, function(choice)
        if choice then
          M.set_mode(choice)
        end
      end)
    else
      M.set_mode(mode)
    end
  end, {
    desc = 'Set pair programming mode',
    nargs = '?',
    complete = function()
      return {"proactive", "reactive", "silent"}
    end,
  })
  
  -- Voice command
  commands.register('PairVoice', function(args)
    M.voice_command(args.args)
  end, {
    desc = 'Execute voice command',
    nargs = '+',
  })
end

return M 