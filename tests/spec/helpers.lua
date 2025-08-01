-- tests/spec/helpers.lua
local M = {}

-- Store original values for unmocking
local original_values = {}

-- Mock a global or module function
function M.mock(name, mock_value, is_global)
  local target = _G
  local key = name

  if not is_global then
    -- Handle module functions like 'vim.api.nvim_get_current_buf'
    local parts = {}
    for part in name:gmatch("([^%.]+)") do
      table.insert(parts, part)
    end

    key = table.remove(parts)
    for i = 1, #parts do
      target = target[parts[i]]
    end
  end

  original_values[name] = {
    target = target,
    key = key,
    value = target[key],
  }
  target[key] = mock_value
end

-- Unmock a previously mocked function
function M.unmock(name)
  local original = original_values[name]
  if original then
    original.target[original.key] = original.value
    original_values[name] = nil
  end
end

-- Clear package cache to allow re-requiring modules
function M.clear_package_cache()
  for k, _ in pairs(package.loaded) do
    if k:match('^caramba') then
      package.loaded[k] = nil
    end
  end
end

return M