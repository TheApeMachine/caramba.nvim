-- Caramba Planning Module - Multi-stage reasoning for better code generation
local M = {}

local config = require("caramba.config")
local llm = require("caramba.llm")
local context = require("caramba.context")
local search = require("caramba.search")

-- Project plan storage (in-memory for now, could persist to file)
M._project_plan = {
  goals = {},
  architecture = {
    project_type = "unknown",
    main_language = "unknown",
    structure = {},
    patterns = {},
    dependencies = {}
  },
  conventions = {
    naming = {},
    formatting = {},
    patterns = {}
  },
  current_tasks = {},
  completed_tasks = {},
  known_issues = {},
  metadata = {
    created_at = os.date("%Y-%m-%d %H:%M:%S"),
    last_updated = os.date("%Y-%m-%d %H:%M:%S"),
    version = "1.0"
  }
}

-- Load project plan from file if exists
function M.load_project_plan()
  local plan_file = vim.fn.getcwd() .. "/.caramba-project-plan.json"
  if vim.fn.filereadable(plan_file) == 1 then
    local ok, content = pcall(vim.fn.readfile, plan_file)
    if ok and content then
      local json_ok, plan = pcall(vim.json.decode, table.concat(content, "\n"))
      if json_ok and type(plan) == "table" then
        M._project_plan = vim.tbl_deep_extend("force", M._project_plan, plan)
        return true
      else
        vim.notify("Caramba Planner: Failed to parse project plan file", vim.log.levels.WARN)
      end
    end
  end
  return false
end

-- Save project plan to file
function M.save_project_plan()
  local plan_file = vim.fn.getcwd() .. "/.caramba-project-plan.json"
  
  -- Update metadata
  M._project_plan.metadata = M._project_plan.metadata or {}
  M._project_plan.metadata.last_updated = os.date("%Y-%m-%d %H:%M:%S")
  
  local ok, content = pcall(vim.json.encode, M._project_plan)
  if ok then
    local write_ok = pcall(vim.fn.writefile, vim.split(content, "\n"), plan_file)
    if not write_ok then
      vim.notify("Caramba Planner: Failed to save project plan", vim.log.levels.ERROR)
    end
  else
    vim.notify("Caramba Planner: Failed to encode project plan", vim.log.levels.ERROR)
  end
end

-- Analyze project structure and conventions
function M.analyze_project_structure(callback)
  local analysis_prompt = {
    {
      role = "system",
      content = [[You are a software architect analyzing a codebase.
Analyze the provided project information and identify key aspects of the project structure, 
patterns, and architecture.]]
    },
    {
      role = "user", 
      content = "Analyze the following project files and structure:\n\n" .. M._get_project_overview()
    }
  }
  
  -- Use structured output with JSON schema for OpenAI
  local opts = { }
  
  if config.get().provider == "openai" then
    opts.response_format = {
      type = "json_schema",
      json_schema = {
        name = "project_analysis",
        strict = true,
        schema = {
          type = "object",
          properties = {
            project_type = { type = "string" },
            main_language = { type = "string" },
            structure = {
              type = "object",
              properties = {
                directories = {
                  type = "array",
                  items = { type = "string" }
                },
                entry_points = {
                  type = "array",
                  items = { type = "string" }
                },
                config_files = {
                  type = "array",
                  items = { type = "string" }
                }
              },
              required = { "directories", "entry_points", "config_files" },
              additionalProperties = false
            },
            patterns = {
              type = "object",
              properties = {
                naming = { type = "string" },
                organization = { type = "string" },
                style = { type = "string" }
              },
              required = { "naming", "organization", "style" },
              additionalProperties = false
            },
            dependencies = {
              type = "object",
              properties = {
                external = {
                  type = "array",
                  items = { type = "string" }
                },
                internal = {
                  type = "array",
                  items = { type = "string" }
                }
              },
              required = { "external", "internal" },
              additionalProperties = false
            },
            notes = { type = "string" }
          },
          required = { "project_type", "main_language", "structure", "patterns", "dependencies", "notes" },
          additionalProperties = false
        }
      }
    }
  else
    -- For non-OpenAI providers, we still need to prompt
    analysis_prompt[1].content = analysis_prompt[1].content .. [[

Return your analysis as a JSON object with this structure:
{
  "project_type": "type of project",
  "main_language": "primary programming language",
  "structure": {
    "directories": ["list", "of", "key", "directories"],
    "entry_points": ["main files or entry points"],
    "config_files": ["configuration files found"]
  },
  "patterns": {
    "naming": "observed naming conventions",
    "organization": "how code is organized",
    "style": "coding style observations"
  },
  "dependencies": {
    "external": ["key external dependencies"],
    "internal": ["internal module structure"]
  },
  "notes": "any other important observations"
}
]]
  end
  
  llm.request(analysis_prompt, opts, callback)
