-- Core Caramba Commands
-- Handles system-wide commands and delegates module-specific commands

local M = {}

-- Keywords that indicate a complex task requiring planning
local COMPLEX_KEYWORDS = {"implement", "create", "build", "design", "refactor", "migrate", "convert"}

-- Core completion functionality
function M._do_completion(instruction)
  local context = require("caramba.context")
  local llm = require("caramba.llm")
  local edit = require("caramba.edit")
  local utils = require("caramba.utils")
  
  -- Check if this is a complex task that needs planning
  local lower_instruction = instruction:lower()
  local is_complex = false
  
  for _, keyword in ipairs(COMPLEX_KEYWORDS) do
    if lower_instruction:match("^%s*" .. keyword) then
      is_complex = true
      break
    end
  end
  
  if is_complex then
    vim.notify("This looks like a complex task. Consider using :CarambaPlan for better results.", vim.log.levels.WARN)
    vim.ui.select({"Use Planner", "Continue with Completion"}, {
      prompt = "This task might benefit from planning first:",
    }, function(choice)
      if choice == "Use Planner" then
        local planner = require("caramba.planner")
        planner.interactive_planning_session(instruction)
        return
      else
        M._do_simple_completion(instruction)
      end
    end)
  else
    M._do_simple_completion(instruction)
  end
end

