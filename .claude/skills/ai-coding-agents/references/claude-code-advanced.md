# Claude Code CLI Advanced Reference

## Configuration Deep Dive

### Configuration Files
```
~/.claude/settings.json          # User settings (all projects)
.claude/settings.json            # Project settings (shared)
.claude/settings.local.json      # Local settings (gitignored)
```

### Settings Hierarchy
Local > Project > User (more specific wins)

### Full Settings Example
```json
{
  "model": "claude-sonnet-4-5-20250929",
  "verbose": false,
  "theme": "dark",
  "permissions": {
    "allow": ["Bash(git:*)", "Read", "Edit"],
    "deny": ["Bash(rm -rf:*)"]
  },
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-filesystem", "/path/to/allowed"]
    }
  }
}
```

### Environment Variables
| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | API authentication |
| `CLAUDE_CODE_USE_BEDROCK` | Use AWS Bedrock |
| `CLAUDE_CODE_USE_VERTEX` | Use Google Vertex |
| `CLAUDE_CODE_DEBUG` | Enable debug logging |
| `CLAUDE_CODE_MAX_TURNS` | Default max turns |

## Print Mode Patterns

### Basic Patterns
```bash
# Simple query
claude -p "explain this function"

# With model selection
claude -p --model opus "complex analysis"

# Process file
cat code.py | claude -p "review this code"

# Multiple files
cat file1.ts file2.ts | claude -p "find inconsistencies"
```

### Output Formats
```bash
# Plain text (default)
claude -p "summarize" --output-format text

# Single JSON object
claude -p "extract data" --output-format json

# Streaming JSON (real-time)
claude -p "long task" --output-format stream-json

# With partial messages
claude -p --output-format stream-json --include-partial-messages "task"
```

### Streaming Input/Output
```bash
# Full streaming pipeline
claude -p \
  --input-format stream-json \
  --output-format stream-json \
  --include-partial-messages \
  --replay-user-messages
```

### Structured Output
```bash
# JSON Schema validation
claude -p --json-schema '{
  "type": "object",
  "properties": {
    "bugs": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "line": {"type": "integer"},
          "severity": {"enum": ["low", "medium", "high"]}
        }
      }
    }
  }
}' "find bugs in src/"
```

### Budget & Turn Limits
```bash
# Spending limit
claude -p --max-budget-usd 2.50 "expensive analysis"

# Turn limit (prevent runaway)
claude -p --max-turns 5 "quick fix"

# Combined
claude -p --max-turns 10 --max-budget-usd 5.00 "complex refactor"
```

## Session Management

### Continue vs Resume
```bash
# Continue: last conversation in current directory
claude -c
claude -c -p "check for issues"

# Resume: specific session (any directory)
claude -r "session-id"
claude -r "session-name" "continue this"
claude --resume abc123 --fork-session "try different approach"
```

### Session ID Control
```bash
# Use specific UUID
claude --session-id "550e8400-e29b-41d4-a716-446655440000" "task"

# Disable persistence
claude -p --no-session-persistence "one-off task"
```

### Remote Sessions (Experimental)
```bash
# Create web session on claude.ai
claude --remote "complex task"

# Resume web session in terminal
claude --teleport
```

## Custom Agents

### Defining Subagents
```bash
claude --agents '{
  "security-reviewer": {
    "description": "Security expert. Use proactively for auth/crypto code.",
    "prompt": "You are a security expert. Focus on: injection vulnerabilities, auth bypasses, crypto weaknesses, data exposure.",
    "tools": ["Read", "Grep", "Glob"],
    "model": "opus"
  },
  "test-writer": {
    "description": "Test specialist for generating comprehensive tests.",
    "prompt": "You write thorough tests. Cover edge cases, error paths, and boundary conditions.",
    "tools": ["Read", "Write", "Edit", "Bash"],
    "model": "sonnet"
  },
  "quick-fixer": {
    "description": "Fast fixes for simple issues.",
    "prompt": "Make minimal, focused changes. No refactoring.",
    "model": "haiku"
  }
}'
```

### Agent Fields
| Field | Required | Description |
|-------|----------|-------------|
| `description` | Yes | When to invoke (shown in Task tool) |
| `prompt` | Yes | System prompt for agent |
| `tools` | No | Available tools (inherits all if omitted) |
| `model` | No | sonnet/opus/haiku (inherits if omitted) |

### Using Agents
```bash
# Claude automatically invokes based on description
# Or force specific agent
claude --agent security-reviewer "review auth module"
```

## Custom Commands

### Project Commands
Location: `.claude/commands/<name>.md`

Example `.claude/commands/fix-issue.md`:
```markdown
Fix GitHub issue #$ARGUMENTS

Steps:
1. Fetch issue details from GitHub
2. Understand the problem
3. Locate relevant code
4. Implement fix
5. Write/update tests
6. Create commit with conventional format
```

Usage: `/project:fix-issue 1234`

### User Commands
Location: `~/.claude/commands/<name>.md`

Example `~/.claude/commands/daily-standup.md`:
```markdown
Generate daily standup report:

1. Check git log for yesterday's commits
2. List current WIP branches
3. Identify blockers from TODO comments
4. Suggest today's priorities
```

Usage: `/user:daily-standup`

### Command Arguments
- `$ARGUMENTS` - All arguments as string
- Arguments passed after command name

## MCP Server Patterns

### Transport Types
```bash
# Stdio (default) - subprocess
claude mcp add my-server -- npx @org/mcp-server

# SSE (Server-Sent Events)
claude mcp add -t sse sse-server https://api.example.com/sse

# HTTP (Streamable HTTP)
claude mcp add -t http http-server https://api.example.com/mcp
```

