local M = {}

M.check = function()
  vim.health.start("AI Assistant")
  
  -- Check for required dependencies
  local deps = {
    { name = "plenary.nvim", module = "plenary" },
    { name = "nvim-treesitter", module = "nvim-treesitter" },
  }
  
  for _, dep in ipairs(deps) do
    local ok = pcall(require, dep.module)
    if ok then
      vim.health.ok(dep.name .. " is installed")
    else
      vim.health.error(dep.name .. " is not installed")
    end
  end
  
  -- Check for Tree-sitter parsers
  local ts_ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if ts_ok then
    local lang = vim.bo.filetype
    if lang and lang ~= "" then
      local parser_ok = parsers.has_parser(lang)
      if parser_ok then
        vim.health.ok("Tree-sitter parser for '" .. lang .. "' is installed")
      else
        vim.health.warn("Tree-sitter parser for '" .. lang .. "' is not installed")
        vim.health.info("Run :TSInstall " .. lang .. " to install it")
      end
    end
  end
  
  -- Check for API keys
  local config = require("ai.config").get()
  local providers = {"openai", "anthropic", "ollama"}
  
  vim.health.start("LLM Providers")
  for _, provider in ipairs(providers) do
    local key_env = provider:upper() .. "_API_KEY"
    local has_key = vim.env[key_env] ~= nil
    
    if provider == "ollama" then
      -- Ollama doesn't need an API key
      vim.health.ok("Ollama (no API key required)")
    elseif has_key then
      vim.health.ok(provider .. " API key is set")
    else
      vim.health.warn(provider .. " API key is not set")
      vim.health.info("Set " .. key_env .. " environment variable")
    end
  end
  
  -- Check current provider
  local current_provider = config.provider
  vim.health.info("Current provider: " .. current_provider)
  
  -- Test LLM connection
  vim.health.start("LLM Connection Test")
  local llm = require("ai.llm")
  local test_passed = false
  
  llm.request({
    { role = "user", content = "Say 'test passed' if you can read this." }
  }, { max_tokens = 10 }, function(response)
    if response and response:lower():find("test passed") then
      test_passed = true
    end
  end)
  
  -- Wait a bit for the async response
  vim.wait(3000, function() return test_passed end, 100)
  
  if test_passed then
    vim.health.ok("LLM connection test passed")
  else
    vim.health.error("LLM connection test failed")
    vim.health.info("Check your API key and network connection")
  end
end

return M 