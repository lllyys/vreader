#!/bin/bash
# PreToolUse hook for the Bash tool.
#
# Purpose: blocks a Bash command that mutates a repo-TRACKED file in
# place (heredoc/redirect, `sed -i`, `tee`, an interpreter one-liner
# that opens a repo path for writing). Those writes bypass the two
# PreToolUse tracker guards — `check_terminal_status_evidence.sh` and
# `check_gh_issue_mirror.sh` — because both are registered ONLY on the
# `Edit|Write|MultiEdit` matcher. A single
# `cat > docs/features.md <<'EOF' … EOF` can therefore flip a row to
# VERIFIED with no evidence file, or add a PLANNED row with no GH
# mirror, with nothing in the way.
#
# `.claude/rules/55-lane-dispatch.md` already forbids this ("lanes …
# never edit ANY file via Bash … use Edit/Write tools, everywhere, so
# hooks fire"), and the rule binds the orchestrator too. It was
# unenforced until now: on 2026-08-04 TWO separate agents heredoc-wrote
# tracker files in one day, both self-reported it, both while
# explicitly briefed not to. When two well-briefed agents violate the
# same rule the same way, the gap is in enforcement, not discipline.
# This hook is that enforcement.
#
# Detected constructs (each must resolve to a tracked repo path):
#   - `> path` / `>> path` (incl. `cat > f <<EOF`, `printf … > f`,
#     `echo … >> f`, `awk … > f`) and `&> path`
#   - `sed -i` / `perl -i` / `ruby -i` in-place edits
#   - `tee path` / `tee -a path`
#   - `python3 -c '… open(p, "w") …'`, `python3 - <<EOF`, `node -e`,
#     `ruby -e`, `perl -e` — interpreter + a write API + a repo path
#
# Deliberately NOT blocked (false positives here would get the hook
# disabled, which is worse than no hook):
#   - anything outside the repo: the scratchpad, /tmp, $TMPDIR
#   - untracked output: `build/`, `*/build/`, `.gradle/`, `DerivedData`,
#     `node_modules/`, `.reports/`, `test-books/`, `*.log`, `*.output`
#   - `.claude/cron-logs/*.log` appends (the cron prompts do this)
#   - `git` / `gh` / `xcodegen` — rewriting tracked files IS their job
#   - read-only pipelines (`grep`, `cat f | …`, `sed` without `-i`)
#   - paths that are not under a tracked directory
#   - a QUOTED mention of a write (`grep -rn "> docs/features.md" …`,
#     `echo "never sed -i docs/bugs.md"`) — an operator inside shell
#     quotes is text, not a redirect
#   - anything whose target is unresolvable (unexpanded `$VAR`) —
#     ambiguity ALLOWS; the rule-55 discipline covers the remainder.
#
# Known residual gaps (deliberate — each would cost false positives on
# routine traffic, which is the failure mode that gets a hook disabled):
#   - a write wrapped in quotes for another shell: `bash -c "sed -i … f"`
#   - `mv` / `cp` of an untracked file OVER a tracked path
#   - a target built from an unexpanded variable other than
#     $CLAUDE_PROJECT_DIR
#   - a write into a SIBLING worktree from the main checkout (the repo
#     root is resolved from the invocation cwd, so the target reads as
#     out-of-repo)
#
# Escape hatch (documented, warns, never silent): set
# `VREADER_ALLOW_BASH_EDIT=1`, either in the hook's environment or as an
# inline prefix on the command itself:
#     VREADER_ALLOW_BASH_EDIT=1 sed -i '' 's/a/b/' docs/foo.md
# Use it only when no Edit/Write tool call can express the mutation.
#
# Speed: this runs on EVERY Bash call. Hot path is one `jq` (matching
# the sibling Bash hook) plus a pure-bash regex prefilter; `python3` is
# spawned only when the command actually contains a write construct.
# Tracked-ness is a STATIC top-level prefix check — no `git ls-files`,
# no git invocation at all.
#
# Reads PreToolUse JSON from stdin. Exits 0 to allow, 2 to block.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    # Tool missing — fail open rather than block the agent.
    exit 0
fi

# `|| echo ""` on every extraction: a malformed payload must fail OPEN
# (exit 0), not die with jq's exit code under `set -e` — a hook on the
# Bash hot path that errors noisily is a hook someone disables.
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")"
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")"
[[ -n "$COMMAND" ]] || exit 0

