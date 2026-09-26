# Contributing to BuildSweep

BuildSweep is a free macOS app distributed as a disk image. It is not a Mac App Store app and it has no in-app purchase.

## Build and run

Requirements: macOS 14 or later, and Xcode 26 or later.

1. Open `BuildSweep.xcodeproj`.
2. Select the `BuildSweep` scheme and `My Mac`.
3. Run, then choose `~/Library/Developer` during onboarding.

From Terminal:

```bash
./script/build_and_run.sh
```

That script builds a Debug app into project-local `DerivedData` with signing disabled, then opens it. Signing is disabled so the build is repeatable without a developer certificate. Security-scoped bookmarks, App Sandbox behavior, and Simulator checks need an automatically signed Xcode build instead.

## Tests

```bash
./script/test.sh
```

The script runs the `BuildSweep` scheme with `CODE_SIGNING_ALLOWED=NO`. Unit tests cover path safety, scanning, and cleanup planning. The UI launch test is included in that script. On an unsigned build it can be killed before it connects, and on an ad-hoc signed build it has failed to find the onboarding and overview labels. See `TEST_REPORT.md`.

GitHub Actions runs `BuildSweepTests` only, on `macos-26` and `macos-15`, with signing disabled. The tag-triggered release workflow is separate: it uses repository Actions secrets to sign and notarize a universal disk image, then publishes a GitHub Release only after validation succeeds. Do not use unsigned test artifacts as public downloads.

## Changes that are welcome

- Clearer explanations of what a cleanup will do.
- Scanner and cleanup fixes that keep the existing path checks.
- Tests for those checks.
- Accessibility and copy improvements.
- Documentation that matches the direct-download release.

Open an issue before a large change. Pull requests should stay focused.

These need an issue first, and a reason that preserves the safety model:

- Deleting a broader set of paths.
- Enabling Simulator or SwiftUI Preview deletion. That stays off until `SANDBOX_FEASIBILITY.md` is done for a signed build.
- Adding a package dependency, a network call, analytics, or a purchase flow.

## Reporting a defect

Use the bug report template: https://github.com/ayushhagarwal/buildsweep-macos/issues/new?template=bug_report.yml

Include the macOS version, the BuildSweep version, whether Xcode was running, and what you selected. Leave out source trees, secrets, and chat history. The in-app diagnostics copy is meant to be shareable because it omits project paths.

For a vulnerability, follow `SECURITY.md` instead of opening a public issue.

## Proposing a feature

Use the feature request template: https://github.com/ayushhagarwal/buildsweep-macos/issues/new?template=feature_request.yml

You can also email `support@ayushdev.com`. Describe the storage problem and how the change stays inside the folders the app is allowed to touch.

## Pull requests

- Target `main`.
- Describe the user-visible change and which tests you ran.
- Keep new cleanup paths inside the existing allowlists and rejection rules.
- Do not commit `DerivedData/`, `dist/`, certificates, or notarization credentials.