end

-- Get overview of project structure
function M._get_project_overview()
  local overview = {}
  
  -- Get directory structure
  local dirs = vim.fn.systemlist("find . -type d -name '.git' -prune -o -type d -print | head -50")
  table.insert(overview, "Directory Structure:")
  for _, dir in ipairs(dirs) do
    table.insert(overview, dir)
  end
  
  -- Get key files
  table.insert(overview, "\nKey Files:")
  local key_patterns = {
    "README*", "package.json", "Cargo.toml", "go.mod", 
    "requirements.txt", "Gemfile", "*.config.*", "Makefile"
  }
  
  for _, pattern in ipairs(key_patterns) do
    local files = vim.fn.glob(pattern, false, true)
    for _, file in ipairs(files) do
      table.insert(overview, file)
      -- Include first few lines of important files
      if vim.fn.filereadable(file) == 1 then
        local lines = vim.fn.readfile(file, "", 20)
        table.insert(overview, "  Content preview:")
        for i, line in ipairs(lines) do
          if i > 10 then break end
          table.insert(overview, "  " .. line)
        end
      end
    end
  end
  
  return table.concat(overview, "\n")
end

-- Helper function to show questions in a window
M._show_questions_window = function(lines, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  
  local width = 80
  local height = math.min(#lines + 2, 20)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Caramba Questions ',
    title_pos = 'center',
  })
  
  -- Set up keymaps to close window and continue
  local opts = { buffer = buf, nowait = true }
  vim.keymap.set('n', '<CR>', function()
    vim.api.nvim_win_close(win, true)
    if callback then callback() end
  end, opts)
  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(win, true)
    if callback then callback() end
  end, opts)
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
    if callback then callback() end
  end, opts)
end

