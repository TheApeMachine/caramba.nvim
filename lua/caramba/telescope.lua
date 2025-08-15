-- Telescope integration for Caramba

local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
  return {}
end

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local M = {}

-- Commands picker
function M.commands()
  local registry = require('caramba.core.commands').list()
  pickers.new({}, {
    prompt_title = 'Caramba Commands',
    finder = finders.new_table({
      results = registry,
      entry_maker = function(cmd)
        return {
          value = cmd,
          display = string.format('%-32s %s', cmd.name, cmd.desc or ''),
          ordinal = cmd.name .. ' ' .. (cmd.desc or ''),
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      local run = function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value and selection.value.name then
          pcall(vim.cmd, selection.value.name)
        end
      end
      map('i', '<CR>', run)
      map('n', '<CR>', run)
      return true
    end,
  }):find()
end

-- Chat history picker
function M.chat_history()
  local state = require('caramba.state').get()
  local history = (state.chat and state.chat.history) or {}
  local items = {}
  for i, msg in ipairs(history) do
    local role = msg.role or 'unknown'
    local first = (msg.content or ''):gsub('\n', ' '):sub(1, 80)
    table.insert(items, { idx = i, role = role, content = msg.content or '', display = string.format('%3d [%s] %s', i, role, first) })
  end

  pickers.new({}, {
    prompt_title = 'Caramba Chat History',
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = item.display,
          ordinal = item.display,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      local view = function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value then
          local ui = require('caramba.ui')
          local lines = {
            '# Chat Message',
            '',
            'Role: ' .. selection.value.role,
            '',
          }
          for l in (selection.value.content or ''):gmatch('[^\n]+') do table.insert(lines, l) end
          ui.show_lines_centered(lines, { title = ' Chat Message ', filetype = 'markdown' })
        end
      end
      map('i', '<CR>', view)
      map('n', '<CR>', view)
      return true
    end,
  }):find()
end

-- Register extension (optional)
function M.setup_commands()
  local commands = require('caramba.core.commands')
  commands.register('Telescope', function()
    if not has_telescope then
      vim.notify('telescope.nvim not found', vim.log.levels.WARN)
      return
    end
    require('telescope').setup({})
  end, { desc = 'Ensure Telescope is set up (no-op if already)' })

  commands.register('TelescopeCommands', function()
    if not has_telescope then
      vim.notify('telescope.nvim not found', vim.log.levels.WARN)
      return
    end
    M.commands()
  end, { desc = 'Pick and run Caramba commands' })

  commands.register('TelescopeChat', function()
    if not has_telescope then
      vim.notify('telescope.nvim not found', vim.log.levels.WARN)
      return
    end
    M.chat_history()
  end, { desc = 'Browse Caramba chat history' })
end

return M


