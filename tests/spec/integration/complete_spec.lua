describe('Caramba Complete integration', function()
  before_each(function()
    -- Mock only the networked part of LLM; keep prompt builders intact
    local real_llm = require('caramba.llm')
    package.loaded['caramba.llm'] = setmetatable({
      request = function(_, _, cb)
        vim.schedule(function()
          cb('console.log("hello from test")')
        end)
      end
    }, { __index = real_llm })
    -- New buffer
    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'function test() {',
      '  // TODO',
      '}'
    })
    vim.bo.filetype = 'javascript'
    -- Place cursor at end of line 2
    vim.api.nvim_win_set_cursor(0, {2, 8})
  end)

  it('shows a diff preview window', function()
    -- Call complete with explicit instruction to avoid prompt
    vim.cmd('CarambaComplete Insert a console.log')

    -- Give event loop a moment
    vim.wait(200)

    local found = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg and cfg.title and tostring(cfg.title):match('Diff Preview') then
        found = true
        break
      end
    end

    assert.is_true(found, 'Diff Preview window should appear')
  end)
end)


