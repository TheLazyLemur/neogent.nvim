# Neogent Specification

> AI that thinks when you need it, executes when you don't, and stays out of your way.

## Vision

Neogent is an AI coding assistant for Neovim that respects the Unix philosophy and vim's composability. It provides two modes of interaction that work together: **Agent Mode** for planning and exploration, and **Operator Mode** for precise, targeted edits.

Unlike tools that replace your editor (Cursor) or provide shallow autocomplete (Copilot), Neogent integrates deeply with vim's grammar while maintaining full agentic capabilities when needed.

## Philosophy

- **For developers without skill issues** - Augments expertise, doesn't replace thinking
- **Unix philosophy** - Do one thing well, compose with other tools
- **Vim-native** - Operator grammar (`g=af`, `g=ip`), not a separate UI bolted on
- **Backend agnostic** - Works with any Anthropic-compatible API
- **You control the AI** - Not the other way around

## Architecture

```
neogent.nvim/
├── lua/neogent/
│   ├── init.lua      -- Setup, orchestration
│   ├── api.lua       -- Anthropic API client (streaming, SSE)
│   ├── tools.lua     -- Tool registry (read_file, search, symbols, etc.)
│   ├── ui.lua        -- Chat sidebar UI
│   └── operator.lua  -- g= vim operator
```

### Shared Infrastructure

Both modes share:
- **api.lua** - Streaming API client for any Anthropic-compatible endpoint
- **tools.lua** - Agentic tools (read_file, search_files, list_files, document_symbols, workspace_symbols)
- **AGENT.md** - Project-specific context discovery

## Two Modes

### Agent Mode (Chat)

Full conversational AI with tool use for complex, multi-step tasks.

```
:Neogent
```

**Use cases:**
- Explore unfamiliar codebase
- Plan feature implementation
- Multi-file refactoring
- Debugging with context gathering
- Generate plans for operator mode

**Capabilities:**
- Streaming responses
- Tool execution (read, search, write, run commands)
- Conversation history
- Diff view for file changes

### Operator Mode (`g=`)

Vim operator for quick, targeted edits. Treats AI as a composable text filter.

```
g=af    -- AI transform function
g=ip    -- AI transform paragraph
g==     -- AI transform current line (fill mode)
vip g=  -- Visual selection
```

**Two sub-modes:**

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Fill** | Placeholder detected (TODO, pass, _, etc.) | Auto-executes, replaces inline |
| **Transform** | Existing code | Opens scratch buffer for instruction |

**Fill Mode:**
- Detects placeholders: `TODO`, `pass`, `_`, `unimplemented!()`, `...`
- AI explores codebase if needed (reads types, searches patterns)
- Auto-applies result (no review step)
- Falls back to transform mode on failure

**Transform Mode:**
- Opens horizontal scratch buffer
- User types instruction, `:w` to send
- AI explores codebase, then outputs code
- Review in buffer, `<C-CR>` to apply, `<C-d>` for diff, `q` to cancel

## Integrated Workflow: Plan → Execute

The two modes form a complete workflow:

```
┌─────────────────────────────────────────────────────────┐
│  1. PLAN (Agent Mode)                                   │
│     :Neogent                                            │
│     "Plan how to add authentication to this app"        │
│     → Agent explores codebase                           │
│     → Generates plan, saves to AGENT.md                 │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  2. EXECUTE (Operator Mode)                             │
│     g=af on each function                               │
│     → Operator reads AGENT.md for context               │
│     → Knows the plan, fills intelligently               │
│     → Quick targeted edits, full control                │
└─────────────────────────────────────────────────────────┘
```

**The synergy:** Chat does the thinking, operator does the doing.

## Agentic Capabilities

Both modes can execute tools before generating code:

```lua
read_only_tools = {
    "read_file",        -- Read file contents
    "search_files",     -- Ripgrep search
    "list_files",       -- Directory listing
    "document_symbols", -- LSP symbols in file
    "workspace_symbols" -- LSP workspace search
}
```

**Example flow (Fill mode on ambiguous placeholder):**
1. User: `g==` on `TODO` inside `func newRouter() *Router`
2. Agent: calls `search_files` for "Router" type definition
3. Agent: calls `read_file` on router.go to understand fields
4. Agent: calls `document_symbols` to see available methods
5. Agent: generates correct implementation
6. Auto-applied to buffer

## AGENT.md Context

Both modes discover project context by searching upward for `AGENT.md`:

```
project/
├── AGENT.md           ← Project-wide context
├── src/
│   ├── AGENT.md       ← Module-specific context (found first)
│   └── auth/
│       └── handler.go ← Current file
```

**AGENT.md contents:**
- Project conventions
- Architecture decisions
- Generated plans from agent mode
- Domain-specific knowledge

## Configuration

```lua
require("neogent").setup({
    -- API
    base_url = "https://api.anthropic.com/v1/messages",
    api_key = os.getenv("ANTHROPIC_API_KEY"),
    model = "claude-sonnet-4-20250514",
    max_tokens = 4096,

    -- Agent mode
    follow_agent = true,        -- Open files agent reads
    inject_diagnostics = false, -- Include LSP errors in context

    -- Operator mode
    operator = {
        timeout_ms = 60000,
        max_tool_iterations = 10,
        keymap = "g=",          -- Configurable
    },
})
```

## Differentiators

| Feature | Neogent | Copilot | Cursor | 99 |
|---------|---------|---------|--------|-----|
| Full agent chat | ✅ | ❌ | ✅ | ❌ |
| Vim operator | ✅ `g=` | ❌ | ❌ | Partial |
| Plan → Execute flow | ✅ | ❌ | ❌ | ❌ |
| Backend agnostic | ✅ | ❌ | ❌ | ❌ (OpenCode) |
| Stays in Neovim | ✅ | ✅ | ❌ | ✅ |
| Tool use / agentic | ✅ | ❌ | ✅ | ✅ |

## Target Users

Developers who:
- Live in Neovim and won't leave
- Have 10+ years of vim muscle memory
- Want AI to augment, not replace, their skills
- Need both strategic planning and tactical execution
- Value control over convenience

## Non-Goals

- Autocomplete / ghost text (use Copilot for that)
- Replacing your editor
- Hand-holding for beginners
- Vendor lock-in

## Summary

Neogent provides a unique AI experience:

1. **Think** - Full agent mode for planning and exploration
2. **Do** - Vim operator for precise execution
3. **Flow** - Plans feed into operator context
4. **Freedom** - Any Anthropic-compatible backend

*"Plan with the agent, execute with the operator."*
