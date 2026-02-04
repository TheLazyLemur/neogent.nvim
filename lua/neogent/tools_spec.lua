-- neogent.nvim - Tool tests
-- Run with: nvim --headless -c "luafile lua/neogent/tools_spec.lua" -c "qa!"

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("✓ " .. name)
    else
        print("✗ " .. name)
        print("  " .. tostring(err))
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "assertion failed") .. ": expected " .. vim.inspect(b) .. ", got " .. vim.inspect(a))
    end
end

local function assert_table_eq(a, b, msg)
    if vim.inspect(a) ~= vim.inspect(b) then
        error((msg or "assertion failed") .. ": expected " .. vim.inspect(b) .. ", got " .. vim.inspect(a))
    end
end

-- Test format_error_diagnostics returns empty table when no diagnostics
test("format_error_diagnostics returns empty table when no diagnostics", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local result = tools.format_error_diagnostics({})
    assert_table_eq(result, {}, "should return empty table")
end)

-- Test format_error_diagnostics filters to errors only
test("format_error_diagnostics filters to errors only", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local diagnostics = {
        { severity = vim.diagnostic.severity.ERROR, lnum = 10, col = 5, message = "undefined variable 'foo'" },
        { severity = vim.diagnostic.severity.WARN, lnum = 15, col = 0, message = "unused variable" },
        { severity = vim.diagnostic.severity.ERROR, lnum = 20, col = 12, message = "type mismatch" },
        { severity = vim.diagnostic.severity.HINT, lnum = 25, col = 0, message = "consider using const" },
    }

    local result = tools.format_error_diagnostics(diagnostics)

    assert_eq(#result, 2, "should have 2 errors")
    assert_eq(result[1].line, 11, "first error line (1-indexed)")
    assert_eq(result[1].message, "undefined variable 'foo'", "first error message")
    assert_eq(result[2].line, 21, "second error line (1-indexed)")
    assert_eq(result[2].message, "type mismatch", "second error message")
end)

-- Test format_error_diagnostics includes column info
test("format_error_diagnostics includes column info", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local diagnostics = {
        { severity = vim.diagnostic.severity.ERROR, lnum = 5, col = 10, message = "error here" },
    }

    local result = tools.format_error_diagnostics(diagnostics)

    assert_eq(result[1].col, 11, "column should be 1-indexed")
end)

-- Test format_error_diagnostics handles missing fields gracefully
test("format_error_diagnostics handles missing fields gracefully", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local diagnostics = {
        { severity = vim.diagnostic.severity.ERROR, lnum = 0, message = "minimal error" },
    }

    local result = tools.format_error_diagnostics(diagnostics)

    assert_eq(#result, 1, "should have 1 error")
    assert_eq(result[1].line, 1, "line should default correctly")
    assert_eq(result[1].message, "minimal error", "message should be present")
end)

-- Test get_buffer_error_diagnostics returns errors for a buffer
test("get_buffer_error_diagnostics returns formatted errors for buffer", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    -- Create a test buffer
    local buf = vim.api.nvim_create_buf(false, true)

    -- Set some mock diagnostics on the buffer
    local ns = vim.api.nvim_create_namespace("test_diagnostics")
    vim.diagnostic.set(ns, buf, {
        { lnum = 0, col = 0, message = "Test error", severity = vim.diagnostic.severity.ERROR },
        { lnum = 5, col = 10, message = "Another error", severity = vim.diagnostic.severity.ERROR },
        { lnum = 10, col = 0, message = "Just a warning", severity = vim.diagnostic.severity.WARN },
    })

    local result = tools.get_buffer_error_diagnostics(buf)

    assert_eq(#result, 2, "should have 2 errors")
    assert_eq(result[1].line, 1, "first error line")
    assert_eq(result[1].message, "Test error", "first error message")
    assert_eq(result[2].line, 6, "second error line")

    -- Cleanup
    vim.diagnostic.reset(ns, buf)
    vim.api.nvim_buf_delete(buf, { force = true })
end)

-- Test get_buffer_error_diagnostics returns empty for buffer with no errors
test("get_buffer_error_diagnostics returns empty when no errors", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local buf = vim.api.nvim_create_buf(false, true)

    local result = tools.get_buffer_error_diagnostics(buf)

    assert_table_eq(result, {}, "should return empty table")

    vim.api.nvim_buf_delete(buf, { force = true })
end)

-- Test apply_line_replacement replaces middle lines
test("apply_line_replacement replaces middle lines", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local original = { "line1", "line2", "line3", "line4", "line5" }
    local result = tools.apply_line_replacement(original, 2, 4, { "new2", "new3" })

    assert_table_eq(result, { "line1", "new2", "new3", "line5" }, "should replace lines 2-4")
end)

-- Test apply_line_replacement inserts when from > to (insert before from_line)
test("apply_line_replacement inserts when from > to", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local original = { "line1", "line2", "line3" }
    local result = tools.apply_line_replacement(original, 2, 1, { "inserted" })

    assert_table_eq(result, { "line1", "inserted", "line2", "line3" }, "should insert before line 2")
end)

-- Test apply_line_replacement deletes when text is empty
test("apply_line_replacement deletes when text is empty", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local original = { "line1", "line2", "line3", "line4" }
    local result = tools.apply_line_replacement(original, 2, 3, {})

    assert_table_eq(result, { "line1", "line4" }, "should delete lines 2-3")
end)

-- Test apply_line_replacement handles single line replacement
test("apply_line_replacement handles single line replacement", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local original = { "line1", "line2", "line3" }
    local result = tools.apply_line_replacement(original, 2, 2, { "replaced" })

    assert_table_eq(result, { "line1", "replaced", "line3" }, "should replace line 2 only")
end)

-- Test apply_line_replacement handles replacement at start
test("apply_line_replacement handles replacement at start", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local original = { "line1", "line2", "line3" }
    local result = tools.apply_line_replacement(original, 1, 1, { "new_first" })

    assert_table_eq(result, { "new_first", "line2", "line3" }, "should replace first line")
end)

-- Test apply_line_replacement handles replacement at end
test("apply_line_replacement handles replacement at end", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local original = { "line1", "line2", "line3" }
    local result = tools.apply_line_replacement(original, 3, 3, { "new_last" })

    assert_table_eq(result, { "line1", "line2", "new_last" }, "should replace last line")
end)

-- Test apply_line_replacement expands single line to multiple
test("apply_line_replacement expands single line to multiple", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local original = { "line1", "line2", "line3" }
    local result = tools.apply_line_replacement(original, 2, 2, { "new2a", "new2b", "new2c" })

    assert_table_eq(result, { "line1", "new2a", "new2b", "new2c", "line3" }, "should expand to multiple lines")
end)

-- Test wait_for_lsp_attach returns nil on timeout (no LSP attached)
test("wait_for_lsp_attach returns nil on timeout when no LSP", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    -- Create a scratch buffer with no LSP
    local buf = vim.api.nvim_create_buf(false, true)
    local result_received = false
    local result_clients = "not_called"

    tools.wait_for_lsp_attach(buf, 100, function(clients)
        result_received = true
        result_clients = clients
    end)

    -- Wait for callback (async)
    vim.wait(200, function() return result_received end)

    assert_eq(result_received, true, "callback should be called")
    assert_eq(result_clients, nil, "should return nil when no LSP attaches")

    vim.api.nvim_buf_delete(buf, { force = true })
end)

-- Test format_lsp_symbols handles empty input
test("format_lsp_symbols returns empty table for nil input", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local result = tools.format_lsp_symbols(nil)
    assert_table_eq(result, {}, "should return empty table for nil")
end)

test("format_lsp_symbols returns empty table for empty input", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local result = tools.format_lsp_symbols({})
    assert_table_eq(result, {}, "should return empty table for empty array")
end)

-- Test format_lsp_symbols converts symbol kinds to names
test("format_lsp_symbols converts kind numbers to names", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local symbols = {
        {
            name = "MyClass",
            kind = 5,  -- Class
            range = { start = { line = 10, character = 0 }, ["end"] = { line = 20, character = 1 } },
        },
        {
            name = "my_function",
            kind = 12,  -- Function
            range = { start = { line = 25, character = 0 }, ["end"] = { line = 30, character = 1 } },
        },
    }

    local result = tools.format_lsp_symbols(symbols)

    assert_eq(#result, 2, "should have 2 symbols")
    assert_eq(result[1].name, "MyClass", "first symbol name")
    assert_eq(result[1].kind, "Class", "first symbol kind should be converted")
    assert_eq(result[1].line, 11, "line should be 1-indexed")
    assert_eq(result[2].name, "my_function", "second symbol name")
    assert_eq(result[2].kind, "Function", "second symbol kind should be converted")
    assert_eq(result[2].line, 26, "line should be 1-indexed")
end)

-- Test format_lsp_symbols handles unknown kind numbers
test("format_lsp_symbols handles unknown kind numbers", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local symbols = {
        {
            name = "unknown_thing",
            kind = 999,  -- Unknown
            range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
        },
    }

    local result = tools.format_lsp_symbols(symbols)

    assert_eq(result[1].kind, "Unknown", "unknown kind should default to 'Unknown'")
end)

-- Test format_lsp_symbols flattens nested children
test("format_lsp_symbols flattens nested children", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local symbols = {
        {
            name = "OuterClass",
            kind = 5,  -- Class
            range = { start = { line = 0, character = 0 }, ["end"] = { line = 50, character = 1 } },
            children = {
                {
                    name = "inner_method",
                    kind = 6,  -- Method
                    range = { start = { line = 10, character = 4 }, ["end"] = { line = 20, character = 5 } },
                },
                {
                    name = "inner_field",
                    kind = 8,  -- Field
                    range = { start = { line = 5, character = 4 }, ["end"] = { line = 5, character = 20 } },
                },
            },
        },
    }

    local result = tools.format_lsp_symbols(symbols)

    assert_eq(#result, 3, "should flatten to 3 symbols")
    assert_eq(result[1].name, "OuterClass", "parent first")
    assert_eq(result[2].name, "inner_method", "first child")
    assert_eq(result[2].kind, "Method", "child kind")
    assert_eq(result[3].name, "inner_field", "second child")
end)

-- Test format_workspace_symbols handles empty input
test("format_workspace_symbols returns empty table for nil input", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local result = tools.format_workspace_symbols(nil)
    assert_table_eq(result, {}, "should return empty table for nil")
end)

test("format_workspace_symbols returns empty table for empty input", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local result = tools.format_workspace_symbols({})
    assert_table_eq(result, {}, "should return empty table for empty array")
end)

-- Test format_workspace_symbols extracts file path from URI
test("format_workspace_symbols extracts file path from URI", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local symbols = {
        {
            name = "MyService",
            kind = 5,  -- Class
            location = {
                uri = "file:///home/user/project/src/service.lua",
                range = { start = { line = 10, character = 0 }, ["end"] = { line = 50, character = 1 } },
            },
        },
        {
            name = "helper_func",
            kind = 12,  -- Function
            location = {
                uri = "file:///home/user/project/utils.lua",
                range = { start = { line = 5, character = 0 }, ["end"] = { line = 15, character = 1 } },
            },
        },
    }

    local result = tools.format_workspace_symbols(symbols)

    assert_eq(#result, 2, "should have 2 symbols")
    assert_eq(result[1].name, "MyService", "first symbol name")
    assert_eq(result[1].kind, "Class", "first symbol kind")
    assert_eq(result[1].file, "/home/user/project/src/service.lua", "file path extracted from URI")
    assert_eq(result[1].line, 11, "line should be 1-indexed")
    assert_eq(result[2].file, "/home/user/project/utils.lua", "second file path")
end)

-- Test format_workspace_symbols handles missing location gracefully
test("format_workspace_symbols handles missing location", function()
    package.loaded["neogent.tools"] = nil
    local tools = require("neogent.tools")

    local symbols = {
        {
            name = "orphan_symbol",
            kind = 13,  -- Variable
            -- no location field
        },
    }

    local result = tools.format_workspace_symbols(symbols)

    assert_eq(#result, 1, "should still include symbol")
    assert_eq(result[1].name, "orphan_symbol", "name preserved")
    assert_eq(result[1].file, nil, "file should be nil")
    assert_eq(result[1].line, nil, "line should be nil")
end)

print("\n--- Tools Tests Complete ---\n")
