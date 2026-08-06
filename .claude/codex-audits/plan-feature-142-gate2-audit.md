---
gate: 2
kind: plan-audit
feature: 142
plan: dev-docs/plans/20260806-feature-142-android-azw3-annotations.md
rounds: 2
final_verdict: pending-round-3
---

# Gate-2 plan audit — feature #142 (Android AZW3 selection + highlights/notes)

Auditor: Codex `gpt-5.5`, effort `high`, read-only, via `scripts/run-codex.sh` (rule 53).
Committed per the Gate-2 artifact requirement (rule 47) — see
`.claude/codex-audits/plan-feature-141-gate2-audit.md` for why that requirement exists.

## Auditor reliability note (round 1)

Round 1 cited paths under `android/app/src/main/kotlin/me/lllyys/vreader/…`. **There is no `me/`
package in this repo** — the real root is `com/vreader/app/…` — and design citations dropped the
`vreader-fidelity-v1/project/` segment. Every finding was therefore re-verified at real paths
before being actioned; **none turned out to rest on a nonexistent file**, so nothing was dismissed
on the citation error. Round 2's prompt required path verification and its citations check out.

## Round 1 — `block-recommended` (4 High, 3 Medium, 2 Low)

| # | Sev | Finding | Round-2 status |
|---|---|---|---|
| 1 | High | Payload caps applied too late — `FoliateBridge.kt:137` hands `message.data` straight to `FoliateMessageParser.parse`, which calls `parseToJsonElement` immediately (orchestrator-confirmed at the real path), so field-level caps never see the hostile input first. | **PARTIALLY** — cap added in the right place; the author's narrowing (`WebMessageCompat.data` is already a String, so the cap bounds JSON amplification, not receipt) is confirmed correct. But the **sizing is wrong**: see H1. |
| 2 | High | Connected tests allowed to `Assume`-skip — bug #369's exact shape, where a skip exits 0 like a pass. | **RESOLVED** — WI-7 acceptance uses the fail-hard `importRealBook()` pattern (`assertTrue` + content-digest identity); slice tier keeps skip helpers explicitly; Gate-5 evidence requires non-zero executed count and zero skips. |
| 3 | High | Standalone-note acceptance had no entry point to create one. | **RESOLVED by removal** — `AnnotationsRepository.addNote` has **zero** production call sites; EPUB/TXT "Note" attaches to a highlight (`ReaderActivity.kt:678`, `TxtReaderActivity.kt:1171`). Dropped from scope; no control invented. Orchestrator filed the app-wide gap as **feature #176**. |
| 4 | High | Tapped-highlight routing conflicts with the newer committed design (`highlight-popover-canvas-artboards.jsx:666`: *"Trigger: single tap on an existing highlight… Long-press route stays on the selection popover"*). | **ADJUDICATED, not fixed** — the conflict is real but **pre-existing and app-wide**: `ReaderActivity.kt:598` and `TxtReaderActivity.kt:1107` already route taps into `PopoverMode.EDIT`. #142 stays consistent with every other format; cross-format adoption tracked as **feature #175**. |
| 5 | Med | The bundle's posted selection `rect` is section-iframe-relative (the tap path routes through `mapTapToHostViewport` for exactly that reason), and a `frameLeft`-only probe ignores frame top, RTL, writing mode, scrolled-vs-paginated, and multi-rect selections. The auditor's fix would require touching the SHA-pinned bundle. | **PARTIALLY** — premise **verified**: `Azw3DomProbe.kt:58/:156` already evaluates JS in the shell and reaches `renderer.getContents()[0].doc` with `Range.getClientRects()`; `foliate-bundle.js:7141` reads `frameElement.getBoundingClientRect()` from the same context; `reader.html:5` pins `initial-scale=1`. **No bundle change needed** — SHA pin and rule-54 posture untouched. Remaining defects: M1. |
| 6 | Med | Coroutine scopes unpinned — the shape of the Activity leak #165 WI-7 fixed one week earlier. | **RESOLVED** — per-work-kind scope table: `appScope` for repository writes capturing only value types, composition/lifecycle for reads, WebView calls and the probe; callbacks nulled + `teardown()` in the existing `onDispose`. Caution carried to the WI brief: existing EPUB code still captures Activity fields inside `appScope`; do not copy it. |
| 7 | Med | Write-set collision with the in-flight bug #368 lane (`Azw3ReaderActivity.kt` / `Azw3ReaderChrome.kt`). | **RESOLVED** — WI-1…WI-4 independent, WI-5/WI-6 wait for #368, WI-7 test/evidence-only. Verified against the WI file lists. |
| 8/9 | Low | Bundle/API assumptions verified; anchor/restore trap **independently confirmed on both platforms** (Android `anchor = null` on restore, iOS `anchor: nil`, `contracts/identity/backup-format.md` states `locatorJSON` is plain `Locator` JSON). | **RESOLVED** — provenance test extended to pin `selection`/`annotation-show`/`create-overlay` and `addAnnotation`/`deleteAnnotation`/`deselect`, so bundle drift fails visibly. |

### The plan's own highest-value catch, confirmed by the auditor

The backup wire carries **no anchor**, so `restoreAnnotations` inserts `anchor = null`. Reading the
CFI only from the anchor — the obvious iOS-parity design — would make **every restored AZW3
highlight permanently invisible**. The `record.anchor?.cfi ?: record.locator.cfi` fallback and its
RED test stay.

## Round 2 — `block-recommended` (2 new)

- **H1 (High)** — `MAX_RAW_MESSAGE_CHARS = 4 Mi` is **below** the worst-case *legitimate*
  `book-ready`. Each TOC row serialises as `{label, href, subitems}`; a 10 000-entry flat TOC is
  ~370 112 chars with empty strings but **~4 370 112** with 200-char labels and hrefs, above the
  4 194 304 cap — so the cap can drop a legitimate message and strand the reader before `Loaded`.
  **One of the two proposed fixes is closed**: `FoliateTocParser.kt:99-100` preserves labels and
  hrefs *byte-for-byte* by design, because `relocate.tocHref` matching is byte-exact — capping them
  would break #140's current-chapter highlighting. So the cap must be raised (derived, not picked)
  or made per-message-name.
- **M1 (Medium)** — the anchor probe overclaims the focus edge and accepts degenerate rects: it
  always takes `rects[rects.length - 1]`, but the Selection API defines **backward** selections
  where focus is the range *start*; and it accepts any non-empty rect list, where the existing probe
  filters by width (`Azw3DomProbe.kt:91`). Vertical writing mode is claimed but untested.

Round 3 (the rule-47 cap) is in progress on both.
