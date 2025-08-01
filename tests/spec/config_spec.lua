-- Tests for caramba.config module
-- Comprehensive test suite covering configuration management, validation, and defaults

-- Mock vim API for testing
local mock_vim = {
  env = {
    OPENAI_API_KEY = "test-openai-key",
    ANTHROPIC_API_KEY = "test-anthropic-key",
    GOOGLE_API_KEY = "test-google-key",
  },
  fn = {
    expand = function(path) return path:gsub("~", "/home/user") end,
    stdpath = function(type) 
      if type == "config" then return "/home/user/.config/nvim"
      elseif type == "data" then return "/home/user/.local/share/nvim"
      end
      return "/tmp"
    end,
    filereadable = function(path) return 1 end,
    readfile = function(path) 
      return {'{"custom_setting": "test_value"}'} 
    end,
    writefile = function(lines, path) return 0 end,
  },
  json = {
    encode = function(data) return '{"encoded":"data"}' end,
    decode = function(str) 
      if str:find("custom_setting") then
        return {custom_setting = "test_value"}
      end
      return {}
    end,
  },
  log = {
    levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 }
  },
  notify = function(msg, level) end,
  tbl_deep_extend = function(behavior, ...)
    local function deep_extend(t1, t2)
      local result = {}
      for k, v in pairs(t1) do
        result[k] = v
      end
      for k, v in pairs(t2) do
        if type(v) == "table" and type(result[k]) == "table" then
          result[k] = deep_extend(result[k], v)
        else
          result[k] = v
        end
      end
      return result
    end
    
    local result = {}
    for _, tbl in ipairs({...}) do
      result = deep_extend(result, tbl)
    end
    return result
  end,
  validate = function(spec, value)
    -- Simple validation mock
    for key, validator in pairs(spec) do
      if value[key] == nil and not validator.optional then
        return false, "Missing required field: " .. key
      end
    end
    return true
  end,
}

_G.vim = mock_vim

-- Load the config module
local config = require('caramba.config')

