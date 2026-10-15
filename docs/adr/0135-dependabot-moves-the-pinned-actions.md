# 0135 — Dependabot moves the pinned actions, and a pull request tries what it moved

- **Status:** Accepted (2026-10-15)
- **Refs:** #831 (found in the 2026-10-11 survey); amends ADR 0061 (every action is pinned by
  commit), whose Consequences named this as the answer if manual updates became the problem;
  ADR 0134 (runner labels, the other half of #831).
- **Scope:** `.github/dependabot.yml`, every `uses:` under `.github/workflows/`,
  `.github/workflows/release.yml` (the `assets` and `upload` jobs),
  `spike/check-action-pins.sh` (its sunset and the hint for resolving a tag).

## Context

ADR 0061 pinned every action by commit and said what that cost: "Action updates become
manual. Nothing tracks upstream releases now." #831 found the result a month later — the
pins where 0061 left them, `actions/checkout` at v4 against v7.0.1, `upload-artifact` and
`download-artifact` at v4 against v7.0.2 and v8.0.2. Nothing had asked anyone to move them.

Two things stood between an update and finding out it was wrong. `download-artifact` ran in
one job, `release.yml`'s `upload`, which a pull request skipped: a new version of it would
first run at the next release, with the token that attaches the binaries. And the hint the
check printed for resolving a tag, `git/ref/tags/<tag> --jq .object.sha`, returns the tag
object's SHA for an annotated tag rather than the commit's (measured on `git/git` v2.50.0:
`192a0a2c…` against `16bd9f20…`); the four actions here use lightweight tags, where the two
agree, so it had not bitten yet.

## Decision

1. **The four actions move to their latest releases now**, by commit with the version
   beside it: `actions/checkout` v7.0.1, `actions/upload-artifact` v7.0.2,
   `actions/download-artifact` v8.0.2, `mlugg/setup-zig` v2.2.1 (its SHA was already
   v2.2.1; the comment said `v2`).
2. **`.github/dependabot.yml` moves them from here on**: GitHub Actions, weekly, one pull
   request for every minor and patch update together, a pull request of its own for each
   action's major version (a major matches no group), and no version younger than seven days
   (`cooldown`). Dependabot rewrites a SHA pin and its version comment; a pin stays a SHA.
3. **`release.yml` tries `download-artifact` on every run.** The build writes each tarball's
   SHA-256 beside it into its artifact, and a new `assets` job, read-only, downloads them and
   checks that three tarballs arrived and each matches its checksum — the bytes the build's own
   inventory check read. The checksums stay in the artifacts; `upload` attaches only the
   tarballs, and the release still carries no SHA256SUMS (ADR 0061). `upload` keeps `contents: write` and runs only for a release or a dispatch that
   names a tag, after `assets`. They are two jobs because `permissions` takes no expression:
   one job that ran on pull requests and could upload would hold the write token on every
   pull request. `release.yml` runs on pull requests that touch it, and it uses all four
   actions, so every update to any of them touches it and runs it.
4. **`check-action-pins.sh` stays.** ADR 0061 said a Dependabot configuration would make it
   the second place one judgment lives. It does not: Dependabot moves a pin that is already a
   SHA and leaves a newly written `@v4`, or an `ubuntu-latest` (ADR 0134), where it is. Its
   hint resolves a tag through `commits/refs/tags/<tag> --jq .sha`, which gives the commit for
   both kinds of tag and refuses a name that is only a branch.

## What this does not do

A pull request runs each action, not every way this repository uses it. These uses run only
off a pull request:

- `upstream-watch.yml` pushes a branch with the credentials `actions/checkout` leaves behind,
  and checkout v6 moved those from `.git/config` to a separate file. It runs only on `main`,
  and pushes only when its tracker has something the open pull request does not, so a green
  run proves nothing until its log shows `opened <url>`, printed only after the push and the
  pull request both succeed; the first such run after this merges is the check. A push that
  fails prints `BROKEN` and turns that job red rather than passing quietly.
- `spike-platforms.yml` runs `actions/checkout` inside a Rocky Linux 8.10 job container, on
  `windows-2025` and on `windows-11-arm`, on dispatch only; no workflow a pull request runs
  uses a Windows runner.

`assets` is not a required check: `release.yml` runs only on pull requests that touch it, and a
check that does not run on every pull request cannot be required. A red `assets` on a
Dependabot pull request is seen, not enforced; a release whose download fails stops at
`upload`, which needs it.

## Alternatives considered

- **Move the pins by hand on a schedule.** That is what 0061 left, and #831 is what it
  produced: nothing prompted the move.
- **Renovate.** Equivalent for this, and one more app with write access to the repository.
- **Pin to tags again.** Reverses 0061; a tag is a pointer its owner can move.
- **One Dependabot group for everything, or one for every major version.** A major version's
  breaking change would ride in the same pull request as a week of patches, or as another
  action's major, and be read as one of them.
