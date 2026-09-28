# BuildSweep 1.0.0

BuildSweep is a free, MIT-licensed macOS app for inspecting developer storage and reviewing selected cleanup in a native confirmation screen.

## Included

- Xcode Derived Data, archives, Device Support, caches, and logs with inspection before cleanup.
- Separately authorized AI-tool and package-manager cache locations.
- A redesigned developer storage map with folder navigation, proportional color tiles, and a complete list of measured items.
- Improved scrolling, window sizing, back navigation, and cleanup review presentation.
- Universal app for Apple silicon and Intel; minimum macOS 14.

## Installation

Download the signed and notarized `BuildSweep-1.0.0.dmg` from this release's Assets, open it, drag BuildSweep to Applications, and launch it from Applications. Authorize folders in the app before scanning. Select items and choose Review Cleanup; only your confirmation moves eligible items to Trash.

## Limitations

- Local MCP is experimental, off by default, and requires the app to remain open. Signed IPC and Claude/Codex interoperability have not completed validation. Agents cannot approve cleanup.
- Simulator deletion and SwiftUI Preview deletion remain inspection-only.
- Reported reclaimable space is an estimate. Moving files to Trash does not free their space until Trash is emptied.
- Cross-version GUI, Intel runtime, and accessibility checks remain incomplete; see RELEASE_CHECKLIST.md and TEST_REPORT.md.

## Download

Download `BuildSweep-1.0.0.dmg` from the Assets section of this GitHub release. The installer has passed Developer ID signature verification, Apple notarization, stapling, Gatekeeper assessment, and disk-image contents checks.
