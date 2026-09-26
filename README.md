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

## Safety model

- Scanning reads Xcode metadata plists and filesystem metadata only.
- Optional AI Tools cleanup is a Settings grant for Cursor, Codex, and Claude. It scans allowlisted cache and log folders only — never chats, skills, auth, sessions, or project trees.
- File cleanup always routes exact, revalidated URLs through `FileManager.trashItem`.
- Cleanup rejects broad roots, tool homes, source/project paths, unknown category shapes, symlinks, and paths outside authorized roots.
- Archives, Device Support, and Simulator devices are never preselected.
- SwiftUI Preview deletion and Simulator deletion are inspection-only until signed App Sandbox feasibility is proven.
- Simulator runtimes remain inspection-only and are managed in Xcode Settings › Components.
- Cursor, Codex, or Claude caches are not preselected and cannot be trashed while that app is running.

See `RELEASE_CHECKLIST.md`, `SANDBOX_FEASIBILITY.md`, and `STOREKIT_HANDOFF.md` before distribution.

## License

BuildSweep is released under the [MIT License](LICENSE).

The app icon in `BuildSweep/Assets.xcassets` and the concept artwork in `Design/AppIconConcepts` were created for this project and are covered by the same license. The repository does not include third-party code, fonts, or artwork.

