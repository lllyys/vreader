# Feature #1121 — Edit handoff: auto-open editor after jump (Bug #249 follow-up)

> GH #1121. Source of truth: this plan + the issue. Design status: **plumbing, not
> new UI** — the Edit destination (`HighlightActionCard` editing mode for highlights,
> the note editor for standalones) is already designed/built; this wires the
> programmatic "navigate → open the editor" entry point that #1080 deferred.

## Problem

The HighlightsSheet (Notes) `⋯ → Edit` currently does a navigate-only handoff
(`HighlightsSheet+Delete.edit()` → `onNavigate(locator)` + `onDismiss()`), landing
the user on the passage where the in-reader edit affordance is one tap away. The
committed design says Edit should **auto-open** the editor after the jump. It can't
today: the in-reader popover (`HighlightPopoverModifier`) only presents in response
to a real `.readerHighlightTapped` (a tap on a *rendered* highlight, resolved async
by the per-format reader bridge); there is no programmatic post-navigation
edit-open entry point. Standalone notes have no presentation path from the sheet at all.

## Surface area (file-by-file)

- **`vreader/Views/Reader/ReaderNotifications.swift`** — `ReaderHighlightTapEvent`
  gains `openInEditMode: Bool = false` (Sendable/Equatable preserved; default keeps
  every existing call site unchanged). Add a new `Notification.Name`
  `.readerHighlightEditRequested` (payload: highlight `UUID`).
- **`vreader/Views/Reader/HighlightPopoverModifier.swift`** — when presenting a card
  for an event with `openInEditMode == true`, present in `mode = .editing` (and seed
  the `noteDraft` from the highlight's note). Extract the mode/draft seed into a pure
  helper `HighlightPopoverEditSeed.mode(for:)` for unit testing.
- **`vreader/Views/Reader/Annotations/HighlightsSheet+Delete.swift`** — `edit()` for
  a `.highlight` posts `.readerHighlightEditRequested(highlightID)` AFTER
  `onNavigate` (a pure router `HighlightEditHandoff.request(for:)` decides
  highlight-vs-standalone routing — testable). For `.standalone`, route to the note
  editor presentation (WI-3).
- **Per-format reader bridges** (TXT/MD chunked + non-chunked, EPUB, Foliate, PDF) —
  observe `.readerHighlightEditRequested`: once the highlight re-renders in the new
  scroll/page position (reuse each format's existing highlight-render/restore
  signal — e.g. Foliate `.foliateOverlayReadyForSection`, EPUB `sectionMaterialized`,
  TXT cell render), resolve the highlight's anchor rect (the SAME resolver the tap
  path uses) and post `.readerHighlightTapped` with `openInEditMode: true`.
