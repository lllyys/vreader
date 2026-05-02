# 40 - Version Bump Procedure

vreader's version lives in `project.yml` (xcodegen) under `targets: vreader: settings: base:`. xcodegen regenerates `vreader.xcodeproj/project.pbxproj` from it; pbxproj is checked in but should not be hand-edited for a bump.

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

1. **Edit ****`project.yml`** — change `MARKETING_VERSION` to the new version. Bump `CURRENT_PROJECT_VERSION` too (always increasing — App Store requires a higher build number than any previously-uploaded build).

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
