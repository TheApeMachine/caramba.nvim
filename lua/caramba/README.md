# AI Assistant for Neovim

A comprehensive AI-powered coding assistant that integrates directly into Neovim, providing intelligent code completion, refactoring, and analysis capabilities.

## Features

### Core Features

- **Smart Code Completion** - Context-aware code suggestions using LLMs
- **Code Explanation** - Understand complex code with AI-powered explanations
- **Intelligent Refactoring** - Automated code improvements and transformations
- **Semantic Code Search** - Find code by meaning, not just text
- **Multi-File Operations** - Refactor across entire codebases
- **AI-Powered Testing** - Generate comprehensive test suites automatically
- **Advanced Debugging** - AI-assisted error analysis and fixes
- **Interactive Chat** - ChatGPT-style interface within Neovim

### Advanced Features

- **AST-Based Transformations** - Language-aware code transformations
- **Local Code Intelligence** - Fast, offline code analysis and navigation
- **AI Pair Programming** - Real-time coding assistance and suggestions
- **Smart Git Integration** - AI-powered commit messages and PR reviews
- **Test-Driven Development Assistant** - Implement code from tests
- **Project-Wide Consistency Enforcer** - Learn and enforce coding patterns
- **Web Search Integration** - Search and summarize web content
- **Tool Calling** - AI autonomously uses tools to answer queries

## Installation

Add to your Neovim configuration:

```lua
-- In your plugin manager (e.g., lazy.nvim)
{
  'your-username/caramba.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    require('caramba').setup({
      -- Optional configuration
      providers = {
        openai = {
          api_key = vim.env.OPENAI_API_KEY,
          model = "gpt-4-turbo-preview",
        },
      },
    })
  end,
}
```

## Commands

### Basic Commands

- `:CarambaComplete` - Complete code at cursor
- `:CarambaExplain` - Explain selected code
- `:CarambaRefactor <type>` - Refactor code (extract/inline/simplify)
- `:CarambaSearch <query>` - Search codebase semantically
- `:CarambaChat` - Open interactive chat

### Planning & Architecture

- `:CarambaPlan` - Create implementation plan
- `:CarambaShowPlan` - Show current plan
- `:CarambaAnalyzeProject` - Analyze project structure
- `:CarambaLearnPatterns` - Learn project patterns

### Testing & Debugging

- `:CarambaGenerateTests` - Generate tests for current code
- `:CarambaDebugError` - Analyze error at cursor
- `:CarambaImplementFromTest` - Implement code from test specification
- `:CarambaGeneratePropertyTests` - Generate property-based tests
- `:CarambaWatchTests` - Watch tests and suggest fixes
- `:CarambaImplementUncovered` - Implement uncovered code paths

### Multi-File & Refactoring

- `:CarambaRenameSymbol` - Rename across project
- `:CarambaExtractModule` - Extract code to new module
- `:CarambaTransform` - Transform code using AST
- `:CarambaTransformCallback` - Convert callbacks to async/await
- `:CarambaMigratePattern` - Apply migration pattern

### Git Integration

- `:CarambaCommitMessage` - Generate commit message
- `:CarambaReviewCode` - Review current changes
- `:CarambaReviewPR` - Review pull request
- `:CarambaExplainDiff` - Explain current diff
- `:CarambaResolveConflict` - Help resolve merge conflicts
- `:CarambaGitBlame` - Explain git blame

### Code Intelligence

- `:CarambaIndexProject` - Index project for navigation
- `:CarambaFindDefinition` - Find symbol definition
- `:CarambaFindReferences` - Find symbol references
- `:CarambaFindRelated` - Find related code
- `:CarambaCallHierarchy` - Show call hierarchy
- `:CarambaFindSimilar` - Find similar functions

### Consistency & Quality

- `:CarambaCheckConsistency` - Check file for consistency issues
- `:CarambaLearnPatterns` - Learn coding patterns from codebase
- `:CarambaEnableConsistencyCheck` - Auto-check on save

### Pair Programming

- `:CarambaPairStart` - Start pair programming session
- `:CarambaPairStop` - Stop pair programming session
- `:CarambaPairToggle` - Toggle pair programming
- `:CarambaPairStatus` - Show session status

### Web & Research

- `:CarambaWebSearch <query>` - Search the web
- `:CarambaWebSummary <url>` - Summarize web page
- `:CarambaResearch <topic>` - Research topic online
- `:CarambaQuery <question>` - Query with tool access

### Utility Commands

- `:CarambaCancel` - Cancel current operation
- `:CarambaSetModel <model>` - Change AI model
- `:CarambaSetProvider <provider>` - Change provider
- `:CarambaShowContext` - Show current context

## Test-Driven Development Assistant

The TDD Assistant helps you write code by implementing functionality from test specifications:

### Test-Driven Development Features

- **Test-First Implementation** - Write tests, then let AI implement the code
- **Property-Based Testing** - Generate comprehensive property tests
- **Test Watching** - Monitor test execution and suggest fixes
- **Coverage Analysis** - Find and implement uncovered code paths

### Usage

1. **Implement from Test**:

   ```javascript
   // Write your test first
   describe('Calculator', () => {
     it('should add two numbers', () => {
       expect(add(2, 3)).toBe(5);
     });
   });
   ```

   Run `:CarambaImplementFromTest` to generate the implementation.

