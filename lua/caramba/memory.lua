-- Caramba Long-term Memory System
-- Provides searchable memory for context enrichment

local M = {}

-- Dependencies
local Path = require('plenary.path')
local utils = require('caramba.utils')
local llm = require('caramba.llm')
local config = require('caramba.config')

-- Memory storage
M._memory_file = nil
M._memory_cache = {}
M._namespaces = { extracted = true }

-- Initialize memory system
function M.setup()
  local data_dir = vim.fn.stdpath('data') .. '/caramba'
  vim.fn.mkdir(data_dir, 'p')
  M._memory_file = Path:new(data_dir .. '/memory.json')

  -- Load existing memory
  M._load_memory()
end

-- Load memory from disk
function M._load_memory()
  if M._memory_file:exists() then
    local ok, data = pcall(function()
      return vim.json.decode(M._memory_file:read())
    end)

    if ok and data then
      M._memory_cache = data
    else
      M._memory_cache = { entries = {}, index = {} }
    end
  else
    M._memory_cache = { entries = {}, index = {} }
  end
end

-- Save memory to disk
function M._save_memory()
  local ok, json = pcall(vim.json.encode, M._memory_cache)
  if ok then
    M._memory_file:write(json, 'w')
  end
end

-- Store a memory entry
function M.store(content, context, tags)
  tags = tags or {}

  local entry = {
    id = vim.fn.localtime() .. '_' .. math.random(1000, 9999),
    content = content,
    context = context or {},
    tags = tags,
    timestamp = vim.fn.localtime(),
    access_count = 0,
  }

  -- Add to entries
  table.insert(M._memory_cache.entries, entry)
  -- Enforce max entries (simple FIFO)
  local max_entries = ((config.get().memory or {}).max_entries) or 5000
  if #M._memory_cache.entries > max_entries then
    table.remove(M._memory_cache.entries, 1)
  end

  -- Update search index
  M._update_index(entry)

  -- Save to disk
  M._save_memory()

  return entry.id
end

-- Update search index for an entry
function M._update_index(entry)
  if not M._memory_cache.index then
    M._memory_cache.index = {}
  end

  -- Extract keywords from content and context
  local keywords = {}

  -- From content
  for word in entry.content:gmatch('%w+') do
    if #word > 3 then -- Skip short words
      table.insert(keywords, word:lower())
    end
  end

  -- From context
  if entry.context.file_path then
    local filename = entry.context.file_path:match('([^/]+)$') or entry.context.file_path
    table.insert(keywords, filename:lower())
  end

  if entry.context.language then
    table.insert(keywords, entry.context.language:lower())
  end

  -- From tags
  for _, tag in ipairs(entry.tags) do
    table.insert(keywords, tag:lower())
  end

  -- Add to index
  for _, keyword in ipairs(keywords) do
    if not M._memory_cache.index[keyword] then
      M._memory_cache.index[keyword] = {}
    end
    table.insert(M._memory_cache.index[keyword], entry.id)
  end
end

-- Search memory with multiple angles
function M.search_multi_angle(user_query, code_context, ai_angle)
  local results = {}

  -- Angle 1: User query based search
  if user_query and user_query ~= "" then
    local user_results = M._search_by_text(user_query)
    for _, result in ipairs(user_results) do
      result.source = "user_query"
      table.insert(results, result)
    end
  end

  -- Angle 2: Code context based search
  if code_context then
    local code_results = M._search_by_code_context(code_context)
    for _, result in ipairs(code_results) do
      result.source = "code_context"
      table.insert(results, result)
    end
  end

  -- Angle 3: AI-controlled search
  if ai_angle and ai_angle ~= "" then
    local ai_results = M._search_by_text(ai_angle)
    for _, result in ipairs(ai_results) do
      result.source = "ai_angle"
      table.insert(results, result)
    end
  end

  -- Deduplicate and rank
  return M._deduplicate_and_rank(results)
end

