# 0134 — Every workflow's runner names its OS version

- **Status:** Accepted (2026-10-15)
- **Refs:** #831 (found in the 2026-10-11 survey); ADR 0061 (actions pinned by commit, the same
  reasoning applied to the other moving pointer in a workflow).
- **Scope:** every file under `.github/workflows/`, `spike/check-action-pins.sh`,
  `spike/release-build-flags.sh`'s fixture.

## Context

`runs-on: ubuntu-latest` and `runs-on: macos-latest` are labels GitHub repoints. #831 records
that `ubuntu-latest` begins moving from Ubuntu 24.04 to Ubuntu 26 on 2026-10-19. When a label
moves, every job on it changes OS on the next run with no commit in this repository, so the
first red after the move reads as a regression of whatever pull request happened to be open —
and all four required checks (`linux`, `macos`, `crash-consistency`, `required`) ran on those
labels.

What the labels point at today, read from the "Runner Image" section of a `main` run's logs
(run 38683137277): `ubuntu-latest` is `ubuntu-24.04` (24.04.5), `macos-latest` is
`macos-26-arm64` (macOS 26.6.2).

## Decision

Every `runs-on:` and every matrix value that names a runner names the OS version:
`ubuntu-24.04` and `macos-26`, the images the labels point at today, so this change moves no
job to a different OS. Moving to a newer OS is a pull request that changes the name and is
read like any other change.

`spike/check-action-pins.sh` refuses any line in a workflow file that names `ubuntu-latest`,
`macos-latest` or `windows-latest`. It matches the word, not the `runs-on:` key, because a
matrix carries the label with no key beside it; a comment naming one is refused too, and the
remedy is to reword the comment. Other keys that say `latest` (`zig: latest`, a lane called
`latest`) are not runner labels and pass. The check refuses those three labels and nothing
else: a label with no version that is not `-latest` (`ubuntu-slim`, or one read from
`vars`) passes it, and no workflow uses one today.

## What this does not do

The images under a named version still update weekly — packages, toolchains, the kernel patch
level. GitHub offers no way to hold an image, so the property is the OS version, not the
image. A failure that tracks an image update rather than a commit is still possible after
this, and is read against the "Runner Image" section of the failing run.

## Alternatives considered

- **Stay on `-latest` and fix what breaks after 2026-10-19.** That is the state #831 records;
  it makes the OS change arrive inside unrelated pull requests.
- **Move to `ubuntu-26.04` now.** That is the upgrade, not the pin; it belongs in its own pull
  request, read for what it changes, once the version has been seen green here.
- **Check only `runs-on:` lines.** Misses the matrix values, which is where `zig-ahead.yml`
  and `release.yml` name their runners.
