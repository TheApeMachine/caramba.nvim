-- LLM Integration Module
-- Supports multiple LLM providers with async operations

local M = {}
local Job = require("plenary.job")
local config = require("caramba.config")
local utils = require("caramba.utils")
local logger = require("caramba.logger")

-- Response cache
M._cache = {}
M._active_requests = {}
M._active_jobs = {}
M._request_queue = {}
M._max_concurrent = 3
M._processing_queue = false
M._streaming_jobs = {}

-- Provider implementations
M.providers = {}

-- Task-aware model selection (router)
-- opts.task: 'chat' | 'plan' | 'refactor' | 'search' | 'explain' | 'tdd'
local function select_provider_and_model(opts)
  local cfg = config.get()
  local provider = (opts and opts.provider) or cfg.provider
  local api = cfg.api
  local task = opts and opts.task or 'chat'

  -- Default: current provider
  local chosen_provider = provider
  local chosen_model = api[provider] and api[provider].model

  -- Heuristics: route heavy tasks to more capable models if available
  local function has(p)
    return api[p] and api[p].api_key and api[p].models and #api[p].models > 0
  end

  local function prefer(p, model)
    chosen_provider = p
    if model then
      chosen_model = model
    else
      chosen_model = api[p].model
    end
  end

  if task == 'plan' or task == 'refactor' or task == 'tdd' then
    if provider == 'openai' then
      -- Prefer higher-capability OpenAI model if listed
      local models = api.openai.models or {}
      for _, m in ipairs(models) do
        if m:match('^o3') or m:match('^gpt%-4%.?') or m:match('^o4') then
          chosen_model = m
          break
        end
      end
    elseif has('anthropic') then
      prefer('anthropic')
    end
  elseif task == 'search' or task == 'explain' or task == 'chat' then
    -- Prefer cheaper/faster models when possible
    if provider == 'openai' then
      local models = api.openai.models or {}
      for _, m in ipairs(models) do
        if m:match('mini') or m:match('flash') then
          chosen_model = m
          break
        end
      end
    elseif has('ollama') then
      prefer('ollama')
    end
  end

  return chosen_provider, chosen_model
end

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
      max_completion_tokens = opts.max_tokens,
      stream = false,
    }

    -- Add tools if provided
    if opts.tools then
      body.tools = opts.tools
    end

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

