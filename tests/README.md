# Caramba.nvim Test Suite

A comprehensive test suite for the Caramba.nvim plugin, covering all major modules and functionality with 142 test cases.

## Overview

The test suite has been significantly expanded from the original single basic test to provide comprehensive coverage of:

- **Core Modules**: Context extraction, LLM integration, configuration management
- **Command System**: Registration, execution, and management
- **Multi-file Operations**: Transactions, previews, and file operations
- **Testing & TDD**: Test generation, framework detection, and TDD workflows
- **Error Handling**: Graceful degradation and error recovery
- **Integration**: End-to-end workflows and module interactions
- **Health Checks**: System validation and dependency checking

## Test Structure

```
tests/
├── README.md                    # This file
├── python_test_runner.py        # Python-based test runner
├── test_runner.lua              # Lua test framework (for nvim/lua)
└── spec/                        # Test specifications
    ├── commands_spec.lua         # Command system tests (17 tests)
    ├── config_spec.lua           # Configuration tests (17 tests)
    ├── context_spec.lua          # Context extraction tests (9 tests)
    ├── error_handling_spec.lua   # Error handling tests (15 tests)
    ├── health_spec.lua           # Health check tests (10 tests)
    ├── integration_spec.lua      # Integration tests (13 tests)
    ├── llm_spec.lua              # LLM provider tests (15 tests)
    ├── multifile_spec.lua        # Multi-file operation tests (17 tests)
    ├── tdd_spec.lua              # TDD workflow tests (15 tests)
    └── testing_spec.lua          # Test generation tests (14 tests)
```

## Running Tests

### Quick Start

```bash
# Run all tests
./test.sh

# Run specific test module
./test.sh context

# Run with Python test runner directly
python3 tests/python_test_runner.py
```

### Test Runners

The test suite supports multiple execution environments with different levels of reliability:

1. **Neovim Headless** (preferred): Uses nvim --headless for authentic testing
2. **Lua Interpreter**: Fallback for environments without Neovim
3. **Python Test Runner**: ⚠️ **FALLBACK ONLY** - Structure validation, NOT execution

**IMPORTANT**: The Python test runner does NOT execute Lua code. It only validates test structure and syntax. For real test execution, use Neovim or Lua interpreter.

### Requirements

- **Preferred**: Neovim 0.9+
- **Fallback**: Lua 5.1+ or Python 3.6+
- **Optional**: Git, curl (for integration tests)

### Test Setup

The test suite uses a custom test runner and does **not** require plenary.nvim to be installed in the repository. The tests run in standalone Lua or with mocked vim APIs.

**Note**: `tests/plenary.nvim/` is not included in the repository and should not be committed. If you see this directory, it was accidentally added and should be removed from git tracking.

## Test Categories

### Core Module Tests (58 tests)

**Context Module** (`context_spec.lua`) - 9 tests
- Buffer content extraction
- Tree-sitter integration
- Import detection
- Caching mechanisms
- Multi-language support

**LLM Module** (`llm_spec.lua`) - 15 tests
- Provider abstraction (OpenAI, Anthropic, Google, Ollama)
- Request/response handling
- Error handling and timeouts
- API key validation
- Provider fallback

**Configuration** (`config_spec.lua`) - 17 tests
- Default configuration
- User config merging
- Validation and schema checking
- Environment variable loading
- Runtime updates

**Commands** (`commands_spec.lua`) - 17 tests
- Command registration and prefixing
- Setup and teardown
- Error handling
- Option preservation
- Source tracking

### Feature Tests (46 tests)

**Multi-file Operations** (`multifile_spec.lua`) - 17 tests
- Transaction management
- CRUD operations (Create, Read, Update, Delete)
- Preview functionality
- Error rollback
- Directory creation

**Testing Module** (`testing_spec.lua`) - 14 tests
- Framework detection (Jest, pytest, etc.)
- Test generation
- Test file path resolution
- Test merging and updates
- Failure analysis

**TDD Workflow** (`tdd_spec.lua`) - 15 tests
- Implementation from tests
- Property-based test generation
- Test watching and auto-execution
- Coverage analysis
- Multi-language support

### Quality Assurance (38 tests)

**Error Handling** (`error_handling_spec.lua`) - 15 tests
- Buffer access errors
- Network failures
- File system errors
- JSON parsing errors
- Memory constraints
- Graceful degradation

**Health Checks** (`health_spec.lua`) - 10 tests
- Dependency validation
- API key checking
- System requirements
- Configuration validation
- Helpful error messages

**Integration** (`integration_spec.lua`) - 13 tests
- End-to-end workflows
- Module interactions
- Plugin lifecycle
- Provider fallback
- Error scenarios

## Test Features

### Comprehensive Mocking

Each test module includes sophisticated mocking of:
- Vim API functions
- File system operations
- Network requests
- Tree-sitter parsers
- External dependencies

### Error Simulation

Tests include scenarios for:
- Network timeouts
- File system failures
- Invalid configurations
- Missing dependencies
- Malformed data

### Multi-language Support

Tests cover functionality for:
- JavaScript/TypeScript (Jest, Mocha, Vitest)
- Python (pytest, unittest)
- Go (go test)
- Rust (cargo test)
- Lua (busted)

### Real-world Scenarios

Tests simulate:
- Large codebases
- Complex project structures
- Multiple test frameworks
- CI/CD environments
- Development workflows

## Test Results

Current test suite status:
- **Total Tests**: 142
- **Passing**: 142 (100%)
- **Failing**: 0
- **Errors**: 0

### Coverage Areas

- ✅ Core functionality
- ✅ Error handling
- ✅ Edge cases
- ✅ Multi-language support
- ✅ Integration scenarios
- ✅ Performance considerations
- ✅ User workflows

## Development

### Adding New Tests

1. Create a new `*_spec.lua` file in `tests/spec/`
2. Follow the existing pattern with `describe()` and `it()` blocks
3. Include comprehensive mocking for dependencies
4. Test both success and failure scenarios
5. Run tests to ensure they pass

### Test Structure

```lua
describe("module.name", function()
  
  local function reset_state()
    -- Reset any global state
  end
  
  it("should do something specific", function()
    reset_state()
    
    -- Setup
    local input = "test input"
    
    -- Execute
    local result = module.function(input)
    
    -- Assert
    assert.is_not_nil(result, "Should return a result")
    assert.equals(result.status, "success", "Should succeed")
  end)
  
end)
```

### Best Practices

- **Isolation**: Each test should be independent
- **Clarity**: Test names should describe expected behavior
- **Coverage**: Test both happy path and error cases
- **Mocking**: Mock external dependencies consistently
- **Assertions**: Use descriptive assertion messages

## Continuous Integration

The test suite is designed to run in CI environments:

```bash
# CI-friendly test execution
./test.sh || exit 1
```

Tests are self-contained and don't require:
- Network access
- External services
- Specific file system permissions
- GUI environment

## Future Enhancements

Potential areas for expansion:
- Performance benchmarking
- Memory usage testing
- Concurrency testing
- UI interaction testing
- Plugin compatibility testing

---

This test suite provides a solid foundation for maintaining code quality and preventing regressions in Caramba.nvim development.
