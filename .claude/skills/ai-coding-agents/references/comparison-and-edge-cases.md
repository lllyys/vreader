# CLI Comparison & Edge Cases

## Feature Comparison Matrix

| Feature | Codex CLI | Claude Code CLI |
|---------|-----------|-----------------|
| **Provider** | OpenAI | Anthropic |
| **Auth** | ChatGPT OAuth / API key | Claude Pro/Max / API key |
| **Models** | GPT-5-Codex, GPT-5, GPT-4.1 | Opus, Sonnet, Haiku |
| **Local OSS** | Yes (Ollama/LM Studio) | No |
| **Web Search** | Yes (`--search`) | Via MCP/Chrome |
| **Image Input** | Yes (`-i`) | Via file reference |
| **MCP Support** | Yes | Yes |
| **Plugins** | Via skills | Yes (marketplace) |
| **Cloud Tasks** | Yes (experimental) | Remote sessions |
| **Sandbox** | Seatbelt/Landlock | Permission modes |
| **Code Review** | `codex review` | Via prompt |
| **IDE Integration** | VS Code extension | VS Code, JetBrains |
| **Session Resume** | Yes | Yes |
| **Custom Agents** | Via AGENTS.md | `--agents` JSON |
| **Structured Output** | `--output-schema` | `--json-schema` |
| **Spending Limits** | No | `--max-budget-usd` |
| **Turn Limits** | No | `--max-turns` |
| **Shell Completions** | Yes | No (yet) |

## When to Use Which

### Use Codex CLI When:
- You have ChatGPT Plus/Pro/Enterprise
- You need web search built-in
- You want local OSS model support (Ollama)
- You need dedicated code review (`codex review`)
- You're working with cloud tasks
- You need fine-grained sandbox control
- You prefer TOML configuration

### Use Claude Code CLI When:
- You have Claude Pro/Max or Anthropic API
- You need spending/turn limits for CI
- You want plugin marketplace access
- You need custom subagent definitions
- You prefer JSON configuration
- You want IDE auto-connect
- You need structured output validation

## Edge Cases & Gotchas

### Authentication Edge Cases

**Codex:**
```bash
# API key with special characters - use stdin
echo 'sk-xxx-with-$pecial' | codex login --with-api-key

# Check if logged in (exit code 0 = logged in)
codex login status && echo "logged in" || echo "not logged in"

# Multiple accounts - not supported, logout first
codex logout && codex login
```

**Claude:**
```bash
# API key via environment (preferred for CI)
export ANTHROPIC_API_KEY="sk-ant-xxx"
claude -p "task"

# Token refresh issues
claude setup-token  # Re-authenticate

# Bedrock/Vertex auth
export CLAUDE_CODE_USE_BEDROCK=1
# Uses AWS credentials chain
```

### Path & Directory Edge Cases

**Both CLIs:**
```bash
# Paths with spaces - quote them
codex --add-dir "/path/with spaces/dir"
claude --add-dir "/path/with spaces/dir"

# Relative vs absolute paths
codex -C ./subdir          # Relative OK
codex --add-dir ../sibling # Relative OK

# Symlinks - behavior varies by OS
# Generally resolved to real path

# Non-existent directory
codex -C /nonexistent      # Error
claude --add-dir /missing  # Validation error
```

### Model Edge Cases

**Codex:**
```bash
# Model not available in plan
codex -m gpt-5 "task"  # May fail if not in subscription

# OSS model not running
codex --oss "task"  # Error if Ollama not started

# Model aliases
codex -m codex      # Resolves to gpt-5-codex
codex -m mini       # Resolves to gpt-4.1-mini
```

**Claude:**
```bash
# Model aliases
claude --model sonnet  # Latest Sonnet
claude --model opus    # Latest Opus
claude --model haiku   # Latest Haiku

# Full model name
claude --model claude-sonnet-4-5-20250929

# Fallback when overloaded
claude -p --model opus --fallback-model sonnet "task"

# Model in config but overloaded
# Use fallback or explicit model flag
```

### Session Edge Cases

**Codex:**
```bash
# Resume non-existent session
codex resume abc123  # Error: session not found

# Resume from different directory
codex resume --all  # Shows all sessions
codex resume <id>   # Works from any directory

# Session corruption
rm -rf ~/.codex/sessions/<id>  # Manually clean
```

**Claude:**
```bash
# Resume with search
claude -r "partial-name"  # Opens picker with filter

# Fork to new session
claude -r <id> --fork-session "new direction"

# Session ID format
claude --session-id "not-a-uuid"  # Error: must be valid UUID

# Disabled persistence
claude -p --no-session-persistence "task"
# Cannot resume this session
```

### MCP Edge Cases

**Both:**
```bash
# Server startup timeout
# Default ~30s, then fails

# Server crashes mid-session
# Tools become unavailable, may need restart

# Conflicting tool names
# Last registered wins, or use qualified name
```

**Codex:**
```bash
# Stdio server with interactive prompts
# Hangs - server must be non-interactive

# HTTP server without CORS
# Connection fails - server must allow origin

# OAuth token expiry
codex mcp login <server>  # Re-authenticate
```

