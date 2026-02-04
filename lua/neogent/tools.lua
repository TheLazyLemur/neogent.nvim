-- neogent.nvim - Tool registry and implementations
local M = {}
local ui = require("neogent.ui")

-- LSP symbol kind mapping (from LSP spec)
local lsp_symbol_kinds = {
    [1] = "File", [2] = "Module", [3] = "Namespace", [4] = "Package",
    [5] = "Class", [6] = "Method", [7] = "Property", [8] = "Field",
    [9] = "Constructor", [10] = "Enum", [11] = "Interface", [12] = "Function",
    [13] = "Variable", [14] = "Constant", [15] = "String", [16] = "Number",
    [17] = "Boolean", [18] = "Array", [19] = "Object", [20] = "Key",
    [21] = "Null", [22] = "EnumMember", [23] = "Struct", [24] = "Event",
    [25] = "Operator", [26] = "TypeParameter",
}

M.registry = {}
M.config = {
    follow_agent = true, -- open files agent reads in a buffer
}
M._reopen_callback = nil  -- called after diff closes to reopen agent

function M.set_reopen_callback(fn)
    M._reopen_callback = fn
end

-- Register a tool with name, schema (Anthropic format), and executor function
function M.register(name, schema, executor)
    M.registry[name] = {
        schema = schema,
        execute = executor,
    }
end

function M.configure(opts)
    M.config = vim.tbl_extend("force", M.config, opts or {})
end

--- Format diagnostics, filtering to errors only
--- @param diagnostics table[] List of vim.Diagnostic objects
--- @return table[] List of {line, col, message} for errors only (1-indexed)
function M.format_error_diagnostics(diagnostics)
    local errors = {}
    for _, d in ipairs(diagnostics) do
        if d.severity == vim.diagnostic.severity.ERROR then
            table.insert(errors, {
                line = (d.lnum or 0) + 1,
                col = (d.col or 0) + 1,
                message = d.message or "",
            })
        end
    end
    return errors
end

--- Get error diagnostics for a buffer
--- @param bufnr number Buffer number
--- @return table[] List of {line, col, message} for errors only
function M.get_buffer_error_diagnostics(bufnr)
    local diagnostics = vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })
    return M.format_error_diagnostics(diagnostics)
end

--- Format LSP document symbols into a flat list
--- @param symbols table[]|nil LSP DocumentSymbol[] response
--- @return table[] List of {name, kind, line} (1-indexed)
function M.format_lsp_symbols(symbols)
    if not symbols then return {} end

    local result = {}

    local function process_symbol(sym)
        local line = nil
        if sym.range and sym.range.start then
            line = sym.range.start.line + 1  -- Convert 0-indexed to 1-indexed
        elseif sym.selectionRange and sym.selectionRange.start then
            line = sym.selectionRange.start.line + 1
        end

        table.insert(result, {
            name = sym.name,
            kind = lsp_symbol_kinds[sym.kind] or "Unknown",
            line = line,
        })

        -- Recursively process children (LSP returns hierarchical structure)
        if sym.children then
            for _, child in ipairs(sym.children) do
                process_symbol(child)
            end
        end
    end

    for _, sym in ipairs(symbols) do
        process_symbol(sym)
    end

    return result
end

--- Format LSP workspace symbols into a flat list
--- @param symbols table[]|nil LSP SymbolInformation[] response
--- @return table[] List of {name, kind, file, line} (1-indexed)
function M.format_workspace_symbols(symbols)
    if not symbols then return {} end

    local result = {}

    for _, sym in ipairs(symbols) do
        local file = nil
        local line = nil

        if sym.location then
            -- Extract file path from file:// URI
            if sym.location.uri then
                file = sym.location.uri:gsub("^file://", "")
            end
            if sym.location.range and sym.location.range.start then
                line = sym.location.range.start.line + 1  -- Convert 0-indexed to 1-indexed
            end
        end

        table.insert(result, {
            name = sym.name,
            kind = lsp_symbol_kinds[sym.kind] or "Unknown",
            file = file,
            line = line,
        })
    end

    return result
end

