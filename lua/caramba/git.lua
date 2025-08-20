-- Smart Git Integration
-- AI-powered version control with semantic understanding

local M = {}

local llm = require('caramba.llm')
local ast_transform = require('caramba.ast_transform')

-- Git operations
M.operations = {}

-- Generate semantic commit message
M.generate_commit_message = function(opts)
  opts = opts or {}

  -- Get staged changes
  local diff = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"git", "diff", "--cached"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then diff = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end
  if diff == "" then
    vim.notify("No staged changes found", vim.log.levels.WARN)
    return
  end

  -- Analyze changes
  local prompt = [[
Analyze this git diff and generate a conventional commit message.

Rules:
1. Use conventional commit format: type(scope): description
2. Types: feat, fix, docs, style, refactor, test, chore, perf
3. Keep the first line under 72 characters
4. Add body if changes are complex (blank line, then details)
5. Be specific about what changed and why

Diff:
]] .. diff .. [[

Generate only the commit message, nothing else.
]]

  llm.request(prompt, { temperature = 1 }, function(response)
    if response then
      vim.schedule(function()
        -- If in git commit buffer, insert message
        if vim.bo.filetype == "gitcommit" then
          local lines = vim.split(response, '\n')
          vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
        else
          -- Show in a centered window
          local ui = require('caramba.ui')
          local lines = vim.split(response, '\n')
          local buf, win = ui.show_lines_centered(lines, { title = ' Generated Commit Message ', filetype = 'markdown' })
          vim.keymap.set('n', '<CR>', function()
            if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
            vim.fn.setreg('+', response)
            vim.notify("Commit message copied to clipboard", vim.log.levels.INFO)
          end, { buffer = buf, desc = 'Copy commit message' })
        end
      end)
    end
  end)
end

-- Semantic merge conflict resolution
M.resolve_conflict = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Find conflict markers
  local conflicts = M._find_conflicts(lines)

  if #conflicts == 0 then
    vim.notify("No merge conflicts found in buffer", vim.log.levels.INFO)
    return
  end

  -- Process each conflict
  for _, conflict in ipairs(conflicts) do
    M._resolve_single_conflict(bufnr, conflict)
  end
end

-- Find conflict markers in buffer
M._find_conflicts = function(lines)
  local conflicts = {}
  local current_conflict = nil

  for i, line in ipairs(lines) do
    if line:match("^<<<<<<< ") then
      current_conflict = {
        start = i,
        ours_start = i + 1,
        marker = line,
      }
    elseif line:match("^=======$") and current_conflict then
      current_conflict.ours_end = i - 1
      current_conflict.theirs_start = i + 1
    elseif line:match("^>>>>>>> ") and current_conflict then
      current_conflict.theirs_end = i - 1
      current_conflict.end_line = i
      table.insert(conflicts, current_conflict)
      current_conflict = nil
    end
  end

  return conflicts
end

-- Resolve a single conflict
M._resolve_single_conflict = function(bufnr, conflict)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Extract conflict sections
  local ours = {}
  for i = conflict.ours_start, conflict.ours_end do
    table.insert(ours, lines[i])
  end

  local theirs = {}
  for i = conflict.theirs_start, conflict.theirs_end do
    table.insert(theirs, lines[i])
  end

  -- Get base version if available (3-way merge)
  local base = M._get_base_version(conflict.marker)

  -- Use semantic merge
  ast_transform.semantic_merge_async(
    base or "",
    table.concat(ours, '\n'),
    table.concat(theirs, '\n'),
    function(merged)
      if merged then
        M._preview_resolution(bufnr, conflict, merged)
      else
        vim.notify("Semantic merge failed", vim.log.levels.ERROR)
      end
    end
  )
end

