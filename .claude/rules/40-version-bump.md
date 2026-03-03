# 40 - Version Bump Procedure

When bumping the version number, **all five files must be updated together**.

## Files to Update

| File | Field | Source |
|------|-------|--------|
| `package.json` | `"version"` | Frontend/npm |
| `src-tauri/tauri.conf.json` | `"version"` | Bundle (CFBundleShortVersionString) |
| `src-tauri/Cargo.toml` | `version` | Rust (`env!("CARGO_PKG_VERSION")`) |
| `vmark-mcp-server/package.json` | `"version"` | MCP sidecar npm |
| `vmark-mcp-server/src/cli.ts` | `VERSION` | MCP sidecar health check |

## Why All Five Matter

**App version (first 3 files):**
- macOS About dialog displays version from Cargo.toml and tauri.conf.json
- If they differ, macOS shows: `Version 0.2.5 (0.3.0)` (confusing)

**MCP server version (last 2 files):**
- `--version` and `--health-check` CLI flags report version from cli.ts
- Settings panel and status dialog show version from useMcpHealthCheck.ts (reads from MCP_VERSION constant)
- Must match main app to avoid user confusion

## Bump Procedure

1. **Update all five files** with the new version:
   ```bash
   # Example: bumping to 0.4.0
   VERSION="0.4.0"

   # Main app files
   sed -i '' 's/"version": "[^"]*"/"version": "'$VERSION'"/' package.json
   sed -i '' 's/"version": "[^"]*"/"version": "'$VERSION'"/' src-tauri/tauri.conf.json
   sed -i '' 's/^version = "[^"]*"/version = "'$VERSION'"/' src-tauri/Cargo.toml

   # MCP server files
   sed -i '' 's/"version": "[^"]*"/"version": "'$VERSION'"/' vmark-mcp-server/package.json
   sed -i '' 's/const VERSION = "[^"]*"/const VERSION = "'$VERSION'"/' vmark-mcp-server/src/cli.ts
   ```

2. **Verify all match**:
   ```bash
   grep '"version"' package.json src-tauri/tauri.conf.json vmark-mcp-server/package.json
   grep '^version' src-tauri/Cargo.toml
   grep 'const VERSION' vmark-mcp-server/src/cli.ts
   ```

3. **Commit together**:
   ```bash
   git add package.json src-tauri/tauri.conf.json src-tauri/Cargo.toml \
           vmark-mcp-server/package.json vmark-mcp-server/src/cli.ts
   git commit -m "chore: bump version to 0.4.0"
   ```

4. **Tag and push**:
   ```bash
   git tag v0.4.0
   git push origin main --tags
   ```

## Common Mistakes

- Forgetting Cargo.toml (causes dual version display in About dialog)
- Forgetting MCP server files (causes version mismatch in health check)
- Tagging before all files are updated
- Using different versions across files

## Verification

1. Check About VMark dialog shows single version number
2. Run `vmark-mcp-server --version` shows same version
3. MCP Status dialog in Settings shows same version
