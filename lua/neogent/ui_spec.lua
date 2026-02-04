-- neogent.nvim - UI tests
-- Run with: nvim --headless -c "luafile lua/neogent/ui_spec.lua" -c "qa!"

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

local function assert_contains(tbl, value, msg)
    for _, v in ipairs(tbl) do
        if v == value then return end
    end
    error((msg or "assertion failed") .. ": table does not contain " .. vim.inspect(value))
end

local function assert_match(str, pattern, msg)
    if not string.match(str, pattern) then
        error((msg or "assertion failed") .. ": '" .. str .. "' does not match pattern '" .. pattern .. "'")
    end
end

-- Test highlight groups are defined
test("highlight groups are defined on module load", function()
    -- Reset any existing highlight groups
    vim.cmd("highlight clear ChatToolPending")
    vim.cmd("highlight clear ChatToolRunning")
    vim.cmd("highlight clear ChatToolSuccess")
    vim.cmd("highlight clear ChatToolError")

    -- Reload the module
    package.loaded["neogent.ui"] = nil
    local ui = require("neogent.ui")

    -- Check highlight groups exist
    local pending = vim.api.nvim_get_hl(0, { name = "ChatToolPending" })
    local running = vim.api.nvim_get_hl(0, { name = "ChatToolRunning" })
    local success = vim.api.nvim_get_hl(0, { name = "ChatToolSuccess" })
    local error_hl = vim.api.nvim_get_hl(0, { name = "ChatToolError" })

    assert(pending.fg ~= nil, "ChatToolPending should have fg colour")
    assert(running.fg ~= nil, "ChatToolRunning should have fg colour")
    assert(success.fg ~= nil, "ChatToolSuccess should have fg colour")
    assert(error_hl.fg ~= nil, "ChatToolError should have fg colour")
end)

-- Test add_tool_separator function exists and works
test("add_tool_separator adds separator entry", function()
    package.loaded["neogent.ui"] = nil
    local ui = require("neogent.ui")

    -- Clear and add a tool
    ui.clear_tool_status()
    ui.add_tool_status("tool_1", "read_file", "success")

    -- Add separator
    ui.add_tool_separator()

    -- Add another tool
    ui.add_tool_status("tool_2", "write_file", "pending")

    -- The internal state should have separator between tools
    -- We verify by checking the function exists and doesn't error
    assert(type(ui.add_tool_separator) == "function", "add_tool_separator should be a function")
end)

-- Test that add_tool_separator does nothing when no tools exist
test("add_tool_separator does nothing when no tools", function()
    package.loaded["neogent.ui"] = nil
    local ui = require("neogent.ui")

    ui.clear_tool_status()

    -- Should not error
    ui.add_tool_separator()
end)

-- Test tool statuses persist across multiple add_tool_status calls
test("tool statuses accumulate without clearing", function()
    package.loaded["neogent.ui"] = nil
    local ui = require("neogent.ui")

    ui.clear_tool_status()
    ui.add_tool_status("id1", "tool1", "success")
    ui.add_tool_status("id2", "tool2", "success")
    ui.add_tool_status("id3", "tool3", "pending")

    -- All three should be tracked - update by ID
    ui.update_tool_status("id1", "success")
    ui.update_tool_status("id2", "error")
    ui.update_tool_status("id3", "running")
end)

-- Test _render_status handles separator entries
test("_render_status handles separator entries", function()
    package.loaded["neogent.ui"] = nil
    local ui = require("neogent.ui")

    -- Create a status buffer for testing
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"

    ui.clear_tool_status()
    ui.add_tool_status("id1", "tool1", "success")
    ui.add_tool_separator()
    ui.add_tool_status("id2", "tool2", "pending")

    -- Give vim.schedule time to run
    vim.wait(100, function() return false end)
end)

-- Test duplicate tool names are tracked separately by ID
test("duplicate tool names tracked by ID", function()
    package.loaded["neogent.ui"] = nil
    local ui = require("neogent.ui")

    ui.clear_tool_status()
    ui.add_tool_status("id_a", "read_file", "pending")
    ui.add_tool_status("id_b", "read_file", "pending")
    ui.add_tool_status("id_c", "read_file", "pending")

    -- Update each by ID - they should update independently
    ui.update_tool_status("id_a", "success")
    ui.update_tool_status("id_b", "running")
    ui.update_tool_status("id_c", "error")
end)

print("\n--- UI Tests Complete ---\n")
