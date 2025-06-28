-- Test script to demonstrate the refactored command registration system

-- This would normally be run as part of the plugin initialization
local function test_command_registration()
  -- Mock the core commands module for testing
  local commands = require('caramba.core.commands')
  
  print("=== Testing Command Registration System ===\n")
  
  -- Test 1: Register a command
  print("Test 1: Registering AITestCommand")
  local success = commands.register("TestCommand", function()
    print("Test command executed!")
  end, {
    desc = "Test command for demonstration",
  })
  print("Registration successful:", success)
  
  -- Test 2: Try to register duplicate
  print("\nTest 2: Attempting duplicate registration")
  local duplicate = commands.register("TestCommand", function()
    print("Duplicate command")
  end, {
    desc = "This should fail",
  })
  print("Duplicate registration blocked:", not duplicate)
  
  -- Test 3: List all commands
  print("\nTest 3: Listing all registered commands")
  local all_commands = commands.list()
  print("Total commands registered:", #all_commands)
  
  -- Test 4: Show debug info
  print("\nTest 4: Debug output")
  commands.debug()
end

-- Run the test
test_command_registration() 