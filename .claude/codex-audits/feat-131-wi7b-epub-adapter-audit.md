---
branch: feat/131-wi7b-epub-adapter
threadId: 019f5fd2-round3
rounds: 3
final_verdict: follow-up-recommended
date: 2026-07-14
---

# Gate-4 audit — feature #131 WI-7b (Android EPUB bilingual DOM-injection adapter)

Independent Codex review (gpt-5, high effort, read-only sandbox, `scripts/run-codex.sh`) of the
WI-7b production code: `EpubBilingualJs.kt` + `EpubBilingualInjectJs.kt` (the JS builders),
`EpubBilingualController.kt` (the Mutex + session-token single owner), `EpubChapterTextProvider.kt`
(the href-keyed provider), and the ADDITIVE bilingual wiring in `ReaderActivity.kt`
(`buildBilingual` / `evalOnMain` / `scheduleBilingual` / `awaitBilingualHydration` /
`observePosition` / `observeDisplaySettings` / `onDestroy` + the `@VisibleForTesting` seams).

Three rounds, per rule 47/55 (≤3). Threads: r1 `019f5fb3-5400-7140-b75b-2d81825dda59`,
r2 `019f5fc0-03cf-7dd1-8243-67203428494e`, r3 (this file's thread). Full transcripts in
`.reports/wi7b-audit.txt` / `-r2.txt` / `-r3.txt`.

## Round 1 — 4 High / 2 Medium / 2 Low → ALL fixed

- **H1** `onEpubBlocksEnumerated` inert ⇒ probe expected-count always 0 ⇒ probe gating defeated.
  Fixed: the controller tracks the last-applied NONBLANK count per unit (`expectedCountFor`); the
  host probe compares against that, not the (inert) VM render state.
- **H2** awaiting translation inside the position collector blocks chrome + risks A→B cross-inject.
  Fixed: bilingual re-apply runs on a DEDICATED cancellable `bilingualJob` (a new resource/enable
  cancels the prior apply); the position/display collectors never suspend on translation.
- **H3** token not re-checked after every suspend; `reapplyIfNeeded` captured a fresh token;
  `onDestroy` didn't cancel/join. Fixed: one captured token threaded through style/enum/cache/
  provider-translate/commit/inject with a re-check after each; `reapplyIfNeeded` preserves the
  probe's token; `onDestroy` cancels the job + bumps the session before `super.onDestroy()`.
- **H4** persisted-enablement hydration race. Fixed: the open-time apply awaits the VM's persisted
  enabled+language hydration before applying.
- **M1** main-thread dispatch assumed + `runCatching` swallowed cancellation. Fixed: `evalOnMain`
  = `withContext(Dispatchers.Main.immediate)` + rethrows `CancellationException`.
- **M2** style survival across a reflow + blank-count probe skew. Fixed: style re-ensured on every
  reinject; the probe uses the nonblank injected count.
- **L1** trusted pre-existing book-supplied bid (duplicate). **L2** enable seam waited only on
  `enabled` + silent timeout. Both fixed (dup-bid guard; await enabled+language, throw on timeout).

## Round 2 — 1 High / 3 Medium → ALL fixed

- **H** stale/wrong-language decorations not reconciled. Fixed: `bumpSession()` clears
  `appliedCount`; a LANGUAGE change clears the old-language DOM (shutdown = bump + clear) before
  the new apply; the inject now takes the FULL enumerated id list and RECONCILES (removes the owned
  decoration of any enumerated block not translated this pass — a now-blank/absent block or a
  shorter language set).
- **M** `__proto__` bid still broken with `{}`. Fixed: ids/texts passed as two index-paired JSON
  ARRAYS (a `__proto__` is an ordinary element — no map-collapse, no prototype pollution); the
  enumerate dup-guard uses an array + `indexOf`.
- **M** final inject lacked a token re-check. Fixed: re-check the captured token after the inject
  eval before updating `appliedCount`.
- **M** RTL targets had no DOM direction. Fixed: `dir=rtl/auto` on the translation nodes via a
  `targetIsRtl` seam.

## Round 3 — 2 High / 2 Medium → 2 fixed in-scope, 2 deferred to WI-9

**Fixed in WI-7b:**
- **H (finding 1)** cancelled/failed clear treated as success during a language change. Fixed:
  `clear()` returns true only when `clearScript` verified 0 remaining; `shutdown()` rethrows
  `CancellationException` + returns the verified result; ReaderActivity advances
  `bilingualLang`/`bilingualUnit` ONLY after a verified clear (a cancelled/failed clear leaves the
  transition pending → retried next schedule).
- **M (finding 3)** cross-spine ownership — a slow apply enumerating chapter A could inject into
  chapter B. Fixed: the enumerate returns `{doc, blocks}` where `doc` = `document.location.href`;
  the controller carries `doc` into the inject, which aborts (return -1) if the live document
  changed; the controller treats -1 as an abort (no probe update).

**Deferred to WI-9 (entry wiring + full acceptance — requires edits OUTSIDE this WI's write-set):**
- **H (finding 2)** on a language switch, retained cross-spine SCROLL-mode DOMs of OTHER resources
  keep the old language until each is revisited + re-applied. WI-7b's `scheduleBilingual`
  clears+re-applies the CURRENT resource on entry (+ the inject reconciles blank blocks in place),
  so a revisited resource is corrected; the residual is an OFF-screen retained DOM whose eventual
  re-apply fails. A complete fix needs a per-resource decoration-language marker + a cross-spine
  reconcile on every resource entry — behavior WI-9 owns via full acceptance across spines +
  language change. Accepted residual: the visible current resource is always correct; the connected
  test exercises one language.
- **M (finding 4)** `BilingualViewModel.onEpubBlocksEnumerated` is intentionally inert, so
  production `translationsByUnit` never receives EPUB results. The VISIBLE EPUB render is the
  injected DOM (the controller's `expectedCountFor` drives the probe, not the VM slice, which is
  unread for EPUB), so this is an observability gap, not a correctness one for WI-7b. Wiring the VM
  to commit EPUB segments edits `BilingualViewModel.kt` — WI-6/WI-7a-owned, outside the WI-7b
  write-set. WI-9 (which wires the More-menu entry) is the correct home.

## Verdict: follow-up-recommended

The WI-7b deliverable is complete and hardened: JS CSP-safety (no innerHTML, JSON-array
interpolation, CSS.escape fallback, `__proto__`-safe bids), the Mutex + monotonic session-token
single-owner race contract (token re-checked after every suspend incl. inject; a stale token never
becomes an errorUnit; verified clear before teardown; a document-ownership inject guard),
probe-gated re-apply, main-thread-only eval with cancellation preserved, the TXT/MD prefetch path
staying EPUB-free (Medium-1), and additive ReaderActivity wiring (no regression to
position/search/display/TTS). JVM (`EpubBilingualJs`/`Controller`/`ChapterTextProvider`) + a
connected EPUB test (enable injects from seeded cache with ZERO provider calls; disable clears;
re-enable + probe-gated re-apply restore) all green on `emulator-5554`. The two remaining round-3
findings are WI-9-scoped (full acceptance across spines + the VM commit), requiring edits outside
this WI's declared write-set; they are recorded as explicit follow-ups, not open WI-7b blockers.