function M._do_simple_completion(instruction)
  local context = require("caramba.context")
  local llm = require("caramba.llm")
  local edit = require("caramba.edit")
  
  vim.notify("Caramba: Extracting context...", vim.log.levels.INFO)
  
  -- Build context
  local ctx = context.build_completion_context()
  if not ctx then
    vim.notify("Caramba: Cannot get context - ensure Tree-sitter parser is installed for this filetype", vim.log.levels.WARN)
    return
  end
  
  local prompt = llm.build_completion_prompt(ctx, instruction)
  
  vim.notify("Caramba: Generating completion for: " .. instruction, vim.log.levels.INFO)
  
  llm.request(prompt, { stream = false }, function(result, err)
    if err then
      vim.notify("Completion failed: " .. err, vim.log.levels.ERROR)
      return
    end

    local cursor_line = vim.fn.line('.') - 1
    local lines = vim.split(result, '\n')
    local end_row = cursor_line + (#lines - 1)
    edit.show_diff_preview(0, cursor_line, end_row, result, function()
      local success, err2 = edit.insert_at_cursor(result)
      if success then
        vim.notify("Caramba: Completion applied", vim.log.levels.INFO)
      else
        vim.notify("Caramba: Completion failed - " .. err2, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Helper function for explanations
function M._do_explanation(content, context_info, question)
  local llm = require("caramba.llm")
  local utils = require("caramba.utils")

  vim.notify("Caramba: Analyzing " .. context_info:lower() .. "...", vim.log.levels.INFO)

  local prompt = llm.build_explanation_prompt(content, question)

  llm.request(prompt, { stream = false }, function(result, err)
    if err then
      vim.notify("Explanation failed: " .. err, vim.log.levels.ERROR)
      return
    end

    local title = "Caramba Explanation"
    if context_info then
      title = title .. " - " .. context_info
    end

    utils.show_result_window(result, title)
  end)
end

-- Setup core commands only
function M.setup_commands()
  local commands = require('caramba.core.commands')
  local context = require("caramba.context")
  local llm = require("caramba.llm")
  local utils = require("caramba.utils")
  local config = require("caramba.config")
  
  -- Core completion command
  commands.register("Complete", function(args)
    local instruction = args.args
    
    if instruction == "" then
      vim.ui.input({
        prompt = "Caramba Complete: What would you like me to do? ",
        default = "Complete the code at cursor",
      }, function(input)
        if input and input ~= "" then
          M._do_completion(input)
        end
      end)
    else
      M._do_completion(instruction)
    end
  end, {
    desc = "Caramba: Complete code at cursor",
    nargs = "?",
  })
  
  -- Core explain command
  commands.register("Explain", function(args)
    local mode = vim.fn.mode()
    local content
    local context_info = ""

    if mode == "v" or mode == "V" then
      -- Visual selection - use selected text
      content = utils.get_visual_selection()
      context_info = "Selected code"
    else
      -- No selection - use entire file
      local bufnr = vim.api.nvim_get_current_buf()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      content = table.concat(lines, "\n")

      local filename = vim.fn.expand("%:t")
      local filetype = vim.bo.filetype
      context_info = string.format("Entire file: %s (%s)", filename, filetype)

      -- If file is very large, warn user and offer to explain just current function
      local line_count = #lines
      if line_count > 500 then
        vim.ui.select(
          {"Entire file (" .. line_count .. " lines)", "Current function/scope only"},
          {
            prompt = "File is large. What would you like to explain?",
          },
          function(choice)
            if choice and choice:match("Current function") then
              local ctx = context.collect()
              if ctx and ctx.content then
                content = ctx.content
                context_info = "Current scope"
              end
            end
            -- Continue with explanation
            M._do_explanation(content, context_info, args.args)
          end
        )
        return
      end
    end

    if not content or content:match("^%s*$") then
      vim.notify("No code to explain", vim.log.levels.WARN)
      return
    end

    M._do_explanation(content, context_info, args.args)
  end, {
    desc = "Caramba: Explain code",
    nargs = "?",
    range = true,
  })
  
  -- System configuration commands
  commands.register("SetProvider", function(args)
    local provider = args.args
    local valid_providers = {"openai", "anthropic", "ollama"}
    
    if not vim.tbl_contains(valid_providers, provider) then
      vim.notify("Invalid provider. Choose from: " .. table.concat(valid_providers, ", "), vim.log.levels.ERROR)
      return
    end
    
    local cfg = config.get()
    cfg.provider = provider
    vim.notify("Caramba: Provider set to " .. provider, vim.log.levels.INFO)
  end, {
    desc = "Caramba: Set LLM provider",
    nargs = 1,
    complete = function()
      return {"openai", "anthropic", "ollama"}
    end,
  })
  
  -- Cache management
  commands.register("ClearCache", function()
    llm.clear_cache()
    context.clear_cache()
    vim.notify("Caramba: All caches cleared", vim.log.levels.INFO)
  end, {
    desc = "Caramba: Clear all caches",
  })
  
  -- Debug commands
  commands.register("DebugContext", function()
    local ctx = context.collect()
    if ctx then
      local info = string.format(
        "File: %s\nLanguage: %s\nFunction: %s\nClass: %s\nImports: %d\nContent Length: %d chars",
        ctx.file_path or "unknown",
        ctx.language or "unknown",
        ctx.current_function or "none",
        ctx.current_class or "none",
        ctx.imports and #ctx.imports or 0,
        ctx.content and #ctx.content or 0
      )
      utils.show_result_window(info, "Context Debug Info")
    else
      vim.notify("No context available", vim.log.levels.WARN)
    end
  end, {
    desc = "Caramba: Show current context info",
  })
  
  -- Cancel any ongoing operations
  commands.register("Cancel", function()
    llm.cancel_all()
    vim.notify("Caramba: Cancelled all pending operations", vim.log.levels.INFO)
  end, {
    desc = "Caramba: Cancel all pending LLM requests",
  })
  
  -- Show all registered commands
  commands.register("ShowCommands", function()
    local cmds = commands.list()
    local lines = {"=== Registered Caramba Commands ===", ""}
    
    for _, cmd in ipairs(cmds) do
      table.insert(lines, string.format("%-30s %s", cmd.name, cmd.desc))
    end
    
    utils.show_result_window(table.concat(lines, "\n"), "Caramba Commands")
  end, {
    desc = "Caramba: Show all registered commands",
  })
end

return M 