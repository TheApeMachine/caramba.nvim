# caramba.nvim

An advanced AI-powered coding assistant that transforms Neovim into an AI-native development environment.
Features include intelligent code completion, refactoring, test generation, and much more.

<p align="center">
  <img src="https://img.shields.io/badge/Neovim-0.9+-green.svg" alt="Neovim 0.9+"/>
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License MIT"/>
  <img src="https://img.shields.io/badge/Lua-5.1+-purple.svg" alt="Lua 5.1+"/>
</p>

> [!WARNING]
> This project is under construction and may not work as expected.

## ✨ Features

### 🚀 Core Features

- **Smart Code Completion** - Context-aware suggestions using LLMs
- **Intelligent Refactoring** - Automated code improvements
- **Semantic Code Search** - Find code by meaning, not just text
- **Multi-File Operations** - Refactor across entire codebases
- **AI-Powered Testing** - Generate comprehensive test suites
- **Advanced Debugging** - AI-assisted error analysis
- **Interactive Chat** - ChatGPT-style interface within Neovim
- **Live Streaming Responses** - Output streams in a floating window

### 🔥 Advanced Features

- **AST-Based Transformations** - Language-aware code transformations
- **Local Code Intelligence** - Fast, offline code analysis
- **AI Pair Programming** - Real-time coding assistance
- **Smart Git Integration** - AI-powered commits and PR reviews
- **Test-Driven Development** - Implement code from tests
- **Consistency Enforcer** - Learn and enforce coding patterns
- **Web Search Integration** - Search and summarize web content
- **Tool Calling** - AI autonomously uses tools

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'your-username/caramba.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    require('ai').setup({
      -- Your configuration here
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'your-username/caramba.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    require('ai').setup({
      -- Your configuration here
    })
  end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'your-username/caramba.nvim'

" Then in your init.lua or after plug#end()
lua require('ai').setup({})
```

## ⚙️ Configuration

### Minimal Setup

```lua
require('ai').setup({
  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
    },
  },
})
```

### Full Configuration

```lua
require('ai').setup({
  -- Provider settings
  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      model = "gpt-4-turbo-preview",
      temperature = 0.7,
    },
    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
      model = "claude-3-opus-20240229",
    },
    ollama = {
      endpoint = "http://localhost:11434/api/generate",
      model = "codellama",
    },
  },
  
  -- Default provider
  provider = "openai", -- "openai", "anthropic", or "ollama"
  
  -- Feature toggles
  features = {
    auto_complete = true,
    context_tracking = true,
    pair_programming = false,
    consistency_check = true,
  },
  
  -- Context settings
  context = {
    max_lines = 100,
    include_imports = true,
    include_related = true,
  },
  
  -- Performance settings
  performance = {
    cache_responses = true,
    cache_ttl_seconds = 3600,
    max_concurrent_requests = 3,
    request_timeout_ms = 30000,
  },
  
  -- Search settings
  search = {
    exclude_dirs = {'.git', 'node_modules', 'dist', 'build'},
    include_extensions = {'lua', 'py', 'js', 'ts', 'jsx', 'tsx', 'go', 'rust'},
    max_file_size = 1024 * 1024, -- 1MB
    use_embeddings = true,
    embedding_model = "text-embedding-3-small",
    embedding_dimensions = 512,
  },
  
  -- TDD settings
  tdd = {
    auto_implement = true,
    watch_on_save = false,
    coverage_threshold = 80,
  },
  
  -- Consistency settings
  consistency = {
    auto_check = false,
    severity = "warning",
    ignore_patterns = {"test_*", "*.spec.js"},
  },
})
```

## 🔑 API Keys

Set your API keys as environment variables:

```bash
# In your shell config (.bashrc, .zshrc, etc.)
export OPENAI_API_KEY="your-openai-api-key"
export ANTHROPIC_API_KEY="your-anthropic-api-key"

