-- Semantic Search Module
-- Tree-sitter powered code search and indexing

local M = {}
local Job = require("plenary.job")
local Path = require("plenary.path")
local context = require("caramba.context")
local config = require("caramba.config")
local parsers = require("nvim-treesitter.parsers")
local scan = require('plenary.scandir')
local embeddings = require('caramba.embeddings')

-- Search index storage
M._index = {}
M._embeddings = {}
M._file_hashes = {}
M._indexing = false
M._last_indexed = nil
M._workspace_paths_cache = nil
M._workspace_paths_cache_key = nil

-- Configuration
M.config = {
  index_path = nil,  -- Will be set dynamically based on workspace
  embeddings_path = nil,  -- Will be set dynamically based on workspace
  exclude_dirs = {
    '.git', 'node_modules', '.venv', 'venv', '__pycache__', 
    'dist', 'build', 'target', '.idea', '.vscode'
  },
  include_extensions = {
    'lua', 'py', 'js', 'ts', 'jsx', 'tsx', 'go', 'rs', 
    'c', 'cpp', 'h', 'hpp', 'java', 'cs', 'rb', 'php'
  },
  max_file_size = 1024 * 1024, -- 1MB
  chunk_size = 50, -- Lines per chunk for embedding
}

-- Generate workspace-specific paths
local function get_workspace_paths()
  local workspace = vim.fn.getcwd()
  
  -- Check if we have a cached result for this workspace
  if M._workspace_paths_cache_key == workspace and M._workspace_paths_cache then
    return M._workspace_paths_cache
  end
  
  -- Ensure workspace is valid
  if not workspace or workspace == "" then
    error("Invalid workspace path")
  end
  
  -- Create a simple hash of the workspace path to make filenames unique
  local hash = vim.fn.sha256(workspace):sub(1, 8)
  local workspace_name = vim.fn.fnamemodify(workspace, ':t')
  
  local cache_dir = vim.fn.stdpath('cache')
  local paths = {
    index_path = Path:new(cache_dir, 'ai_search_index_' .. workspace_name .. '_' .. hash .. '.json'):absolute(),
    embeddings_path = Path:new(cache_dir, 'ai_embeddings_' .. workspace_name .. '_' .. hash .. '.json'):absolute(),
  }
  
  -- Cache the result
  M._workspace_paths_cache = paths
  M._workspace_paths_cache_key = workspace
  
  return paths
end

-- Initialize search index
function M.setup(opts)
  if opts then
    M.config = vim.tbl_extend('force', M.config, opts)
  end
  
  -- Set workspace-specific paths
  local paths = get_workspace_paths()
  M.config.index_path = paths.index_path
  M.config.embeddings_path = paths.embeddings_path
  
  -- Load existing index and embeddings
  M.load_index()
  M.load_embeddings()
  
  -- Setup file watchers for automatic updates
  M.setup_file_watchers()
  
  -- Check index freshness on startup
  vim.defer_fn(function()
    if vim.tbl_count(M._index) > 0 then
      local freshness = M.check_index_freshness()
      if freshness.total_stale > 0 or freshness.total_missing > 0 then
        vim.notify(
          string.format(
            "AI: Found %d stale and %d missing files in index. Run :AIRefreshIndex to update.", 
            freshness.total_stale, 
            freshness.total_missing
          ), 
          vim.log.levels.WARN
        )
      end
    end
  end, 2000)
end

-- Check if file should be indexed
function M._should_index_file(filepath)
  -- Skip non-existent files
  if vim.fn.filereadable(filepath) ~= 1 then
    return false
  end
  
  -- Skip files based on patterns
  local config = require("caramba.config").get()
  for _, pattern in ipairs(config.search.exclude_patterns) do
    if filepath:match(pattern) then
      return false
    end
  end
  
  -- Check file size
  local size = vim.fn.getfsize(filepath)
  if size > config.search.max_file_size then
    return false
  end
  
  -- Skip binary files by checking extension first
  local ext = filepath:match("%.([^%.]+)$")
  if ext then
    local binary_extensions = {
      "png", "jpg", "jpeg", "gif", "bmp", "ico", "webp",
      "pdf", "zip", "tar", "gz", "7z", "rar",
      "exe", "dll", "so", "dylib", "bin",
      "mp3", "mp4", "avi", "mov", "wmv",
      "ttf", "otf", "woff", "woff2",
      "db", "sqlite", "cache"
    }
    for _, bin_ext in ipairs(binary_extensions) do
      if ext:lower() == bin_ext then
        return false
      end
    end
  end
  
  -- For more complex filetype detection, we need to defer it
  -- Since we can't use vim.filetype.match in fast context
  return true