-- Interactive planning session
function M.interactive_planning_session(task_description, context_info, callback)
  -- Step 1: Create initial plan
  vim.notify("Caramba Planner: Creating initial plan...", vim.log.levels.INFO)
  
  context_info = context_info or context.build_context_string(context.collect())
  
  -- If no context is selected, use the current buffer's content
  if not context_info or context_info:match("^%s*$") then
    vim.schedule(function()
      vim.notify("Caramba Planner: No code selected, using current buffer as context.", vim.log.levels.INFO)
    end)
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    context_info = table.concat(buffer_lines, "\n")
  end
  
  -- Final fallback: if buffer is also empty, then prompt user.
  if not context_info or context_info:match("^%s*$") then
    vim.schedule(function()
      vim.notify("Caramba Planner: Buffer is empty. Please provide a task description.", vim.log.levels.WARN)
      vim.ui.input({
        prompt = "Describe what you want to do: ",
      }, function(input)
        if input and input ~= "" then
          M.interactive_planning_session(input, "", callback)
        else
          if callback then callback(nil, nil, "Planning cancelled.") end
        end
      end)
    end)
    return
  end
  
  M.create_task_plan(task_description, context_info, function(plan_result, plan_err)
    if plan_err then
      vim.schedule(function()
        vim.notify("Failed to create plan: " .. plan_err, vim.log.levels.ERROR)
      end)
      return
    end
    
    -- Parse the plan, with better error handling
    local ok, plan
    if type(plan_result) == "table" then
      plan = plan_result -- Already a table, no need to decode
      ok = true
    elseif type(plan_result) == "string" then
      ok, plan = pcall(vim.json.decode, plan_result)
    else
      ok = false
      plan = "Invalid response type: " .. type(plan_result)
    end
    
    if not ok then
      vim.schedule(function()
        vim.notify("Failed to parse plan: " .. tostring(plan), vim.log.levels.ERROR)
        -- Show the raw response for debugging
        if callback then
          callback(nil, nil, "Failed to parse plan: " .. plan_result)
        else
          M._show_result_window(plan_result, "Raw Plan Response (Failed to Parse)")
        end
      end)
      return
    end
    
    vim.schedule(function()
      -- Step 2: Show plan and questions
      if plan.questions and #plan.questions > 0 then
        -- Show questions in a window first
        local question_lines = {
          "=== Caramba Planning System - Questions ===",
          "",
          "The AI has the following questions about your request:",
          ""
        }
        
        for i, question in ipairs(plan.questions) do
          table.insert(question_lines, string.format("%d. %s", i, question))
        end
        
        table.insert(question_lines, "")
        table.insert(question_lines, "Press any key to continue and provide answers...")
        
        -- Show questions in a window
        M._show_questions_window(question_lines, function()
          -- After user acknowledges, prompt for answers
          vim.ui.input({
            prompt = "Please answer the questions (or press Enter to skip): ",
          }, function(input)
            if input and input ~= "" then
              plan.user_clarifications = input
            end
            M._continue_planning(task_description, plan, callback)
          end)
        end)
      else
        M._continue_planning(task_description, plan, callback)
      end
    end)
  end)
end

-- Continue planning after questions
function M._continue_planning(task_description, plan, callback)
  -- Step 3: Review plan
  vim.notify("Caramba Planner: Reviewing plan...", vim.log.levels.INFO)
  
  M.review_plan(vim.json.encode(plan), task_description, function(review_result, review_err)
    if review_err then
      vim.schedule(function()
        vim.notify("Failed to review plan: " .. review_err, vim.log.levels.ERROR)
        if callback then
          callback(plan, nil, "Failed to review plan")
        else
          -- Show plan anyway
          M._show_plan_window(plan, nil)
        end
      end)
      return
    end
    
    local ok, review = pcall(vim.json.decode, review_result)
    if not ok then
      vim.schedule(function()
        vim.notify("Failed to parse review: " .. tostring(review), vim.log.levels.WARN)
        if callback then
          callback(plan, nil, "Failed to parse review")
        else
          -- Show plan anyway
          M._show_plan_window(plan, nil)
        end
      end)
      return
    end
    
    vim.schedule(function()
      if callback then
        callback(plan, review)
      else
        -- Step 4: Show plan to user
        M._show_plan_window(plan, review)
      end
    end)
  end)
end

