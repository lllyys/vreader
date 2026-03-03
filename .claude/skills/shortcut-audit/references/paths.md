# Shortcut Audit Paths

## Docs
- `website/guide/shortcuts.md` (primary, in repo)
- `dev-docs/shortcuts.md` (local, not in repo — if available)

## Code (common sources)
- `src/utils/shortcutMatch.ts`
- `src/plugins/codemirror/sourceShortcuts.ts`
- `src/plugins/formatToolbar/` (toolbar triggers)
- `src/plugins/sourceContextDetection/` (source mode shortcuts and format actions)
- `src/plugins/editorPlugins.tiptap.ts` (keymaps)
- `src-tauri/src/menu.rs` (menu accelerators)

## Useful scans
- `rg -n "shortcut|keymap|accelerator|Cmd\+|Ctrl\+|F[0-9]+" src src-tauri`