# Escape hatch — env var, or an inline `VREADER_ALLOW_BASH_EDIT=1` prefix
# (the hook process does not inherit the command's own assignments).
if [[ "${VREADER_ALLOW_BASH_EDIT:-}" == "1" ]] \
   || [[ "$COMMAND" == *"VREADER_ALLOW_BASH_EDIT=1"* ]]; then
    echo "[bash-file-edit-hook] WARNING: VREADER_ALLOW_BASH_EDIT=1 — Bash file-edit guard bypassed for this command. Prefer the Edit/Write tools (.claude/rules/55-lane-dispatch.md)." >&2
    exit 0
fi

# Cheap pure-bash prefilter: no redirect / tee / in-place / interpreter
# token means there is nothing to analyse. Keeps python3 off the hot path.
if [[ ! "$COMMAND" =~ ([>]|(^|[^[:alnum:]_./-])(tee|sed|gsed|perl|python|python3|node|ruby|deno|bun)([^[:alnum:]_-]|$)) ]]; then
    exit 0
fi

# cwd of the invocation (a worktree lane runs elsewhere than
# $CLAUDE_PROJECT_DIR — see check_codex_audit_artifact.sh's note).
HOOK_CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
[[ -n "$HOOK_CWD" ]] || HOOK_CWD="$(pwd)"

# Command text travels on stdin, never argv/env: a heredoc body can be
# large and env+argv share ARG_MAX (E2BIG — the same trap documented in
# check_gh_issue_mirror.sh).
FINDINGS="$(printf '%s' "$COMMAND" | HOOK_CWD="$HOOK_CWD" \
    PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}" python3 -c '
import os, re, sys

cmd = sys.stdin.read()

# ---------------------------------------------------------------- config
# Top-level tracked directories + tracked root files (static: a per-call
# `git ls-files` would be a subprocess on every Bash invocation).
TRACKED_DIRS = {
    ".claude", ".codex", ".gemini", ".github", "TestPlans", "android",
    "archive", "canon", "contracts", "dev-docs", "docs", "scripts",
    "spikes", "vreader", "vreader.xcodeproj", "vreaderTests",
    "vreaderUITests",
}
TRACKED_ROOT_FILES = {
    ".cc-suite.md", ".gitignore", "AGENTS.md", "BUREAU.md", "CLAUDE.md",
    "GEMINI.md", "README.md", "project.yml",
}
# Any path component in this set makes the target untracked build/report
# output — allowed even under a tracked dir (android/app/build/..., etc).
ALLOW_COMPONENTS = {
    "build", ".gradle", ".git", "DerivedData", "node_modules", ".reports",
    "cron-logs", "test-books", "tmp", ".tokenize", ".secrets", "logs",
}
ALLOW_EXT = {".log", ".output"}
# Tools whose whole purpose is rewriting tracked files.
ALLOW_TOOLS = {"git", "gh", "xcodegen"}

# --------------------------------------------------- heredoc body split
# Bodies are removed from the "code" text so a doc/plan being written
# cannot trip the detector with example commands in its own prose. They
# are kept separately for the interpreter-write scan (python3 - <<EOF).
HEREDOC = re.compile(r"(?<!<)<<-?\s*(?!<)([\"\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1")
lines = cmd.split("\n")
code_lines, body_lines = [], []
i = 0
while i < len(lines):
    line = lines[i]
    code_lines.append(line)
    delims = [m.group(2) for m in HEREDOC.finditer(line)]
    i += 1
    for d in delims:
        while i < len(lines) and lines[i].strip() != d:
            body_lines.append(lines[i])
            i += 1
        if i < len(lines):
            i += 1
code = "\n".join(code_lines)
full = cmd

# ------------------------------------------------------- root + cwd
def strip_quotes(tok):
    tok = tok.strip()
    while len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "\"\x27":
        tok = tok[1:-1]
    return tok

cwd = os.environ.get("HOOK_CWD") or os.getcwd()
# A leading `cd <abs> &&` retargets every relative path in the command.
m = re.match(r"\s*cd\s+(\"[^\"]*\"|\x27[^\x27]*\x27|[^\s;&|]+)\s*(?:&&|;)", cmd)
if m:
    lead = strip_quotes(m.group(1))
    if lead.startswith("/"):
        cwd = lead

root = ""
probe = os.path.normpath(cwd)
while True:
    if os.path.exists(os.path.join(probe, ".git")):
        root = probe
        break
    parent = os.path.dirname(probe)
    if parent == probe:
        break
    probe = parent
if not root:
    root = os.environ.get("PROJECT_DIR", "")
if not root:
    sys.exit(0)
root = root.rstrip("/")