--- Wait for LSP client to attach to buffer
--- @param bufnr number Buffer number
--- @param timeout_ms number Timeout in milliseconds
--- @param callback function Called with (clients) or nil if timeout
function M.wait_for_lsp_attach(bufnr, timeout_ms, callback)
    local start = vim.loop.now()

    local function check()
        local elapsed = vim.loop.now() - start
        local clients = vim.lsp.get_clients({ bufnr = bufnr })

        if #clients > 0 then
            callback(clients)
            return
        end

        if elapsed >= timeout_ms then
            callback(nil)
            return
        end

        -- Keep polling
        vim.defer_fn(check, 50)
    end

    -- Start checking immediately
    check()
end

--- Wait for diagnostics and return errors
--- @param bufnr number Buffer number
--- @param timeout_ms number Timeout in milliseconds
--- @param callback function Called with error diagnostics table
function M.wait_for_diagnostics(bufnr, timeout_ms, callback)
    local start = vim.loop.now()

    local function check()
        local elapsed = vim.loop.now() - start
        local errors = M.get_buffer_error_diagnostics(bufnr)

        -- Return if we have errors or timeout reached
        if #errors > 0 or elapsed >= timeout_ms then
            callback(errors)
            return
        end

        -- Keep polling
        vim.defer_fn(check, 100)
    end

    -- Start checking after initial delay to let LSP attach
    vim.defer_fn(check, 200)
end

function M.get(name)
    return M.registry[name]
end

function M.list()
    return vim.tbl_keys(M.registry)
end

-- Get all tool schemas for API request
function M.get_schemas()
    local schemas = {}
    for _, tool in pairs(M.registry) do
        table.insert(schemas, tool.schema)
    end
    return schemas
end

-- Execute a tool by name with input (sync - for non-blocking tools)
function M.execute(name, input)
    local tool = M.registry[name]
    if not tool then
        return { success = false, error = "Unknown tool: " .. name }
    end
    local ok, result = pcall(tool.execute, input)
    if not ok then
        return { success = false, error = tostring(result) }
    end
    return result
end

-- Execute a tool asynchronously with callback
-- callback(result) where result = { success, message/error }
function M.execute_async(name, input, callback)
    local tool = M.registry[name]
    if not tool then
        callback({ success = false, error = "Unknown tool: " .. name })
        return
    end

    -- Check if tool has async executor
    if tool.execute_async then
        local ok, err = pcall(tool.execute_async, input, callback)
        if not ok then
            callback({ success = false, error = tostring(err) })
        end
    else
        -- Fallback to sync execution via vim.schedule
        vim.schedule(function()
            local ok, result = pcall(tool.execute, input)
            if not ok then
                callback({ success = false, error = tostring(result) })
            else
                callback(result)
            end
        end)
    end
end

-- Helper to register tool with both sync and async executors
function M.register_async(name, schema, sync_executor, async_executor)
    M.registry[name] = {
        schema = schema,
        execute = sync_executor,
        execute_async = async_executor,
    }
end

-- search_files: ripgrep wrapper (content search)
local function build_search_cmd(input)
    local pattern = input.pattern
    if not pattern or pattern == "" then
        return nil, "Missing search pattern"
    end

    local cmd = { "rg", "--line-number", "--no-heading", "--color=never" }
    local max_results = input.max_results or 50
    table.insert(cmd, "--max-count=" .. max_results)

    if input.glob then
        table.insert(cmd, "--glob")
        table.insert(cmd, input.glob)
    end

    table.insert(cmd, "--")
    table.insert(cmd, pattern)

    if input.path then
        table.insert(cmd, input.path)
    end

    return cmd, nil
end

local function parse_rg_result(result)
    if result.code ~= 0 and result.code ~= 1 then
        return { success = false, error = result.stderr or "rg failed" }
    end

    local output = result.stdout or ""
    if output == "" then
        return { success = true, message = "No matches found" }
    end

    local lines = vim.split(output, "\n", { trimempty = true })
    return { success = true, message = table.concat(lines, "\n") }
end

