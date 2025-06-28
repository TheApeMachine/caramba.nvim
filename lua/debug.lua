-- AI Debugging Assistant Module
-- Helps analyze errors, stack traces, and debug issues

local M = {}

local config = require('ai.config')
local context = require('ai.context')
local llm = require('ai.llm')
local multifile = require('ai.multifile')

-- Parse stack trace to extract file locations
local function parse_stack_trace(trace)
  local locations = {}
  
  -- Common stack trace patterns
  local patterns = {
    -- Python: File "path/to/file.py", line 42, in function_name
    python = 'File "([^"]+)", line (%d+)',
    -- JavaScript/Node: at functionName (path/to/file.js:42:15)
    javascript = 'at .* %(([^:]+):(%d+):(%d+)%)',
    -- Lua: path/to/file.lua:42: in function 'name'
    lua = '([^:]+%.lua):(%d+):',
    -- Go: path/to/file.go:42 +0x123
    go = '([^:]+%.go):(%d+)',
    -- Rust: at path/to/file.rs:42:15
    rust = 'at ([^:]+%.rs):(%d+):(%d+)',
    -- Java: at com.example.Class.method(File.java:42)
    java = 'at .+%(([^:]+%.java):(%d+)%)',
    -- Generic: anything with file:line pattern
    generic = '([^:]+%.[a-zA-Z]+):(%d+)',
  }
  
  -- Try each pattern
  for lang, pattern in pairs(patterns) do
    for file, line, col in trace:gmatch(pattern) do
      -- Normalize path
      file = vim.fn.resolve(file)
      
      -- Check if file exists
      if vim.fn.filereadable(file) == 1 then
        table.insert(locations, {
          file = file,
          line = tonumber(line),
          column = tonumber(col),
          language = lang,
        })
      end
    end
  end
  
  -- Remove duplicates
  local seen = {}
  local unique = {}
  for _, loc in ipairs(locations) do
    local key = loc.file .. ":" .. loc.line
    if not seen[key] then
      seen[key] = true
      table.insert(unique, loc)
    end
  end
  
  return unique
end

