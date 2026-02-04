-- neogent.nvim - Skills tests
-- Run with: nvim --headless -c "luafile lua/neogent/skills_spec.lua" -c "qa!"

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

local function assert_contains(str, substr, msg)
    if not str:find(substr, 1, true) then
        error((msg or "assertion failed") .. ": expected string to contain '" .. substr .. "', got: " .. str)
    end
end

local function assert_nil(val, msg)
    if val ~= nil then
        error((msg or "assertion failed") .. ": expected nil, got " .. vim.inspect(val))
    end
end

local function assert_true(val, msg)
    if val ~= true then
        error((msg or "assertion failed") .. ": expected true, got " .. vim.inspect(val))
    end
end

local function assert_false(val, msg)
    if val ~= false then
        error((msg or "assertion failed") .. ": expected false, got " .. vim.inspect(val))
    end
end

-- Helper to create temp directories and files
local function create_temp_skill(dir, name, description, content)
    local skill_dir = dir .. "/" .. name
    vim.fn.mkdir(skill_dir, "p")
    local skill_file = skill_dir .. "/SKILL.md"
    local skill_content = string.format([[---
name: %s
description: %s
---

%s]], name, description, content or "Skill instructions here.")
    vim.fn.writefile(vim.split(skill_content, "\n"), skill_file)
    return skill_dir
end

local function cleanup_temp_dir(dir)
    vim.fn.delete(dir, "rf")
end

-- parse_frontmatter tests
test("parse_frontmatter extracts name and description correctly", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    local skill_file = temp_dir .. "/SKILL.md"
    vim.fn.writefile({
        "---",
        "name: test-skill",
        "description: A test skill for unit testing",
        "---",
        "",
        "# Instructions",
        "Do the thing.",
    }, skill_file)

    local result = skills.parse_frontmatter(skill_file)

    assert_eq(result.name, "test-skill", "name should be extracted")
    assert_eq(result.description, "A test skill for unit testing", "description should be extracted")

    cleanup_temp_dir(temp_dir)
end)

test("parse_frontmatter returns nil for invalid file (no frontmatter)", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    local skill_file = temp_dir .. "/SKILL.md"
    vim.fn.writefile({
        "# No frontmatter here",
        "Just regular markdown.",
    }, skill_file)

    local result = skills.parse_frontmatter(skill_file)

    assert_nil(result, "should return nil for missing frontmatter")

    cleanup_temp_dir(temp_dir)
end)

test("parse_frontmatter returns nil for missing name field", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    local skill_file = temp_dir .. "/SKILL.md"
    vim.fn.writefile({
        "---",
        "description: Missing name field",
        "---",
        "Content",
    }, skill_file)

    local result = skills.parse_frontmatter(skill_file)

    assert_nil(result, "should return nil when name is missing")

    cleanup_temp_dir(temp_dir)
end)

test("parse_frontmatter returns nil for missing description field", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    local skill_file = temp_dir .. "/SKILL.md"
    vim.fn.writefile({
        "---",
        "name: missing-desc",
        "---",
        "Content",
    }, skill_file)

    local result = skills.parse_frontmatter(skill_file)

    assert_nil(result, "should return nil when description is missing")

    cleanup_temp_dir(temp_dir)
end)

test("parse_frontmatter validates name format (lowercase and hyphens only)", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    local skill_file = temp_dir .. "/SKILL.md"
    vim.fn.writefile({
        "---",
        "name: Invalid_Name",
        "description: Has underscores",
        "---",
        "Content",
    }, skill_file)

    local result = skills.parse_frontmatter(skill_file)

    assert_nil(result, "should return nil for invalid name format")

    cleanup_temp_dir(temp_dir)
end)

