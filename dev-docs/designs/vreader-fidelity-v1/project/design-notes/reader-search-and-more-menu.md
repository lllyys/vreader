# Reader chrome — Search + More menu (Feature #60 WI-6 supplement)

> Resolves [#760](https://github.com/lllyys/vreader/issues/760). To be filed under `dev-docs/designs/vreader-fidelity-v1/`.

## 1. Search button — placement

**Decision: keep Search as an icon in the top chrome**, between back-to-Library and Bookmark.

Production order, left → right: `← Library  |  Title  |  🔍 Search   📑 Bookmark   ⋯ More`

### Why not the other options

| Option | Why not |
|---|---|
| Add Search as a 5th button in the bottom toolbar | Bottom toolbar is for tools that change *what you see now* — Contents, Notes, Display, AI. Search jumps you to *somewhere else*. Mixing intents weakens both clusters, and 5 buttons in a 402-px bar drops each hit target near the 44-pt minimum. |
| Bury Search under the More menu | Search is high-frequency mid-read. Two taps (More → Search) breaks the production app's one-tap contract. |
| Long-press a chrome region | Discoverability is poor; iOS reading apps don't use this pattern; accessibility-hostile (VoiceOver users have no equivalent). |
| Drop Search from Reader | Explicit regression. Library-only search forces the user to leave their reading position to find a passage they're already mid-book on. Rejected. |

### States — Search button
1. **Default** — `Icons.Search`, theme `ink` color, 36×36 hit target, no background.
2. **Active/pressed** — momentary highlight via the same iconBtn style as the bookmark + more buttons.
3. (No persistent "searching" state on the button itself — the sheet handles that.)

## 2. More menu — contents & visual treatment

**Decision: anchored popover from the `⋯` button** (top-right). Width 268 px, radius 16, drop shadow + hairline border. Notch points to the trigger.

### Items (top → bottom)

| Icon | Label | Sub-detail | Control |
|---|---|---|---|
| Volume | **Read aloud** | "Start text-to-speech" → "Playing · System voice" when active | Tap → opens TTS player; row stays highlighted while playing |
| Timer | **Auto-turn pages** | "Off" → "Every 30s" when on | Toggle switch (inline) |
| Translate | **Bilingual mode** | "Translate inline" → "English ↔ Chinese" when on | Toggle switch (inline) |
| — | *(divider)* | | |
| Info | **Book details** | — | Tap → metadata sheet (file format, size, fingerprint, location) |
| Share | **Share book** | — | Tap → system share sheet |
| Download | **Export annotations** | "Markdown · JSON · VReader JSON" | Tap → export-format picker |

### Items deliberately **not** in the menu

- **Search** — lives in the top bar (decision §1).
- **Display / Contents / Notes / AI** — already in the bottom toolbar.
- **Settings** — global app settings live in Library, not Reader.
- **Switch renderer (Native ↔ Unified)** — a debug affordance, gated to DEBUG builds, not user-facing UI.

### States

1. **Closed** — `⋯` button neutral.
2. **Open** — `⋯` button takes a 6% backdrop tint to show it's the menu anchor; popover slides into place; tapping the backdrop or any item closes it.
3. **With toggles on** — toggle rows show accent-tinted icon background + green toggle; sub-text updates to the active state ("Every 30s", "English ↔ Chinese", "Playing · System voice").

### Theme rendering — all 5

- Paper: bg `#fcf8f0`, ink `#1d1a14`, hairline `rgba(29,26,20,0.12)`
- Sepia: bg `#fcf8f0` (inherits `chrome` token), warm hairline
- Dark: bg `#2a2724`, ink `#d8d2c5`, hairline `rgba(216,210,197,0.12)`
- OLED: bg `#2a2724` (slight lift above `#000` so it reads as a surface), ink `#b9b6b0`
- Photo: bg `rgba(20,16,12,0.92)` (must be opaque enough to read against arbitrary backgrounds; no backdrop-filter dependency)

## 3. Cross-references

- Prototype implementation: `vreader-more.jsx`, wired in `vreader-reader.jsx::ReaderScreen` and `ReaderTopChrome`.
- Search sheet itself unchanged from v1.1 — `vreader-search.jsx`.
- Production `ReaderChromeBar.swift`: keep the existing Search button; replace `onMore → onOpenSettings` stub with the popover defined here.
- Accessibility: each top-bar icon gets an `accessibilityIdentifier` matching the `ReaderChromeButton` enum WI-6a is introducing (`reader.chrome.search`, `reader.chrome.bookmark`, `reader.chrome.more`).

## 4. What this does NOT cover

- The Book Details sheet contents (file metadata, fingerprint, location, cover swap). Punt to a follow-up issue when WI-6 lands.
- TTS player UI (#15/#17 are tracking the presenter re-skin separately).
- Export-format picker UI — system action sheet is fine; no custom UI needed.
