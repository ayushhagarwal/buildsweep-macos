# Current release preparation — 2026-09-27

The latest source builds as a universal Release app. The app and embedded MCP helper were signed with Developer ID team `X42TSM29Q6`; strict signature verification passed during packaging. The newest storage-map changes are included.

**Publication is blocked:** notarization of this candidate failed because the local `buildsweep-notary` Keychain profile was not found. The current `dist/BuildSweep-1.0.0.dmg` must not be published until notarization, stapling, and Gatekeeper checks succeed. An earlier candidate passed these checks, but that result does not validate the new artifact.

Manual UI checks during the preceding UX work covered dashboard scrolling, visible cleanup controls, review cancellation, empty categories, and map folder navigation. End-to-end cleanup execution, signed MCP IPC/client compatibility, and the outstanding platform/accessibility checklist are not signed off.

The following report is historical; its dependency and entitlement descriptions predate MCP and do not describe the current app.

---

# Test report

This report replaces earlier notes. The local `dist/BuildSweep-1.0.0.dmg` below is a historical unsigned artifact built before the latest repository changes; it is not a current release candidate.

Evidence below is from 2026-09-26 on this Mac only:

- Machine: MacBook Air, Apple silicon
- macOS 27.2 (build 26B5086k)
- Xcode 27A266a
- Historical local artifact: `dist/BuildSweep-1.0.0.dmg` and the Release app inside it
- App version: 1.0.0 (build 1)
- Minimum system version in the built app: 14.0
- Slices: `arm64` and `x86_64` (`lipo -archs`)

The disk image was built with `ALLOW_UNSIGNED=1 ./script/package_dmg.sh` because no Developer ID Application certificate was available. It is not notarized. `codesign --verify --deep --strict --verbose=2 dist/BuildSweep.app` reported `code object is not signed at all`. `codesign -dvvv` shows an ad-hoc linker signature, no team, and no sealed resources. Gatekeeper acceptance was not tested and should not be assumed.

## What passed

- Universal Release build for `arm64` and `x86_64` succeeded.
- Unit tests: 29 tests, 0 failures, on macOS 27.2 (`BuildSweepTests` via `xcodebuild test`, signing disabled). The latest run used `/tmp/BuildSweepCacheSafetyTests/Logs/Test/Test-BuildSweep-2026.09.26_20-38-32-+0530.xcresult`. It includes exact-root checks for all seven package-manager cache locations and a scanner fixture that verifies unapproved neighboring caches are omitted.
- One synthetic fixture file was moved to Trash with `FileManager.trashItem` and moved back. The original contents were still readable. This was not a run of the app's cleanup flow, and it did not cover Derived Data, archives, device support, or Simulator devices.
- Source review: no Swift package dependencies. `BuildSweep/BuildSweep.entitlements` contains only App Sandbox and user-selected read/write access. Those entitlements are not sealed into the unsigned candidate.
- `BuildSweep/PrivacyInfo.xcprivacy` declares no tracking and no collected data types. Accessed API reasons are UserDefaults `CA92.1`, file timestamp `3B52.1`, and disk space `85F4.1`.
- Opening the unsigned Release app with `open -n` left the `BuildSweep` process running. Window contents were not inspected.

## Continuous integration

After commit `7374407`, GitHub Actions run [36252823705](https://github.com/ayushhagarwal/buildsweep-macos/actions/runs/36252823705) passed all unit tests on `macos-15` and `macos-26`. This CI job runs `BuildSweepTests` only; it does not run the UI launch test or validate a signed app.

## What did not pass

- `BuildSweepUITests.testLaunchShowsOnboardingOrOverview` still fails on this machine. An ad-hoc signed debug run connected, but the accessibility hierarchy contained the app/menu bar and no visible main window, so neither expected screen label was found. Result bundle: `/tmp/BuildSweepUIUnderUser/Logs/Test/Test-BuildSweep-2026.09.26_20-39-21-+0530.xcresult`.
- A follow-up UI run could not activate the app (`Running Background`) and timed out after 360 seconds. This is not a successful UI launch validation. No Developer ID signed release candidate was available for testing.
- The latest source was not packaged as a Release DMG after the audit changes. The old unsigned image above must not be used as evidence for those changes.

## Not run

- macOS 14 runtime behavior. macOS 15 and macOS 26 have unit-test CI coverage, but no signed Release app or GUI validation on those systems.
- Execution of the `x86_64` slice.
- VoiceOver, Increased Contrast, Reduce Motion, keyboard-only, fullscreen, and multiple displays.
- Xcode-running guards, corrupt plists, cancellation, and partial success through the app UI.
- Disposable-user cleanup of real Xcode folders.
- `SANDBOX_FEASIBILITY.md` Simulator deletion checks.
- Developer ID signing, notarization, stapling, and `spctl` assessment.
- A check that the production website and support pages are live.

Do not treat this file as a passing release sign-off. The public download still needs a Developer ID-signed, notarized disk image and the unchecked items in `RELEASE_CHECKLIST.md`.
