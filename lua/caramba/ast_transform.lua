-- AST-Based Code Transformation Module
-- Provides semantic code transformations using Tree-sitter

local M = {}

local ts_utils = require('nvim-treesitter.ts_utils')
local parsers = require('nvim-treesitter.parsers')
local llm = require('caramba.llm')
local utils = require('caramba.utils')

-- Transformation registry
M.transformations = {}

-- Register a transformation
M.register_transformation = function(name, transform_fn)
  M.transformations[name] = transform_fn
end

-- Find nodes matching a query
M.find_nodes = function(bufnr, query_string)
  local parser = parsers.get_parser(bufnr)
  if not parser then return {} end
  
  local tree = parser:parse()[1]
  local root = tree:root()
  
  local lang = parser:lang()
  local query = vim.treesitter.query.parse(lang, query_string)
  
  local matches = {}
  for pattern, match, metadata in query:iter_matches(root, bufnr) do
    for id, node in pairs(match) do
      table.insert(matches, {
        node = node,
        name = query.captures[id],
        metadata = metadata
      })
    end
  end
  
  return matches
end

-- Built-in Transformations

-- Callback to Async/Await (JavaScript/TypeScript)
M.transformations.callback_to_async = {
  name = "callback_to_async",
  languages = {"javascript", "typescript", "javascriptreact", "typescriptreact"},
  
  detect = function(bufnr)
    -- Find callback patterns
    local query = [[
      (call_expression
        arguments: (arguments
          (arrow_function
            parameters: (formal_parameters
              (identifier) @err
              (identifier) @result)
            body: (_) @callback_body) @callback))
    ]]
    
    return M.find_nodes(bufnr, query)
  end,
  
  transform = function(node, bufnr)
    local text = utils.get_node_text(node.node, bufnr)
    
    -- Use AI to transform
    local prompt = string.format([[
Transform this callback-based code to use async/await:

```javascript
%s
```

Rules:
1. Convert the function to async
2. Replace callbacks with await
3. Use try/catch for error handling
4. Preserve the original logic
5. Return the transformed code only
]], text)
    
    return llm.request_sync(prompt, { temperature = 1 })
  end,
}

