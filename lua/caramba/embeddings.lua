-- Embeddings module for semantic search
local M = {}
local config = require('caramba.config')

-- Vector operations
M.cosine_similarity = function(vec1, vec2)
  if #vec1 ~= #vec2 then
    return 0
  end
  
  local dot_product = 0
  local norm1 = 0
  local norm2 = 0
  
  for i = 1, #vec1 do
    dot_product = dot_product + (vec1[i] * vec2[i])
    norm1 = norm1 + (vec1[i] * vec1[i])
    norm2 = norm2 + (vec2[i] * vec2[i])
  end
  
  norm1 = math.sqrt(norm1)
  norm2 = math.sqrt(norm2)
  
  if norm1 == 0 or norm2 == 0 then
    return 0
  end
  
  return dot_product / (norm1 * norm2)
end

-- Generate embedding for text using OpenAI
M.generate_embedding_openai = function(text, callback)
  local api_config = config.get().api.openai
  local search_config = config.get().search
  
  if not api_config.api_key then
    callback(nil, "OpenAI API key not set")
    return
  end
  
  -- Truncate text if too long (new models support up to 8191 tokens)
  if #text > 30000 then
    text = text:sub(1, 30000) .. "..."
  end
  
  -- Use the configured model or default to text-embedding-3-small
  local model = search_config.embedding_model or "text-embedding-3-small"
  
  -- Optional: specify dimensions for text-embedding-3-* models
  -- This can reduce costs and storage while maintaining quality
  local body = {
    model = model,
    input = text
  }
  
  -- For the new models, we can specify dimensions to reduce size
  if model == "text-embedding-3-small" or model == "text-embedding-3-large" then
    -- Default dimensions: 3-small=1536, 3-large=3072
    -- We can use fewer dimensions to save space and cost
    body.dimensions = search_config.embedding_dimensions or (model == "text-embedding-3-small" and 512 or 1024)
  end
  
  local body_json = vim.json.encode(body)
  
  local Job = require('plenary.job')
  local job = Job:new({
    command = "curl",
    args = {
      "-sS",
      "https://api.opencaramba.com/v1/embeddings",
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-H", "Authorization: Bearer " .. api_config.api_key,
      "-d", body_json
    },
    on_exit = function(j, return_val)
      if return_val ~= 0 then
        callback(nil, "Request failed")
        return
      end
      
      local response = table.concat(j:result(), "\n")
      local ok, data = pcall(vim.json.decode, response)
      
      if ok and data.data and data.data[1] and data.data[1].embedding then
        callback(data.data[1].embedding, nil)
      else
        callback(nil, "Failed to parse embedding response")
      end
    end,
  })
  
  job:start()
end

-- Generate embedding using the current provider
M.generate_embedding = function(text, callback)
  local provider = config.get().provider
  
  if provider == "openai" then
    M.generate_embedding_openai(text, callback)
  else
    -- For other providers, we'll use a simple TF-IDF-like approach
    -- This is a placeholder - real implementations would use the provider's embedding API
    M.generate_embedding_fallback(text, callback)
  end
end

-- Fallback embedding using character n-grams (poor man's embedding)
M.generate_embedding_fallback = function(text, callback)
  local search_config = config.get().search
  local dimensions = search_config.embedding_dimensions or 512
  
  -- Create a simple embedding using character trigrams
  local embedding = {}
  local ngram_counts = {}
  local total = 0
  
  -- Convert to lowercase and extract trigrams
  text = text:lower()
  for i = 1, #text - 2 do
    local trigram = text:sub(i, i + 2)
    ngram_counts[trigram] = (ngram_counts[trigram] or 0) + 1
    total = total + 1
  end
  
  -- Create a fixed-size embedding vector matching configured dimensions
  -- Use a simple hash function to map trigrams to dimensions
  for i = 1, dimensions do
    embedding[i] = 0
  end
  
  -- Distribute trigram counts across dimensions
  for trigram, count in pairs(ngram_counts) do
    -- Simple hash: sum of character codes
    local hash = 0
    for j = 1, #trigram do
      hash = hash + string.byte(trigram, j)
    end
    
    -- Map to multiple dimensions for better distribution
    for offset = 0, 2 do
      local dim = ((hash + offset * 31) % dimensions) + 1
      embedding[dim] = embedding[dim] + count
    end
  end
  
  -- Normalize the vector
  local norm = 0
  for i = 1, dimensions do
    embedding[i] = embedding[i] / math.max(total, 1)
    norm = norm + embedding[i] * embedding[i]
  end
  norm = math.sqrt(norm)
  
  if norm > 0 then
    for i = 1, dimensions do
      embedding[i] = embedding[i] / norm
    end
  end
  
  vim.schedule(function()
    callback(embedding, nil)
  end)
end

-- Generate embeddings for code chunks
M.generate_code_embedding = function(code, language, callback)
  -- Prepare code for embedding by adding context
  local prepared_text = string.format([[
Language: %s

%s
]], language or "unknown", code)
  
  M.generate_embedding(prepared_text, callback)
end

-- Find most similar embeddings
M.find_similar = function(query_embedding, embeddings, top_k)
  top_k = top_k or 10
  local similarities = {}
  
  for id, embedding in pairs(embeddings) do
    local similarity = M.cosine_similarity(query_embedding, embedding)
    table.insert(similarities, {
      id = id,
      score = similarity
    })
  end
  
  -- Sort by similarity score
  table.sort(similarities, function(a, b)
    return a.score > b.score
  end)
  
  -- Return top k results
  local results = {}
  for i = 1, math.min(top_k, #similarities) do
    if similarities[i].score > 0.1 then -- Minimum similarity threshold
      table.insert(results, similarities[i])
    end
  end
  
  return results
end

-- Batch generate embeddings with rate limiting
M.batch_generate_embeddings = function(texts, callback, progress_callback)
  local embeddings = {}
  local completed = 0
  local total = vim.tbl_count(texts)
  
  local function process_next(ids)
    if #ids == 0 then
      callback(embeddings)
      return
    end
    
    local id = table.remove(ids, 1)
    local text = texts[id]
    
    M.generate_embedding(text, function(embedding, err)
      if embedding then
        embeddings[id] = embedding
      end
      
      completed = completed + 1
      if progress_callback then
        progress_callback(completed, total)
      end
      
      -- Process next with a small delay to avoid rate limiting
      vim.defer_fn(function()
        process_next(ids)
      end, 100) -- 100ms delay between requests
    end)
  end
  
  -- Start processing
  local ids = vim.tbl_keys(texts)
  process_next(ids)
end

return M 