# Security policy

BuildSweep reads filesystem metadata and moves selected Xcode and AI-tool cache folders to Trash. A bug in path checks, bookmark handling, or cleanup can affect files on the Mac where the app is running.

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
