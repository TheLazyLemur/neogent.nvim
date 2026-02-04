-- neogent.nvim - Agentic AI assistant for Neovim
local M = {}

local api = require("neogent.api")
local ui = require("neogent.ui")
local tools = require("neogent.tools")

local state = {
    messages = {},
    current_job = nil,
    is_streaming = false,
    cancelled = false,
    steering_queue = {},
}

local config = {}

local default_config = {
    base_url = "https://api.anthropic.com/v1/messages",
    api_key = os.getenv("ANTHROPIC_API_KEY"),
    model = "claude-sonnet-4-20250514",
    max_tokens = 4096,
    follow_agent = true, -- open files agent reads in a buffer
    inject_diagnostics = false, -- whether to inject LSP diagnostics into tool results
}

function M.setup(opts)
    config = vim.tbl_extend("force", default_config, opts or {})
    api.configure({
        base_url = config.base_url,
        api_key = config.api_key,
        model = config.model,
        max_tokens = config.max_tokens,
    })
    tools.configure({ follow_agent = config.follow_agent })

    -- Set callback for tools to reopen agent after diffs
    tools.set_reopen_callback(function()
        M.open()
    end)
end

function M.toggle()
    ui.toggle()
    if ui.is_open() then
        M._setup_keymaps()
    end
end

function M.open()
    ui.open()
    M._setup_keymaps()
end

function M.close()
    ui.close()
end

local function reset_streaming_state()
    if state.current_job then
        api.cancel(state.current_job)
    end
    state.cancelled = true
    state.is_streaming = false
    state.current_job = nil
    state.steering_queue = {}
    ui.hide_spinner()
    ui.hide_queued_indicator()
end

function M.cancel()
    if state.is_streaming and state.current_job then
        reset_streaming_state()
        ui.append_text(" ✗")
        ui.append_lines({ "" })
    end
end

function M._setup_keymaps()
    local buf = ui.get_buf()
    local input_buf = ui.get_input_buf()
    local status_buf = ui.get_status_buf()

    -- Chat buffer keymaps
    if buf and vim.api.nvim_buf_is_valid(buf) then
        local opts = { buffer = buf, nowait = true }
        vim.keymap.set("n", "c", M.clear, opts)
        vim.keymap.set("n", "q", M.close, opts)
        vim.keymap.set("n", "i", function() ui.focus_input() vim.cmd("startinsert") end, opts)
        vim.keymap.set("n", "<Esc>", M.cancel, opts)
        vim.keymap.set("n", "<C-c>", M.cancel, opts)
        vim.keymap.set("n", "<Tab>", function() ui.focus_input() end, opts)
    end

    -- Input buffer keymaps (prompt)
    if input_buf and vim.api.nvim_buf_is_valid(input_buf) then
        local opts = { buffer = input_buf, nowait = true }
        vim.keymap.set("n", "<CR>", M.send_from_input, opts)
        vim.keymap.set("i", "<CR>", M.send_from_input, opts)
        vim.keymap.set("n", "q", M.close, opts)
        vim.keymap.set("n", "c", M.clear, opts)
        vim.keymap.set("n", "<Tab>", function() ui.focus_status() end, opts)
        vim.keymap.set("i", "<Tab>", function() vim.cmd("stopinsert") ui.focus_status() end, opts)
        vim.keymap.set("i", "<C-c>", M.cancel, opts)
    end

    -- Status buffer keymaps (tools)
    if status_buf and vim.api.nvim_buf_is_valid(status_buf) then
        local opts = { buffer = status_buf, nowait = true }
        vim.keymap.set("n", "q", M.close, opts)
        vim.keymap.set("n", "c", M.clear, opts)
        vim.keymap.set("n", "<Tab>", function() ui.focus_chat() end, opts)
        vim.keymap.set("n", "i", function() ui.focus_input() vim.cmd("startinsert") end, opts)
        vim.keymap.set("n", "<Esc>", M.cancel, opts)
        vim.keymap.set("n", "<C-c>", M.cancel, opts)
    end

    local function cleanup()
        if state.is_streaming then
            reset_streaming_state()
        end
    end

    if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_create_autocmd("BufDelete", { buffer = buf, once = true, callback = cleanup })
    end
end

function M.send_from_input()
    local input = vim.trim(ui.get_input_text())
    if input == "" then
        return
    end

    ui.clear_input()
    M.send_message(input)
end

