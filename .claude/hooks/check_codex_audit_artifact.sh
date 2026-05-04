#!/bin/bash
# PreToolUse hook for the Bash tool.
#
# Purpose: blocks `gh pr merge` (and equivalents) unless there's a
# Codex audit log at `.claude/codex-audits/<branch>-audit.md` for the
# current branch with a final_verdict of `ship-as-is` or
# `follow-up-recommended`. Catches the workflow gap where bug-fix PRs
# merged to main without the Gate-4 audit step from
# `.claude/rules/47-feature-workflow.md`.
#
# The audit file's required frontmatter:
#
#   ---
#   branch: <current branch name>
#   threadId: <Codex MCP thread id>
#   rounds: <integer ≥ 1>
#   final_verdict: ship-as-is | follow-up-recommended | block-recommended
#   date: YYYY-MM-DD
#   ---
#
# Exits 0 to allow, 2 (with message on stderr) to block.
#
# Escape hatch: meta-process / docs-only PRs that touch zero Swift
# files don't need an audit. The hook detects this by checking
# `git diff main..HEAD --name-only` — if nothing under
# `vreader/` or `vreaderTests/` changed, allow without an audit.
#
# Reads PreToolUse JSON from stdin.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    # Tool missing — fail open rather than block the agent.
    exit 0
fi

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // ""')"

# Match `gh pr merge` with any flags. Use a permissive regex so
# `--squash`, `--rebase`, `--auto`, `--admin`, etc. all trigger.
# Skip if the command is some other gh pr usage (view, list, comment).
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'; then
    exit 0
fi

# Resolve repo root + current branch.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$REPO_ROOT"

if ! BRANCH="$(git branch --show-current 2>/dev/null)" || [[ -z "$BRANCH" ]]; then
    # Detached HEAD or non-git state — can't enforce, fail open.
    exit 0
fi

# main / master never gets merged via `gh pr merge` from itself
# (you'd be merging some OTHER PR). Skip the check.
case "$BRANCH" in
    main|master) exit 0 ;;
esac

# Detect docs/meta-only PRs that don't need a code audit.
# Fail open if the diff command itself fails (no upstream main, etc.).
SWIFT_TOUCHED="no"
if CHANGED="$(git diff main..HEAD --name-only 2>/dev/null)"; then
    if echo "$CHANGED" | grep -qE '^(vreader/|vreaderTests/)'; then
        SWIFT_TOUCHED="yes"
    fi
fi
if [[ "$SWIFT_TOUCHED" == "no" ]]; then
    # Docs / hooks / config / rules only — audit not required.
    exit 0
fi

# Audit file path.
SAFE_BRANCH="${BRANCH//\//-}"
AUDIT_FILE="$REPO_ROOT/.claude/codex-audits/${SAFE_BRANCH}-audit.md"

if [[ ! -f "$AUDIT_FILE" ]]; then
    cat >&2 <<EOF
[codex-audit-merge-gate] BLOCKED.

Branch \`$BRANCH\` touches Swift files but has no Codex audit log at:

  $AUDIT_FILE

Per .claude/rules/47-feature-workflow.md Gate 4 and the /fix-issue
skill's Phase 4, every PR that ships Swift code must run through a
Codex audit loop before merge. Two ways to proceed:

  1. Run the audit. The cheap path:
        a. mcp__plugin_codex-toolkit_codex__codex with sandbox=read-only
           and a prompt that audits the diff vs main. Capture the
           threadId from the response.
        b. Iterate via codex-reply until the verdict is "ship-as-is"
           or "follow-up-recommended" (with follow-ups filed as
           separate bugs).
        c. Write the log to:
              $AUDIT_FILE
           with frontmatter:
              ---
              branch: $BRANCH
              threadId: <from step a>
              rounds: <count>
              final_verdict: ship-as-is | follow-up-recommended
              date: $(date +%Y-%m-%d)
              ---
        d. git add + commit the audit log alongside the fix.
        e. Retry the merge.

  2. If the audit is genuinely impractical (Codex MCP is down and
     can't be brought up), do a manual mini-audit per the
     /fix-issue skill's fallback procedure and write the same file
     with final_verdict + a "Manual audit evidence" section
     replacing the Codex transcript. The hook accepts manual logs.
EOF
    exit 2
fi

# Validate the audit file's frontmatter.
RESULT="$(AUDIT_FILE="$AUDIT_FILE" BRANCH="$BRANCH" python3 - <<'PYEOF'
import os
import re
import sys

path = os.environ["AUDIT_FILE"]
branch = os.environ["BRANCH"]

with open(path) as f:
    content = f.read()

m = re.match(r"^---\s*\n(.*?)\n---\s*\n", content, re.DOTALL)
if not m:
    print("error: missing or malformed frontmatter")
    sys.exit(0)

front = m.group(1)
fields = {}
for line in front.splitlines():
    if ":" in line:
        k, v = line.split(":", 1)
        fields[k.strip()] = v.strip()

if fields.get("branch", "") != branch:
    print(f"error: frontmatter branch={fields.get('branch','')!r} doesn't match current branch {branch!r}")
    sys.exit(0)

verdict = fields.get("final_verdict", "")
if verdict not in {"ship-as-is", "follow-up-recommended", "block-recommended"}:
    print(f"error: final_verdict={verdict!r} must be one of ship-as-is, follow-up-recommended, block-recommended")
    sys.exit(0)

if verdict == "block-recommended":
    print(f"block: final_verdict=block-recommended — Codex says don't merge")
    sys.exit(0)

print("ok")
PYEOF
)"

case "$RESULT" in
    ok)
        exit 0
        ;;
    block:*)
        cat >&2 <<EOF
[codex-audit-merge-gate] BLOCKED.

The Codex audit log at $AUDIT_FILE marks final_verdict=block-recommended.
That's a hard "do not merge." Either:

  1. Address the audit's blocking findings, run another round, update
     the verdict to ship-as-is or follow-up-recommended.
  2. Override only with explicit user authorization for an emergency
     ship — discuss with the user before bypassing this hook.

Verdict comment:
  ${RESULT#block: }
EOF
        exit 2
        ;;
    error:*)
        cat >&2 <<EOF
[codex-audit-merge-gate] BLOCKED — audit log frontmatter invalid.

  $AUDIT_FILE

Reason: ${RESULT#error: }

Required frontmatter:
  ---
  branch: $BRANCH
  threadId: <Codex thread id>
  rounds: <integer>
  final_verdict: ship-as-is | follow-up-recommended | block-recommended
  date: YYYY-MM-DD
  ---

Fix the file, retry the merge.
EOF
        exit 2
        ;;
    *)
        # Unexpected python output — fail open with a stderr warning
        # rather than block the agent on hook bugs.
        echo "[codex-audit-merge-gate] python validator returned unexpected output: $RESULT" >&2
        exit 0
        ;;
esac