M.register_async("search_files", {
    name = "search_files",
    description = "Search file contents for a regex pattern using ripgrep. Use this to find definitions, usages, or patterns across the codebase. Always try this before asking 'where is X defined?' Use the 'glob' parameter to filter by file type (e.g., '*.lua', '*.ts'). Returns matching lines with file paths and line numbers.",
    input_schema = {
        type = "object",
        properties = {
            pattern = {
                type = "string",
                description = "Regex pattern to search for IN FILE CONTENTS. NOT a file glob. Examples: 'function\\s+\\w+', 'TODO', 'import.*react'",
            },
            path = {
                type = "string",
                description = "Directory or file to search in. Defaults to cwd.",
            },
            glob = {
                type = "string",
                description = "Filter FILES by glob pattern. Examples: '*.lua', '*.ts', '**/*.md'. This filters which files to search, NOT what to search for.",
            },
            max_results = {
                type = "number",
                description = "Max results to return. Default 50.",
            },
        },
        required = { "pattern" },
    },
},
-- sync executor
function(input)
    local cmd, err = build_search_cmd(input)
    if not cmd then return { success = false, error = err } end
    return parse_rg_result(vim.system(cmd, { text = true }):wait())
end,
-- async executor
function(input, callback)
    local cmd, err = build_search_cmd(input)
    if not cmd then
        callback({ success = false, error = err })
        return
    end
    vim.system(cmd, { text = true }, function(result)
        vim.schedule(function()
            callback(parse_rg_result(result))
        end)
    end)
end)

-- list_files: find files by glob pattern
local function build_list_cmd(input)
    local glob = input.glob
    if not glob or glob == "" then
        return nil, "Missing glob pattern"
    end

    local cmd = { "rg", "--files", "--glob", glob }
    if input.path then
        table.insert(cmd, input.path)
    end
    return cmd, nil
end

local function parse_list_result(result, max_results)
    if result.code ~= 0 and result.code ~= 1 then
        return { success = false, error = result.stderr or "rg --files failed" }
    end

    local output = result.stdout or ""
    if output == "" then
        return { success = true, message = "No files found" }
    end

    local lines = vim.split(output, "\n", { trimempty = true })
    max_results = max_results or 100
    if #lines > max_results then
        local total = #lines
        lines = vim.list_slice(lines, 1, max_results)
        table.insert(lines, string.format("... truncated (%d more)", total - max_results))
    end

    return { success = true, message = table.concat(lines, "\n") }
end

M.register_async("list_files", {
    name = "list_files",
    description = "List files matching a glob pattern. Use this to explore project structure, find files by name or extension, or verify a file exists before reading. Does NOT search file contents - use search_files for that. Examples: '*.lua' (all Lua files), 'src/**/*.ts' (TypeScript in src), '**/test_*.py' (Python test files).",
    input_schema = {
        type = "object",
        properties = {
            glob = {
                type = "string",
                description = "Glob pattern. Examples: '*.lua', '**/*.ts', 'src/**/*.jsx'",
            },
            path = {
                type = "string",
                description = "Directory to search in. Defaults to cwd.",
            },
            max_results = {
                type = "number",
                description = "Max files to return. Default 100.",
            },
        },
        required = { "glob" },
    },
},
-- sync executor
function(input)
    local cmd, err = build_list_cmd(input)
    if not cmd then return { success = false, error = err } end
    return parse_list_result(vim.system(cmd, { text = true }):wait(), input.max_results)
end,
-- async executor
function(input, callback)
    local cmd, err = build_list_cmd(input)
    if not cmd then
        callback({ success = false, error = err })
        return
    end
    vim.system(cmd, { text = true }, function(result)
        vim.schedule(function()
            callback(parse_list_result(result, input.max_results))
        end)
    end)
end)

--- Apply line replacement to a table of lines
--- @param lines string[] Original lines
--- @param from_line number Start line (1-indexed)
--- @param to_line number End line (1-indexed, inclusive). If < from_line, inserts before from_line
--- @param new_lines string[] Replacement lines (empty to delete)
--- @return string[] Modified lines
function M.apply_line_replacement(lines, from_line, to_line, new_lines)
    local result = {}

    -- Insert mode: from_line > to_line means insert before from_line
    if to_line < from_line then
        for i = 1, from_line - 1 do
            table.insert(result, lines[i])
        end
        for _, line in ipairs(new_lines) do
            table.insert(result, line)
        end
        for i = from_line, #lines do
            table.insert(result, lines[i])
        end
        return result
    end

    -- Replace mode: replace lines from from_line to to_line
    for i = 1, from_line - 1 do
        table.insert(result, lines[i])
    end
    for _, line in ipairs(new_lines) do
        table.insert(result, line)
    end
    for i = to_line + 1, #lines do
        table.insert(result, lines[i])
    end

    return result