describe("caramba.config", function()
  
  it("should have default configuration", function()
    local defaults = config.get_defaults()
    
    assert.is_not_nil(defaults, "Defaults should not be nil")
    assert.is_not_nil(defaults.api, "API config should exist")
    assert.is_not_nil(defaults.llm, "LLM config should exist")
    assert.is_not_nil(defaults.features, "Features config should exist")
    assert.is_not_nil(defaults.context, "Context config should exist")
  end)
  
  it("should setup with default configuration", function()
    config.setup()
    local current_config = config.get()
    
    assert.is_not_nil(current_config, "Config should not be nil")
    assert.is_not_nil(current_config.api.openai, "OpenAI config should exist")
    assert.is_not_nil(current_config.api.anthropic, "Anthropic config should exist")
    assert.equals(current_config.llm.provider, "openai", "Default provider should be openai")
  end)
  
  it("should merge user configuration with defaults", function()
    local user_config = {
      llm = {
        provider = "anthropic",
        temperature = 0.5,
      },
      features = {
        auto_complete = false,
      }
    }
    
    config.setup(user_config)
    local current_config = config.get()
    
    assert.equals(current_config.llm.provider, "anthropic", "Should use user provider")
    assert.equals(current_config.llm.temperature, 0.5, "Should use user temperature")
    assert.is_false(current_config.features.auto_complete, "Should use user feature setting")
    assert.is_not_nil(current_config.api.openai, "Should keep default API configs")
  end)
  
  it("should validate configuration", function()
    local valid_config = {
      llm = {
        provider = "openai",
        temperature = 0.7,
      }
    }
    
    local is_valid, error = config.validate(valid_config)
    assert.is_true(is_valid, "Valid config should pass validation")
    assert.is_nil(error, "Should not have validation error")
  end)
  
  it("should reject invalid configuration", function()
    local invalid_config = {
      llm = {
        provider = "invalid_provider",
        temperature = 2.0, -- Invalid temperature
      }
    }
    
    local is_valid, error = config.validate(invalid_config)
    assert.is_false(is_valid, "Invalid config should fail validation")
    assert.is_not_nil(error, "Should have validation error")
  end)
  
  it("should load API keys from environment", function()
    config.setup()
    local current_config = config.get()
    
    assert.equals(current_config.api.openai.api_key, "test-openai-key", "Should load OpenAI key from env")
    assert.equals(current_config.api.anthropic.api_key, "test-anthropic-key", "Should load Anthropic key from env")
  end)
  
  it("should allow API key override in config", function()
    local user_config = {
      api = {
        openai = {
          api_key = "custom-openai-key"
        }
      }
    }
    
    config.setup(user_config)
    local current_config = config.get()
    
    assert.equals(current_config.api.openai.api_key, "custom-openai-key", "Should use custom API key")
  end)
  
  it("should save configuration to file", function()
    local test_config = {
      llm = {
        provider = "anthropic"
      }
    }
    
    config.setup(test_config)
    local success = config.save()
    
    assert.is_true(success, "Should save configuration successfully")
  end)
  
  it("should load configuration from file", function()
    -- Mock file exists and contains config
    vim.fn.filereadable = function(path) return 1 end
    vim.fn.readfile = function(path) 
      return {'{"llm":{"provider":"claude"}}'} 
    end
    vim.json.decode = function(str)
      return {llm = {provider = "claude"}}
    end
    
    local loaded = config.load()
    
    assert.is_not_nil(loaded, "Should load configuration")
    assert.equals(loaded.llm.provider, "claude", "Should load correct provider")
  end)
  
  it("should handle missing config file gracefully", function()
    vim.fn.filereadable = function(path) return 0 end
    
    local loaded = config.load()
    
    assert.is_nil(loaded, "Should return nil for missing file")
  end)
  
  it("should get provider configuration", function()
    config.setup()
    
    local openai_config = config.get_provider("openai")
    assert.is_not_nil(openai_config, "Should get OpenAI config")
    assert.is_not_nil(openai_config.api_key, "Should have API key")
    assert.is_not_nil(openai_config.model, "Should have model")
    
    local invalid_config = config.get_provider("invalid")
    assert.is_nil(invalid_config, "Should return nil for invalid provider")
  end)
  
  it("should update configuration at runtime", function()
    config.setup()
    
    local updates = {
      llm = {
        temperature = 0.9
      }
    }
    
    config.update(updates)
    local current_config = config.get()
    
    assert.equals(current_config.llm.temperature, 0.9, "Should update temperature")
  end)
  
  it("should reset to defaults", function()
    config.setup({
      llm = {
        provider = "anthropic",
        temperature = 0.5
      }
    })
    
    config.reset()
    local current_config = config.get()
    
    assert.equals(current_config.llm.provider, "openai", "Should reset to default provider")
    assert.equals(current_config.llm.temperature, 0.7, "Should reset to default temperature")
  end)
  
  it("should validate provider availability", function()
    config.setup()
    
    local openai_available = config.is_provider_available("openai")
    assert.is_true(openai_available, "OpenAI should be available with API key")
    
    -- Test without API key
    vim.env.OPENAI_API_KEY = nil
    config.setup()
    
    local openai_unavailable = config.is_provider_available("openai")
    assert.is_false(openai_unavailable, "OpenAI should not be available without API key")
  end)
  
  it("should get feature flags", function()
    config.setup({
      features = {
        auto_complete = false,
        context_tracking = true,
      }
    })
    
    assert.is_false(config.is_feature_enabled("auto_complete"), "Auto complete should be disabled")
    assert.is_true(config.is_feature_enabled("context_tracking"), "Context tracking should be enabled")
    assert.is_true(config.is_feature_enabled("nonexistent"), "Unknown features should default to true")
  end)
  
  it("should handle configuration schema validation", function()
    local schema_valid_config = {
      api = {
        openai = {
          api_key = "sk-test123",
          model = "gpt-4",
          temperature = 0.7,
          max_tokens = 1000,
        }
      },
      llm = {
        provider = "openai",
        timeout = 30,
      }
    }
    
    local is_valid = config.validate_schema(schema_valid_config)
    assert.is_true(is_valid, "Valid schema should pass validation")
  end)
  
  it("should provide configuration help", function()
    local help = config.get_help()
    
    assert.is_not_nil(help, "Help should not be nil")
    assert.is_true(type(help) == "string", "Help should be a string")
    assert.is_true(help:find("provider"), "Help should mention providers")
  end)
  
end)
