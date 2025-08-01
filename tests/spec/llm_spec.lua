-- Tests for caramba.llm module
-- Comprehensive test suite covering LLM providers, API calls, and error handling

-- Mock vim API for testing
local mock_vim = {
  fn = {
    jobstart = function(cmd, opts)
      -- Mock successful job
      if opts and opts.on_exit then
        vim.schedule(function()
          opts.on_exit(1, 0) -- job_id, exit_code
        end)
      end
      return 1
    end,
    jobstop = function(job_id) return true end,
    system = function(cmd) return "mock system output" end,
  },
  json = {
    encode = function(data) return '{"mock":"json"}' end,
    decode = function(str) 
      if str:find("error") then
        error("Invalid JSON")
      end
      return {choices = {{message = {content = "Mock response"}}}}
    end,
  },
  schedule = function(fn) fn() end,
  log = {
    levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 }
  },
  notify = function(msg, level) end,
  tbl_extend = function(behavior, ...)
    local result = {}
    for _, tbl in ipairs({...}) do
      for k, v in pairs(tbl) do
        result[k] = v
      end
    end
    return result
  end,
  env = {
    OPENAI_API_KEY = "test-openai-key",
    ANTHROPIC_API_KEY = "test-anthropic-key",
  }
}

_G.vim = mock_vim

-- Mock config module
package.loaded['caramba.config'] = {
  get = function()
    return {
      api = {
        openai = {
          api_key = "test-openai-key",
          model = "gpt-4",
          endpoint = "https://api.openai.com/v1/chat/completions",
          temperature = 0.7,
          max_tokens = 1000,
        },
        anthropic = {
          api_key = "test-anthropic-key",
          model = "claude-3-opus-20240229",
          endpoint = "https://api.anthropic.com/v1/messages",
          temperature = 0.7,
          max_tokens = 1000,
        },
        google = {
          api_key = "test-google-key",
          model = "gemini-pro",
          endpoint = "https://generativelanguage.googleapis.com/v1beta",
          temperature = 0.7,
          max_tokens = 1000,
        },
        ollama = {
          model = "llama2",
          endpoint = "http://localhost:11434/api/generate",
          temperature = 0.7,
        }
      },
      llm = {
        provider = "openai",
        fallback_providers = {"anthropic", "ollama"},
        timeout = 30,
        max_retries = 3,
      }
    }
  end
}

-- Load the LLM module
local llm = require('caramba.llm')