end

-- Shared helpers
local function resolve_path(path)
    if not path:match("^/") then
        return vim.fn.getcwd() .. "/" .. path
    end
    return path
end

local function find_editor_window()
    -- Prefer tracked editor window from when sidebar opened
    local tracked = ui.get_editor_win()
    if tracked then
        return tracked
    end
    -- Fallback: heuristic (original window may have been closed)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype ~= "nofile" then
            return win
        end
    end
    return vim.api.nvim_list_wins()[1]
end

local function get_filetype_from_path(path)
    local ext = vim.fn.fnamemodify(path, ":e")
    local ft_map = { lua = "lua", py = "python", js = "javascript", ts = "typescript", md = "markdown", json = "json", yaml = "yaml", yml = "yaml" }
    return ft_map[ext] or ext
end

local diff_state = nil

local function close_diff_view(state, open_file)
    if not state then return end

    -- Clear autocmd
    if state.autocmd_id then
        pcall(vim.api.nvim_del_autocmd, state.autocmd_id)
    end

    -- diffoff on both windows
    for _, win in ipairs({ state.orig_win, state.prop_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_call(win, function() vim.cmd("diffoff") end)
        end
    end

    -- Close proposed window
    if state.prop_win and vim.api.nvim_win_is_valid(state.prop_win) then
        pcall(vim.api.nvim_win_close, state.prop_win, true)
    end

    -- Open actual file in orig_win BEFORE deleting scratch buffers
    if open_file and state.orig_win and vim.api.nvim_win_is_valid(state.orig_win) then
        local path = resolve_path(state.filepath)
        vim.api.nvim_set_current_win(state.orig_win)
        vim.cmd("edit " .. vim.fn.fnameescape(path))
    end

    -- Now safe to delete scratch buffers
    for _, buf in ipairs({ state.orig_buf, state.prop_buf }) do
        if buf and vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end

    diff_state = nil

    -- Reopen the agent UI
    if M._reopen_callback then
        vim.schedule(M._reopen_callback)
    end
end

local function open_diff_view(original_lines, proposed_lines, filepath, on_accept, on_reject)
    -- Exit insert mode and hide the agent UI
    vim.cmd("stopinsert")
    ui.close()

    local ft = get_filetype_from_path(filepath)

    -- Create original buffer (left)
    local orig_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, original_lines)
    vim.bo[orig_buf].filetype = ft
    vim.bo[orig_buf].modifiable = false
    vim.bo[orig_buf].buftype = "nofile"
    vim.api.nvim_buf_set_name(orig_buf, "original://" .. filepath)

    -- Create proposed buffer (right)
    local prop_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(prop_buf, 0, -1, false, proposed_lines)
    vim.bo[prop_buf].filetype = ft
    vim.bo[prop_buf].modifiable = false
    vim.bo[prop_buf].buftype = "nofile"
    vim.api.nvim_buf_set_name(prop_buf, "proposed://" .. filepath)

    local target_win = find_editor_window()

    -- Open original in target window (left side)
    vim.api.nvim_set_current_win(target_win)
    vim.api.nvim_win_set_buf(target_win, orig_buf)
    vim.cmd("diffthis")
    local orig_win = target_win

    -- Split right for proposed (right side)
    vim.cmd("rightbelow vsplit")
    local prop_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(prop_win, prop_buf)
    vim.cmd("diffthis")

    -- Focus the proposed buffer (right side) for accept/reject
    vim.api.nvim_set_current_win(prop_win)

    -- Store state
    local state = {
        orig_buf = orig_buf,
        prop_buf = prop_buf,
        orig_win = orig_win,
        prop_win = prop_win,
        filepath = filepath,
        proposed_lines = proposed_lines,
        on_accept = on_accept,
        on_reject = on_reject,
    }

    -- Keymaps on proposed buffer
    local function accept()
        local path = resolve_path(state.filepath)
        local ok, err = pcall(vim.fn.writefile, state.proposed_lines, path)
        close_diff_view(state, true)
        if ok then
            -- Get the buffer for the file we just wrote
            local bufnr = vim.fn.bufnr(path)
            if bufnr == -1 then
                -- Buffer not found, try current buffer as fallback
                bufnr = vim.api.nvim_get_current_buf()
            end
            M.wait_for_diagnostics(bufnr, 2000, function(errors)
                state.on_accept({ errors = errors })
            end)
        else
            state.on_reject("Write failed: " .. tostring(err))
        end
    end

    local function reject()
        close_diff_view(state, vim.fn.filereadable(resolve_path(state.filepath)) == 1)
        state.on_reject("Rejected by user")
    end

    vim.keymap.set("n", "<CR>", accept, { buffer = prop_buf, nowait = true })
    vim.keymap.set("n", "q", reject, { buffer = prop_buf, nowait = true })
    vim.keymap.set("n", "<CR>", accept, { buffer = orig_buf, nowait = true })
    vim.keymap.set("n", "q", reject, { buffer = orig_buf, nowait = true })

    -- Autocmd for manual close
    state.autocmd_id = vim.api.nvim_create_autocmd("BufWinLeave", {
        buffer = prop_buf,
        once = true,
        callback = function()
            vim.schedule(function()
                if diff_state == state then
                    close_diff_view(state, vim.fn.filereadable(resolve_path(state.filepath)) == 1)
                    state.on_reject("Rejected by user")
                end
            end)
        end,
    })

    diff_state = state
end

M.register_async("write_file", {
    name = "write_file",
    description = "Create a new file with the specified content. IMPORTANT: This tool FAILS if the file already exists - use replace_lines to edit existing files. Shows a diff view for user approval before writing. Use this only for creating new files, not for modifying existing ones.",
    input_schema = {
        type = "object",
        properties = {
            path = { type = "string", description = "File path (absolute or relative to cwd)" },
            content = { type = "string", description = "File content" },
        },
        required = { "path", "content" },
    },
},
-- sync executor
function(input)
    return { success = false, error = "write_file requires async execution" }
end,
-- async executor
function(input, callback)
    if not input.path then
        callback({ success = false, error = "Missing path" })
        return
    end
    if not input.content then
        callback({ success = false, error = "Missing content" })
        return
    end

    local path = resolve_path(input.path)

    -- Fail if file exists
    if vim.fn.filereadable(path) == 1 then
        callback({ success = false, error = "File already exists: " .. path .. ". Use replace_lines to edit existing files." })
        return
    end

    local proposed_lines = vim.split(input.content, "\n", { plain = true })

    vim.schedule(function()
        open_diff_view(
            {},
            proposed_lines,
            input.path,
            function(result)
                local response = { success = true, message = "File created: " .. input.path }
                if result and result.errors and #result.errors > 0 then
                    response.diagnostics = result.errors
                end
                callback(response)
            end,
            function(reason) callback({ success = false, error = reason or "Write rejected" }) end
        )
    end)
end)

-- replace_lines: patch-like line replacement with diff view
M.register_async("replace_lines", {
    name = "replace_lines",
    description = "Replace a range of lines in an existing file. ALWAYS read_file first to get accurate line numbers. Shows a diff view for user approval. Preferred tool for editing existing files. Set from_line > to_line to INSERT before from_line. Use empty text to DELETE lines. Line numbers are 1-indexed and inclusive.",
    input_schema = {
        type = "object",
        properties = {
            path = { type = "string", description = "File path (absolute or relative to cwd)" },
            from_line = { type = "number", description = "Start line (1-indexed)" },
            to_line = { type = "number", description = "End line (1-indexed, inclusive). Set < from_line to insert before from_line" },
            text = { type = "string", description = "Replacement text (can be empty to delete lines)" },
        },
        required = { "path", "from_line", "to_line", "text" },
    },
},
-- sync executor
function(input)
    return { success = false, error = "replace_lines requires async execution" }
end,
-- async executor
function(input, callback)
    if not input.path then
        callback({ success = false, error = "Missing path" })
        return
    end
    if not input.from_line then
        callback({ success = false, error = "Missing from_line" })
        return
    end
    if not input.to_line then
        callback({ success = false, error = "Missing to_line" })
        return
    end
    if input.text == nil then
        callback({ success = false, error = "Missing text" })
        return
    end

    local path = resolve_path(input.path)

    -- File must exist for replace_lines
    if vim.fn.filereadable(path) ~= 1 then
        callback({ success = false, error = "File not found: " .. path })
        return
    end

    local original_lines = vim.fn.readfile(path)
    local new_lines = vim.split(input.text, "\n", { plain = true })

    -- Handle empty text as deletion (empty array)
    if input.text == "" then
        new_lines = {}
    end

    local proposed_lines = M.apply_line_replacement(
        original_lines,
        input.from_line,
        input.to_line,
        new_lines
    )

    vim.schedule(function()
        open_diff_view(
            original_lines,
            proposed_lines,
            input.path,
            function(result)
                local response = { success = true, message = string.format(
                    "Replaced lines %d-%d in %s",
                    input.from_line, input.to_line, input.path
                )}
                if result and result.errors and #result.errors > 0 then
                    response.diagnostics = result.errors
                end
                callback(response)
            end,
            function(reason) callback({ success = false, error = reason or "Edit rejected" }) end
        )
    end)
end)

-- read_file: read file contents
M.register("read_file", {
    name = "read_file",
    description = "Read contents of a file. ALWAYS use this before editing a file to understand context and get accurate line numbers. For large files (>500 lines), use start_line/end_line to read specific sections. Returns content with line numbers prefixed. The file will be opened in Neovim so the user can follow along.",
    input_schema = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to file (absolute or relative to cwd)",
            },
            start_line = {
                type = "number",
                description = "Start line (1-indexed). Omit to read from beginning.",
            },
            end_line = {
                type = "number",
                description = "End line (1-indexed, inclusive). Omit to read to end.",
            },
        },
        required = { "path" },
    },
}, function(input)
    if not input.path then
        return { success = false, error = "Missing file path" }
    end

    local path = resolve_path(input.path)

    if vim.fn.filereadable(path) ~= 1 then
        return { success = false, error = "File not found: " .. path }
    end

    -- Follow agent: open file in buffer (without stealing focus)
    if M.config.follow_agent then
        vim.schedule(function()
            local current_win = vim.api.nvim_get_current_win()
            local target_win = find_editor_window()
            if target_win then
                vim.api.nvim_win_call(target_win, function()
                    vim.cmd("edit " .. vim.fn.fnameescape(path))
                    if input.start_line then
                        vim.api.nvim_win_set_cursor(0, { input.start_line, 0 })
                    end
                end)
                vim.api.nvim_set_current_win(current_win)
            end
        end)
    end

    local lines = vim.fn.readfile(path)

    local start_line = input.start_line or 1
    local end_line = input.end_line or #lines

    -- Clamp bounds
    start_line = math.max(1, start_line)
    end_line = math.min(#lines, end_line)

    local selected = {}
    for i = start_line, end_line do
        table.insert(selected, string.format("%d: %s", i, lines[i]))
    end

    local content = table.concat(selected, "\n")
    local msg = string.format("File: %s (lines %d-%d)\n%s", path, start_line, end_line, content)

    return { success = true, message = msg }
end)

