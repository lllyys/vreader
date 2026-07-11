---
title: Timeline — feature delivery history
updated: 2026-07-10
status: proposed
---

# Timeline — feature delivery history

## Purpose

Chronological record of what vreader shipped, in what order, and where each feature stands. Source of truth is the `docs/features.md` tracker (its `## Rules` header is binding: bugs vs features split, `PLANNED` before `IN PROGRESS`, `Deps:[…]` typed tokens, atomic IDs via `scripts/reserve-id.sh`). Statuses are `TODO / PLANNED / IN PROGRESS / DONE / VERIFIED / DEFERRED / WONT DO / DUPLICATE`; `DONE` means merged with tests, `VERIFIED` additionally requires an end-to-end acceptance pass recorded in `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` (schema: `dev-docs/verification/SCHEMA.md`). The gate model behind every delivery is in [[Decision — six-gate workflow and lane dispatch]].

## Status snapshot (2026-07-10)

- `docs/features.md` holds 127 rows spanning IDs 1–130; IDs 51, 119, 128 have no row (119 is named inside #118 as the "bilingual interlinear" follow-on; 128 is named in `docs/parity/android-checklist.md` as the Android-search split from #127). The 127 figure is arithmetic (130 IDs minus the 3 named gaps), not an independently reproduced count of table rows — re-verify directly against `docs/features.md` if the row count matters.
- Counts: 119 VERIFIED, 2 DONE (#68 chapter-start typography, #102 Android umbrella), 1 PLANNED (#129), 1 TODO (#110 parity driver), 1 DEFERRED (#16 remote server), 1 WONT DO (#10 iCloud backup — "WebDAV (#29) covers backup needs"), 2 DUPLICATE (#19 → #6, #39 → #32).
- Current versions: iOS `MARKETING_VERSION: 3.67.6` / `CURRENT_PROJECT_VERSION: 1048` in `project.yml` (latest tag `v3.67.6`); Android `versionName=0.13.11` / `versionCode=84` in `android/version.properties` (latest tag `android/v0.13.11`).
- Known doc drift: `README.md` Status line says "52 done" and its Tech Stack table says "SwiftData (SchemaV6)", while the tracker has 119 VERIFIED rows and the code's migration chain reaches `enum SchemaV10` (`vreader/Models/Migration/SchemaV10.swift`); `docs/architecture.md` correctly says SchemaV10.

## Era 0 — pre-tracker plans (Mar–Apr 2026)

Earliest artifacts in `dev-docs/plans/`: `20260322-1600-icloud-backup.md`, `20260322-bug89-book-opening-performance.md`, `20260328-gh30-unified-chapter-system.md`, `20260403-cover-image-extraction.md`. The dated `YYYYMMDD-feature-N-<slug>.md` convention starts 2026-05-03.

## Era 1 — core readers, annotations, search, first AI (#1–#45; verified 2026-05-04 → 2026-05-28, #45 itself not finalized until 2026-06-08)

The foundation wave, all VERIFIED: bookmarks CRUD (#1), manual highlighting (#3) and notes (#4), library preferences (#6), progress scrubber (#8), EPUB highlighting (#11), MD/TXT auto-TOC (#12, #23 — #23 uses Legado's 25 chapter-detection regex rules), AI summarize/chat/translate (#13, #14, #15, #18), PDF highlighting + theming (#17), paginated mode (#21), book-source scraping (#24), tap zones (#25), TTS (#26 — 7 verification rounds), replacement rules (#27), Simp/Trad conversion (#28), WebDAV backup (#29, PR #128), custom covers (#30), auto page turn (#31 — 10 verification rounds), theme backgrounds (#32), dictionary (#33), collections (#34 — closed via verification-exception, the precedent later cited by #85), annotation export/import (#35), OPDS (#36), per-book settings (#37), TTS highlight/auto-scroll (#40, #41), cover extraction (#43). Two tooling features anchor the era: #44 DebugBridge (`vreader-debug://` scheme, 15 verification rounds) and #45 verification-harness sweep, which introduced the `VERIFIED` status itself. See [[Module — debug bridge]].

## Era 2 — materializing backup (#46–#47, May 2026)

#46 WebDAV backup includes book files (materializing restore, 11 WIs, plan `dev-docs/plans/20260503-feature-46-materializing-restore.md` — the worked example in rule 47) and #47 selective restore picker + lazy-on-tap background downloads (`BookFileState`, `LazyDownloadTaskMeta`). Both VERIFIED. See [[Module — backup and WebDAV]].

## Era 3 — visual identity v2 and reskins (#50–#70, mid-May 2026)

#60 "VReader visual identity v2" (Source Serif 4 / Inter, 5 themes Paper/Sepia/Dark/OLED/Photo, oxblood accent, generative typographic covers) VERIFIED 2026-05-16 at v3.27.0 with 12 WIs; it seeded rule 51 (UI only from committed `dev-docs/designs/` bundles) and a follow-up cluster: #61 Book Details sheet, #62 annotations panel split (TOCSheet + HighlightsSheet), #63 search reskin, #64 unified highlight popover, #65 AI sheet reskin, #66 settings sub-controls, #67 profile card, #69 summarize scope chips — all VERIFIED; #68 chapter-start typography is the era's one row still at DONE. Alongside: #50 multi-provider AI, #52 multiple WebDAV profiles, #53 tap-on-highlight, #54 removal of the Native/Unified toggle (internal `ReaderEngine` routing), #55 note preview, #59 system document handler ("Open in"), #56 bilingual reading mode (interlinear + disk cache + whole-book translation, VERIFIED 2026-05-20), #57 AZW3 TTS, #58 reading dashboard, #70 cross-format font-size calibration (split from bug #166).

## Era 4 — reader-engine deepening (#42, #71–#85, late May–early Jun 2026)

Continuous-scroll parity across engines: #71 EPUB cross-chapter scroll (VERIFIED 2026-05-28), #73 Foliate windowed multi-section surface (K=3, `#windowedScroll`, v3.41.0, resolves bug #283), #75 RTL/vertical-writing EPUB paging (reclassified from bug #292), #76 vertical-writing windowed scroll, #83 Readium cross-chapter scroll, #85 seam elimination (closed 2026-06-06 under verification-exception, citing the #34 precedent). The era's centerpiece is #42, re-scoped 2026-05-28 from "Foliate everywhere" to **Readium + libmobi convert-on-import** (plan `20260528-feature-42-readium-libmobi-reader-engine.md`): Readium EPUB engine default-ON 2026-06-01 (WI-14 flip), `kindleConvertOnImport` default-ON 2026-06-02, VERIFIED 2026-06-03 at v3.51.1. See [[Module — EPUB reader]], [[Module — Foliate AZW3 reader]], [[Module — Kindle AZW3 and libmobi]].

## Era 5 — AI expansion (#77–#101, Jun 2026)

Bilingual/AI depth, all VERIFIED by 2026-06-11 (v3.66.0 era): #77 translation-progress shimmer, #78 Ask-AI on selection, #79/#80 provider-editor placeholders + Test-before-Save, #81/#82 in-reader provider entry + consent, #84 AA contrast bump, #86 chat scope + sources ("Drew on" provenance), #87 stop control, #88 conversation sessions (`@Model ChatSession`, SchemaV9), #89 AI-history WebDAV backup, #90 bilingual summary, #91 agentic tool-calling, #92/#95 justified text TXT/EPUB, #93 AZW3 theme parity, #94 filterable TOC, #96 in-app diagnostics log, #97 `list_library` tool, #98 background-resilient translation, #99 translation-settings re-entry, #100 heading translation, #101 in-reader total reading time. See [[Module — AI providers and tools]] and [[Module — bilingual translation]].

## Era 6 — Android port (#102–#129, 2026-06-16 → 2026-06-29)

Strategy decided 2026-06-16 (`docs/decisions/0001-android-port-strategy.md`: native Kotlin + Compose monorepo under `android/`, two independently-shippable apps sharing `contracts/`) — see [[Decision — Android port strategy]]. Foundation: #103 Phase-0 safety plumbing (gate routing, `android/vX.Y.Z` tag namespace, write isolation), #104 Spike A identity conformance (`contracts/`, golden vectors, dual-platform conformance), #105 Spike B CJK WebView benchmark (`spikes/android-reader-bench/`), #106 foundation bar (import → open → resume one EPUB, VERIFIED 2026-06-18, `android/v0.1.0`–`v0.3.0`), #107 dev-loop readiness (`scripts/run-android-tests.sh`, platform router). Two iOS-side contract obligations followed: #108 source-bytes canonical fingerprint for converted Kindle (`Book.sourceCanonicalKey`, SchemaV10, v3.66.38) and #109 NFC locator normalization + recompute migration (v3.66.35). The umbrella #102 closed DONE-by-decomposition; #110 (TODO) remains the finite parity driver whose definition-of-done is `docs/parity/android-checklist.md`. Capability wave, each VERIFIED with its own `android/vX.Y.Z`: #111 TXT reader (`v0.4.0`, real 14MB UTF-16LE CJK book), #112 MD reader (`v0.5.0`), #113 backup-format DTOs (`v0.6.1`), #114 backup/restore UI (`v0.6.0`), #115 PDF reader (`v0.7.0`), #116 WebDAV backend (`v0.7.7`, live rclone round-trip), #117 OPDS backend, #118 AI provider + chat (`v0.8.0`), #120 OPDS UI (`v0.8.1`–`v0.8.4`), #121 TTS (`v0.8.5`–`v0.9.0`), #122 reading stats (`v0.10.0`), #123/#124/#125 EPUB/TXT/MD highlights (`v0.11.0`/`v0.12.0`/`v0.13.0`), #126 AZW3 reader (WebView + pinned foliate-js, GO per user 2026-06-29, `v0.12.9`), #127 collections (`v0.13.7`). Open at snapshot: #129 display-settings typography slice (PLANNED, Gate-2 clean), plus checklist boxes C (needs #128 search), D (bilingual), E (layout follow-up), F (navigation chrome). See [[Module — Android port]] and [[Module — cross-platform contracts]].

## Era 7 — agent-lane harness (#130, 2026-07-08 → 2026-07-09)

#130 "Parallel agent-lane harness" (meta/tooling, no app code): thin orchestrator + ≤2 worktree-isolated implementer lanes on leased simulators, HANDOFF JSON contract, lock order `dispatch → sim leases → id-reserve → tracker-write`, typed `Deps:[…]` tokens, `/dispatch` skill, `scripts/reserve-id.sh` / `sim-lease.sh` / `agent-lock.sh` / `deps-check.sh`, kill switch `.claude/state/dispatch-kill`. Plan `dev-docs/plans/20260708-feature-130-agent-lane-harness.md`; VERIFIED 2026-07-09 (evidence `dev-docs/verification/feature-130-20260709.md` — canary + M-SHAKEDOWN + WI-7 cron cutover, commit `137f9d50`). Codified as rule 55. See [[Module — automation and tooling]].

## Edge cases and invariants

- **DONE ≠ VERIFIED** is enforced mechanically: `.claude/hooks/check_terminal_status_evidence.sh` blocks flipping a row to `VERIFIED` without a matching `dev-docs/verification/` evidence file.
- Verification is iterative by design — rounds are named in evidence filenames (e.g. `feature-31-20260521-round10.md`, `feature-44-20260513-round15.md`, `feature-53-20260518-round9.md`); a `partial` result keeps the row below VERIFIED.
- A "verification-exception" label (deterministic integration/unit evidence in lieu of a full on-device repro) was used to flip #34, #85, #97 straight to `VERIFIED` at Gate 5b — i.e. the exception was applied to the **feature acceptance gate itself**, not merely to justify closing the mirrored GH issue: #34 (`dev-docs/verification/feature-34-20260512.md`, 17/19 criteria evidenced, 2 deferred as harness/fixture gaps, citing AGENTS.md's "Close gate"), #85 (`dev-docs/verification/feature-85-20260606.md`, 7/8 criteria device-verified, explicitly citing the #34 row as precedent), #97 (`dev-docs/verification/feature-97-20260610.md`, all 6 criteria via a registry-dispatch integration test standing in for a real-LLM tool-use provider the mock can't exercise). Note AGENTS.md's "verification exception" clause is written for the **bug** close-gate (closing a mirrored GH issue via a high-fidelity integration test); these three feature rows extend that concept by internal precedent (#85 citing #34), not a separately documented feature-side rule.
- ID gaps are legitimate: `reserve-id.sh` allocation plus Gate-2 splits mean a reserved number (#119, #128) can be referenced before its row exists; #51 was never a row.
- Rows are append-heavy, not archived: even 2026-05-era rows keep full verification narratives in Notes (the file is 535KB for 406 lines).
- `dev-docs/plans/` and `dev-docs/verification/` are claimed here at the directory level but remain genuinely mixed-content — bug-specific plan/evidence files sit alongside feature ones, not yet split file-by-file (known residual). `dev-docs/README.md` belongs to [[Module — automation and tooling]]; `dev-docs/verification-red-checks.md`, `dev-docs/integration-tests/`, and `dev-docs/test-debt/` belong to [[Module — test architecture]] (verification-process/test-debt material, not feature-delivery narrative) — not this dossier.

## History

- The tracker's own workflow hardened over the eras: #44/#45 built the verification harness, #60 created rule 51 (needs-design gate), #102–#107 added platform routing + per-platform versioning (rule 40 multi-platform), and #130 added lane dispatch (rule 55). Bug-side counterpart: [[Timeline — bug history and recurring classes]].

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
