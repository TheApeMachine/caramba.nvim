-- AI Assistant Commands
-- User-facing commands for all AI features

local M = {}

-- Setup all commands
function M.setup()
  local context = require("caramba.context")
  local llm = require("caramba.llm")
  local edit = require("caramba.edit")
  local refactor = require("caramba.refactor")
  local search = require("caramba.search")
  local config = require("caramba.config")
  local ai = require('ai')
  
  -- Completion command
  vim.api.nvim_create_user_command("AIComplete", function(args)
    local instruction = args.args
    
    -- If no instruction provided, ask for one
    if instruction == "" then
      vim.ui.input({
        prompt = "AI Complete: What would you like me to do? ",
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
    desc = "AI: Complete code at cursor",
    nargs = "?",
  })
  
  -- Helper function for completion
  function M._do_completion(instruction)
    -- Check if this is a complex task that needs planning
    local lower_instruction = instruction:lower()
    local complex_keywords = {"implement", "create", "build", "design", "refactor", "migrate", "convert"}
    local is_complex = false
    
    for _, keyword in ipairs(complex_keywords) do
      -- Check if instruction starts with the keyword (ignoring whitespace)
      if lower_instruction:match("^%s*" .. keyword) then
        is_complex = true
        break
      end
    end
    
    if is_complex then
      vim.notify("This looks like a complex task. Consider using :AIPlan for better results.", vim.log.levels.WARN)
      -- Ask if they want to use the planner instead
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
    -- Show what we're doing
    vim.notify("AI: Extracting context...", vim.log.levels.INFO)
    
    -- Build context
    local ctx = context.build_completion_context()
    if not ctx then
      vim.notify("AI: Cannot get context - ensure Tree-sitter parser is installed for this filetype", vim.log.levels.WARN)
      return
    end
    
    local prompt = llm.build_completion_prompt(ctx, instruction)
    
    vim.notify("AI: Generating completion for: " .. instruction, vim.log.levels.INFO)
    
    llm.request(prompt, {}, function(result, err)
      if err then
        vim.schedule(function()
          vim.notify("Completion failed: " .. err, vim.log.levels.ERROR)
        end)
        return
      end
      
      -- Check if we should show a preview first
      vim.schedule(function()
        local cursor_line = vim.fn.line('.') - 1
        local lines = vim.split(result, '\n')
        local end_row = cursor_line + (#lines - 1)
        edit.show_diff_preview(0, cursor_line, end_row, result, function()
          -- User accepted, apply the edit
          local success, err = edit.insert_at_cursor(result)
          if success then
            vim.notify("AI: Completion applied", vim.log.levels.INFO)
          else
            vim.notify("AI: Completion failed - " .. err, vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end
  
  -- Explain command
  vim.api.nvim_create_user_command("AIExplain", function(args)
    local mode = vim.fn.mode()
    local content
    
    if mode == "v" or mode == "V" then
      -- Get visual selection
      local start_pos = vim.fn.getpos("'<")
      local end_pos = vim.fn.getpos("'>")
      local lines = vim.api.nvim_buf_get_lines(
        0, start_pos[2] - 1, end_pos[2], false
      )
      content = table.concat(lines, "\n")
    else
      -- Get current context
      local ctx = context.collect()
      if ctx then
        content = ctx.content
      end
    end
    
    if not content then
      vim.notify("No code to explain", vim.log.levels.WARN)
      return
    end
    
    local question = args.args ~= "" and args.args or nil
    local prompt = llm.build_explanation_prompt(content, question)
    
    llm.request(prompt, {}, function(result, err)
      if err then
        vim.notify("Explanation failed: " .. err, vim.log.levels.ERROR)
        return
      end
      
      -- Show in floating window
      M._show_result_window(result, "AI Explanation")
    end)
  end, {
    desc = "AI: Explain code",
    nargs = "?",
    range = true,
  })
  
  -- Refactoring commands
  vim.api.nvim_create_user_command("AIRefactor", function(args)
    if args.args == "" then
      vim.notify("Please provide refactoring instruction", vim.log.levels.WARN)
      return
    end
    
    refactor.refactor_with_instruction(args.args)
  end, {
    desc = "AI: Refactor with custom instruction",
    nargs = "+",
    range = true,
  })
  
  vim.api.nvim_create_user_command("AIRename", function(args)
    if args.args == "" then
      vim.notify("Usage: :AIRename <new_name>", vim.log.levels.ERROR)
      return
    end
    
    refactor.rename_symbol(args.args)
  end, {
    desc = "AI: Rename symbol",
    nargs = 1,
  })
  
  vim.api.nvim_create_user_command("AIExtractFunction", function()
    refactor.extract_function()
  end, {
    desc = "AI: Extract function from selection",
    range = true,
  })
  
  vim.api.nvim_create_user_command("AISimplifyLogic", function()
    refactor.simplify_conditional()
  end, {
    desc = "AI: Simplify conditional logic",
  })
  
  vim.api.nvim_create_user_command("AIAddTypes", function()
    refactor.add_type_annotations()
  end, {
    desc = "AI: Add type annotations",
  })
  
  vim.api.nvim_create_user_command("AIOrganizeImports", function()
    refactor.organize_imports()
  end, {
    desc = "AI: Organize imports",
  })
  
  -- Search commands
  vim.api.nvim_create_user_command("AISearch", function(args)
    local search = require("caramba.search")
    local query = args.args
    
    if query == "" then
      vim.ui.input({
        prompt = "Search query: ",
      }, function(input)
        if input and input ~= "" then
          M._do_search(input)
        end
      end)
    else
      M._do_search(query)
    end
  end, {
    desc = "AI: Search codebase",
    nargs = "?",
  })
  
  vim.api.nvim_create_user_command("AIEnableEmbeddings", function()
    local config = require("caramba.config")
    local current = config.get()
    current.search.use_embeddings = true
    vim.notify("AI: Embeddings-based search enabled. Re-index to generate embeddings.", vim.log.levels.INFO)
  end, {
    desc = "AI: Enable embeddings-based search",
  })
  
  vim.api.nvim_create_user_command("AIDisableEmbeddings", function()
    local config = require("caramba.config")
    local current = config.get()
    current.search.use_embeddings = false
    vim.notify("AI: Embeddings-based search disabled. Using keyword search.", vim.log.levels.INFO)
  end, {
    desc = "AI: Disable embeddings-based search",
  })
  
  vim.api.nvim_create_user_command("AISetEmbeddingDimensions", function(args)
    local config = require("caramba.config")
    local dimensions = tonumber(args.args)
    
    if not dimensions then
      vim.notify("AI: Invalid dimensions. Usage: :AISetEmbeddingDimensions <number>", vim.log.levels.ERROR)
      return
    end
    
    local current = config.get()
    local model = current.search.embedding_model
    local max_dims = model == "text-embedding-3-large" and 3072 or 1536
    
    if dimensions < 256 or dimensions > max_dims then
      vim.notify(string.format("AI: Dimensions must be between 256 and %d for model %s", max_dims, model), vim.log.levels.ERROR)
      return
    end
    
    current.search.embedding_dimensions = dimensions
    vim.notify(string.format("AI: Embedding dimensions set to %d. Re-index to apply changes.", dimensions), vim.log.levels.INFO)
  end, {
    desc = "AI: Set embedding dimensions",
    nargs = 1,
  })
  
  vim.api.nvim_create_user_command("AISetEmbeddingModel", function(args)
    local config = require("caramba.config")
    local model = args.args
    
    if model ~= "text-embedding-3-small" and model ~= "text-embedding-3-large" then
      vim.notify("AI: Invalid model. Use 'text-embedding-3-small' or 'text-embedding-3-large'", vim.log.levels.ERROR)
      return
    end
    
    local current = config.get()
    current.search.embedding_model = model
    
    -- Adjust dimensions if needed
    local max_dims = model == "text-embedding-3-large" and 3072 or 1536
    if current.search.embedding_dimensions > max_dims then
      current.search.embedding_dimensions = max_dims
      vim.notify(string.format("AI: Model set to %s, dimensions adjusted to %d", model, max_dims), vim.log.levels.INFO)
    else
      vim.notify(string.format("AI: Model set to %s. Re-index to apply changes.", model), vim.log.levels.INFO)
    end
  end, {
    desc = "AI: Set embedding model",
    nargs = 1,
    complete = function()
      return { "text-embedding-3-small", "text-embedding-3-large" }
    end,
  })
  
  vim.api.nvim_create_user_command("AIIndexWorkspace", function()
    local search = require("caramba.search")
    search.index_workspace(function()
      vim.notify("AI: Workspace indexing complete", vim.log.levels.INFO)
    end)
  end, {
    desc = "AI: Index workspace for search",
  })
  
  vim.api.nvim_create_user_command("AIFindDefinition", function(args)
    local symbol = args.args
    if symbol == "" then
      -- Get symbol under cursor
      local node = require("nvim-treesitter.ts_utils").get_node_at_cursor()
      if node and node:type() == "identifier" then
        symbol = context.get_node_text(node)
      end
    end
    
    if symbol == "" then
      vim.notify("No symbol specified", vim.log.levels.WARN)
      return
    end
    
    local definition = search.find_definition(symbol)
    if definition then
      M._jump_to_location(definition)
    else
      vim.notify("Definition not found for: " .. symbol, vim.log.levels.WARN)
    end
  end, {
    desc = "AI: Find definition",
    nargs = "?",
  })
  
  vim.api.nvim_create_user_command("AIFindReferences", function(args)
    local symbol = args.args
    if symbol == "" then
      -- Get symbol under cursor
      local node = require("nvim-treesitter.ts_utils").get_node_at_cursor()
      if node and node:type() == "identifier" then
        symbol = context.get_node_text(node)
      end
    end
    
    if symbol == "" then
      vim.notify("No symbol specified", vim.log.levels.WARN)
      return
    end
    
    local references = search.find_references(symbol)
    M._show_search_results(references, "References to: " .. symbol)
  end, {
    desc = "AI: Find references",
    nargs = "?",
  })
  
  -- Index management
  vim.api.nvim_create_user_command("AIIndexStats", function()
    local stats = search.get_stats()
    vim.notify(string.format(
      "AI Index: %d files, %d nodes%s",
      stats.files,
      stats.nodes,
      stats.indexing and " (indexing...)" or ""
    ))
  end, {
    desc = "AI: Show index statistics",
  })
  
  -- Edit commands
  vim.api.nvim_create_user_command("AIUndo", function(args)
    local steps = tonumber(args.args) or 1
    edit.rollback(steps)
    vim.notify(string.format("Rolled back %d edit(s)", steps))
  end, {
    desc = "AI: Undo AI edits",
    nargs = "?",
  })
  
  -- Configuration commands
  vim.api.nvim_create_user_command("AISetProvider", function(args)
    if args.args == "" then
      vim.notify("Current provider: " .. config.get().provider)
      return
    end
    
    config.update("provider", args.args)
    vim.notify("AI provider set to: " .. args.args)
  end, {
    desc = "AI: Set LLM provider",
    nargs = "?",
    complete = function()
      return { "openai", "anthropic", "ollama" }
    end,
  })
  
  vim.api.nvim_create_user_command("AISetModel", function(args)
    if args.args == "" then
      local provider = config.get().provider
      local model = config.get().api[provider].model
      vim.notify("Current model: " .. model)
      return
    end
    
    local provider = config.get().provider
    config.update("api." .. provider .. ".model", args.args)
    vim.notify("Model set to: " .. args.args)
  end, {
    desc = "AI: Set LLM model",
    nargs = "?",
  })
  
  -- Debug commands
  vim.api.nvim_create_user_command("AIDebugContext", function()
    local ctx = context.collect({
      include_parent = true,
      include_siblings = true,
    })
    
    if not ctx then
      vim.notify("No context available", vim.log.levels.WARN)
      return
    end
    
    local info = vim.inspect(ctx)
    M._show_result_window(info, "AI Context Debug")
  end, {
    desc = "AI: Debug context extraction",
  })
  
  vim.api.nvim_create_user_command("AIClearCache", function()
    llm.clear_cache()
    context.clear_cache()
    vim.notify("AI caches cleared")
  end, {
    desc = "AI: Clear all caches",
  })
  
  -- Test command
  vim.api.nvim_create_user_command("AITest", function()
    vim.notify("AI: Running system test...", vim.log.levels.INFO)
    
    -- Test 1: Check configuration
    local config_ok = pcall(require, "caramba.config")
    if not config_ok then
      vim.notify("❌ Configuration module failed", vim.log.levels.ERROR)
      return
    end
    vim.notify("✓ Configuration loaded", vim.log.levels.INFO)
    
    -- Test 2: Check API key
    local provider = config.get().provider
    local api_key = nil
    if provider == "openai" then
      api_key = config.get().api.openai.api_key
    elseif provider == "anthropic" then
      api_key = config.get().api.anthropic.api_key
    end
    
    if not api_key or api_key == "" then
      vim.notify("❌ No API key found for " .. provider, vim.log.levels.ERROR)
      vim.notify("Set OPENAI_API_KEY or ANTHROPIC_API_KEY environment variable", vim.log.levels.WARN)
      return
    end
    vim.notify("✓ API key configured for " .. provider, vim.log.levels.INFO)
    
    -- Test 3: Simple LLM request
    vim.notify("Testing LLM connection...", vim.log.levels.INFO)
    
    local test_prompt = {
      {
        role = "system",
        content = "You are a helpful assistant testing the AI system."
      },
      {
        role = "user",
        content = "Please confirm the AI system is working"
      }
    }
    
    -- Use structured output with JSON schema for OpenAI
    local test_opts = { temperature = 0 }
    
    if config.get().provider == "openai" then
      test_opts.response_format = {
        type = "json_schema",
        json_schema = {
          name = "system_test",
          strict = true,
          schema = {
            type = "object",
            properties = {
              status = { 
                type = "string",
                enum = { "ok", "error" }
              },
              message = { type = "string" }
            },
            required = { "status", "message" },
            additionalProperties = false
          }
        }
      }
    else
      -- For non-OpenAI providers, we need to prompt
      test_prompt[1].content = test_prompt[1].content .. ' Return JSON with status="ok" and message="AI system working".'
    end
    
    llm.request(test_prompt, test_opts, function(result, err)
      vim.schedule(function()
        if err then
          vim.notify("❌ LLM request failed: " .. err, vim.log.levels.ERROR)
          return
        end
        
        local ok, parsed = pcall(vim.json.decode, result)
        if ok and parsed.status == "ok" then
          vim.notify("✓ LLM connection successful", vim.log.levels.INFO)
          vim.notify("✓ JSON parsing working", vim.log.levels.INFO)
          vim.notify("🎉 AI system is fully operational!", vim.log.levels.INFO)
        else
          vim.notify("❌ LLM returned invalid response", vim.log.levels.ERROR)
          M._show_result_window(result, "LLM Test Response")
        end
      end)
    end)
  end, {
    desc = "AI: Test setup",
  })
  
  -- Inline completion (ghost text style)
  vim.api.nvim_create_user_command("AIInlineComplete", function()
    -- Get context
    local context_str = context.build_completion_context()
    if not context_str or context_str == "" then
      return
    end
    
    -- Simple prompt for inline completion
    local prompt = llm.build_completion_prompt(context_str, "Complete the current line or statement")
    
    llm.request(prompt, { temperature = 0.1 }, function(result, err)
      if err or not result then
        return
      end
      
      vim.schedule(function()
        -- Show as virtual text (ghost text)
        local lines = vim.split(result, "\n")
        local first_line = lines[1] or ""
        
        -- Create a namespace for our virtual text
        local ns = vim.api.nvim_create_namespace("ai_inline_completion")
        
        -- Clear previous virtual text
        vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
        
        -- Add virtual text at cursor
        local row = vim.fn.line(".") - 1
        vim.api.nvim_buf_set_extmark(0, ns, row, -1, {
          virt_text = {{first_line, "Comment"}},
          virt_text_pos = "inline",
        })
        
        -- Store the completion for accepting
        vim.b.ai_inline_completion = result
        
        -- Show hint
        vim.notify("Press <Tab> to accept, <Esc> to dismiss", vim.log.levels.INFO)
      end)
    end)
  end, {
    desc = "AI: Show inline completion",
  })
  
  -- Accept inline completion
  vim.api.nvim_create_user_command("AIAcceptInline", function()
    if vim.b.ai_inline_completion then
      local success, err = edit.insert_at_cursor(vim.b.ai_inline_completion)
      if success then
        -- Clear the virtual text
        local ns = vim.api.nvim_create_namespace("ai_inline_completion")
        vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
        vim.b.ai_inline_completion = nil
      else
        vim.notify("Failed to accept completion: " .. err, vim.log.levels.ERROR)
      end
    end
  end, {
    desc = "AI: Accept inline completion",
  })
  
  -- Clear inline completion
  vim.api.nvim_create_user_command("AIClearInline", function()
    local ns = vim.api.nvim_create_namespace("ai_inline_completion")
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    vim.b.ai_inline_completion = nil
  end, {
    desc = "AI: Clear inline completion",
  })
  
  -- Planning commands
  vim.api.nvim_create_user_command('AIPlan', function(opts)
    local planner = require('caramba.planner')
    if opts.args == "" then
      vim.ui.input({
        prompt = "What would you like to implement? ",
      }, function(input)
        if input and input ~= "" then
          planner.interactive_planning_session(input)
        end
      end)
    else
      planner.interactive_planning_session(opts.args)
    end
  end, { nargs = '?', desc = 'Create an implementation plan' })
  
  vim.api.nvim_create_user_command('AIExecutePlan', function()
    planner.execute_plan()
  end, { desc = 'Execute the current plan' })
  
  vim.api.nvim_create_user_command('AIShowPlan', function()
    planner.show_current_plan()
  end, { desc = 'Show current plan' })
  
  vim.api.nvim_create_user_command("AIAnalyzeProject", function()
    local planner = require("caramba.planner")
    vim.notify("AI: Analyzing project structure...", vim.log.levels.INFO)
    
    planner.analyze_project_structure(function(result, err)
      if err then
        vim.schedule(function()
          vim.notify("Failed to analyze project: " .. err, vim.log.levels.ERROR)
        end)
        return
      end
      
      vim.schedule(function()
        -- First, try to parse as JSON
        local ok, analysis = pcall(vim.json.decode, result)
        if ok and type(analysis) == "table" then
          -- Update project plan
          planner._project_plan.architecture = analysis
          planner.save_project_plan()
          vim.notify("AI: Project analysis complete!", vim.log.levels.INFO)
          
          -- Show results
          M._show_result_window(vim.json.encode(analysis), "Project Analysis")
        else
          -- If not valid JSON, show the raw response
          vim.notify("AI: Analysis returned non-JSON response", vim.log.levels.WARN)
          M._show_result_window(result, "Project Analysis (Raw Response)")
          
          -- Try to extract useful information anyway
          local lines = vim.split(result, "\n")
          local extracted = {
            raw_analysis = result,
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            note = "Analysis was not in expected JSON format"
          }
          
          -- Save what we can
          planner._project_plan.architecture = extracted
          planner.save_project_plan()
        end
      end)
    end)
  end, {
    desc = "AI: Analyze project structure",
  })
  
  vim.api.nvim_create_user_command("AILearnPatterns", function()
    local planner = require("caramba.planner")
    planner.learn_from_codebase()
  end, {
    desc = "AI: Learn from codebase patterns",
  })
  
  -- Chat commands
  vim.api.nvim_create_user_command('AIChat', function()
    require('caramba.chat').toggle()
  end, {
    desc = "Toggle AI chat window"
  })
  
  -- Multi-file operation commands
  vim.api.nvim_create_user_command('AIRenameSymbol', function(opts)
    local old_name = vim.fn.expand('<cword>')
    local new_name = opts.args
    
    if new_name == "" then
      new_name = vim.fn.input("Rename '" .. old_name .. "' to: ")
      if new_name == "" then
        return
      end
    end
    
    require('caramba.multifile').rename_symbol(old_name, new_name)
  end, {
    nargs = '?',
    desc = "AI: Rename symbol across all files"
  })
  
  vim.api.nvim_create_user_command('AIExtractModule', function(opts)
    local module_name = opts.args
    if module_name == "" then
      module_name = vim.fn.input("New module name: ")
      if module_name == "" then
        return
      end
    end
    
    require('caramba.multifile').extract_module(module_name)
  end, {
    nargs = '?',
    desc = "AI: Extract functionality into a new module"
  })
  
  -- Testing commands
  vim.api.nvim_create_user_command('AIGenerateTests', function(opts)
    require('caramba.testing').generate_tests({
      framework = opts.args ~= "" and opts.args or nil
    })
  end, {
    nargs = '?',
    desc = "AI: Generate unit tests for current function/class"
  })
  
  vim.api.nvim_create_user_command('AIUpdateTests', function()
    require('caramba.testing').update_tests()
  end, {
    desc = "AI: Update tests to match implementation changes"
  })
  
  vim.api.nvim_create_user_command('AIAnalyzeTestFailures', function(opts)
    require('caramba.testing').analyze_test_failures({
      output = opts.args ~= "" and opts.args or nil
    })
  end, {
    nargs = '?',
    desc = "AI: Analyze test failures and suggest fixes"
  })
  
  -- Debugging commands
  vim.api.nvim_create_user_command('AIDebugError', function(opts)
    require('caramba.debug').analyze_error({
      error = opts.args ~= "" and opts.args or nil
    })
  end, {
    nargs = '?',
    desc = "AI: Analyze error/stack trace"
  })
  
  vim.api.nvim_create_user_command('AIApplyFix', function()
    require('caramba.debug').apply_fixes()
  end, {
    desc = "AI: Apply pending debug fixes"
  })
  
  vim.api.nvim_create_user_command('AIDebugSession', function()
    require('caramba.debug').start_debug_session()
  end, {
    desc = "AI: Start interactive debug session"
  })
  
  vim.api.nvim_create_user_command('AIAnalyzePerformance', function(opts)
    local profile_data = opts.args
    if profile_data == "" then
      -- Try to get from current buffer
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      profile_data = table.concat(lines, "\n")
    end
    
    require('caramba.debug').analyze_performance({
      profile = profile_data
    })
  end, {
    nargs = '?',
    desc = "AI: Analyze performance profile"
  })
  
  -- Commit message generation
  vim.api.nvim_create_user_command('AICommitMessage', function()
    local diff = vim.fn.system('git diff --staged')
    if diff == "" then
      vim.notify("No staged changes", vim.log.levels.WARN)
      return
    end
    
    local prompt = [[
Generate a commit message for these changes following Conventional Commits specification:

``` 
]] .. diff .. [[
```

Format:
<type>(<scope>): <description>

<body>

<footer>

Types: feat, fix, docs, style, refactor, perf, test, chore
Keep the description under 50 characters.
]]

    require('caramba.llm').request(prompt, { temperature = 0.3 }, function(response)
      if response then
        vim.schedule(function()
          -- If in a git commit buffer, insert the message
          if vim.bo.filetype == "gitcommit" then
            local lines = vim.split(response, "\n")
            vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
          else
            -- Otherwise show in a floating window
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
            
            local width = math.min(80, vim.o.columns - 4)
            local height = math.min(20, vim.o.lines - 4)
            
            local win = vim.api.nvim_open_win(buf, true, {
              relative = 'editor',
              row = math.floor((vim.o.lines - height) / 2),
              col = math.floor((vim.o.columns - width) / 2),
              width = width,
              height = height,
              style = 'minimal',
              border = 'rounded',
              title = ' Generated Commit Message ',
              title_pos = 'center',
            })
            
            -- Copy to clipboard on yank
            vim.keymap.set('n', 'y', function()
              vim.fn.setreg('+', response)
              vim.notify("Commit message copied to clipboard")
              vim.api.nvim_win_close(win, true)
            end, { buffer = buf })
          end
        end)
      end
    end)
  end, {
    desc = "AI: Generate commit message from staged changes"
  })
  
  -- Code review command
  vim.api.nvim_create_user_command('AIReviewCode', function(opts)
    local ctx = require('caramba.context').collect()
    if not ctx then
      vim.notify("Could not extract context", vim.log.levels.ERROR)
      return
    end
    
    local prompt = [[
Please review this code for:
1. Potential bugs or logic errors
2. Performance issues
3. Security vulnerabilities
4. Code style and best practices
5. Suggestions for improvement

Code:
```]] .. ctx.language .. "\n" .. (ctx.node_text or ctx.current_line) .. [[
```

Provide specific, actionable feedback with examples where applicable.
]]

    require('caramba.llm').request(prompt, { temperature = 0.3 }, function(response)
      if response then
        vim.schedule(function()
          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
          vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
          
          vim.cmd('vsplit')
          vim.api.nvim_set_current_buf(buf)
        end)
      end
    end)
  end, {
    desc = "AI: Review current code"
  })
  
  -- System commands
  vim.api.nvim_create_user_command('AICancel', function()
    require('caramba.llm').cancel_all()
    vim.notify("All AI requests cancelled", vim.log.levels.INFO)
  end, {
    desc = "AI: Cancel all active requests"
  })
  
  -- Web search commands
  vim.api.nvim_create_user_command('AIWebSearch', function(opts)
    if opts.args == "" then
      local query = vim.fn.input("Search query: ")
      if query == "" then return end
      opts.args = query
    end
    
    require('caramba.websearch').search(opts.args)
  end, {
    nargs = '?',
    desc = "AI: Search the web"
  })
  
  vim.api.nvim_create_user_command('AIWebSummary', function(opts)
    if opts.args == "" then
      local query = vim.fn.input("Search and summarize: ")
      if query == "" then return end
      opts.args = query
    end
    
    require('caramba.websearch').search_and_summarize(opts.args)
  end, {
    nargs = '?',
    desc = "AI: Search web and summarize results"
  })
  
  vim.api.nvim_create_user_command('AIResearch', function(opts)
    if opts.args == "" then
      local topic = vim.fn.input("Research topic: ")
      if topic == "" then return end
      opts.args = topic
    end
    
    require('caramba.websearch').research_topic(opts.args)
  end, {
    nargs = '?',
    desc = "AI: Deep research on a topic"
  })
  
  vim.api.nvim_create_user_command('AIQuery', function(opts)
    if opts.args == "" then
      local query = vim.fn.input("AI Query (with tool support): ")
      if query == "" then return end
      opts.args = query
    end
    
    require('caramba.tools').query_with_tools(opts.args)
  end, {
    nargs = '?',
    desc = "AI: Query with access to web search and tools"
  })
  
  -- AST Transformation commands
  vim.api.nvim_create_user_command('AITransform', function(opts)
    local transform_name = opts.args
    if transform_name == "" then
      -- Show available transformations
      local transforms = {
        "callback_to_async - Convert callbacks to async/await",
        "class_to_function - Convert React classes to functions", 
        "cjs_to_esm - Convert CommonJS to ES modules",
        "py2_to_py3 - Convert Python 2 to Python 3",
      }
      vim.ui.select(transforms, {
        prompt = "Select transformation:",
      }, function(choice)
        if choice then
          local name = choice:match("^(%w+)")
          require('caramba.ast_transform').apply_transformation(name)
        end
      end)
    else
      require('caramba.ast_transform').apply_transformation(transform_name)
    end
  end, {
    nargs = '?',
    desc = "AI: Apply AST transformation",
    complete = function()
      return {'callback_to_async', 'class_to_function', 'cjs_to_esm', 'py2_to_py3'}
    end,
  })
  
  vim.api.nvim_create_user_command('AICrossRename', function(opts)
    local args = vim.split(opts.args, " ")
    if #args < 2 then
      vim.notify("Usage: :AICrossRename <old_name> <new_name>", vim.log.levels.ERROR)
      return
    end
    require('caramba.ast_transform').cross_language_rename(args[1], args[2])
  end, {
    nargs = '+',
    desc = "AI: Cross-language symbol rename"
  })
  
  vim.api.nvim_create_user_command('AISemanticMerge', function(opts)
    -- This would typically be called from a git merge conflict
    vim.notify("Semantic merge requires git conflict markers in buffer", vim.log.levels.INFO)
  end, {
    desc = "AI: Semantic merge for conflicts"
  })
  

  

  

  
  -- TDD commands
  vim.api.nvim_create_user_command('AIImplementFromTest', function()
    caramba.tdd.implement_from_test()
  end, { desc = 'Implement code from test specification' })
  
  vim.api.nvim_create_user_command('AIGeneratePropertyTests', function()
    caramba.tdd.generate_property_tests()
  end, { desc = 'Generate property-based tests for function' })
  
  vim.api.nvim_create_user_command('AIWatchTests', function()
    caramba.tdd.watch_tests()
  end, { desc = 'Watch tests and suggest fixes on failure' })
  
  vim.api.nvim_create_user_command('AIImplementUncovered', function()
    caramba.tdd.implement_uncovered_code()
  end, { desc = 'Implement code for uncovered test cases' })
  
  -- Consistency commands
  vim.api.nvim_create_user_command('AILearnPatterns', function()
    caramba.consistency.learn_patterns()
  end, { desc = 'Learn coding patterns from codebase' })
  
  vim.api.nvim_create_user_command('AICheckConsistency', function()
    caramba.consistency.check_file()
  end, { desc = 'Check current file for consistency issues' })
  
  vim.api.nvim_create_user_command('AIEnableConsistencyCheck', function()
    caramba.consistency.enable_auto_check()
  end, { desc = 'Enable automatic consistency checking on save' })
  
  -- Git commands
  vim.api.nvim_create_user_command('AICommitMessage', function()
    caramba.git.generate_commit_message()
  end, { desc = 'Generate commit message from staged changes' })
  
  vim.api.nvim_create_user_command('AIReviewPR', function()
    caramba.git.review_pr()
  end, { desc = 'Review pull request changes' })
  
  vim.api.nvim_create_user_command('AIExplainDiff', function()
    caramba.git.explain_diff()
  end, { desc = 'Explain current diff' })
  
  vim.api.nvim_create_user_command('AIResolveConflict', function()
    caramba.git.resolve_conflict()
  end, { desc = 'Help resolve merge conflict' })
  
  vim.api.nvim_create_user_command('AIImproveCommit', function()
    caramba.git.improve_commit_message()
  end, { desc = 'Improve commit message' })
  
  vim.api.nvim_create_user_command('AIGitBlame', function()
    caramba.git.explain_blame()
  end, { desc = 'Explain git blame for current line' })
  
  -- Pair programming commands
  vim.api.nvim_create_user_command('AIPairStart', function()
    caramba.pair.start_session()
  end, { desc = 'Start AI pair programming session' })
  
  vim.api.nvim_create_user_command('AIPairStop', function()
    caramba.pair.stop_session()
  end, { desc = 'Stop AI pair programming session' })
  
  vim.api.nvim_create_user_command('AIPairToggle', function()
    caramba.pair.toggle_session()
  end, { desc = 'Toggle AI pair programming session' })
  
  vim.api.nvim_create_user_command('AIPairStatus', function()
    caramba.pair.show_status()
  end, { desc = 'Show AI pair programming status' })
  
  -- Intelligence commands
  vim.api.nvim_create_user_command('AIIndexProject', function()
    caramba.intelligence.index_project()
  end, { desc = 'Index project for intelligent navigation' })
  
  vim.api.nvim_create_user_command('AIFindDefinition', function()
    caramba.intelligence.find_definition()
  end, { desc = 'Find symbol definition' })
  
  vim.api.nvim_create_user_command('AIFindReferences', function()
    caramba.intelligence.find_references()
  end, { desc = 'Find symbol references' })
  
  vim.api.nvim_create_user_command('AIFindRelated', function()
    caramba.intelligence.find_related()
  end, { desc = 'Find related code' })
  
  vim.api.nvim_create_user_command('AICallHierarchy', function()
    caramba.intelligence.show_call_hierarchy()
  end, { desc = 'Show call hierarchy' })
  
  vim.api.nvim_create_user_command('AIFindSimilar', function()
    caramba.intelligence.find_similar_functions()
  end, { desc = 'Find similar functions' })
  
  vim.api.nvim_create_user_command('AIAnalyzeDependencies', function()
    caramba.intelligence.analyze_dependencies()
  end, { desc = 'Analyze module dependencies' })
  
  -- AST transformation commands
  vim.api.nvim_create_user_command('AITransform', function()
    caramba.ast_transform.transform_code()
  end, { desc = 'Transform code using AST' })
  
  vim.api.nvim_create_user_command('AITransformCallback', function()
    caramba.ast_transform.transform_callbacks_to_async()
  end, { desc = 'Transform callbacks to async/await' })
  
  vim.api.nvim_create_user_command('AITransformClass', function()
    caramba.ast_transform.transform_class_to_hooks()
  end, { desc = 'Transform class components to hooks' })
  
  vim.api.nvim_create_user_command('AITransformImports', function()
    caramba.ast_transform.transform_commonjs_to_esm()
  end, { desc = 'Transform CommonJS to ESM' })
  
  vim.api.nvim_create_user_command('AITransformPython', function()
    caramba.ast_transform.transform_python2_to_3()
  end, { desc = 'Transform Python 2 to Python 3' })
  
  vim.api.nvim_create_user_command('AIMergeConflict', function()
    caramba.ast_transform.semantic_merge()
  end, { desc = 'Semantic merge conflict resolution' })
  
  vim.api.nvim_create_user_command('AIRenameAcrossLanguages', function()
    caramba.ast_transform.rename_across_languages()
  end, { desc = 'Rename symbol across different languages' })
end

-- Show results in a floating window
function M._show_result_window(content, title)
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  
  -- Detect filetype for syntax highlighting
  if content:match("```") then
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  end
  
  -- Calculate window size
  local width = math.min(80, math.floor(vim.o.columns * 0.8))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))
  
  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })
  
  -- Set up keymaps
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { silent = true })
end

-- Show search results in quickfix
function M._show_search_results(results, title)
  if #results == 0 then
    vim.notify("No results found", vim.log.levels.INFO)
    return
  end
  
  local qf_items = {}
  for _, result in ipairs(results) do
    table.insert(qf_items, {
      filename = result.filepath,
      lnum = result.range.start_row + 1,
      col = result.range.start_col + 1,
      text = string.format("[%s] %s", result.type, result.name or ""),
    })
  end
  
  vim.fn.setqflist(qf_items)
  vim.fn.setqflist({}, "a", { title = title })
  vim.cmd("copen")
end

-- Jump to a location
function M._jump_to_location(location)
  vim.cmd("edit " .. location.filepath)
  vim.api.nvim_win_set_cursor(0, {
    location.range.start_row + 1,
    location.range.start_col
  })
end

-- Helper function for search
function M._do_search(query)
  local search = require("caramba.search")
  local config = require("caramba.config")
  
  vim.notify("AI: Searching for: " .. query, vim.log.levels.INFO)
  
  local results
  if config.get().search.use_embeddings then
    results = search.semantic_search(query)
  else
    results = search.keyword_search(query)
  end
  
  M._show_search_results(results, query)
end

return M 