-- Get base version from conflict marker
M._get_base_version = function(marker)
  -- Try to extract commit info from marker
  local commit = marker:match("<<<<<<< ([^%s]+)")
  if commit and commit ~= "HEAD" then
    -- Try to get the merge base
    local base_commit = ""
    do
      local co = coroutine.running(); local done = false
      vim.fn.jobstart({"sh", "-c", "git merge-base HEAD " .. commit}, {
        stdout_buffered = true,
        on_stdout = function(_, data, _)
          if type(data) == 'table' then base_commit = table.concat(data, "\n") end
        end,
        on_exit = function() done = true; if co then coroutine.resume(co) end end,
      })
      if co then coroutine.yield() end
    end
    if base_commit ~= "" then
      -- Get the file content at base
      -- This is simplified - would need file path
      return nil
    end
  end
  return nil
end

-- Preview conflict resolution
M._preview_resolution = function(bufnr, conflict, resolution)
  -- Show before/after
  local preview_lines = {
    "# Conflict Resolution Preview",
    "",
    "## Original Conflict:",
    "```",
  }

  -- Add original conflict
  local lines = vim.api.nvim_buf_get_lines(bufnr, conflict.start - 1, conflict.end_line, false)
  vim.list_extend(preview_lines, lines)

  table.insert(preview_lines, "```")
  table.insert(preview_lines, "")
  table.insert(preview_lines, "## Semantic Resolution:")
  table.insert(preview_lines, "```")
  vim.list_extend(preview_lines, vim.split(resolution, '\n'))
  table.insert(preview_lines, "```")
  table.insert(preview_lines, "")
  table.insert(preview_lines, "Press 'a' to apply resolution, 'q' to close")

  local ui = require('caramba.ui')
  local preview_buf, win = ui.show_lines_centered(preview_lines, { title = ' Conflict Resolution Preview ', filetype = 'markdown' })

  -- Add apply command
  vim.keymap.set('n', 'a', function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    -- Replace conflict with resolution
    local resolution_lines = vim.split(resolution, '\n')
    vim.api.nvim_buf_set_lines(bufnr, conflict.start - 1, conflict.end_line, false, resolution_lines)
    vim.notify("Conflict resolved", vim.log.levels.INFO)
  end, { buffer = preview_buf, desc = "Apply resolution" })

  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, { buffer = preview_buf, desc = "Close" })
end

-- Generate PR description
M.generate_pr_description = function()
  -- Get branch diff
  local base_branch = ""; local current_branch = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"sh", "-c", "git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then base_branch = (table.concat(data, "\n") or ''):gsub('\n','') end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"git", "branch", "--show-current"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then current_branch = (table.concat(data, "\n") or ''):gsub('\n','') end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end

  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to get branch information", vim.log.levels.ERROR)
    return
  end

  -- Get commits
  local commits = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"sh", "-c", "git log --oneline " .. base_branch .. ".." .. current_branch}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then commits = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end

  -- Get diff summary
  local diff_stat = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"sh", "-c", "git diff --stat " .. base_branch .. ".." .. current_branch}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then diff_stat = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end

  -- Get detailed diff for context
  local diff = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"sh", "-c", "git diff " .. base_branch .. ".." .. current_branch}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then diff = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end

  local prompt = string.format([[
Generate a comprehensive pull request description based on these changes:

Branch: %s -> %s

Commits:
%s

Changes Summary:
%s

Generate a PR description with:
1. Title (clear and descriptive)
2. Summary (what and why)
3. Changes Made (bullet points)
4. Testing (what to test)
5. Screenshots (placeholder if UI changes)
6. Related Issues (if mentioned in commits)

Be specific and helpful for reviewers.
]], current_branch, base_branch, commits, diff_stat)

  llm.request(prompt, { temperature = 1 }, function(response)
    if response then
      vim.schedule(function()
        local ui = require('caramba.ui')
        local lines = vim.split(response, '\n')
        local buf, win = ui.show_lines_centered(lines, { title = ' Generated PR Description ', filetype = 'markdown' })
        vim.keymap.set('n', 'y', function()
          if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
          local content = table.concat(lines, '\n')
          vim.fn.setreg('+', content)
          vim.notify("PR description copied to clipboard", vim.log.levels.INFO)
        end, { buffer = buf, desc = 'Copy PR description' })
        vim.keymap.set('n', 'q', function()
          if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        end, { buffer = buf, desc = 'Close' })
      end)
    end
  end)
