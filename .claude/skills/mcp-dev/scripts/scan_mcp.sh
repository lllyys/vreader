#!/usr/bin/env bash
set -euo pipefail

rg -n "mcp" src src-tauri dev-docs || true
