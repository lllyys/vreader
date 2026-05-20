#!/bin/bash
# Rebuilds foliate-bundle.js from foliate-host.js using esbuild.
# Run from the JS directory: cd vreader/Services/Foliate/JS && ./build-bundle.sh
#
# Reproducibility: esbuild output is byte-stable for a given input + version.
# This script uses the LOCAL esbuild pinned by ./package.json (currently
# 0.28.0). The local pin closes the determinism gap that arose with the
# previous `npx esbuild` resolution — `npx` resolved whatever esbuild the
# current user had cached, which could drift across machines and produce
# different bundle bytes from the same source.
#
# First-time setup: run `npm ci` in this directory once to materialize
# `node_modules/`. The script will bootstrap that for you if the bin is
# missing — using `npm ci` (lockfile-enforced) so the bootstrap never
# rewrites package-lock.json. `node_modules/` is gitignored; only
# package.json + package-lock.json are checked in. Regenerating the
# lockfile (e.g. when bumping esbuild) is an explicit maintainer
# action: `npm install <pkg>@<ver>` then commit the lockfile diff.
#
# Verifying parity: the Swift test `FoliatePaginatorScrollBoundaryTests`
# grep-checks paginator.js (source) against foliate-bundle.js (built). If
# you edit one without rebuilding the other, that test fails.

set -euo pipefail
cd "$(dirname "$0")"

ESBUILD_BIN="./node_modules/.bin/esbuild"

# Node version preflight — esbuild 0.28 requires node >=18 (declared in
# package.json's `engines`). Fail early with a clear message rather than
# letting npm/esbuild emit a cryptic error.
if command -v node >/dev/null 2>&1; then
    node_major=$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)
    if [ "$node_major" -lt 18 ]; then
        echo "ERROR: node >=18 required (found $(node --version)). Update node, then re-run." >&2
        exit 1
    fi
else
    echo "ERROR: node not on PATH. Install node >=18 and re-run." >&2
    exit 1
fi

# Bootstrap node_modules if missing — uses `npm ci` (lockfile-enforced)
# so the bootstrap never rewrites package-lock.json. Lockfile drift would
# weaken the determinism guarantee this script promises.
if [ ! -x "$ESBUILD_BIN" ]; then
    echo "Local esbuild missing; running npm ci..." >&2
    npm ci --no-audit --no-fund --silent
fi

actual_esbuild_version=$("$ESBUILD_BIN" --version)

# Create stubs for unsupported formats
echo 'export const makeComicBook = () => { throw new Error("not supported") }' > comic-book.js
echo 'export const makeFB2 = () => { throw new Error("not supported") }' > fb2.js
echo 'export const makePDF = () => { throw new Error("not supported") }' > pdf.js

# Bundle with the pinned local esbuild
"$ESBUILD_BIN" foliate-host.js --bundle --format=iife --global-name=FoliateHost --outfile=foliate-bundle.js

# Cleanup stubs
rm -f comic-book.js fb2.js pdf.js

echo "Built foliate-bundle.js ($(wc -c < foliate-bundle.js | tr -d ' ') bytes) with esbuild ${actual_esbuild_version}"
