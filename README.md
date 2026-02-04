# neogent.nvim

Agentic AI assistant for Neovim with tool use capabilities.

> **Status:** Alpha (v0.0.1) - Under active development

## Features

- 🤖 **Agentic workflow** - AI can use tools autonomously to complete tasks
- 📁 **File operations** - Read, write, search, and edit files
- 🔍 **Code search** - Ripgrep integration for content search
- 🛠️ **LSP integration** - Document and workspace symbol lookup
- 💻 **Command execution** - Run shell commands with safety guardrails
- 📝 **Diff view** - Review and approve file changes before applying
- ⚡ **Streaming** - Real-time response streaming from Anthropic API

## Requirements

- Neovim 0.10+
- `curl` (for API requests)
- `rg` (ripgrep, for search)
- `ANTHROPIC_API_KEY` environment variable

## Installation

Using `vim.pack.add` (Neovim 0.10+):

```lua
vim.pack.add({ { src = "https://github.com/yourusername/neogent.nvim" } })
```

Using lazy.nvim:

```lua
{
    "yourusername/neogent.nvim",
    config = function()
        require("neogent").setup()
    end,
}
```

## Setup

```lua
require("neogent").setup({
    -- Anthropic API settings
    api_key = os.getenv("ANTHROPIC_API_KEY"),
    model = "claude-sonnet-4-20250514",
    max_tokens = 4096,

    -- Behaviour
    follow_agent = true,  -- Open files in buffer as agent reads them
})
```

## Usage

| Command | Description |
|---------|-------------|
| `:Neogent` | Toggle the Neogent UI |
| `:NeogentOpen` | Open the Neogent UI |
| `:NeogentClose` | Close the Neogent UI |
| `:NeogentClear` | Clear conversation history |

### Keymaps (in Neogent UI)

| Key | Description |
|-----|-------------|
| `<CR>` | Send message (in input buffer) |
| `q` | Close UI |
| `c` | Clear conversation |
| `i` | Focus input and enter insert mode |
| `<Tab>` | Cycle between panels |
| `<Esc>` / `<C-c>` | Cancel current request |

### Diff View (when reviewing changes)

| Key | Description |
|-----|-------------|
| `<CR>` | Accept changes |
| `q` | Reject changes |

## Available Tools

The AI agent has access to:

- `read_file` - Read file contents
- `write_file` - Create new files
- `replace_lines` - Edit existing files (with diff review)
- `search_files` - Search file contents with ripgrep
- `list_files` - Find files by glob pattern
- `run_command` - Execute shell commands
- `document_symbols` - List symbols in a file (LSP)
- `workspace_symbols` - Search symbols across workspace (LSP)

## Roadmap

- [ ] Provider abstraction (OpenAI, Ollama, etc.)
- [ ] Context injection (@buffer, @selection)
- [ ] Conversation persistence
- [ ] Slash commands / skills
- [ ] Image support

## Licence

MIT
