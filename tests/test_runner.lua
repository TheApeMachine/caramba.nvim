-- Basic test runner for Caramba.nvim
local M = {}

-- Simple assertion library (avoid conflicts with built-in assert)
local test_assert = {}

function test_assert.equals(actual, expected, message)
    if actual ~= expected then
        error(string.format("Assertion failed: %s\nExpected: %s\nActual: %s",
            message or "values not equal", tostring(expected), tostring(actual)))
    end
end

function test_assert.is_true(value, message)
    if not value then
        error(string.format("Assertion failed: %s\nExpected: true\nActual: %s",
            message or "value is not true", tostring(value)))
    end
end

function test_assert.is_false(value, message)
    if value then
        error(string.format("Assertion failed: %s\nExpected: false\nActual: %s",
            message or "value is not false", tostring(value)))
    end
end

function test_assert.is_nil(value, message)
    if value ~= nil then
        error(string.format("Assertion failed: %s\nExpected: nil\nActual: %s",
            message or "value is not nil", tostring(value)))
    end
end

function test_assert.is_not_nil(value, message)
    if value == nil then
        error(string.format("Assertion failed: %s\nExpected: not nil\nActual: nil",
            message or "value is nil"))
    end
end

function test_assert.contains(haystack, needle, message)
    if type(haystack) == "string" then
        if not haystack:find(needle, 1, true) then
            error(string.format("Assertion failed: %s\nExpected string to contain: %s\nActual: %s",
                message or "string does not contain expected value", tostring(needle), tostring(haystack)))
        end
    elseif type(haystack) == "table" then
        local found = false
        for _, v in pairs(haystack) do
            if v == needle then
                found = true
                break
            end
        end
        if not found then
            error(string.format("Assertion failed: %s\nExpected table to contain: %s",
                message or "table does not contain expected value", tostring(needle)))
        end
    else
        error("contains assertion only works with strings and tables")
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

-- Make test functions available globally
_G.assert = test_assert  -- Override built-in assert with our test version
_G.describe = describe
_G.it = it

-- Store original assert for modules that need it
_G.lua_assert = _G.assert or function() end

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
