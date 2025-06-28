-- AI Assistant Configuration

local M = {}

-- Default configuration
M.defaults = {
  -- LLM Provider settings
  provider = "openai", -- "openai", "anthropic", "ollama", "custom"
  
  -- API settings
  api = {
    openai = {
      endpoint = "https://api.openai.com/v1/chat/completions",
      model = "gpt-4o-mini",
      temperature = 0.3,
      max_tokens = 4096,
      api_key = vim.env.OPENAI_API_KEY,
    },
    anthropic = {
      endpoint = "https://api.anthropic.com/v1/messages",
      model = "claude-3-sonnet-20240229",
      temperature = 0.3,
      max_tokens = 4096,
      api_key = vim.env.ANTHROPIC_API_KEY,
    },
    ollama = {
      endpoint = "http://localhost:11434/api/generate",
      model = "codellama",
      temperature = 0.3,
    },
  },
  
  -- Context extraction settings
  context = {
    max_bytes = 8000,           -- Maximum bytes for context
    max_lines = 200,            -- Maximum lines to include
    include_imports = true,     -- Include import statements
    include_comments = true,    -- Include comments in context
    include_siblings = false,   -- Include sibling functions/classes
    search_radius = 2,          -- Hops in symbol graph for context
  },
  
  -- Editing settings
  editing = {
    validate_syntax = true,     -- Validate syntax before applying edits
    auto_format = true,         -- Auto-format after edits
    safe_mode = true,           -- Enable rollback on syntax errors
    diff_preview = true,        -- Preview diffs before applying
  },
  
  -- Search and indexing
  search = {
    enable_index = true,        -- Enable search indexing
    index_on_startup = false,   -- Index workspace on startup
    max_file_size = 100000,     -- Skip files larger than this
    exclude_patterns = {        -- Patterns to exclude from indexing
      "%.git/",
      "node_modules/",
      "%.venv/",
      "venv/",
      "__pycache__/",
      "%.min%.js$",
      "%.min%.css$",
      "dist/",
      "build/",
    },
    use_embeddings = false, -- Enable embeddings-based search
    embedding_chunk_size = 50, -- Lines per chunk for embedding
    embedding_model = "text-embedding-3-small", -- OpenAI embedding model (3-small or 3-large)
    embedding_dimensions = 512, -- Dimensions for embeddings (lower = faster/cheaper, max: 1536 for small, 3072 for large)
  },
  
  -- Feature toggles
  features = {
    enable_search_index = true,
    enable_auto_context = true,
    track_cursor_context = true,
    enable_completions = true,
    enable_refactoring = true,
    enable_explanations = true,
  },
  
  -- UI settings
  ui = {
    diff_highlights = true,
    progress_notifications = true,
    floating_window_border = "rounded",
    preview_window_width = 0.6,
    preview_window_height = 0.8,
  },
  
  -- Performance settings
  performance = {
    debounce_ms = 150,          -- Debounce for context updates
    max_concurrent_requests = 2, -- Max concurrent LLM requests
    cache_responses = true,      -- Cache LLM responses
    cache_ttl_seconds = 3600,    -- Cache TTL
    request_timeout_ms = 30000, -- 30 seconds default
  },
  
  -- Web search settings
  web_search = {
    default_provider = "duckduckgo", -- duckduckgo, google, brave
    result_limit = 5,
    -- API keys for search providers (can also use env vars)
    api_keys = {
      google = nil, -- Uses GOOGLE_API_KEY env var if nil
      google_search_engine_id = nil, -- Uses GOOGLE_SEARCH_ENGINE_ID env var if nil
      brave = nil, -- Uses BRAVE_API_KEY env var if nil
    },
  },
  
  -- Planning settings
}

-- Current configuration
M.options = {}

-- Setup configuration
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
  
  -- Validate configuration
  M._validate()
  
  -- Set up global namespace
  _G.ai_assistant = _G.ai_assistant or {}
  _G.ai_assistant.config = M.options
end

-- Validate configuration
function M._validate()
  -- Check API keys
  local provider = M.options.provider
  if provider == "openai" and not M.options.api.openai.api_key then
    vim.notify("AI: OpenAI API key not found. Set OPENAI_API_KEY environment variable.", vim.log.levels.WARN)
  elseif provider == "anthropic" and not M.options.api.anthropic.api_key then
    vim.notify("AI: Anthropic API key not found. Set ANTHROPIC_API_KEY environment variable.", vim.log.levels.WARN)
  end
  
  -- Validate numeric values
  assert(M.options.context.max_bytes > 0, "context.max_bytes must be positive")
  assert(M.options.context.max_lines > 0, "context.max_lines must be positive")
  assert(M.options.performance.debounce_ms >= 0, "performance.debounce_ms must be non-negative")
end

-- Get current configuration
function M.get()
  return M.options
end

-- Update configuration
function M.update(path, value)
  local keys = vim.split(path, ".", { plain = true })
  local current = M.options
  
  for i = 1, #keys - 1 do
    current = current[keys[i]]
    if not current then
      error("Invalid configuration path: " .. path)
    end
  end
  
  current[keys[#keys]] = value
end

return M 