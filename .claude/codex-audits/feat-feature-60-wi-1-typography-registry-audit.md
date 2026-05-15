---
branch: feat/feature-60-wi-1-typography-registry
threadId: 019e2dbe-b40a-7973-b993-19b9fadfb889
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Gate 4 implementation audit — Feature #60 WI-1 (typography registry — Swift API portion)

Per `.claude/rules/47-feature-workflow.md` Gate 4. Audit of the Swift
API portion of WI-1: `ReaderTypography` namespace, `ReaderFontFamily`
enum extension (3 → 5 cases), and downstream compile-fix updates at
the 4 call-sites switching on `ReaderFontFamily`.

## Scope

Branch: `feat/feature-60-wi-1-typography-registry`

**This PR ships the Swift API portion only.** Font binaries
(Source Serif 4 + Inter `.otf` files) are NOT bundled in this WI —
they require external asset fetching with licence verification,
deferred to a separate **WI-1b** manual-ops step. The plan author
flagged this in the WI's est line ("font binary excluded"). The
Swift API's fallback chain handles the not-yet-bundled case
gracefully so WI-5/WI-6 consumers can compile against the registry.

### Source (5 files)

- `vreader/Models/TypographySettings.swift` — `ReaderFontFamily`
  extended from `.system` / `.serif` / `.monospace` to add
  `.sourceSerif4` and `.inter`. Doc-comment explains the WI-1b
  deferral and the per-case fallback chain.
- `vreader/Services/ReaderTypography.swift` (new) — stateless
  namespace. Two static methods: `body(for:size:) -> UIFont` (never
  nil, with canonical-PostScript-name lookup first then fallbacks)
  and `cssFontStack(for:) -> String` (EPUB CSS injection).
- `vreader/Models/ReaderTheme.swift` — `fileprivate cssFontStack`
  delegates to the canonical entry point in `ReaderTypography`. WI-4
  will retire this delegate when it migrates the EPUB CSS injection
  to call `ReaderTypography` directly.
- `vreader/Services/ReaderSettingsStore.swift` — `uiFont` and
  `txtViewConfig` now resolve via `ReaderTypography.body(...)` for
  the 5-case enum.
- `vreader/Views/Reader/ReaderSettingsPanel.swift` — `previewFont`
  switch resolves `.sourceSerif4` / `.inter` via the registry.

### Tests (2 files)

- `vreaderTests/Services/ReaderTypographyTests.swift` (new) — 14
  tests in 2 suites: registry returns UIFont for every case +
  respects point size; per-family fallback assertions (sourceSerif4
  → serif; inter → sans); legacy-family preservation; CSS stack
  contents; ReaderFontFamily 5-case Codable + legacy + new rawValue
  decode/encode.
- `vreaderTests/Models/TypographySettingsTests.swift` — updated the
  pre-existing `fontFamilyAllCases` test (3 → 5 cases). Per the
  Codex audit Medium #2 — this pre-existing assertion would have
  failed the unit gate without an update.

## Round 1 findings

Zero Critical / High. Two Mediums.

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `vreader/Services/ReaderTypography.swift:64` | Medium | `.sourceSerif4` lookup omitted the canonical Adobe PostScript name `"SourceSerif4-Regular"`. `UIFont(name:size:)` expects a fully-qualified face name; Source Serif 4 static releases ship under that name. The prior chain would have stayed on Georgia even after WI-1b bundled the binary. | **Fixed.** Extended chain: `"SourceSerif4-Regular"` (canonical PostScript) → `"SourceSerif4"` (family) → `"Source Serif 4"` (display) → `"SourceSerifPro-Regular"` (older typeface PostScript) → `"Source Serif Pro"` (older typeface display) → Georgia → system. Inter: `"Inter-Regular"` (PostScript) → `"Inter"` (family) → system. Inline comment cites Apple docs. |
| 2 | `vreaderTests/Models/TypographySettingsTests.swift:152` | Medium | Pre-existing assertion `ReaderFontFamily.allCases.count == 3` would have failed the unit gate against the extended enum, breaking the broader suite. | **Fixed.** Updated to `count == 5` with `.contains(.sourceSerif4)` and `.contains(.inter)` assertions. Doc-comment explains the WI-1 additive extension. |

## Round 2 verification

Codex final verdict (quoted from thread `019e2dbe-b40a-7973-b993-19b9fadfb889`):

> Gate 4 passes on this round. I don't see any remaining open
> Critical/High/Medium findings in the audited WI-1 scope.
>
> The two prior Mediums are resolved: [ReaderTypography.swift]
> now tries the canonical static face names first, including
> `SourceSerif4-Regular`, plus sensible legacy aliases before
> falling back. [TypographySettingsTests.swift] now matches the
> 5-case enum shape, so the pre-existing unit suite is coherent
> again.
>
> The rest of the earlier audit still stands as acceptable for
> foundational dormant infra: backward compatibility is intact,
> I don't find any missed `ReaderFontFamily` switch fallout in
> source, and the temporary `ReaderTheme.cssFontStack` delegate
> remains a reasonable transition.

## Cross-checks performed by Codex

- **Non-exhaustive `ReaderFontFamily` switches**: zero missed sites
  in source after the enum extension. All 4 compile-fix targets
  (ReaderTheme + ReaderSettingsStore × 2 + ReaderSettingsPanel)
  delegate to ReaderTypography uniformly.
- **Backward compat**: additive enum extension; existing per-book
  persisted rawValues continue decoding.
- **Concurrency**: ReaderTypography is stateless namespace; no
  shared mutable state, no `@MainActor` needed.
- **Delegate stability**: `ReaderTheme.cssFontStack` delegate is
  an acceptable transition state; WI-4 will retire it.

## Test gate

```
xcodebuild test -only-testing:vreaderTests/ReaderTypographyTests \
                -only-testing:vreaderTests/ReaderFontFamilyExtensionTests \
                -only-testing:vreaderTests/TypographySettingsTests
```

Result: 45 tests in 3 suites, all passing. ** TEST SUCCEEDED **

## Verification gap noted (deferred to WI-1b)

When WI-1b ships the `.otf` binaries, a follow-up test will assert
the canonical PostScript name `"SourceSerif4-Regular"` is preferred
over the Georgia fallback (i.e., the registered face wins). For
WI-1 (Swift API only) the fallback chain itself is what's tested.
Codex accepted this deferral explicitly.

## Summary verdict

**Ship-as-is.** Gate 4 clean after 2 rounds. WI-1's Swift API
portion ships as dormant foundational infra; WI-5 (TXT/MD theme)
and WI-6 (chrome) can be authored against `ReaderTypography`
without further plumbing. WI-1b adds the font binaries separately
under manual ops with licence-verification context.
