# #1597 · Settings → Diagnostics entry + in-app log viewer (feature #96)

> Source of truth: `VReader Diagnostics Canvas.html` (every state across themes).
> Components: `vreader-diagnostics.jsx` · Artboards: `diagnostics-artboards.jsx`

**Decision: a "Support" group row in `SettingsView` that pushes a Diagnostics
screen — chip filters (level + category), monospace newest-first log list,
share trigger in the nav-bar trailing slot, pinned capture-status footer.**

---

## Entry point

A new **Support** group at the bottom of `SettingsView`, above nothing and
containing two rows:

| Row | Tile | Glyph | Trailing |
|---|---|---|---|
| **Diagnostics** (new) | steel `#5b6770` | pulse/waveform line | chevron |
| About VReader (existing, regrouped) | gray `#8a8a8e` | info | version + chevron |

- Matches the shipped colored-tile `SettingsRow` vocabulary (30×30 tile, white
  17px glyph, 15px title, 11px detail subline).
- Detail line: *"View and export app logs"* — names both jobs of the screen.
- **Why a Support group and not inside About:** the whole point is a scripted
  bug-report ask — *"Settings → Diagnostics → tap share"*. Burying it one level
  deeper inside About adds a hop to every support conversation.
- **Why no error-count badge on the row (alt X3):** it makes Settings feel
  alarming for errors the user can't act on. Diagnostics are for when something
  already went wrong, not an invitation to worry.

## Log viewer screen

Pushed within the Settings nav (`‹ Settings` back, serif "Diagnostics" title) —
same `NavSheet` frame as #1380.

### Filters — two chip rows under the nav bar

- **Level row:** `All · Errors · Debug · Info`, each with a count. Active chip
  is the inverted-ink pill (HighlightsSheetV2 vocabulary); the **Errors chip
  takes the error tint when active** so a filtered list is legible at a glance.
- **Category row:** horizontally scrollable chips — `All · Library ·
  Persistence · Reader · AI · Sync · DebugBridge`. Chips, not a dropdown:
  categories are few, and one tap beats two.
- Both filters compose. The footer reflects the filtered scope
  (*"Showing 12 of 487 · errors"*). An empty intersection gets a distinct
  filtered-empty state with a **Clear filters** pill.

### Log rows

Newest first, grouped under day headers (*"Today · 10 June"*).

```
14:32:07.412  ERROR  [Persistence]
Failed to save ReadingSession: CKError 4 (networkUnavailable)
— retry queued for next launch
```

- Meta line: mono 10.5px timestamp · colored uppercase level · mono category
  pill on a subtle fill.
- Level color is functional, not decorative: error = warm red
  (`#b13e36` / `#e0826f` dark), info = cool blue (`#3a6f9c` / `#7fb2d9`),
  debug = the theme's `sub`.
- Message: monospace 12px, **clamped to 3 lines**. Tap expands in place —
  full text + a "Copy entry" pill. Chrome stays Inter; only log content is mono.

### Export / share

- **Canonical trigger:** share icon in the nav-bar trailing slot — the
  iOS-standard home for "get this content out of here".
- Payload header (ours to spec, shown in the share-sheet mock):
  `vreader-log-2026-06-10.txt · Plain text · 312 KB · last 24 h`.
- The share sheet itself is system chrome — mocked reduced-fidelity on the
  canvas, labeled as not-designed-here.
- **Why not a pinned "Export log…" CTA (alt X2):** spends permanent vertical
  space on a rare action and crowds the status footer.

### Footer

Pinned: left = scope (`487 entries · last 24 h`), right = a green dot +
**"Capturing"**. Capture is always on in Release (OSLog recorder, subsystem
`com.vreader.app`) — the footer states this instead of offering a toggle, so
nobody hunts for a switch that doesn't exist.

## States covered (per the issue)

| State | Treatment |
|---|---|
| default | filters + list + footer (paper + dark) |
| loading | spinner + *"Reading log store…"* + `OSLogStore · com.vreader.app` — read-back is async |
| empty | pulse tile + *"No log entries yet"* + copy saying capture needs nothing turned on; filters and share hidden (nothing to filter/export) |
| error-filter-active | Errors chip tinted red, footer shows filtered scope |
| category-filter-active | Persistence example, footer scope |
| filtered-empty | filter glyph + named filter + Clear filters |
| export trigger | nav share tapped → system sheet over the dimmed viewer |

## Cross-references

- `SettingsRow` vocabulary — WI-5 of feature #67, `vreader-ai-toggles.jsx`
- `NavSheet` pushed-screen frame — #1380, `vreader-ai-provider-entry.jsx`
- Chip filter language — `HighlightsSheetV2`, feature #62
- Library-as-identity settings hero — #862, `vreader-profile-stats.jsx`