test("parse_frontmatter validates name format (no consecutive hyphens)", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    local skill_file = temp_dir .. "/SKILL.md"
    vim.fn.writefile({
        "---",
        "name: bad--name",
        "description: Has consecutive hyphens",
        "---",
        "Content",
    }, skill_file)

    local result = skills.parse_frontmatter(skill_file)

    assert_nil(result, "should return nil for consecutive hyphens")

    cleanup_temp_dir(temp_dir)
end)

test("parse_frontmatter validates name length (1-64 chars)", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    -- Test empty name
    local skill_file1 = temp_dir .. "/SKILL1.md"
    vim.fn.writefile({
        "---",
        "name: ",
        "description: Empty name",
        "---",
        "Content",
    }, skill_file1)
    local result1 = skills.parse_frontmatter(skill_file1)
    assert_nil(result1, "should return nil for empty name")

    -- Test name too long (>64 chars)
    local skill_file2 = temp_dir .. "/SKILL2.md"
    local long_name = string.rep("a", 65)
    vim.fn.writefile({
        "---",
        "name: " .. long_name,
        "description: Name too long",
        "---",
        "Content",
    }, skill_file2)
    local result2 = skills.parse_frontmatter(skill_file2)
    assert_nil(result2, "should return nil for name > 64 chars")

    cleanup_temp_dir(temp_dir)
end)

-- generate_available_xml tests
test("generate_available_xml produces correct XML structure", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    skills.available = {
        { name = "test-skill", description = "A test skill", path = "/tmp/test" },
        { name = "another-skill", description = "Another skill", path = "/tmp/another" },
    }

    local xml = skills.generate_available_xml()

    assert_contains(xml, "<available-skills>", "should have opening tag")
    assert_contains(xml, "</available-skills>", "should have closing tag")
    assert_contains(xml, "<skill name=\"test-skill\">", "should have first skill")
    assert_contains(xml, "A test skill", "should have first description")
    assert_contains(xml, "<skill name=\"another-skill\">", "should have second skill")
    assert_contains(xml, "Another skill", "should have second description")

    skills.available = {}
end)

test("generate_available_xml returns empty string when no skills", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    skills.available = {}

    local xml = skills.generate_available_xml()

    assert_eq(xml, "", "should return empty string")
end)

