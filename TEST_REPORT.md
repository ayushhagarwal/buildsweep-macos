# Test report

This report replaces the 2026-08-08 note. That earlier run is not verification of the 1.0.0 disk image.

Evidence below is from 2026-09-26 on this Mac only:

- Machine: MacBook Air, Apple silicon
- macOS 27.2 (build 26B5086k)
- Xcode 27A266a
- Candidate: `dist/BuildSweep-1.0.0.dmg` and the Release app inside it
- App version: 1.0.0 (build 1)
- Minimum system version in the built app: 14.0
- Slices: `arm64` and `x86_64` (`lipo -archs`)

The disk image was built with `ALLOW_UNSIGNED=1 ./script/package_dmg.sh` because no Developer ID Application certificate was available. It is not notarized. `codesign --verify --deep --strict --verbose=2 dist/BuildSweep.app` reported `code object is not signed at all`. `codesign -dvvv` shows an ad-hoc linker signature, no team, and no sealed resources. Gatekeeper acceptance was not tested and should not be assumed.

## What passed

- Universal Release build for `arm64` and `x86_64` succeeded.
- Unit tests: 21 tests, 0 failures, on macOS 27.2 (`BuildSweepTests` via `xcodebuild test`, signing disabled). Coverage still includes path containment, symlink escape, Derived Data and archive metadata, inspection-only rejection, allocated sizing, and allowlisted AI-tool folders. Purchase-state tests are gone with StoreKit.
- One synthetic fixture file was moved to Trash with `FileManager.trashItem` and moved back. The original contents were still readable. This was not a run of the app's cleanup flow, and it did not cover Derived Data, archives, device support, or Simulator devices.
- Source review: no Swift package dependencies. `BuildSweep/BuildSweep.entitlements` contains only App Sandbox and user-selected read/write access. Those entitlements are not sealed into the unsigned candidate.
- `BuildSweep/PrivacyInfo.xcprivacy` declares no tracking and no collected data types. Accessed API reasons are UserDefaults `CA92.1`, file timestamp `3B52.1`, and disk space `85F4.1`.
- Opening the unsigned Release app with `open -n` left the `BuildSweep` process running. Window contents were not inspected.

## What did not pass

- `BuildSweepUITests.testLaunchShowsOnboardingOrOverview` failed on an ad-hoc signed debug build. The test launched the app (pid recorded by XCTest) and did not find "Understand Xcode storage" or "Xcode storage at a glance" within the timeout. Result bundle: `DerivedData/Logs/Test/Test-BuildSweep-2026.09.26_19-13-51-+0530.xcresult`.
- The same UI test, with signing disabled, was killed before it connected (`signal kill`). That run is not a UI result.

## Not run

- macOS 14, macOS 15, and any macOS 26 build other than 27.2 on this Mac.
- Execution of the `x86_64` slice.
- VoiceOver, Increased Contrast, Reduce Motion, keyboard-only, fullscreen, and multiple displays.
- Xcode-running guards, corrupt plists, cancellation, and partial success through the app UI.
- Disposable-user cleanup of real Xcode folders.
- `SANDBOX_FEASIBILITY.md` Simulator deletion checks.
- Developer ID signing, notarization, stapling, and `spctl` assessment.
- A check that the production website and support pages are live.

Do not treat this file as a passing release sign-off. The public download still needs a Developer ID-signed, notarized disk image and the unchecked items in `RELEASE_CHECKLIST.md`.
