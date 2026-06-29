---
branch: feat/feature-126-wi-1-bundle-shell
threadId: 019f1148-4d38-7043-8ffc-f3367a602155
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #126 WI-1 (ship patched bundle + shell + provenance test)

Codex (gpt-5.5/high) audited the hand-written WI-1 surface (the bundle + shell are
byte-identical copies of the WI-0-validated spike assets, not re-audited).

**Findings: none.** Key checks confirmed:
- `FoliateBundleProvenanceTest.kt` fails hard if no candidate asset path exists (no
  silent false-pass), catches any remaining `allow-scripts`, and pins the exact
  patched SHA-256 `aa4327f1…` (the shipped asset hashes to it).
- `reader.html` is inert before WI-3 — the `window.webkit.messageHandlers` shim is a
  no-op while `vreaderHost` is absent (the bridge is wired in WI-3); shipping it +
  the `'unsafe-inline'` shell CSP now is not a WI-1 blocker (no section `allow-scripts`,
  no production bridge yet). WI-3 hardens the shell CSP.
- `android/version.properties` bumps `0.12.1/61` → `0.12.2/62`.

Re-verification: `FoliateBundleProvenanceTest` passes 2/2 via `:app:testDebugUnitTest`.

**Verdict: ship-as-is.**
