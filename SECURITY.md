# Security policy

BuildSweep reads filesystem metadata and moves selected Xcode and AI-tool cache folders to Trash. A bug in path checks, bookmark handling, or cleanup can affect files on the Mac where the app is running.

## MCP boundary

The local MCP service is disabled by default. When enabled, a sandboxed stdio helper talks to the open app through a private Unix-domain socket inside the shared app group. Both processes verify the peer's strict code signature, bundle identifier, and signing team before accepting requests. The app handles a bounded request schema. The helper does not receive security-scoped bookmarks and cannot scan or clean authorized folders on its own.

MCP tools expose scan state and bounded metadata, never absolute paths or file contents. Item IDs are opaque and tied to a scan generation. A cleanup request can only stage currently listed, allowlisted items through the existing planner. It opens the native review UI; no MCP tool can approve or execute cleanup. Disabling MCP closes the listener and cancels an outstanding agent review.

The app and helper use the same macOS team-prefixed app group, `<TeamID>.com.ayush.buildsweep`, so only code signed by that team can use the shared container. The helper is signed before the containing app and is verified separately during packaging.

## Report privately

Do not open a public GitHub issue for a vulnerability, and do not include exploit details in a pull request.

Use either of these:

- GitHub private vulnerability reporting: https://github.com/ayushhagarwal/buildsweep-macos/security/advisories/new
- Email `support@ayushdev.com` with the subject "BuildSweep security"

Include the BuildSweep version, the macOS version, what you were cleaning, and the impact you observed. A synthetic fixture path is enough. Do not send source trees, credentials, chats, or a live production archive.

## What to expect

This is a single-maintainer project.

- You should receive an acknowledgement within 7 days.
- A follow-up will say whether the report is accepted, needs more information, or is outside the app's behavior.
- An accepted issue is fixed on `main` first. A notarized disk image follows when a Developer ID release is cut.
- There is no bug bounty.

Please give the maintainer 90 days after acknowledgement before publishing details, unless you have agreed on a different date.

## Supported versions

Security fixes go to the current `main` branch and to the latest version tag. Older tags are not maintained separately.

The 1.0.0 source is public. A notarized `BuildSweep-1.0.0.dmg` is not attached to GitHub Releases yet. Build from source, or wait for a signed release, rather than redistributing an unsigned local disk image.
