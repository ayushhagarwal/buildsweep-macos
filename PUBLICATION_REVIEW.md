# Pre-publication history review

Reviewed on 2026-09-26, before this repository is treated as the public source.

## What was checked

- Remote `origin/main` at `38b8edb` (`first commit`, 2026-09-06).
- Every later local commit on `main`.
- The file list of every commit, including files deleted later.
- Text in those commits for private keys, tokens, passwords, provisioning profiles, and home-directory paths.

## Findings

No commit contains `.env` files, private keys, certificates, provisioning profiles, API tokens, or the ignored `.codex/` and `.cursor/` directories. `.gitignore` excludes those paths, and they are absent from the historical file list. Local build output under `DerivedData/`, `DerivedDataRelease/`, and `dist/` is also ignored.

The only email address in source files is the public support address, `support@ayushdev.com`.

Every commit, including the commit already on `origin/main`, records the same git author. That author address is a personal mailbox. It is not the support address, and it is not written in the source files. It is part of the commit metadata, so it becomes public when the history is pushed. Removing it means rewriting every commit and force-pushing `main`. This review did not rewrite history.

Deleted files from earlier commits (`BuildSweep/IAP/StoreKitPurchaseClient.swift`, `BuildSweep/Views/PaywallView.swift`, `STOREKIT_HANDOFF.md`, and the purchase tests) contain the old product id `com.ayush.buildsweep.pro.lifetime`. They do not contain credentials.

## Left on purpose

`support@ayushdev.com`, the bundle id `com.ayush.buildsweep`, and the copyright line "Ayush" are the public project identity.