end

-- Extract symbols from a parsed tree
M._extract_symbols = function(filepath, content)
  local symbols = {}
  
  -- Try to detect language from extension
  local ext = filepath:match("%.([^%.]+)$")
  if not ext then return symbols end
  
  local lang = nil
  -- Map common extensions to Tree-sitter language names
  local ext_to_lang = {
    lua = "lua", py = "python", js = "javascript", ts = "typescript",
    jsx = "javascript", tsx = "typescript", go = "go", rs = "rust",
    c = "c", cpp = "cpp", h = "c", hpp = "cpp", java = "java",
    rb = "ruby", php = "php", cs = "c_sharp"
  }
  
  lang = ext_to_lang[ext:lower()]
  if not lang then return symbols end
  
  -- Try to parse with Tree-sitter
  local ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
  if not ok or not parser then return symbols end
  
  local tree = parser:parse()[1]
  if not tree then return symbols end
  
  local root = tree:root()
  
  -- Query for common symbol types
  local query_string = [[
    (function_declaration name: (identifier) @function.name)
    (function_definition name: (identifier) @function.name)
    (method_declaration name: (identifier) @method.name)
    (method_definition name: (identifier) @method.name)
    (class_declaration name: (identifier) @class.name)
    (class_definition name: (identifier) @class.name)
    (variable_declaration name: (identifier) @variable.name)
    (assignment_statement left: (identifier) @variable.name)
  ]]
  
  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok_query then return symbols end
  
  for id, node in query:iter_captures(root, content) do
    local name = vim.treesitter.get_node_text(node, content)
    local start_row, start_col, end_row, end_col = node:range()
    
    table.insert(symbols, {
      name = name,
      type = query.captures[id],
      range = {
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
      }
    })
  end
  
  return symbols
end

-- Check if a path should be excluded
local function should_exclude(path)
  local cfg = config.get()
  -- Check against exclude_patterns from the main config
  for _, pattern in ipairs(cfg.search.exclude_patterns) do
    if path:match(pattern) then
      return true
    end
  end
  return false
end

-- Check if a file should be included
local function should_include(path)
  local ext = path:match("%.([^%.]+)$")
  if not ext then return false end
  
  -- Use the include_extensions from M.config for now
  -- since the main config doesn't have an include list
  for _, include_ext in ipairs(M.config.include_extensions) do
    if ext == include_ext then
      return true
    end
  end
  return false
end

-- Index a single file
function M.index_file(filepath)
  local path = Path:new(filepath)
  
  -- Check file size
  local stat = vim.loop.fs_stat(filepath)
  if not stat or stat.size > M.config.max_file_size then
    return nil
  end
  
  -- Read file content
  local ok, content = pcall(path.read, path)
  if not ok then
    return nil
  end
  
  -- Extract symbols if possible
  local symbols = M._extract_symbols(filepath, content)
  
  return {
    path = filepath,
    content = content,
    symbols = symbols,
    size = stat.size,
    modified = stat.mtime.sec,
  }
end