# --------------------------------------------------------- classifier
def is_blocked_path(raw):
    p = strip_quotes(raw)
    if not p or p.startswith("-"):
        return None
    # Only $CLAUDE_PROJECT_DIR is resolvable; any other expansion is
    # ambiguous, and ambiguity ALLOWS.
    p = p.replace("$CLAUDE_PROJECT_DIR", root).replace("${CLAUDE_PROJECT_DIR}", root)
    if "$" in p or "`" in p or "*" in p or "?" in p:
        return None
    if p.startswith("~"):
        p = os.path.expanduser(p)
    if not p.startswith("/"):
        p = os.path.join(cwd, p)
    p = os.path.normpath(p)
    if not p.startswith(root + "/"):
        return None
    rel = p[len(root) + 1:]
    parts = rel.split("/")
    if any(part in ALLOW_COMPONENTS for part in parts):
        return None
    if os.path.splitext(rel)[1] in ALLOW_EXT:
        return None
    if parts[0] in TRACKED_DIRS and len(parts) > 1:
        return rel
    if len(parts) == 1 and rel in TRACKED_ROOT_FILES:
        return rel
    return None

def quoted_mask(s):
    """1 for every offset inside a shell quote. A `>` there is text, not a
    redirect — `grep -rn "> docs/features.md" .claude/rules/` and any command
    that merely QUOTES a write (a test fixture, a doc example) must not
    block. Trade-off: `bash -c "sed -i ... docs/x"` is missed; a false block
    on routine grep/echo traffic is the worse failure (it gets hooks
    disabled), so ambiguity ALLOWS."""
    mask = bytearray(len(s))
    q = None
    i = 0
    while i < len(s):
        c = s[i]
        if q is None:
            if c in "\"\x27":
                q = c
                mask[i] = 1
            elif c == "\\":
                i += 1
        else:
            mask[i] = 1
            if c == "\\" and q == "\"":
                if i + 1 < len(s):
                    mask[i + 1] = 1
                i += 1
            elif c == q:
                q = None
        i += 1
    return mask

def segment_tool(text, idx):
    """Command name of the pipeline segment containing offset idx."""
    start = 0
    for sep in (";", "&&", "||", "|", "\n", "(", "{"):
        j = text.rfind(sep, 0, idx)
        if j + len(sep) > start:
            start = j + len(sep)
    seg = text[start:idx]
    for tok in seg.split():
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            continue  # leading VAR=value assignment
        return os.path.basename(strip_quotes(tok))
    return ""

findings = []
seen = set()

def record(construct, raw, offset=None, text=None):
    if offset is not None and text is not None:
        if segment_tool(text, offset) in ALLOW_TOOLS:
            return
    rel = is_blocked_path(raw)
    if rel and (construct, rel) not in seen:
        seen.add((construct, rel))
        findings.append((construct, rel))

# ------------------------------------------------------- 1. redirects
norm = re.sub(r"(\d)?>&\s*(\d|-)", "  ", code)        # fd dup: 2>&1, >&-
norm = norm.replace("&>>", " >>").replace("&>", " >")  # bash both-streams
norm_q = quoted_mask(norm)
for m in re.finditer(
        r"(?<![<>&])(>>?)\s*(\"[^\"]*\"|\x27[^\x27]*\x27|[^\s;|&<>()]+)", norm):
    if norm_q[m.start()]:
        continue                                       # quoted text, not a redirect
    target = m.group(2)
    if target.startswith("("):
        continue                                       # process substitution
    label = "shell redirect `%s`" % m.group(1)
    record(label, target, m.start(), norm)

code_q = quoted_mask(code)

# ------------------------------------------------------------ 2. tee
for m in re.finditer(r"(?:^|[\s;|&(])(tee)\b([^|;&\n]*)", code):
    if code_q[m.start(1)]:
        continue
    for tok in m.group(2).split():
        if tok.startswith("-"):
            continue
        record("`tee`", tok, m.start(1), code)

# --------------------------------------------- 3. in-place stream edits
INPLACE_FLAG = re.compile(r"^--?[a-zA-Z]*i([.\x27\"].*)?$")
for m in re.finditer(r"(?:^|[\s;|&(])(sed|gsed|perl|ruby)\b([^;|&\n]*)", code):
    if code_q[m.start(1)]:
        continue
    tool, args = m.group(1), m.group(2)
    toks = args.split()
    if not any(INPLACE_FLAG.match(t) or t.startswith("--in-place") for t in toks):
        continue
    for tok in toks:
        if tok.startswith("-"):
            continue
        record("`%s -i` in-place edit" % tool, tok, m.start(1), code)

