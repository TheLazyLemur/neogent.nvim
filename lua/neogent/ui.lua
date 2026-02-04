-- neogent.nvim - Floating window UI management
local M = {}

local state = {
    buf = nil,
    win = nil,
    input_buf = nil,
    input_win = nil,
    status_buf = nil,
    status_win = nil,
    editor_win = nil,
    -- Layout config
    width_ratio = 0.98, -- total width of floating UI
    height_ratio = 0.95, -- total height
    status_width = 32,  -- fixed width for status panel
    input_height = 5,   -- height of input panel
    padding = 2,        -- gap between panels
    -- Spinner state
    spinner_timer = nil,
    spinner_frame = 1,
    spinner_line = nil,
    queued_count = 0,
    -- Tool status tracking
    tool_statuses = {},
}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Define highlight groups for tool status colours
vim.api.nvim_set_hl(0, "ChatToolPending", { fg = "#808080" })  -- grey
vim.api.nvim_set_hl(0, "ChatToolRunning", { fg = "#61afef" })  -- blue
vim.api.nvim_set_hl(0, "ChatToolSuccess", { fg = "#98c379" })  -- green
vim.api.nvim_set_hl(0, "ChatToolError", { fg = "#e06c75" })    -- red
vim.api.nvim_set_hl(0, "ChatToolSeparator", { fg = "#5c6370" }) -- dark grey

local function calculate_layout()
    local total_width = math.floor(vim.o.columns * state.width_ratio)
    -- Account for cmdline (1-2 lines typically)
    local usable_lines = vim.o.lines - vim.o.cmdheight - 1
    local total_height = math.floor(usable_lines * state.height_ratio)

    -- Centre horizontally, slight top margin vertically
    local start_col = math.floor((vim.o.columns - total_width) / 2)
    local start_row = 1

    -- Left column (chat + input) and right column (status)
    local left_width = total_width - state.status_width - state.padding
    local chat_height = total_height - state.input_height - state.padding

    return {
        chat = {
            width = left_width,
            height = chat_height,
            row = start_row,
            col = start_col,
        },
        input = {
            width = left_width,
            height = state.input_height,
            row = start_row + chat_height + state.padding,
            col = start_col,
        },
        status = {
            width = state.status_width,
            height = chat_height + state.padding + state.input_height,
            row = start_row,
            col = start_col + left_width + state.padding,
        },
    }
end

function M.set_width_ratio(ratio)
    state.width_ratio = math.max(0.5, math.min(0.95, ratio))
    if M.is_open() then
        M._reposition()
    end
end

local function create_scratch_buffer(ft)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = ft or "markdown"
    return buf
end

local function create_float(buf, layout, title, border_hl)
    local win = vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = layout.width,
        height = layout.height,
        row = layout.row,
        col = layout.col,
        style = "minimal",
        border = "rounded",
        title = title and (" " .. title .. " ") or nil,
        title_pos = title and "center" or nil,
    })

    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].cursorline = false

    if border_hl then
        vim.wo[win].winhighlight = "FloatBorder:" .. border_hl
    end

    return win
end

function M.is_open()
    return state.win and vim.api.nvim_win_is_valid(state.win)
end

function M.open()
    if M.is_open() then
        return state.buf, state.win, state.input_buf, state.input_win
    end

    state.editor_win = vim.api.nvim_get_current_win()

    -- Create buffers if needed
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        state.buf = create_scratch_buffer("markdown")
        vim.bo[state.buf].modifiable = false
    end
    if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
        state.input_buf = create_scratch_buffer("markdown")
    end
    if not state.status_buf or not vim.api.nvim_buf_is_valid(state.status_buf) then
        state.status_buf = create_scratch_buffer("markdown")
        vim.bo[state.status_buf].modifiable = false
        M._render_status()
    end

    local layout = calculate_layout()

    -- Create floating windows
    state.win = create_float(state.buf, layout.chat, "Chat", "Comment")
    state.input_win = create_float(state.input_buf, layout.input, "Prompt", "Function")
    state.status_win = create_float(state.status_buf, layout.status, "Tools", "Special")

    -- Make input buffer modifiable
    vim.bo[state.input_buf].modifiable = true

    -- Close all windows if any buffer is hidden/closed
    state.closing = false
    local function on_buf_leave()
        if state.closing then return end
        state.closing = true
        vim.schedule(function()
            M.close()
            state.closing = false
        end)
    end

    for _, buf in ipairs({ state.buf, state.input_buf, state.status_buf }) do
        vim.api.nvim_create_autocmd("BufWinLeave", {
            buffer = buf,
            callback = on_buf_leave,
            once = true,
        })
    end

    -- Focus input window
    vim.api.nvim_set_current_win(state.input_win)
    vim.cmd("startinsert")

    return state.buf, state.win, state.input_buf, state.input_win
