# 24 - Architecture & README Sync

`docs/architecture.md` and `README.md` are checked-in claims about the codebase.
Every PR that changes the code must check whether those claims still hold and
update them in the same PR if not. Drift is a real problem here — the
architecture doc currently still says "SwiftData SchemaV3" even though the
schema migrated to V4 long ago, because nobody owned the line at the time.

## When to update `docs/architecture.md`

Update in the same PR whenever the code change touches any of:

| Trigger                                                 | What to update                                                    |
| ------------------------------------------------------- | ----------------------------------------------------------------- |
| New `@Model` entity or schema version                   | Data Layer section + the schema name in the system diagram        |
| New `Service` (singleton / actor / namespace)           | Services Layer table                                              |
| New `Coordinator` / `ViewModel` shared by ≥2 features   | Coordinator Layer table or Layers section                         |
| New SwiftUI `Environment` key threaded through views    | Note in Layers section + reference in App Layer if injected there |
| New `Notification.Name` on the cross-component bus      | Notification Bus table (name, payload, direction)                 |
| New `HighlightRenderer` adapter or other protocol impl  | Highlight System table or relevant pattern table                  |
| New top-level directory under `vreader/` or `Services/` | File Organization tree                                            |
| New design pattern shared across features               | Key Design Patterns section                                       |
| Performance optimization with cross-cutting impact      | Performance Optimizations table                                   |
| New Android `@Entity` / Room schema, Compose host, repo, DI module, or `contracts/` change (feature #107/#106) | `docs/architecture.md` Android section (once #106 adds it) + the `contracts/` doc if a shared spec changed; an iOS↔Android parity-affecting change updates `docs/parity/` |
| Existing stated fact becomes wrong                      | Fix it. Stale-but-passing doc text is worse than no doc text      |

You don't need to update for: pure bug fixes, edits inside a single existing
file, refactors that don't change the layer/file boundaries, test-only changes,
or new code paths that conform to an already-documented pattern.

## When to update `README.md`

Update in the same PR whenever:

| Trigger                                                    | What to update                                                  |
| ---------------------------------------------------------- | --------------------------------------------------------------- |
| User-visible feature lands or is removed                   | Features section (the right sub-bullet)                         |
| Tech stack change (rendering engine, persistence, etc.)    | Tech Stack table                                                |
| New requirement (Xcode version, iOS target, external dep)  | Requirements section                                            |
| Setup or run instructions change                           | Getting Started block                                           |
| New top-level directory worth highlighting                 | File Organization tree (it's a tree, not the full layout)       |
| Major design decision flips                                | Key Design Decisions bullets                                    |
| Feature or bug counts change meaningfully (≥5 new entries) | Status line at the bottom (`docs/features.md` / `docs/bugs.md`) |
| New developer tool / harness                               | Developer Tools section                                         |

You don't need to update for: minor bug fixes, internal refactors invisible to
the user, doc-only changes elsewhere, or unit test churn.

## Pre-PR self-check

As the last step before opening a PR, run a quick mental audit:

1. **Diff scan.** What did this PR add/remove that's mentioned in either doc?
2. **Claim scan.** For files I touched, do the doc's claims about them still hold?
3. **Cross-reference.** If I added a service/notification/pattern, did I also
   add it to the right table?

If a doc update is needed, it goes in the same PR as a separate commit
(`docs: update architecture.md for <change>` or similar), not as a follow-up.
The version bump tail commit (per `40-version-bump.md`) lands after the doc
update commit.

## Anti-patterns

- **"I'll update the doc later."** Later doesn't happen. The doc rots and the
  next agent inherits stale claims.
- **Updating the doc as the only commit in a separate PR.** Splits the change
  from its evidence; reviewers can't see what triggered the update.
- **Adding a service to the Services Layer table without describing its
  purpose.** A bare row is no better than missing — the table's value is the
  one-line "what does this do" column.
- **Bumping the feature count in README without updating ****`docs/features.md`****.**
  README's Status line cites the trackers; the trackers are authoritative.

## Not covered by this rule

This rule covers `docs/architecture.md` and `README.md` only. The live
trackers (`docs/bugs.md`, `docs/features.md`, `docs/tasks.md`) carry their
own workflow rules at the top of each file — those are binding for those
files and govern bug/feature/task lifecycle, not architecture/README claim
sync. AGENTS.md is the rule pointer.

## Rationale

`docs/architecture.md` is the first thing AGENTS.md tells every agent to read.
If it lies, every downstream decision starts from a wrong premise. README.md
is the first thing humans read on the GitHub page, and stale feature lists
make the project look abandoned even when active. The cost of a one-line edit
in the same PR is far below the cost of either kind of drift.
