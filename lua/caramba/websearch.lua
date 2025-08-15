-- Web Search Module
-- Provides internet search capabilities for the AI assistant

local M = {}

local Job = require('plenary.job')
local config = require('caramba.config')
local llm = require('caramba.llm')

-- Search providers configuration
M.providers = {
  -- DuckDuckGo (no API key required)
  duckduckgo = {
    search = function(query, opts)
      opts = opts or {}
      local limit = opts.limit or 5
      
      -- Use DuckDuckGo's HTML version and parse it
      -- Note: For production, consider using their API
      local url = "https://html.duckduckgo.com/html/"
      
      local job = Job:new({
        command = "curl",
        args = {
          "-s",
          "-G",
          url,
          "--data-urlencode", "q=" .. query,
          "-H", "User-Agent: Mozilla/5.0 (compatible; AI Assistant)",
        },
        on_exit = function(j, return_val)
          if return_val ~= 0 then
            opts.callback(nil, "Search request failed")
            return
          end
          
          local html = table.concat(j:result(), "\n")
          local results = M._parse_duckduckgo_html(html, limit)
          opts.callback(results, nil)
        end,
      })
      
      job:start()
    end,
  },
  
  -- Google Custom Search (requires API key)
  google = {
    search = function(query, opts)
      opts = opts or {}
      local api_key = opts.api_key or os.getenv("GOOGLE_API_KEY")
      local cx = opts.search_engine_id or os.getenv("GOOGLE_SEARCH_ENGINE_ID")
      
      if not api_key or not cx then
        opts.callback(nil, "Google search requires GOOGLE_API_KEY and GOOGLE_SEARCH_ENGINE_ID")
        return
      end
      
      local limit = opts.limit or 5
      local url = "https://www.googleapis.com/customsearch/v1"
      
      local job = Job:new({
        command = "curl",
        args = {
          "-s",
          "-G",
          url,
          "--data-urlencode", "key=" .. api_key,
          "--data-urlencode", "cx=" .. cx,
          "--data-urlencode", "q=" .. query,
          "--data-urlencode", "num=" .. tostring(limit),
        },
        on_exit = function(j, return_val)
          if return_val ~= 0 then
            opts.callback(nil, "Search request failed")
            return
          end
          
          local response = table.concat(j:result(), "\n")
          local ok, data = pcall(vim.json.decode, response)
          
          if not ok then
            opts.callback(nil, "Failed to parse response")
            return
          end
          
          local results = {}
          if data.items then
            for _, item in ipairs(data.items) do
              table.insert(results, {
                title = item.title,
                url = item.link,
                snippet = item.snippet,
              })
            end
          end
          
          opts.callback(results, nil)
        end,
      })
      
      job:start()
    end,
  },
  
  -- Brave Search (requires API key)
  brave = {
    search = function(query, opts)
      opts = opts or {}
      local api_key = opts.api_key or os.getenv("BRAVE_API_KEY")
      
      if not api_key then
        opts.callback(nil, "Brave search requires BRAVE_API_KEY")
        return
      end
      
      local limit = opts.limit or 5
      local url = "https://api.search.brave.com/res/v1/web/search"
      
      local job = Job:new({
        command = "curl",
        args = {
          "-s",
          "-G",
          url,
          "--data-urlencode", "q=" .. query,
          "--data-urlencode", "count=" .. tostring(limit),
          "-H", "X-Subscription-Token: " .. api_key,
          "-H", "Accept: application/json",
        },
        on_exit = function(j, return_val)
          if return_val ~= 0 then
            opts.callback(nil, "Search request failed")
            return
          end
          
          local response = table.concat(j:result(), "\n")
          local ok, data = pcall(vim.json.decode, response)
          
          if not ok then
            opts.callback(nil, "Failed to parse response")
            return
          end
          
          local results = {}
          if data.web and data.web.results then
            for _, item in ipairs(data.web.results) do
              table.insert(results, {
                title = item.title,
                url = item.url,
                snippet = item.description,
              })
            end
          end
          
          opts.callback(results, nil)
        end,
      })
      
      job:start()
    end,
  },
}

