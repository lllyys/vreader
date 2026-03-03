# Security Configuration Reference

## Overview

Tauri 2.0 uses a **capabilities-based security model**:

- **Capabilities** - Define what permissions apply to which windows
- **Permissions** - Enable/disable specific commands and API access
- **Scopes** - Restrict parameters (e.g., which paths can be accessed)

All plugin commands are **blocked by default**. You must explicitly enable them.

## Capability Files

Location: `src-tauri/capabilities/*.json` (or `.toml`)

All `.json` files in this directory are automatically loaded.

### Basic Structure

```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "main-capability",
  "description": "Main window capabilities",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "fs:default",
    "dialog:default"
  ]
}
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `identifier` | Yes | Unique capability name |
| `description` | No | Human-readable description |
| `windows` | Yes* | Window labels this applies to |
| `webviews` | Yes* | Webview labels (for multi-webview) |
| `permissions` | Yes | Array of permission identifiers |
| `platforms` | No | Limit to specific platforms |
| `remote` | No | Allow remote URLs to use these permissions |

*At least one of `windows` or `webviews` required.

## Permission Formats

### Simple Permission (by identifier)

```json
{
  "permissions": [
    "fs:default",
    "fs:allow-read-text-file",
    "dialog:allow-open"
  ]
}
```

### Permission with Scope

```json
{
  "permissions": [
    {
      "identifier": "fs:allow-read-text-file",
      "allow": [
        { "path": "$APPDATA/**" },
        { "path": "$HOME/Documents/**" }
      ],
      "deny": [
        { "path": "$HOME/Documents/private/**" }
      ]
    }
  ]
}
```

## Core Permissions

```json
{
  "permissions": [
    "core:default",           // Basic app functionality
    "core:window:allow-close",
    "core:window:allow-minimize",
    "core:window:allow-maximize",
    "core:window:allow-set-title",
    "core:event:default",     // Event listening/emitting
    "core:app:default",       // App info (name, version)
    "core:path:default"       // Path resolution
  ]
}
```

## Plugin Permissions

### File System (`fs`)

```json
{
  "permissions": [
    "fs:default",
    "fs:allow-read-text-file",
    "fs:allow-write-text-file",
    "fs:allow-read-file",
    "fs:allow-write-file",
    "fs:allow-read-dir",
    "fs:allow-create-dir",
    "fs:allow-remove",
    "fs:allow-rename",
    "fs:allow-copy-file",
    "fs:allow-exists",
    "fs:allow-stat",
    "fs:allow-watch",
    {
      "identifier": "fs:scope",
      "allow": [
        { "path": "$APPDATA/**" },
        { "path": "$DOCUMENT/**" }
      ]
    }
  ]
}
```

### Dialog

```json
{
  "permissions": [
    "dialog:default",
    "dialog:allow-open",
    "dialog:allow-save",
    "dialog:allow-message",
    "dialog:allow-ask",
    "dialog:allow-confirm"
  ]
}
```

### Clipboard

```json
{
  "permissions": [
    "clipboard-manager:allow-read",
    "clipboard-manager:allow-write",
    "clipboard-manager:allow-read-image",
    "clipboard-manager:allow-write-image",
    "clipboard-manager:allow-write-html",
    "clipboard-manager:allow-clear"
  ]
}
```

### Shell

```json
{
  "permissions": [
    "shell:allow-open",
    "shell:allow-execute",
    {
      "identifier": "shell:allow-execute",
      "allow": [
        { "name": "node", "cmd": "node", "args": true },
        { "name": "git", "cmd": "git", "args": ["status", "log", "diff"] }
      ]
    }
  ]
}
```

### HTTP

```json
{
  "permissions": [
    "http:default",
    {
      "identifier": "http:default",
      "allow": [
        { "url": "https://api.myapp.com/**" },
        { "url": "https://*.github.com/**" }
      ],
      "deny": [
        { "url": "http://**" }
      ]
    }
  ]
}
```

## Scope Variables

Use these in scope paths:

| Variable | macOS | Windows | Linux |
|----------|-------|---------|-------|
| `$APPCONFIG` | `~/Library/Application Support/{id}` | `%APPDATA%\{id}` | `~/.config/{id}` |
| `$APPDATA` | `~/Library/Application Support/{id}` | `%APPDATA%\{id}` | `~/.local/share/{id}` |
| `$APPLOCALDATA` | `~/Library/Application Support/{id}` | `%LOCALAPPDATA%\{id}` | `~/.local/share/{id}` |
| `$APPCACHE` | `~/Library/Caches/{id}` | `%LOCALAPPDATA%\{id}\cache` | `~/.cache/{id}` |
| `$APPLOG` | `~/Library/Logs/{id}` | `%LOCALAPPDATA%\{id}\logs` | `~/.local/share/{id}/logs` |
| `$HOME` | `~` | `%USERPROFILE%` | `~` |
| `$DOCUMENT` | `~/Documents` | `%USERPROFILE%\Documents` | `~/Documents` |
| `$DOWNLOAD` | `~/Downloads` | `%USERPROFILE%\Downloads` | `~/Downloads` |
| `$DESKTOP` | `~/Desktop` | `%USERPROFILE%\Desktop` | `~/Desktop` |
| `$TEMP` | `/tmp` | `%TEMP%` | `/tmp` |
| `$RESOURCE` | App bundle resources | App resources | App resources |

## Platform-Specific Capabilities

```json
{
  "identifier": "desktop-only",
  "platforms": ["linux", "macos", "windows"],
  "windows": ["main"],
  "permissions": [
    "shell:allow-execute",
    "updater:default"
  ]
}
```

Valid platforms: `linux`, `macos`, `windows`, `android`, `ios`

## Window-Specific Capabilities

```json
// capabilities/main.json
{
  "identifier": "main-window",
  "windows": ["main"],
  "permissions": ["fs:default", "dialog:default"]
}
```

```json
// capabilities/settings.json
{
  "identifier": "settings-window",
  "windows": ["settings"],
  "permissions": ["store:default"]
}
```

## Remote Access (Use with Caution)

Allow remote URLs to access Tauri APIs:

```json
{
  "identifier": "remote-capability",
  "windows": ["main"],
  "remote": {
    "urls": ["https://trusted.example.com/*"]
  },
  "permissions": ["http:default"]
}
```

⚠️ **Security Warning:** Only enable for trusted domains. Remote access exposes your app's capabilities to external code.

## Custom Command Permissions

For your own commands, define permissions in `src-tauri/permissions/`:

```toml
# src-tauri/permissions/my-commands.toml
[[permission]]
identifier = "allow-save-document"
description = "Allow saving documents"
commands.allow = ["save_document"]

[[permission]]
identifier = "allow-load-document"
description = "Allow loading documents"
commands.allow = ["load_document"]

[default]
description = "Default permissions for document commands"
permissions = ["allow-save-document", "allow-load-document"]
```

Reference in capabilities:

```json
{
  "permissions": [
    "my-commands:default"
  ]
}
```

## Debugging Permissions

### Common Errors

**"command not allowed"** or **"not allowed by scope"**:
- Check capability files include the window label
- Verify permission is listed
- Check scope allows the requested path/URL

### List Available Permissions

After building, check `src-tauri/gen/schemas/`:
- `desktop-schema.json` - All available permissions
- `<platform>-schema.json` - Platform-specific

### Verify Capabilities

```bash
# Build generates schema with all available permissions
npm run tauri build -- --debug

# Check gen/schemas/ for available permission identifiers
```

## Best Practices

1. **Principle of Least Privilege** - Only enable what's needed
2. **Use scopes** - Restrict file/network access to specific paths/domains
3. **Separate capabilities** - Different windows get different permissions
4. **Audit regularly** - Review permissions when adding features
5. **Avoid remote access** - Unless absolutely necessary
6. **Use `deny` for sensitive paths** - Even within allowed scopes
