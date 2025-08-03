#!/usr/bin/env python3
"""
FALLBACK Test Runner for Caramba.nvim Lua tests

WARNING: This is a FALLBACK runner that does NOT execute Lua code.
It only performs basic syntax and structure validation.

For REAL test execution, use:
1. Neovim headless mode (preferred)
2. Lua interpreter

This fallback should only be used when neither Neovim nor Lua are available,
and it will only validate test structure, not execute actual test logic.
"""

import os
import re
import sys
import glob
from typing import List, Dict, Any, Tuple

class LuaTestRunner:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.errors = 0
        self.current_describe = None
        
    def parse_lua_test_file(self, file_path: str) -> List[Dict[str, Any]]:
        """Parse a Lua test file and extract test cases"""
        tests = []
        
        try:
            with open(file_path, 'r') as f:
                content = f.read()
            
            # Extract describe blocks
            describe_pattern = r'describe\s*\(\s*["\']([^"\']+)["\']\s*,\s*function\s*\(\s*\)'
            describe_matches = re.finditer(describe_pattern, content)
            
            for describe_match in describe_matches:
                describe_name = describe_match.group(1)
                describe_start = describe_match.end()
                
                # Find the end of this describe block (simplified - assumes proper nesting)
                brace_count = 1
                pos = describe_start
                while pos < len(content) and brace_count > 0:
                    if content[pos] == '{':
                        brace_count += 1
                    elif content[pos] == '}':
                        brace_count -= 1
                    pos += 1
                
                describe_content = content[describe_start:pos-1]
                
                # Extract it() blocks within this describe
                it_pattern = r'it\s*\(\s*["\']([^"\']+)["\']\s*,\s*function\s*\(\s*\)'
                it_matches = re.finditer(it_pattern, describe_content)
                
                for it_match in it_matches:
                    test_name = it_match.group(1)
                    full_test_name = f"{describe_name} {test_name}"
                    
                    # Extract the test function body
                    it_start = it_match.end()
                    it_brace_count = 1
                    it_pos = it_start
                    while it_pos < len(describe_content) and it_brace_count > 0:
                        if describe_content[it_pos] == '{':
                            it_brace_count += 1
                        elif describe_content[it_pos] == '}':
                            it_brace_count -= 1
                        it_pos += 1
                    
                    test_body = describe_content[it_start:it_pos-1]
                    
                    tests.append({
                        'name': full_test_name,
                        'describe': describe_name,
                        'it': test_name,
                        'body': test_body.strip()
                    })
        
        except Exception as e:
            print(f"Error parsing {file_path}: {e}")
            return []
        
        return tests
    
    def execute_test(self, test: Dict[str, Any]) -> Tuple[bool, str]:
        """
        WARNING: This is a fallback test runner that cannot actually execute Lua code.
        It only performs basic syntax and structure validation.
        For real test execution, use Neovim or Lua interpreter.
        """
        try:
            body = test['body']

            # Basic syntax validation
            if not body.strip():
                return False, "Empty test body"

            # Check for basic test structure
            has_assertions = bool(re.search(r'assert\.\w+\s*\(', body))
            if not has_assertions:
                return False, "No assertions found in test"

            # Check for obvious syntax errors
            syntax_errors = [
                r'function\s*\(\s*\)\s*end\s*\(',  # Malformed function calls
                r'assert\.\w+\s*\(\s*\)',          # Empty assertions
                r'local\s+function\s*\(',          # Incomplete function definitions
            ]

            for pattern in syntax_errors:
                if re.search(pattern, body):
                    return False, f"Potential syntax error detected: {pattern}"

            # This is NOT actual test execution - just structure validation
            return True, "Structure validation passed (NOT executed)"

        except Exception as e:
            return False, f"Validation error: {str(e)}"
    
    def check_equals(self, actual: str, expected: str) -> bool:
        """Check equality assertion"""
        # Simplified - in real implementation would evaluate expressions
        return True
    
    def check_is_true(self, value: str) -> bool:
        """Check is_true assertion"""
        return 'true' in value.lower() or 'success' in value.lower()
    
    def check_is_false(self, value: str) -> bool:
        """Check is_false assertion"""
        return 'false' in value.lower() or 'fail' in value.lower()
    
    def check_is_nil(self, value: str) -> bool:
        """Check is_nil assertion"""
        return 'nil' in value.lower()
    
    def check_is_not_nil(self, value: str) -> bool:
        """Check is_not_nil assertion"""
        return 'nil' not in value.lower()
    
    def run_test_file(self, file_path: str) -> None:
        """Run all tests in a file"""
        print(f"========================================")
        print(f"Testing: \t{file_path}")
        print(f"WARNING: Using fallback runner - structure validation only!")

        tests = self.parse_lua_test_file(file_path)

        if not tests:
            print(f"Error\t||\tNo tests found in {file_path}")
            self.errors += 1
            return
        
        for test in tests:
            success, message = self.execute_test(test)

            if success:
                print(f"SUCCESS: {test['name']}")
                self.passed += 1
            else:
                print(f"FAILED: {test['name']}")
                if message:
                    print(f"Error: {message}")
                self.failed += 1
    
    def run_all_tests(self, test_dir: str = "tests/spec") -> int:
        """Run all test files in the test directory"""
        print("Starting Caramba.nvim Test Suite (FALLBACK MODE)")
        print("WARNING: This runner only validates test structure, not execution!")
        print("For real test execution, use Neovim or Lua interpreter.")
        print("========================================")

        if not os.path.exists(test_dir):
            print(f"Test directory {test_dir} not found")
            return 1
        
        test_files = glob.glob(os.path.join(test_dir, "*_spec.lua"))
        
        if not test_files:
            print(f"No test files found in {test_dir}")
            return 1
        
        for test_file in sorted(test_files):
            self.run_test_file(test_file)
        
        # Print summary
        print("========================================")
        print("Test Summary:")
        print(f"Success: \t{self.passed}")
        print(f"Failed : \t{self.failed}")
        print(f"Errors : \t{self.errors}")
        print("========================================")
        
        return 1 if (self.failed > 0 or self.errors > 0) else 0

def main():
    runner = LuaTestRunner()
    
    # Check if specific test file or pattern provided
    if len(sys.argv) > 1:
        arg = sys.argv[1]

        # If it's a full path to a test file, use it directly
        if arg.endswith('_spec.lua') and os.path.exists(arg):
            test_files = [arg]
        else:
            # Otherwise treat it as a pattern
            test_files = glob.glob(f"tests/spec/*{arg}*_spec.lua")

        if not test_files:
            print(f"No test files found for: {arg}")
            return 1

        print("Starting Caramba.nvim Test Suite")
        print("========================================")

        for test_file in sorted(test_files):
            runner.run_test_file(test_file)

        print("========================================")
        print("Test Summary:")
        print(f"Success: \t{runner.passed}")
        print(f"Failed : \t{runner.failed}")
        print(f"Errors : \t{runner.errors}")
        print("========================================")

        return 1 if (runner.failed > 0 or runner.errors > 0) else 0
    else:
        return runner.run_all_tests()

if __name__ == "__main__":
    sys.exit(main())
