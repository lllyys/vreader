---
description: Bump vreader version (project.yml) — regenerate Xcode project, commit, tag, push
argument-hint: "[version | patch | minor | major]"
---

# Version Bump

Bump `MARKETING_VERSION` (and increment `CURRENT_PROJECT_VERSION`) in `project.yml`, regenerate the Xcode project, commit, tag, and push. Full procedure documented in `.claude/rules/40-version-bump.md`.

## Input

```text
$ARGUMENTS
```

## Phase 1: Determine New Version

Read current `MARKETING_VERSION` from `project.yml`.

Parse `$ARGUMENTS`:

| Input | Action |
|-------|--------|
| `0.5.0` | Use exactly as specified |
| `patch` | Increment patch: `0.4.2` → `0.4.3` |
| `minor` | Increment minor: `0.4.2` → `0.5.0` |
| `major` | Increment major: `0.4.2` → `1.0.0` |
| (empty) | Default to `patch` |

Display: `Current: {old} → New: {new}` and ask user to confirm.

Also bump `CURRENT_PROJECT_VERSION` by 1 — App Store Connect requires monotonically-increasing build numbers.

## Phase 2: Update project.yml

Use the Edit tool. Both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are under `targets: vreader: settings: base:` in `project.yml` (NOT the top-level `settings`).

```yaml
targets:
  vreader:
    settings:
      base:
        MARKETING_VERSION: {new}
        CURRENT_PROJECT_VERSION: {build+1}
```

## Phase 3: Regenerate Xcode project

```bash
xcodegen generate
```

Verify both files updated:

```bash
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" project.yml
grep -E "MARKETING_VERSION =|CURRENT_PROJECT_VERSION =" vreader.xcodeproj/project.pbxproj
```

If `pbxproj` doesn't reflect the change, xcodegen didn't run — investigate before proceeding.

## Phase 4: Build smoke test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Must end with `BUILD SUCCEEDED`. Don't ship a bump that breaks the build.

## Phase 5: Commit, Tag, Push

```bash
git add project.yml vreader.xcodeproj/project.pbxproj
git commit -m "chore: bump version to {version}"
git tag v{version}
git push origin main --tags
```

If `main` is protected (PR-only), open a PR for the bump commit, merge it, then tag from the merge commit on `main`.

Report done: `Bumped to {version} (build {build+1}), tagged v{version}, pushed.`
