# Test report

Current automated coverage includes 18 focused unit tests plus one macOS UI launch test:

- canonical path containment, broad-root blocking, source-path blocking, and symlink escape;
- Derived Data workspace metadata and default-selection behavior;
- archive version/build/bundle/signing/dSYM parsing and Important risk behavior;
- cleanup partial success and immediate free-session consumption;
- successful Trash reporting when Keychain accounting itself needs attention;
- exact Device Support and optional Xcode-cache allowlists with unknown-item fail-closed behavior;
- allocated sizing of hidden files and package contents;
- inspection-only planning rejection;
- review milestone, version, and cooldown policy;
- verified, pending, revoked, unavailable, unverified, and restore-without-entitlement purchase states.

Run on 2026-08-08 using Xcode 26.6 and the macOS destination. All 18 unit tests and the UI launch test passed. The universal Release artifact also built for arm64 and x86_64, then passed local ad-hoc `codesign --verify --deep --strict` verification with only the two intended sandbox entitlements.

The UI launch target must still be rerun from the uploaded TestFlight candidate. Destructive Trash and Simulator QA are intentionally manual and gated by `SANDBOX_FEASIBILITY.md`.