-- Create a plan for a specific task (with callback)
function M.create_task_plan(task_description, context_info, callback)
  local planning_prompt = {
    {
      role = "system",
      content = [[You are a senior software engineer creating a detailed implementation plan.
Analyze the task and create a comprehensive plan considering architecture, dependencies, 
and potential issues.]]
    },
    {
      role = "user",
      content = string.format([[
Task: %s

Current Context:
%s

Project Information:
%s

Existing Conventions:
%s
]], task_description, context_info, 
    vim.json.encode(M._project_plan.architecture),
    vim.json.encode(M._project_plan.conventions))
    }
  }
  
  -- Use structured output with JSON schema for OpenAI
  local opts = { }
  
  if config.get().provider == "openai" then
    opts.response_format = {
      type = "json_schema",
      json_schema = {
        name = "implementation_plan",
        strict = true,
        schema = {
          type = "object",
          properties = {
            understanding = { type = "string" },
            affected_components = {
              type = "array",
              items = { type = "string" }
            },
            implementation_steps = {
              type = "array",
              items = {
                type = "object",
                properties = {
                  step = { type = "number" },
                  action = { type = "string" },
                  file = { type = "string" },
                  reason = { type = "string" }
                },
                required = { "step", "action", "file", "reason" },
                additionalProperties = false
              }
            },
            potential_issues = {
              type = "array",
              items = { type = "string" }
            },
            questions = {
              type = "array",
              items = { type = "string" }
            },
            estimated_complexity = {
              type = "string",
              enum = { "low", "medium", "high" }
            }
          },
          required = { 
            "understanding", "affected_components", "implementation_steps",
            "potential_issues", "questions", "estimated_complexity"
          },
          additionalProperties = false
        }
      }
    }
  else
    -- For non-OpenAI providers, add JSON instructions
    planning_prompt[1].content = planning_prompt[1].content .. [[

Return ONLY a valid JSON object with this structure:
{
  "understanding": "Clear description of what needs to be done",
  "affected_components": ["list", "of", "affected", "parts"],
  "implementation_steps": [
    {"step": 1, "action": "...", "file": "...", "reason": "..."}
  ],
  "potential_issues": ["list", "of", "concerns"],
  "questions": ["clarifying", "questions", "if", "any"],
  "estimated_complexity": "low|medium|high"
}
]]
  end
  
  llm.request(planning_prompt, opts, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    
    -- The llm.request now often returns a parsed table directly
    if type(result) == "table" then
      callback(result, nil)
    elseif type(result) == "string" then
      -- Fallback for providers that return a raw string
      local ok, decoded = pcall(vim.json.decode, result)
      if ok then
        callback(decoded, nil)
      else
        callback(nil, "Failed to decode JSON response: " .. result)
      end
    else
      callback(nil, "Invalid response type from LLM: " .. type(result))
    end
  end)
end

-- Review a plan before execution (with callback)
function M.review_plan(plan, task_description, callback)
  local review_prompt = {
    {
      role = "system",
      content = [[You are a technical lead reviewing an implementation plan.
Evaluate the plan for completeness, safety, consistency, efficiency, and edge cases.]]
    },
    {
      role = "user",
      content = string.format([[
Original Task: %s

Proposed Plan:
%s

Known Issues:
%s
]], task_description, plan, vim.json.encode(M._project_plan.known_issues))
    }
  }
  
  -- Use structured output with JSON schema for OpenAI
  local opts = { }
  
  if config.get().provider == "openai" then
    opts.response_format = {
      type = "json_schema",
      json_schema = {
        name = "plan_review",
        strict = true,
        schema = {
          type = "object",
          properties = {
            decision = {
              type = "string",
              enum = { "APPROVE", "REQUEST_CHANGES", "REJECT" }
            },
            feedback = {
              type = "array",
              items = { type = "string" }
            },
            suggestions = {
              type = "array",
              items = { type = "string" }
            },
            risks = {
              type = "array",
              items = { type = "string" }
            }
          },
          required = { "decision", "feedback", "suggestions", "risks" },
          additionalProperties = false
        }
      }
    }
  else
    -- For non-OpenAI providers, add JSON instructions
    review_prompt[1].content = review_prompt[1].content .. [[

Return ONLY a valid JSON object with this structure:
{
  "decision": "APPROVE|REQUEST_CHANGES|REJECT",
  "feedback": ["specific", "feedback", "points"],
  "suggestions": ["improvement", "suggestions"],
  "risks": ["identified", "risks"]
}
]]
  end
  
  llm.request(review_prompt, opts, callback)
end

-- Show result window helper
function M._show_result_window(content, title)
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Format content
  local lines = vim.split(content, "\n")
  
  -- Set content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "json")
  
  -- Create window
  local width = math.min(100, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })
  
  -- Set up close keymap
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, silent = true })
end

