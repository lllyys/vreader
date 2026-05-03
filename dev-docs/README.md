# dev-docs

Working notes during a feature's active development cycle.

## What lives here

| Path              | Contents                                                            |
| ----------------- | ------------------------------------------------------------------- |
| `dev-docs/plans/` | Active implementation plans (one file per WIP feature or refactor). |

## What does NOT live here

- **Permanent reference** — anything an outsider or future agent would
  read to understand the codebase belongs in `docs/` instead. Subsystem
  references (e.g. the DEBUG-only `vreader-debug://` URL scheme) live at
  `docs/subsystems/<name>.md`.
- **Live trackers** — bug / feature / task lists live in `docs/`
  (`bugs.md`, `features.md`, `tasks.md`).
- **Frozen history** — shipped, abandoned, or superseded plans rotate to
  the top-level `archive/plans/` directory. Old plans should not stay in
  `dev-docs/plans/` once they're no longer driving current work.

## Lifecycle for a plan file

```
dev-docs/plans/<date>-<slug>.md
        │
        ├── (active development on this feature)
        │
        ▼
        Feature ships, is abandoned, or is superseded
        │
        ▼
archive/plans/<same-filename>.md
```

When you create a plan file:

1. Use a `YYYYMMDD-<slug>.md` naming scheme so chronological order is obvious.
2. Reference the feature/bug tracker row(s) it implements (`features.md` /
   `bugs.md` / GH issue #).
3. Update the plan as decisions evolve — don't write a follow-up file for
   the same feature.

When the work the plan covers is done (or definitively dropped):

1. Move the file: `git mv dev-docs/plans/<file>.md archive/plans/<file>.md`.
2. Land the move in the same PR as the feature's final commit, or as a
   follow-up cleanup PR if the feature shipped without one.

## See also

- `docs/architecture.md` — canonical architecture reference (read first).
- `docs/subsystems/` — subsystem references (DebugBridge, etc.).
- `.claude/rules/24-doc-sync.md` — when to update `docs/architecture.md` and `README.md`.
- `.claude/rules/20-logging-and-docs.md` — keep one source of truth per topic.

