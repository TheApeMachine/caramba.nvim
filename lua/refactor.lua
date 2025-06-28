-- Refactoring Module
-- Tree-sitter powered code transformations

local M = {}
local context = require("ai.context")
local llm = require("ai.llm")
local edit = require("ai.edit")
local ts_utils = require("nvim-treesitter.ts_utils")
local config = require("ai.config")

-- Common refactoring operations
M.operations = {
  extract_function = "Extract the selected code into a new function",
  extract_variable = "Extract the selected expression into a variable",
  inline_variable = "Inline the variable at cursor",
  rename_symbol = "Rename the symbol under cursor",
  simplify_conditional = "Simplify conditional logic (early returns, guard clauses)",
  add_type_annotations = "Add type annotations to function parameters and return values",
  convert_to_async = "Convert function to async/await pattern",
  extract_interface = "Extract interface from class/struct",
  organize_imports = "Organize and optimize imports",
}

-- Rename symbol with AI assistance
function M.rename_symbol(new_name, opts)
  opts = opts or {}
  
  -- Get current symbol
  local node = ts_utils.get_node_at_cursor()
  if not node then
    vim.notify("No symbol at cursor", vim.log.levels.WARN)
    return
  end
  
  -- Find identifier node
  while node and node:type() ~= "identifier" do
    node = node:parent()
  end
  
  if not node then
    vim.notify("No identifier found at cursor", vim.log.levels.WARN)
    return
  end
  
  local old_name = context.get_node_text(node)
  
  -- Get buffer content
  local bufnr = 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  
  -- Build prompt
  local prompt = llm.build_refactor_prompt(
    content,
    string.format("Rename all occurrences of '%s' to '%s'. Ensure all references are updated.", 
      old_name, new_name)
  )
  
  -- Request refactoring
  llm.request(prompt, opts, function(result, err)
    if err then
      vim.schedule(function()
        vim.notify("Refactoring failed: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    -- Apply with preview
    vim.schedule(function()
      if config.get().editing.diff_preview then
        edit.show_diff_preview(bufnr, 0, #lines - 1, result, function()
          edit.apply_patch(bufnr, result)
          vim.notify(string.format("Renamed '%s' to '%s'", old_name, new_name))
        end)
      else
        local success, error_msg = edit.apply_patch(bufnr, result)
        if success then
          vim.notify(string.format("Renamed '%s' to '%s'", old_name, new_name))
        else
          vim.notify("Failed to apply refactoring: " .. error_msg, vim.log.levels.ERROR)
        end
      end
    end)
  end)
end

-- Extract function from selection
function M.extract_function(opts)
  opts = opts or {}
  
  -- Get visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  
  -- Get selected text
  local bufnr = 0
  local selected_lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
  local selected_text = table.concat(selected_lines, "\n")
  
  -- Get full context
  local ctx = context.collect({ bufnr = bufnr })
  if not ctx then
    vim.notify("Failed to extract context", vim.log.levels.ERROR)
    return
  end
  
  -- Build prompt
  local prompt = llm.build_refactor_prompt(
    context.build_context_string(ctx),
    string.format([[Extract the following code into a new function:

```
%s
```

Create a well-named function with appropriate parameters and return values. 
Replace the selected code with a call to the new function.
Place the new function in an appropriate location.]], selected_text)
  )
  
  -- Request refactoring
  llm.request(prompt, opts, function(result, err)
    if err then
      vim.schedule(function()
        vim.notify("Extract function failed: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    -- Apply the refactoring
    vim.schedule(function()
      local success, error_msg = edit.apply_patch(bufnr, result)
      if success then
        vim.notify("Function extracted successfully")
      else
        vim.notify("Failed to extract function: " .. error_msg, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Simplify conditional logic
function M.simplify_conditional(opts)
  opts = opts or {}
  
  -- Get current function context
  local ctx = context.collect({ bufnr = 0 })
  if not ctx then
    vim.notify("Failed to extract context", vim.log.levels.ERROR)
    return
  end
  
  -- Build prompt
  local prompt = llm.build_refactor_prompt(
    ctx.content,
    [[Simplify the conditional logic in this code:
- Use early returns where appropriate
- Convert nested if-else to guard clauses
- Reduce nesting levels
- Make the code more readable
- Preserve the exact same functionality]]
  )
  
  -- Request refactoring
  llm.request(prompt, opts, function(result, err)
    if err then
      vim.schedule(function()
        vim.notify("Simplify conditional failed: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    vim.schedule(function()
      -- Find the function boundaries
      local node = context.get_node_at_cursor()
      local func_node = context.find_parent_node(node, context.node_types.function_like)
      
      if not func_node then
        vim.notify("Could not find function boundaries", vim.log.levels.WARN)
        return
      end
      
      local start_row, _, end_row, _ = func_node:range()
      
      -- Apply the refactoring
      local success, error_msg = edit.apply_edit(0, start_row, 0, end_row, -1, result)
      if success then
        vim.notify("Conditional logic simplified")
      else
        vim.notify("Failed to simplify: " .. error_msg, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Add type annotations
function M.add_type_annotations(opts)
  opts = opts or {}
  
  local ctx = context.collect({ bufnr = 0 })
  if not ctx then
    vim.notify("Failed to extract context", vim.log.levels.ERROR)
    return
  end
  
  -- Language-specific prompts
  local lang_prompts = {
    python = "Add type hints using Python 3.9+ syntax",
    typescript = "Add TypeScript type annotations",
    javascript = "Add JSDoc type annotations",
    rust = "Add explicit type annotations where they improve clarity",
    go = "Ensure all function signatures have explicit types",
  }
  
  local instruction = lang_prompts[ctx.language] or "Add appropriate type annotations"
  
  -- Build prompt
  local prompt = llm.build_refactor_prompt(
    ctx.content,
    instruction .. ". Only add types where they are missing or would improve code clarity."
  )
  
  -- Request refactoring
  llm.request(prompt, opts, function(result, err)
    if err then
      vim.schedule(function()
        vim.notify("Add types failed: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    vim.schedule(function()
      -- Apply to current function/class
      local node = context.get_node_at_cursor()
      local target_node = context.find_parent_node(
        node, 
        vim.list_extend(context.node_types.function_like, context.node_types.class_like)
      )
      
      if not target_node then
        vim.notify("Could not find target boundaries", vim.log.levels.WARN)
        return
      end
      
      local start_row, _, end_row, _ = target_node:range()
      
      local success, error_msg = edit.apply_edit(0, start_row, 0, end_row, -1, result)
      if success then
        vim.notify("Type annotations added")
      else
        vim.notify("Failed to add types: " .. error_msg, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Organize imports
function M.organize_imports(opts)
  opts = opts or {}
  
  local bufnr = 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  
  local ctx = context.collect({ bufnr = bufnr })
  local lang = ctx and ctx.language or vim.bo.filetype
  
  -- Language-specific instructions
  local lang_instructions = {
    python = [[Group imports by: standard library, third-party, local. 
Sort alphabetically within groups. Remove unused imports.]],
    javascript = [[Group imports by: external packages, internal modules. 
Combine imports from same module. Remove unused imports.]],
    typescript = [[Group imports by: external packages, internal modules, types. 
Combine imports from same module. Remove unused imports.]],
    go = [[Group imports with standard library first, then external packages. 
Use gofmt style. Remove unused imports.]],
    rust = [[Group use statements logically. Combine related imports. 
Follow Rust style guidelines. Remove unused imports.]],
  }
  
  local instruction = lang_instructions[lang] or "Organize and optimize imports. Remove unused ones."
  
  -- Build prompt
  local prompt = llm.build_refactor_prompt(content, instruction)
  
  -- Request refactoring
  llm.request(prompt, opts, function(result, err)
    if err then
      vim.schedule(function()
        vim.notify("Organize imports failed: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    vim.schedule(function()
      local success, error_msg = edit.apply_patch(bufnr, result)
      if success then
        vim.notify("Imports organized")
      else
        vim.notify("Failed to organize imports: " .. error_msg, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Generic refactoring with custom instruction
function M.refactor_with_instruction(instruction, opts)
  opts = opts or {}
  
  -- Determine scope
  local mode = vim.fn.mode()
  local bufnr = 0
  local content, start_row, end_row
  
  if mode == "v" or mode == "V" then
    -- Visual selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    start_row = start_pos[2] - 1
    end_row = end_pos[2] - 1
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    content = table.concat(lines, "\n")
  else
    -- Current function/class
    local ctx = context.collect({ bufnr = bufnr })
    if ctx then
      content = ctx.content
      local node = context.get_node_at_cursor()
      local target = context.find_parent_node(
        node,
        vim.list_extend(context.node_types.function_like, context.node_types.class_like)
      )
      if target then
        start_row, _, end_row, _ = target:range()
      end
    end
  end
  
  if not content then
    vim.notify("No content to refactor", vim.log.levels.WARN)
    return
  end
  
  -- Build prompt
  local prompt = llm.build_refactor_prompt(content, instruction)
  
  -- Request refactoring
  llm.request(prompt, opts, function(result, err)
    if err then
      vim.schedule(function()
        vim.notify("Refactoring failed: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    vim.schedule(function()
      if start_row and end_row then
        local success, error_msg = edit.apply_edit(bufnr, start_row, 0, end_row, -1, result)
        if success then
          vim.notify("Refactoring applied")
        else
          vim.notify("Failed to apply refactoring: " .. error_msg, vim.log.levels.ERROR)
        end
      else
        -- Full buffer
        local success, error_msg = edit.apply_patch(bufnr, result)
        if success then
          vim.notify("Refactoring applied")
        else
          vim.notify("Failed to apply refactoring: " .. error_msg, vim.log.levels.ERROR)
        end
      end
    end)
  end)
end

return M 