end

function M._reposition()
    if not M.is_open() then return end

    local layout = calculate_layout()

    local function update_win(win, l)
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_config(win, {
                relative = "editor",
                width = l.width,
                height = l.height,
                row = l.row,
                col = l.col,
            })
        end
    end

    update_win(state.win, layout.chat)
    update_win(state.input_win, layout.input)
    update_win(state.status_win, layout.status)
end

function M.close()
    M.hide_spinner()

    local windows = { state.input_win, state.status_win, state.win }
    for _, win in ipairs(windows) do
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    state.win = nil
    state.input_win = nil
    state.status_win = nil

    -- Return focus to editor
    if state.editor_win and vim.api.nvim_win_is_valid(state.editor_win) then
        vim.api.nvim_set_current_win(state.editor_win)
    end
end

function M.toggle()
    if M.is_open() then
        M.close()
    else
        M.open()
    end
end

function M.get_buf()
    return state.buf
end

function M.get_win()
    return state.win
end

function M.get_input_buf()
    return state.input_buf
end

function M.get_input_win()
    return state.input_win
end

function M.get_status_buf()
    return state.status_buf
end

function M.get_status_win()
    return state.status_win
end

function M.get_editor_win()
    if state.editor_win and vim.api.nvim_win_is_valid(state.editor_win) then
        return state.editor_win
    end
    return nil
end

function M.get_input_text()
    if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
        return ""
    end
    local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    return table.concat(lines, "\n")
end

function M.clear_input()
    if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
        return
    end
    vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, {})
end

function M.focus_input()
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
        vim.api.nvim_set_current_win(state.input_win)
    end
end

function M.focus_chat()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_set_current_win(state.win)
    end
end

function M.focus_status()
    if state.status_win and vim.api.nvim_win_is_valid(state.status_win) then
        vim.api.nvim_set_current_win(state.status_win)
    end
end

function M.append_lines(lines)
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        return
    end
    vim.bo[state.buf].modifiable = true
    local count = vim.api.nvim_buf_line_count(state.buf)
    local first_line = vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1]
    if count == 1 and first_line == "" then
        vim.api.nvim_buf_set_lines(state.buf, 0, 1, false, lines)
    else
        vim.api.nvim_buf_set_lines(state.buf, count, count, false, lines)
    end
    vim.bo[state.buf].modifiable = false
    M.scroll_to_bottom()
end

function M.append_text(text)
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        return
    end
    vim.bo[state.buf].modifiable = true
    local count = vim.api.nvim_buf_line_count(state.buf)
    local last_line = vim.api.nvim_buf_get_lines(state.buf, count - 1, count, false)[1] or ""
    local new_text = last_line .. text
    local new_lines = vim.split(new_text, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(state.buf, count - 1, count, false, new_lines)
    vim.bo[state.buf].modifiable = false
    M.scroll_to_bottom()
end

function M.clear()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        return
    end
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {})
    vim.bo[state.buf].modifiable = false
    M.clear_tool_status()
end

function M.scroll_to_bottom()
    if M.is_open() and state.win and vim.api.nvim_win_is_valid(state.win) then
        local count = vim.api.nvim_buf_line_count(state.buf)
        pcall(vim.api.nvim_win_set_cursor, state.win, { count, 0 })
    end
end