**Claude:**
```bash
# Project-scope server not in git
# Other devs won't have it

# Headers with special characters
claude mcp add -H "Auth: Bearer token=with=equals" server url
# May need escaping

# Resetting all project choices
claude mcp reset-project-choices
```

### Input/Output Edge Cases

**Codex:**
```bash
# Very long prompt
echo "$(cat huge-file.txt)" | codex exec -
# May hit token limits - will truncate

# Binary in stdout
codex exec --json "task" > output.json
# Output is valid JSON, but content may be truncated

# Non-UTF8 input
cat binary.bin | codex exec -
# Undefined behavior
```

**Claude:**
```bash
# Stream JSON with malformed input
echo '{"bad json' | claude -p --input-format stream-json
# Parse error

# Schema validation failure
claude -p --json-schema '{"type":"number"}' "say hello"
# Output may not match, error or empty

# Large file piping
cat 10mb-log.txt | claude -p "summarize"
# Truncated to context limit
```

### Permission Edge Cases

**Codex:**
```bash
# Sandbox + network
codex -s read-only --search "web task"
# Web search may fail in strict sandbox

# Full auto in strict environment
codex --full-auto "task"
# Still respects workspace boundaries

# YOLO in production
codex --yolo "task"  # NEVER DO THIS
# Bypasses all safety, can destroy system
```

**Claude:**
```bash
# Permission mode conflicts
claude --permission-mode plan --dangerously-skip-permissions
# --dangerously-skip-permissions wins

# Tool in disallowedTools used in allowedTools
claude --allowedTools "Bash" --disallowedTools "Bash(rm:*)"
# Disallow takes precedence for pattern

# Custom permission tool failure
claude -p --permission-prompt-tool broken_tool "task"
# Falls back to deny
```

### CI/CD Edge Cases

**Codex:**
```bash
# No TTY in CI
codex exec "task"  # Works (non-interactive)
codex "task"       # May fail (expects TTY)

# Parallel jobs same API key
# Rate limiting may occur
# Use different API keys or queue

# Git not initialized
codex exec --skip-git-repo-check "task"
```

**Claude:**
```bash
# Headless environment
claude -p "task"  # Works
claude "task"     # Fails (needs TTY)

# Budget exceeded mid-task
claude -p --max-budget-usd 0.01 "complex task"
# Stops immediately, partial work may be lost

# Turn limit reached
claude -p --max-turns 1 "multi-step task"
# Only one response, task incomplete
```

### Concurrency Edge Cases

```bash
# Multiple Codex sessions same repo
# Session files may conflict
# Use different working directories

# Multiple Claude sessions same project
# Sessions are isolated
# But file edits may conflict

# Parallel tool execution
# Neither CLI parallelizes tools internally
# But multiple CLI processes can conflict

# Lock files
# Neither uses lock files
# Manual coordination needed
```

### Unicode & Encoding Edge Cases

```bash
# Unicode in prompts
codex "fix 中文 comments"  # Works
claude "fix 中文 comments"  # Works

# Unicode in file paths
codex --add-dir "./路径"   # OS-dependent
claude --add-dir "./路径"  # OS-dependent

# RTL text
# Rendering may be incorrect in terminal
# But processing is correct

# Emoji in prompts
codex "add 🚀 to readme"  # Works
claude "add 🚀 to readme" # Works
```

### Network Edge Cases

```bash
# Proxy required
export HTTP_PROXY=http://proxy:8080
export HTTPS_PROXY=http://proxy:8080
codex "task"  # Uses proxy
claude "task" # Uses proxy

# Offline mode
# Neither has true offline mode
# But cached sessions can be viewed

# VPN/firewall blocking
# API calls fail
# Check connectivity with curl

# SSL certificate issues
export NODE_TLS_REJECT_UNAUTHORIZED=0  # DANGEROUS
# Only for debugging
```

### Recovery Patterns

**After Crash:**
```bash
# Codex
codex resume --last  # Try to resume

# Claude
claude -c            # Continue last
claude -r <id>       # Specific session
```

**After Bad Edit:**
```bash
# Both: Use git
git checkout -- <file>
git stash

# Codex cloud: Apply selectively
codex cloud diff <task>  # Review first
```

**After Rate Limit:**
```bash
# Wait and retry
sleep 60 && codex exec "task"

# Or use fallback
claude -p --fallback-model haiku "task"
```

**After Auth Expiry:**
```bash
# Codex
codex logout && codex login

# Claude
claude setup-token
```

## Best Practices Summary

1. **Always work in git repos** - enables recovery
2. **Use appropriate safety modes** - start restrictive
3. **Set budget/turn limits in CI** - prevent runaway
4. **Use sessions** - don't lose work
5. **Test MCP servers** - verify before critical work
6. **Quote paths** - especially with spaces
7. **Use print mode in scripts** - consistent behavior
8. **Handle errors** - check exit codes
9. **Manage context** - compact or fresh sessions
10. **Commit checkpoints** - before major changes
