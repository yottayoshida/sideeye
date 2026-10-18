# #929: three macOS target shapes — the selection, fixed before the first run

This file is committed alone, before any `preflight` or `explore` of these targets, so that no target, command, invariant or control is chosen or replaced after a verdict is seen (#929). The measurement that follows reads this file; a change to it after the first run is a new study, named as such.

## What is measured, and on what

- **Release**: the `aarch64-macos` asset of **v1.15.0**, downloaded from the release and checked against the digest it publishes. #929 named v1.14.0; the owner moved it to v1.15.0 on 2026-10-18 so that the conclusion is about the release users install now. What v1.15.0 changed for macOS is recorded beside the results.
- **Hosts**: GitHub's `macos-14` and `macos-26` runners, Apple silicon. Each run records `sw_vers`. A runner that cannot be obtained is recorded as unmeasured, not replaced; macOS 13 is not inferred from either.
- **Privilege**: `--oracle-fs-usage` needs root. The runners' `sudo` asks for no password; each run records `sudo -n true` before it starts, and a failure there is recorded as a missing privilege, not as an engine limit.
- **Per pair**: `preflight --twice`; then, when the recording is accepted, `explore --oracle-fs-usage`; and separately `explore --allow-unverified`, which is recorded beside the oracle's result and never counted as an oracle-verified PASS. Each run records its command, duration, the full report, the oracle's status, the worlds explored, and the exact refusal or setup error; a FAIL keeps its case and its replay. Every recording is kept under 90 seconds, so #896 does not decide this study.
- **Control**: before any verdict counts, the checker is run once against the deliberately broken state below and must exit non-zero. A checker that passes its control makes that pair's PASS uninformative, and the pair is recorded as such.
- **Bound**: three targets, one week (#929). A refusal retried on `main` is recorded separately with its commit.

## 1. A dynamically linked, single-process CLI a user installs: GNU sed

- **Target**: GNU sed from Homebrew (`brew install gnu-sed`, run as `$(brew --prefix)/bin/gsed`). Homebrew cannot pin a version; each runner records `gsed --version` and the binary's `codesign -dv`.
- **Operation**: `gsed -i s/mode=old/mode=new/ <state>/app.conf` — an in-place edit, which GNU sed performs by writing a temporary file in the same directory and renaming it over the original.
- **State**: one directory holding `app.conf`, eight lines of `name=value` with `mode=old` on the fourth, written by the setup.
- **Invariant**: after a crash, `app.conf` holds either the whole old content or the whole new content. Checker: compare the file byte for byte with the two expected contents; anything else exits 1.
- **Control**: `app.conf` truncated to its first two lines.
- **Why this shape**: the plainest workflow a macOS user brings — a Homebrew CLI that rewrites one file. `sed -i` was measured on Linux through busybox (`docs/target-classes.md`, busybox row) and toybox; GNU sed on macOS, from Homebrew, with the macOS oracle, is not in any record.
- **Expected**: an oracle-verified PASS, since the edit is a temporary file and a rename (confidence 60%; fs_usage may refuse a call it does not classify).

## 2. A CLI that launches a helper during the operation: git gc

- **Target**: git from Homebrew (`brew install git`, run as `$(brew --prefix)/bin/git`, never `/usr/bin/git`, which is the Command Line Tools' `xcrun` stub). Each runner records `git --version` and `codesign -dv`.
- **Operation**: `git -C <state>/repo gc --quiet` — git starts `pack-objects` (and, depending on the version, `repack` or `prune`) as child processes.
- **State**: a repository with twelve commits of small text files and their loose objects, built by the setup with fixed author and committer dates and names so that its bytes repeat.
- **Invariant**: after a crash, the repository is intact and holds all twelve commits. Checker: `git fsck --full` exits 0 and `git rev-list --count HEAD` prints 12.
- **Control**: the setup's repository with one loose object deleted.
- **Why this shape**: the common case of a tool whose operation is several processes. git was measured on Linux (`git commit`, a PASS; and automatic maintenance, refused `child_touched_state_dir`); `git gc` on macOS is not in any record.
- **Expected**: refused. `fs_usage` refuses a process boundary (`docs/cli.md`, `--oracle-fs-usage`), and `--allow-unverified` does not lift a boundary's refusal, so both explores are expected to name it. #948 (`F_FULLFSYNC`, which git uses on macOS) may be met first (confidence 60%).

## 3. A workflow entered through a protected system executable: plutil

- **Target**: `/usr/bin/plutil`, the macOS property-list tool. Each runner records `codesign -dv /usr/bin/plutil`.
- **Operation**: `/usr/bin/plutil -convert binary1 <state>/prefs.plist` — converts an XML property list to the binary format in place.
- **State**: one XML property list with a dictionary of five keys, written by the setup.
- **Invariant**: after a crash, `prefs.plist` is a valid property list holding the same five keys. Checker: `plutil -lint` exits 0 and `plutil -extract name raw` prints the expected value.
- **Control**: `prefs.plist` truncated to half its bytes.
- **Why this shape**: by definition this shape is an Apple platform binary, and `docs/target-classes.md` already records that wall for plutil: `no_shim_marker` on macOS 15, and `recording_run_failed` (an arm64e mismatch) on macOS 26. `/bin/sh` reaching a user binary is the same wall. What is new is the release (v1.15.0) and the host (macOS 14, never measured for this shape). A script written for this study would not be a real workflow, so none is used.
- **Expected**: refused at the recording on both hosts — `no_shim_marker` or `recording_run_failed` (confidence 80%).

## What would change the conclusion

The study's one product-facing conclusion is which of these shapes the current release can honestly be recommended for on macOS, and either one narrowly scoped next change supported by repeated evidence, or no new product change. A known #896 or #829 reproduction is written on that issue, not here.