-- discover tests
test("discover finds skills in directories", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    create_temp_skill(temp_dir, "skill-one", "First skill")
    create_temp_skill(temp_dir, "skill-two", "Second skill")

    local result = skills.discover({ temp_dir })

    assert_eq(#result, 2, "should find 2 skills")
    local names = vim.tbl_map(function(s) return s.name end, result)
    table.sort(names)
    assert_eq(names[1], "skill-one", "first skill name")
    assert_eq(names[2], "skill-two", "second skill name")

    cleanup_temp_dir(temp_dir)
end)

test("discover ignores directories without SKILL.md", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    create_temp_skill(temp_dir, "valid-skill", "Valid skill")

    -- Create a directory without SKILL.md
    local invalid_dir = temp_dir .. "/not-a-skill"
    vim.fn.mkdir(invalid_dir, "p")
    vim.fn.writefile({ "Just a readme" }, invalid_dir .. "/README.md")

    local result = skills.discover({ temp_dir })

    assert_eq(#result, 1, "should only find valid skill")
    assert_eq(result[1].name, "valid-skill", "should be the valid skill")

    cleanup_temp_dir(temp_dir)
end)

test("discover handles non-existent directories gracefully", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local result = skills.discover({ "/non/existent/path/12345" })

    assert_eq(#result, 0, "should return empty table for non-existent paths")
end)

-- load tests
test("load returns content and marks skill as loaded", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    create_temp_skill(temp_dir, "loadable-skill", "A loadable skill", "Do these specific things.")

    skills.available = skills.discover({ temp_dir })

    local result = skills.load("loadable-skill")

    assert_true(result.success, "load should succeed")
    assert_contains(result.content, "Do these specific things.", "should return full content")
    assert_true(skills.is_loaded("loadable-skill"), "skill should be marked as loaded")

    cleanup_temp_dir(temp_dir)
end)

test("load returns error for unknown skill", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    skills.available = {}

    local result = skills.load("non-existent-skill")

    assert_false(result.success, "load should fail")
    assert_contains(result.error, "not found", "should have error message")
end)

-- is_loaded tests
test("is_loaded returns correct state", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    skills.loaded = {}

    assert_false(skills.is_loaded("some-skill"), "should be false initially")

    skills.loaded["some-skill"] = true

    assert_true(skills.is_loaded("some-skill"), "should be true after loading")
    assert_false(skills.is_loaded("other-skill"), "other skill should still be false")
end)

-- get_loaded tests
test("get_loaded returns list of loaded skill names", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    skills.loaded = {
        ["skill-a"] = true,
        ["skill-b"] = true,
    }

    local result = skills.get_loaded()
    table.sort(result)

    assert_eq(#result, 2, "should have 2 loaded skills")
    assert_eq(result[1], "skill-a", "first loaded skill")
    assert_eq(result[2], "skill-b", "second loaded skill")

    skills.loaded = {}
end)

-- clear_loaded tests
test("clear_loaded resets loaded state", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    skills.loaded = { ["skill-a"] = true, ["skill-b"] = true }

    skills.clear_loaded()

    assert_eq(vim.tbl_count(skills.loaded), 0, "loaded should be empty")
    assert_false(skills.is_loaded("skill-a"), "skill-a should not be loaded")
end)

-- generate_reminder_xml tests
test("generate_reminder_xml includes only loaded skills", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    create_temp_skill(temp_dir, "loaded-skill", "Loaded skill", "Loaded instructions")
    create_temp_skill(temp_dir, "unloaded-skill", "Unloaded skill", "Unloaded instructions")

    skills.available = skills.discover({ temp_dir })
    skills.loaded = {}
    skills.load("loaded-skill")

    local xml = skills.generate_reminder_xml()

    assert_contains(xml, "<loaded-skills>", "should have opening tag")
    assert_contains(xml, "</loaded-skills>", "should have closing tag")
    assert_contains(xml, "loaded-skill", "should include loaded skill name")
    assert_contains(xml, "Loaded instructions", "should include loaded skill content")

    -- Should NOT contain unloaded skill content
    if xml:find("Unloaded instructions", 1, true) then
        error("should not include unloaded skill content")
    end

    cleanup_temp_dir(temp_dir)
    skills.loaded = {}
end)

test("generate_reminder_xml returns empty string when no skills loaded", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    skills.loaded = {}

    local xml = skills.generate_reminder_xml()

    assert_eq(xml, "", "should return empty string")
end)

-- refresh tests
test("refresh updates available skills from configured paths", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    create_temp_skill(temp_dir, "refreshed-skill", "Refreshed")

    skills.configure({ paths = { temp_dir } })
    skills.refresh()

    assert_eq(#skills.available, 1, "should have 1 skill after refresh")
    assert_eq(skills.available[1].name, "refreshed-skill", "should find the skill")

    cleanup_temp_dir(temp_dir)
    skills.available = {}
end)

-- configure tests
test("configure sets skills_paths", function()
    package.loaded["neogent.skills"] = nil
    local skills = require("neogent.skills")

    skills.configure({ paths = { "/custom/path", "/another/path" } })

    -- Access internal config to verify (we'll expose this via a getter if needed)
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir .. "/test-skill", "p")
    vim.fn.writefile({
        "---",
        "name: test-skill",
        "description: Test",
        "---",
        "Content",
    }, temp_dir .. "/test-skill/SKILL.md")

    -- Test that discover uses the paths
    skills.configure({ paths = { temp_dir } })
    skills.refresh()
    assert_eq(#skills.available, 1, "should use configured paths")

    cleanup_temp_dir(temp_dir)
    skills.available = {}
end)

print("\n--- Skills Tests Complete ---\n")
