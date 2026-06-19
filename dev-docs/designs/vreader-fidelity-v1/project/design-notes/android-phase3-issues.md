# Two Android Phase-3 needs-design issues — design notes

> Resolves the design gaps blocking [#1766](https://github.com/lllyys/vreader/issues/1766) and [#1767](https://github.com/lllyys/vreader/issues/1767), both children of the [#110](https://github.com/lllyys/vreader/issues/110) Android Phase-3 capability-parity driver.
> Source of truth: `VReader PDF Reader Canvas.html` and `VReader Backup Restore Canvas.html` (every state across themes).

Both issues are blocked by Rule 51 (UI from the committed design bundle only). iOS gets these surfaces from system components (PDFKit's `PDFView`; the `Views/Backup` + `WebDAV*` subsystem); Android's `PdfRenderer` and the lack of a UI subsystem mean the surfaces have to be built — and therefore designed. These designs are rendered in VReader's existing vocabulary (the reader `THEMES`, Source-Serif titles, `#8c2f2f` / `#d6885a` accent, rounded-14 cards, the AI-provider form primitives) so Android reads as the same product, not a Material re-skin.

---

## #1766 · Android PDF reader — base page-view

**Decision: continuous vertical scroll (canonical), with paged single-page as a Display-panel toggle.** Component file: `vreader-pdf-reader.jsx`. Canvas: `VReader PDF Reader Canvas.html`.

### Why continuous scroll wins (the question the issue asks)

`PdfRenderer` hands back one **bitmap per page**. The two layout options:

- **A. Continuous scroll (CANONICAL).** Bitmaps stack vertically with gaps on a neutral viewer backdrop. This is the native grammar of every mainstream Android PDF surface (Drive, Files, Adobe), so it needs zero teaching. Crucially, a technical library (DDIA, Pragmatic Programmer — the actual PDFs in `BOOKS`) is figure-heavy, and a visible page edge above/below keeps figures and their captions legible. Tap-centre toggles chrome; the scroll itself is the navigation.
- **B. Paged (alternative).** One page at a time, reusing the EPUB reader's left-30% / right-30% / centre tap-zones so PDF and EPUB share one navigation grammar. It loses page-edge context and re-rasterizes a fresh bitmap per turn. Good for prose-only PDFs; wrong as the default. Shipped as a **Display-panel toggle**, not a fork.

### Surfaces & states

| Area | Treatment |
|---|---|
| Page render area | Page bitmap floats on a neutral backdrop (`#cdc7ba` light / `#101010` dark), distinct from the reader paper tone so it reads as an object. |
| Page progress | Floating glassy **"Page N of M"** pill, bottom-centre. Visible while scrolling / chrome-hidden. |
| Chrome | Reuses `vreader-reader.jsx`'s vocabulary — back-chevron "Library" + italic serif title + icon row; bottom toolbar (Contents / Pages / Display / AI). |
| Dark mode | The bitmap is drawn onto a **dimmed sheet**, not pure white — a full-white PDF page on OLED at night is the #1 PDF-reader complaint. Invert is a separate Display option. |
| Loading | "Rendering page N…" — skeleton page frame + shimmer (the bitmap is rasterizing). |
| Encrypted | Lock glyph + password field + Unlock; wrong-password sub-state. **Recoverable.** |
| Corrupt | Undecodable file — re-import / back to Library. **Not recoverable in place.** |
| Image-only (scan) | Not an error — the bitmap renders fine; only selection / translation degrade. |
| Page jump | The "Pages" toolbar item: thumbnail strip + scrubber for non-linear navigation of a 600-page book. |

Encrypted ≠ corrupt ≠ image-only — three visually distinct outcomes so the user knows whether to type a password, re-import, or just keep reading.

---

## #1767 · Android backup & WebDAV restore UI

**Decision: three pushed surfaces in the app's own form vocabulary, every error naming its HTTP cause + the one action that fixes it.** Component file: `vreader-backup-webdav.jsx`. Canvas: `VReader Backup Restore Canvas.html`. Reuses the AI-provider editor's primitives (`UI`, `Card`, `Row`, `GroupHeader/Footer`, `Tag`, `PhoneFrame`, `AppSheet`) so Settings feels like one system.

The **backend** (cross-platform backup-format per `contracts/identity/backup-format.md`, the WebDAV client, the restore import pipeline) is **not design-gated** and is verified separately via instrumented tests against a local WebDAV. Only the user-facing surfaces below were blocked.

### A — WebDAV server settings

Saved-servers list. Empty-state onboards (names the compatible hosts: Nextcloud, Fastmail, Synology). Populated rows carry a live **status dot** + the exact failure reason (`401 — authentication failed`), not a generic "error". Tap a row to edit/test; `+` adds.

### B — Add / edit a server

Name · Base URL · Username · Password · **Back up on Wi-Fi only** toggle. **Test Connection runs against the live form — no save first** (same contract as the AI-provider sheet) and reports the HTTP result inline (`Connected — found an existing /vreader folder with 3 backups` / `Failed: 401 Unauthorized`). Edit mode adds a destructive **Remove Server** with a confirm alert that promises the on-server backups are left untouched.

### C — Backup & restore

Active-server header + **Back Up Now** (which swaps to an inline `Backing up… 8 / 12` progress state), then the list of backups on the server (date · book count · size · device, newest tagged **Latest**). Covers `loading` (reading from server), `empty` (no backups → first-backup nudge), and **every WebDAV error the client can surface**: `401` (re-auth), `404` (no `/vreader` folder yet → back up to create it), `offline`, `timeout`. Each error states the cause and gives exactly one CTA.

### D — Restore: confirm → progress → result

- **Confirm alert** — states the merge rules explicitly: *"Merges 12 books… Nothing is deleted — existing books and progress are kept, newer versions win."*
- **Progress** — radial percent + book-by-book label (`Downloading book 7 of 12 · The Pragmatic Programmer`) + Cancel.
- **Result** — three distinct outcomes: **success** (Done), **partial** (`9 of 12… retry 3 books` in place), **failed** (`library unchanged` → try again). The partial/failed split is the part most apps get wrong; the copy always says what survived.

**Restore never deletes** — this promise appears in the confirm alert, the screen footer, and the success copy. A backup is a merge, not a replace; that's what makes the big primary button safe.

### E — Selective restore picker

Choose which books to restore from a backup manifest. Per-book state is the whole point — a manifest can reference books not yet on this device:

| State | Affordance |
|---|---|
| `local` | "On this device" + green dot — already here. |
| `remote` | "Download · 1.8 MB" — pulled from the server lazily **on tap** (mirrors the iOS two-tap affordance, [#47](https://github.com/lllyys/vreader/issues/47)). |
| `downloading` | Inline progress bar + percent. |
| `failed` | "Download failed — tap to retry" — retries in place without restarting the whole restore. |

Pinned footer totals the selection (`5 books selected · 3 already local · 2 will download`).

---

## Cross-references

| File | Role |
|---|---|
| `VReader PDF Reader Canvas.html` | Canvas of every PDF-reader state across themes — #1766. |
| `vreader-pdf-reader.jsx` | `PdfContinuousReader`, `PdfPagedReader`, `PdfPaper`, `PdfRendering`, `PdfEncrypted`, `PdfCorrupt`, `PdfPageJump`, reader chrome — #1766. |
| `pdf-reader-artboards.jsx` | Canvas artboards — #1766. |
| `VReader Backup Restore Canvas.html` | Canvas of every backup/WebDAV state across themes — #1767. |
| `vreader-backup-webdav.jsx` | `WebDAVServerList`, `ServerEditSheet`, `BackupRestoreScreen`, `RestoreProgress`, `SelectiveRestoreSheet`, `AppAlert` — #1767. |
| `backup-webdav-artboards.jsx` | Canvas artboards — #1767. |
