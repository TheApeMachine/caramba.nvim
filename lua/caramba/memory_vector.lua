-- File-based vector store built on JSONL records
-- Each line: { vector = number[], meta = table }

local M = {}

local Path = require('plenary.path')
local embeddings = require('caramba.embeddings')
local config = require('caramba.config')
local logger = require('caramba.logger')

M._file = nil

function M.setup()
  local data_dir = vim.fn.stdpath('data') .. '/caramba'
  vim.fn.mkdir(data_dir, 'p')
  local path = data_dir .. '/memory_vectors.jsonl'
  M._file = Path:new(path)
  if not M._file:exists() then
    M._file:write('', 'w')
  end
end

local function cosine_similarity(vec1, vec2)
  local n = math.min(#vec1, #vec2)
  local dot, n1, n2 = 0, 0, 0
  for i=1,n do
    local a, b = vec1[i], vec2[i]
    dot = dot + (a*b)
    n1 = n1 + (a*a)
    n2 = n2 + (b*b)
  end
  if n1 == 0 or n2 == 0 then return 0 end
  return dot / (math.sqrt(n1) * math.sqrt(n2))
end

-- Add an embedding for arbitrary text with metadata
function M.add_from_text(text, meta)
  if not text or text == '' then return end
  M.setup()
  embeddings.generate_embedding(text, function(vec, err)
    if not vec then
      logger.warn('memory_vector: embedding failed', err)
      return
    end
    local rec = vim.json.encode({ vector = vec, meta = meta or {} })
    M._file:write(rec .. '\n', 'a')
  end)
end

-- Recall top_k related items for a query text
function M.recall(query_text, top_k, callback)
  top_k = top_k or 5
  M.setup()
  embeddings.generate_embedding(query_text or '', function(qvec, err)
    if not qvec then
      callback({}, err)
      return
    end
    local ok, content = pcall(function() return M._file:read() end)
    if not ok or not content or content == '' then
      callback({})
      return
    end
    local results = {}
    for line in content:gmatch('[^\n]+') do
      local okj, obj = pcall(vim.json.decode, line)
      if okj and obj and obj.vector and obj.meta then
        local score = cosine_similarity(qvec, obj.vector)
        table.insert(results, { score = score, meta = obj.meta })
      end
    end
    table.sort(results, function(a,b) return a.score > b.score end)
    local out = {}
    for i=1, math.min(top_k, #results) do
      table.insert(out, results[i])
    end
    callback(out)
  end)
end

return M


