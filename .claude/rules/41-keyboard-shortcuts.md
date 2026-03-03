# 41 - Keyboard Shortcuts

Rules for adding, changing, or deleting keyboard shortcuts.

## Files That Must Stay in Sync

When modifying shortcuts, update ALL of these files:

| File | Purpose | Format |
|------|---------|--------|
| `src-tauri/src/menu.rs` | Menu accelerators (2 places) | `Some("Alt+CmdOrCtrl+L")` |
| `src/stores/shortcutsStore.ts` | Frontend defaults | `defaultKey: "Alt-Mod-l"` |
| `website/guide/shortcuts.md` | Documentation | `Alt + Mod + L` |

### Format Differences

| Context | Example | Notes |
|---------|---------|-------|
| Rust menu | `CmdOrCtrl+Shift+N` | Uses `+` separator, full modifier names |
| Frontend store | `Mod-Shift-n` | Uses `-` separator, `Mod` for Cmd/Ctrl |
| Documentation | `Mod + Shift + N` | Human-readable with spaces |

## Before Adding or Changing a Shortcut

### 1. Check for Conflicts

```bash
# Check menu.rs for existing accelerators
grep -i "Some(\".*YourKey" src-tauri/src/menu.rs

# Check shortcutsStore.ts for existing defaults
grep -i "defaultKey.*your-key" src/stores/shortcutsStore.ts

# Find all uses of a key combination
grep -riE "Mod-Shift-n|CmdOrCtrl\+Shift\+N" src-tauri/ src/stores/
```

### 2. Check for Duplicates in Store

```bash
# List all shortcuts sorted by frequency (duplicates show count > 1)
grep -oE 'defaultKey: "[^"]*"' src/stores/shortcutsStore.ts | sort | uniq -c | sort -rn
```

## Update Procedure

### Step 1: Update menu.rs (TWO places)

The file has two menu creation functions that must both be updated:

1. `create_menu()` - Default menu (~line 60-600)
2. `create_menu_with_shortcuts()` - Custom shortcuts menu (~line 700-1180)

### Step 2: Update shortcutsStore.ts

Find the shortcut definition and update `defaultKey`:

```typescript
{ id: "lineNumbers", label: "Toggle Line Numbers", category: "view", defaultKey: "Alt-Mod-l", menuId: "line-numbers" },
```

### Step 3: Update Documentation

Update `website/guide/shortcuts.md` in the appropriate table.

### Step 4: Verify

```bash
# Check Rust compiles
cargo check --manifest-path src-tauri/Cargo.toml

# Verify no duplicates
grep -oE 'defaultKey: "[^"]*"' src/stores/shortcutsStore.ts | sort | uniq -c | sort -rn | head -5
```

## Common Pitfalls

### 1. Duplicate Shortcuts

If two menu items share the same accelerator, only one will work. The other is silently blocked.

**Example conflict we fixed:**
- `Cmd+Shift+N` was assigned to both "New Window" and "Toggle Line Numbers"
- Only "Toggle Line Numbers" responded; "New Window" appeared broken

### 2. Frontend Interception

Some shortcuts are handled by frontend hooks that call `e.preventDefault()`:

| Hook | Shortcuts Handled |
|------|-------------------|
| `useViewShortcuts.ts` | sourceMode, focusMode, typewriterMode, wordWrap, lineNumbers, toggleTerminal |
| `useTabShortcuts.ts` | newTab, closeTab (Mod+W), toggleStatusBar |
| `useFileExplorerShortcuts.ts` | toggleHiddenFiles |

If you add a shortcut to the menu but the frontend intercepts it first, the menu event won't fire.

### 3. Forgetting the Second Menu Function

`menu.rs` has TWO places where menus are defined. Missing one causes inconsistent behavior between default and customized shortcuts.

## Standard Shortcut Conventions

| Pattern | Use For | Examples |
|---------|---------|----------|
| `Mod+Key` | Common actions | Save, Open, New, Close |
| `Mod+Shift+Key` | Variants of common actions | Save As, New Window |
| `Alt+Mod+Key` | View toggles, block formatting | Toggle Outline, Blockquote |
| `Alt+Mod+Shift+Key` | Less common actions | Format CJK File |
| `F1-F12` | Mode toggles | F7=StatusBar, F8=Focus, F9=Typewriter |

## Mnemonic Guidelines

Choose shortcuts that are memorable:

| Shortcut | Action | Mnemonic |
|----------|--------|----------|
| `Alt+Mod+L` | Toggle Line Numbers | **L**ines |
| `Alt+Mod+N` | Insert Note | **N**ote |
| `Alt+Mod+Q` | Blockquote | **Q**uote |
| `Alt+Mod+C` | Code Block | **C**ode |
