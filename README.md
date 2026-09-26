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

## Local MCP for AI agents

BuildSweep includes an optional MCP stdio helper for Claude, Codex, and other compatible clients. It is off by default. Enable **Settings → General → Local MCP for AI agents**, then copy the setup snippet into the client yourself. BuildSweep never edits client configuration files.

The app must be open while the client is connected. The agent can check scan status, scan locations already authorized in BuildSweep, list and inspect bounded item summaries, and stage up to 50 items for review. Paths and file contents are not returned to the client. Staging opens BuildSweep's native cleanup review; only a person confirming in that window can move selected items to Trash. The MCP helper has no direct access to the authorized folders and provides no cleanup approval or execution tool.

This feature requires a signed BuildSweep build. The app and helper use the macOS team-prefixed app group `<TeamID>.com.ayush.buildsweep`, which avoids a separate profile registration step for direct distribution. An unsigned local image will not establish the shared app-group container and is not suitable for MCP validation. The helper uses the Model Context Protocol Swift SDK, pinned to 0.12.1.

After building the app, run `python3 script/test_mcp_protocol.py` to smoke-test MCP initialization, tool discovery, bounded schemas, unknown-tool rejection, and stdout framing without connecting to the app.

## Build and test

Requirements: macOS 14 or later, and Xcode 26 or later.

```bash
./script/build_and_run.sh
./script/test.sh
```

Or open `BuildSweep.xcodeproj`, select the `BuildSweep` scheme and `My Mac`, and run.

The run script writes a Debug build to project-local `DerivedData` and disables signing so compilation does not need a certificate. Bookmark, sandbox, and Simulator checks need an automatically signed Xcode build.

`./script/package_dmg.sh` builds the universal Release app. A public disk image is signed with a Developer ID Application certificate, notarized, stapled, and checked with `spctl`. The script fails if `NOTARY_KEYCHAIN_PROFILE` is missing or if notarization or Gatekeeper assessment fails. `ALLOW_UNSIGNED=1` writes a local test image only.

Pushing a matching `v<version>` tag runs the signed release workflow. Configure these repository Actions secrets first: `DEVELOPER_ID_CERTIFICATE_P12_BASE64`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `NOTARY_API_KEY_BASE64`, `NOTARY_API_KEY_ID`, and `NOTARY_API_ISSUER_ID`. The workflow publishes a GitHub Release only after signing, notarization, stapling, and Gatekeeper checks succeed. See `RELEASE_CHECKLIST.md` before creating a public tag.

## Known limitations

- Archives, Device Support, and Simulator devices are never preselected.
- SwiftUI Preview deletion and Simulator device deletion stay inspection-only until `SANDBOX_FEASIBILITY.md` passes on a signed build.
- Simulator runtimes are listed only. Remove them in Xcode Settings › Components.
- Cursor, Codex, and Claude caches are optional, are not preselected, and are refused while that app is running.
- Swift Package Manager, CocoaPods, Carthage, npm, Yarn, pnpm, and Bun caches require separate folder approval in Settings and are not preselected. They may need to be downloaded or rebuilt again after moving to Trash.
- The read-only developer storage map shows at most the first 200 items in each folder, alphabetically. Its mapped byte total covers only those shown items; folder size estimates use allocated file sizes.
- The UI launch test does not currently pass on an unsigned or ad-hoc build. Details are in `TEST_REPORT.md`.

## Safety model

- Optional AI Tools cleanup is a Settings grant for Cursor, Codex, and Claude. It scans allowlisted cache and log folders only: never chats, skills, auth, sessions, or project trees.
- Optional package-cache cleanup requires a separate user-selected grant for each exact package-manager cache directory. It does not include project folders, lockfiles, or `node_modules`.
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
