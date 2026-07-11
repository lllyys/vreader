#!/usr/bin/env bash
# canon-staleness.sh — detect drift between the bureau canon's verified
# dossiers and the code they were verified against.
#
# The compile pipeline records, for every `status: verified` dossier, a
# sha256 of each artifact it was checked against (canon/_verify.json, built
# by the compile step). This script re-hashes those artifacts and flags any
# page whose evidence no longer matches the live repo — i.e. the code changed
# under a dossier and its `verified` claim may now be stale.
#
# This is the "keep the canon fresh" detector: `verified` is auto-checked but
# not human-approved, and `stale` is a legal AI-writable trust tier, so a page
# whose evidence drifted is demoted to `stale` (never touched again until a
# fresh compile/verify pass re-confirms it). Never touches `canonical`
# (human-owned) or `proposed`/`stale` pages.
#
# Usage:
#   scripts/canon-staleness.sh            # report only (read-only)
#   scripts/canon-staleness.sh --apply    # also flip drifted pages verified -> stale
#
# Env (for tests): CANON_DIR (default: canon), VERIFY_JSON (default:
#   $CANON_DIR/_verify.json).
#
# Exit: 0 = clean (no drift), 3 = drift found, 2 = usage/environment error.
# Emits one machine-parseable final line: `CANON-STALENESS RESULT: ...`.

set -uo pipefail

APPLY=0
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        -h|--help)
            sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "canon-staleness: unknown argument: $arg" >&2
           echo "CANON-STALENESS RESULT: ERROR (bad usage)"; exit 2 ;;
    esac
done

# CANON_ROOT overridable so tests can point artifact resolution at a fixture
# tree; defaults to the repo root inferred from this script's location.
REPO_ROOT="${CANON_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CANON_DIR="${CANON_DIR:-$REPO_ROOT/canon}"
VERIFY_JSON="${VERIFY_JSON:-$CANON_DIR/_verify.json}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "canon-staleness: python3 not found" >&2
    echo "CANON-STALENESS RESULT: ERROR (no python3)"; exit 2
fi
if [ ! -f "$VERIFY_JSON" ]; then
    echo "canon-staleness: verify ledger not found: $VERIFY_JSON" >&2
    echo "CANON-STALENESS RESULT: ERROR (no _verify.json)"; exit 2
fi

CANON_DIR="$CANON_DIR" VERIFY_JSON="$VERIFY_JSON" REPO_ROOT="$REPO_ROOT" \
APPLY="$APPLY" python3 - <<'PY'
import json, os, re, sys, hashlib

canon_dir  = os.environ["CANON_DIR"]
verify_p   = os.environ["VERIFY_JSON"]
repo_root  = os.environ["REPO_ROOT"]
apply      = os.environ["APPLY"] == "1"

try:
    verify = json.load(open(verify_p, encoding="utf-8"))
except Exception as e:
    print(f"canon-staleness: cannot parse {verify_p}: {e}", file=sys.stderr)
    print("CANON-STALENESS RESULT: ERROR (bad _verify.json)")
    sys.exit(2)

# Index every dossier by its frontmatter title -> (path, current status).
title_re  = re.compile(r'^title:\s*(.+?)\s*$', re.MULTILINE)
status_re = re.compile(r'^status:\s*(\S+)', re.MULTILINE)
by_title = {}
for root, _dirs, files in os.walk(canon_dir):
    for fn in files:
        if not fn.endswith(".md"):
            continue
        fp = os.path.join(root, fn)
        try:
            head = open(fp, encoding="utf-8", errors="replace").read(4096)
        except OSError:
            continue
        mt = title_re.search(head)
        ms = status_re.search(head)
        if mt:
            by_title[mt.group(1).strip()] = (fp, ms.group(1).strip() if ms else None)

def sha256(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None

# High-churn provenance files: almost every dossier cites these for bug/feature
# cross-references, and they change on essentially every merge. Drift here does
# NOT invalidate a dossier's claims about the CODE, so it is advisory only —
# never a demotion trigger. Everything else (source, rules, architecture doc,
# contracts, README, dev-docs) is substantive: drift demotes.
SOFT = {
    "docs/features.md",
    "docs/bugs.md",
    "docs/tasks.md",
    "archive/bugs-history.md",
}

stale = []       # (title, path, status, hard_reasons) — real code drift
soft_only = []   # (title, [soft_reasons]) — drifted only on provenance files
orphaned = []    # titles in _verify.json with no matching dossier
for title, entry in sorted(verify.items()):
    hit = by_title.get(title)
    if hit is None:
        orphaned.append(title)
        continue
    path, status = hit
    hard, soft = [], []
    for chk in entry.get("checks", []):
        art = chk.get("artifact")
        want = chk.get("hash")
        if not art or not want:
            continue
        got = sha256(os.path.join(repo_root, art))
        if got is None:
            (soft if art in SOFT else hard).append(f"missing: {art}")
        elif got != want:
            (soft if art in SOFT else hard).append(f"changed: {art}")
    if hard:
        stale.append((title, path, status, hard))
    elif soft:
        soft_only.append((title, soft))

# Report.
for title in orphaned:
    print(f"ORPHAN   {title}  (in _verify.json but no dossier with that title)")
flipped = 0
for title, path, status, reasons in stale:
    rel = os.path.relpath(path, repo_root)
    shown = reasons[:6]
    extra = f" (+{len(reasons)-6} more)" if len(reasons) > 6 else ""
    print(f"STALE    {title}")
    print(f"         {rel}  [{len(reasons)} artifact(s) drifted]{extra}")
    for r in shown:
        print(f"           - {r}")
    if apply and status == "verified":
        # Re-read live to avoid racing a concurrent human edit; only flip a
        # page that is STILL verified.
        txt = open(path, encoding="utf-8").read()
        m = re.search(r'^status:\s*verified\s*$', txt, re.MULTILINE)
        if m:
            txt2 = txt[:m.start()] + "status: stale" + txt[m.end():]
            # Add a one-line marker after the frontmatter's closing --- if not
            # already present, so a reader knows why it went stale.
            marker = "**Stale.** verification evidence drifted; re-run the compile/verify pass."
            if "**Stale.**" not in txt2:
                fm_end = txt2.find("\n---", 3)
                if fm_end != -1:
                    insert = txt2.find("\n", fm_end + 1)
                    # place the marker right after the first blank line past frontmatter
                    body_nl = txt2.find("\n\n", insert if insert != -1 else fm_end)
                    if body_nl != -1:
                        txt2 = txt2[:body_nl+2] + marker + "\n\n" + txt2[body_nl+2:]
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(txt2)
            os.replace(tmp, path)
            flipped += 1
            print(f"         -> demoted to status: stale")

for title, soft in soft_only:
    print(f"ADVISORY {title}  (only provenance files drifted: {', '.join(soft[:3])}"
          + (f", +{len(soft)-3} more" if len(soft) > 3 else "") + ")")

n = len(stale)
advisories = len(soft_only) + len(orphaned)
if apply:
    print(f"canon-staleness: {flipped} page(s) demoted verified -> stale")
if n == 0:
    tail = f" ({advisories} advisory)" if advisories else ""
    print(f"CANON-STALENESS RESULT: CLEAN{tail}")
    sys.exit(0)
tail = f" ({advisories} advisory)" if advisories else ""
print(f"CANON-STALENESS RESULT: STALE {n}{tail}")
sys.exit(3)
PY
