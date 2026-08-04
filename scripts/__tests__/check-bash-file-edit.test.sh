#!/usr/bin/env bash
# Contract tests for .claude/hooks/check_bash_file_edit.sh — the PreToolUse
# guard that stops a Bash command from mutating a repo-tracked file in place.
#
# Why the hook exists: the two tracker guards (check_terminal_status_evidence,
# check_gh_issue_mirror) are registered ONLY on the Edit|Write|MultiEdit
# matcher, so `cat > docs/features.md <<EOF` bypasses both. Rule 55 forbids
# Bash file edits; on 2026-08-04 two separately-briefed agents did it anyway.
#
# Everything runs against a TEMPORARY fixture repo (a dir with a `.git`
# marker), never the real checkout, so the verdict never moves when the real
# tracker files change. The blocked/allowed split is the whole contract:
# a false block on a routine command is worse than a missed exotic write.
#
# Run: bash scripts/__tests__/check-bash-file-edit.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/check_bash_file_edit.sh"
fails=0

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

echo "== check_bash_file_edit =="

if [ ! -f "$HOOK" ]; then
    echo "FAIL — $HOOK missing"; echo "1 FAILURE(S)"; exit 1
fi
if ! bash -n "$HOOK" 2>/dev/null; then
    echo "FAIL — $HOOK is not valid bash"; echo "1 FAILURE(S)"; exit 1
fi

FIX="$(mktemp -d -t bash-edit-fixture.XXXXXX)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/.git" "$FIX/docs" "$FIX/dev-docs" "$FIX/vreader/Services" \
         "$FIX/.claude/cron-logs" "$FIX/build" "$FIX/android/app/build" \
         "$FIX/.reports" "$FIX/scripts"
: > "$FIX/docs/features.md"
: > "$FIX/docs/bugs.md"

OUT=""; RC=0
run() { # <command>  — payload cwd is the fixture repo
    OUT="$(python3 -c '
import json, sys
print(json.dumps({"tool_name": "Bash", "cwd": sys.argv[1],
                  "tool_input": {"command": sys.argv[2]}}))' "$FIX" "$1" \
        | env -u VREADER_ALLOW_BASH_EDIT bash "$HOOK" 2>&1)"
    RC=$?
}

blocks() { # <label> <command> <path-that-must-be-named>
    run "$2"
    if [ "$RC" -ne 2 ]; then
        fail "$1: expected exit 2, got $RC"
    elif ! grep -q "BLOCKED" <<<"$OUT"; then
        fail "$1: exit 2 but no BLOCKED banner"
    elif ! grep -q -- "$3" <<<"$OUT"; then
        fail "$1: block message does not name '$3' — got: $(head -6 <<<"$OUT" | tr '\n' ' ')"
    else
        ok "$1"
    fi
}

allows() { # <label> <command>
    run "$2"
    if [ "$RC" -eq 0 ]; then
        ok "$1"
    else
        fail "$1: expected exit 0, got $RC — $(grep -E '^  - ' <<<"$OUT" | tr '\n' ' ')"
    fi
}

# --- BLOCKED: the constructs rule 55 forbids --------------------------------

blocks "heredoc into docs/features.md is blocked" \
"cat > docs/features.md <<'EOF'
| 5 | thing | Reader | High | VERIFIED | done |
EOF" "docs/features.md"

blocks "sed -i on a tracked file is blocked" \
    "sed -i '' 's/TODO/FIXED/' docs/bugs.md" "docs/bugs.md"

blocks "perl -i on a tracked file is blocked" \
    "perl -pi -e 's/a/b/' docs/bugs.md" "docs/bugs.md"

blocks "tee to a tracked file is blocked" \
    "echo x | tee docs/features.md" "docs/features.md"

blocks "tee -a to a tracked file is blocked" \
    "echo x | tee -a dev-docs/notes.md" "dev-docs/notes.md"

