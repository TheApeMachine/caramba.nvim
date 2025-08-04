---
description: Repository Information Overview
alwaysApply: true
---

# Caramba.nvim Information

## Summary
Caramba.nvim is an advanced AI-powered coding assistant that transforms Neovim into an AI-native development environment. It provides intelligent code completion, refactoring, test generation, and many other features to enhance the coding experience within Neovim.

## Structure
- **lua/caramba/**: Core plugin modules implementing various features
- **plugin/**: Neovim plugin initialization and keymaps
- **tests/**: Test suite with specs and test runner
- **.zencoder/**: Documentation and rules
- **.augment/**: Additional rules for the plugin

## Language & Runtime
**Language**: Lua
**Version**: Lua 5.1+
**Neovim Version**: 0.9+
**Package Manager**: None (Neovim plugin)

## Dependencies
**Main Dependencies**:
- nvim-lua/plenary.nvim (Lua utility functions)
- nvim-treesitter/nvim-treesitter (Syntax parsing)

**Optional Dependencies**:
- folke/which-key.nvim (Keymap hints)
- ripgrep (Faster file searching)
- fd (Faster file finding)

## Build & Installation
```bash
# Using lazy.nvim
require('lazy').setup({
  'theapemachine/caramba.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    require('caramba').setup({})
  end,
})

# Using packer.nvim
use {
  'theapemachine/caramba.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    require('caramba').setup({})
  end,
}
```

## Testing
**Framework**: Custom Lua test framework
**Test Location**: tests/spec/
**Naming Convention**: *_spec.lua
**Configuration**: tests/init.lua, tests/test_runner.lua
**Run Command**:
```bash
./test.sh
```

## Features
**Core Features**:
- Smart Code Completion
- Intelligent Refactoring
- Semantic Code Search
- Multi-File Operations
- AI-Powered Testing
- Advanced Debugging
- Interactive Chat
- Live Streaming Responses

**Advanced Features**:
- AST-Based Transformations
- Local Code Intelligence
- AI Pair Programming
- Smart Git Integration
- Test-Driven Development
- Consistency Enforcer
- Web Search Integration
- Tool Calling

## Configuration
**Configuration File**: lua/caramba/config.lua
**Main Settings**:
- LLM Provider (OpenAI, Anthropic, Ollama, Google)
- Context extraction settings
- Editing settings
- Search and indexing options
- Feature toggles
- UI settings
- Performance settings
- Web search settings

## Commands
**Key Commands**:
- `:CarambaComplete` - Complete code at cursor
- `:CarambaExplain` - Explain selected code
- `:CarambaRefactor` - Refactor code
- `:CarambaSearch` - Search codebase semantically
- `:CarambaChat` - Open interactive chat
- `:CarambaGenerateTests` - Generate tests
- `:CarambaDebugError` - Analyze error
- `:CarambaCommitMessage` - Generate commit message

**Default Keymaps**:
- `<leader>ac` - Complete code
- `<leader>ae` - Explain code
- `<leader>ar` - Refactor code
- `<leader>as` - Search code
- `<leader>ap` - Plan implementation
- `<leader>at` - Open chat
- `<leader>ag` - Generate tests