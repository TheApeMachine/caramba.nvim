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

-- Configuration
M.config = {
  index_path = vim.fn.stdpath('cache') .. '/ai_search_index.json',
  embeddings_path = vim.fn.stdpath('cache') .. '/ai_embeddings.json',
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

-- Initialize search index
function M.setup(opts)
  if opts then
    M.config = vim.tbl_extend('force', M.config, opts)
  end
  
  -- Load existing index and embeddings
  M.load_index()
  M.load_embeddings()
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
  for _, exclude in ipairs(M.config.exclude_dirs) do
    if path:match(exclude) then
      return true
    end
  end
  return false
end

-- Check if a file should be included
local function should_include(path)
  local ext = path:match("%.([^%.]+)$")
  if not ext then return false end
  
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
    depth = 10,
    add_dirs = false,
    respect_gitignore = true,
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
      M.index_file(file)
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
  M.index_file(filepath)
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
  M._file_cache = {}
  
  local workspace_root = vim.fn.getcwd()
  local files_indexed = 0
  
  -- Use plenary's scandir for cross-platform file scanning
  local files = scan.scan_dir(workspace_root, {
    hidden = false,
    depth = 10,
    add_dirs = false,
    respect_gitignore = true,
    on_insert = function(path)
      -- Check if we should process this file
      if should_exclude(path) then
        return false
      end
      if not should_include(path) then
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
      end
      
      return true
    end,
  })
  
  -- Save index to cache
  M.save_index()
  
  vim.schedule(function()
    vim.notify(string.format("AI Search: Indexed %d files", files_indexed), vim.log.levels.INFO)
    M._last_indexed = os.time()
    if callback then callback() end
  end)
end

return M 