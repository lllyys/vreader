#!/bin/bash
# Stop hook — surfaces "merged without Codex audit log" debt.
#
# Scans the last 5 merges on `main` (the typical session window) and
# warns if any merged a feature/fix branch that touched CODE (iOS Swift OR
# Android/Kotlin/contracts — via the shared `code-paths.sh` classifier,
# feature #107) without a matching `.claude/codex-audits/<branch>-audit.md`.
# Catches the "ran the workflow but skipped Gate 4" pattern at session
# end so the next session can backfill the audit if appropriate.
#
# Exits 0 always — informational only. The PreToolUse hook
# `check_codex_audit_artifact.sh` is the actual block.
#
# Reads Stop JSON from stdin per Claude Code's hook spec.

set -euo pipefail

# Bail quietly if not in a git repo (don't break unrelated sessions).
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR"
if ! git rev-parse --git-dir >/dev/null 2>&1; then exit 0; fi

# Feature #107 WI-1: classify "touched code" via the shared classifier (the
# Stop-time twin of #103's PreToolUse fix), so an `android/` / `*.kt` /
# `contracts/` PR accrues audit debt too — not just `vreader/`. Before this,
# the inline `^(vreader/|vreaderTests/)` regex false-greened every Android PR.
# Resolve the real repo root (PROJECT_DIR can be a subdir via the line-19 pwd
# fallback) and TOLERATE a load failure — this hook's contract is "exit 0
# always" (informational), so a missing/corrupt lib must not fail the Stop hook.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")"
# shellcheck source=lib/code-paths.sh
source "$REPO_ROOT/.claude/hooks/lib/code-paths.sh" 2>/dev/null || exit 0

# Find recent squash-merges on main. The default `gh pr merge --squash`
# leaves "(#N)" in the commit subject. Walk the last few commits and
# extract branch names from PR refs where possible.
DEBT=""
COUNT=0

# Look at the last 5 commits on main, grab any squash-merge headers.
while IFS=$'\t' read -r sha subject; do
    # Skip merge commits without a PR marker. GitHub's squash-merge
    # subjects end with " (#N)" — anchor to end so we don't pick up a
    # bug-ref like "fix(#115):" earlier in the subject.
    if [[ ! "$subject" =~ \(#([0-9]+)\)[[:space:]]*$ ]]; then continue; fi
    PR_NUMBER="${BASH_REMATCH[1]}"

    # Use gh to map PR number to its head branch name.
    if ! command -v gh >/dev/null 2>&1; then continue; fi
    BRANCH="$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName' 2>/dev/null || true)"
    if [[ -z "$BRANCH" ]]; then continue; fi

    # Skip main / master self-merges and dependabot etc.
    case "$BRANCH" in
        main|master|dependabot/*) continue ;;
    esac

    # Did the PR touch CODE (iOS Swift OR Android/Kotlin/contracts, via the
    # shared classifier — feature #107)? Use the parent commit's tree to
    # diff the squashed commit against. If the merge was a squash, the
    # commit's parent is the previous main HEAD.
    PARENT="$(git rev-parse "$sha^" 2>/dev/null || true)"
    if [[ -z "$PARENT" ]]; then continue; fi
    if ! git diff "$PARENT".."$sha" --name-only 2>/dev/null | code_paths_touched; then
        continue
    fi

    # Look for matching audit log.
    SAFE_BRANCH="${BRANCH//\//-}"
    AUDIT_FILE="$PROJECT_DIR/.claude/codex-audits/${SAFE_BRANCH}-audit.md"
    if [[ -f "$AUDIT_FILE" ]]; then continue; fi

    DEBT+="  - ${sha:0:7} #${PR_NUMBER} (${BRANCH})"$'\n'
    COUNT=$((COUNT + 1))
done < <(git log --format='%H%x09%s' main -5 2>/dev/null)

if [[ "$COUNT" -gt 0 ]]; then
    cat >&2 <<EOF
[codex-audit-debt-hook] Recent merges on main without audit logs:

$DEBT
These PRs touched Swift code but have no \`.claude/codex-audits/<branch>-audit.md\`.
The PreToolUse hook \`check_codex_audit_artifact.sh\` blocks new merges
without an audit, but doesn't catch ones that pre-date the hook. If
you want to backfill: read the diff, run a Codex audit on it, and
write the log under the branch name (with hyphens replacing slashes).
EOF
fi

exit 0
