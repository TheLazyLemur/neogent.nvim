-- neogent.nvim - Agentic AI assistant for Neovim
-- Autoload file

if vim.g.loaded_neogent then
    return
end
vim.g.loaded_neogent = true

vim.api.nvim_create_user_command("Neogent", function()
    require("neogent").toggle()
end, { desc = "Toggle Neogent" })

vim.api.nvim_create_user_command("NeogentOpen", function()
    require("neogent").open()
end, { desc = "Open Neogent" })

vim.api.nvim_create_user_command("NeogentClose", function()
    require("neogent").close()
end, { desc = "Close Neogent" })

vim.api.nvim_create_user_command("NeogentClear", function()
    require("neogent").clear()
end, { desc = "Clear Neogent conversation" })
