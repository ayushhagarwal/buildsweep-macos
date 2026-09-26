# BuildSweep

BuildSweep is a free native macOS 14+ utility that explains and cleans Xcode-generated storage without reading source contents. It uses SwiftUI, App Sandbox security-scoped bookmarks, ServiceManagement, OS frameworks only, and no external package or service. Direct downloads do not include in-app purchases.

## Open and run

1. Open `BuildSweep.xcodeproj` in Xcode 26 or later.
2. Select the `BuildSweep` scheme and `My Mac`.
3. Run, then choose `~/Library/Developer` during onboarding.

From Codex or Terminal:

```bash
./script/build_and_run.sh
./script/test.sh
```

The Run script builds into project-local `DerivedData`. Its default local build disables signing for repeatable compilation. Use an automatically signed Xcode build or archive for security-scoped bookmark, App Sandbox, and Simulator feasibility QA.

## Production identifiers

- Bundle identifier: `com.ayush.buildsweep`
- Website: `https://buildsweep.ayushdev.com`
- Support: `support@ayushdev.com`

The app is free. It does not use StoreKit, a paywall, or a license key.

## Releases

Version 1.0.0 is the first public release. Tags use `vMAJOR.MINOR.PATCH`. The app's short version is `CFBundleShortVersionString` in `BuildSweep/Info.plist` (currently `1.0.0`). The build number is `CFBundleVersion`.

The downloadable file is `BuildSweep-<version>.dmg`. It supports:

- macOS 14.0 or later
- Apple silicon (`arm64`) and Intel (`x86_64`)

```bash
./script/package_dmg.sh
```

The script builds a universal Release app. It signs with a Developer ID Application certificate when one is installed, or when `CODESIGN_IDENTITY` names one. Set `NOTARY_KEYCHAIN_PROFILE` to a `notarytool` keychain profile to submit the disk image and staple the ticket. That signature and notarization step is what gives a normal Gatekeeper install. `ALLOW_UNSIGNED=1` writes a local image for testing only; Gatekeeper will not treat it as a public download.

See `RELEASE_CHECKLIST.md` before publishing a tag.

## Safety model

- Scanning reads Xcode metadata plists and filesystem metadata only.
- Optional AI Tools cleanup is a Settings grant for Cursor, Codex, and Claude. It scans allowlisted cache and log folders only — never chats, skills, auth, sessions, or project trees.
- File cleanup always routes exact, revalidated URLs through `FileManager.trashItem`.
- Cleanup rejects broad roots, tool homes, source/project paths, unknown category shapes, symlinks, and paths outside authorized roots.
- Archives, Device Support, and Simulator devices are never preselected.
- SwiftUI Preview deletion and Simulator deletion are inspection-only until signed App Sandbox feasibility is proven.
- Simulator runtimes remain inspection-only and are managed in Xcode Settings › Components.
- Cursor, Codex, or Claude caches are not preselected and cannot be trashed while that app is running.

See `RELEASE_CHECKLIST.md` and `SANDBOX_FEASIBILITY.md` before distribution. Releases are notarized disk images, not Mac App Store builds.

## License

BuildSweep is released under the [MIT License](LICENSE).

The app icon in `BuildSweep/Assets.xcassets` and the concept artwork in `Design/AppIconConcepts` were created for this project and are covered by the same license. The repository does not include third-party code, fonts, or artwork.