-- Search by text query
function M._search_by_text(query)
  local results = {}
  local query_words = {}

  -- Extract words from query
  for word in query:gmatch('%w+') do
    if #word > 2 then
      table.insert(query_words, word:lower())
    end
  end

  -- Find matching entries
  local entry_scores = {}

  for _, word in ipairs(query_words) do
    if M._memory_cache.index[word] then
      for _, entry_id in ipairs(M._memory_cache.index[word]) do
        entry_scores[entry_id] = (entry_scores[entry_id] or 0) + 1
      end
    end
  end

  -- Convert to results with scores
  for entry_id, score in pairs(entry_scores) do
    local entry = M._find_entry_by_id(entry_id)
    if entry then
      table.insert(results, {
        entry = entry,
        score = score,
        relevance = score / #query_words
      })
    end
  end

  -- Sort by relevance
  table.sort(results, function(a, b) return a.relevance > b.relevance end)

  return results
end

-- Search by code context
function M._search_by_code_context(context)
  local results = {}

  if context.language then
    local lang_results = M._search_by_text(context.language)
    for _, result in ipairs(lang_results) do
      table.insert(results, result)
    end
  end

  if context.file_path then
    local filename = context.file_path:match('([^/]+)$') or context.file_path
    local file_results = M._search_by_text(filename)
    for _, result in ipairs(file_results) do
      table.insert(results, result)
    end
  end

  return results
end

-- Find entry by ID
function M._find_entry_by_id(id)
  for _, entry in ipairs(M._memory_cache.entries or {}) do
    if entry.id == id then
      entry.access_count = entry.access_count + 1
      return entry
    end
  end
  return nil
end

-- Deduplicate and rank results
function M._deduplicate_and_rank(results)
  local seen = {}
  local unique_results = {}

  for _, result in ipairs(results) do
    if not seen[result.entry.id] then
      seen[result.entry.id] = true
      table.insert(unique_results, result)
    end
  end

  -- Sort by relevance and recency
  table.sort(unique_results, function(a, b)
    if a.relevance == b.relevance then
      return a.entry.timestamp > b.entry.timestamp
    end
    return a.relevance > b.relevance
  end)

  -- Return top 5 results
  local top_results = {}
  for i = 1, math.min(5, #unique_results) do
    table.insert(top_results, unique_results[i])
  end

  return top_results
end

-- Purge expired extracted memories (TTL)
function M.purge_expired()
  local ttl_days = ((config.get().memory or {}).extracted_ttl_days) or 30
  local cutoff = vim.fn.localtime() - (ttl_days * 24 * 60 * 60)
  local kept = {}
  for _, e in ipairs(M._memory_cache.entries or {}) do
    local is_extracted = false
    for _, t in ipairs(e.tags or {}) do
      if t == 'extracted' then is_extracted = true break end
    end
    if (not is_extracted) or (e.timestamp or 0) >= cutoff then
      table.insert(kept, e)
    end
  end
  M._memory_cache.entries = kept
  -- Rebuild index
  M._memory_cache.index = {}
  for _, e in ipairs(kept) do M._update_index(e) end
  M._save_memory()
end

-- Build a compact recall pack for injection
function M.build_recall_pack(query, ctx)
  local items = M.search_multi_angle(query or '', ctx or {}, 'assistant recall') or {}
  if #items == 0 then return nil end
  local lines = { '## Recall Pack' }
  for _, r in ipairs(items) do
    lines[#lines+1] = string.format('- %s', r.entry.content)
  end
  return table.concat(lines, '\n')
end

-- Get memory stats
function M.get_stats()
  return {
    total_entries = #(M._memory_cache.entries or {}),
    index_size = vim.tbl_count(M._memory_cache.index or {}),
    memory_file = M._memory_file and M._memory_file:absolute() or "not initialized"
  }
end

-- Clear all memory (for testing/reset)
function M.clear_all()
  M._memory_cache = { entries = {}, index = {} }
  M._save_memory()
end

return M
