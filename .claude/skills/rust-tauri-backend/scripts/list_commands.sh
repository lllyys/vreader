#!/usr/bin/env bash
set -euo pipefail

rg -n "tauri::command|invoke_handler|menu" src-tauri/src || true
