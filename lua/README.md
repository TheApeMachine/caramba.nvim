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
    require('ai').setup({
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
- `:AIComplete` - Complete code at cursor
- `:AIExplain` - Explain selected code
- `:AIRefactor <type>` - Refactor code (extract/inline/simplify)
- `:AISearch <query>` - Search codebase semantically
- `:AIChat` - Open interactive chat

### Planning & Architecture
- `:AIPlan` - Create implementation plan
- `:AIShowPlan` - Show current plan
- `:AIAnalyzeProject` - Analyze project structure
- `:AILearnPatterns` - Learn project patterns

### Testing & Debugging
- `:AIGenerateTests` - Generate tests for current code
- `:AIDebugError` - Analyze error at cursor
- `:AIImplementFromTest` - Implement code from test specification
- `:AIGeneratePropertyTests` - Generate property-based tests
- `:AIWatchTests` - Watch tests and suggest fixes
- `:AIImplementUncovered` - Implement uncovered code paths

### Multi-File & Refactoring
- `:AIRenameSymbol` - Rename across project
- `:AIExtractModule` - Extract code to new module
- `:AITransform` - Transform code using AST
- `:AITransformCallback` - Convert callbacks to async/await
- `:AITransformClass` - Convert class components to hooks
- `:AITransformImports` - Convert CommonJS to ESM

### Git Integration
- `:AICommitMessage` - Generate commit message
- `:AIReviewCode` - Review current changes
- `:AIReviewPR` - Review pull request
- `:AIExplainDiff` - Explain current diff
- `:AIResolveConflict` - Help resolve merge conflicts
- `:AIGitBlame` - Explain git blame

### Code Intelligence
- `:AIIndexProject` - Index project for navigation
- `:AIFindDefinition` - Find symbol definition
- `:AIFindReferences` - Find symbol references
- `:AIFindRelated` - Find related code
- `:AICallHierarchy` - Show call hierarchy
- `:AIFindSimilar` - Find similar functions

### Consistency & Quality
- `:AICheckConsistency` - Check file for consistency issues
- `:AILearnPatterns` - Learn coding patterns from codebase
- `:AIEnableConsistencyCheck` - Auto-check on save

### Pair Programming
- `:AIPairStart` - Start pair programming session
- `:AIPairStop` - Stop pair programming session
- `:AIPairToggle` - Toggle pair programming
- `:AIPairStatus` - Show session status

### Web & Research
- `:AIWebSearch <query>` - Search the web
- `:AIWebSummary <url>` - Summarize web page
- `:AIResearch <topic>` - Research topic online
- `:AIQuery <question>` - Query with tool access

### Utility Commands
- `:AICancel` - Cancel current operation
- `:AISetModel <model>` - Change AI model
- `:AISetProvider <provider>` - Change provider
- `:AIShowContext` - Show current context

## Test-Driven Development Assistant

The TDD Assistant helps you write code by implementing functionality from test specifications:

### Features
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
   Run `:AIImplementFromTest` to generate the implementation.

2. **Property Testing**:
   Place cursor on a function and run `:AIGeneratePropertyTests` to create property-based tests that check invariants.

3. **Test Watching**:
   Run `:AIWatchTests` to monitor test execution. When tests fail, AI will analyze failures and suggest fixes.

4. **Coverage Gaps**:
   Run `:AIImplementUncovered` to find code paths without test coverage and generate appropriate tests.

## Project-Wide Consistency Enforcer

The Consistency Enforcer learns your project's coding patterns and helps maintain them:

### Features
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

### Usage

1. **Learn Project Patterns**:
   ```vim
   :AILearnPatterns
   ```
   Analyzes your entire codebase to learn conventions.

2. **Check Current File**:
   ```vim
   :AICheckConsistency
   ```
   Shows consistency issues in the current file.

3. **Enable Auto-Check**:
   ```vim
   :AIEnableConsistencyCheck
   ```
   Automatically checks files on save and shows issues as diagnostics.

4. **Fix Issues**:
   In the consistency report buffer:
   - Press `f` to fix issue at cursor
   - Press `a` to apply all fixes
   - Press `i` to ignore an issue

### Example Consistency Report
```
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

```
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

```
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

Run `:checkhealth ai` to diagnose issues.

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
