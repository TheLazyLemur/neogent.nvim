-- neogent.nvim - Init module tests
-- Run with: nvim --headless -c "luafile lua/neogent/init_spec.lua" -c "qa!"

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

local function assert_contains(str, pattern, msg)
    if not string.find(str, pattern, 1, true) then
        error((msg or "assertion failed") .. ": expected string to contain '" .. pattern .. "', got: " .. str)
    end
end

-- Test format_tool_error_content includes message when present
test("format_tool_error_content includes result.message when present", function()
    package.loaded["neogent"] = nil
    local neogent = require("neogent")

    local result = {
        error = "Exit code 1",
        message = "Command: npm install\nExit code: 1\n\nSTDERR:\nnpm: command not found",
    }

    local content = neogent.format_tool_error_content(result)

    assert_contains(content, "Exit code 1", "should contain error")
    assert_contains(content, "npm: command not found", "should contain stderr from message")
end)

-- Test format_tool_error_content works without message
test("format_tool_error_content works when message is nil", function()
    package.loaded["neogent"] = nil
    local neogent = require("neogent")

    local result = {
        error = "Tool not found",
    }

    local content = neogent.format_tool_error_content(result)

    assert_contains(content, "Tool not found", "should contain error")
    assert_contains(content, "retry", "should contain retry hint")
end)

-- Test format_tool_error_content works with empty message
test("format_tool_error_content ignores empty message", function()
    package.loaded["neogent"] = nil
    local neogent = require("neogent")

    local result = {
        error = "Validation failed",
        message = "",
    }

    local content = neogent.format_tool_error_content(result)

    assert_contains(content, "Validation failed", "should contain error")
    -- Should not have double newlines from empty message
end)

print("\n--- Init Tests Complete ---\n")
