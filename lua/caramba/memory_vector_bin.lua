-- Binary on-disk vector store: header(dimension: u32 BE) + repeated { vector(float32 LE * dim) + meta_len(u32 BE) + meta_json }

local M = {}

local embeddings = require('caramba.embeddings')
local logger = require('caramba.logger')

M._path = nil
M._dim = nil
local has_pack = type(string.pack) == 'function' and type(string.unpack) == 'function'

local function ensure_file(path, dim)
  local f = io.open(path, 'rb')
  if f == nil then
    local wf = io.open(path, 'wb')
    if not wf then error('Failed to create vector store file: ' .. path) end
    wf:write(string.pack('>I4', dim))
    wf:close()
    return dim
  end
  local header = f:read(4)
  f:close()
  if not header or #header < 4 then
    local wf = io.open(path, 'wb')
    if wf then
      wf:write(string.pack('>I4', dim))
      wf:close()
    end
    return dim
  end
  local existing_dim = string.unpack('>I4', header)
  if existing_dim ~= dim then
    logger.warn('memory_vector_bin: dimension mismatch; recreating file', { want = dim, have = existing_dim })
    local wf = io.open(path, 'wb')
    if wf then
      wf:write(string.pack('>I4', dim))
      wf:close()
    end
    return dim
  end
  return existing_dim
end

function M.setup(opts)
  opts = opts or {}
  local data_dir = vim.fn.stdpath('data') .. '/caramba'
  vim.fn.mkdir(data_dir, 'p')
  M._path = opts.path or (data_dir .. '/memory_vectors.bin')
  local dim = opts.dim or (require('caramba.config').get().search.embedding_dimensions or 512)
  if has_pack then
    M._dim = ensure_file(M._path, dim)
  else
    -- Fallback to JSONL store if packing is unavailable (LuaJIT)
    M._dim = dim
  end
end

local function add_record(vec, meta)
  if not M._path then M.setup() end
  local f = assert(io.open(M._path, 'ab'))
  -- vector as little endian float32
  for i = 1, #vec do
    f:write(string.pack('<f', vec[i]))
  end
  local meta_json = vim.json.encode(meta or {})
  f:write(string.pack('>I4', #meta_json))
  f:write(meta_json)
  f:close()
end

function M.add_from_text(text, meta)
  if not text or text == '' then return end
  if not M._path then M.setup() end
  if not has_pack then
    -- Delegate to JSONL store when binary pack/unpack is unavailable
    pcall(function() require('caramba.memory_vector').add_from_text(text, meta) end)
    return
  end
  embeddings.generate_embedding(text, function(vec, err)
    if not vec then
      logger.warn('memory_vector_bin: embedding failed', err)
      return
    end
    add_record(vec, meta or { snippet = text:sub(1, 200) })
  end)
end

local function cosine(a, b)
  local n = math.min(#a, #b)
  local dot, n1, n2 = 0, 0, 0
  for i = 1, n do
    local x, y = a[i], b[i]
    dot = dot + x * y
    n1 = n1 + x * x
    n2 = n2 + y * y
  end
  if n1 == 0 or n2 == 0 then return 0 end
  return dot / (math.sqrt(n1) * math.sqrt(n2))
end

function M.recall(query_text, top_k, callback)
  top_k = top_k or 5
  if not M._path then M.setup() end
  if not has_pack then
    pcall(function() require('caramba.memory_vector').recall(query_text, top_k, callback) end)
    return
  end
  embeddings.generate_embedding(query_text or '', function(qvec, err)
    if not qvec then callback({}, err); return end
    local f = io.open(M._path, 'rb')
    if not f then callback({}); return end
    local header = f:read(4)
    if not header or #header < 4 then f:close(); callback({}); return end
    local dim = string.unpack('>I4', header)
    local vec_bytes = dim * 4
    local results = {}
    while true do
      local vraw = f:read(vec_bytes)
      if not vraw or #vraw < vec_bytes then break end
      local vec = {}
      for i = 1, dim do
        local val = string.unpack('<f', vraw, (i - 1) * 4 + 1)
        vec[i] = val
      end
      local len_raw = f:read(4)
      if not len_raw or #len_raw < 4 then break end
      local mlen = string.unpack('>I4', len_raw)
      local mjson = f:read(mlen)
      if not mjson or #mjson < mlen then break end
      local ok, meta = pcall(vim.json.decode, mjson)
      if not ok then meta = { raw = mjson } end
      local score = cosine(qvec, vec)
      table.insert(results, { score = score, meta = meta })
    end
    f:close()
    table.sort(results, function(a, b) return a.score > b.score end)
    local out = {}
    for i = 1, math.min(top_k, #results) do out[i] = results[i] end
    callback(out)
  end)
end

return M


