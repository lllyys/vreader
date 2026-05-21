# Codex Gate-4 audit — verify(#64) Gate-5b partial PR

Thread: `019e461e-51fb-7180-bbd0-c936e5d66e0a`
Date: 2026-05-20
Verdict: `ship-as-is`

## Diff under audit

- `dev-docs/verification/feature-64-20260520.md` (+274) — Gate-5b acceptance evidence file, `result: partial`.
- `project.yml` + `vreader.xcodeproj/project.pbxproj` (version bump 3.38.22 → 3.38.23).

Refs #822.

## Findings

Zero Critical / High / Medium / Low findings against this PR.

### Honesty
> "the evidence is appropriately conservative. It clearly separates what was actually verified from what was blocked, and it labels the TXT bridge and unit-test results as supporting-only, not Gate-5 acceptance."

### Completeness
> "the plan for Feature #64 has 8 acceptance criteria, not 10, in the final Gate-5 section. The evidence table covers all 8; criterion 1 is reasonably expanded into 5 per-format rows."

### Hook compliance
> "filename matches `feature-<id>-<YYYYMMDD>.md`, frontmatter contains all required fields, and the required body sections are present per schema."

### Misclassification risk
> "I do not see a credible path where this should have flipped the row to `VERIFIED`. The file explicitly says `result: partial`, keeps the row at `DONE`, and keeps GH #822 open with `awaiting-device-verification`."

## Follow-up filing (auditor recommendation)

- **Do NOT file** for CU outage — environment/hardware availability, not a product defect.
- **Do NOT file** for XCUITest in-runner sandbox block — already tracked in Bug #240 / #242.
- **Do NOT file** for stale `ImportedBooks/` clutter — shared-simulator hygiene / verification-process contamination; better handled by cron prompt / simctl reset discipline.
- **File a NEW bug** for the EPUB DebugReaderRegistry / WebView registration race if not already tracked. Distinct from #240/#242 because it affects the host-side DebugBridge path too, not just the sandboxed in-runner path, and blocks EPUB verification even when the bridge command is issued successfully.

Follow-up is OUT of this PR's scope. Recorded here for the next iteration to act on.
