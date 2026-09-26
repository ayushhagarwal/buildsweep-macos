# BuildSweep

BuildSweep is a free native macOS app that shows where Xcode-generated files use disk space and moves the ones you select to Trash. Scanning reads filesystem metadata and Xcode plists. It does not read source contents.

The app is distributed as a disk image. It is not sold on the Mac App Store, and it has no StoreKit purchase or license key.

There are no product screenshots in this repository yet.

## Download and install

Public downloads are `BuildSweep-<version>.dmg` on [GitHub Releases](https://github.com/ayushhagarwal/buildsweep-macos/releases). A notarized 1.0.0 disk image is not attached yet. Until that file is published, build from source with the steps below. An unsigned local image is not a public download: Gatekeeper will reject it.

When a notarized disk image is published:

1. Download `BuildSweep-<version>.dmg` from Releases.
2. Open the disk image and drag BuildSweep to Applications.
3. Open BuildSweep from Applications and choose `~/Library/Developer` during onboarding.

The app supports:

- macOS 14.0 or later
- Apple silicon (`arm64`) and Intel (`x86_64`)

## Build and test

Requirements: macOS 14 or later, and Xcode 26 or later.

```bash
./script/build_and_run.sh
./script/test.sh
```

Or open `BuildSweep.xcodeproj`, select the `BuildSweep` scheme and `My Mac`, and run.

The run script writes a Debug build to project-local `DerivedData` and disables signing so compilation does not need a certificate. Bookmark, sandbox, and Simulator checks need an automatically signed Xcode build.

`./script/package_dmg.sh` builds the universal Release app and, when `CODESIGN_IDENTITY` and `NOTARY_KEYCHAIN_PROFILE` are set, signs and notarizes the disk image. Those secrets stay off ordinary CI. See `RELEASE_CHECKLIST.md`.

## Known limitations

- Archives, Device Support, and Simulator devices are never preselected.
- SwiftUI Preview deletion and Simulator device deletion stay inspection-only until `SANDBOX_FEASIBILITY.md` passes on a signed build.
- Simulator runtimes are listed only. Remove them in Xcode Settings › Components.
- Cursor, Codex, and Claude caches are optional, are not preselected, and are refused while that app is running.
- The UI launch test does not currently pass on an unsigned or ad-hoc build. Details are in `TEST_REPORT.md`.

## Safety model

- Optional AI Tools cleanup is a Settings grant for Cursor, Codex, and Claude. It scans allowlisted cache and log folders only: never chats, skills, auth, sessions, or project trees.
- File cleanup always routes exact, revalidated URLs through `FileManager.trashItem`.
- Cleanup rejects broad roots, tool homes, source or project paths, unknown category shapes, symlinks, and paths outside authorized roots.

## Project

- Bundle identifier: `com.ayush.buildsweep`
- Version: `1.0.0` (build `1`), tags `vMAJOR.MINOR.PATCH`
- Website: https://buildsweep.ayushdev.com
- Support: support@ayushdev.com

## Community

- [Contributing](CONTRIBUTING.md): build, tests, welcome changes, bug reports, and feature proposals
- [Security](SECURITY.md): private vulnerability reports
- [Code of conduct](CODE_OF_CONDUCT.md)
- [Releases](https://github.com/ayushhagarwal/buildsweep-macos/releases)

## License

BuildSweep is released under the [MIT License](LICENSE).

The app icon in `BuildSweep/Assets.xcassets` and the concept artwork in `Design/AppIconConcepts` were created for this project and are covered by the same license. The repository does not include third-party code, fonts, or artwork.
