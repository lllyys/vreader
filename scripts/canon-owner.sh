#!/usr/bin/env bash
# canon-owner.sh — resolve repo paths (or path prefixes) to the bureau-canon
# dossier(s) that document them, via canon/_coverage-ledger.json.
#
# Purpose: the /dispatch brief generator calls this with a lane's write-set
# prefixes so the generated lane brief can list the owning dossier(s) as
# read-only orientation Inputs (rule 55 lane-brief step). An implementer lane
# then reads the relevant canon page for cross-module context BEFORE editing,
# without a human hand-picking it. Read-routing, not read-forcing.
#
# Usage:
#   scripts/canon-owner.sh vreader/Services/Backup/            # a write-set prefix
#   scripts/canon-owner.sh vreader/Services/Foo.swift docs/x   # exact files/prefixes
#
# Prints one repo-relative dossier path per line (deduped, sorted), then a
# final `CANON-OWNER RESULT: <n> dossier(s)` line. Exit 0 if >=1 owner found,
# 3 if none, 2 on error.

set -uo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: canon-owner.sh <path-or-prefix>..." >&2
    echo "CANON-OWNER RESULT: ERROR (no paths)"; exit 2
fi

REPO_ROOT="${CANON_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CANON_DIR="${CANON_DIR:-$REPO_ROOT/canon}"
LEDGER="${COVERAGE_LEDGER:-$CANON_DIR/_coverage-ledger.json}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "canon-owner: python3 not found" >&2
    echo "CANON-OWNER RESULT: ERROR (no python3)"; exit 2
fi
if [ ! -f "$LEDGER" ]; then
    echo "canon-owner: coverage ledger not found: $LEDGER" >&2
    echo "CANON-OWNER RESULT: ERROR (no _coverage-ledger.json)"; exit 2
fi

CANON_DIR="$CANON_DIR" LEDGER="$LEDGER" python3 - "$@" <<'PY'
import json, os, re, sys

canon_dir = os.environ["CANON_DIR"]
ledger_p  = os.environ["LEDGER"]
inputs    = [a.rstrip("/") for a in sys.argv[1:]]

try:
    ledger = json.load(open(ledger_p, encoding="utf-8"))
except Exception as e:
    print(f"canon-owner: cannot parse {ledger_p}: {e}", file=sys.stderr)
    print("CANON-OWNER RESULT: ERROR (bad ledger)"); sys.exit(2)

# (path, dossier) pairs from per-file rows and group rows.
entries = []
for r in ledger.get("rows", []):
    if r.get("dossier"):
        entries.append((r["path"].rstrip("/"), r["dossier"]))
for g in ledger.get("groups", []):
    if g.get("dossier"):
        entries.append((g["path"].rstrip("/"), g["dossier"]))

def owners_for(query):
    q = query.rstrip("/")
    found = set()
    for path, dossier in entries:
        # exact file match, query is a prefix of an entry, or entry (a group
        # dir) is a prefix of the query.
        if path == q or path.startswith(q + "/") or q.startswith(path + "/"):
            found.add(dossier)
    return found

dossiers = set()
for q in inputs:
    dossiers |= owners_for(q)

# Map dossier title -> canon file path.
title_re = re.compile(r'^title:\s*(.+?)\s*$', re.MULTILINE)
by_title = {}
for root, _d, files in os.walk(canon_dir):
    for fn in files:
        if not fn.endswith(".md"):
            continue
        fp = os.path.join(root, fn)
        try:
            head = open(fp, encoding="utf-8", errors="replace").read(2048)
        except OSError:
            continue
        m = title_re.search(head)
        if m:
            by_title[m.group(1).strip()] = fp

repo_root = os.path.dirname(canon_dir)
paths = sorted({os.path.relpath(by_title[d], repo_root) for d in dossiers if d in by_title})
for p in paths:
    print(p)
n = len(paths)
print(f"CANON-OWNER RESULT: {n} dossier(s)")
sys.exit(0 if n else 3)
PY