-- run_command: execute shell commands with safety guardrails
-- Blocklist of dangerous commands/patterns
local COMMAND_BLOCKLIST = {
    "rm%s+%-rf%s+/",
    "rm%s+%-rf%s+%~/",
    "rm%s+%-rf%s+%.%.",
    ">%s*/",
    "dd%s+if=",
    "mkfs",
    "fdisk",
    "format",
    "del%s+/",
    "rmdir%s+/s",
    "shutdown",
    "reboot",
    "halt",
    "poweroff",
    "init%s+0",
    ":(){",
    "fork",
}

local function is_command_blocked(cmd)
    local lower_cmd = cmd:lower()
    for _, pattern in ipairs(COMMAND_BLOCKLIST) do
        if lower_cmd:match(pattern) then
            return pattern
        end
    end
    return nil
end

local function sanitize_command(input)
    local cmd = input.command
    if not cmd or cmd == "" then
        return nil, "Missing command"
    end

    -- Check blocklist
    local blocked = is_command_blocked(cmd)
    if blocked then
        return nil, "Command blocked for safety (matches pattern: " .. blocked .. ")"
    end

    -- Validate timeout
    local timeout = input.timeout or 30000
    if timeout < 1000 then
        timeout = 1000
    elseif timeout > 120000 then
        timeout = 120000  -- Max 2 minutes
    end

    return { command = cmd, timeout = timeout, cwd = input.cwd }, nil