2. **Property Testing**:
   Place cursor on a function and run `:CarambaGeneratePropertyTests` to create property-based tests that check invariants.

3. **Test Watching**:
   Run `:CarambaWatchTests` to monitor test execution. When tests fail, AI will analyze failures and suggest fixes.

4. **Coverage Gaps**:
   Run `:CarambaImplementUncovered` to find code paths without test coverage and generate appropriate tests.

## Project-Wide Consistency Enforcer

The Consistency Enforcer learns your project's coding patterns and helps maintain them:

### Consistency Enforcer Features

- **Pattern Learning** - Analyzes your codebase to learn conventions
- **Real-time Checking** - Validates code against learned patterns
- **Auto-fixing** - Suggests and applies fixes for inconsistencies
- **Multi-aspect Analysis** - Checks naming, structure, style, and architecture

### Pattern Categories

1. **Naming Conventions**:
   - Function naming (camelCase, snake_case, etc.)
   - Variable naming patterns
   - Class naming standards
   - Common prefixes/suffixes

2. **Code Structure**:
   - Import organization
   - File organization
   - Module boundaries
   - Export patterns

3. **Style Consistency**:
   - Indentation standards
   - Line length limits
   - Comment styles
   - Formatting rules

4. **Architecture Compliance**:
   - Layer separation (MVC, Clean Architecture)
   - Dependency rules
   - Module boundaries
   - Anti-pattern detection

### Project-Wide Consistency Enforcer Usage

1. **Learn Project Patterns**:

   ```vim
   :CarambaLearnPatterns
   ```

   Analyzes your entire codebase to learn conventions.

2. **Check Current File**:

   ```vim
   :CarambaCheckConsistency
   ```

   Shows consistency issues in the current file.

3. **Enable Auto-Check**:

   ```vim
   :CarambaEnableConsistencyCheck
   ```

   Automatically checks files on save and shows issues as diagnostics.

4. **Fix Issues**:
   In the consistency report buffer:
   - Press `f` to fix issue at cursor
   - Press `a` to apply all fixes
   - Press `i` to ignore an issue

### Example Consistency Report

```text
# Consistency Report

Found 3 consistency issues

## Naming
⚠️ Line 15: function 'get_user_data' doesn't follow camelCase convention
⚠️ Line 23: variable 'UserName' doesn't follow camelCase convention

## Import Order
💡 Line 3: Import 'react' should come before 'external' imports

## Quick Actions
- Press `f` to auto-fix issues
- Press `i` to ignore an issue
- Press `a` to apply all fixes
```

## Configuration

```lua
require('caramba').setup({
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
  },

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

  -- TDD settings
  tdd = {
    auto_implement = true,
    watch_on_save = false,
    coverage_threshold = 80,
  },

  -- Consistency settings
  consistency = {
    auto_check = false,
    severity = "warning", -- hint, warning, error
    ignore_patterns = {
      "test_*",
      "*.spec.js",
    },
  },
})
```

## Key Mappings

Default mappings under `<leader>a`:

```text
<leader>ac - Complete code
<leader>ae - Explain code
<leader>ar - Refactor code
<leader>as - Search code
<leader>ap - Plan implementation
<leader>at - Open chat
<leader>ag - Generate tests
<leader>ad - Debug error
<leader>am - Generate commit message
<leader>aw - Web search
<leader>aq - Query with tools
<leader>ax - Transform code
<leader>ai - Implement from test
<leader>ao - Check consistency
```

## Architecture

The AI assistant is modular and extensible:

```text
ai/
├── init.lua           # Main module loader
├── config.lua         # Configuration management
├── context.lua        # Context extraction
├── llm.lua           # LLM provider abstraction
├── edit.lua          # Safe code editing
├── refactor.lua      # Refactoring operations
├── search.lua        # Semantic search
├── testing.lua       # Test generation
├── debug.lua         # Error analysis
├── chat.lua          # Interactive chat
├── multifile.lua     # Multi-file operations
├── planner.lua       # Planning system
├── embeddings.lua    # Embedding management
├── websearch.lua     # Web search integration
├── tools.lua         # Tool calling system
├── ast_transform.lua # AST transformations
├── intelligence.lua  # Code intelligence
├── pair.lua          # Pair programming
├── git.lua           # Git integration
├── tdd.lua           # TDD assistant
├── consistency.lua   # Consistency enforcer
├── health.lua        # Health checks
└── commands.lua      # Command definitions
```

## Requirements

- Neovim 0.9+
- Tree-sitter parsers for your languages
- API keys for AI providers (OpenAI/Anthropic/Ollama)
- Git (for git integration features)
- Internet connection (for web search features)

## Performance Tips

1. **Use local models** (Ollama) for faster responses
2. **Enable caching** to avoid redundant API calls
3. **Limit context size** for large files
4. **Use embeddings** for large codebases
5. **Index project** once for better navigation

## Troubleshooting

Run `:checkhealth caramba` to diagnose issues.

Common issues:

- **No API key**: Set environment variables
- **Timeout errors**: Increase timeout in config
- **Context too large**: Reduce max_lines in config
- **Parser errors**: Install Tree-sitter parsers

## Contributing

Contributions welcome! The codebase is modular and well-documented.

Areas for contribution:

- Additional language support
- New transformation patterns
- Performance optimizations
- Additional tool integrations
- UI improvements

## License

MIT