end

-- Suggest branch name
M.suggest_branch_name = function()
  -- Get current changes
  local status = ""; local diff = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"git", "status", "--porcelain"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then status = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"git", "diff"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then diff = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end

  local prompt = [[
Based on these changes, suggest a git branch name:

Status:
]] .. status .. [[

Changes preview:
]] .. vim.fn.strpart(diff, 0, 1000) .. [[

Rules for branch naming:
1. Use kebab-case
2. Start with type: feature/, fix/, chore/, docs/
3. Be descriptive but concise
4. Include ticket number if found in changes (e.g., JIRA-123)

Suggest 3 branch names, one per line.
]]

  llm.request(prompt, { temperature = 0.5 }, function(response)
    if response then
      vim.schedule(function()
        local names = vim.split(response, '\n')

        -- Filter empty lines
        local filtered = {}
        for _, name in ipairs(names) do
          if name ~= "" then
            table.insert(filtered, name)
          end
        end

        -- Let user choose
        vim.ui.select(filtered, {
          prompt = "Select branch name:",
        }, function(choice)
          if choice then
            -- Create branch
            local ok_checkout = false
            local co = coroutine.running(); local done = false
            vim.fn.jobstart({"git", "checkout", "-b", choice}, {
              on_exit = function(_, code, _)
                ok_checkout = (code == 0)
                done = true
                if co then coroutine.resume(co) end
              end,
            })
            if co then coroutine.yield() end
            if ok_checkout then
              vim.notify("Created branch: " .. choice, vim.log.levels.INFO)
            else
              vim.notify("Failed to create branch: " .. choice, vim.log.levels.ERROR)
            end
          end
        end)
      end)
    end
  end)
end

-- Smart rebase helper
M.interactive_rebase_helper = function()
  -- Check if in rebase
  if vim.fn.isdirectory(".git/rebase-merge") == 0 then
    vim.notify("Not in an interactive rebase", vim.log.levels.WARN)
    return
  end

  -- Get rebase todo
  local todo_file = ".git/rebase-merge/git-rebase-todo"
  if vim.fn.filereadable(todo_file) == 0 then
    return
  end

  -- Analyze commits
  local lines = vim.fn.readfile(todo_file)
  local commits = {}

  for _, line in ipairs(lines) do
    local action, hash, message = line:match("^(%w+)%s+(%w+)%s+(.+)")
    if action and hash then
      table.insert(commits, {
        action = action,
        hash = hash,
        message = message,
        line = line,
      })
    end
  end

  -- Suggest optimizations
  local suggestions = M._analyze_rebase_commits(commits)

  if #suggestions > 0 then
    M._show_rebase_suggestions(suggestions)
  end
end

-- Analyze commits for rebase optimization
M._analyze_rebase_commits = function(commits)
  local suggestions = {}

  -- Look for fixup candidates
  for i, commit in ipairs(commits) do
    if commit.message:match("^fix") or commit.message:match("^fixup") then
      -- Find related commit
      for j = i - 1, 1, -1 do
        if commits[j].message:match(commit.message:match("fix%s+(.+)")) then
          table.insert(suggestions, {
            type = "fixup",
            commit = commit,
            target = commits[j],
            reason = "Appears to be fixing " .. commits[j].message,
          })
          break
        end
      end
    end
  end

  -- Look for squash candidates
  local prev_feature = nil
  for _, commit in ipairs(commits) do
    if commit.message:match("^WIP") or commit.message:match("^wip") then
      table.insert(suggestions, {
        type = "squash",
        commit = commit,
        reason = "WIP commit should be squashed",
      })
    end
  end

  return suggestions
end

