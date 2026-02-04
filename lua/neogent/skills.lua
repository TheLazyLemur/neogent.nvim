-- neogent.nvim - Agent Skills module
-- Implements support for Agent Skills (https://agentskills.io/)
local M = {}

-- State
M.available = {}  -- Discovered skills: {name, description, path}
M.loaded = {}     -- Currently loaded skills: {name = true}

-- Internal config
local config = {
    paths = {},  -- Additional skill directories
}

-- Default discovery locations (in priority order)
local function get_discovery_paths()
    local paths = {}

    -- Project: <cwd>/.skills/
    local project_skills = vim.fn.getcwd() .. "/.skills"
    table.insert(paths, project_skills)

    -- User: ~/.config/neogent/skills/
    local user_skills = vim.fn.expand("~/.config/neogent/skills")
    table.insert(paths, user_skills)

    -- Additional configured paths
    for _, p in ipairs(config.paths or {}) do
        table.insert(paths, p)
    end

    return paths
end

--- Validate skill name format
--- @param name string
--- @return boolean
local function is_valid_name(name)
    if not name or name == "" then
        return false
    end
    if #name > 64 then
        return false
    end
    -- Must be lowercase letters, numbers, and single hyphens only
    -- No consecutive hyphens, no leading/trailing hyphens
    if not name:match("^[a-z0-9]+[a-z0-9%-]*[a-z0-9]+$") and not name:match("^[a-z0-9]+$") then
        return false
    end
    -- Check for consecutive hyphens
    if name:find("%-%-") then
        return false
    end
    return true
end

--- Parse YAML frontmatter from a SKILL.md file
--- @param path string Path to SKILL.md file
--- @return table|nil {name, description} or nil if invalid
function M.parse_frontmatter(path)
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end

    local lines = vim.fn.readfile(path)
    if #lines < 3 then
        return nil
    end

    -- Check for opening delimiter
    if lines[1] ~= "---" then
        return nil
    end

    -- Find closing delimiter
    local end_idx = nil
    for i = 2, #lines do
        if lines[i] == "---" then
            end_idx = i
            break
        end
    end

    if not end_idx then
        return nil
    end

    -- Extract frontmatter lines
    local name = nil
    local description = nil

    for i = 2, end_idx - 1 do
        local line = lines[i]
        local key, value = line:match("^(%w+):%s*(.*)$")
        if key == "name" then
            name = value
        elseif key == "description" then
            description = value
        end
    end

    -- Validate required fields
    if not name or name == "" then
        return nil
    end
    if not description or description == "" then
        return nil
    end

    -- Validate name format
    if not is_valid_name(name) then
        return nil
    end

    return {
        name = name,
        description = description,
    }
end

--- Discover skills in the given directories
--- @param paths string[] List of directory paths to search
--- @return table[] List of {name, description, path}
function M.discover(paths)
    local skills = {}

    for _, dir in ipairs(paths) do
        if vim.fn.isdirectory(dir) == 1 then
            -- List subdirectories
            local entries = vim.fn.readdir(dir)
            for _, entry in ipairs(entries) do
                local skill_dir = dir .. "/" .. entry
                local skill_file = skill_dir .. "/SKILL.md"

                if vim.fn.isdirectory(skill_dir) == 1 and vim.fn.filereadable(skill_file) == 1 then
                    local meta = M.parse_frontmatter(skill_file)
                    if meta then
                        table.insert(skills, {
                            name = meta.name,
                            description = meta.description,
                            path = skill_dir,
                        })
                    end
                end
            end
        end
    end

    return skills
end

--- Generate XML listing available skills for the system prompt
--- @return string XML string or empty string if no skills
function M.generate_available_xml()
    if #M.available == 0 then
        return ""
    end

    local lines = { "<available-skills>" }
    for _, skill in ipairs(M.available) do
        table.insert(lines, string.format('<skill name="%s">', skill.name))
        table.insert(lines, skill.description)
        table.insert(lines, "</skill>")
    end
    table.insert(lines, "</available-skills>")

    return table.concat(lines, "\n")
end

--- Refresh available skills from configured paths
function M.refresh()
    local paths = get_discovery_paths()
    M.available = M.discover(paths)
end

--- Load a skill by name
--- @param name string Skill name
--- @return table {success, content} or {success, error}
function M.load(name)
    -- Find the skill in available
    local skill = nil
    for _, s in ipairs(M.available) do
        if s.name == name then
            skill = s
            break
        end
    end

    if not skill then
        return {
            success = false,
            error = "Skill '" .. name .. "' not found. Use available skills: " ..
                table.concat(vim.tbl_map(function(s) return s.name end, M.available), ", "),
        }
    end

    -- Read the full SKILL.md content
    local skill_file = skill.path .. "/SKILL.md"
    if vim.fn.filereadable(skill_file) ~= 1 then
        return {
            success = false,
            error = "Skill file not found: " .. skill_file,
        }
    end

    local content = table.concat(vim.fn.readfile(skill_file), "\n")

    -- Mark as loaded
    M.loaded[name] = true

    return {
        success = true,
        content = content,
    }
end

--- Check if a skill is loaded
--- @param name string Skill name
--- @return boolean
function M.is_loaded(name)
    return M.loaded[name] == true
end

--- Get list of loaded skill names
--- @return string[]
function M.get_loaded()
    local names = {}
    for name, _ in pairs(M.loaded) do
        table.insert(names, name)
    end
    return names
end

--- Clear loaded skills state
function M.clear_loaded()
    M.loaded = {}
end

--- Generate XML reminder for loaded skills
--- @return string XML string or empty string if no loaded skills
function M.generate_reminder_xml()
    local loaded_names = M.get_loaded()
    if #loaded_names == 0 then
        return ""
    end

    local lines = { "<loaded-skills>" }

    for _, name in ipairs(loaded_names) do
        -- Find the skill
        local skill = nil
        for _, s in ipairs(M.available) do
            if s.name == name then
                skill = s
                break
            end
        end

        if skill then
            local skill_file = skill.path .. "/SKILL.md"
            if vim.fn.filereadable(skill_file) == 1 then
                local content = table.concat(vim.fn.readfile(skill_file), "\n")
                table.insert(lines, string.format('<skill name="%s">', name))
                table.insert(lines, content)
                table.insert(lines, "</skill>")
            end
        end
    end

    table.insert(lines, "</loaded-skills>")

    return table.concat(lines, "\n")
end

--- Configure the skills module
--- @param opts table {paths = string[]}
function M.configure(opts)
    if opts.paths then
        config.paths = opts.paths
    end
end

return M