-- Show plan in a window
function M._show_plan_window(plan, review)
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Format plan content
  local lines = {
    "=== Caramba Implementation Plan ===",
    "",
    "Understanding: " .. (plan.understanding or ""),
    "",
    "Complexity: " .. (plan.estimated_complexity or "unknown"),
    "",
    "Affected Components:",
  }
  
  for _, component in ipairs(plan.affected_components or {}) do
    table.insert(lines, "  - " .. component)
  end
  
  table.insert(lines, "")
  table.insert(lines, "Implementation Steps:")
  
  for _, step in ipairs(plan.implementation_steps or {}) do
    table.insert(lines, string.format("  %d. %s", step.step, step.action))
    table.insert(lines, string.format("     File: %s", step.file or "N/A"))
    table.insert(lines, string.format("     Reason: %s", step.reason))
    table.insert(lines, "")
  end
  
  if plan.potential_issues and #plan.potential_issues > 0 then
    table.insert(lines, "Potential Issues:")
    for _, issue in ipairs(plan.potential_issues) do
      table.insert(lines, "  ⚠️  " .. issue)
    end
    table.insert(lines, "")
  end
  
  -- Add review feedback
  if review then
    table.insert(lines, "=== Review Decision: " .. (review.decision or "PENDING") .. " ===")
    table.insert(lines, "")
    
    if review.feedback and #review.feedback > 0 then
      table.insert(lines, "Feedback:")
      for _, feedback in ipairs(review.feedback) do
        table.insert(lines, "  • " .. feedback)
      end
      table.insert(lines, "")
    end
    
    if review.risks and #review.risks > 0 then
      table.insert(lines, "Identified Risks:")
      for _, risk in ipairs(review.risks) do
        table.insert(lines, "  ⚠️  " .. risk)
      end
    end
  end
  
  table.insert(lines, "")
  table.insert(lines, "Press 'y' to execute, 'n' to cancel, 'e' to edit task")
  
  -- Set content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  
  -- Create window
  local width = math.min(100, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " Caramba Planning System ",
    title_pos = "center",
  })
  
  -- Store plan for execution
  vim.b[buf].caramba_plan = plan
  vim.b[buf].caramba_review = review
  
  -- Set up keymaps
  local opts = { buffer = buf, silent = true }
  vim.keymap.set("n", "y", function()
    vim.api.nvim_win_close(win, true)
    M.execute_plan(plan)
  end, opts)
  
  vim.keymap.set("n", "n", function()
    vim.api.nvim_win_close(win, true)
    vim.notify("Plan cancelled", vim.log.levels.INFO)
  end, opts)
  
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, opts)
end

-- Get the current plan
M.get_current_plan = function()
  return M._current_plan
end

-- Mark the current plan as complete
M.mark_complete = function()
  if M._current_plan then
    table.insert(M._project_plan.completed_tasks, {
      description = M._current_plan.description or "Implementation task",
      date = os.date("%Y-%m-%d %H:%M:%S"),
      steps = #(M._current_plan.steps or {})
    })
    M._current_plan = nil
    M.save_project_plan()
  end
end