end

M.register_async("run_command", {
    name = "run_command",
    description = "Execute a shell command in the project root. Use for running tests (e.g., 'go test ./...', 'npm test'), builds, linters, git commands, or checking project state. Dangerous commands (rm -rf /, mkfs, etc.) are blocked. Max timeout 2 minutes. Returns stdout, stderr, and exit code.",
    input_schema = {
        type = "object",
        properties = {
            command = {
                type = "string",
                description = "Shell command to execute. Dangerous commands (rm -rf /, mkfs, etc.) are blocked.",
            },
            cwd = {
                type = "string",
                description = "Working directory for command. Defaults to current working directory.",
            },
            timeout = {
                type = "number",
                description = "Timeout in milliseconds. Default 30000 (30s), max 120000 (2min).",
            },
        },
        required = { "command" },
    },
},
-- sync executor
function(input)
    return { success = false, error = "run_command requires async execution" }
end,
-- async executor
function(input, callback)
    local spec, err = sanitize_command(input)
    if not spec then
        callback({ success = false, error = err })
        return
    end

    local cmd = spec.command
    local timeout = spec.timeout
    local cwd = spec.cwd

    -- Prepare system options
    local opts = { text = true }
    if cwd then
        opts.cwd = cwd
    end

    -- Track timeout
    local timed_out = false
    local timeout_timer = vim.uv.new_timer()
    local job = nil

    timeout_timer:start(timeout, 0, vim.schedule_wrap(function()
        timed_out = true
        if job then
            pcall(vim.fn.jobstop, job)
        end
    end))

    -- Use vim.system for async execution
    job = vim.system({ "sh", "-c", cmd }, opts, function(result)
        -- Cancel timeout timer
        if timeout_timer then
            timeout_timer:stop()
            timeout_timer:close()
        end

        vim.schedule(function()
            if timed_out then
                callback({ success = false, error = "Command timed out after " .. timeout .. "ms" })
                return
            end

            local exit_code = result.code
            local stdout = result.stdout or ""
            local stderr = result.stderr or ""

            -- Build response message
            local lines = {}
            table.insert(lines, "Command: " .. cmd)
            if cwd then
                table.insert(lines, "Working dir: " .. cwd)
            end
            table.insert(lines, "Exit code: " .. exit_code)

            if stdout ~= "" then
                table.insert(lines, "")
                table.insert(lines, "STDOUT:")
                for _, line in ipairs(vim.split(stdout, "\n", { trimempty = false })) do
                    table.insert(lines, line)
                end
            end

            if stderr ~= "" then
                table.insert(lines, "")
                table.insert(lines, "STDERR:")
                for _, line in ipairs(vim.split(stderr, "\n", { trimempty = false })) do
                    table.insert(lines, line)
                end
            end

            local message = table.concat(lines, "\n")

            if exit_code == 0 then
                callback({ success = true, message = message })
            else
                callback({ success = false, error = "Exit code " .. exit_code, message = message })
            end
        end)
    end)
end)