function M.send_message(content)
    if not content or content == "" then return end

    if state.is_streaming then
        -- Queue mode: agent is running
        table.insert(state.steering_queue, content)
        ui.show_queued_indicator(#state.steering_queue)
        return
    end

    -- Send mode: immediate
    table.insert(state.messages, { role = "user", content = content })
    -- Blockquote user messages
    local quoted = vim.tbl_map(function(line) return "> " .. line end, vim.split(content, "\n"))
    ui.append_lines({ "" })
    ui.append_lines(quoted)
    ui.append_lines({ "", "---", "" })
    M._send_to_api()
end

local function drain_steering_queue()
    if #state.steering_queue == 0 then return end

    local combined = table.concat(state.steering_queue, "\n\n")
    state.steering_queue = {}

    table.insert(state.messages, { role = "user", content = combined })
    local quoted = vim.tbl_map(function(line) return "> " .. line end, vim.split(combined, "\n"))
    ui.append_lines({ "" })
    ui.append_lines(quoted)
    ui.append_lines({ "", "---", "" })
    ui.hide_queued_indicator()
end

function M._send_to_api()
    ui.show_spinner("thinking")

    state.is_streaming = true
    state.cancelled = false

    local response_text = ""
    local first_chunk = true

    state.current_job = api.send(
        state.messages,
        function(chunk)
            if state.cancelled then return end
            if first_chunk then
                first_chunk = false
                ui.hide_spinner()
            end
            response_text = response_text .. chunk
            ui.append_text(chunk)
        end,
        function(content_blocks)
            if state.cancelled then return end
            state.is_streaming = false
            state.current_job = nil
            ui.hide_spinner()

            -- Check for tool use in content blocks
            local tool_uses = {}
            local text_content = ""
            for _, block in ipairs(content_blocks or {}) do
                if block.type == "tool_use" then
                    table.insert(tool_uses, block)
                elseif block.type == "text" then
                    text_content = text_content .. (block.text or "")
                end
            end

            -- Add assistant response to history (with full content blocks if tools used)
            if #tool_uses > 0 then
                local content_for_history = {}
                for _, block in ipairs(content_blocks) do
                    if block.type == "text" then
                        table.insert(content_for_history, { type = "text", text = block.text })
                    elseif block.type == "tool_use" then
                        table.insert(content_for_history, {
                            type = "tool_use",
                            id = block.id,
                            name = block.name,
                            input = block.input,
                        })
                    end
                end
                table.insert(state.messages, { role = "assistant", content = content_for_history })

                -- Execute tools and continue conversation
                M._handle_tool_use(tool_uses)
            else
                table.insert(state.messages, { role = "assistant", content = response_text })
                ui.append_lines({ "", "" })
            end
        end,
        function(err)
            if state.cancelled then return end
            state.is_streaming = false
            state.current_job = nil
            ui.hide_spinner()
            vim.notify("Chat error: " .. err, vim.log.levels.ERROR)
            ui.append_lines({ "", "*Error: " .. err .. "*", "" })
        end
    )
end

function M._handle_tool_use(tool_uses)
    local tool_results = {}
    local index = 1

    -- Add separator if there are existing tools, then add new tools as pending
    ui.add_tool_separator()
    for _, tool in ipairs(tool_uses) do
        ui.add_tool_status(tool.id, tool.name, "pending")
    end

    local function process_next()
        if index > #tool_uses then
            -- All tools done, continue conversation
            table.insert(state.messages, { role = "user", content = tool_results })
            drain_steering_queue()
            M._send_to_api()
            return
        end

        local tool_use = tool_uses[index]
        index = index + 1

        -- Update status panel to running
        ui.update_tool_status(tool_use.id, "running")

        local input = tool_use.input
        if type(input) == "table" and input._raw then
            -- JSON parse error
            ui.update_tool_status(tool_use.id, "error", "parse error")
            local err_str = "Parse error: " .. (input._parse_error or "unknown") .. ". Please try again with valid JSON."
            table.insert(tool_results, {
                type = "tool_result",
                tool_use_id = tool_use.id,
                content = err_str,
                is_error = true,
            })
            process_next()
            return
        end

        -- Execute tool asynchronously
        tools.execute_async(tool_use.name, input, function(result)
            if state.cancelled then return end

            -- Update status panel only
            if result.success then
                ui.update_tool_status(tool_use.id, "success")
                -- Build content with diagnostics if present
                local content = result.message
                if result.diagnostics and #result.diagnostics > 0 and config.inject_diagnostics then
                    content = content .. "\n\nDiagnostic errors in file:"
                    for _, diag in ipairs(result.diagnostics) do
                        content = content .. string.format("\n  Line %d, Col %d: %s", diag.line, diag.col, diag.message)
                    end
                end
                table.insert(tool_results, {
                    type = "tool_result",
                    tool_use_id = tool_use.id,
                    content = content,
                })
            else
                ui.update_tool_status(tool_use.id, "error", result.error)
                table.insert(tool_results, {
                    type = "tool_result",
                    tool_use_id = tool_use.id,
                    content = "Error: " .. result.error .. ". You may retry with different parameters or ask the user for help.",
                    is_error = true,
                })
            end

            process_next()
        end)
    end

    process_next()
end

function M.clear()
    if state.is_streaming then
        reset_streaming_state()
    end
    state.messages = {}
    ui.clear()
end

return M
