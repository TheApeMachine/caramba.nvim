-- Basic test runner for Caramba.nvim
local M = {}

-- Simple assertion library
local assert = {}

function assert.equals(actual, expected, message)
    if actual ~= expected then
        error(string.format("Assertion failed: %s\nExpected: %s\nActual: %s", 
            message or "values not equal", tostring(expected), tostring(actual)))
    end
end

function assert.is_true(value, message)
    if not value then
        error(string.format("Assertion failed: %s\nExpected: true\nActual: %s", 
            message or "value is not true", tostring(value)))
    end
end

function assert.is_false(value, message)
    if value then
        error(string.format("Assertion failed: %s\nExpected: false\nActual: %s", 
            message or "value is not false", tostring(value)))
    end
end

function assert.is_nil(value, message)
    if value ~= nil then
        error(string.format("Assertion failed: %s\nExpected: nil\nActual: %s", 
            message or "value is not nil", tostring(value)))
    end
end

function assert.is_not_nil(value, message)
    if value == nil then
        error(string.format("Assertion failed: %s\nExpected: not nil\nActual: nil", 
            message or "value is nil"))
    end
end

-- Test context
local current_describe = nil
local test_results = {}

-- Test framework functions
function describe(name, func)
    current_describe = name
    func()
    current_describe = nil
end

function it(description, func)
    local test_name = current_describe and (current_describe .. " " .. description) or description
    local success, err = pcall(func)
    
    if success then
        print("SUCCESS: " .. test_name)
        table.insert(test_results, {status = "SUCCESS", name = test_name})
    else
        print("FAILED: " .. test_name)
        print("Error: " .. tostring(err))
        table.insert(test_results, {status = "FAILED", name = test_name, error = err})
    end
end

-- Make assert available globally
_G.assert = assert
_G.describe = describe
_G.it = it

-- Run a test file
function M.run_file(file_path)
    test_results = {}
    local success, err = pcall(dofile, file_path)
    
    if not success then
        print("ERROR: Failed to load test file: " .. tostring(err))
        return false
    end
    
    return true
end

return M
