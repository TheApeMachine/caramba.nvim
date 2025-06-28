-- Smart Git Integration
-- AI-powered version control with semantic understanding

local M = {}

local llm = require('ai.llm')
local ast_transform = require('ai.ast_transform')

-- Git operations
M.operations = {}

-- Generate semantic commit message
M.generate_commit_message = function(opts)
  opts = opts or {}
  
  -- Get staged changes
  local diff = vim.fn.system("git diff --cached")
  if vim.v.shell_error ~= 0 or diff == "" then
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

  llm.request(prompt, { temperature = 0.3 }, function(response)
    if response then
      vim.schedule(function()
        -- If in git commit buffer, insert message
        if vim.bo.filetype == "gitcommit" then
          local lines = vim.split(response, '\n')
          vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
        else
          -- Show in a buffer
          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, '\n'))
          
          vim.cmd('split')
          vim.api.nvim_set_current_buf(buf)
          
          -- Add command to use this message
          vim.keymap.set('n', '<CR>', function()
            vim.fn.setreg('+', response)
            vim.notify("Commit message copied to clipboard", vim.log.levels.INFO)
          end, { buffer = buf, desc = "Copy commit message" })
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
  local merged = ast_transform.semantic_merge(
    base or "",
    table.concat(ours, '\n'),
    table.concat(theirs, '\n')
  )
  
  if merged then
    -- Show preview
    M._preview_resolution(bufnr, conflict, merged)
  end
end

-- Get base version from conflict marker
M._get_base_version = function(marker)
  -- Try to extract commit info from marker
  local commit = marker:match("<<<<<<< ([^%s]+)")
  if commit and commit ~= "HEAD" then
    -- Try to get the merge base
    local base_commit = vim.fn.system("git merge-base HEAD " .. commit)
    if vim.v.shell_error == 0 then
      -- Get the file content at base
      -- This is simplified - would need file path
      return nil
    end
  end
  return nil
end

-- Preview conflict resolution
M._preview_resolution = function(bufnr, conflict, resolution)
  -- Create preview buffer
  local preview_buf = vim.api.nvim_create_buf(false, true)
  
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
  
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, preview_lines)
  vim.api.nvim_buf_set_option(preview_buf, 'filetype', 'markdown')
  
  -- Show in split
  vim.cmd('split')
  vim.api.nvim_set_current_buf(preview_buf)
  
  -- Add apply command
  vim.keymap.set('n', 'a', function()
    -- Replace conflict with resolution
    local resolution_lines = vim.split(resolution, '\n')
    vim.api.nvim_buf_set_lines(bufnr, conflict.start - 1, conflict.end_line, false, resolution_lines)
    vim.cmd('close')
    vim.notify("Conflict resolved", vim.log.levels.INFO)
  end, { buffer = preview_buf, desc = "Apply resolution" })
end

-- Generate PR description
M.generate_pr_description = function()
  -- Get branch diff
  local base_branch = vim.fn.system("git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'"):gsub('\n', '')
  local current_branch = vim.fn.system("git branch --show-current"):gsub('\n', '')
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to get branch information", vim.log.levels.ERROR)
    return
  end
  
  -- Get commits
  local commits = vim.fn.system("git log --oneline " .. base_branch .. ".." .. current_branch)
  
  -- Get diff summary
  local diff_stat = vim.fn.system("git diff --stat " .. base_branch .. ".." .. current_branch)
  
  -- Get detailed diff for context
  local diff = vim.fn.system("git diff " .. base_branch .. ".." .. current_branch)
  
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

  llm.request(prompt, { temperature = 0.3 }, function(response)
    if response then
      vim.schedule(function()
        -- Show in buffer
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, '\n'))
        vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
        
        vim.cmd('tabnew')
        vim.api.nvim_set_current_buf(buf)
        
        -- Add copy command
        vim.keymap.set('n', 'y', function()
          local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
          vim.fn.setreg('+', content)
          vim.notify("PR description copied to clipboard", vim.log.levels.INFO)
        end, { buffer = buf, desc = "Copy PR description" })
      end)
    end
  end)
end

-- Suggest branch name
M.suggest_branch_name = function()
  -- Get current changes
  local status = vim.fn.system("git status --porcelain")
  local diff = vim.fn.system("git diff")
  
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
            local result = vim.fn.system("git checkout -b " .. choice)
            if vim.v.shell_error == 0 then
              vim.notify("Created branch: " .. choice, vim.log.levels.INFO)
            else
              vim.notify("Failed to create branch: " .. result, vim.log.levels.ERROR)
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
  local remote = vim.fn.system("git remote"):gsub('\n', '')
  local branch = vim.fn.system("git branch --show-current"):gsub('\n', '')
  local commits = vim.fn.system("git log --oneline " .. remote .. "/" .. branch .. "..HEAD")
  
  if commits == "" then
    vim.notify("No unpushed commits", vim.log.levels.INFO)
    return
  end
  
  -- Get full diff
  local diff = vim.fn.system("git diff " .. remote .. "/" .. branch .. "..HEAD")
  
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
          vim.fn.system("git push")
          if vim.v.shell_error == 0 then
            vim.notify("Pushed successfully", vim.log.levels.INFO)
          else
            vim.notify("Push failed", vim.log.levels.ERROR)
          end
        end, { buffer = buf, desc = "Push commits" })
      end)
    end
  end)
end

return M 