-- Google Gemini provider (using OpenAI compatible endpoint)
M.providers.google = {
  prepare_request = function(prompt, opts)
    local api_config = config.get().api.google
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
      max_completion_tokens = opts.max_tokens,
      stream = false,
    }

    return {
      url = api_config.endpoint .. "/openai/chat/completions",
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_config.api_key,
      },
      body = vim.json.encode(body),
    }
  end,

  -- The response format is OpenAI-compatible
  parse_response = M.providers.openai.parse_response,
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
  local routed_provider, routed_model = select_provider_and_model(opts)
  local provider = routed_provider
  if routed_model then
    opts = vim.tbl_extend('force', opts, { model = routed_model })
  end

  -- Guard unsupported/experimental providers
  if provider == "google" then
    local api = config.get().api
    local compat = api and api.google and api.google.compatibility_mode
    if not compat then
      vim.schedule(function()
        callback(nil, "Google provider is disabled. Enable api.google.compatibility_mode=true to use the experimental OpenAI-compatible endpoint.")
      end)
      return
    end
  end

  -- Default to streaming for faster feedback
  local use_streaming = opts.stream ~= false
  if use_streaming then
    local stream_ui
    if config.get().ui.stream_window then
      stream_ui = utils.create_stream_window("AI Response")
      if not stream_ui or not stream_ui.append then
        vim.schedule(function()
          vim.notify("Failed to create stream window", vim.log.levels.WARN)
        end)
        stream_ui = nil
      end
    end

    if config.get().ui.progress_notifications then
      vim.schedule(function()
        vim.notify("AI: Streaming response...", vim.log.levels.INFO)
      end)
    end

    local parts = {}
    local function on_chunk(chunk)
      if chunk then
        table.insert(parts, chunk)
        if stream_ui then
          vim.schedule(function()
            stream_ui.append(chunk)
          end)
        end
      end
    end
    local function on_complete(_, err)
      if stream_ui then
        vim.schedule(function()
          if err then
            stream_ui.lock()
          else
            stream_ui.close()
          end
        end)
      end

      if err then
        callback(nil, err)
      else
        callback(table.concat(parts, ""), err)
      end
    end

    return M.request_stream(messages, opts, on_chunk, on_complete)
  end

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
  elseif provider == "google" and not api_config.api_key then
    vim.schedule(function()
      callback(nil, "Google API key not set. Please set GOOGLE_API_KEY environment variable.")
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

  -- Debug logging (with redaction)
  if config.get().debug then
    local function redact_args(args)
      local redacted = {}
      local i = 1
      while i <= #args do
        local val = args[i]
        if val == "-H" and args[i+1] then
          local header = args[i+1]
          if type(header) == "string" and header:lower():match("authorization:%s*bearer%s+") then
            table.insert(redacted, "-H")
            table.insert(redacted, "Authorization: Bearer ***")
            i = i + 2
          else
            table.insert(redacted, "-H")
            table.insert(redacted, header)
            i = i + 2
          end
        elseif val == "-d" and args[i+1] then
          table.insert(redacted, "-d")
          table.insert(redacted, "<omitted JSON body>")
          i = i + 2
        else
          table.insert(redacted, val)
          i = i + 1
        end
      end
      return redacted
    end
    logger.debug("LLM request curl args", redact_args(vim.deepcopy(curl_args)))
    logger.debug("LLM request URL", request_data.url)
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
  logger.info(string.format("LLM request start provider=%s id=%s", provider, request_id))

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
  local provider = opts.provider or config.get().provider

  -- Validate API key
  local api_config = config.get().api[provider]
  if provider == "openai" and not (api_config and api_config.api_key) then
    vim.notify("OpenAI API key not set.", vim.log.levels.ERROR)
    return nil
  elseif provider == "anthropic" and not (api_config and api_config.api_key) then
    vim.notify("Anthropic API key not set.", vim.log.levels.ERROR)
    return nil
  elseif provider == "google" and not (api_config and api_config.api_key) then
    vim.notify("Google API key not set.", vim.log.levels.ERROR)
    return nil
  end

  -- Prepare request
  local request_data = M.providers[provider].prepare_request(prompt, opts)

  -- Build curl command
  local curl_args = {
    "-sS",
    request_data.url,
    "-X", "POST",
    "--max-time", "15", -- Shorter timeout for sync requests
  }

  for header, value in pairs(request_data.headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, header .. ": " .. value)
  end

  table.insert(curl_args, "-d")
  table.insert(curl_args, request_data.body)

  local job = Job:new({
    command = "curl",
    args = curl_args,
  })

  local stdout, stderr, code = job:sync()

  if code ~= 0 then
    local err_msg = "LLM sync request failed with code " .. tostring(code)
    if stderr and #stderr > 0 and stderr[1] ~= "" then
      err_msg = err_msg .. ": " .. table.concat(stderr, " ")
    end
    vim.notify(err_msg, vim.log.levels.ERROR)
    return nil
  end

  if not stdout or #stdout == 0 then
    vim.notify("LLM sync request returned empty response.", vim.log.levels.ERROR)
    return nil
  end

  local response_text = table.concat(stdout, "\n")
  local result, err = M.providers[provider].parse_response(response_text)

  if err then
    vim.notify("LLM sync request failed to parse response: " .. err, vim.log.levels.ERROR)
    return nil
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
      if job.id then
        vim.fn.jobstop(job.id)
      elseif job.shutdown then
        -- Legacy plenary job
        job:shutdown()
      end
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
  local routed_provider, routed_model = select_provider_and_model(opts)
  local provider = routed_provider
  if routed_model then
    opts = vim.tbl_extend('force', opts, { model = routed_model })
  end

  -- Guard unsupported/experimental providers
  if provider == "google" then
    local api = config.get().api
    local compat = api and api.google and api.google.compatibility_mode
    if not compat then
      vim.schedule(function()
        on_complete(nil, "Google provider is disabled. Enable api.google.compatibility_mode=true to use the experimental OpenAI-compatible endpoint.")
      end)
      return
    end
  end

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
  elseif provider == "google" and not api_config.api_key then
    vim.schedule(function()
      on_complete(nil, "Google API key not set. Please set GOOGLE_API_KEY environment variable.")
    end)
    return
  end

  -- Only OpenAI and Google (via compatibility layer) support streaming currently
  if provider ~= "openai" and provider ~= "google" then
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

  -- Debug logging
  logger.info("LLM stream start provider=" .. provider)

  -- Build curl command using table for better shell escaping
  local curl_args = {
    "curl",
    "-sS",
    "-N",
    request_data.url,
    "-X", "POST",
    "--max-time", "30"
  }

  for header, value in pairs(request_data.headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, header .. ": " .. value)
  end

  table.insert(curl_args, "-d")
  table.insert(curl_args, request_data.body)

  -- Debug logging (with redaction)
  if config.get().debug then
    local function redact_args(args)
      local redacted = {}
      local i = 1
      while i <= #args do
        local val = args[i]
        if val == "-H" and args[i+1] then
          local header = args[i+1]
          if type(header) == "string" and header:lower():match("authorization:%s*bearer%s+") then
            table.insert(redacted, "-H")
            table.insert(redacted, "Authorization: Bearer ***")
            i = i + 2
          else
            table.insert(redacted, "-H")
            table.insert(redacted, header)
            i = i + 2
          end
        elseif val == "-d" and args[i+1] then
          table.insert(redacted, "-d")
          table.insert(redacted, "<omitted JSON body>")
          i = i + 2
        else
          table.insert(redacted, val)
          i = i + 1
        end
      end
      return redacted
    end
    logger.debug("LLM stream curl args", redact_args(vim.deepcopy(curl_args)))
  end

  -- Generate unique request ID
  local request_id = tostring(os.time()) .. "_" .. math.random(10000)

  -- Track active request
  M._active_requests[request_id] = true

  local accumulated_content = ""
  local buffer = ""

  -- Use vim's jobstart for better streaming support
  local job_id = vim.fn.jobstart(curl_args, {
    on_stdout = function(_, data, _)
      if not data or not M._active_requests[request_id] then return end

      for _, line in ipairs(data) do
        if line and line ~= "" then
          if line:match("^data: ") then
            local data_content = line:sub(7)

            if data_content == "[DONE]" then
                if M._active_requests[request_id] then
                  M._active_requests[request_id] = nil
                  vim.schedule(function()
                    on_complete(accumulated_content, nil)
                  end)
                  if M._active_jobs[request_id] and M._active_jobs[request_id].id then
                    pcall(vim.fn.jobstop, M._active_jobs[request_id].id)
                  end
                end
              return
            end

            local ok, chunk_data = pcall(vim.json.decode, data_content)
            if ok and chunk_data then
              if chunk_data.choices and chunk_data.choices[1] and chunk_data.choices[1].delta and chunk_data.choices[1].delta.content then
                local delta_content = chunk_data.choices[1].delta.content
                accumulated_content = accumulated_content .. delta_content
                vim.schedule(function()
                  on_chunk(delta_content)
                end)
              elseif chunk_data.error then
                if M._active_requests[request_id] then
                  M._active_requests[request_id] = nil
                  local err_msg = chunk_data.error.message or "Unknown API error in stream"
                  vim.schedule(function()
                    on_complete(nil, err_msg)
                  end)
                  if M._active_jobs[request_id] and M._active_jobs[request_id].id then
                    pcall(vim.fn.jobstop, M._active_jobs[request_id].id)
                  end
                end
                return
              end
            else
              -- Handle non-JSON data in stream, which could be an error message
              if config.get().debug then
                vim.schedule(function()
                  vim.notify("AI: Non-JSON data in stream: " .. data_content, vim.log.levels.WARN)
                end)
              end
            end
          else
            -- Line does not start with "data: ", could be an error from the API provider
            if config.get().debug then
              vim.schedule(function()
                vim.notify("AI: Received raw line in stream: " .. line, vim.log.levels.INFO)
              end)
            end
            -- Check if this raw line is a JSON error object
            local ok, err_data = pcall(vim.json.decode, line)
            if ok and err_data and err_data.error then
              if M._active_requests[request_id] then
                M._active_requests[request_id] = nil
                local err_msg = err_data.error.message or "Unknown API error in stream"
                vim.schedule(function()
                  on_complete(nil, err_msg)
                end)
                if M._active_jobs[request_id] and M._active_jobs[request_id].id then
                  pcall(vim.fn.jobstop, M._active_jobs[request_id].id)
                end
              end
              return
            end
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data and #data > 0 then
        local error_text = table.concat(data, "\n")
        if error_text ~= "" and M._active_requests[request_id] then
          logger.error("LLM stream curl stderr", error_text)
        end
      end
    end,
    on_exit = function(_, return_val, _)
      -- Clean up tracking, only if the request is still considered active
      if not M._active_requests[request_id] then
        process_queue()
        return
      end

      M._active_requests[request_id] = nil
      M._active_jobs[request_id] = nil

      -- Debug logging
      logger.info("LLM stream job exit", { code = return_val, content_len = #accumulated_content })

      if return_val and return_val ~= 0 and return_val ~= -15 -- -15 is SIGTERM from jobstop
      then
        vim.schedule(function()
          local error_msg = "Stream failed with code: " .. tostring(return_val)
          if return_val == 28 then
            error_msg = "Request timed out"
          elseif return_val == 7 then
            error_msg = "Failed to connect to API"
          end
          on_complete(nil, error_msg)
        end)
      elseif return_val == 0 and #accumulated_content == 0 then
        -- Success but no content received
        vim.schedule(function()
          vim.notify("AI: Stream completed but no content was received", vim.log.levels.WARN)
          on_complete(nil, "No response received from API")
        end)
      elseif accumulated_content ~= "" then
        -- The stream ended without a [DONE] message, but we have content
        vim.schedule(function()
          on_complete(accumulated_content, nil)
        end)
      end

      -- Process any queued requests
      process_queue()
    end,
  })

  -- Track the job
  M._active_jobs[request_id] = { id = job_id }

  -- Add timeout handling
  local timeout_ms = config.get().performance.request_timeout_ms or 30000
  vim.defer_fn(function()
    if M._active_requests[request_id] then
      M._active_requests[request_id] = nil
      if M._active_jobs[request_id] then
        vim.fn.jobstop(M._active_jobs[request_id].id)
        M._active_jobs[request_id] = nil
      end
      vim.schedule(function()
        on_complete(nil, "Stream timeout")
      end)
      process_queue()
    end
  end, timeout_ms)

  return { id = job_id }
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

-- Interactively select a provider and model
M.select_model = function()
  local providers = {}
  for name, _ in pairs(config.get().api) do
    table.insert(providers, name)
  end

  vim.ui.select(providers, {
    prompt = "Select AI Provider:",
  }, function(provider)
    if not provider then return end

    local models = config.get().api[provider].models or {}
    if #models == 0 then
      vim.notify("No models configured for provider: " .. provider, vim.log.levels.WARN)
      return
    end

    vim.ui.select(models, {
      prompt = "Select Model for " .. provider .. ":",
    }, function(model)
      if not model then return end

      -- Update the config
      config.update("provider", provider)
      config.update("api." .. provider .. ".model", model)

      vim.notify(string.format("Set AI provider to %s and model to %s", provider, model), vim.log.levels.INFO)
    end)
  end)
end

-- Note: chat_stream function removed - use request_stream instead

M.setup_commands = function()
  local commands = require('caramba.core.commands')

  commands.register('SetModel', M.select_model, {
    desc = 'Select the AI provider and model to use',
  })

  commands.register('ShowConfig', function()
    vim.notify(vim.inspect(config.get()), vim.log.levels.INFO)
  end, {
    desc = 'Show the current AI assistant configuration',
  })
end

return M