# BuildSweep 1.0 release checklist

## Automated

- [x] Project-local clean universal Release build passes with Xcode 26.6.
- [ ] Unit tests pass on macOS 14, 15, and 26.
- [x] UI launch test passes from a local automatically signed test build.
- [ ] Archive validation succeeds.
- [x] No external package, network entitlement, helper, or service is present.

## Destructive manual QA

- [ ] Use only a separate disposable macOS user or synthetic fixture tree.
- [ ] Verify every Trash action can be restored.
- [ ] Exercise disappearing items, permission failures, corrupt plist files, 100,000-file trees, cancellation, and partial success.
- [ ] Verify Xcode-running guards for Derived Data and shared caches.
- [ ] Never test against active production archives or a normal Simulator device.

## Platform and accessibility

- [ ] macOS 14, 15, and 26.
- [ ] Apple silicon and release architectures.
- [ ] Light/Dark, Increased Contrast, Reduce Motion, VoiceOver, keyboard-only.
- [ ] Minimum window, fullscreen, and multiple displays.
- [ ] Xcode stable/beta, Xcode running, no Xcode, and misconfigured command-line tools.

## Trust and distribution

- [ ] Review Xcode’s generated privacy report and required-reason API declarations.
- [ ] Privacy and support pages are live at the production domain.
- [ ] Real IAP purchase and restore pass in App Store sandbox.
- [ ] `codesign --verify --deep --strict BuildSweep.app` passes on the archived/exported artifact.
- [ ] `codesign -dvvv --entitlements :- BuildSweep.app` shows only intended entitlements.
- [ ] Final TestFlight build receives the same cleanup, StoreKit, permission, and accessibility QA.
- [ ] Developer completes screenshots, App Store metadata, privacy, age-rating, and export-compliance questionnaires.
