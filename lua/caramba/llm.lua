-- LLM Integration Module
-- Supports multiple LLM providers with async operations

local M = {}
local Job = require("plenary.job")
local config = require("caramba.config")

-- Response cache
M._cache = {}
M._active_requests = {}
M._active_jobs = {}
M._request_queue = {}
M._max_concurrent = 3
M._processing_queue = false

-- Provider implementations
M.providers = {}

-- OpenAI provider
M.providers.openai = {
  prepare_request = function(prompt, opts)
    local api_config = config.get().api.openai
    opts = vim.tbl_extend("force", {
      model = api_config.model,
      temperature = api_config.temperature,
      max_tokens = api_config.max_tokens,
    }, opts or {})
    
    local messages = type(prompt) == "string" 
      and {{ role = "user", content = prompt }}
      or prompt
    
    local body = {
      model = opts.model,
      messages = messages,
      temperature = opts.temperature,
      max_tokens = opts.max_tokens,
      stream = false,
    }
    
    -- Handle JSON response format
    if opts.response_format then
      if opts.response_format.type == "json_schema" then
        -- Use structured outputs for schema-based responses
        body.response_format = opts.response_format
      elseif opts.response_format.type == "json_object" then
        -- Use simple JSON mode
        body.response_format = { type = "json_object" }
      end
    end
    
    return {
      url = api_config.endpoint,
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_config.api_key,
      },
      body = vim.json.encode(body),
    }
  end,
  
  parse_response = function(response_text)
    local ok, data = pcall(vim.json.decode, response_text)
    if not ok then
      return nil, "Failed to parse response: " .. response_text
    end
    
    if data.error then
      return nil, data.error.message or "Unknown error"
    end
    
    if data.choices and data.choices[1] and data.choices[1].message then
      return data.choices[1].message.content, nil
    end
    
    return nil, "Invalid response format"
  end,
}

-- Anthropic provider
M.providers.anthropic = {
  prepare_request = function(prompt, opts)
    local api_config = config.get().api.anthropic
    opts = vim.tbl_extend("force", {
      model = api_config.model,
      temperature = api_config.temperature,
      max_tokens = api_config.max_tokens,
    }, opts or {})
    
    local messages = type(prompt) == "string"
      and {{ role = "user", content = prompt }}
      or prompt
    
    -- Convert from OpenAI format if needed
    local anthropic_messages = {}
    for _, msg in ipairs(messages) do
      if msg.role == "system" then
        -- Anthropic uses system as a separate field
        opts.system = msg.content
      else
        table.insert(anthropic_messages, {
          role = msg.role,
          content = msg.content,
        })
      end
    end
    
    local body = {
      model = opts.model,
      messages = anthropic_messages,
      temperature = opts.temperature,
      max_tokens = opts.max_tokens,
    }
    
    if opts.system then
      body.system = opts.system
    end
    
    return {
      url = api_config.endpoint,
      headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = api_config.api_key,
        ["anthropic-version"] = "2023-06-01",
      },
      body = vim.json.encode(body),
    }
  end,
  
  parse_response = function(response_text)
    local ok, data = pcall(vim.json.decode, response_text)
    if not ok then
      return nil, "Failed to parse response: " .. response_text
    end
    
    if data.error then
      return nil, data.error.message or "Unknown error"
    end
    
    if data.content and data.content[1] and data.content[1].text then
      return data.content[1].text, nil
    end
    
    return nil, "Invalid response format"
  end,
}

