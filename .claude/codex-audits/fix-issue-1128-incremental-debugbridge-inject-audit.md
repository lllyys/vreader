---
branch: fix/issue-1128-incremental-debugbridge-inject
threadId: 019e6363-598a-7bc1-97af-ef74ff417516
rounds: 1
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Bug #259 / GH #1128 (incremental build drops vreader-debug URL scheme)

Independent audit (Codex MCP, separate process) of the build-config fix for the
DEBUG `vreader-debug://` URL scheme being dropped from the Info.plist after an
incremental build (simctl openurl → error 115 until a clean build).

File audited: `project.yml` (the "Inject DebugBridge URL types (DEBUG only)"
postCompileScript) + the generated `vreader.xcodeproj/project.pbxproj` phase.

## Root cause (refined during verification — deeper than the issue's stated cause)

The issue reported "inputFiles-but-no-outputFiles → phase skipped on incremental."
Device verification revealed a SECOND, dominant cause: on incremental builds Xcode
re-ran `ProcessInfoPlistFile` AFTER the inject script (observed order: inject →
ProcessInfoPlistFile → CodeSign), regenerating the Info.plist from source and
CLOBBERING the just-injected scheme. So `basedOnDependencyAnalysis: false` alone
(make the phase always run) was insufficient — verified: openurl still failed 115
after an incremental build because the injection was clobbered.

## Fix

1. `basedOnDependencyAnalysis: false` (pbxproj `alwaysOutOfDate = 1`) — phase runs every build.
2. Declare the BUILT Info.plist (`$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)`) as an
   `inputFiles` entry → forces XCBuild to schedule the inject script AFTER the task
   that produces it (`ProcessInfoPlistFile`). Inputs do NOT trigger the duplicate-
   output failure that declaring it as an OUTPUT would.

## Round 1 — clean (no findings)

Codex confirmed:
- The built-plist-as-input edge is a sound, standard way to order the shell phase
  after `ProcessInfoPlistFile` under XCBuild; no dependency cycle (the phase does
  not declare the plist as an output, so it's a read edge, not a producer edge);
  no legacy-build-system regression.
- `basedOnDependencyAnalysis: false` composes correctly with the input edge
  ("should it run?" vs "what must exist first?") — always-run does not erase the
  ordering dependency.
- No Release-safety regression: the script is gated on `CONFIGURATION == Debug`;
  `verify-release-no-debugbridge.sh` contract intact; Release cost is a trivial no-op.
- Per-config `INFOPLIST_FILE` (split Debug/Release plists) is the only alternative,
  and Codex agreed it is MORE drift-prone — keep the single-authoritative-plist
  approach.

## Verification (device, end-to-end — CU-free)

iPhone 17 Pro Simulator, isolated derivedDataPath:
- Clean build → install → `simctl openurl vreader-debug://reset` → **exit 0**; build
  order `ProcessInfoPlistFile` → `Injected`.
- `touch vreader/App/VReaderApp.swift` → **INCREMENTAL** build → install →
  `openurl` → **exit 0**; order still `ProcessInfoPlistFile` → `Injected`; the
  `vreader-debug` scheme present in the installed Info.plist.
- (Pre-fix the incremental openurl failed with error 115 — confirmed during the
  first fix iteration, where the order was inject → ProcessInfoPlistFile and the
  injection was clobbered.)

## Verdict

**Ship-as-is.** Config-only change, no findings, device-verified end-to-end. The
fix is the input-ordering edge (the `alwaysOutOfDate`-only first attempt was
proven insufficient by verification).
