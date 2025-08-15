local helpers = require('plenary.test_harness')

describe('Caramba Chat integration', function()
  it('opens chat window without errors', function()
    -- Open a scratch buffer
    vim.cmd('enew')
    vim.bo.filetype = 'lua'

    -- Run the command
    vim.cmd('CarambaChat')

    -- Assert a window exists whose buffer name is "Caramba Chat" (more reliable than title)
    local found = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match('Caramba Chat') then
        found = true
        break
      end
    end

    assert.is_true(found, 'Chat window should be opened')
  end)
end)


