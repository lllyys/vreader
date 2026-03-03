# Codex CLI Advanced Reference

## Configuration Deep Dive

### Config File Location
```
~/.codex/config.toml
```

### Full Configuration Example
```toml
# Default model
model = "gpt-5-codex"

# Approval policy: untrusted | on-failure | on-request | never
approval_policy = "on-request"

# Enable features
[features]
web_search = true
mcp = true

# Sandbox configuration
[sandbox]
mode = "workspace-write"  # read-only | workspace-write | danger-full-access
permissions = ["disk-full-read-access"]

# Shell environment
[shell_environment_policy]
inherit = "all"  # all | none | allowlist
# allowlist = ["PATH", "HOME", "USER"]

# Named profiles
[profiles.ci]
model = "gpt-4.1"
approval_policy = "never"

[profiles.review]
model = "gpt-5"
approval_policy = "on-request"

# MCP servers
[mcp_servers.my-server]
command = ["npx", "my-mcp-server"]
env = { API_KEY = "xxx" }

[mcp_servers.http-server]
url = "https://api.example.com/mcp"
bearer_token_env_var = "API_TOKEN"
```

### Config Override Syntax
```bash
# Simple value
codex -c model="gpt-5"

# Nested value (dotted path)
codex -c sandbox.mode="workspace-write"

# Array value (TOML syntax)
codex -c 'sandbox_permissions=["disk-full-read-access"]'

# Complex nested
codex -c 'shell_environment_policy.inherit=all'
```

## Exec Mode Patterns

### Pipeline Integration
```bash
# Read prompt from file
cat prompt.txt | codex exec -

# Chain with other tools
codex exec --json "analyze" | jq '.messages[-1].content'

# Save structured output
codex exec --output-schema schema.json -o result.json "generate"

# CI error handling
codex exec "fix" || echo "Codex failed" && exit 1
```

### Output Schema Validation
```json
// schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "files_changed": {
      "type": "array",
      "items": { "type": "string" }
    },
    "summary": { "type": "string" }
  },
  "required": ["files_changed", "summary"]
}
```

```bash
codex exec --output-schema schema.json "refactor and report changes"
```

### Resume Patterns
```bash
# Resume with new context
codex resume <id> "now also add tests"

# Resume in exec mode
codex exec resume <id>
codex exec resume --last
```

## Review Command Patterns

### Branch Comparison
```bash
# Current branch vs main
codex review

# Against specific base
codex review --base develop
codex review --base origin/release-2.0

# Uncommitted changes (staged + unstaged + untracked)
codex review --uncommitted

# Specific commit
codex review --commit abc123
codex review --commit HEAD~3

# With custom focus
codex review "focus on security vulnerabilities"
codex review --base main "check for breaking changes"
```

### Review in CI
```bash
#!/bin/bash
# pr-review.sh
codex review --base origin/main \
  --title "PR #${PR_NUMBER}: ${PR_TITLE}" \
  "Check for: security issues, performance regressions, missing tests"
```

## Cloud Tasks (Experimental)

### Submit and Monitor
```bash
# Submit task
TASK_ID=$(codex cloud exec "fix all bugs" --env prod-env --json | jq -r '.task_id')

# Poll status
while true; do
  STATUS=$(codex cloud status $TASK_ID --json | jq -r '.status')
  echo "Status: $STATUS"
  [ "$STATUS" = "completed" ] && break
  sleep 30
done

# Review and apply
codex cloud diff $TASK_ID
codex cloud apply $TASK_ID
```

### Environment Management
```bash
# List environments (via TUI)
codex cloud

# Target specific environment
codex cloud exec "task" --env my-env-id

# Multiple attempts for complex tasks
codex cloud exec "complex refactor" --env prod --attempts 4
```

## MCP Server Patterns

### Stdio Server with Environment
```bash
codex mcp add my-db \
  --env DATABASE_URL="postgres://..." \
  --env LOG_LEVEL="debug" \
  -- npx @my-org/db-mcp-server
```

### HTTP Server with Auth
```bash
codex mcp add github-api \
  --url https://api.github.com/mcp \
  --bearer-token-env-var GITHUB_TOKEN

# OAuth flow (for servers that support it)
codex mcp login github-api --scopes repo,workflow
```

### Verifying MCP Tools
```bash
# List all available tools from MCP
codex mcp list --json | jq '.[].tools'

# In interactive session
# Type: /mcp
```

## Sandbox Deep Dive

### macOS Seatbelt
```bash
# Basic sandbox
codex sandbox macos -- npm test

# With workspace write
codex sandbox macos --full-auto -- npm run build

# Custom config
codex sandbox macos -c 'sandbox_permissions=["network-client"]' -- curl example.com
```

### Linux Landlock
```bash
# Read-only
codex sandbox linux -- cat /etc/passwd

# With write access
codex sandbox linux --full-auto -- npm install
```

### Permission Model
| Permission | Description |
|------------|-------------|
| `disk-full-read-access` | Read any file |
| `disk-write-access` | Write to workspace |
| `network-client` | Outbound network |
| `network-server` | Listen on ports |

## Feature Flags

### List Features
```bash
codex features list
```

### Enable/Disable
```bash
# Via flag
codex --enable mcp --enable web_search "task"
codex --disable telemetry "task"

# Via config
codex -c 'features.mcp=true' "task"
```

### Common Features
| Feature | Description |
|---------|-------------|
| `mcp` | Model Context Protocol support |
| `web_search` | Web search capability |
| `telemetry` | Usage analytics |
| `experimental_tools` | Bleeding edge tools |

## Error Handling

### Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Authentication error |
| 4 | Network error |
| 5 | Sandbox violation |

### Handling in Scripts
```bash
#!/bin/bash
set -e

codex exec "task" 2>&1 | tee codex.log
EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -ne 0 ]; then
  echo "Codex failed with code $EXIT_CODE"
  cat codex.log | tail -20
  exit $EXIT_CODE
fi
```

## Performance Optimization

### Reduce Latency
```bash
# Use faster model for simple tasks
codex -m gpt-4.1-mini "simple formatting fix"

# Skip unnecessary checks
codex exec --skip-git-repo-check "standalone task"
```

### Manage Context
```bash
# In interactive session, use /compact regularly
# Or start fresh for independent tasks
codex --no-cache "new unrelated task"
```

### Parallel Execution
```bash
# Run multiple independent tasks
codex exec "fix file1.ts" &
codex exec "fix file2.ts" &
wait
```

## Integration Examples

### Git Hooks
```bash
# .git/hooks/pre-commit
#!/bin/bash
codex exec -m gpt-4.1-mini "check staged files for issues" || exit 1
```

### VS Code Task
```json
{
  "label": "Codex Review",
  "type": "shell",
  "command": "codex review --uncommitted",
  "problemMatcher": []
}
```

### GitHub Action
```yaml
name: Codex Review
on: [pull_request]
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Setup Codex
        run: npm i -g @openai/codex
      - name: Login
        run: echo "${{ secrets.OPENAI_API_KEY }}" | codex login --with-api-key
      - name: Review PR
        run: codex review --base origin/${{ github.base_ref }}
```