-- document_symbols: list all symbols in a file via LSP
M.register_async("document_symbols", {
    name = "document_symbols",
    description = "List all symbols (functions, classes, methods, variables, etc.) in a specific file using LSP. Use this to understand file structure before editing, or to find the line number of a specific function/class. More accurate than text search for code navigation. Requires an LSP server for the file type.",
    input_schema = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "File path (absolute or relative to cwd)",
            },
        },
        required = { "path" },
    },
},
-- sync executor
function(input)
    return { success = false, error = "document_symbols requires async execution" }
end,
-- async executor
function(input, callback)
    if not input.path then
        callback({ success = false, error = "Missing path" })
        return
    end

    local path = resolve_path(input.path)

    -- Check file exists
    if vim.fn.filereadable(path) ~= 1 then
        callback({ success = false, error = "File not found: " .. path })
        return
    end

    vim.schedule(function()
        -- Find or create buffer for the file
        local bufnr = vim.fn.bufnr(path)
        if bufnr == -1 then
            -- Load the file into a buffer
            bufnr = vim.fn.bufadd(path)
            vim.fn.bufload(bufnr)
        end

        local function make_request()
            -- Make the LSP request
            local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }

            vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params, function(err, result)
                if err then
                    callback({ success = false, error = "LSP error: " .. tostring(err) })
                    return
                end

                if not result or #result == 0 then
                    callback({ success = true, message = "No symbols found in " .. path })
                    return
                end

                local symbols = M.format_lsp_symbols(result)

                -- Format output
                local lines = { "Symbols in " .. path .. ":" }
                for _, sym in ipairs(symbols) do
                    local line_info = sym.line and (":" .. sym.line) or ""
                    table.insert(lines, string.format("  %s %s%s", sym.kind, sym.name, line_info))
                end

                callback({ success = true, message = table.concat(lines, "\n") })
            end)
        end

        -- Check if LSP is already attached
        local clients = vim.lsp.get_clients({ bufnr = bufnr })
        if #clients > 0 then
            make_request()
        else
            -- Wait for LSP to attach (up to 2 seconds)
            M.wait_for_lsp_attach(bufnr, 2000, function(attached_clients)
                if not attached_clients then
                    callback({ success = false, error = "No LSP server attached to buffer after 2s. Ensure an LSP is configured for this file type." })
                    return
                end
                make_request()
            end)
        end
    end)
