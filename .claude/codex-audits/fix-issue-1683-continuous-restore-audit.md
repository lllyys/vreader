---
branch: fix/issue-1683-continuous-restore
threadId: 019eb6e1-53d3-7970-ba42-61764e645b53
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Bug #349 — Codex audit

Fix: `EPUBFileLoader.restorePosition` resolves the saved href through
`EPUBScrollAnchorResolver.matchIndex` (moved to Services/EPUB; gains
the nil-on-miss variant + a percent-encoding-normalized retry) and
returns the spine's canonical href so every downstream exact match
agrees. Runner: `scripts/run-codex.sh`. Round-2 session: `019eb6e9-97e7-7ec0-893a-dcaed236b06e`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| Fragment-bearing saved hrefs ("ch1.xhtml#p12" — Readium stores locator hrefs verbatim) still fell through to the cover | Medium | **Fixed** — the fragment strips before every match pass; tests for plain/container-relative/encoded-CJK + fragment. |
| The decoded retry could false-positive when distinct manifest entries collapse after percent-decoding ("a%2Fb.xhtml" vs "a/b.xhtml") — `firstIndex` guessed | Medium | **Fixed** — the decoded passes require a UNIQUE match (exact then suffix); ambiguity falls back to the first-spine default instead of guessing. Collision test pins nil. |

Round 1 explicitly confirmed: "./" prefixes covered by the suffix rule,
mixed-case escapes decode correctly, the canonical-href return is right
for the downstream exact-equality consumers, the move is layer-clean,
and `anchorIndex` keeps its 0-on-miss contract for the existing caller.

## Round 2 (verify)

Clean — both fixes + their pins confirmed.

## Verdict

ship-as-is. 26 tests green across the 5 suites (loader cross-engine
restore incl. encoded CJK; resolver fragments/ambiguity/encoding; the
pre-existing loader + resolver suites). Device: a Readium-paged-saved
position (spine 42, 4%) reopened in scroll mode materializes the window
at [41,42,43] with the intra-chapter offset restored and the chrome
agreeing — pre-fix it opened at the cover with the chrome disagreeing.