-- Parse DuckDuckGo HTML results
M._parse_duckduckgo_html = function(html, limit)
  local results = {}
  local count = 0
  
  -- Simple HTML parsing for results
  -- Look for result blocks
  for result_block in html:gmatch('<div class="results_links[^"]*">(.-)</div>') do
    if count >= limit then break end
    
    -- Extract URL
    local url = result_block:match('<a[^>]+href="([^"]+)"')
    
    -- Extract title (remove HTML tags)
    local title_block = result_block:match('<a[^>]+>(.-)</a>')
    local title = title_block and title_block:gsub("<[^>]+>", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    
    -- Extract snippet
    local snippet = result_block:match('<a class="result__snippet"[^>]*>(.-)</a>')
    if snippet then
      snippet = snippet:gsub("<[^>]+>", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    end
    
    if url and title then
      table.insert(results, {
        title = title,
        url = url,
        snippet = snippet or "",
      })
      count = count + 1
    end
  end
  
  return results
end

-- Fetch and extract content from a URL
M.fetch_url = function(url, callback)
  -- Use curl with appropriate options
  local job = Job:new({
    command = "curl",
    args = {
      "-s",
      "-L", -- Follow redirects
      "--max-time", "10",
      "-H", "User-Agent: Mozilla/5.0 (compatible; AI Assistant)",
      url,
    },
    on_exit = function(j, return_val)
      if return_val ~= 0 then
        callback(nil, "Failed to fetch URL")
        return
      end
      
      local html = table.concat(j:result(), "\n")
      
      -- Extract text content from HTML
      local content = M._extract_text_from_html(html)
      callback(content, nil)
    end,
  })
  
  job:start()
end

-- Extract readable text from HTML
M._extract_text_from_html = function(html)
  -- Remove script and style blocks
  html = html:gsub("<script.-</script>", "")
  html = html:gsub("<style.-</style>", "")
  
  -- Extract title
  local title = html:match("<title>(.-)</title>") or ""
  
  -- Try to find main content areas
  local content = ""
  
  -- Look for article or main content
  local article = html:match('<article[^>]*>(.-)</article>') or
                  html:match('<main[^>]*>(.-)</main>') or
                  html:match('<div[^>]+role="main"[^>]*>(.-)</div>')
  
  if article then
    content = article
  else
    -- Fallback to body content
    content = html:match('<body[^>]*>(.-)</body>') or html
  end
  
  -- Remove HTML tags
  content = content:gsub("<[^>]+>", " ")
  
  -- Clean up whitespace
  content = content:gsub("%s+", " ")
  content = content:match("^%s*(.-)%s*$")
  
  -- Limit length
  if #content > 5000 then
    content = content:sub(1, 5000) .. "..."
  end
  
  return title .. "\n\n" .. content
end

-- Perform a web search
M.search = function(query, opts)
  opts = opts or {}
  local provider = opts.provider or "duckduckgo"
  
  if not M.providers[provider] then
    vim.notify("Unknown search provider: " .. provider, vim.log.levels.ERROR)
    return
  end
  
  -- Show searching notification
  vim.notify("Searching web for: " .. query, vim.log.levels.INFO)
  
  M.providers[provider].search(query, {
    limit = opts.limit or 5,
    api_key = opts.api_key,
    search_engine_id = opts.search_engine_id,
    callback = function(results, err)
      if err then
        vim.notify("Search error: " .. err, vim.log.levels.ERROR)
        if opts.callback then
          opts.callback(nil, err)
        end
        return
      end
      
      -- Format results
      local formatted = M._format_results(results)
      
      if opts.callback then
        opts.callback(formatted, nil)
      else
        -- Show results in a buffer
        M._show_results(query, results)
      end
    end,
  })
end

-- Format search results for display
M._format_results = function(results)
  local lines = {}
  
  for i, result in ipairs(results) do
    table.insert(lines, string.format("%d. %s", i, result.title))
    table.insert(lines, "   " .. result.url)
    if result.snippet and result.snippet ~= "" then
      table.insert(lines, "   " .. result.snippet)
    end
    table.insert(lines, "")
  end
  
  return table.concat(lines, "\n")
end

-- Show search results in a buffer
M._show_results = function(query, results)
  vim.schedule(function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
    
    local lines = {
      "# Web Search Results",
      "",
      "**Query:** " .. query,
      "",
    }
    
    for i, result in ipairs(results) do
      table.insert(lines, string.format("## %d. %s", i, result.title))
      table.insert(lines, "")
      table.insert(lines, "**URL:** " .. result.url)
      table.insert(lines, "")
      if result.snippet and result.snippet ~= "" then
        table.insert(lines, result.snippet)
        table.insert(lines, "")
      end
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Open in a centered window
    local ui = require('caramba.ui')
    ui.show_lines_centered(lines, { title = ' Web Search Results ', filetype = 'markdown' })
    
    -- Add keymaps to open URLs
    for i = 1, #results do
      vim.keymap.set('n', tostring(i), function()
        local url = results[i].url
        -- Try to open URL in browser
        local open_cmd = vim.fn.has('mac') == 1 and 'open' or 'xdg-open'
        vim.fn.system(open_cmd .. ' ' .. vim.fn.shellescape(url))
        vim.notify("Opening: " .. url)
      end, { buffer = buf, desc = "Open URL " .. i })
    end
    
    -- Add keymap to fetch content
    vim.keymap.set('n', 'f', function()
      local line = vim.fn.line('.')
      local result_idx = nil
      
      -- Find which result we're on
      for i = 1, #results do
        local pattern = "^## " .. i .. "%."
        for j = line, 1, -1 do
          local line_text = vim.fn.getline(j)
          if line_text:match(pattern) then
            result_idx = i
            break
          end
        end
        if result_idx then break end
      end
      
      if result_idx and results[result_idx] then
        M.fetch_url(results[result_idx].url, function(content, err)
          if err then
            vim.notify("Failed to fetch content: " .. err, vim.log.levels.ERROR)
            return
          end
          
          vim.schedule(function()
            -- Show content in a centered window
            local ui = require('caramba.ui')
            local content_lines = vim.split(content, "\n")
            ui.show_lines_centered(content_lines, { title = ' Page Content ', filetype = 'text' })
          end)
        end)
      end
    end, { buffer = buf, desc = "Fetch page content" })
  end)
end

-- Search and summarize results with AI
M.search_and_summarize = function(query, opts)
  opts = opts or {}
  
  M.search(query, {
    provider = opts.provider,
    limit = opts.limit or 3,
    callback = function(formatted_results, err)
      if err then
        vim.notify("Search failed: " .. err, vim.log.levels.ERROR)
        return
      end
      
      -- Build prompt for AI
      local prompt = string.format([[
I searched the web for: "%s"

Here are the search results:

%s

Please provide a comprehensive summary of the key information found, focusing on:
1. The most relevant and accurate information
2. Any consensus or common themes across sources
3. Important details that answer the query
4. Any contradictions or caveats to be aware of

Format your response clearly with sections as appropriate.
]], query, formatted_results)
      
      -- Get AI summary
      llm.request(prompt, { temperature = 1 }, function(summary)
        if summary then
          vim.schedule(function()
            -- Show summary
            local ui = require('caramba.ui')
            local lines = {
              "# Web Search Summary",
              "",
              "**Query:** " .. query,
              "",
              "---",
              "",
            }
            vim.list_extend(lines, vim.split(summary, "\n"))
            ui.show_lines_centered(lines, { title = ' Web Search Summary ', filetype = 'markdown' })
          end)
        end
      end)
    end,
  })
end

-- Research a topic with deep search
M.research_topic = function(topic, opts)
  opts = opts or {}
  
  -- Generate search queries
  local search_prompt = string.format([[
Generate 3-5 specific search queries to thoroughly research the topic: "%s"

Consider different angles:
- Technical documentation
- Best practices
- Common issues and solutions
- Recent developments
- Comparisons and alternatives

Output only the search queries, one per line.
]], topic)
  
  llm.request(search_prompt, { temperature = 1 }, function(response)
    if not response then
      vim.notify("Failed to generate search queries", vim.log.levels.ERROR)
      return
    end
    
    local queries = vim.split(response, "\n")
    local all_results = {}
    local completed = 0
    
    -- Search for each query
    for _, query in ipairs(queries) do
      if query and query ~= "" then
        M.search(query, {
          limit = 3,
          callback = function(results, err)
            completed = completed + 1
            
            if results then
              table.insert(all_results, {
                query = query,
                results = results,
              })
            end
            
            -- When all searches complete, summarize
            if completed >= #queries then
              M._summarize_research(topic, all_results)
            end
          end,
        })
      end
    end
  end)
end

-- Summarize research results
M._summarize_research = function(topic, all_results)
  -- Build comprehensive prompt
  local prompt = string.format([[
I've researched the topic: "%s"

Here are the search results from multiple queries:

]], topic)
  
  for _, search in ipairs(all_results) do
    prompt = prompt .. string.format("\n## Query: %s\n%s\n", 
      search.query, search.results)
  end
  
  prompt = prompt .. [[

Please create a comprehensive research summary that:
1. Synthesizes information from all sources
2. Organizes findings into logical sections
3. Highlights key insights and important details
4. Notes any conflicting information or different perspectives
5. Provides practical recommendations or conclusions
6. Lists the most authoritative sources for further reading

Format as a well-structured technical document.
]]

  llm.request(prompt, { temperature = 1 }, function(summary)
    if summary then
      vim.schedule(function()
        -- Create research document
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
        vim.api.nvim_buf_set_name(buf, "Research: " .. topic)
        
        local lines = {
          "# Research Summary: " .. topic,
          "",
          "*Generated on " .. os.date("%Y-%m-%d %H:%M:%S") .. "*",
          "",
          "---",
          "",
        }
        
        vim.list_extend(lines, vim.split(summary, "\n"))
        
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        
        -- Open in a new tab
        vim.cmd('tabnew')
        vim.api.nvim_set_current_buf(buf)
      end)
    end
  end)
end

-- Setup commands for this module
M.setup_commands = function()
  local commands = require('caramba.core.commands')
  
  -- Web search command
  commands.register('WebSearch', function(args)
    local query = args.args
    if query == "" then
      vim.ui.input({
        prompt = "Search query: ",
      }, function(input)
        if input and input ~= "" then
          M.search(input)
        end
      end)
    else
      M.search(query)
    end
  end, {
    desc = 'Search the web',
    nargs = '?',
  })
  
  -- Search and summarize
  commands.register('WebSearchSummarize', function(args)
    local query = args.args
    if query == "" then
      vim.ui.input({
        prompt = "Search query: ",
      }, function(input)
        if input and input ~= "" then
          M.search_and_summarize(input)
        end
      end)
    else
      M.search_and_summarize(query)
    end
  end, {
    desc = 'Search web and summarize with AI',
    nargs = '?',
  })
  
  -- Research topic
  commands.register('ResearchTopic', function(args)
    local topic = args.args
    if topic == "" then
      vim.ui.input({
        prompt = "Research topic: ",
      }, function(input)
        if input and input ~= "" then
          M.research_topic(input)
        end
      end)
    else
      M.research_topic(topic)
    end
  end, {
    desc = 'Deep research on a topic',
    nargs = '?',
  })
end

return M 