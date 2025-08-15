describe('context.collect unit', function()
  it('falls back to whole buffer when parser unavailable', function()
    package.loaded['caramba.context'] = nil
    local context = require('caramba.context')
    -- Mock parsers to force nil parser
    package.loaded['nvim-treesitter.parsers'] = {
      has_parser = function() return false end,
      get_parser = function() return nil end,
    }

    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'print("x")' })
    vim.bo.filetype = 'lua'
    local ctx = context.collect({})
    assert.is_true(ctx ~= nil and ctx.content ~= nil, 'Should return buffer content when no parser')
  end)
end)


