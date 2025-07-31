#!/bin/bash

# Caramba.nvim Test Runner
# Comprehensive test suite for all modules

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="tests"
SPEC_DIR="$TEST_DIR/spec"
MOCK_DIR="$TEST_DIR/mocks"
COVERAGE_DIR="$TEST_DIR/coverage"

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
ERROR_TESTS=0

# Ensure test directories exist
mkdir -p "$SPEC_DIR" "$MOCK_DIR" "$COVERAGE_DIR"

# Function to print test results
print_result() {
    local status=$1
    local test_name=$2
    local message=$3
    
    case $status in
        "SUCCESS")
            echo -e "${GREEN}Success${NC}\t||\t$test_name"
            ((PASSED_TESTS++))
            ;;
        "FAILED")
            echo -e "${RED}Failed${NC}\t||\t$test_name"
            if [ -n "$message" ]; then
                echo -e "${RED}Error: $message${NC}"
            fi
            ((FAILED_TESTS++))
            ;;
        "ERROR")
            echo -e "${YELLOW}Error${NC}\t||\t$test_name"
            if [ -n "$message" ]; then
                echo -e "${YELLOW}Error: $message${NC}"
            fi
            ((ERROR_TESTS++))
            ;;
    esac
    ((TOTAL_TESTS++))
}

# Function to run a single test file
run_test_file() {
    local test_file=$1
    local test_name
    test_name=$(basename "$test_file" .lua)
    
    echo "========================================"
    echo -e "Testing: \t$test_file"
    
    # Check available interpreters (nvim > lua > python fallback)
    local test_cmd=""
    if command -v nvim &> /dev/null; then
        test_cmd="nvim"
    elif command -v lua &> /dev/null; then
        test_cmd="lua"
    elif command -v python3 &> /dev/null; then
        test_cmd="python3"
    else
        print_result "ERROR" "$test_name" "No suitable interpreter found (nvim, lua, or python3)"
        return 1
    fi

    # Run the test based on available interpreter
    local output
    local exit_code

    case "$test_cmd" in
        "nvim")
            # Use nvim headless mode
            if output=$(nvim --headless --noplugin -u NONE \
                -c "lua package.path = package.path .. ';./lua/?.lua;./tests/?.lua'" \
                -c "lua require('test_runner').run_file('$test_file')" \
                -c "qa!" 2>&1); then
                exit_code=0
            else
                exit_code=$?
            fi
            ;;
        "lua")
            # Use standalone lua
            if output=$(lua -e "
                package.path = package.path .. ';./lua/?.lua;./tests/?.lua'
                require('test_runner').run_file('$test_file')
            " 2>&1); then
                exit_code=0
            else
                exit_code=$?
            fi
            ;;
        "python3")
            # Use Python test runner
            if output=$(python3 tests/python_test_runner.py "$(basename "$test_file" .lua | sed 's/_spec$//')" 2>&1); then
                exit_code=0
            else
                exit_code=$?
            fi
            ;;
    esac
    
    if [ $exit_code -eq 0 ]; then
        # Parse output for individual test results
        local tests_in_file=0
        while IFS= read -r line; do
            if [[ $line =~ ^(SUCCESS|FAILED|ERROR):\s*(.+)$ ]]; then
                ((tests_in_file++))
                local status="${BASH_REMATCH[1]}"
                local test_desc="${BASH_REMATCH[2]}"
                print_result "$status" "$test_desc"
            fi
        done <<< "$output"

        # If no tests were found in this file, it's an error
        if [ $tests_in_file -eq 0 ]; then
            print_result "ERROR" "$test_name" "No tests were executed for this file"
        fi
    else
        print_result "ERROR" "$test_name" "Exit code: $exit_code"
        echo "$output"
    fi
}

# Function to run all tests
run_all_tests() {
    echo "Starting Caramba.nvim Test Suite"
    echo "========================================"
    
    # Find all test files
    local test_files
    if [ -d "$SPEC_DIR" ]; then
        test_files=$(find "$SPEC_DIR" -name "*_spec.lua" | sort)
    else
        echo "No test directory found at $SPEC_DIR"
        exit 1
    fi
    
    if [ -z "$test_files" ]; then
        echo "No test files found in $SPEC_DIR"
        exit 1
    fi
    
    # Run each test file
    for test_file in $test_files; do
        run_test_file "$test_file"
    done
    
    # Print summary
    echo "========================================"
    echo "Test Summary:"
    echo -e "Success: \t$PASSED_TESTS"
    echo -e "Failed : \t$FAILED_TESTS" 
    echo -e "Errors : \t$ERROR_TESTS"
    echo "========================================"
    
    # Exit with error if any tests failed
    if [ $FAILED_TESTS -gt 0 ] || [ $ERROR_TESTS -gt 0 ]; then
        exit 1
    fi
}

# Function to run specific test
run_specific_test() {
    local test_pattern=$1
    local test_files
    
    if [ -d "$SPEC_DIR" ]; then
        test_files=$(find "$SPEC_DIR" -name "*$test_pattern*_spec.lua")
    fi
    
    if [ -z "$test_files" ]; then
        echo "No test files found matching pattern: $test_pattern"
        exit 1
    fi
    
    for test_file in $test_files; do
        run_test_file "$test_file"
    done
}

# Function to setup test environment
setup_test_env() {
    echo "Setting up test environment..."

    # Check that test runner exists
    if [ ! -f "$TEST_DIR/test_runner.lua" ]; then
        echo -e "${RED}Error: Test runner not found at '$TEST_DIR/test_runner.lua'.${NC}" >&2
        echo "Please ensure the test infrastructure is correctly set up." >&2
        exit 1
    fi

    
    echo "Test environment ready!"
}

# Main execution
case "${1:-all}" in
    "setup")
        setup_test_env
        ;;
    "all")
        setup_test_env
        run_all_tests
        ;;
    *)
        setup_test_env
        run_specific_test "$1"
        ;;
esac