# Or in your Neovim config
vim.env.OPENAI_API_KEY = "your-openai-api-key"
vim.env.ANTHROPIC_API_KEY = "your-anthropic-api-key"
```

## 📚 Commands

### Essential Commands

| Command            | Description                  |
|--------------------|------------------------------|
| `:AIComplete`      | Complete code at cursor      |
| `:AIExplain`       | Explain selected code        |
| `:AIRefactor`      | Refactor code                |
| `:AISearch`        | Search codebase semantically |
| `:AIChat`          | Open interactive chat        |
| `:AIGenerateTests` | Generate tests               |
| `:AIDebugError`    | Analyze error                |
| `:AICommitMessage` | Generate commit message      |

### All Commands

<details>
<summary>Click to expand full command list</summary>

#### Core

- `:AIComplete [instruction]` - Complete code with optional instruction
- `:AIExplain [question]` - Explain code with optional question
- `:AIRefactor <instruction>` - Refactor with instruction
- `:AISearch <query>` - Semantic search
- `:AIChat` - Toggle chat window
- `:AICancel` - Cancel active operations

#### Planning & Architecture

- `:AIPlan [task]` - Create implementation plan
- `:AIShowPlan` - Show current plan
- `:AIAnalyzeProject` - Analyze project structure
- `:AILearnPatterns` - Learn coding patterns

#### Testing & Debugging

- `:AIGenerateTests [framework]` - Generate tests
- `:AIUpdateTests` - Update existing tests
- `:AIDebugError [error]` - Analyze error
- `:AIImplementFromTest` - Implement from test spec
- `:AIWatchTests` - Watch tests for failures

#### Multi-File & Refactoring

- `:AIRenameSymbol [new_name]` - Rename across project
- `:AIExtractModule [name]` - Extract to new module
- `:AITransform [type]` - Apply AST transformation

#### Git Integration

- `:AICommitMessage` - Generate commit message
- `:AIReviewCode` - Review current code
- `:AIReviewPR` - Review pull request
- `:AIResolveConflict` - Resolve merge conflicts

#### Code Intelligence

- `:AIIndexProject` - Index for navigation
- `:AIFindDefinition` - Find symbol definition
- `:AIFindReferences` - Find references
- `:AICallHierarchy` - Show call hierarchy

#### Consistency & Quality

- `:AICheckConsistency` - Check file consistency
- `:AILearnPatterns` - Learn project patterns
- `:AIEnableConsistencyCheck` - Auto-check on save

#### Web & Research

- `:AIWebSearch <query>` - Search the web
- `:AIResearch <topic>` - Deep research
- `:AIQuery <question>` - Query with tools

</details>

## ⌨️ Default Keymaps

The plugin sets up keymaps under the `<leader>a` prefix:

```lua
<leader>ac - Complete code
<leader>ae - Explain code
<leader>ar - Refactor code
<leader>as - Search code
<leader>ap - Plan implementation
<leader>at - Open chat
<leader>ag - Generate tests
<leader>ad - Debug error
<leader>am - Commit message
<leader>aw - Web search
```

### Custom Keymaps

```lua
-- In your config
vim.keymap.set('n', '<C-k>', ':AIComplete<CR>', { desc = 'AI Complete' })
vim.keymap.set('v', '<C-k>', ':AIExplain<CR>', { desc = 'AI Explain' })
```

## 🚀 Quick Start

1. Install the plugin using your package manager
2. Set your OpenAI API key: `export OPENAI_API_KEY="sk-..."`
3. Add to your config: `require('ai').setup({})`
4. Open a file and try `:AIComplete` or `<leader>ac`
5. Results appear in a floating window as they stream back

## 📋 Requirements

- Neovim 0.9.0 or later
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- Tree-sitter parsers for your languages
- API key for at least one provider (OpenAI/Anthropic/Ollama)
- Git (for git features)
- curl (for API requests)

### Optional Dependencies

- [which-key.nvim](https://github.com/folke/which-key.nvim) - For keymap hints
- ripgrep - For faster file searching
- fd - For faster file finding

## 🏥 Health Check

Run `:checkhealth ai` to diagnose any issues with your setup.

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) first.

### Development Setup

```bash
git clone https://github.com/your-username/caramba.nvim
cd caramba.nvim

# Run tests
make test

# Lint code
make lint
```

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- Built with [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Inspired by GitHub Copilot and Cursor
- Tree-sitter integration from [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)

## 🐛 Troubleshooting

<details>
<summary>Common Issues</summary>

### No API Key Error

```bash
Error: No API key found for openai
```

**Solution**: Set your API key in environment or config

### Timeout Errors

```bash
Error: Request timeout
```

**Solution**: Increase timeout in config or check internet connection

### Parser Not Found

```bash
Error: No Tree-sitter parser for language
```

**Solution**: Install parser with `:TSInstall <language>`

</details>

## 📊 Stats

- 40+ commands
- 20+ modules
- 3 LLM providers
- 15k+ lines of code

---

<p align="center">
Made with ❤️ for the Neovim community
</p>

## Installation

## Troubleshooting

### Neovim becomes unresponsive when using AI Chat

If Neovim freezes when using the AI chat feature, this is likely due to a network timeout or API connection issue. We've added several fixes to prevent this:

1. **Enable debug mode** to see what's happening:
   ```lua
   require('caramba').setup({
     debug = true,
     -- your other config...
   })
   ```

2. **Test your connection** with the debug commands:
   ```vim
   :AITestConnection
   :AIShowConfig
   ```

3. **Common causes and solutions**:
   - **API Key not set**: Ensure your `OPENAI_API_KEY` environment variable is set
   - **Network issues**: The plugin now has a 30-second timeout on all requests
   - **API endpoint issues**: Check if the OpenAI API is accessible from your network

4. **If Neovim still hangs**:
   - The plugin should now timeout after 30 seconds instead of hanging indefinitely
   - You can kill the curl process from another terminal: `pkill -f "curl.*openai"`
   - Report the issue with debug logs enabled

### Error Messages

- **"Request timed out"**: The API didn't respond within 30 seconds. Check your internet connection.
- **"Failed to connect to API"**: Network connection failed. Check if you can access the API endpoint.
- **"Stream failed with code: X"**: Curl error. Common codes:
  - 7: Failed to connect
  - 28: Timeout
  - 35: SSL connection error

### Tree-sitter Parser Warnings

If you see "No Tree-sitter parser available for X" warnings:

1. **Parsers are now auto-installed by default!** When you open a file with a missing Tree-sitter parser, caramba.nvim will automatically install it for you.

2. **To disable auto-installation**:
   ```lua
   require('caramba').setup({
     features = {
       auto_install_parsers = false,  -- Disable automatic parser installation
     },
   })
   ```

3. **Manual installation** (if auto-install is disabled):
   ```vim
   :TSInstall <language>
   ```

4. **The warning only appears once per buffer** and won't spam you.

5. **Disable cursor context tracking entirely** if you don't need it:
   ```lua
   require('caramba').setup({
     features = {
       track_cursor_context = false,  -- Disable cursor context tracking
     },
   })
   ```

6. **Common languages without Tree-sitter parsers**:
   - Plain text files
   - Some configuration formats
   - Proprietary or very new languages

The plugin uses Tree-sitter for intelligent code analysis. Without a parser, some features like context-aware completions may be less accurate, but the plugin will still work.
