-- AI Assistant for Neovim
local M = {}

-- Health check support
M.health = require('caramba.health')

-- Load all modules
local modules = {
  'caramba.config',
  'caramba.context', 
  'caramba.llm',
  'caramba.edit',
  'caramba.refactor',
  'caramba.search',
  'caramba.embeddings',
  'caramba.planner',
  'caramba.commands',
  'caramba.chat',
  'caramba.multifile',
  'caramba.testing',
  'caramba.debug',
  'caramba.websearch',
  'caramba.tools',
  'caramba.ast_transform',
  'caramba.intelligence',
  'caramba.pair',
  'caramba.git',
  'caramba.tdd',
  'caramba.consistency',
}

for _, module in ipairs(modules) do
  local ok, err = pcall(require, module)
  if not ok then
    vim.notify('Failed to load ' .. module .. ': ' .. err, vim.log.levels.ERROR)
  end
end

-- Export modules
M.config = require('caramba.config')
M.context = require('caramba.context')
M.llm = require('caramba.llm')
M.edit = require('caramba.edit')
M.refactor = require('caramba.refactor')
M.search = require('caramba.search')
M.planner = require('caramba.planner')
M.embeddings = require('caramba.embeddings')
M.chat = require('caramba.chat')
M.multifile = require('caramba.multifile')
M.testing = require('caramba.testing')
M.debug = require('caramba.debug')
M.websearch = require('caramba.websearch')
M.tools = require('caramba.tools')
M.ast_transform = require('caramba.ast_transform')
M.intelligence = require('caramba.intelligence')
M.pair = require('caramba.pair')
M.git = require('caramba.git')
M.commands = require('caramba.commands')
M.tdd = require('caramba.tdd')
M.consistency = require('caramba.consistency')

-- Initialize the module
function M.setup(opts)
  -- Merge user options with defaults
  M.config.setup(opts)
  
  -- Setup planner
  M.planner.setup()
  
  -- Setup commands
  M.commands.setup()
  
  -- Initialize search index if enabled
  local search = require('caramba.search')
  if M.config.get().search.index_on_startup then
    vim.defer_fn(function()
      search.index_workspace()
    end, 1000) -- Wait 1 second after startup
  end
  
  -- Set up autocommands
  local context = require('caramba.context')
  local last_update_time = 0
  local pending_update = false
  
  -- Only track cursor context if enabled
  if M.config.get().features.track_cursor_context then
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "BufEnter"}, {
      group = vim.api.nvim_create_augroup("AIContext", { clear = true }),
      callback = function()
        -- Simple time-based debouncing
        local current_time = vim.loop.now()
        local time_since_last = current_time - last_update_time
        
        if time_since_last >= 150 then
          -- Enough time has passed, update immediately
          last_update_time = current_time
          pending_update = false
          
          -- Wrap in pcall to prevent errors
          local ok, err = pcall(context.update_cursor_context)
          if not ok and M.config.get().debug then
            vim.notify("Error updating cursor context: " .. tostring(err), vim.log.levels.ERROR)
          end
        elseif not pending_update then
          -- Schedule an update for later
          pending_update = true
          vim.defer_fn(function()
            if pending_update then
              pending_update = false
              last_update_time = vim.loop.now()
              
              local ok, err = pcall(context.update_cursor_context)
              if not ok and M.config.get().debug then
                vim.notify("Error updating cursor context: " .. tostring(err), vim.log.levels.ERROR)
              end
            end
          end, 150)
        end
      end,
    })
  end
  
  -- Initialize sub-modules that have setup functions
  if M.consistency.setup then
    M.consistency.setup()
  end
  
  -- Create WhichKey mappings
  local ok, which_key = pcall(require, 'which-key')
  if ok then
    which_key.add({
      { "<leader>a", group = "AI" },
      { "<leader>ac", "<cmd>AIComplete<cr>", desc = "Complete code" },
      { "<leader>ad", "<cmd>AIDebugError<cr>", desc = "Debug error" },
      { "<leader>ae", "<cmd>AIExplain<cr>", desc = "Explain code" },
      { "<leader>ag", "<cmd>AIGenerateTests<cr>", desc = "Generate tests" },
      { "<leader>ai", "<cmd>AIImplementFromTest<cr>", desc = "Implement from test" },
      { "<leader>am", "<cmd>AICommitMessage<cr>", desc = "Generate commit message" },
      { "<leader>ao", "<cmd>AICheckConsistency<cr>", desc = "Check consistency" },
      { "<leader>ap", "<cmd>AIPlan<cr>", desc = "Plan implementation" },
      { "<leader>aq", "<cmd>AIQuery<cr>", desc = "Query with tools" },
      { "<leader>ar", "<cmd>AIRefactor<cr>", desc = "Refactor code" },
      { "<leader>as", "<cmd>AISearch<cr>", desc = "Search code" },
      { "<leader>at", "<cmd>AIChat<cr>", desc = "Open chat" },
      { "<leader>aw", "<cmd>AIWebSearch<cr>", desc = "Web search" },
      { "<leader>ax", "<cmd>AITransform<cr>", desc = "Transform code" },
    })
  end
  
  -- Add debug commands if debug mode is enabled
  if M.config.get().debug then
    vim.api.nvim_create_user_command("AITestConnection", function()
      local test_messages = {
        { role = "user", content = "Say 'Hello, I'm working!' if you can see this." }
      }
      
      M.llm.request(test_messages, { 
        temperature = 0.1,
        max_tokens = 50
      }, function(result, err)
        if err then
          vim.notify("LLM Test Failed: " .. err, vim.log.levels.ERROR)
          vim.notify("Provider: " .. M.config.get().provider, vim.log.levels.INFO)
        else
          vim.notify("LLM Test Success: " .. (result or "No response"), vim.log.levels.INFO)
        end
      end)
    end, { desc = "Test LLM connection" })
    
    vim.api.nvim_create_user_command("AIShowConfig", function()
      local cfg = M.config.get()
      vim.notify("Provider: " .. cfg.provider, vim.log.levels.INFO)
      
      if cfg.provider == "openai" then
        local has_key = cfg.api.openai.api_key and cfg.api.openai.api_key ~= ""
        vim.notify("OpenAI API Key: " .. (has_key and "Set" or "Not Set"), vim.log.levels.INFO)
        vim.notify("Model: " .. cfg.api.openai.model, vim.log.levels.INFO)
      end
    end, { desc = "Show AI configuration" })
  end
  
  vim.notify("AI Assistant initialized", vim.log.levels.INFO)
end

return M 