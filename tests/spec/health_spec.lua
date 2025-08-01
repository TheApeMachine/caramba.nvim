-- Tests for caramba.health module
-- Comprehensive test suite covering health checks and system validation

-- Mock vim API for testing
local mock_vim = {
  health = {
    start = function(name) 
      mock_vim._health_reports = mock_vim._health_reports or {}
      table.insert(mock_vim._health_reports, {type = "start", name = name})
    end,
    ok = function(msg)
      mock_vim._health_reports = mock_vim._health_reports or {}
      table.insert(mock_vim._health_reports, {type = "ok", msg = msg})
    end,
    warn = function(msg, advice)
      mock_vim._health_reports = mock_vim._health_reports or {}
      table.insert(mock_vim._health_reports, {type = "warn", msg = msg, advice = advice})
    end,
    error = function(msg, advice)
      mock_vim._health_reports = mock_vim._health_reports or {}
      table.insert(mock_vim._health_reports, {type = "error", msg = msg, advice = advice})
    end,
  },
  fn = {
    executable = function(cmd)
      local executables = {
        nvim = 1,
        git = 1,
        curl = 1,
        python3 = 1,
      }
      return executables[cmd] or 0
    end,
    system = function(cmd)
      if cmd:find("git --version") then
        return "git version 2.34.1"
      elseif cmd:find("curl --version") then
        return "curl 7.81.0"
      end
      return ""
    end,
    has = function(feature)
      local features = {
        nvim = 1,
        ["nvim-0.9"] = 1,
        treesitter = 1,
        lua = 1,
      }
      return features[feature] or 0
    end,
  },
  env = {
    OPENAI_API_KEY = "sk-test123",
    ANTHROPIC_API_KEY = "test-key",
  },
  log = { levels = { ERROR = 1, WARN = 2, INFO = 3 } },
  notify = function(msg, level) end,
  _health_reports = {},
}

_G.vim = mock_vim

-- Mock dependencies
package.loaded['caramba.config'] = {
  get = function()
    return {
      api = {
        openai = { api_key = "sk-test123" },
        anthropic = { api_key = "test-key" },
      },
      llm = { provider = "openai" }
    }
  end
}

package.loaded['caramba.llm'] = {
  test_connection = function(provider, callback)
    vim.schedule(function()
      if provider == "openai" then
        callback(true, nil)
      else
        callback(false, "Connection failed")
      end
    end)
  end,
  validate_api_key = function(provider, key)
    return key and key:len() > 10
  end
}

-- Load the health module
local health = require('caramba.health')

describe("caramba.health", function()
  
  -- Reset state before each test
  local function reset_state()
    mock_vim._health_reports = {}
  end
  
  it("should check Neovim version", function()
    reset_state()
    
    health.check()
    
    local has_nvim_check = false
    for _, report in ipairs(mock_vim._health_reports) do
      if report.type == "start" and report.name:find("Neovim") then
        has_nvim_check = true
        break
      end
    end
    
    assert.is_true(has_nvim_check, "Should check Neovim version")
  end)
  
  it("should check required dependencies", function()
    reset_state()
    
    health.check()
    
    local has_dependency_check = false
    for _, report in ipairs(mock_vim._health_reports) do
      if report.type == "start" and report.name:find("Dependencies") then
        has_dependency_check = true
        break
      end
    end
    
    assert.is_true(has_dependency_check, "Should check dependencies")
  end)
  
  it("should validate API keys", function()
    reset_state()
    
    health.check()
    
    local has_api_check = false
    for _, report in ipairs(mock_vim._health_reports) do
      if report.type == "start" and report.name:find("API") then
        has_api_check = true
        break
      end
    end
    
    assert.is_true(has_api_check, "Should check API keys")
  end)
  
  it("should test LLM connections", function()
    reset_state()
    
    health.check()
    
    local has_llm_check = false
    for _, report in ipairs(mock_vim._health_reports) do
      if report.type == "start" and report.name:find("LLM") then
        has_llm_check = true
        break
      end
    end
    
    assert.is_true(has_llm_check, "Should test LLM connections")
  end)
  
  it("should report missing dependencies", function()
    reset_state()
    
    -- Mock missing git
    vim.fn.executable = function(cmd)
      if cmd == "git" then return 0 end
      return 1
    end
    
    health.check()
    
    local has_warning = false
    for _, report in ipairs(mock_vim._health_reports) do
      if report.type == "warn" or report.type == "error" then
        has_warning = true
        break
      end
    end
    
    assert.is_true(has_warning, "Should warn about missing dependencies")
  end)
  
  it("should report invalid API keys", function()
    reset_state()
    
    -- Mock invalid API key
    vim.env.OPENAI_API_KEY = "invalid"
    
    health.check()
    
    local has_api_warning = false
    for _, report in ipairs(mock_vim._health_reports) do
      if (report.type == "warn" or report.type == "error") and 
         report.msg and report.msg:find("API") then
        has_api_warning = true
        break
      end
    end
    
    assert.is_true(has_api_warning, "Should warn about invalid API keys")
  end)
  
  it("should check tree-sitter availability", function()
    reset_state()
    
    health.check()
    
    local has_treesitter_check = false
    for _, report in ipairs(mock_vim._health_reports) do
      if report.name and report.name:find("Tree-sitter") then
        has_treesitter_check = true
        break
      end
    end
    
    assert.is_true(has_treesitter_check, "Should check tree-sitter")
  end)
  
  it("should provide helpful advice for issues", function()
    reset_state()
    
    -- Mock missing dependency
    vim.fn.executable = function(cmd) return 0 end
    
    health.check()
    
    local has_advice = false
    for _, report in ipairs(mock_vim._health_reports) do
      if report.advice then
        has_advice = true
        break
      end
    end
    
    assert.is_true(has_advice, "Should provide advice for issues")
  end)
  
  it("should check configuration validity", function()
    reset_state()
    
    health.check()
    
    local has_config_check = false
    for _, report in ipairs(mock_vim._health_reports) do
      if report.name and report.name:find("Configuration") then
        has_config_check = true
        break
      end
    end
    
    assert.is_true(has_config_check, "Should check configuration")
  end)
  
  it("should report overall health status", function()
    reset_state()
    
    health.check()
    
    assert.is_true(#mock_vim._health_reports > 0, "Should generate health reports")
    
    local has_start_reports = false
    local has_status_reports = false
    
    for _, report in ipairs(mock_vim._health_reports) do
      if report.type == "start" then
        has_start_reports = true
      elseif report.type == "ok" or report.type == "warn" or report.type == "error" then
        has_status_reports = true
      end
    end
    
    assert.is_true(has_start_reports, "Should have section headers")
    assert.is_true(has_status_reports, "Should have status reports")
  end)
  
end)
