---
branch: fix/issue-1538-retranslate-error-message
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Gate-4 audit — Bug #320 (GH #1538): sanitize the chapter re-translate failure message

`ChapterTranslationService.mapTransportError` returned `.providerFailed(String(describing: error))`
for every non-offline failure → for an `AIError.providerError("HTTP 400: {json}")`
that stringified to the enum-case syntax + raw provider JSON, which the
re-translate sheet showed verbatim ("Translation failed: providerError(\"…\")"),
leaking internals + reading as a crash.

## Manual fallback — why
The independent Codex runner wedged repeatedly this session (rule-53 0%-CPU
ghost). Per rule 47, manual fallback for this trivial, fully-tested fix.

## Manual Audit Evidence
- **Fix**: extracted `static func sanitizedProviderMessage(_ error: Error) -> String`
  — a known `AIError` → its `errorDescription` (the SAME sanitized path the
  Chat/Summarize/Translate tabs use), anything else → `localizedDescription`;
  NEVER `String(describing:)`. `mapTransportError`'s two `.providerFailed` cases
  use it. The raw detail is logged once at the catch site (`log.error(... String(describing: error) ...)`, `privacy: .public`) — kept in the log only, per the bug's prescribed fix.
- **No behavior change** to the offline mapping or the `.cancelled`/`ChapterTranslationError` paths.
- **Tests**: `ChapterTranslationServiceTests` 19 green incl. 2 new — `sanitizedProviderMessage_AIError_usesErrorDescription_notRawDump` (asserts no `providerError(` substring + the `AI provider error:` prefix + equals `errorDescription`) and `sanitizedProviderMessage_genericError_usesLocalizedDescription` (asserts `== localizedDescription`, `!= String(describing:)`).
- **Edge**: `AIError` cases whose `errorDescription` is nil fall through to `localizedDescription` (defensive). Swift 6 / @MainActor: the helper is a pure static, no isolation concern.

`ship-as-is`.
