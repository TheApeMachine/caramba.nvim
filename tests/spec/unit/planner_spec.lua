describe('Planner unit', function()
  before_each(function()
    -- Mock llm to avoid network
    package.loaded['caramba.llm'] = {
      request = function(prompt, opts, cb)
        local fake = '{"understanding":"ok","affected_components":[],"implementation_steps":[{"step":1,"action":"do","file":"x","reason":"y"}]}'
        vim.schedule(function() cb(fake) end)
      end
    }
  end)

  it('creates a plan without error', function()
    local planner = require('caramba.planner')
    local called = false
    planner.create_task_plan('Add thing', 'ctx', function() called = true end)
    vim.wait(200)
    assert.is_true(called, 'Callback should be called')
  end)
end)


