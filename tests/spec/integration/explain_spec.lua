describe('Caramba Explain integration', function()
  before_each(function()
    -- Mock only the networked part of LLM; keep prompt builders intact
    local real_llm = require('caramba.llm')
    package.loaded['caramba.llm'] = setmetatable({
      request = function(_, _, cb)
        vim.schedule(function()
          cb('# Explanation\nThis is a mock explanation')
        end)
      end
    }, { __index = real_llm })
    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'function add(a, b) {',
      '  return a + b;',
      '}'
    })
    vim.bo.filetype = 'javascript'
  end)

  it('opens a result window with markdown', function()
    vim.cmd('CarambaExplain')
    vim.wait(200)

    local found = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'markdown' then
        found = true
        break
      end
    end
    assert.is_true(found, 'Markdown window should be opened for explanation')
  end)
end)