-- Index the workspace with embeddings
M.index_workspace_with_embeddings = function(callback)
  vim.notify("AI: Indexing workspace with embeddings...", vim.log.levels.INFO)
  M._index = {}
  M._embeddings = {}
  M._indexing = true
  
  local workspace_root = vim.fn.getcwd()
  local files_to_index = {}
  
  -- First, collect all files to index
  scan.scan_dir(workspace_root, {
    hidden = false,
    depth = 100,  -- Increased depth to ensure we go deep into subdirectories
    add_dirs = false,
    respect_gitignore = false, -- Changed to false to ensure we scan all files
    silent = false,  -- Show errors if any
    on_insert = function(path)
      if should_exclude(path) or not should_include(path) then
        return false
      end
      table.insert(files_to_index, path)
      return true
    end,
  })
  
  vim.notify(string.format("AI: Found %d files to index", #files_to_index), vim.log.levels.INFO)
  
  -- Process files in batches
  local completed = 0
  local batch_size = 5
  
  local function process_batch(start_idx)
    local batch_completed = 0
    local batch_count = 0
    
    for i = start_idx, math.min(start_idx + batch_size - 1, #files_to_index) do
      batch_count = batch_count + 1
      M.index_file_with_embeddings(files_to_index[i], function(success)
        batch_completed = batch_completed + 1
        completed = completed + 1
        
        if completed % 10 == 0 then
          vim.schedule(function()
            vim.notify(string.format("AI: Indexed %d/%d files", completed, #files_to_index), vim.log.levels.INFO)
          end)
        end
        
        -- Process next batch when current batch is done
        if batch_completed == batch_count then
          if completed < #files_to_index then
            vim.defer_fn(function()
              process_batch(start_idx + batch_size)
            end, 500) -- Delay between batches
          else
            -- All done
            M._indexing = false
            M.save_index()
            M.save_embeddings()
            vim.schedule(function()
              vim.notify(string.format("AI: Indexed %d files with embeddings", completed), vim.log.levels.INFO)
              if callback then callback() end
            end)
          end
        end
      end)
    end
  end
  
  -- Start processing
  if #files_to_index > 0 then
    process_batch(1)
  else
    M._indexing = false
    if callback then callback() end
  end
end

-- Process files in batches
function M.process_batch(files, start_idx, callback)
  local batch_size = 10
  local end_idx = math.min(start_idx + batch_size - 1, #files)
  
  if start_idx > #files then
    vim.schedule(function()
      local total = vim.tbl_count(M._index)
      vim.notify(string.format("AI Search: Indexed %d files", total), vim.log.levels.INFO)
      M._last_indexed = os.time()
      if callback then callback() end
    end)
    return
  end
  
  -- Process current batch
  for i = start_idx, end_idx do
    local file = files[i]
    if file and M._should_index_file(file) then
      local file_data = M.index_file(file)
      if file_data then
        M._index[file] = file_data
      end
    end
  end
  
  -- Schedule next batch
  vim.defer_fn(function()
    M.process_batch(files, end_idx + 1, callback)
  end, 10) -- Small delay between batches
end

-- Update file in index
function M.update_file(filepath)
  filepath = vim.fn.fnamemodify(filepath, ":p")
  
  -- Check if file should be indexed
  if not should_include(filepath) or should_exclude(filepath) then
    -- Remove from index if it was previously indexed
    if M._index[filepath] then
      M._index[filepath] = nil
      vim.notify("AI: Removed " .. vim.fn.fnamemodify(filepath, ":~:.") .. " from index", vim.log.levels.DEBUG)
    end
    return
  end
  
  local file_data = M.index_file(filepath)
  if file_data then
    M._index[filepath] = file_data
    
    -- Update embeddings if enabled
    if config.get().search.use_embeddings then
      M.index_file_with_embeddings(filepath, function(success)
        if success then
          vim.notify("AI: Updated " .. vim.fn.fnamemodify(filepath, ":~:.") .. " in index (with embeddings)", vim.log.levels.DEBUG)
        else
          vim.notify("AI: Updated " .. vim.fn.fnamemodify(filepath, ":~:.") .. " in index (embeddings failed)", vim.log.levels.DEBUG)
        end
      end)
    else
      vim.notify("AI: Updated " .. vim.fn.fnamemodify(filepath, ":~:.") .. " in index", vim.log.levels.DEBUG)
    end
  end
end

-- Find definition of a symbol
function M.find_definition(symbol_name, opts)
  opts = opts or {}
  local results = M.semantic_search(symbol_name, opts)
  
  -- Return first result as the most likely definition
  return results[1]
end

-- Find references to a symbol
function M.find_references(symbol_name, opts)
  opts = opts or {}
  return M.semantic_search(symbol_name, opts)
end

-- Get index statistics
function M.get_stats()
  local total_files = vim.tbl_count(M._index)
  local total_symbols = 0
  
  for _, file_data in pairs(M._index) do
    if file_data.symbols then
      total_symbols = total_symbols + #file_data.symbols
    end
  end
  
  return {
    files = total_files,
    symbols = total_symbols,
    last_indexed = M._last_indexed,
  }
end

-- True semantic search using embeddings
M.semantic_search = function(query, opts)
  opts = opts or {}
  local max_results = opts.max_results or 10
  
  -- Check if we have embeddings
  if vim.tbl_count(M._embeddings) == 0 then
    vim.notify("AI: No embeddings found. Falling back to keyword search.", vim.log.levels.WARN)
    return M.keyword_search(query, opts)
  end
  
  -- Generate embedding for the query
  local results = {}
  embeddings.generate_embedding(query, function(query_embedding, err)
    if err or not query_embedding then
      vim.notify("AI: Failed to generate query embedding. Falling back to keyword search.", vim.log.levels.WARN)
      results = M.keyword_search(query, opts)
      return
    end
    
    -- Find similar chunks
    local similar = embeddings.find_similar(query_embedding, M._embeddings, max_results * 2)
    
    -- Convert chunk results to file results
    local seen_files = {}
    for _, match in ipairs(similar) do
      local chunk_id = match.id
      local filepath, chunk_idx = chunk_id:match("^(.+):(%d+)$")
      chunk_idx = tonumber(chunk_idx)
      
      if filepath and chunk_idx and M._index[filepath] then
        local file_data = M._index[filepath]
        local chunk = file_data.chunks[chunk_idx]
        
        if chunk and not seen_files[filepath] then
          seen_files[filepath] = true
          table.insert(results, {
            file = filepath,
            line = chunk.start_line,
            text = chunk.content,
            score = match.score,
            match_type = "semantic"
          })
          
          if #results >= max_results then
            break
          end
        end
      end
    end
    
    -- If we don't have enough results, supplement with keyword search
    if #results < max_results / 2 then
      local keyword_results = M.keyword_search(query, {
        max_results = max_results - #results
      })
      
      for _, result in ipairs(keyword_results) do
        result.match_type = "keyword"
        table.insert(results, result)
      end
    end
  end)
  
  -- Wait for async operation (with timeout)
  local timeout = 5000
  local start = vim.loop.now()
  while #results == 0 and (vim.loop.now() - start) < timeout do
    vim.wait(10)
  end
  
  return results
end

-- Keyword search (renamed from semantic_search)
M.keyword_search = function(query, opts)
  opts = opts or {}
  
  if vim.tbl_isempty(M._index) then
    return {}
  end
  
  -- Simple keyword-based search for now
  -- TODO: Integrate with LLM for true semantic search
  
  local results = {}
  local query_lower = query:lower()
  local keywords = vim.split(query_lower, "%s+")
  
  for filepath, file_data in pairs(M._index) do
    local content_lower = file_data.content:lower()
    local score = 0
    
    -- Check if all keywords appear in content
    local all_found = true
    for _, keyword in ipairs(keywords) do
      if content_lower:find(keyword, 1, true) then
        score = score + 1
      else
        all_found = false
      end
    end
    
    if all_found and score > 0 then
      -- Find best matching line
      local lines = vim.split(file_data.content, "\n")
      local best_line = 1
      local best_line_score = 0
      
      for i, line in ipairs(lines) do
        local line_lower = line:lower()
        local line_score = 0
        for _, keyword in ipairs(keywords) do
          if line_lower:find(keyword, 1, true) then
            line_score = line_score + 1
          end
        end
        if line_score > best_line_score then
          best_line = i
          best_line_score = line_score
        end
      end
      
      table.insert(results, {
        filepath = filepath,
        line = best_line,
        score = score,
        preview = lines[best_line] or "",
        symbols = file_data.symbols,
      })
    end
  end
  
  -- Sort by score
  table.sort(results, function(a, b)
    return a.score > b.score
  end)
  
  -- Limit results
  local max_results = opts.max_results or 20
  local limited_results = {}
  for i = 1, math.min(#results, max_results) do
    table.insert(limited_results, results[i])
  end
  
  return limited_results
end

-- Save index to disk
M.save_index = function()
  local cache_path = M.config.index_path
  local cache_dir = vim.fn.fnamemodify(cache_path, ':h')
  
  -- Ensure cache directory exists
  vim.fn.mkdir(cache_dir, 'p')
  
  -- Save index
  local ok, encoded = pcall(vim.json.encode, {
    version = 1,
    indexed_at = os.time(),
    workspace = vim.fn.getcwd(),
    index = M._index,
  })
  
  if ok then
    local file = io.open(cache_path, 'w')
    if file then
      file:write(encoded)
      file:close()
    end
  end
end

-- Load index from disk
M.load_index = function()
  local cache_path = M.config.index_path
  
  if vim.fn.filereadable(cache_path) == 0 then
    return false
  end
  
  local file = io.open(cache_path, 'r')
  if not file then
    return false
  end
  
  local content = file:read('*all')
  file:close()
  
  local ok, data = pcall(vim.json.decode, content)
  if ok and data and data.workspace == vim.fn.getcwd() then
    M._index = data.index or {}
    M._last_indexed = data.indexed_at
    return true
  end
  
  return false
end

-- Extract code chunks for embedding
local function extract_chunks(filepath, content)
  local chunks = {}
  local lines = vim.split(content, '\n')
  local language = vim.filetype.match({ filename = filepath })
  
  -- Try to extract semantic chunks (functions, classes)
  if language and parsers.has_parser(language) then
    local parser = vim.treesitter.get_string_parser(content, language)
    local tree = parser:parse()[1]
    local root = tree:root()
    
    -- Query for function and class nodes
    local query_string = [[
      (function_declaration) @function
      (function_definition) @function
      (method_declaration) @function
      (method_definition) @function
      (class_declaration) @class
      (class_definition) @class
    ]]
    
    local ok, query = pcall(vim.treesitter.query.parse, language, query_string)
    if ok then
      for id, node in query:iter_captures(root, content) do
        local start_row, _, end_row, _ = node:range()
        local chunk_lines = {}
        
        for i = start_row + 1, math.min(end_row + 1, #lines) do
          table.insert(chunk_lines, lines[i])
        end
        
        if #chunk_lines > 0 then
          table.insert(chunks, {
            content = table.concat(chunk_lines, '\n'),
            start_line = start_row + 1,
            end_line = end_row + 1,
            type = query.captures[id]
          })
        end
      end
    end
  end
  
  -- Fallback: chunk by fixed size if no semantic chunks found
  if #chunks == 0 then
    for i = 1, #lines, M.config.chunk_size do
      local chunk_lines = {}
      local end_idx = math.min(i + M.config.chunk_size - 1, #lines)
      
      for j = i, end_idx do
        table.insert(chunk_lines, lines[j])
      end
      
      table.insert(chunks, {
        content = table.concat(chunk_lines, '\n'),
        start_line = i,
        end_line = end_idx,
        type = "block"
      })
    end
  end
  
  return chunks
end

-- Index a single file with embeddings
M.index_file_with_embeddings = function(filepath, callback)
  local path = Path:new(filepath)
  
  -- Check file size
  local stat = vim.loop.fs_stat(filepath)
  if not stat or stat.size > M.config.max_file_size then
    if callback then callback(false) end
    return
  end
  
  -- Read file content
  local ok, content = pcall(path.read, path)
  if not ok then
    if callback then callback(false) end
    return
  end
  
  -- Extract chunks
  local chunks = extract_chunks(filepath, content)
  
  -- Generate embeddings for chunks
  local chunk_texts = {}
  for i, chunk in ipairs(chunks) do
    local chunk_id = filepath .. ":" .. i
    chunk_texts[chunk_id] = chunk.content
  end
  
  embeddings.batch_generate_embeddings(chunk_texts, function(chunk_embeddings)
    -- Store file data
    M._index[filepath] = {
      path = filepath,
      content = content,
      chunks = chunks,
      size = stat.size,
      modified = stat.mtime.sec,
    }
    
    -- Store embeddings
    for chunk_id, embedding in pairs(chunk_embeddings) do
      M._embeddings[chunk_id] = embedding
    end
    
    if callback then callback(true) end
  end)
end

-- Save embeddings to disk
M.save_embeddings = function()
  local embeddings_path = M.config.embeddings_path
  local cache_dir = vim.fn.fnamemodify(embeddings_path, ':h')
  
  vim.fn.mkdir(cache_dir, 'p')
  
  local ok, encoded = pcall(vim.json.encode, {
    version = 1,
    embeddings = M._embeddings,
  })
  
  if ok then
    local file = io.open(embeddings_path, 'w')
    if file then
      file:write(encoded)
      file:close()
    end
  end
end

-- Load embeddings from disk
M.load_embeddings = function()
  local embeddings_path = M.config.embeddings_path
  
  if vim.fn.filereadable(embeddings_path) == 0 then
    return false
  end
  
  local file = io.open(embeddings_path, 'r')
  if not file then
    return false
  end
  
  local content = file:read('*all')
  file:close()
  
  local ok, data = pcall(vim.json.decode, content)
  if ok and data then
    M._embeddings = data.embeddings or {}
    return true
  end
  
  return false
end

-- Update the main index_workspace to use embeddings if available
M.index_workspace = function(callback)
  -- Refresh paths in case workspace changed
  local paths = get_workspace_paths()
  M.config.index_path = paths.index_path
  M.config.embeddings_path = paths.embeddings_path
  
  local provider = config.get().provider
  
  -- Use embeddings for OpenAI or if explicitly enabled
  if provider == "openai" or config.get().search.use_embeddings then
    M.index_workspace_with_embeddings(callback)
  else
    -- Use the existing keyword-based indexing
    M.index_workspace_keyword(callback)
  end
end

-- Rename the old index_workspace to index_workspace_keyword
M.index_workspace_keyword = function(callback)
  vim.notify("AI: Indexing workspace with keyword search...", vim.log.levels.INFO)
  M._index = {}
  
  local workspace_root = vim.fn.getcwd()
  local files_indexed = 0
  local files_scanned = 0
  local files_excluded = 0
  
  vim.notify("AI: Scanning directory: " .. workspace_root, vim.log.levels.INFO)
  
  -- Check if the directory exists
  if vim.fn.isdirectory(workspace_root) == 0 then
    vim.notify("AI: Error - workspace directory does not exist: " .. workspace_root, vim.log.levels.ERROR)
    if callback then callback() end
    return
  end
  
  -- Use plenary's scandir for cross-platform file scanning
  local ok, files = pcall(scan.scan_dir, workspace_root, {
    hidden = false,
    depth = 100,  -- Increased depth to ensure we go deep into subdirectories
    add_dirs = false,
    respect_gitignore = false, -- Changed to false to ensure we scan all files
    silent = false,  -- Show errors if any
    on_insert = function(path)
      files_scanned = files_scanned + 1
      
      -- Debug first few files
      if files_scanned <= 5 then
        vim.notify("AI: Scanning file: " .. path, vim.log.levels.DEBUG)
      end
      
      -- Check if we should process this file
      if should_exclude(path) then
        files_excluded = files_excluded + 1
        if files_excluded <= 5 then
          vim.notify("AI: Excluded: " .. path, vim.log.levels.DEBUG)
        end
        return false
      end
      if not should_include(path) then
        if files_scanned <= 10 then
          local ext = path:match("%.([^%.]+)$") or "no extension"
          vim.notify("AI: Skipped (extension " .. ext .. "): " .. path, vim.log.levels.DEBUG)
        end
        return false
      end
      
      -- Index the file
      local file_data = M.index_file(path)
      if file_data then
        M._index[path] = file_data
        files_indexed = files_indexed + 1
        
        -- Show progress every 100 files
        if files_indexed % 100 == 0 then
          vim.schedule(function()
            vim.notify(string.format("AI Search: Indexed %d files...", files_indexed), vim.log.levels.INFO)
          end)
        end
        
        -- Debug: show every Go file found
        if file_data and path:match("%.go$") and files_indexed <= 20 then
          vim.schedule(function()
            vim.notify("AI: Indexed Go file: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
          end)
        end
      end
      
      return true
    end,
  })
  
  if not ok then
    vim.notify("AI: Error scanning directory: " .. tostring(files), vim.log.levels.ERROR)
    if callback then callback() end
    return
  end
  
  -- If we didn't find many files, try using vim's globpath as fallback
  if files_indexed < 10 and files_scanned < 100 then
    vim.notify("AI: Few files found with plenary, trying vim.fn.globpath fallback...", vim.log.levels.WARN)
    
    -- Try to find files using globpath for each extension
    for _, ext in ipairs(M.config.include_extensions) do
      local pattern = "**/*." .. ext
      local found_files = vim.fn.globpath(workspace_root, pattern, false, true)
      
      vim.notify(string.format("AI: Found %d .%s files", #found_files, ext), vim.log.levels.INFO)
      
      for _, filepath in ipairs(found_files) do
        -- Make sure we haven't already indexed this file
        if not M._index[filepath] then
          files_scanned = files_scanned + 1
          
          -- Check exclusions
          if not should_exclude(filepath) then
            local file_data = M.index_file(filepath)
            if file_data then
              M._index[filepath] = file_data
              files_indexed = files_indexed + 1
              
              -- Show progress
              if files_indexed <= 10 or files_indexed % 50 == 0 then
                vim.schedule(function()
                  vim.notify(string.format("AI: Indexed %s", vim.fn.fnamemodify(filepath, ":~:.")), vim.log.levels.INFO)
                end)
              end
            end
          end
        end
      end
    end
  end
  
  -- Save index to cache
  M.save_index()
  
  vim.schedule(function()
    local stats = M.get_stats()
    vim.notify(string.format("AI Search: Indexed %d symbols from %d files (scanned: %d, excluded: %d)", 
      stats.symbols, files_indexed, files_scanned, files_excluded), vim.log.levels.INFO)
    M._last_indexed = os.time()
    if callback then callback() end
  end)
end

-- List all index files in cache directory
M.list_index_files = function()
  local cache_dir = vim.fn.stdpath('cache')
  local files = vim.fn.globpath(cache_dir, 'ai_search_index_*.json', false, true)
  local embedding_files = vim.fn.globpath(cache_dir, 'ai_embeddings_*.json', false, true)
  
  local all_files = {}
  for _, f in ipairs(files) do
    table.insert(all_files, { path = f, type = "index" })
  end
  for _, f in ipairs(embedding_files) do
    table.insert(all_files, { path = f, type = "embeddings" })
  end
  
  return all_files
end

-- Check if a file path belongs to the current workspace
M.is_current_workspace_file = function(filepath)
  local current_paths = get_workspace_paths()
  return filepath == current_paths.index_path or filepath == current_paths.embeddings_path
end

-- Clean up old index files (keep only current workspace)
M.cleanup_old_indexes = function()
  local all_files = M.list_index_files()
  local removed = 0
  
  for _, file_info in ipairs(all_files) do
    if not M.is_current_workspace_file(file_info.path) then
      vim.fn.delete(file_info.path)
      removed = removed + 1
    end
  end
  
  vim.notify(string.format("Removed %d old index files", removed), vim.log.levels.INFO)
  return removed
end

-- Get current workspace index info
M.get_index_info = function()
  local paths = get_workspace_paths()
  local info = {
    workspace = vim.fn.getcwd(),
    index_path = paths.index_path,
    embeddings_path = paths.embeddings_path,
    index_exists = vim.fn.filereadable(paths.index_path) == 1,
    embeddings_exist = vim.fn.filereadable(paths.embeddings_path) == 1,
  }
  
  -- Get file sizes if they exist
  if info.index_exists then
    local stat = vim.loop.fs_stat(paths.index_path)
    if stat then
      info.index_size = stat.size
    end
  end
  
  if info.embeddings_exist then
    local stat = vim.loop.fs_stat(paths.embeddings_path)
    if stat then
      info.embeddings_size = stat.size
    end
  end
  
  return info
end

-- Move embeddings from one file to another
local function move_file_embeddings(old_path, new_path)
  local i = 1
  while true do
    local old_chunk_id = old_path .. ":" .. i
    local new_chunk_id = new_path .. ":" .. i
    if M._embeddings[old_chunk_id] then
      M._embeddings[new_chunk_id] = M._embeddings[old_chunk_id]
      M._embeddings[old_chunk_id] = nil
      i = i + 1
    else
      break
    end
  end
end

-- Setup file watchers for automatic index updates
M.setup_file_watchers = function()
  local group = vim.api.nvim_create_augroup("AISearchIndexUpdate", { clear = true })
  
  -- Update on file save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*",
    callback = function(args)
      -- Skip if indexing is disabled
      if not config.get().search.enable_index then
        return
      end
      
      -- Skip if we're currently doing a full index
      if M._indexing then
        return
      end
      
      -- Update the file in the index
      vim.defer_fn(function()
        M.update_file(args.file)
        -- Save index periodically (debounced)
        M.schedule_save()
      end, 100)
    end,
  })
  
  -- Handle file deletion
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    pattern = "*",
    callback = function(args)
      local filepath = vim.fn.fnamemodify(args.file, ":p")
      if M._index[filepath] then
        M._index[filepath] = nil
        
        -- Remove embeddings
        remove_file_embeddings(filepath)
        
        vim.notify("AI: Removed " .. vim.fn.fnamemodify(filepath, ":~:.") .. " from index", vim.log.levels.DEBUG)
        M.schedule_save()
      end
    end,
  })
  
  -- Handle file rename (via LSP)
  -- NOTE: This only catches renames done through LSP (e.g., via language server rename).
  -- Renames done outside the editor (file manager, command line) won't be detected.
  -- TODO: Consider adding a :AIDetectRenames command that scans for moved files
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LspRename",
    callback = function(args)
      if args.data and args.data.old_name and args.data.new_name then
        local old_path = vim.fn.fnamemodify(args.data.old_name, ":p")
        local new_path = vim.fn.fnamemodify(args.data.new_name, ":p")
        
        if M._index[old_path] then
          -- Move the index entry
          M._index[new_path] = M._index[old_path]
          M._index[new_path].path = new_path
          M._index[old_path] = nil
          
          -- Update embeddings
          move_file_embeddings(old_path, new_path)
          
          vim.notify(
            string.format(
              "AI: Renamed %s to %s in index",
              vim.fn.fnamemodify(old_path, ":~:."),
              vim.fn.fnamemodify(new_path, ":~:.")
            ),
            vim.log.levels.DEBUG
          )
          M.schedule_save()
        end
      end
    end,
  })
end

-- Debounced save functionality
M._save_timer = nil
M.schedule_save = function()
  if M._save_timer then
    vim.fn.timer_stop(M._save_timer)
  end
  
  M._save_timer = vim.fn.timer_start(5000, function()
    M.save_index()
    M.save_embeddings()
    vim.notify("AI: Index saved", vim.log.levels.DEBUG)
    M._save_timer = nil
  end)
end

-- Check if index needs refresh (for stale files)
M.check_index_freshness = function()
  local stale_files = {}
  local missing_files = {}
  
  for filepath, file_data in pairs(M._index) do
    local stat = vim.loop.fs_stat(filepath)
    
    if not stat then
      -- File no longer exists
      table.insert(missing_files, filepath)
    elseif stat.mtime.sec > file_data.modified then
      -- File has been modified outside of Neovim
      table.insert(stale_files, filepath)
    end
  end
  
  return {
    stale = stale_files,
    missing = missing_files,
    total_stale = #stale_files,
    total_missing = #missing_files,
  }
end

-- Refresh stale files in index
M.refresh_stale_files = function(callback)
  local freshness = M.check_index_freshness()
  local total_updates = freshness.total_stale + freshness.total_missing
  
  if total_updates == 0 then
    vim.notify("AI: Index is up to date", vim.log.levels.INFO)
    if callback then callback() end
    return
  end
  
  vim.notify(string.format("AI: Refreshing %d stale and %d missing files", freshness.total_stale, freshness.total_missing), vim.log.levels.INFO)
  
  -- Remove missing files
  for _, filepath in ipairs(freshness.missing) do
    M._index[filepath] = nil
    
    -- Remove embeddings
    remove_file_embeddings(filepath)
  end
  
  -- Update stale files
  local updated = 0
  for _, filepath in ipairs(freshness.stale) do
    M.update_file(filepath)
    updated = updated + 1
    
    if updated % 10 == 0 then
      vim.notify(string.format("AI: Updated %d/%d stale files", updated, freshness.total_stale), vim.log.levels.INFO)
    end
  end
  
  -- Save changes
  M.save_index()
  M.save_embeddings()
  
  vim.notify("AI: Index refresh complete", vim.log.levels.INFO)
  if callback then callback() end
end

-- Get combined index data (stats + info) to reduce I/O
M.get_combined_index_data = function()
  -- Get basic stats
  local total_files = vim.tbl_count(M._index)
  local total_symbols = 0
  
  for _, file_data in pairs(M._index) do
    if file_data.symbols then
      total_symbols = total_symbols + #file_data.symbols
    end
  end
  
  -- Get index info
  local paths = get_workspace_paths()
  local index_exists = vim.fn.filereadable(paths.index_path) == 1
  local embeddings_exist = vim.fn.filereadable(paths.embeddings_path) == 1
  
  local result = {
    stats = {
      files = total_files,
      symbols = total_symbols,
      last_indexed = M._last_indexed,
    },
    info = {
      workspace = vim.fn.getcwd(),
      index_path = paths.index_path,
      embeddings_path = paths.embeddings_path,
      index_exists = index_exists,
      embeddings_exist = embeddings_exist,
    }
  }
  
  -- Get file sizes if they exist (single stat call per file)
  if index_exists then
    local stat = vim.loop.fs_stat(paths.index_path)
    if stat then
      result.info.index_size = stat.size
    end
  end
  
  if embeddings_exist then
    local stat = vim.loop.fs_stat(paths.embeddings_path)
    if stat then
      result.info.embeddings_size = stat.size
    end
  end
  
  return result
end

-- Remove all embeddings for a file
local function remove_file_embeddings(filepath)
  local i = 1
  while true do
    local chunk_id = filepath .. ":" .. i
    if M._embeddings[chunk_id] then
      M._embeddings[chunk_id] = nil
      i = i + 1
    else
      break
    end
  end
end

return M 