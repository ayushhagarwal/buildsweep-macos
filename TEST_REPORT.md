# Current release preparation — 2026-09-27

## Latest signed MCP and installer verification — 2026-09-28

The release candidate was rebuilt and Apple accepted app notarization submission `721995cc-93fa-44be-901c-2b20a5ae1726` and disk-image submission `629b5d82-580f-4a87-bd8f-c2bdf8730490`. The app and DMG both validate their stapled tickets. A read-only DMG mount contained exactly `BuildSweep.app` and the `Applications` shortcut. The embedded helper is Developer ID signed as `com.ayush.buildsweep.mcp` by team `X42TSM29Q6`; Gatekeeper accepts the app and disk image as Notarized Developer ID. Latest DMG SHA-256: `acb080e0ca4ba7f8e56ac0fed50aa1efc30176dbfca1a574cab527585ff2a64b`.

A signed MCP helper from the candidate, run with its matching app copy under `/Applications`, completed MCP initialization and a read-only `get_status` tool call. The returned response demonstrates that the helper strictly verified the running app and the app strictly verified the helper before returning data. Running this helper against an app launched from the development checkout fails its sandboxed code lookup (EPERM); this is not the installed-app path used for distribution. Claude, Codex, and full review-flow interoperability remain unverified.

The latest credential-pattern scan covered 86 tracked source files and files in the candidate app bundle; it found zero matches for common private-key, GitHub, AWS, Google, OpenAI, and Slack credential formats, and no signing certificates or provisioning profiles were bundled. This targeted pattern scan cannot prove absence of every possible secret format.

## Verification update — 2026-09-28

Additional checks on macOS 27.2 (build 26B5086k), Xcode 27A266a:

- `./script/test.sh` passes after the test runner was constrained to the host architecture (`uname -m`, with `ONLY_ACTIVE_ARCH=YES`). It ran 32 unit tests and `BuildSweepUITests.testLaunchShowsOnboardingOrOverview`; all passed. Result bundle: `/Users/ayush/Desktop/Desktop/Projects/BuildSweep/buildsweep-ios/DerivedData/Logs/Test/Test-BuildSweep-2026.09.28_09-02-26-+0530.xcresult`.
- `python3 script/test_mcp_protocol.py` passes initialization, tool schemas, bounds, unknown-tool rejection, and stdout framing. This remains a protocol-level smoke test; it does not validate signed IPC or Claude/Codex interoperability.
- `env DEVELOPMENT_TEAM=X42TSM29Q6 NOTARY_KEYCHAIN_PROFILE=buildsweep-notary ./script/package_dmg.sh` completed successfully when allowed to access the login Keychain outside the workspace sandbox. A separate unsigned universal Release build also succeeded during diagnosis; both app and helper built with `arm64` and `x86_64` slices.
- The first default-architecture Debug test attempt failed linking the MCP helper for `x86_64` with unresolved SDK symbols. Constraining the test runner to the host architecture fixed the test command. The universal Release build succeeds independently.
- The Keychain profile and seven valid signing identities were available when queried outside the sandbox. Earlier in-sandbox Keychain errors were misleading; there is no evidence that the credentials expired.
- Apple accepted notarization submission `95d02fe8-4b08-441e-8595-446452e8029a`. The app and DMG stapled tickets and passed `stapler validate`. The app and helper signatures verify with team `X42TSM29Q6`; the app-group and expected app/helper sandbox entitlements were confirmed.
- Gatekeeper accepted both the app and DMG as `Notarized Developer ID`. The image checksum verified, and a read-only mount contained exactly `BuildSweep.app` and the `Applications` shortcut. DMG SHA-256: `97ad003a65722f46d1cc0d2a0b93f97a92b6287bd0b76bd287d08cdb168aee67`.
- The verified DMG is published at [GitHub Releases](https://github.com/ayushhagarwal/buildsweep-macos/releases/tag/v1.0.0). Its SHA-256 is `97ad003a65722f46d1cc0d2a0b93f97a92b6287bd0b76bd287d08cdb168aee67`.
- Creating the `v1.0.0` ref through GitHub triggered the configured tag-push workflow. Run [36406448791](https://github.com/ayushhagarwal/buildsweep-macos/actions/runs/36406448791) failed at Developer ID certificate import because the GitHub certificate secrets were blank. This did not affect the locally signed, notarized, and validated DMG that was published.
- The private website repository is deployed at `https://buildsweep.ayushdev.com/`; the homepage, privacy page, and support page return HTTP 200. The primary download button links directly to the version 1.0.0 DMG.

The UI launch test in this earlier update used an unsigned Debug build; the signed candidate launch and narrow MCP smoke check are recorded above. Claude/Codex interoperability and outstanding cleanup-safety/platform/accessibility checks remain unverified. The earlier redacted credential scan was targeted, not a formal proof against every possible secret format.

During the 2026-09-27 packaging attempt, a previous app and embedded helper were signed with Developer ID team `X42TSM29Q6`, and strict signature verification passed at that time. That earlier candidate was superseded by the verified 2026-09-28 DMG above.

**Publication complete:** the locally signed and notarized DMG is published. The tag-triggered GitHub signing workflow remains misconfigured because its required GitHub secrets are absent; a future automated release run requires those secrets or a revised workflow.

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
