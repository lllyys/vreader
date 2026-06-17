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
#   threadId: <Codex exec session id, or manual-fallback>
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

# Resolve repo root + current branch from the cwd of the `gh pr merge`
# invocation — NOT $CLAUDE_PROJECT_DIR.
#
# A worktree-isolated agent runs `gh pr merge` from its own worktree,
# but $CLAUDE_PROJECT_DIR points at the primary checkout. Keying off it
# would read a sibling worktree's branch (and its audit log) and wrongly
# block or pass the merge. The PreToolUse payload's `.cwd` is the
# invocation's working directory; fall back to $(pwd), then
# $CLAUDE_PROJECT_DIR, only if it is absent or invalid.
HOOK_CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"
cd "${HOOK_CWD:-$(pwd)}" 2>/dev/null || cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || exit 0

if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$REPO_ROOT" ]]; then
    # Not inside a git working tree — can't enforce, fail open.
    exit 0
fi
cd "$REPO_ROOT"

if ! BRANCH="$(git branch --show-current 2>/dev/null)" || [[ -z "$BRANCH" ]]; then
    # Detached HEAD or non-git state — can't enforce, fail open.
    exit 0
fi

# main / master: `gh pr merge #N` CAN be run from main (it merges PR #N's
# feature branch, not main itself). Blanket-skipping here is a fail-OPEN —
# a code PR merged that way would bypass Gate 4 (bug #353). Instead resolve
# the PR's head branch + changed files from the command via `gh` and enforce
# against THOSE; fail CLOSED if the PR can't be resolved.
PR_FILES_OVERRIDE=""
case "$BRANCH" in
    main|master)
        # `|| true`: grep exits 1 on no match, which would trip `set -e` before
        # the fail-closed `exit 2` below.
        PR_NUM="$(printf '%s' "$COMMAND" | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+#?[0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
        if [[ -z "$PR_NUM" ]] || ! command -v gh >/dev/null 2>&1; then
            echo "BLOCKED: 'gh pr merge' from $BRANCH without a resolvable PR number (or gh unavailable) — cannot verify the Codex Gate-4 audit. Merge from the PR's feature branch, or pass the PR number explicitly." >&2
            exit 2
        fi
        BRANCH="$(gh pr view "$PR_NUM" --json headRefName -q .headRefName 2>/dev/null || true)"
        PR_FILES_OVERRIDE="$(gh pr view "$PR_NUM" --json files -q '.files[].path' 2>/dev/null || true)"
        if [[ -z "$BRANCH" || -z "$PR_FILES_OVERRIDE" ]]; then
            echo "BLOCKED: could not resolve PR #$PR_NUM head branch / changed files via gh — failing CLOSED on the Codex Gate-4 audit (a code PR must not merge from main without verification)." >&2
            exit 2
        fi
        ;;
esac

# Detect docs/meta-only PRs that don't need a code audit.
#
# Diff against origin/main with a three-dot range (merge-base...HEAD),
# NOT the local `main` ref. The local `main` ref is shared by every
# worktree under one repo and is routinely stale — a two-dot
# `git diff main..HEAD` from a worktree picks up Swift files from
# OTHER PRs that merged into main after this branch forked, wrongly
# flagging a docs-only PR as Swift-touching. `origin/main...HEAD`
# (after a best-effort fetch) counts only the files THIS branch
# changed since it diverged from origin/main.
#
# Fail open if the diff itself fails (offline, no upstream main, etc.).
#
# Feature #103 WI-1 (Android Phase 0): code-path classification is now
# factored into `.claude/hooks/lib/code-paths.sh` and matches by ROOT —
# iOS (vreader/, vreaderTests/), Android/Kotlin (android/, spikes/,
# buildSrc/, Gradle / manifest / res / *.kt[s]), and the shared
# `contracts/` surface — so an `android/`/`contracts/` PR can no longer
# bypass this gate as docs-only. Contract pinned by
# `.claude/hooks/__tests__/check_codex_audit_artifact.test.sh`.
CODE_TOUCHED="no"
# shellcheck source=.claude/hooks/lib/code-paths.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/.claude/hooks/lib/code-paths.sh" 2>/dev/null || true
DIFF_OK="yes"
if [[ -n "$PR_FILES_OVERRIDE" ]]; then
    # main-branch merge: classify the PR's actual changed files (from gh).
    CHANGED="$PR_FILES_OVERRIDE"
else
    git fetch origin main --quiet 2>/dev/null || true
    DIFF_BASE="origin/main"
    git rev-parse --verify --quiet origin/main >/dev/null 2>&1 || DIFF_BASE="main"
    CHANGED="$(git diff "${DIFF_BASE}...HEAD" --name-only 2>/dev/null)" || DIFF_OK="no"
fi
if [[ "$DIFF_OK" == "no" ]]; then
    # The diff itself failed (offline mid-op, corrupt ref, etc.) — fail CLOSED
    # (bug #353 defect 2): require an audit rather than let a code PR through on
    # an unknown changeset, consistent with the missing-classifier branch below.
    CODE_TOUCHED="yes"
elif declare -F code_paths_touched >/dev/null 2>&1; then
    if printf '%s\n' "$CHANGED" | code_paths_touched; then
        CODE_TOUCHED="yes"
    fi
else
    # Classifier lib missing/unloadable (corrupt/partial checkout) —
    # fail CLOSED: require an audit rather than risk letting a code PR
    # bypass the gate. Duplicating the classifier inline would only
    # risk drift; refusing to skip is the safe default.
    CODE_TOUCHED="yes"
fi
if [[ "$CODE_TOUCHED" == "no" ]]; then
    # Docs / hooks / config / rules only — audit not required.
    exit 0
fi

# Audit file path.
SAFE_BRANCH="${BRANCH//\//-}"
AUDIT_FILE="$REPO_ROOT/.claude/codex-audits/${SAFE_BRANCH}-audit.md"

if [[ ! -f "$AUDIT_FILE" ]]; then
    cat >&2 <<EOF
[codex-audit-merge-gate] BLOCKED.

Branch \`$BRANCH\` touches code paths (iOS Swift, Android/Kotlin, or the
shared contracts/ surface) but has no Codex audit log at:

  $AUDIT_FILE

Per .claude/rules/47-feature-workflow.md Gate 4 and the /fix-issue
skill's Phase 4, every PR that ships code must run through a
Codex audit loop before merge. Two ways to proceed:

  1. Run the audit. The cheap path:
        a. Run /cc-suite:audit (read-only) — or /cc-suite:audit-fix for
           the audit->fix->verify loop — against the diff vs main.
           cc-suite drives Codex via "codex exec"; capture its session id.
           Do NOT use the codex-toolkit MCP tool; it is no longer loaded.
        b. Iterate until the verdict is "ship-as-is" or
           "follow-up-recommended" (with follow-ups filed as
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

  2. If the audit is genuinely impractical (the Codex runner is down and
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
