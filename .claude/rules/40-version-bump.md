# 40 - Version Bump Procedure

vreader's version lives in `project.yml` (xcodegen) under `targets: vreader: settings: base:`. xcodegen regenerates `vreader.xcodeproj/project.pbxproj` from it; pbxproj is checked in but should not be hand-edited for a bump.

## When to bump

**Every PR must include a version bump.** The version line is owned by the PR
that ships the change, not by a separate release commit, so:

- **Bump before opening the PR** — bumping after the PR is open and rebasing
  conflicts with reviews.
- **Bump as the last step on the branch** — after the feature commits are in,
  not interleaved with them. A clean tail commit `chore: bump version to X.Y.Z`
  is easier to revert than a bump folded into a feature commit.
- **Choose increment by impact:**
  - `patch` — bug fix, docs, chores, refactors with no externally-visible change.
  - `minor` — new user-visible feature or capability.
  - `major` — breaking change to data, schema, or public contract.
- `CURRENT_PROJECT_VERSION` always increments by ≥1 — App Store Connect rejects
  uploads with a non-monotonic build number.

The post-merge tag (`git tag v{version}` on the merge commit) is cut by the
finalizer once the PR lands on `main`.

## Files to Update

| File          | Field                                                       |
| ------------- | ----------------------------------------------------------- |
| `project.yml` | `MARKETING_VERSION` (visible version, e.g. `0.1.0`)         |
| `project.yml` | `CURRENT_PROJECT_VERSION` (build number, monotonic integer) |

After editing `project.yml`, regenerate the Xcode project and commit BOTH:

```bash
# 1. Edit project.yml — change MARKETING_VERSION (and bump CURRENT_PROJECT_VERSION)
# 2. Regenerate
xcodegen generate

# 3. Confirm the regen actually changed pbxproj
git diff vreader.xcodeproj/project.pbxproj | grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION"
```

## Bump Procedure

1. \*\*Edit \*\***`project.yml`** — change `MARKETING_VERSION` to the new version. Bump `CURRENT_PROJECT_VERSION` too (always increasing — App Store requires a higher build number than any previously-uploaded build).

2. **Regenerate the Xcode project**:

   ```bash
   xcodegen generate
   ```

3. **Verify both files updated**:

   ```bash
   grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" project.yml
   grep -E "MARKETING_VERSION =|CURRENT_PROJECT_VERSION =" vreader.xcodeproj/project.pbxproj
   ```

4. **Build to confirm**:

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
       -project vreader.xcodeproj -scheme vreader \
       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
   ```

5. **Commit** (single commit, both files together):

   ```bash
   git add project.yml vreader.xcodeproj/project.pbxproj
   git commit -m "chore: bump version to {version}"
   ```

6. **Tag and push** (only after commit lands on main):

   ```bash
   git tag v{version}
   git push origin main --tags
   ```

## Common Mistakes

- Editing `pbxproj` directly without updating `project.yml` — next `xcodegen` overwrites your change.
- Forgetting `CURRENT_PROJECT_VERSION` — App Store Connect rejects uploads with the same build number as a previous build.
- Tagging before the commit lands on `main` — orphan tag.

## Verification

After a bump, the App's About / TestFlight build number both should reflect the new `MARKETING_VERSION`. The build number from `CURRENT_PROJECT_VERSION` is shown in TestFlight's release lists.

## Multi-platform (Android port — feature #103 Phase 0)

vreader is becoming two independently-shippable native apps (iOS at the
repo root, Android under `android/`). A single `vX.Y.Z` tag space and one
`project.yml` version cannot represent both. The policy:

### Which platform does a PR bump?

**Bump the version file of the platform whose code the PR touched** (the
same code-path classification the audit gate uses,
`.claude/hooks/lib/code-paths.sh`):

| PR touches | Bump |
|---|---|
| iOS code (`vreader/`, `vreaderTests/`) | `project.yml` `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` (the existing iOS flow above) |
| Android code (`android/`, Gradle, Kotlin) | `android/version.properties` (`versionName` + `versionCode`) — *created in Phase 2; until then no Android app exists to bump* |
| Shared only (`docs/`, `contracts/`, `.claude/`, design) | bump the iOS version (iOS is the default release vehicle while Android is pre-foundation); a shared change that is part of an Android-code PR bumps Android |
| Both platforms' code in one PR | avoid — split per the write-isolation rule (rule 48). If genuinely unavoidable, bump both files. |

### Tag namespace (DECIDED — feature #103 plan, Gate-2 clean)

- **iOS keeps plain `vX.Y.Z`, UNCHANGED.** The ~100 existing `v3.66.x`
  tags are NOT retagged. A plain `vX.Y.Z` tag means iOS by definition.
- **Android uses prefixed `android/vX.Y.Z`.** Any `android/`-prefixed tag
  means Android.
- No plain tag is ever cut for an Android-only release; no `android/` tag
  for an iOS-only release.
- **Rationale**: retagging a long iOS history is pointless churn, and the
  namespace asymmetry (iOS plain, Android prefixed) deliberately mirrors
  the directory asymmetry (iOS at root, Android in a subdir) — the ADR's
  "right pragmatic call." Rejected: a single unified product version
  (re-couples two independently-shippable cadences — the ADR's "biggest
  miss").

### Close-gate comment

The GH "shipped in vX.Y.Z" closure comment (AGENTS.md close gate +
`/fix-issue` Phase 9) is platform-namespaced for Android:
"shipped in `android/vX.Y.Z`". The iOS wording is unchanged.

> **Status**: this policy is documented; `android/version.properties` and
> the Android bump mechanics land with the Phase-2 app shell (feature
> #106). Until then every PR is iOS or shared → the existing iOS flow.
