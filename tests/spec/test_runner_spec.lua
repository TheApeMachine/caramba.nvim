-- Tests for the test runner itself
-- Simple validation that our test framework works correctly

describe("test runner", function()
  
  it("should support basic assertions", function()
    assert.equals(1, 1, "Basic equality should work")
    assert.is_true(true, "True assertion should work")
    assert.is_false(false, "False assertion should work")
    assert.is_nil(nil, "Nil assertion should work")
    assert.is_not_nil("something", "Not nil assertion should work")
  end)
  
  it("should support string contains assertion", function()
    assert.contains("hello world", "world", "String should contain substring")
  end)
  
  it("should support table contains assertion", function()
    local test_table = {"apple", "banana", "cherry"}
    assert.contains(test_table, "banana", "Table should contain value")
  end)
  
  it("should handle multiple test cases", function()
    assert.equals(2 + 2, 4, "Math should work")
    assert.is_true(type("string") == "string", "Type checking should work")
  end)
  
  it("should support nested describe blocks", function()
    -- This test validates that our test structure works
    assert.is_not_nil(describe, "describe function should exist")
    assert.is_not_nil(it, "it function should exist")
    assert.is_not_nil(assert, "assert object should exist")
  end)
  
end)
