# BuildSweep direct distribution checklist

BuildSweep is a free app distributed as a macOS disk image. It is not submitted to the Mac App Store, TestFlight, or App Store Connect. In-app purchases are not part of this release: StoreKit is unavailable for apps distributed outside the Mac App Store.

Public versions use semantic tags (`v1.0.0`). The marketing version in the app is `MARKETING_VERSION` (`CFBundleShortVersionString`). The build number is `CURRENT_PROJECT_VERSION` (`CFBundleVersion`). The downloadable file is `BuildSweep-<version>.dmg`.

Supported systems for a release candidate:

- macOS 14.0 or later (`MACOSX_DEPLOYMENT_TARGET`)
- Apple silicon and Intel (`arm64` and `x86_64`)

## Automated

- [ ] Project-local clean Release build passes for `arm64` and `x86_64`.
- [ ] Unit tests pass on the macOS version used to cut the release.
- [ ] UI launch test passes from the signed release candidate, not from an older local build.
- [ ] No external package, network entitlement, helper, or service is present.

## Safety

- [ ] Use only a separate disposable macOS user or synthetic fixture tree for Trash tests.
- [ ] Verify every Trash action can be restored.
- [ ] Exercise disappearing items, permission failures, corrupt plist files, large trees, cancellation, and partial success.
- [ ] Verify Xcode-running guards for Derived Data and shared caches.
- [ ] Never test against active production archives or a normal Simulator device.
- [ ] Leave Simulator deletion inspection-only unless `SANDBOX_FEASIBILITY.md` is complete for this signed build.

## Platform and accessibility

- [ ] Exercise the candidate on each macOS major version you claim (14, 15, and 26). Record the versions you could not run.
- [ ] Confirm the shipped binary contains both `arm64` and `x86_64`.
- [ ] Light appearance, Increased Contrast, Reduce Motion, VoiceOver, and keyboard-only use.
- [ ] Minimum window, fullscreen, and multiple displays.
- [ ] Xcode stable, Xcode beta, Xcode running, no Xcode, and misconfigured command-line tools.

## Signing, notarization, and the disk image

Direct distribution needs a Developer ID Application signature and Apple notarization. An ad-hoc or development signature is not a public download.

- [ ] Sign the Release `.app` with a Developer ID Application certificate, Hardened Runtime, and only the sandbox entitlements in `BuildSweep/BuildSweep.entitlements`.
- [ ] `codesign --verify --deep --strict --verbose=2 BuildSweep.app` passes.
- [ ] `codesign -dvvv --entitlements :- BuildSweep.app` shows only App Sandbox and user-selected read/write access.
- [ ] Submit the app or disk image with `xcrun notarytool submit`, wait until the status is Accepted, and staple the ticket with `xcrun stapler staple`.
- [ ] `spctl --assess --type execute --verbose BuildSweep.app` reports accepted.
- [ ] The disk image opens, the app copies out of it, and Gatekeeper launches it without an “unidentified developer” warning.
- [ ] Publish the stapled `BuildSweep-<version>.dmg` with the git tag for that version.

## Trust

- [ ] Review the privacy manifest in `BuildSweep/PrivacyInfo.xcprivacy`.
- [ ] Privacy and support pages are live at the production domain, or the README states that they are not yet live.
- [ ] The disk image and tag contain no credentials, provisioning profiles, or private notes.