### Scopes
```bash
# Local (current machine, not committed)
claude mcp add -s local my-server -- cmd

# Project (committed to repo)
claude mcp add -s project shared-server -- cmd

# User (all projects for this user)
claude mcp add -s user global-server -- cmd
```

### Environment & Headers
```bash
# Environment variables
claude mcp add -e API_KEY=xxx -e DEBUG=true my-server -- cmd

# HTTP headers
claude mcp add -t http \
  -H "Authorization: Bearer token" \
  -H "X-Custom: value" \
  api-server https://api.example.com/mcp
```

### Import from Claude Desktop
```bash
# Auto-import (Mac/WSL only)
claude mcp add-from-claude-desktop
```

### Running Claude as MCP Server
```bash
# Start Claude as MCP server
claude mcp serve

# With debug
claude mcp serve --debug
```

## Permission Modes

### Available Modes
| Mode | Behavior |
|------|----------|
| `default` | Normal prompting |
| `acceptEdits` | Auto-accept file edits |
| `plan` | Read-only planning mode |
| `dontAsk` | Never prompt, fail on denied |
| `delegate` | Delegate to permission tool |
| `bypassPermissions` | Skip all (requires flag) |

### Usage
```bash
# Start in plan mode
claude --permission-mode plan "analyze architecture"

# Auto-accept edits
claude --permission-mode acceptEdits "refactor"

# Full bypass (dangerous)
claude --dangerously-skip-permissions "trusted task"

# Enable bypass as option
claude --allow-dangerously-skip-permissions --permission-mode default
```

### Permission Prompt Tool (CI/CD)
```bash
# Use MCP tool for permission decisions
claude -p --permission-prompt-tool my_auth_tool "task"
```

## Tool Configuration

### Restrict Tools
```bash
# Only specific tools
claude --tools "Bash,Read,Edit"

# Disable all tools
claude --tools ""

# Default set
claude --tools "default"
```

### Allow/Deny Lists
```bash
# Auto-approve specific patterns
claude --allowedTools "Bash(git:*)" "Read" "Grep"

# Block dangerous patterns
claude --disallowedTools "Bash(rm -rf:*)" "Bash(curl|wget:*)"
```

### Tool Pattern Syntax
```
Bash(git:*)        # All git commands
Bash(npm test:*)   # npm test with any args
Read               # All Read operations
Edit(src/**:*)     # Edit files in src/
```

## Plugin System

### Installation
```bash
# From default marketplace
claude plugin install code-review

# From specific marketplace
claude plugin install code-review@anthropic

# Project scope
claude plugin install -s project team-plugin

# User scope (default)
claude plugin install -s user my-plugin
```

### Management
```bash
# List installed
claude plugin list
claude plugin list --all  # Include disabled

# Enable/disable
claude plugin enable code-review
claude plugin disable code-review

# Update
claude plugin update code-review
claude plugin update --all

# Remove
claude plugin uninstall code-review
```

### Plugin Development
```bash
# Validate manifest
claude plugin validate ./my-plugin

# Marketplace management
claude plugin marketplace list
claude plugin marketplace add https://my-marketplace.com/manifest.json
```

## Debug & Diagnostics

### Debug Mode
```bash
# All debug output
claude --debug

# Filtered categories
claude --debug "api,mcp"
claude --debug "!statsig,!file"  # Exclude categories
```

### Doctor Command
```bash
claude doctor
```

Checks:
- Authentication status
- API connectivity
- MCP server health
- Plugin status
- Configuration validity

## Integration Patterns

### CI/CD Pipeline
```yaml
# GitHub Actions
- name: Claude Code Review
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: |
    claude -p \
      --output-format json \
      --max-turns 5 \
      --max-budget-usd 2.00 \
      "Review changes and output JSON report" > review.json
```

### Git Hooks
```bash
#!/bin/bash
# .git/hooks/pre-commit
claude -p --max-turns 2 "Check staged files for issues" || exit 1
```

### Shell Aliases
```bash
# ~/.bashrc or ~/.zshrc
alias cc="claude"
alias ccp="claude -p"
alias ccr="claude -c"  # resume
alias ccm="claude --model opus"
```

### VS Code Integration
```json
// .vscode/tasks.json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Claude Explain",
      "type": "shell",
      "command": "claude -p 'explain ${file}'",
      "problemMatcher": []
    }
  ]
}
```

## Error Handling

### Common Errors
| Error | Cause | Solution |
|-------|-------|----------|
| `Authentication failed` | Invalid/expired token | `claude setup-token` |
| `Rate limited` | Too many requests | Use `--fallback-model` |
| `Model overloaded` | High demand | Use `--fallback-model haiku` |
| `Context exceeded` | Too much content | Use `/compact` or fresh session |
| `Permission denied` | Tool blocked | Check `--allowedTools` |

### Graceful Degradation
```bash
# Auto-fallback on overload
claude -p --fallback-model haiku "task"

# Manual retry logic
claude -p "task" || claude -p --model haiku "task"
```

## Performance Tips

### Reduce Latency
```bash
# Use faster model
claude --model haiku "simple task"

# Disable persistence for one-off
claude -p --no-session-persistence "quick query"

# Limit turns
claude -p --max-turns 3 "focused task"
```

### Manage Context
```bash
# In interactive: /compact

# Fresh start for unrelated work
claude --session-id "$(uuidgen)" "new topic"
```

### Batch Operations
```bash
# Process multiple files
for f in src/*.ts; do
  claude -p "review $f" >> reviews.txt
done

# Parallel (careful with rate limits)
parallel -j2 'claude -p "review {}"' ::: src/*.ts
```
