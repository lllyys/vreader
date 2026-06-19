---
branch: feat/feature-112-android-md-reader
threadId: 019ee0b0-799e-7912-8960-7b2688252bd8
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #112 (Android Markdown reader)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only sandbox) audited the WI-1 diff:
`MarkdownRenderer.kt` (new), `TxtReaderActivity.kt` (format-aware `TxtBody`),
`MainActivity.kt` (md route), + the JVM/Robolectric/instrumented tests.

## Round 1 — 1 Medium + 1 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| `MarkdownRenderer.kt` parseStar | **Medium** | empty closing match (`******`, `before ****** after`) rendered as an empty string instead of literal — violates the "unknown degrades to literal" contract, drops visible separator runs | **Fixed**: `parseStar` now returns the marker literally and advances when `inner.isEmpty()` (mirrors underscore's `j > i + 1`). Tests: `sixStars_rendersLiterally`, `emptyEmphasisRunBetweenWords_preserved`, `fourStars_rendersLiterally`. |
| `MarkdownRenderer.kt` parseStar / parseUnderscore | Low | closing-delimiter search ignored backslash escapes — `**a\** b**` / `_a\_ b_` closed at the escaped delimiter | **Fixed**: added `findUnescaped()` / `isEscaped()` (odd-backslash parity); `parseStar`'s close search and `parseUnderscore`'s scan now skip escaped delimiters. Tests: `escapedClose_doesNotTerminateBold`, `escapedClose_doesNotTerminateItalicUnderscore`. |

Clean areas confirmed round 1: `parseInline` advances on every branch (no infinite
loop), recursion operates on strictly shorter substrings, no Android-framework calls in
the pure-JVM renderer, `TxtBody`'s format switch is Compose-safe, per-visible-chunk
render is acceptable for ≤4k-char chunks, `MainActivity` routing is exhaustive over
`BookFormat`.

## Round 2 — CLEAN

> "Both round-1 findings are resolved … Empty star emphasis now preserves literal
> markers and advances, so no delimiter loss or loop. Escaped star/underscore closers
> are skipped via odd-backslash parity, with no off-by-one or infinite-loop issue found.
> Existing bold/italic/nested emphasis paths still look intact." — no new Critical/High/Medium.

## Verdict

**ship-as-is.** 30 JVM `MarkdownRendererTest` + 1 Robolectric `MdResumeTest` green in
the unit gate; 3 instrumented `MdReaderRenderTest` + the existing `TxtReaderActivityTest`
green on emulator-5554.