blocks "python3 -c write to a tracked file is blocked" \
    "python3 -c 'open(\"docs/features.md\",\"w\").write(\"rows\")'" "docs/features.md"

blocks "python3 - <<EOF write is blocked" \
"python3 - <<'PY'
open('docs/bugs.md','a').write('| 9 | x |')
PY" "docs/bugs.md"

blocks "node -e writeFileSync is blocked" \
    "node -e 'require(\"fs\").writeFileSync(\"docs/features.md\",\"y\")'" "docs/features.md"

blocks "append redirect to source is blocked" \
    "printf 'x' >> vreader/Services/Foo.swift" "vreader/Services/Foo.swift"

blocks "absolute path into the repo is blocked" \
"cat > $FIX/docs/features.md <<EOF
x
EOF" "docs/features.md"

blocks "awk redirect to a tracked file is blocked" \
    "awk '{print}' /tmp/in > docs/bugs.md" "docs/bugs.md"

blocks "block message cites rule 55 and the Edit tools" \
    "sed -i '' 's/a/b/' docs/features.md" "55-lane-dispatch.md"

blocks "block message names the construct" \
    "echo x | tee docs/bugs.md" 'via `tee`'

# --- ALLOWED: the routine traffic a false positive would break --------------

allows "scratchpad heredoc" \
"cat > /private/tmp/claude-501/proj/session/scratchpad/plan.md <<'EOF'
notes
EOF"

allows "/tmp redirect" "echo hi > /tmp/out.txt"

allows "cron-log append" \
    'echo "$(date +%F) verify FIRED" >> .claude/cron-logs/verify.log'

allows "git commit -F - heredoc" \
"git commit -F - <<'EOF'
fix: thing
EOF"

allows "git checkout of a tracked file" "git checkout docs/features.md"
allows "gh pr comment" "gh pr comment 12 --body 'see docs/features.md'"
allows "xcodegen generate" "xcodegen generate"

allows "read-only grep pipeline" \
    "grep -rn 'VERIFIED' docs/features.md | sed 's/^/> /' | head -5"

allows "read-only sed -n on a tracked file" "sed -n '1,20p' docs/bugs.md"
allows "cat of a tracked file into a pipe" "cat docs/bugs.md | awk '{print}' | wc -l"

allows "write under build/" "echo done > build/marker"
allows "write under android/**/build/" "echo x > android/app/build/gen.kt"
allows "write under .reports/" "./gradlew test > .reports/gradle.output 2>&1"
allows "*.log under a tracked dir" "echo x > scripts/run.log"

allows "fd duplication is not a file write" \
    "scripts/run-tests.sh vreaderTests/FooTests > /tmp/t.out 2>&1"

allows "unresolvable \$VAR target" 'echo x > "$LOG"'

allows "read-only open() in python3" \
    "python3 -c 'print(open(\"docs/features.md\").read()[:40])'"

allows "interpreter writing outside the repo" \
    "python3 -c 'open(\"/tmp/o.json\",\"w\").write(x)' < docs/bugs.md"

# --- Regression: variable-bound path in a multi-line interpreter body -------
# A real bypass, found 2026-08-04 by replaying an agent's `python3 - <<PY`
# heredoc. The path was bound to `p` ~180 chars above `open(p,"w")`, which put
# it outside the 120-char literal window — so the write was invisible. The
# longer the script, the more reliably it evaded. Path-position identifiers are
# now resolved against simple `name = "literal"` bindings anywhere in the body.
blocks "python3 heredoc writing via a variable-bound path is blocked" \
    'python3 - <<PY
