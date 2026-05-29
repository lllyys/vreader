---
branch: feat/feature-42-wi8-readium-highlights
threadId: codex-exec-readonly
rounds: 2
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Implementation Audit — Feature #42 WI-8 (ReadiumDecorationHighlightAdapter)

Independent Codex audit (`codex exec --sandbox read-only`) of WI-8: render
vreader's stored highlights in the Readium EPUB reader via Readium Decorations
(restore-on-open + apply + remove), using the WI-8a text-quote re-anchoring path
(no XPath→CFI). Author = worktree implementer + orchestrator fixes; auditor =
separate `codex exec` process (rule-48 author/auditor separation).

Changed files: `vreader/Services/Reader/ReadiumDecorationHighlightAdapter.swift`
(new), `vreader/Views/Reader/ReadiumEPUBHost.swift`,
`vreaderTests/Services/Reader/ReadiumDecorationHighlightAdapterTests.swift` (new).

## Round 1 — 0 Critical / 0 High / 0 Medium / 3 Low

| File | Severity | Issue | Resolution |
|---|---|---|---|
| ReadiumDecorationHighlightAdapter.swift | **Low** | A record with an href but EMPTY `selectedText` built a decoration with `text.highlight = nil` — Readium re-anchors from the text quote (or a CSS-selector/fragment we don't supply), NOT href/progression alone, so it's a silent no-op + log noise. | FIXED — `decoration(for:)` now requires a non-empty (trimmed) `selectedText` AND a spine href; otherwise SKIP. Empty + whitespace-only skip tests added/inverted. |
| ReadiumEPUBHost.swift (`ReadiumReaderCoordinator.init`) | **Low** | `highlightAdapter` had a default-arg `= ReadiumDecorationHighlightAdapter()`. Production passes the host-owned adapter (identity correct today), but the default left a footgun: a future call site could construct a coordinator that `detach()`es a different adapter than the one attached to the navigator. | FIXED — removed the default; the param is explicit. 5 WI-5-era test sites updated to pass a throwaway adapter. |
| docs/architecture.md | **Low** | Stale: said "Highlights / search / TTS land in WI-8…WI-10" and didn't document the new `ReadiumDecorationHighlightAdapter` / Decorations path. | FIXED — architecture.md doc-sync commit documents restore/apply/remove via Readium Decorations + text-quote re-anchoring. |

## Confirmed by the audit (no action)

- **No retain cycle**: Readium stores value-type `Decoration`s and only registers callbacks if `observeDecorationInteractions` is called (this adapter never does); `EPUBNavigatorViewController.delegate` is weak; the adapter's strong navigator ref is dropped in `detach()` (called from `dismantleUIViewController`).
- **Adapter identity correct in production**: the host `@State` adapter is passed to both `HighlightCoordinator` AND `ReadiumNavigatorRepresentable` → `ReadiumReaderCoordinator` (same instance, so `detach()` clears the attached navigator).
- **Restore/attach is order-independent**: calls before `attach` update the in-memory set; `attach` re-submits. Attach-before-restore → an empty apply then a full apply (acceptable).
- **`.readerHighlightRemoved` payload** is correctly read from `notification.object as? String` (matches `HighlightCoordinator.deleteHighlight`).
- **Ignoring `forHref` on restore** is consistent with Readium's book-wide decoration model (the navigator only renders decorations whose locators fall on visible spine items).
- **Strict-concurrency posture** acceptable under the `complete` build.
- **New-highlight-from-Readium-selection scoped out** (documented follow-up) does not break restore/apply/remove parity for this WI.

## Verdict

**ship-as-is.** One audit round; 0 Critical/High/Medium; all 3 Low fixed. Test
gate green: 69 tests / 4 suites (pure decoration mapping incl. href precedence,
empty/whitespace skip, CJK, nil progression, tint mapping; set-rebuild via a
fake `DecorableNavigator`).

## Gate-5 device finding → round-2 audit (the migration href-mismatch)

Device verification (Gate 5, iPhone 17 Pro Sim, v3.40.23) surfaced a defect that
both the unit tests AND the round-1 audit missed: a legacy EPUB highlight stores
its anchor href OPF-relative (`chapter1.xhtml`), but Readium's reading-order
spine href is container-relative (`OEBPS/chapter1.xhtml`). The decoration's
locator href matched no spine resource, so Readium **silently failed to render**
the restored highlight — the highlight-parity gate (Risk 1) was not actually met
despite green tests.

**Fix (commit 139bc181):** the adapter resolves the stored href against the
publication's reading-order spine hrefs (`publication.readingOrder.map(\.href)`,
threaded into `attach(navigator:spineHrefs:)`) via a pure
`resolveHref(_:against:)` (exact → unique-suffix → unique-basename). Re-verified
on device: the legacy highlight `"raph of the fir"` renders as a yellow Readium
decoration on the re-anchored text quote
(`dev-docs/verification/artifacts/feature-42-wi8-readium-highlight-restore-20260529.png`).

**Round-2 audit of the fix:** 1 Medium — basename fallback could mis-anchor when
≥2 spine resources share a basename across directories. FIXED — both the suffix
AND basename branches now require a UNIQUE match (a collision returns nil rather
than guessing). Regression tests added (ambiguous-suffix→nil, ambiguous-basename
→nil, unique-deeper-suffix→resolves). No other new Critical/High/Medium.

This is why device verification is a binding gate: the green unit suite + a clean
code audit still shipped a non-rendering parity gate until the real navigator
exercised the actual spine-href format.

## Scope note carried forward

Creating a NEW highlight from a Readium text selection (selection gesture →
`HighlightRecord`) is OUT of scope for WI-8 (Readium owns its WebView selection;
no equivalent selection→record plumbing exists). Restore/apply/remove of records
created by other means (or the DebugBridge `highlight` command) is complete — the
parity-gate deliverable. The selection→create path is a documented follow-up.