-- Show rebase suggestions
M._show_rebase_suggestions = function(suggestions)
  local buf = vim.api.nvim_create_buf(false, true)

  local lines = {
    "# Rebase Optimization Suggestions",
    "",
  }

  for _, suggestion in ipairs(suggestions) do
    table.insert(lines, string.format("## %s: %s", suggestion.type, suggestion.commit.message))
    table.insert(lines, "Reason: " .. suggestion.reason)

    if suggestion.type == "fixup" and suggestion.target then
      table.insert(lines, "Target: " .. suggestion.target.message)
      table.insert(lines, "Suggested action: `fixup " .. suggestion.commit.hash .. "`")
    elseif suggestion.type == "squash" then
      table.insert(lines, "Suggested action: `squash " .. suggestion.commit.hash .. "`")
    end

    table.insert(lines, "")
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

  vim.cmd('split')
  vim.api.nvim_set_current_buf(buf)
end

-- Review commit before pushing
M.pre_push_review = function()
  -- Get unpushed commits
  local remote = ""; local branch = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"git", "remote"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then remote = (table.concat(data, "\n") or ''):gsub('\n','') end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"git", "branch", "--show-current"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then branch = (table.concat(data, "\n") or ''):gsub('\n','') end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end
  local commits = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"sh", "-c", "git log --oneline " .. remote .. "/" .. branch .. "..HEAD"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then commits = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end

  if commits == "" then
    vim.notify("No unpushed commits", vim.log.levels.INFO)
    return
  end

  -- Get full diff
  local diff = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"sh", "-c", "git diff " .. remote .. "/" .. branch .. "..HEAD"}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then diff = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end

  local prompt = [[
Review these commits before pushing:

Commits:
]] .. commits .. [[

Check for:
1. Commit message quality
2. Code quality issues
3. Potential bugs
4. Security concerns
5. Performance impacts

Provide a brief review with any concerns or suggestions.
]]

  llm.request(prompt, { temperature = 0.2 }, function(response)
    if response then
      vim.schedule(function()
        local buf = vim.api.nvim_create_buf(false, true)

        local lines = {
          "# Pre-Push Review",
          "",
          "## Commits to Push:",
          "```",
        }

        vim.list_extend(lines, vim.split(commits, '\n'))
        table.insert(lines, "```")
        table.insert(lines, "")
        table.insert(lines, "## AI Review:")
        vim.list_extend(lines, vim.split(response, '\n'))

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

        vim.cmd('split')
        vim.api.nvim_set_current_buf(buf)

        -- Add push command
        vim.keymap.set('n', 'p', function()
          vim.cmd('close')
          local push_ok = false
          local co = coroutine.running(); local done = false
          vim.fn.jobstart({"git", "push"}, {
            on_exit = function(_, code, _)
              push_ok = (code == 0)
              done = true
              if co then coroutine.resume(co) end
            end,
          })
          if co then coroutine.yield() end
          if push_ok then
            vim.notify("Pushed successfully", vim.log.levels.INFO)
          else
            vim.notify("Push failed", vim.log.levels.ERROR)
          end
        end, { buffer = buf, desc = "Push commits" })
      end)
    end
  end)
end

-- Helper: Build review prompt
M._build_review_prompt = function(params)
  return string.format([[
Review the following %s code with full project context:

Language: %s
%s

%s
%s%s%s%s%s%s%s%s

Code to review (starting at line %d):
```%s
%s
```

Please provide a comprehensive review covering:
1. Code quality and adherence to %s best practices
2. Potential bugs or logic errors
3. Performance implications
4. Security vulnerabilities
5. Integration issues with imported dependencies
6. Suggestions for improvement
7. Consistency with project patterns
8. Test coverage adequacy (if test files found)
9. Documentation completeness

Consider the semantic context and how this code interacts with:
- Imported modules and their APIs
- Related files in the project (especially tests)
- Available symbols and their usage
- Overall project architecture
- Recent changes and git history

Provide specific line references and actionable suggestions. If tests exist, comment on test coverage gaps.
]], params.language, params.language, params.review_type,
    table.concat(params.context_sections, "\n"),
    params.semantic_context,
    params.related_files,
    table.concat(params.related_content, "\n"),
    params.references,
    params.conventions,
    params.test_framework and ("\nTest Framework: " .. params.test_framework) or "",
    params.git_context,
    params.documentation and ("\n## Existing Documentation:\n" .. params.documentation) or "",
    params.start_line,
    params.language,
    params.code_to_review,
    params.language)