-- Ollama provider
M.providers.ollama = {
  prepare_request = function(prompt, opts)
    local api_config = config.get().api.ollama
    opts = vim.tbl_extend("force", {
      model = api_config.model,
      temperature = api_config.temperature,
    }, opts or {})
    
    local prompt_text = type(prompt) == "string" 
      and prompt
      or M._messages_to_text(prompt)
    
    return {
      url = api_config.endpoint,
      headers = {
        ["Content-Type"] = "application/json",
      },
      body = vim.json.encode({
        model = opts.model,
        prompt = prompt_text,
        temperature = opts.temperature,
        stream = false,
      }),
    }
  end,
  
  parse_response = function(response_text)
    local ok, data = pcall(vim.json.decode, response_text)
    if not ok then
      return nil, "Failed to parse response: " .. response_text
    end
    
    if data.error then
      return nil, data.error or "Unknown error"
    end
    
    if data.response then
      return data.response, nil
    end
    
    return nil, "Invalid response format"
  end,
}

-- Convert messages array to text for providers that don't support chat format
function M._messages_to_text(messages)
  local parts = {}
  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      table.insert(parts, "System: " .. msg.content)
    elseif msg.role == "user" then
      table.insert(parts, "User: " .. msg.content)
    elseif msg.role == "assistant" then
      table.insert(parts, "Assistant: " .. msg.content)
    end
  end
  return table.concat(parts, "\n\n")
end

-- Helper to generate cache key
function M._generate_cache_key(provider_name, prompt, opts)
  -- Use a simple string concatenation for cache key to avoid vim.fn calls in fast context
  local key_string = provider_name .. "|" .. vim.inspect(prompt) .. "|" .. vim.inspect(opts)
  -- Simple hash function
  local hash = 0
  for i = 1, #key_string do
    hash = (hash * 31 + string.byte(key_string, i)) % 2147483647
  end
  return tostring(hash)
end

-- Process queued requests
local function process_queue()
  -- Use iterative approach instead of recursion
  while #M._request_queue > 0 and vim.tbl_count(M._active_requests) < M._max_concurrent do
    local queued = table.remove(M._request_queue, 1)
    if queued then
      -- Process the queued request
      local function on_complete(response)
        queued.callback(response)
      end
      
      -- Re-submit the request
      if queued.stream then
        M.request_stream(queued.prompt, queued.opts, on_complete)
      else
        M.request(queued.prompt, queued.opts, on_complete)
      end
    end
  end
end

