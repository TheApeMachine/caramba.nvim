-- Caramba Agentic System
-- Provides autonomous file reading and action capabilities

local M = {}

-- Dependencies
local Path = require('plenary.path')
local utils = require('caramba.utils')
local llm = require('caramba.llm')
local memory = require('caramba.memory')

-- Available agent tools
M.tools = {
  read_file = {
    name = "read_file",
    description = "Read the contents of a file",
    parameters = {
      file_path = "string: Path to the file to read"
    }
  },
  
  list_files = {
    name = "list_files", 
    description = "List files in a directory",
    parameters = {
      directory = "string: Directory path to list",
      pattern = "string: Optional file pattern to filter (e.g., '*.lua')"
    }
  },
  
  search_memory = {
    name = "search_memory",
    description = "Search long-term memory for relevant information",
    parameters = {
      query = "string: Search query",
      context = "string: Optional context to improve search"
    }
  },
  
  get_open_buffers = {
    name = "get_open_buffers",
    description = "Get list of currently open buffers/files",
    parameters = {}
  },
  
  analyze_code = {
    name = "analyze_code",
    description = "Analyze code structure and patterns",
    parameters = {
      file_path = "string: Path to file to analyze",
      focus = "string: Optional focus area (functions, classes, imports, etc.)"
    }
  }
}

-- Execute a tool
function M.execute_tool(tool_name, parameters)
  if tool_name == "read_file" then
    return M._read_file(parameters.file_path)
    
  elseif tool_name == "list_files" then
    return M._list_files(parameters.directory, parameters.pattern)
    
  elseif tool_name == "search_memory" then
    return M._search_memory(parameters.query, parameters.context)
    
  elseif tool_name == "get_open_buffers" then
    return M._get_open_buffers()
    
  elseif tool_name == "analyze_code" then
    return M._analyze_code(parameters.file_path, parameters.focus)
    
  else
    return { error = "Unknown tool: " .. tool_name }
  end
end

-- Read file contents
function M._read_file(file_path)
  if not file_path then
    return { error = "file_path is required" }
  end
  
  local path = Path:new(file_path)
  if not path:exists() then
    return { error = "File does not exist: " .. file_path }
  end
  
  if path:is_dir() then
    return { error = "Path is a directory, not a file: " .. file_path }
  end
  
  local ok, content = pcall(function()
    return path:read()
  end)
  
  if not ok then
    return { error = "Failed to read file: " .. file_path }
  end
  
  return {
    file_path = file_path,
    content = content,
    size = #content,
    lines = vim.split(content, '\n')
  }
end

-- List files in directory
function M._list_files(directory, pattern)
  directory = directory or vim.fn.getcwd()
  
  local path = Path:new(directory)
  if not path:exists() or not path:is_dir() then
    return { error = "Directory does not exist: " .. directory }
  end
  
  local files = {}
  local ok, entries = pcall(function()
    return path:fs_scandir()
  end)
  
  if not ok then
    return { error = "Failed to scan directory: " .. directory }
  end
  
  for name, type in entries do
    if not pattern or name:match(pattern) then
      table.insert(files, {
        name = name,
        type = type,
        path = path:joinpath(name):absolute()
      })
    end
  end
  
  return {
    directory = directory,
    pattern = pattern,
    files = files,
    count = #files
  }
end

-- Search memory
function M._search_memory(query, context)
  if not query then
    return { error = "query is required" }
  end
  
  local results = memory.search_multi_angle(query, context and { context = context } or nil, nil)
  
  local formatted_results = {}
  for _, result in ipairs(results) do
    table.insert(formatted_results, {
      content = result.entry.content,
      context = result.entry.context,
      relevance = result.relevance,
      source = result.source,
      timestamp = result.entry.timestamp
    })
  end
  
  return {
    query = query,
    results = formatted_results,
    count = #formatted_results
  }
end

-- Get open buffers
function M._get_open_buffers()
  local buffers = {}
  
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'buflisted') then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name and name ~= "" then
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        table.insert(buffers, {
          bufnr = bufnr,
          name = name,
          filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype'),
          modified = vim.api.nvim_buf_get_option(bufnr, 'modified'),
          line_count = #lines,
          size = table.concat(lines, '\n'):len()
        })
      end
    end
  end
  
  return {
    buffers = buffers,
    count = #buffers
  }
end

-- Analyze code structure
function M._analyze_code(file_path, focus)
  local file_result = M._read_file(file_path)
  if file_result.error then
    return file_result
  end
  
  local content = file_result.content
  local analysis = {
    file_path = file_path,
    language = vim.filetype.match({ filename = file_path }) or "unknown",
    line_count = #file_result.lines,
    size = file_result.size
  }
  
  -- Basic analysis based on file type
  if analysis.language == "lua" then
    analysis.functions = M._extract_lua_functions(content)
    analysis.requires = M._extract_lua_requires(content)
  elseif analysis.language == "javascript" or analysis.language == "typescript" then
    analysis.functions = M._extract_js_functions(content)
    analysis.imports = M._extract_js_imports(content)
  end
  
  return analysis
end

-- Extract Lua functions
function M._extract_lua_functions(content)
  local functions = {}
  for line in content:gmatch("[^\r\n]+") do
    local func_match = line:match("function%s+([%w_.]+)")
    if func_match then
      table.insert(functions, func_match)
    end
  end
  return functions
end

-- Extract Lua requires
function M._extract_lua_requires(content)
  local requires = {}
  for line in content:gmatch("[^\r\n]+") do
    local req_match = line:match("require%s*%(?['\"]([^'\"]+)['\"]")
    if req_match then
      table.insert(requires, req_match)
    end
  end
  return requires
end

-- Extract JavaScript functions
function M._extract_js_functions(content)
  local functions = {}
  for line in content:gmatch("[^\r\n]+") do
    local func_match = line:match("function%s+([%w_]+)") or 
                      line:match("const%s+([%w_]+)%s*=%s*function") or
                      line:match("([%w_]+)%s*:%s*function")
    if func_match then
      table.insert(functions, func_match)
    end
  end
  return functions
end

-- Extract JavaScript imports
function M._extract_js_imports(content)
  local imports = {}
  for line in content:gmatch("[^\r\n]+") do
    local import_match = line:match("import.+from%s+['\"]([^'\"]+)['\"]") or
                        line:match("require%s*%(['\"]([^'\"]+)['\"]")
    if import_match then
      table.insert(imports, import_match)
    end
  end
  return imports
end

return M
