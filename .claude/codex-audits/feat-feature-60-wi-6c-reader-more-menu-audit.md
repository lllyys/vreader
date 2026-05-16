---
branch: feat/feature-60-wi-6c-reader-more-menu
threadId: 019e306d-7abe-7401-aac9-ae2c0cf16607
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-16
---

# Gate 4 — Codex implementation audit: feature #60 WI-6c (reader More-menu popover)

Independent Codex MCP audit (`sandbox: read-only`) of the WI-6c diff:
the reader "More" menu as an anchored popover (`ReaderMorePopover`),
replacing the WI-6b interim `⋯` → settings-sheet wiring.

## Round 1 — findings

| file:line | severity | issue | fix |
|---|---|---|---|
| `ReaderMoreMenuRow.swift` / `ReaderMorePopover.swift` / `ReaderContainerView+Sheets.swift` | **High** | Bilingual row diverged from the committed design — `vreader-more.jsx` draws it as an inline toggle with active tint + "English ↔ Chinese" sub-detail; the implementation rendered it as a chevron tap row with static sub-detail. That is self-designed UI under rule 51. | **Fixed** — omitted the Bilingual row from WI-6c entirely; filed GH #790 (`needs-design`) for the row + its missing backing toggle feature. Popover now ships 5 designed-and-buildable rows. |
| `ReaderMorePopover.swift:206` | **Medium** | `popoverBackground` branched only on `isDark`, so the Photo theme got opaque `#2a2724`; design note §2 specifies the translucent `rgba(20,16,12,0.92)` so the popover stays legible over an arbitrary background image. | **Fixed** — `popoverBackground` now branches on `theme.usesBackgroundImage` first → `Color(red:20/255,green:16/255,blue:12/255).opacity(0.92)`. The notch reuses the same accessor, so it stays in sync. |
| `ReaderMorePopover.swift:103` | **Low** | The notch was a plain triangle `Shape`; the design draws a rotated square with a two-sided hairline. Fidelity regression. | **Fixed** — reverted to a 12×12 `Rectangle` with stroke, `.rotationEffect(.degrees(45))`, placed behind the card so only the two upward-pointing edges show (matching the design's `box-shadow: -1px -1px`). The triangle `Shape` removed. |
| `ReaderContainerView.swift:149,202` | **Low** | `showMorePopover` was not cleared on every chrome-hide path — the "Hide toolbar" accessibility action calls `toggleChrome()` directly, leaving `showMorePopover == true`; re-showing chrome would resurrect the popover. | **Fixed** — `toggleChrome()` now clears `showMorePopover` whenever it hides the chrome. It is the single chrome-toggle path, so both the content-tap observer and the accessibility action are covered. |
| `ReaderMorePopover.swift` | **Low** | File at 312 lines, over the ~300-line guideline. | **Fixed** — split: `ReaderMorePopover.swift` (main view, 229 lines) + new `ReaderMorePopoverParts.swift` (`ReaderMoreToggle` + `ReaderMoreMenuActionObservers` + the View extension, 97 lines). |

No Critical findings. Round 1 also explicitly confirmed clean: the row
order/divider/labels, the Book Details interim routing, the Share-sheet
hookup, the auto-turn interval clamping, the notification round-trip
(`ReaderMoreMenuRow.notification` ↔ `init?(notification:)`), and
`.onReceive` observer lifecycle. No Swift 6 actor-isolation or
retain-cycle problem found.

## Round 2 — re-verification

Codex re-audited the post-fix worktree: **zero findings**. All five
round-1 findings confirmed resolved on disk — the Bilingual row removed
+ documented + pinned-absent by tests, the 5-notification surface
consistent, the rotated-square notch restored, the Photo surface
special-cased, `showMorePopover` cleared on chrome hide, and both files
under the size guideline.

## Resolution summary

All 5 findings (1 High, 1 Medium, 3 Low) **fixed** in-branch before the
final verdict — no accepted-with-rationale, no deferred. The deferred
Bilingual row is the only product follow-up, tracked in **GH #790**
(`needs-design` — needs a backing persistent-bilingual-mode feature +
design confirmation before the row can be re-added). GH #789 separately
tracks the undesigned Book Details destination sheet (the row ships,
routing to the reader settings panel as the design prototype's own
interim punt).

## Final verdict

**follow-up-recommended.** Codex round 2 returned zero findings and
approves the Gate 4 audit for the shipped scope. The implementation has
no blocker; the single follow-up — the deferred Bilingual row — is
already filed as GH #790. WI-6c ships the 5 designed-and-buildable
More-menu rows.