-- Execute a plan
M.execute_plan = function(plan)
  -- Use provided plan or get current plan
  plan = plan or M.get_current_plan()
  
  if not plan or not plan.steps then
    vim.notify("No plan to execute", vim.log.levels.WARN)
    return
  end
  
  vim.notify("Executing plan: " .. (plan.description or "Implementation plan"), vim.log.levels.INFO)
  
  -- Execute steps sequentially to avoid rate limiting
  local execute_step
  local current_step = 1
  
  execute_step = function()
    if current_step > #plan.steps then
      vim.schedule(function()
        vim.notify("Plan execution completed!", vim.log.levels.INFO)
        M.mark_complete()
      end)
      return
    end
    
    local step = plan.steps[current_step]
    vim.schedule(function()
      vim.notify(string.format("Executing step %d/%d: %s", current_step, #plan.steps, step.description), vim.log.levels.INFO)
    end)
    
    -- Add delay between steps to avoid rate limiting
    vim.defer_fn(function()
      local context = require('caramba.context')
      local llm = require('caramba.llm')
      local edit = require('caramba.edit')
      
      -- Build context for this step
      local ctx = context.collect()
      
      local prompt = {
        {
          role = "system",
          content = "You are implementing a specific step from an approved plan. Generate ONLY the code changes needed, no explanations."
        },
        {
          role = "user",
          content = string.format([[
Step %d: %s

Current file: %s
Language: %s

Context:
%s

Please provide the code changes needed for this step.
]], current_step, step.description, vim.fn.expand('%:p'), vim.bo.filetype, context.build_context_string(ctx))
        }
      }
      
      llm.request(prompt, { temperature = 1 }, function(response)
        if response then
          vim.schedule(function()
            -- Apply the changes
            local success = edit.apply_patch(0, response, {
              validate = true,
              preview = false,  -- Don't preview during automated execution
            })
            
            if success then
              vim.notify(string.format("Step %d completed successfully", current_step), vim.log.levels.INFO)
              current_step = current_step + 1
              -- Continue with next step after a delay
              vim.defer_fn(execute_step, 1000)  -- 1 second delay between steps
            else
              vim.notify(string.format("Step %d failed. Stopping execution.", current_step), vim.log.levels.ERROR)
            end
          end)
        else
          vim.schedule(function()
            vim.notify(string.format("Failed to get response for step %d", current_step), vim.log.levels.ERROR)
          end)
        end
      end)
    end, 500)  -- Initial delay before starting
  end
  
  -- Start execution
  execute_step()
end

-- Update project conventions based on observed patterns
function M.learn_from_codebase()
  -- This would analyze recent changes and update conventions
  -- For now, just a placeholder
  vim.notify("Caramba Planner: Learning from codebase patterns...", vim.log.levels.INFO)
end

-- Initialize planner
function M.setup()
  M.load_project_plan()
  
  -- Auto-save plan on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.save_project_plan()
    end,
  })
end

-- Setup commands for this module
function M.setup_commands()
  local commands = require('caramba.core.commands')
  
  -- Main planning command
  commands.register('Plan', function(opts)
    local task = opts.args
    if task == "" then
      vim.ui.input({
        prompt = "What would you like to plan? ",
      }, function(input)
        if input and input ~= "" then
          M.interactive_planning_session(input, nil, nil)
        end
      end)
    else
      M.interactive_planning_session(task, nil, nil)
    end
  end, {
    desc = 'Create an Caramba-powered implementation plan',
    nargs = '?',
  })
  
  -- Analyze project structure
  commands.register('AnalyzeProject', function()
    M.analyze_project_structure(function(analysis, err)
      if err then
        vim.schedule(function()
          vim.notify("Failed to analyze project: " .. tostring(err), vim.log.levels.ERROR)
        end)
        return
      end
      
      if analysis then
        vim.schedule(function()
          M._show_result_window(analysis, "Project Analysis")
        end)
      end
    end)
  end, {
    desc = 'Analyze project structure and architecture',
  })
  
  -- Learn from codebase
  commands.register('LearnFromCodebase', M.learn_from_codebase, {
    desc = 'Learn patterns from successful implementations in codebase',
  })
  
  -- Execute current plan
  commands.register('ExecutePlan', function()
    M.execute_plan()
  end, {
    desc = 'Execute the current implementation plan',
  })
  
  -- Show current plan
  commands.register('ShowPlan', function()
    local plan = M.get_current_plan()
    if plan then
      M._show_plan_window(plan, nil)
    else
      vim.notify("No active plan", vim.log.levels.INFO)
    end
  end, {
    desc = 'Show the current implementation plan',
  })
  
  -- Mark plan as complete
  commands.register('MarkPlanComplete', M.mark_complete, {
    desc = 'Mark the current plan as complete',
  })
end

return M 