-- Tool status panel functions
function M._render_status()
    vim.schedule(function()
        if not state.status_buf or not vim.api.nvim_buf_is_valid(state.status_buf) then
            return
        end

        local lines = {}
        local line_highlights = {} -- Track {line_idx, highlight_group} for each tool line

        if #state.tool_statuses == 0 then
            table.insert(lines, "")
            table.insert(lines, "  No tools running")
        else
            for i, tool in ipairs(state.tool_statuses) do
                if tool.separator then
                    -- Render separator line
                    table.insert(lines, " ────────────────────────")
                    table.insert(line_highlights, { #lines - 1, "ChatToolSeparator" })
                else
                    local icon = tool.icon or "○"
                    local line = string.format(" %s %s", icon, tool.name)
                    table.insert(lines, line)

                    -- Map status to highlight group
                    local hl_map = {
                        pending = "ChatToolPending",
                        running = "ChatToolRunning",
                        success = "ChatToolSuccess",
                        error = "ChatToolError",
                    }
                    local hl_group = hl_map[tool.status] or "ChatToolPending"
                    table.insert(line_highlights, { #lines - 1, hl_group })

                    if tool.detail then
                        table.insert(lines, "   " .. tool.detail)
                        table.insert(line_highlights, { #lines - 1, hl_group })
                    end
                end
                if i < #state.tool_statuses then
                    table.insert(lines, "")
                end
            end
        end

        vim.bo[state.status_buf].modifiable = true
        vim.api.nvim_buf_set_lines(state.status_buf, 0, -1, false, lines)

        -- Clear existing highlights and apply new ones
        vim.api.nvim_buf_clear_namespace(state.status_buf, -1, 0, -1)
        for _, hl in ipairs(line_highlights) do
            local line_idx, hl_group = hl[1], hl[2]
            vim.api.nvim_buf_add_highlight(state.status_buf, -1, hl_group, line_idx, 0, -1)
        end

        vim.bo[state.status_buf].modifiable = false
    end)
end

function M.add_tool_status(id, name, status, detail)
    local icons = {
        pending = "○",
        running = "◐",
        success = "✓",
        error = "✗",
    }
    table.insert(state.tool_statuses, {
        id = id,
        name = name,
        status = status,
        icon = icons[status] or "○",
        detail = detail,
    })
    M._render_status()
end

function M.update_tool_status(id, status, detail)
    local icons = {
        pending = "○",
        running = "◐",
        success = "✓",
        error = "✗",
    }
    for _, tool in ipairs(state.tool_statuses) do
        if tool.id == id then
            tool.status = status
            tool.icon = icons[status] or tool.icon
            if detail then
                tool.detail = detail
            end
            break
        end
    end
    M._render_status()
end

function M.clear_tool_status()
    state.tool_statuses = {}
    M._render_status()
end

function M.add_tool_separator()
    if #state.tool_statuses > 0 then
        table.insert(state.tool_statuses, { separator = true })
        M._render_status()
    end
end

-- Spinner functions
function M.show_spinner(label)
    M.hide_spinner()
    state.spinner_frame = 1

    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

    local count = vim.api.nvim_buf_line_count(state.buf)
    state.spinner_line = vim.api.nvim_buf_get_lines(state.buf, count - 1, count, false)[1] or ""

    local function update()
        if not state.spinner_timer then return end
        if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
            M.hide_spinner()
            return
        end

        local frame = spinner_frames[state.spinner_frame]
        state.spinner_frame = (state.spinner_frame % #spinner_frames) + 1

        vim.bo[state.buf].modifiable = true
        local cnt = vim.api.nvim_buf_line_count(state.buf)
        local new_line = state.spinner_line .. frame .. " " .. label
        vim.api.nvim_buf_set_lines(state.buf, cnt - 1, cnt, false, { new_line })
        vim.bo[state.buf].modifiable = false
    end

    state.spinner_timer = vim.uv.new_timer()
    state.spinner_timer:start(0, 80, vim.schedule_wrap(update))
end

function M.hide_spinner()
    if state.spinner_timer then
        state.spinner_timer:stop()
        state.spinner_timer:close()
        state.spinner_timer = nil
    end

    if state.spinner_line ~= nil and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        vim.bo[state.buf].modifiable = true
        local count = vim.api.nvim_buf_line_count(state.buf)
        vim.api.nvim_buf_set_lines(state.buf, count - 1, count, false, { state.spinner_line })
        vim.bo[state.buf].modifiable = false
        state.spinner_line = nil
    end
end

function M.show_queued_indicator(count)
    state.queued_count = count
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
        vim.api.nvim_win_set_config(state.input_win, {
            title = " Prompt (queued: " .. count .. ") ",
            title_pos = "center",
        })
    end
end

function M.hide_queued_indicator()
    state.queued_count = 0
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
        vim.api.nvim_win_set_config(state.input_win, {
            title = " Prompt ",
            title_pos = "center",
        })
    end
end

-- Auto-resize on terminal resize
vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
        M._reposition()
    end,
})

return M