- **Standalone notes** — wire `HighlightNoteEditSheet` (feature #914) / `AnnotationEditSheet`
  presentation from the review-sheet edit on a `.standalone` card.

### Files OUT of scope
- The popover card UI itself (`HighlightActionCard`) — already designed/built; only
  the *trigger* + initial `mode` change.
- The delete/copy actions (#1080, shipped).
- Any new visible chrome — none. If the in-sheet-vs-after-jump presentation question
  resurfaces, file `needs-design` then (per the issue).

## Prior art / precedent
- The `.readerHighlightTapped` → `HighlightPopoverRequest.event(from:)` →
  `presentCard(mode:)` pipeline (feature #53/#64) — the edit-open reuses it, only
  adding a programmatic producer + the `openInEditMode` flag.
- Per-format highlight-render signals already exist for restore (Foliate
  `.foliateOverlayReadyForSection`, EPUB `sectionMaterialized`) — the edit-open keys
  on the same signals rather than inventing a new "rendered" channel.

## Work-item sequencing
- **WI-1 (foundational, unit-testable, no user-observable behavior alone)**:
  `openInEditMode` flag on `ReaderHighlightTapEvent`; `.readerHighlightEditRequested`
  name; `HighlightPopoverEditSeed.mode(for:)` (pure); modifier presents `.editing`
  when the flag is set; `HighlightEditHandoff.request(for:)` router; `edit()` posts
  the request for highlights. **Ships now.** No format wiring yet → no behavior change
  until a bridge produces the flagged tap (WI-2), so this is safe to ship flag-free.
- **WI-2 (behavioral, CU-verified)**: per-format bridge resolution — observe
  `.readerHighlightEditRequested`, resolve-after-render, post the flagged
  `.readerHighlightTapped`. One format per PR (start with the chunked TXT path —
  the default). Device-verified each.
- **WI-3 (behavioral, CU-verified)**: standalone-note editor presentation path.

## Test catalogue
- `ReaderHighlightTapEventTests` — `openInEditMode` default false; Equatable includes it.
- `HighlightPopoverEditSeedTests` — `mode(for:)` returns `.editing` when the flag is
  set (seeds draft from the note), `.reading` otherwise.
- `HighlightEditHandoffTests` — router maps `.highlight` → an edit-request for that
  id; `.standalone` → the note-editor route.
- WI-2/WI-3: per-bridge integration (CU/device) — the resolve-after-render + present.

## Risks + mitigations
- **Async race (the hard part)**: the highlight may not be rendered when the request
  arrives. Mitigation: key on each format's existing render/restore signal + a bounded
  retry/timeout; if it never renders (e.g. evicted), no-op (the user still landed on
  the passage — the #1080 behavior, no regression).
- **5-format surface**: WI-2 ships one format per PR so each is device-verified
  independently; partial coverage degrades gracefully to the navigate-only handoff.

## Backward compat
- `openInEditMode` defaults false → every existing `ReaderHighlightTapEvent` call site
  + tap behavior is unchanged. WI-1 ships no behavior change until a producer sets the
  flag. No persistence/schema impact.

## CU note
WI-1 is unit-test-verified (pure seams). WI-2/WI-3 are inherently device/CU-verified
(the navigate→render→present flow) — with CU currently down they ship
`awaiting-device-verification` like the in-flight bug fixes, OR pause for CU per the
verification gate.

---

## Gate-2 audit fixes applied (2026-05-31, Codex round 1 → addressed)

| Finding | Resolution |
|---|---|
| H1: the flag is lost in the popover pipeline (`router.present` hard-resets mode=.reading; VM publishes only content) | WI-1 threads intent end-to-end: `VM.presentedInitialMode` set in `handleTap` from `event.openInEditMode`; the modifier passes it to `router.present(_:initialMode:)` (new param) which seeds `mode` + `noteDraft` from `content.note`. Unit-tested. |
| H2: EPUB `sectionMaterialized` too early to mean "highlight measurable" | Deferred to WI-2; the plan's per-format wiring will hook the AFTER-restore ack (post-`restoreHighlightsInSectionJS`), not `sectionMaterialized`. Paged EPUB hooks `didFinish` + pending restore. |
| M3: all 6 `ReaderHighlightTapEvent` constructors (PDF/EPUB/TXT×2/Foliate×2) | The default `openInEditMode = false` keeps all 6 unchanged; WI-2 touches them one format/PR. |
| M4: payload under-specified | `ReaderHighlightEditRequest { highlightID, bookFingerprintKey, token }` — book-scoped + single-flight token. |
| M5: Foliate resolver differs (UUID→CFI, no rect) | WI-2 plans Foliate separately (fetch by UUID → CFI → await overlay → post `.zero` rect → sheet fallback). |
| M6: TXT/MD render signal vague | WI-2: non-chunked resolves after `scrollToMatchedOffset`+`ensureLayout`; chunked waits for the target chunk cell to be visible/rendered. |
| M7: cancellation/staleness | The `token` is the single-flight handle; observers ignore mismatched book / superseded token. WI-2 cancels on new request / manual tap / reader close / book change. |
| L8: equality semantics | tested: default false; `false != true`. |
| L9: "WI-1 behavior-free" imprecise | WI-1 is **non-presenting**: it adds the types + router intent-threading + the pure `HighlightEditHandoff` router, but does NOT change `edit()` (stays navigate-only) and NO bridge observes `.readerHighlightEditRequested` yet → strictly no runtime behavior change. The producer (`edit()` posting) + first observer land together in WI-2. |

**WI-1 shipped** (this PR): `openInEditMode` flag, `ReaderHighlightEditRequest` +
`.readerHighlightEditRequested`, `router.present(_:initialMode:)` + VM threading,
`HighlightEditHandoff` router. Unit-tested (`HighlightEditHandoffTests`,
`HighlightPopoverActionRouterTests`). Non-presenting → no device verification needed.
WI-2 (per-format resolve-after-render) + WI-3 (standalone editor) are the behavioral,
CU-verified slices.
