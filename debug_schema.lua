-- Debug script to test the OpenAI schema directly
local openai_tools = require('lua.caramba.openai_tools')

print("Available tools:")
for i, tool in ipairs(openai_tools.available_tools) do
  print("Tool " .. i .. ":")
  print(vim.inspect(tool))
  print("JSON:")
  print(vim.json.encode(tool))
  print("---")
end