end

-- Review current code for quality, bugs, and improvements
M.review_code = function()
  local utils = require("caramba.utils")
  local context = require("caramba.context")
  local llm = require("caramba.llm")
  local intelligence = require("caramba.intelligence")

  -- Get code to review
  local mode = vim.fn.mode()
  local code_to_review
  local review_type
  local start_line = 1

  if mode == "v" or mode == "V" then
    -- Visual mode: review selection
    code_to_review = utils.get_visual_selection()
    review_type = "Selected code"
    -- Get visual selection line numbers
    local vstart = vim.fn.getpos("'<")
    start_line = vstart[2]
  else
    -- Normal mode: review current file
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    code_to_review = table.concat(lines, '\n')
    review_type = "File: " .. vim.fn.expand('%:t')
  end

  if not code_to_review or code_to_review == "" then
    vim.notify("No code to review", vim.log.levels.WARN)
    return
  end

  -- Collect comprehensive context
  local ctx = context.collect()
  local language = ctx and ctx.language or vim.bo.filetype

  -- Build context sections
  local context_sections = {}

  -- Add project structure
  if ctx and ctx.project_root then
    table.insert(context_sections, "Project root: " .. ctx.project_root)
  end

  -- Add imports/dependencies context
  if ctx and ctx.imports then
    local imports_str = "## Imports and Dependencies:\n"
    for _, import in ipairs(ctx.imports) do
      imports_str = imports_str .. "- " .. import .. "\n"
    end
    table.insert(context_sections, imports_str)
  end

  -- Get semantic context using intelligence module
  local semantic_context = ""
  if intelligence and intelligence.get_semantic_context then
    -- Get context for the current file
    local file_path = vim.fn.expand('%:p')
    local sem_ctx = intelligence.get_semantic_context(file_path, code_to_review)
    if sem_ctx then
      semantic_context = "\n## Semantic Context:\n" .. sem_ctx
    end
  end

  -- Get related files context
  local related_files = ""
  local related_content = {}
  if ctx and ctx.related_files then
    related_files = "\n## Related Files:\n"
    for _, file in ipairs(ctx.related_files) do
      related_files = related_files .. "- " .. file .. "\n"
    end
  else
    -- Try to find related files based on naming patterns
    local current_file = vim.fn.expand('%:t:r')
    local current_ext = vim.fn.expand('%:e')
    local current_dir = vim.fn.expand('%:h')

    -- Language-specific test file patterns
    local test_patterns_by_lang = {
      javascript = {
        current_file .. "_test." .. current_ext,
        current_file .. ".test." .. current_ext,
        current_file .. "_spec." .. current_ext,
        current_file .. ".spec." .. current_ext,
        "test_" .. current_file .. "." .. current_ext,
        "__tests__/" .. current_file .. ".test." .. current_ext,
      },
      typescript = {
        current_file .. "_test." .. current_ext,
        current_file .. ".test." .. current_ext,
        current_file .. "_spec." .. current_ext,
        current_file .. ".spec." .. current_ext,
        "test_" .. current_file .. "." .. current_ext,
        "__tests__/" .. current_file .. ".test." .. current_ext,
        current_file .. ".d.ts", -- TypeScript definitions
      },
      python = {
        "test_" .. current_file .. ".py",
        current_file .. "_test.py",
        "tests/test_" .. current_file .. ".py",
      },
      ruby = {
        current_file .. "_spec.rb",
        "spec/" .. current_file .. "_spec.rb",
      },
      lua = {
        current_file .. "_spec.lua",
        "spec/" .. current_file .. "_spec.lua",
        current_file .. "_test.lua",
        "test/" .. current_file .. "_test.lua",
      },
      go = {
        current_file .. "_test.go",
      },
      rust = {
        "tests/" .. current_file .. ".rs",
      },
    }

    -- Get patterns for current language or fallback to JavaScript patterns
    local patterns = test_patterns_by_lang[language] or test_patterns_by_lang.javascript or {}

    -- Add TypeScript definition file for TS/JS files
    if language == "typescript" or language == "javascript" then
      if language == "javascript" then
        table.insert(patterns, current_file .. ".d.ts")
      end
    end

    local found_related = false
    local related_files_list = {}

    for _, pattern in ipairs(patterns) do
      local full_path = current_dir .. "/" .. pattern
      if vim.fn.filereadable(full_path) == 1 then
        found_related = true
        table.insert(related_files_list, "- " .. pattern .. " (test file)")

        -- Read first few lines to understand test structure
        local test_lines = vim.fn.readfile(full_path)
        if #test_lines > 20 then
          local truncated = {}
          for i = 1, 20 do
            truncated[i] = test_lines[i]
          end
          test_lines = truncated
        end
        if #test_lines > 0 then
          table.insert(related_content, "\nTest file structure (" .. pattern .. "):")
          table.insert(related_content, "```")
          for i, line in ipairs(test_lines) do
            if i <= 10 and (line:match("describe%s*%(") or line:match("test%s*%(") or line:match("it%s*%(")) then
              table.insert(related_content, line)
            end
          end
          table.insert(related_content, "```")
        end
      end
    end

    if found_related then
      related_files = "\n## Potentially Related Files:\n" .. table.concat(related_files_list, "\n")
    end
  end

  -- Get function/class definitions that are referenced
  local references = ""
  if ctx and ctx.symbols then
    references = "\n## Available Symbols in Scope:\n"
    for _, symbol in ipairs(ctx.symbols) do
      if symbol.kind == "function" or symbol.kind == "class" then
        references = references .. string.format("- %s %s\n", symbol.kind, symbol.name)
      end
    end
  end

  -- Detect project conventions and patterns
  local conventions = ""
  local project_root = ctx and ctx.project_root or vim.fn.getcwd()

  -- Check for configuration files that indicate conventions
  local config_files = {
    { file = ".eslintrc", type = "ESLint configuration" },
    { file = ".eslintrc.js", type = "ESLint configuration" },
    { file = ".eslintrc.json", type = "ESLint configuration" },
    { file = ".prettierrc", type = "Prettier configuration" },
    { file = "tsconfig.json", type = "TypeScript configuration" },
    { file = "jest.config.js", type = "Jest test configuration" },
    { file = ".rubocop.yml", type = "RuboCop configuration" },
    { file = "pyproject.toml", type = "Python project configuration" },
    { file = ".flake8", type = "Flake8 configuration" },
  }

  local found_configs = {}
  for _, config in ipairs(config_files) do
    local config_path = project_root .. "/" .. config.file
    if vim.fn.filereadable(config_path) == 1 then
      table.insert(found_configs, config.type)
    end
  end

  if #found_configs > 0 then
    conventions = "\n## Project Configuration:\n"
    for _, config in ipairs(found_configs) do
      conventions = conventions .. "- " .. config .. " detected\n"
    end
  end

  -- Get git context if available
  local git_context = ""
  local file_path_escaped = vim.fn.shellescape(vim.fn.expand('%:p'))
  local git_status = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"sh", "-c", "git status --porcelain " .. file_path_escaped}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then git_status = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end
  if git_status ~= "" then
    if git_status ~= "" then
      git_context = "\n## Git Status:\nFile has uncommitted changes"
    end
  else
    -- Git not available or file not in repository
    git_context = ""
  end

  -- Check recent commits affecting this file
  local recent_commits = ""
  do
    local co = coroutine.running(); local done = false
    vim.fn.jobstart({"sh", "-c", "git log -3 --oneline " .. file_path_escaped}, {
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if type(data) == 'table' then recent_commits = table.concat(data, "\n") end
      end,
      on_exit = function() done = true; if co then coroutine.resume(co) end end,
    })
    if co then coroutine.yield() end
  end
  if recent_commits ~= "" then
    if recent_commits ~= "" then
      git_context = git_context .. "\n\n## Recent commits:\n" .. recent_commits
    end
  end

  -- Build comprehensive prompt
  local prompt = M._build_review_prompt({
    language = language,
    review_type = review_type,
    context_sections = context_sections,
    semantic_context = semantic_context,
    related_files = related_files,
    related_content = related_content,
    references = references,
    conventions = conventions,
    test_framework = ctx and ctx.test_framework,
    git_context = git_context,
    documentation = ctx and ctx.documentation,
    start_line = start_line,
    code_to_review = code_to_review,
  })

  vim.notify("AI: Analyzing code with full context...", vim.log.levels.INFO)

  llm.request(prompt, { temperature = 0.2 }, function(response)
    if response then
      vim.schedule(function()
        -- Show review in a buffer
        local buf = vim.api.nvim_create_buf(false, true)

        local header = {
          "# Code Review with Context",
          "",
          "**Reviewed:** " .. review_type,
          "**Language:** " .. language,
          "**Date:** " .. os.date("%Y-%m-%d %H:%M"),
        }

        -- Add context summary to header
        if ctx and ctx.project_root then
          table.insert(header, "**Project:** " .. vim.fn.fnamemodify(ctx.project_root, ':t'))
        end
        if ctx and ctx.imports and #ctx.imports > 0 then
          table.insert(header, "**Dependencies:** " .. #ctx.imports .. " imports analyzed")
        end

        table.insert(header, "")
        table.insert(header, "---")
        table.insert(header, "")

        local lines = {}
        vim.list_extend(lines, header)
        vim.list_extend(lines, vim.split(response, '\n'))

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

        -- Add keybinding hint at the top
        local hint_lines = {"-- Press <leader>gl on a line number to jump to it --", ""}
        vim.api.nvim_buf_set_lines(buf, 0, 0, false, hint_lines)

        vim.api.nvim_buf_set_option(buf, 'modifiable', false)

        -- Open in a new split
        vim.cmd('vsplit')
        vim.api.nvim_set_current_buf(buf)

        -- Add keymaps
        vim.keymap.set('n', 'q', ':close<CR>', { buffer = buf, desc = "Close review" })
        vim.keymap.set('n', 'y', function()
          local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
          vim.fn.setreg('+', content)
          vim.notify("Review copied to clipboard", vim.log.levels.INFO)
        end, { buffer = buf, desc = "Copy review to clipboard" })

        -- Add keymap to jump to specific line mentioned in review
        -- Use <leader>gl (go to line) to avoid conflicts with built-in gd
        vim.keymap.set('n', '<leader>gl', function()
          local line = vim.fn.getline('.')
          local line_num = line:match("line (%d+)") or line:match("Line (%d+)")
          if line_num then
            vim.cmd('wincmd p') -- Go to previous window
            vim.cmd(':' .. line_num)
            vim.cmd('normal! zz') -- Center the line
          end
        end, { buffer = buf, desc = "Go to line mentioned in review" })



        vim.notify("AI: Context-aware code review complete", vim.log.levels.INFO)
      end)
    else
      vim.notify("AI: Failed to generate code review", vim.log.levels.ERROR)
    end
  end)
end

-- Setup commands for this module
function M.setup_commands()
  local commands = require('caramba.core.commands')

  -- Git commit message generation
  commands.register('CommitMessage', M.generate_commit_message, {
    desc = 'Generate semantic commit message from staged changes',
  })

  -- Merge conflict resolution
  commands.register('ResolveConflict', M.resolve_conflict, {
    desc = 'Resolve merge conflicts using semantic understanding',
  })

  -- PR description generation
  commands.register('GeneratePR', M.generate_pr_description, {
    desc = 'Generate comprehensive pull request description',
  })

  -- Branch naming
  commands.register('SuggestBranch', M.suggest_branch_name, {
    desc = 'Suggest branch name based on changes',
  })

  -- Interactive rebase helper
  commands.register('RebaseHelper', M.interactive_rebase_helper, {
    desc = 'Analyze and optimize interactive rebase',
  })

  -- Pre-push review
  commands.register('PrePushReview', M.pre_push_review, {
    desc = 'Review commits before pushing',
  })

  -- Review current code for quality, bugs, and improvements
  commands.register('ReviewCode', M.review_code, {
    desc = 'Review current code for quality, bugs, and improvements',
  })
end

return M