# ------------------------------------------- 4. interpreter write calls
INTERP = re.compile(r"(?:^|[\s;|&(])(python3?|node|ruby|perl|deno|bun)\b")
WRITE_API = re.compile(
    r"open\s*\([^()]*[,\s][\"\x27][rwxab+t]{1,3}[\"\x27]"
    r"|writeFileSync|appendFileSync|createWriteStream"
    r"|\.write_text\s*\(|\.write_bytes\s*\("
    r"|File\.(?:write|open)|IO\.write|fs\.writeFile|fs\.appendFile")
LITERAL = re.compile(r"([\"\x27])([^\"\x27\n]+)\1")   # paired quotes only
# Simple `name = "literal"` bindings anywhere in the interpreter body.
# Without this, a multi-line script that binds its path to a variable and
# writes to it later is invisible to the bounded window below — the longer
# the script, the more reliably it evades. Found 2026-08-04 by replaying a
# real `python3 - <<PY` heredoc whose `p = "dev-docs/plans/…"` sat ~180 chars
# above its `open(p, "w")`, i.e. outside the window.
ASSIGN = re.compile(r"(?m)^[ \t]*([A-Za-z_]\w*)[ \t]*=[ \t]*([\"\x27])([^\"\x27\n]+)\2")
BOUND = {m.group(1): m.group(3) for m in ASSIGN.finditer(full)}
IDENT = re.compile(r"\b([A-Za-z_]\w*)\b")
if INTERP.search(code):
    lang = INTERP.search(code).group(1)
    for hit in WRITE_API.finditer(full):
        if hit.group(0).startswith("open"):
            mode = re.findall(r"[\"\x27]([rwxab+t]{1,3})[\"\x27]", hit.group(0))
            if not mode or not any(c in mode[-1] for c in "wax"):
                continue                              # read-only open()
        # Bounded window around the write call — the path literal sits
        # inside it (open("p","w")) or just before it (Path("p").write_text).
        close = full.find(")", hit.end())
        end = close + 1 if 0 <= close <= hit.end() + 200 else hit.end() + 200
        window = full[max(0, hit.start() - 120):end]
        for lm in LITERAL.finditer(window):
            lit = lm.group(2)
            if "/" in lit or lit in TRACKED_ROOT_FILES:
                record("interpreter write (`%s`)" % lang, lit)
        # Resolve a bare identifier in the PATH POSITION only:
        #   open(p, "w")            -> first call argument
        #   fs.writeFileSync(p, …)  -> first call argument
        #   p.write_text(…)         -> receiver immediately before the dot
        # Deliberately NOT every identifier in the call: `open(out,"w").write(note)`
        # must stay allowed when `out` is /tmp, even though `note` holds a repo
        # path. The path position is the only one that decides where bytes land.
        seg = full[hit.start():end]
        cands = []
        firstarg = re.search(r"\(\s*([A-Za-z_]\w*)\s*[,)]", seg)
        if firstarg:
            cands.append(firstarg.group(1))
        recv = re.search(r"([A-Za-z_]\w*)\s*\.\s*write_(?:text|bytes)\s*$",
                         full[max(0, hit.start() - 80):hit.end()])
        if recv:
            cands.append(recv.group(1))
        for name in cands:
            lit = BOUND.get(name)
            if lit and ("/" in lit or lit in TRACKED_ROOT_FILES):
                record("interpreter write (`%s`, via `%s`)" % (lang, name), lit)

for construct, rel in findings[:6]:
    print("%s\t%s" % (rel, construct))
' 2>/dev/null || true)"

[[ -n "$FINDINGS" ]] || exit 0

cat >&2 <<'EOF'
[bash-file-edit-hook] BLOCKED.

This Bash command writes to repo-tracked file(s) in place:

EOF
while IFS=$'\t' read -r rel construct; do
    [[ -n "$rel" ]] || continue
    echo "  - $rel   (via $construct)" >&2
done <<< "$FINDINGS"
cat >&2 <<'EOF'

Bash-mediated writes bypass the PreToolUse tracker guards
(check_terminal_status_evidence.sh, check_gh_issue_mirror.sh) — both are
registered ONLY on the Edit|Write|MultiEdit matcher, so they never see a
heredoc, `sed -i`, or `tee`. That is how a tracker row can reach VERIFIED
with no evidence file, or land as PLANNED with no GH mirror.

Per .claude/rules/55-lane-dispatch.md ("never edit ANY file via Bash"):
make this change with the Edit / Write / MultiEdit tools instead. The rule
binds every session — orchestrator, lane, and cron alike.

If the mutation genuinely cannot be expressed as a tool call, re-run with
the documented escape hatch (it warns, it does not hide):

    VREADER_ALLOW_BASH_EDIT=1 <your command>
EOF
exit 2