-- Class to Functional Component (React)
M.transformations.class_to_function = {
  name = "class_to_function",
  languages = {"javascript", "typescript", "javascriptreact", "typescriptreact"},
  
  detect = function(bufnr)
    local query = [[
      (class_declaration
        name: (identifier) @class_name
        superclass: (member_expression
          object: (identifier) @react
          property: (property_identifier) @component)
        body: (class_body) @body)
      (#eq? @react "React")
      (#eq? @component "Component")
    ]]
    
    return M.find_nodes(bufnr, query)
  end,
  
  transform = function(node, bufnr)
    local text = utils.get_node_text(node.node, bufnr)
    
    local prompt = string.format([[
Convert this React class component to a functional component with hooks:

```javascript
%s
```

Rules:
1. Convert to function component
2. Replace state with useState
3. Replace lifecycle methods with useEffect
4. Preserve all functionality
5. Use modern React patterns
6. Return only the transformed code
]], text)
    
    return llm.request_sync(prompt, { temperature = 1 })
  end,
}

-- CommonJS to ES Modules
M.transformations.cjs_to_esm = {
  name = "cjs_to_esm",
  languages = {"javascript", "typescript"},
  
  detect = function(bufnr)
    local require_query = [[(call_expression
      function: (identifier) @require
      (#eq? @require "require"))]]
    
    local export_query = [[(assignment_expression
      left: (member_expression
        object: (identifier) @module
        property: (property_identifier) @exports)
      (#eq? @module "module")
      (#eq? @exports "exports"))]]
    
    local requires = M.find_nodes(bufnr, require_query)
    local exports = M.find_nodes(bufnr, export_query)
    
    return vim.list_extend(requires, exports)
  end,
  
  transform = function(node, bufnr)
    -- Get the entire buffer for context
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, '\n')
    
    local prompt = [[
Convert this CommonJS module to ES modules:

]] .. content .. [[

Rules:
1. Convert require() to import statements
2. Convert module.exports to export statements
3. Handle dynamic requires appropriately
4. Preserve all functionality
5. Use named exports where appropriate
6. Return only the transformed code
]]
    
    return llm.request_sync(prompt, { temperature = 1 })
  end,
}

-- Python 2 to Python 3
M.transformations.py2_to_py3 = {
  name = "py2_to_py3",
  languages = {"python"},
  
  detect = function(bufnr)
    -- Detect Python 2 patterns
    local print_stmt = [[(print_statement) @print]]
    local old_string = [[(string) @str
      (#match? @str "^u['\"]")]]
    
    local prints = M.find_nodes(bufnr, print_stmt)
    local strings = M.find_nodes(bufnr, old_string)
    
    return vim.list_extend(prints, strings)
  end,
  
  transform = function(node, bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, '\n')
    
    local prompt = [[
Convert this Python 2 code to Python 3:

]] .. content .. [[

Changes to make:
1. print statements to print() function
2. unicode strings (u"") to regular strings
3. xrange to range
4. dict.iteritems() to dict.items()
5. raw_input to input
6. exception syntax
7. division behavior
8. Return only the transformed code
]]
    
    return llm.request_sync(prompt, { temperature = 1 })
  end,
}

-- Apply transformation to buffer
M.apply_transformation = function(transform_name, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  local transform = M.transformations[transform_name]
  if not transform then
    vim.notify("Unknown transformation: " .. transform_name, vim.log.levels.ERROR)
    return
  end
  
  -- Check language compatibility
  local parser = parsers.get_parser(bufnr)
  if not parser then
    vim.notify("No parser available for buffer", vim.log.levels.ERROR)
    return
  end
  
  local lang = parser:lang()
  if transform.languages and not vim.tbl_contains(transform.languages, lang) then
    vim.notify("Transformation not available for " .. lang, vim.log.levels.ERROR)
    return
  end
  
  -- Detect applicable nodes
  local nodes = transform.detect(bufnr)
  if #nodes == 0 then
    vim.notify("No applicable code found for transformation", vim.log.levels.INFO)
    return
  end
  
  -- Show preview
  vim.notify("Found " .. #nodes .. " locations to transform", vim.log.levels.INFO)
  
  -- For now, transform the entire buffer
  -- TODO: Support partial transformations
  local result = transform.transform(nodes[1], bufnr)
  
  if result then
    -- Create preview buffer
    local preview_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, vim.split(result, '\n'))
    vim.api.nvim_buf_set_option(preview_buf, 'filetype', vim.bo[bufnr].filetype)
    
    -- Show in split
    vim.cmd('split')
    vim.api.nvim_set_current_buf(preview_buf)
    
    -- Add apply keymap
    vim.keymap.set('n', 'a', function()
      -- Apply transformation
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, '\n'))
      vim.cmd('close')
      vim.notify("Transformation applied", vim.log.levels.INFO)
    end, { buffer = preview_buf, desc = "Apply transformation" })
    
    vim.notify("Press 'a' to apply transformation, 'q' to cancel", vim.log.levels.INFO)
  end
end

-- Semantic diff/merge
M.semantic_merge = function(base, ours, theirs)
  local prompt = string.format([[
Perform a semantic merge of these code versions:

BASE VERSION:
```
%s
```

OUR CHANGES:
```
%s
```

THEIR CHANGES:
```
%s
```

Instructions:
1. Understand the intent of both changes
2. Merge them semantically, not textually
3. Preserve functionality from both versions
4. Resolve conflicts based on code intent
5. Add comments where the merge decision was non-trivial
6. Return only the merged code

]], base, ours, theirs)
  
  return llm.request_sync(prompt, { temperature = 1 })
end

-- Cross-language refactoring
M.cross_language_rename = function(old_name, new_name, opts)
  opts = opts or {}
  
  -- Find all occurrences across languages
  local files = vim.fn.systemlist("rg -l " .. vim.fn.shellescape(old_name))
  
  local changes = {}
  for _, file in ipairs(files) do
    local ext = vim.fn.fnamemodify(file, ':e')
    local lang = M._ext_to_lang(ext)
    
    if lang then
      -- Load file
      local lines = vim.fn.readfile(file)
      local content = table.concat(lines, '\n')
      
      -- Use AI to understand context and rename
      local prompt = string.format([[
In this %s file, rename '%s' to '%s' intelligently:

```%s
%s
```

Rules:
1. Only rename the actual symbol, not partial matches
2. Update imports/exports
3. Update documentation comments
4. Preserve string literals unless they reference the symbol
5. Return the full file with changes
]], lang, old_name, new_name, lang, content)
      
      local result = llm.request_sync(prompt, { temperature = 0 })
      if result then
        table.insert(changes, {
          file = file,
          content = result
        })
      end
    end
  end
  
  -- Show preview of all changes
  M._preview_multi_file_changes(changes)
end

-- Helper to map extensions to languages
M._ext_to_lang = function(ext)
  local map = {
    js = "javascript",
    ts = "typescript", 
    jsx = "javascriptreact",
    tsx = "typescriptreact",
    py = "python",
    lua = "lua",
    go = "go",
    rs = "rust",
    java = "java",
    cpp = "cpp",
    c = "c",
  }
  return map[ext]
end

-- Preview multi-file changes
M._preview_multi_file_changes = function(changes)
  -- Create a buffer showing all changes
  local preview_lines = {"# Cross-Language Refactoring Preview", ""}
  
  for _, change in ipairs(changes) do
    table.insert(preview_lines, "## " .. change.file)
    table.insert(preview_lines, "")
    table.insert(preview_lines, "```" .. (M._ext_to_lang(vim.fn.fnamemodify(change.file, ':e')) or ""))
    vim.list_extend(preview_lines, vim.split(change.content, '\n'))
    table.insert(preview_lines, "```")
    table.insert(preview_lines, "")
  end
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  vim.cmd('tabnew')
  vim.api.nvim_set_current_buf(buf)
  
  -- Add apply command
  vim.keymap.set('n', 'a', function()
    for _, change in ipairs(changes) do
      vim.fn.writefile(vim.split(change.content, '\n'), change.file)
    end
    vim.notify("Applied changes to " .. #changes .. " files", vim.log.levels.INFO)
    vim.cmd('tabclose')
  end, { buffer = buf, desc = "Apply all changes" })
  
  vim.notify("Review changes and press 'a' to apply", vim.log.levels.INFO)
end

-- Safe migration helper
M.migrate_pattern = function(pattern_name, opts)
  opts = opts or {}
  
  local patterns = {
    -- Callback to Promise
    callbacks_to_promises = {
      description = "Convert Node.js callbacks to Promises",
      detect = "callback pattern: (err, result) =>",
      transform = "wrap in new Promise()",
    },
    
    -- jQuery to Vanilla JS
    jquery_to_vanilla = {
      description = "Convert jQuery to vanilla JavaScript", 
      detect = "$() or jQuery()",
      transform = "use document.querySelector and native APIs",
    },
    
    -- Class components to Hooks
    class_to_hooks = {
      description = "Convert React class components to function components with hooks",
      detect = "extends React.Component",
      transform = "useState, useEffect, etc.",
    },
  }
  
  local pattern = patterns[pattern_name]
  if not pattern then
    -- Show available patterns
    local available = vim.tbl_keys(patterns)
    vim.notify("Available migrations: " .. table.concat(available, ", "), vim.log.levels.INFO)
    return
  end
  
  -- Run migration
  vim.notify("Running migration: " .. pattern.description, vim.log.levels.INFO)
  -- Implementation continues...
end

-- Setup commands for this module
M.setup_commands = function()
  local commands = require('caramba.core.commands')
  
  -- Transform code command
  commands.register('Transform', function(args)
    local transform_name = args.args
    if transform_name == "" then
      -- Show available transformations
      local available = vim.tbl_keys(M.transformations)
      vim.ui.select(available, {
        prompt = "Select transformation:",
      }, function(choice)
        if choice then
          M.apply_transformation(choice)
        end
      end)
    else
      M.apply_transformation(transform_name)
    end
  end, {
    desc = 'Apply AST-based code transformation',
    nargs = '?',
    complete = function()
      return vim.tbl_keys(M.transformations)
    end,
  })
  
  -- Cross-language rename
  commands.register('CrossRename', function(args)
    local parts = vim.split(args.args, " ")
    if #parts < 2 then
      vim.notify("Usage: :AICrossRename <old_name> <new_name>", vim.log.levels.ERROR)
      return
    end
    M.cross_language_rename(parts[1], parts[2])
  end, {
    desc = 'Rename symbol across multiple languages',
    nargs = '+',
  })
  
  -- Migrate pattern
  commands.register('MigratePattern', function(args)
    M.migrate_pattern(args.args)
  end, {
    desc = 'Apply migration pattern',
    nargs = '?',
  })
end

return M 