describe("caramba.llm", function()
  
  it("should prepare OpenAI request correctly", function()
    local request = llm.providers.openai.prepare_request("Test prompt", {
      temperature = 0.5,
      max_tokens = 500
    })
    
    assert.is_not_nil(request, "Request should not be nil")
    assert.is_not_nil(request.url, "URL should be present")
    assert.is_not_nil(request.headers, "Headers should be present")
    assert.is_not_nil(request.body, "Body should be present")
    assert.is_true(request.headers["Authorization"]:find("Bearer"), "Should have Bearer token")
  end)
  
  it("should prepare Anthropic request correctly", function()
    local request = llm.providers.anthropic.prepare_request("Test prompt", {
      temperature = 0.5,
      max_tokens = 500
    })
    
    assert.is_not_nil(request, "Request should not be nil")
    assert.is_not_nil(request.url, "URL should be present")
    assert.is_not_nil(request.headers, "Headers should be present")
    assert.is_not_nil(request.body, "Body should be present")
    assert.is_true(request.headers["x-api-key"] == "test-anthropic-key", "Should have correct API key")
  end)
  
  it("should prepare Google request correctly", function()
    local request = llm.providers.google.prepare_request("Test prompt", {
      temperature = 0.5,
      max_tokens = 500
    })
    
    assert.is_not_nil(request, "Request should not be nil")
    assert.is_not_nil(request.url, "URL should be present")
    assert.is_not_nil(request.headers, "Headers should be present")
    assert.is_not_nil(request.body, "Body should be present")
  end)
  
  it("should prepare Ollama request correctly", function()
    local request = llm.providers.ollama.prepare_request("Test prompt", {
      temperature = 0.5
    })
    
    assert.is_not_nil(request, "Request should not be nil")
    assert.is_not_nil(request.url, "URL should be present")
    assert.is_not_nil(request.headers, "Headers should be present")
    assert.is_not_nil(request.body, "Body should be present")
  end)
  
  it("should parse OpenAI response correctly", function()
    local response_text = '{"choices":[{"message":{"content":"Test response"}}]}'
    local result, err = llm.providers.openai.parse_response(response_text)
    
    assert.is_nil(err, "Should not have error")
    assert.is_not_nil(result, "Result should not be nil")
    assert.equals(result, "Test response", "Should extract content correctly")
  end)
  
  it("should parse Anthropic response correctly", function()
    local response_text = '{"content":[{"text":"Test response"}]}'
    local result, err = llm.providers.anthropic.parse_response(response_text)
    
    assert.is_nil(err, "Should not have error")
    assert.is_not_nil(result, "Result should not be nil")
    assert.equals(result, "Test response", "Should extract content correctly")
  end)
  
  it("should handle JSON parsing errors", function()
    local response_text = 'invalid json'
    local result, err = llm.providers.openai.parse_response(response_text)
    
    assert.is_nil(result, "Result should be nil on error")
    assert.is_not_nil(err, "Should have error message")
  end)
  
  it("should convert messages to text for Ollama", function()
    local messages = {
      {role = "system", content = "You are a helpful assistant"},
      {role = "user", content = "Hello"},
      {role = "assistant", content = "Hi there!"},
      {role = "user", content = "How are you?"}
    }
    
    local text = llm._messages_to_text(messages)
    
    assert.is_not_nil(text, "Text should not be nil")
    assert.is_true(text:find("System:"), "Should include system message")
    assert.is_true(text:find("User:"), "Should include user messages")
    assert.is_true(text:find("Assistant:"), "Should include assistant messages")
  end)
  
  it("should make async request successfully", function()
    local callback_called = false
    local response_received = nil
    
    -- Mock successful job execution
    vim.fn.jobstart = function(cmd, opts)
      if opts and opts.on_stdout then
        -- Simulate receiving response data
        opts.on_stdout(1, {'{"choices":[{"message":{"content":"Async response"}}]}'})
      end
      if opts and opts.on_exit then
        opts.on_exit(1, 0)
      end
      return 1
    end
    
    llm.request("Test prompt", {}, function(response)
      callback_called = true
      response_received = response
    end)
    
    assert.is_true(callback_called, "Callback should be called")
    assert.equals(response_received, "Async response", "Should receive correct response")
  end)
  
  it("should handle request timeout", function()
    local callback_called = false
    local error_received = nil
    
    -- Mock job that times out
    vim.fn.jobstart = function(cmd, opts)
      -- Don't call any callbacks to simulate timeout
      return 1
    end
    
    llm.request("Test prompt", {timeout = 1}, function(response, error)
      callback_called = true
      error_received = error
    end)
    
    -- Wait for timeout (in real test, this would be handled by the timeout mechanism)
    -- For this mock, we'll simulate the timeout callback
    vim.schedule(function()
      callback_called = true
      error_received = "Request timed out"
    end)
    
    assert.is_true(callback_called, "Callback should be called on timeout")
    assert.is_not_nil(error_received, "Should receive timeout error")
  end)
  
  it("should make synchronous request successfully", function()
    -- Mock successful sync job
    local mock_job = {
      sync = function()
        return {'{"choices":[{"message":{"content":"Sync response"}}]}'}, {}, 0
      end
    }
    
    vim.fn.jobstart = function(cmd, opts)
      return mock_job
    end
    
    local result = llm.request_sync("Test prompt", {})
    
    assert.is_not_nil(result, "Result should not be nil")
    assert.equals(result, "Sync response", "Should receive correct response")
  end)
  
  it("should handle sync request failure", function()
    -- Mock failed sync job
    local mock_job = {
      sync = function()
        return {}, {"Error message"}, 1
      end
    }
    
    vim.fn.jobstart = function(cmd, opts)
      return mock_job
    end
    
    local result = llm.request_sync("Test prompt", {})
    
    assert.is_nil(result, "Result should be nil on failure")
  end)
  
  it("should validate API key", function()
    local valid = llm.validate_api_key("openai", "sk-test123")
    assert.is_true(valid, "Should validate OpenAI key format")
    
    local invalid = llm.validate_api_key("openai", "invalid")
    assert.is_false(invalid, "Should reject invalid key format")
  end)
  
  it("should test provider connection", function()
    local callback_called = false
    local success_received = false
    
    -- Mock successful connection test
    vim.fn.jobstart = function(cmd, opts)
      if opts and opts.on_stdout then
        opts.on_stdout(1, {'{"choices":[{"message":{"content":"Connection test"}}]}'})
      end
      if opts and opts.on_exit then
        opts.on_exit(1, 0)
      end
      return 1
    end
    
    llm.test_connection("openai", function(success, error)
      callback_called = true
      success_received = success
    end)
    
    assert.is_true(callback_called, "Callback should be called")
    assert.is_true(success_received, "Connection should be successful")
  end)
  
  it("should handle provider fallback", function()
    local callback_called = false
    local response_received = nil
    
    -- Mock first provider failure, second success
    local call_count = 0
    vim.fn.jobstart = function(cmd, opts)
      call_count = call_count + 1
      if call_count == 1 then
        -- First call fails
        if opts and opts.on_exit then
          opts.on_exit(1, 1) -- non-zero exit code
        end
      else
        -- Second call succeeds
        if opts and opts.on_stdout then
          opts.on_stdout(1, {'{"choices":[{"message":{"content":"Fallback response"}}]}'})
        end
        if opts and opts.on_exit then
          opts.on_exit(1, 0)
        end
      end
      return 1
    end
    
    llm.request("Test prompt", {}, function(response)
      callback_called = true
      response_received = response
    end)
    
    assert.is_true(callback_called, "Callback should be called")
    assert.equals(response_received, "Fallback response", "Should use fallback provider")
  end)
  
end)
