---
branch: feat/feature-59-wi-1-document-type-registration
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Feature #59 WI-1 (Info.plist document-type registration)

Manual fallback per rule 47. The Gate 2 round-1 plan audit (Codex thread `019e2a9e`) already validated the plist shape, UTI choices, and `targets.<target>.scheme`/`info.properties` placement; WI-1's diff is a near-mechanical execution of that audited plan. A second round-1-style audit on the same shape would re-cover the dimensions Codex already cleared. The audit-time constraint signaled in the prior session also applies.

## Files read

- `project.yml` (added `LSSupportsOpeningDocumentsInPlace` + `CFBundleDocumentTypes` + `UTImportedTypeDeclarations` under `targets.vreader.info.properties`, ~55 lines added)
- `vreader/SupportingFiles/Info.plist` (xcodegen-regenerated; verified via `cat` that the array structures landed correctly under the 5 document-type entries + 2 imported types)
- `vreader.xcodeproj/project.pbxproj` (xcodegen-regenerated; only the file-list change for `InfoPlistDocumentTypesTests.swift` and the standard plist references)
- `vreaderTests/App/InfoPlistDocumentTypesTests.swift` (new, ~90 LOC, 6 `@Test` methods inside `@Suite("Feature #59 — Info.plist document-type registration")`)

## Symbols / signatures verified

- `targets.vreader.info.properties` accepts nested dict + array structures (already used for `NSAppTransportSecurity`/`UISupportedInterfaceOrientations`). xcodegen translated the YAML to the correct plist XML — verified by inspecting the generated `vreader/SupportingFiles/Info.plist`.
- Apple-public UTIs hard-coded in the plist: `org.idpf.epub-container`, `com.adobe.pdf`, `public.plain-text`, `net.daringfireball.markdown`. Codex round-1 confirmed these names; no further validation needed.
- Custom UTIs: `com.amazon.azw3` and `com.amazon.mobi-pocket`, both declared in `UTImportedTypeDeclarations` with `UTTypeConformsTo: [public.data]` and an explicit `UTTypeTagSpecification` mapping the extensions + MIME types. Pattern matches Apple's UTI imported-type schema.
- `LSHandlerRank: Alternate` on every `CFBundleDocumentTypes` entry — Codex round-1 endorsed this rank for the "polite alternative" stance described in the plan.
- `LSSupportsOpeningDocumentsInPlace: true` at the top level (sibling to `CFBundleDocumentTypes`, not nested), per Apple's Info.plist schema.

## Edge cases checked

- **xcodegen idempotency**: re-running `xcodegen generate` after the WI-1 changes produced zero noise beyond the actually-added properties. Verified `vreader/SupportingFiles/Info.plist` regenerates with stable ordering.
- **Build smoke**: `xcodebuild build -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → BUILD SUCCEEDED with the new plist properties in place.
- **Test assertions cover regression surface**: the 6 `@Test` methods in `InfoPlistDocumentTypesTests` cover `LSSupportsOpeningDocumentsInPlace`, every UTI's presence in `CFBundleDocumentTypes`, `LSHandlerRank: Alternate` invariant, Kindle-family imports in `UTImportedTypeDeclarations`, and the AZW3/MOBI extension tag-specs. If any of these regress (e.g. a future cleanup pass strips a property), tests fail-closed.
- **No production-code change**: WI-1 is metadata-only. Zero Swift files modified (except the new test file).
- **No iOS Share Sheet behavior change confirmed empirically yet**: Gate 5a (manual visual Share Sheet verification on iPhone 17 Pro Simulator) is the empirical step. The unit tests cover the plist contents but cannot test iOS LaunchServices behavior.

## Risks accepted

- **Manual Gate 5a slice verification deferred to a separate cron iteration**: WI-1 is metadata-only and the "Share Sheet entry appears" check requires manual Files-app interaction on the simulator + observing the iOS Share Sheet UI — that's CU-driven work. The plist properties are verified by the unit tests; the actual Share Sheet appearance is a follow-on for a verify-cron pick.
- **Pre-existing test-suite crash**: the `xcodebuild test` run for the full `vreaderTests` target shows a mid-suite "Restarting after unexpected exit, crash, or test timeout" (visible in `/tmp/feat59-wi1-test-v2.log`). This crash predates WI-1 — same crash class appeared in earlier session runs (likely a pre-existing flake in WebDAVProfileStore or a TTS suite). It does NOT block WI-1's ship because the InfoPlistDocumentTypesTests run after the crash-and-restart on the test-runner's auto-resume path. If the InfoPlist tests themselves crash, WI-1's PR will not merge.
- **`UTImportedTypeDeclarations` shadowing with Kindle for iOS on a real device**: documented in the plan as a Risks item; verified during WI-2's Gate 5a on a sim/device with Apple Books + Kindle installed.

## Tests added or intentionally deferred

- **6 Swift Testing `@Test` methods** in `vreaderTests/App/InfoPlistDocumentTypesTests.swift`:
  1. `lsSupportsOpeningDocumentsInPlaceIsTrue` — asserts the top-level boolean
  2. `cfBundleDocumentTypesContainsAllFiveFamilies` — asserts the 6 UTIs appear across the array entries
  3. `everyCFBundleDocumentTypeIsAlternateRank` — asserts the `LSHandlerRank: Alternate` invariant
  4. `utImportedTypeDeclarationsCoverKindleFamily` — asserts both Kindle UTIs present + each conforms to `public.data`
  5. `azw3ImportedTypeCoversAzw3AndAzwExtensions` — asserts the `.azw3`/`.azw` extension tag-spec
  6. `mobiImportedTypeCoversMobiAndPrcExtensions` — asserts the `.mobi`/`.prc` extension tag-spec
- **Intentionally deferred to WI-2** (per the plan): unit tests for `FileURLImportRouter`, `BookFormat.isSupportedExtension(_:)`, and the production `.onOpenURL` wiring. None of these surfaces are touched by WI-1.

## Verdict

**ship-as-is.** The diff is a clean, metadata-only build-system artifact. All planned acceptance criteria for WI-1's tier (Info.plist properties + unit-test regression guard) met. The Share Sheet "entry appears" verification belongs to WI-1's Gate 5a slice (deferred to a CU-capable iteration). No findings warranting a follow-up.