-- Extract code context around error locations
local function get_error_context(locations)
  local contexts = {}
  
  for _, loc in ipairs(locations) do
    local lines = vim.fn.readfile(loc.file)
    if lines then
      -- Get surrounding context (10 lines before/after)
      local start_line = math.max(1, loc.line - 10)
      local end_line = math.min(#lines, loc.line + 10)
      
      local context_lines = {}
      for i = start_line, end_line do
        local prefix = i == loc.line and ">>> " or "    "
        table.insert(context_lines, string.format("%s%4d: %s", prefix, i, lines[i]))
      end
      
      table.insert(contexts, {
        file = loc.file,
        line = loc.line,
        code = table.concat(context_lines, "\n"),
        language = loc.language,
      })
    end
  end
  
  return contexts
end

-- Analyze an error with stack trace
M.analyze_error = function(opts)
  opts = opts or {}
  
  local error_text = opts.error
  if not error_text then
    -- Try to get from clipboard
    error_text = vim.fn.getreg("+")
    if not error_text or error_text == "" then
      -- Try to get from current buffer
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      error_text = table.concat(lines, "\n")
    end
  end
  
  if not error_text or error_text == "" then
    vim.notify("No error text provided", vim.log.levels.ERROR)
    return
  end
  
  -- Parse stack trace
  local locations = parse_stack_trace(error_text)
  local contexts = get_error_context(locations)
  
  -- Build comprehensive prompt
  local prompt = [[
Analyze this error and help me debug it:

Error/Stack Trace:
```
]] .. error_text .. [[
```
]]

  -- Add code contexts
  if #contexts > 0 then
    prompt = prompt .. "\n\nRelevant code sections:\n"
    for _, ctx in ipairs(contexts) do
      prompt = prompt .. string.format("\nFile: %s (line %d)\n```%s\n%s\n```\n",
        ctx.file, ctx.line, ctx.language or "text", ctx.code)
    end
  end
  
  -- Add current file context if available
  local current_ctx = context.collect()
  if current_ctx then
    prompt = prompt .. "\n\nCurrent file context:\n```" .. current_ctx.language .. "\n" ..
      (current_ctx.node_text or current_ctx.current_line) .. "\n```\n"
  end
  
  prompt = prompt .. [[

Please provide:
1. **Root Cause Analysis**: What is causing this error?
2. **Explanation**: Why is this happening in simple terms?
3. **Fix**: Specific code changes to resolve the issue
4. **Prevention**: How to avoid similar errors in the future
5. **Debugging Steps**: Additional steps to investigate if needed

Be specific and provide actual code that can be applied.
]]

  llm.request(prompt, { temperature = 0.3 }, function(response)
    if not response then
      vim.notify("Failed to analyze error", vim.log.levels.ERROR)
      return
    end
    
    vim.schedule(function()
      -- Create a debug report buffer
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
      vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
      vim.api.nvim_buf_set_name(buf, "Debug Analysis")
      
      -- Add the analysis
      local lines = vim.split(response, "\n")
      
      -- Add quick navigation links at the top
      table.insert(lines, 1, "# Debug Analysis Report")
      table.insert(lines, 2, "")
      table.insert(lines, 3, "## Quick Navigation")
      table.insert(lines, 4, "")
      
      local nav_idx = 5
      for i, loc in ipairs(locations) do
        local link = string.format("%d. [%s:%d](%s)", i, 
          vim.fn.fnamemodify(loc.file, ":t"), loc.line, loc.file)
        table.insert(lines, nav_idx, link)
        nav_idx = nav_idx + 1
      end
      
      table.insert(lines, nav_idx, "")
      table.insert(lines, nav_idx + 1, "---")
      table.insert(lines, nav_idx + 2, "")
      
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      
      -- Open in a split
      vim.cmd('split')
      vim.api.nvim_set_current_buf(buf)
      
      -- Set up keymaps for navigation
      local function goto_location(idx)
        if locations[idx] then
          local loc = locations[idx]
          vim.cmd('edit ' .. loc.file)
          vim.api.nvim_win_set_cursor(0, {loc.line, 0})
        end
      end
      
      for i = 1, math.min(9, #locations) do
        vim.keymap.set('n', tostring(i), function() goto_location(i) end, 
          { buffer = buf, desc = "Go to location " .. i })
      end
      
      -- Extract and offer to apply suggested fixes
      M._extract_and_apply_fixes(response, locations)
    end)
  end)
end

-- Extract code fixes from the analysis
M._extract_and_apply_fixes = function(response, locations)
  -- Look for code blocks that might be fixes
  local fixes = {}
  local current_fix = nil
  local in_code_block = false
  
  for line in response:gmatch("[^\n]+") do
    if line:match("^```") then
      if in_code_block and current_fix then
        -- End of code block
        table.insert(fixes, current_fix)
        current_fix = nil
      else
        -- Start of code block
        local lang = line:match("^```(%w+)")
        current_fix = {
          language = lang,
          code = {},
        }
      end
      in_code_block = not in_code_block
    elseif in_code_block and current_fix then
      table.insert(current_fix.code, line)
    elseif line:match("^File:") or line:match("^In%s+.+:") then
      -- Try to extract file reference
      local file = line:match("^File:%s*(.+)")
      if file and current_fix then
        current_fix.file = file
      end
    end
  end
  
  if #fixes > 0 then
    vim.notify(string.format("Found %d potential fixes. Use :AIApplyFix to review and apply.", #fixes))
    M._pending_fixes = fixes
  end
end

-- Apply pending fixes
M.apply_fixes = function()
  if not M._pending_fixes or #M._pending_fixes == 0 then
    vim.notify("No pending fixes", vim.log.levels.INFO)
    return
  end
  
  -- Start transaction
  multifile.begin_transaction()
  
  for i, fix in ipairs(M._pending_fixes) do
    if fix.file and fix.code then
      local code = table.concat(fix.code, "\n")
      
      multifile.add_operation({
        type = multifile.OpType.MODIFY,
        path = fix.file,
        content = code,
        description = "Apply debug fix " .. i,
      })
    end
  end
  
  -- Preview changes
  multifile.preview_transaction()
  
  -- Clear pending fixes after applying
  M._pending_fixes = nil
end

-- Interactive debugging session
M.start_debug_session = function(opts)
  opts = opts or {}
  
  -- Create a debug REPL buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_name(buf, "AI Debug Session")
  
  -- Initialize session state
  local session = {
    history = {},
    breakpoints = {},
    watches = {},
    current_frame = nil,
  }
  
  -- Add initial content
  local lines = {
    "# AI Debug Session",
    "",
    "Commands:",
    "  :break <line>     - Set breakpoint",
    "  :watch <expr>     - Watch expression",
    "  :eval <expr>      - Evaluate expression",
    "  :vars             - Show local variables",
    "  :stack            - Show call stack",
    "  :continue         - Continue execution",
    "",
    "Type your debugging question below:",
    "",
  }
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Open in a split
  vim.cmd('split')
  vim.api.nvim_set_current_buf(buf)
  
  -- Set up debug commands
  local function debug_command(cmd, args)
    local prompt = string.format([[
I'm debugging code and need help with: %s %s

Current debugging context:
- File: %s
- Line: %d
- Language: %s

Please provide specific debugging guidance.
]], cmd, args, vim.fn.expand("%:p"), vim.fn.line("."), vim.bo.filetype)
    
    llm.request(prompt, { temperature = 0.3 }, function(response)
      if response then
        vim.schedule(function()
          -- Append response to debug buffer
          local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          table.insert(current_lines, "")
          table.insert(current_lines, "AI: " .. cmd .. " " .. args)
          table.insert(current_lines, "")
          
          for line in response:gmatch("[^\n]+") do
            table.insert(current_lines, line)
          end
          
          table.insert(current_lines, "")
          table.insert(current_lines, "---")
          table.insert(current_lines, "")
          
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, current_lines)
        end)
      end
    end)
  end
  
  -- Create buffer-local commands
  vim.api.nvim_buf_create_user_command(buf, 'break', function(opts)
    debug_command('break', opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_buf_create_user_command(buf, 'watch', function(opts)
    debug_command('watch', opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_buf_create_user_command(buf, 'eval', function(opts)
    debug_command('eval', opts.args)
  end, { nargs = 1 })
  
  M._debug_session = session
end

-- Analyze performance issues
M.analyze_performance = function(opts)
  opts = opts or {}
  
  local profile_data = opts.profile
  if not profile_data then
    vim.notify("No profiling data provided", vim.log.levels.ERROR)
    return
  end
  
  local prompt = [[
Analyze this performance profile and suggest optimizations:

Profile Data:
```
]] .. profile_data .. [[
```

Please provide:
1. **Bottlenecks**: Identify the main performance issues
2. **Root Causes**: Why these bottlenecks exist
3. **Optimizations**: Specific code changes to improve performance
4. **Trade-offs**: Any downsides to the suggested optimizations
5. **Measurements**: How to verify the improvements

Focus on practical, implementable solutions.
]]

  llm.request(prompt, { temperature = 0.3 }, function(response)
    if response then
      vim.schedule(function()
        -- Show analysis
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
        vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
        
        vim.cmd('split')
        vim.api.nvim_set_current_buf(buf)
      end)
    end
  end)
end

return M 