import re
p="dev-docs/plans/some-plan.md"
s=open(p).read()
s=s.replace("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
open(p,"w").write(s)
PY' "dev-docs/plans/some-plan.md"

blocks "Path(var).write_text is blocked" \
    'python3 - <<PY
from pathlib import Path
p="docs/bugs.md"
Path(p).write_text("x")
PY' "docs/bugs.md"

# The path POSITION is what decides where bytes land — a repo path merely
# passed as CONTENT must not be mistaken for the target.
allows "variable-bound /tmp target, repo path only as content" \
    'python3 - <<PY
out="/tmp/scratch-only-target.txt"
open(out,"w").write("plain content with no slashes")
PY'

allows "heredoc BODY mentioning a write to a tracked file" \
"cat > /tmp/rule.md <<'EOF'
Never do: sed -i '' 's/a/b/' docs/features.md
Never do: cat > docs/bugs.md <<INNER
EOF"

allows "untracked path at repo root" "echo x > notes-scratch.md"

# Quoted mentions of a write are text, not a write. This class bit live
# during development: a test driver whose ARGUMENT contained the heredoc
# literal was blocked. Routine grep/echo traffic must survive.
allows "grep for a redirect pattern" \
    "grep -rn '> docs/features.md' .claude/rules/ | head"
allows "echo mentioning a forbidden write" \
    "echo 'never run: cat > docs/bugs.md or sed -i docs/bugs.md'"
allows "quoted tee mention" "echo 'do not tee docs/features.md'"

# --- escape hatch + non-Bash tools ------------------------------------------

run "VREADER_ALLOW_BASH_EDIT=1 sed -i '' 's/a/b/' docs/features.md"
if [ "$RC" -eq 0 ] && grep -q "WARNING" <<<"$OUT"; then
    ok "inline VREADER_ALLOW_BASH_EDIT=1 bypasses with a warning"
else
    fail "inline escape hatch wrong (rc=$RC out='$(head -2 <<<"$OUT")')"
fi

ENVOUT="$(python3 -c '
import json, sys
print(json.dumps({"tool_name": "Bash", "cwd": sys.argv[1],
                  "tool_input": {"command": sys.argv[2]}}))' \
    "$FIX" "cat > docs/features.md <<EOF
x
EOF" | VREADER_ALLOW_BASH_EDIT=1 bash "$HOOK" 2>&1)"
ENVRC=$?
if [ "$ENVRC" -eq 0 ] && grep -q "WARNING" <<<"$ENVOUT"; then
    ok "env VREADER_ALLOW_BASH_EDIT=1 bypasses with a warning"
else
    fail "env escape hatch wrong (rc=$ENVRC out='$(head -2 <<<"$ENVOUT")')"
fi

NB="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/docs/features.md"}}' "$FIX" \
      | bash "$HOOK" 2>&1)"; NBRC=$?
if [ "$NBRC" -eq 0 ] && [ -z "$NB" ]; then
    ok "non-Bash tool call passes through untouched"
else
    fail "non-Bash tool mishandled (rc=$NBRC out='$NB')"
fi

EMPTY="$(printf '{"tool_name":"Bash","tool_input":{"command":""}}' | bash "$HOOK" 2>&1)"; ERC=$?
if [ "$ERC" -eq 0 ]; then ok "empty command allowed"; else fail "empty command exited $ERC"; fi

MALFORMED="$(printf 'not json' | bash "$HOOK" 2>&1)"; MRC=$?
if [ "$MRC" -eq 0 ]; then
    ok "malformed payload fails open"
else
    fail "malformed payload exited $MRC (must fail open)"
fi

# --- registration: the hook is wired on the Bash matcher --------------------

if python3 -c '
import json, sys
cfg = json.load(open(sys.argv[1]))
pre = cfg["hooks"]["PreToolUse"]
bash_entries = [e for e in pre if e.get("matcher") == "Bash"]
assert bash_entries, "no Bash matcher in PreToolUse"
cmds = " ".join(h["command"] for e in bash_entries for h in e["hooks"])
assert "check_bash_file_edit.sh" in cmds, cmds
assert "check_codex_audit_artifact.sh" in cmds, "existing Bash hook lost"
' "$ROOT/.claude/settings.json" 2>/dev/null; then
    ok "registered as a PreToolUse Bash hook in .claude/settings.json"
else
    fail "not registered on the Bash matcher in .claude/settings.json"
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
