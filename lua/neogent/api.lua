-- neogent.nvim - Anthropic API client with streaming
local M = {}

local tools = require("neogent.tools")

local config = {
    base_url = "https://api.anthropic.com/v1/messages",
    api_key = nil,
    model = "claude-sonnet-4-20250514",
    max_tokens = 4096,
    system_prompt = [[You are an expert coding assistant integrated into Neovim. Your goal is to help the user write, refactor, and debug code efficiently while respecting the editor's state and file system integrity.

You have tools available for file operations, code search, and command execution. Refer to your tool definitions for details on each tool's purpose and parameters.

## Core Principles
- **Safety First**: Always read files before editing. Use `edit_file` for edits, `write_file` only for new files.
- **Neovim Context**: You operate within the user's current working directory. Respect project structure.
- **Minimal Changes**: Make focused edits. Don't refactor unrelated code.

## Workflow
1. Read before writing to understand context
2. Use LSP tools (`document_symbols`, `workspace_symbols`) for navigation when available
3. If a tool errors, analyze and retry with corrected parameters
4. Summarize what was done after completing tasks]],
}

function M.configure(opts)
    config = vim.tbl_extend("force", config, opts or {})
end

function M.get_config()
    return config
end

-- Send message to API with streaming
-- @param messages: array of {role, content} objects
-- @param on_chunk: function(text) called for each streamed chunk
-- @param on_done: function(content_blocks) called when complete with full content blocks
-- @param on_error: function(err) called on error
function M.send(messages, on_chunk, on_done, on_error)
    local api_key = config.api_key or os.getenv("ANTHROPIC_API_KEY")
    if not api_key then
        on_error("ANTHROPIC_API_KEY not set")
        return nil
    end

    local tool_schemas = tools.get_schemas()

    local request_body = {
        model = config.model,
        max_tokens = config.max_tokens,
        stream = true,
        system = config.system_prompt,
        messages = messages,
    }

    if #tool_schemas > 0 then
        request_body.tools = tool_schemas
    end

    local body = vim.json.encode(request_body)

    local cmd = {
        "curl",
        "--no-buffer",
        "-s",
        "-X", "POST",
        config.base_url,
        "-H", "Content-Type: application/json",
        "-H", "x-api-key: " .. api_key,
        "-H", "anthropic-version: 2023-06-01",
        "-d", "@-",  -- Read body from stdin
    }

    local stderr_buffer = ""
    local done_called = false
    local content_blocks = {}
    local current_block = nil
    local current_block_index = nil

    local function safe_on_done()
        if not done_called then
            done_called = true
            vim.schedule(function()
                on_done(content_blocks)
            end)
        end
    end

    local job_id = vim.fn.jobstart(cmd, {
        stdin = "pipe",
        on_stdout = function(_, data, _)
            for _, line in ipairs(data) do
                -- Process each line directly - SSE data: lines are self-contained
                if line:sub(1, 5) == "data:" then
                    M._process_sse_line(line, on_chunk, safe_on_done, on_error, content_blocks, function(idx, block)
                        current_block_index = idx
                        current_block = block
                    end, function()
                        return current_block_index, current_block
                    end)
                end
                -- event: lines are ignored (we parse type from data JSON)
            end
        end,
        on_stderr = function(_, data, _)
            local err = table.concat(data, "\n")
            if err ~= "" then
                stderr_buffer = stderr_buffer .. err
            end
        end,
        on_exit = function(_, code, _)
            if code ~= 0 and stderr_buffer ~= "" then
                vim.schedule(function()
                    on_error(stderr_buffer)
                end)
            elseif code ~= 0 then
                vim.schedule(function()
                    on_error("curl exited with code " .. code)
                end)
            end
        end,
    })

    -- Write body to stdin and close
    if job_id > 0 then
        vim.fn.chansend(job_id, body)
        vim.fn.chanclose(job_id, "stdin")
    end

    return job_id
end

function M._process_sse_line(line, on_chunk, on_done, on_error, content_blocks, set_current, get_current)
    -- Handle both "data: " (with space) and "data:" (without space)
    local json_str
    if line:sub(1, 6) == "data: " then
        json_str = line:sub(7)
    elseif line:sub(1, 5) == "data:" then
        json_str = line:sub(6)
    else
        return -- event: lines or other, ignore
    end

    if json_str == "[DONE]" then
        on_done()
        return
    end

    local ok, data = pcall(vim.json.decode, json_str)
    if not ok then
        return
    end

    -- Handle different event types
    if data.type == "content_block_start" then
        local block = data.content_block
        local index = data.index
        if block then
            content_blocks[index + 1] = {
                type = block.type,
                text = block.text or "",
                id = block.id,
                name = block.name,
                input = "",  -- Always string, accumulate from deltas
            }
            set_current(index, content_blocks[index + 1])
        end
    elseif data.type == "content_block_delta" then
        local delta = data.delta
        local _, current = get_current()
        if delta and delta.type == "text_delta" and delta.text then
            if current and current.type == "text" then
                current.text = current.text .. delta.text
            end
            vim.schedule(function()
                on_chunk(delta.text)
            end)
        elseif delta and delta.type == "input_json_delta" and delta.partial_json then
            if current and current.type == "tool_use" then
                current.input = current.input .. delta.partial_json
            end
        end
    elseif data.type == "content_block_stop" then
        local _, current = get_current()
        if current and current.type == "tool_use" and current.input ~= "" then
            local parse_ok, parsed = pcall(vim.json.decode, current.input)
            if parse_ok then
                current.input = parsed
            else
                -- JSON parse failed, wrap raw string for debugging
                current.input = { _raw = current.input, _parse_error = tostring(parsed) }
            end
        end
    elseif data.type == "message_stop" then
        on_done()
    elseif data.type == "error" then
        local err_msg = data.error and data.error.message or "Unknown API error"
        vim.schedule(function()
            on_error(err_msg)
        end)
    end
end

function M.cancel(job_id)
    if job_id then
        vim.fn.jobstop(job_id)
    end
end

return M
