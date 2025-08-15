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
    
    # Check available interpreters (prefer python3 for comprehensive test coverage)
    local test_cmd=""
    if command -v python3 &> /dev/null; then
        test_cmd="python3"
    elif command -v lua &> /dev/null; then
        test_cmd="lua"
    else
        print_result "ERROR" "$test_name" "No suitable interpreter found (python3 or lua)"
        return 1
    fi

    # Run the test based on available interpreter
    local temp_output="/tmp/caramba_test_output_$$"
    local exit_code

    case "$test_cmd" in
        "nvim")
            # Use nvim headless mode with minimal initialization
            nvim --headless -u tests/minimal_init.lua \
                -c "lua require('test_runner').run_file('$test_file')" \
                -c "qa!" > "$temp_output" 2>&1
            exit_code=$?
            ;;
        "lua")
            # Use standalone lua
            lua -e "
                package.path = package.path .. ';./lua/?.lua;./tests/?.lua'
                require('test_runner').run_file('$test_file')
            " > "$temp_output" 2>&1
            exit_code=$?
            ;;
        "python3")
            # Use Python test runner - pass the full test file path
            python3 tests/python_test_runner.py "$test_file" > "$temp_output" 2>&1
            exit_code=$?
            ;;
    esac
    
    if [ $exit_code -eq 0 ]; then
        # Parse output for individual test results
        local tests_in_file=0

        # Read the output file line by line
        while IFS= read -r line; do
            # Match SUCCESS:, FAILED:, or ERROR: at start of line
            if [[ $line =~ ^(SUCCESS|FAILED|ERROR):[[:space:]]*(.+)$ ]]; then
                ((tests_in_file++))
                local status="${BASH_REMATCH[1]}"
                local test_desc="${BASH_REMATCH[2]}"
                print_result "$status" "$test_desc"
            elif [[ $line =~ ^Error:[[:space:]]*(.+)$ ]]; then
                # Handle error details on separate lines
                echo -e "${RED}  ${BASH_REMATCH[1]}${NC}"
            fi
        done < "$temp_output"

        # If no tests were found in this file, it's an error
        if [ $tests_in_file -eq 0 ]; then
            print_result "ERROR" "$test_name" "No tests were executed for this file"
            echo "Output was:"
            cat "$temp_output"
        fi
    else
        print_result "ERROR" "$test_name" "Exit code: $exit_code"
        cat "$temp_output"
    fi

    # Clean up temporary file
    rm -f "$temp_output"
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

run_plenary() {
    if command -v nvim >/dev/null 2>&1; then
        echo "Running plenary tests..."
        # Use Plenary test_harness to print to stdout in headless mode
        REPO_DIR=$(pwd)
        nvim --headless -u tests/plenary_init.lua \
          -c "set nomore" \
          -c "lua require('plenary.test_harness').test_directory('$REPO_DIR/tests/spec', { minimal_init = '$REPO_DIR/tests/plenary_init.lua', sequential = true, verbose = true })" \
          -c "qa!" | cat
    else
        echo "Neovim not found; skipping plenary tests"
    fi
}

# Main execution
case "${1:-all}" in
    "setup")
        setup_test_env
        ;;
    "all")
        setup_test_env
        run_all_tests
        run_plenary
        ;;
    *)
        setup_test_env
        run_specific_test "$1"
        run_plenary
        ;;
esac
