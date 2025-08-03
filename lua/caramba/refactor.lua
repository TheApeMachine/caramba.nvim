-- Refactoring Module
-- Tree-sitter powered code transformations

local M = {}
local context = require("caramba.context")
local llm = require("caramba.llm")
local edit = require("caramba.edit")
local config = require("caramba.config")
local utils = require('caramba.utils')

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
  local context = require("caramba.context")

  -- Get current symbol
  local node = context.get_node_at_cursor()
  if not node then
    vim.notify("No symbol at cursor", vim.log.levels.WARN)
    return
  end

  -- Find identifier node
  local ident_node = node
  while ident_node and ident_node:type() ~= "identifier" do
    ident_node = ident_node:parent()
  end

  if not ident_node then
    vim.notify("No identifier found at cursor", vim.log.levels.WARN)
    return
  end

  local old_name = utils.get_node_text(ident_node)

  -- Defer to the multi-file implementation for project-wide rename
  require('caramba.multifile').rename_symbol(old_name, new_name, opts)
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
    -- No selection - offer options
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local line_count = #lines

    if line_count > 300 then
      -- Large file - offer choices
      vim.ui.select(
        {"Current function/scope", "Entire file (" .. line_count .. " lines)"},
        {
          prompt = "What would you like to refactor?",
        },
        function(choice)
          if choice and choice:match("Current function") then
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
          else
            -- Entire file
            content = table.concat(lines, "\n")
            start_row = 0
            end_row = line_count - 1
          end

          if content then
            M._do_refactor_with_content(content, instruction, bufnr, start_row, end_row)
          end
        end
      )
      return -- Exit early, callback will handle the rest
    else
      -- Small file - use entire file
      content = table.concat(lines, "\n")
      start_row = 0
      end_row = line_count - 1
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

-- Helper function for refactoring with content
function M._do_refactor_with_content(content, instruction, bufnr, start_row, end_row, opts)
  opts = opts or {}
  local llm = require("caramba.llm")
  local edit = require("caramba.edit")

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

-- Setup commands for this module
function M.setup_commands()
  local commands = require('caramba.core.commands')
  
  -- Main refactoring command
  commands.register("Refactor", function(args)
    if args.args == "" then
      vim.notify("Please provide refactoring instruction", vim.log.levels.WARN)
      return
    end
    
    M.refactor_with_instruction(args.args)
  end, {
    desc = "AI: Refactor with custom instruction",
    nargs = "+",
    range = true,
  })
  
  -- Rename symbol
  commands.register("Rename", function(args)
    if args.args == "" then
      vim.notify("Usage: :Rename <new_name>", vim.log.levels.ERROR)
      return
    end
    
    M.rename_symbol(args.args)
  end, {
    desc = "AI: Rename symbol project-wide",
    nargs = 1,
  })
  
  -- Extract function
  commands.register("ExtractFunction", M.extract_function, {
    desc = "AI: Extract function from selection",
    range = true,
  })
  
  -- Simplify logic
  commands.register("SimplifyLogic", M.simplify_conditional, {
    desc = "AI: Simplify conditional logic",
  })
  
  -- Add type annotations
  commands.register("AddTypes", M.add_type_annotations, {
    desc = "AI: Add type annotations",
  })
  
  -- Organize imports
  commands.register("OrganizeImports", M.organize_imports, {
    desc = "AI: Organize imports",
  })
end

return M 