-- Make an LLM request
M.request = function(messages, opts, callback)
  opts = opts or {}
  local provider = opts.provider or config.get().provider
  
  -- Validate API key for providers that need it
  local api_config = config.get().api[provider]
  if provider == "openai" and not api_config.api_key then
    vim.schedule(function()
      callback(nil, "OpenAI API key not set. Please set OPENAI_API_KEY environment variable.")
    end)
    return
  elseif provider == "anthropic" and not api_config.api_key then
    vim.schedule(function()
      callback(nil, "Anthropic API key not set. Please set ANTHROPIC_API_KEY environment variable.")
    end)
    return
  end
  
  -- Check if we're at the concurrent limit
  if vim.tbl_count(M._active_requests) >= M._max_concurrent then
    -- Queue the request instead of rejecting
    table.insert(M._request_queue, {
      prompt = messages,  -- Changed from 'messages' to 'prompt' for consistency
      opts = opts,
      callback = callback,
      stream = false,
    })
    vim.schedule(function()
      vim.notify("AI: Request queued due to rate limiting. Queue size: " .. #M._request_queue, vim.log.levels.INFO)
    end)
    return
  end
  
  -- Check cache if enabled
  local cache_key = nil
  if config.get().performance.cache_responses then
    cache_key = M._generate_cache_key(provider, messages, opts)
    local cached = M._cache[cache_key]
    if cached and (os.time() - cached.time) < config.get().performance.cache_ttl_seconds then
      callback(cached.response, nil)
      return
    end
  end
  
  -- Prepare request
  local request_data = M.providers[provider].prepare_request(messages, opts)
  
  -- Generate unique request ID
  local request_id = tostring(os.time()) .. "_" .. math.random(10000)
  
  -- Track active request and job
  M._active_requests[request_id] = true
  
  -- Build curl command
  local curl_args = {
    "-sS",
    request_data.url,
    "-X", "POST",
    "--max-time", "30", -- Add timeout to prevent hanging
  }
  
  for header, value in pairs(request_data.headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, header .. ": " .. value)
  end
  
  table.insert(curl_args, "-d")
  table.insert(curl_args, request_data.body)
  
  -- Debug logging
  if config.get().debug then
    vim.schedule(function()
      vim.notify("AI: Curl command: curl " .. table.concat(curl_args, " "), vim.log.levels.INFO)
      vim.notify("AI: Request URL: " .. request_data.url, vim.log.levels.INFO)
    end)
  end
  
  local buffer = ""
  
  -- Create job
  local job = Job:new({
    command = "curl",
    args = curl_args,
    on_exit = function(j, return_val)
      -- Remove from active requests and jobs
      M._active_requests[request_id] = nil
      M._active_jobs[request_id] = nil
      
      if return_val and return_val ~= 0 then
        vim.schedule(function()
          callback(nil, "Request failed with code: " .. tostring(return_val))
        end)
        -- Process any queued requests
        process_queue()
        return
      elseif not return_val then
        vim.schedule(function()
          callback(nil, "Request terminated unexpectedly")
        end)
        -- Process any queued requests
        process_queue()
        return
      end
      
      local response = table.concat(j:result(), "\n")
      local result, err = M.providers[provider].parse_response(response)
      
      if result and cache_key then
        -- Cache successful response
        M._cache[cache_key] = {
          response = result,
          time = os.time(),
        }
      end
      
      vim.schedule(function()
        callback(result, err)
      end)
      
      -- Process any queued requests
      process_queue()
    end,
  })
  
  -- Track the job before starting
  M._active_jobs[request_id] = job
  
  -- Debug logging
  if config.get().debug then
    vim.schedule(function()
      vim.notify(string.format("AI: Starting request to %s (ID: %s)", provider, request_id), vim.log.levels.INFO)
    end)
  end
  
  -- Start job
  job:start()
  
  -- Clear request on timeout
  local timeout_ms = config.get().performance.request_timeout_ms or 30000
  vim.defer_fn(function()
    if M._active_requests[request_id] then
      M._active_requests[request_id] = nil
      if M._active_jobs[request_id] then
        M._active_jobs[request_id]:shutdown()
        M._active_jobs[request_id] = nil
      end
      vim.schedule(function()
        callback(nil, "Request timeout")
      end)
      process_queue()
    end
  end, timeout_ms)
end

-- Synchronous request (blocks until complete)
M.request_sync = function(prompt, opts)
  opts = opts or {}
  local result = nil
  local done = false
  
  M.request(prompt, opts, function(response)
    result = response
    done = true
  end)
  
  -- Wait for completion (with timeout)
  local timeout = opts.timeout or 30000 -- 30 seconds
  local start = vim.loop.now()
  
  while not done and (vim.loop.now() - start) < timeout do
    vim.wait(10) -- Wait 10ms
  end
  
  return result
end

-- Build a prompt for code completion
function M.build_completion_prompt(context, instruction)
  local system_prompt = [[You are an expert programmer providing code completions. 

CRITICAL RULES:
1. Generate ONLY the code to be inserted at the cursor position
2. Do NOT include code that already exists in the context
3. Ensure proper indentation matching the surrounding code
4. Complete partial statements or add new code as requested
5. The code must be syntactically valid when inserted at the cursor
6. Pay attention to:
   - Open parentheses, brackets, or braces that need closing
   - Current indentation level
   - Whether you're inside a function, class, or other scope
   - Language-specific syntax requirements

Follow the existing code style and conventions.]]
  
  local user_prompt = string.format([[
Context:
%s

Instruction: %s

Generate only the code to insert at the cursor position. The cursor is at the end of the provided context.
]], context, instruction or "Complete the code at the cursor position")
  
  return {
    { role = "system", content = system_prompt },
    { role = "user", content = user_prompt },
  }
end

-- Build a prompt for refactoring
function M.build_refactor_prompt(code, instruction)
  local system_prompt = [[You are an expert programmer. Refactor the provided code according to the instructions. 
Maintain the same functionality while improving code quality. Output only the refactored code.]]
  
  return {
    { role = "system", content = system_prompt },
    { role = "user", content = code .. "\n\nRefactoring instruction: " .. instruction },
  }
end

-- Build a prompt for explanation
function M.build_explanation_prompt(code, question)
  local system_prompt = [[You are an expert programmer and teacher. Explain the code clearly and concisely.
Use examples when helpful. Format your response in markdown.]]
  
  local user_prompt = code
  if question then
    user_prompt = user_prompt .. "\n\nQuestion: " .. question
  end
  
  return {
    { role = "system", content = system_prompt },
    { role = "user", content = user_prompt },
  }
end

-- Clear response cache
function M.clear_cache()
  M._cache = {}
end

-- Cancel all active requests
function M.cancel_all()
  for request_id, job in pairs(M._active_jobs) do
    if job then
      job:shutdown()
    end
  end
  M._active_requests = {}
  M._active_jobs = {}
  M._request_queue = {}
end

-- Simple completion helper (for backward compatibility)
M.complete = function(prompt, callback)
  local messages = {
    { role = "user", content = prompt }
  }
  return M.request(messages, {}, callback)
end

-- Make an LLM request with optional streaming
M.request_stream = function(messages, opts, on_chunk, on_complete)
  opts = opts or {}
  local provider = opts.provider or config.get().provider
  
  -- Validate API key for providers that need it
  local api_config = config.get().api[provider]
  if provider == "openai" and not api_config.api_key then
    vim.schedule(function()
      on_complete(nil, "OpenAI API key not set. Please set OPENAI_API_KEY environment variable.")
    end)
    return
  elseif provider == "anthropic" and not api_config.api_key then
    vim.schedule(function()
      on_complete(nil, "Anthropic API key not set. Please set ANTHROPIC_API_KEY environment variable.")
    end)
    return
  end
  
  -- Only OpenAI supports streaming currently
  if provider ~= "openai" then
    -- Fall back to regular request
    M.request(messages, opts, function(result, err)
      if result then
        on_chunk(result)
      end
      on_complete(result, err)
    end)
    return
  end
  
  -- Prepare streaming request
  local request_data = M.providers[provider].prepare_request(messages, opts)
  local body = vim.json.decode(request_data.body)
  body.stream = true
  request_data.body = vim.json.encode(body)
  
  -- Build curl command for streaming
  local curl_args = {
    "-sS",
    "-N", -- No buffering for streaming
    request_data.url,
    "-X", "POST",
    "--max-time", "30", -- Add timeout to prevent hanging
  }
  
  for header, value in pairs(request_data.headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, header .. ": " .. value)
  end
  
  table.insert(curl_args, "-d")
  table.insert(curl_args, request_data.body)
  
  -- Debug logging
  if config.get().debug then
    vim.schedule(function()
      vim.notify("AI: Curl command: curl " .. table.concat(curl_args, " "), vim.log.levels.INFO)
      vim.notify("AI: Request body: " .. string.sub(request_data.body, 1, 200) .. "...", vim.log.levels.INFO)
    end)
  end
  
  -- Generate unique request ID
  local request_id = tostring(os.time()) .. "_" .. math.random(10000)
  
  -- Track active request
  M._active_requests[request_id] = true
  
  local accumulated_content = ""
  local buffer = ""
  
  -- Debug logging
  if config.get().debug then
    vim.notify("AI: Starting streaming request to " .. provider, vim.log.levels.INFO)
  end
  
  -- Create streaming job
  local job = Job:new({
    command = "curl",
    args = curl_args,
    on_stdout = function(_, data)
      if not data then return end
      
      buffer = buffer .. data
      
      -- Process SSE events - they are separated by double newlines
      while true do
        -- Find the next complete event (ends with \n\n)
        local event_end = buffer:find("\n\n", 1, true)
        if not event_end then
          -- No complete event yet
          break
        end
        
        -- Extract the event
        local event = buffer:sub(1, event_end - 1)
        buffer = buffer:sub(event_end + 2) -- Skip the \n\n
        
        -- Process each line in the event
        for line in event:gmatch("[^\n]+") do
          if line:match("^data: ") then
            local data_content = line:sub(7) -- Remove "data: " prefix
            
            if data_content == "[DONE]" then
              vim.schedule(function()
                on_complete(accumulated_content, nil)
              end)
            else
              -- Parse the JSON data
              local ok, chunk_data = pcall(vim.json.decode, data_content)
              if ok and chunk_data then
                if chunk_data.choices and chunk_data.choices[1] then
                  local delta = chunk_data.choices[1].delta
                  if delta and delta.content then
                    accumulated_content = accumulated_content .. delta.content
                    vim.schedule(function()
                      on_chunk(delta.content)
                    end)
                  end
                elseif chunk_data.error then
                  -- Handle API errors
                  vim.schedule(function()
                    on_complete(nil, chunk_data.error.message or "Unknown API error")
                  end)
                  return
                end
              elseif not ok and config.get().debug then
                vim.schedule(function()
                  vim.notify("AI: Failed to parse chunk: " .. vim.inspect(data_content), vim.log.levels.WARN)
                end)
              end
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          vim.notify("AI: Curl error: " .. data, vim.log.levels.ERROR)
        end)
      end
    end,
    on_exit = function(j, return_val)
      -- Clean up tracking
      M._active_requests[request_id] = nil
      M._active_jobs[request_id] = nil
      
      if return_val and return_val ~= 0 then
        vim.schedule(function()
          local error_msg = "Stream failed with code: " .. tostring(return_val)
          if return_val == 28 then
            error_msg = "Request timed out"
          elseif return_val == 7 then
            error_msg = "Failed to connect to API"
          end
          on_complete(nil, error_msg)
        end)
      elseif not return_val then
        vim.schedule(function()
          on_complete(nil, "Stream terminated unexpectedly")
        end)
      end
      
      -- Process any queued requests
      process_queue()
    end,
  })
  
  -- Track the job before starting
  M._active_jobs[request_id] = job
  
  -- Debug logging
  if config.get().debug then
    vim.schedule(function()
      vim.notify(string.format("AI: Starting request to %s (ID: %s)", provider, request_id), vim.log.levels.INFO)
    end)
  end
  
  -- Start job
  job:start()
  
  -- Add timeout handling
  local timeout_ms = config.get().performance.request_timeout_ms or 30000
  vim.defer_fn(function()
    if M._active_requests[request_id] then
      M._active_requests[request_id] = nil
      if M._active_jobs[request_id] then
        M._active_jobs[request_id]:shutdown()
        M._active_jobs[request_id] = nil
      end
      vim.schedule(function()
        on_complete(nil, "Stream timeout")
      end)
      process_queue()
    end
  end, timeout_ms)
  
  return job
end

-- Request a conversation (multi-turn chat)
M.request_conversation = function(messages, opts, callback)
  opts = opts or {}
  
  -- Use streaming if requested
  if opts.stream then
    -- For streaming, we need to wrap the single callback into two separate handlers
    local on_chunk = function(chunk)
      callback(chunk, false) -- Not complete yet
    end
    local on_complete = function(result, err)
      if err then
        -- Signal error
        callback(nil, false)
        vim.schedule(function()
          vim.notify("AI Error: " .. err, vim.log.levels.ERROR)
        end)
      else
        -- Signal completion with nil chunk and true for is_complete
        callback(nil, true)
      end
    end
    
    return M.request_stream(messages, opts, on_chunk, on_complete)
  else
    return M.request(messages, opts, function(result, err)
      if err then
        vim.schedule(function()
          vim.notify("AI Error: " .. err, vim.log.levels.ERROR)
        end)
        callback(nil, true)
      else
        callback(result, true)
      end
    end)
  end
end

return M 