end)

-- workspace_symbols: search for symbols by name across the workspace via LSP
M.register_async("workspace_symbols", {
    name = "workspace_symbols",
    description = "Search for symbols by name across the entire project using LSP. Use this to find where a function, class, or type is defined globally. More accurate than grep for finding definitions. Supports partial matching. Returns symbol name, kind, file path, and line number. Requires an LSP server with workspace symbol support.",
    input_schema = {
        type = "object",
        properties = {
            query = {
                type = "string",
                description = "Symbol name to search for (partial match supported)",
            },
        },
        required = { "query" },
    },
},
-- sync executor
function(input)
    return { success = false, error = "workspace_symbols requires async execution" }
end,
-- async executor
function(input, callback)
    if not input.query then
        callback({ success = false, error = "Missing query" })
        return
    end

    vim.schedule(function()
        -- Find a buffer with an LSP client that supports workspace symbols
        local clients = vim.lsp.get_clients()
        local client = nil

        for _, c in ipairs(clients) do
            if c.server_capabilities.workspaceSymbolProvider then
                client = c
                break
            end
        end

        if not client then
            callback({ success = false, error = "No LSP server with workspace symbol support found" })
            return
        end

        -- Make the LSP request
        local params = { query = input.query }

        client.request("workspace/symbol", params, function(err, result)
            if err then
                callback({ success = false, error = "LSP error: " .. tostring(err) })
                return
            end

            if not result or #result == 0 then
                callback({ success = true, message = "No symbols found matching '" .. input.query .. "'" })
                return
            end

            local symbols = M.format_workspace_symbols(result)

            -- Format output
            local lines = { "Symbols matching '" .. input.query .. "':" }
            for _, sym in ipairs(symbols) do
                local location = ""
                if sym.file then
                    -- Make path relative to cwd if possible
                    local cwd = vim.fn.getcwd()
                    local rel_path = sym.file
                    if vim.startswith(sym.file, cwd) then
                        rel_path = sym.file:sub(#cwd + 2)
                    end
                    location = rel_path .. (sym.line and (":" .. sym.line) or "")
                end
                table.insert(lines, string.format("  %s %s  [%s]", sym.kind, sym.name, location))
            end

            callback({ success = true, message = table.concat(lines, "\n") })
        end)
    end)
end)

return M
