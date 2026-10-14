# 0131 — One `required` job needs every CI job, and branch protection requires it

- **Status:** Accepted (2026-10-14)
- **Refs:** #828 (found in the 2026-10-11 survey); `CONTRIBUTING.md`'s "CI fails a pull request
  whose tracked Zig files `zig fmt` would change" and `CLAUDE.md`'s same rule, which this makes a
  merge gate; ADR 0080 (the quickstart's release lane).
- **Scope:** `.github/workflows/ci.yml` (the `required` job), `spike/check-ci-required.py`,
  `main`'s branch protection, `CONTRIBUTING.md`, `CLAUDE.md`.

## Context

`main`'s branch protection required 17 status contexts, listed by job name. `ci.yml` had 19 jobs,
and three of them — `fmt`, `agent-skills` and `zig-ahead-judge` — were not among the 17. A red one
left the merge button enabled, though `CONTRIBUTING.md` and `CLAUDE.md` both say CI fails a pull
request whose Zig files are not formatted. The list was kept by hand, so the next job added to
`ci.yml` would have been optional too, until someone edited the setting.

Two of the required names, `linux` and `macos`, are also the names of the two jobs in
`quickstart-release.yml`, which runs on every pull request and every push to `main`. A required
context is matched by name across every workflow that reports on the commit. Which of the two
GitHub holds a required context to was not measured.

## Decision

- `ci.yml` gets one more job, `required`, with `if: always()` and `needs:` listing every other job
  in the workflow. `spike/check-ci-required.py` reads `${{ toJSON(needs) }}` and fails unless each
  result is `success`. It reads the workflow too, and fails when a job of the workflow is missing
  from `required`'s `needs:` or `needs:` names a job that is gone. A job added to `ci.yml` without
  that edit turns `required` red the day it lands.
- Branch protection requires `required`, `crash-consistency` (`quickstart.yml`), `linux` and
  `macos`, in place of the 17. The fourteen `ci.yml` names it drops are all covered by
  `required`'s `needs:`. `linux` and `macos` stay as they were: what they hold
  `quickstart-release.yml`'s jobs to is the same as before, and the name overlap is left as found.
- The protection changes once, before this pull request merges, with the owner's approval and the
  setting before it kept so it can be put back: from the 17 to the four. The documents that say
  `main` requires `required` are then true from the moment they land. The checks stay bound to
  GitHub Actions (`app_id`), as the 17 are. Between that change and this merge no other pull
  request can merge, since none reports `required` until its run reads a workflow that has it.

## Alternatives considered

- **Add the three missing names to the list.** The list stays hand-kept, so the next job is
  optional again; this is the mechanism that went stale.
- **Rename `quickstart-release.yml`'s jobs so the names no longer overlap.** That file is the one
  `docs/ci-quickstart.md` tells adopters to copy, and its job names are part of that page.
- **Make the protection `strict`** (a branch up to date with `main` before it merges). It is a
  different problem from this one, and it would make every pull request rebase.

## Consequences

- A pull request with any `ci.yml` job not `success` — failed, cancelled or skipped — cannot be
  merged once the protection requires `required`.
- Removing a job no longer stops at the protection. With the names listed, a pull request that
  deleted or renamed a job left that context unreported and could not merge. Now a pull request
  that deletes a job and its `needs:` entry together goes green, and catching that is left to
  review.
- A pull request's run reads the workflow of its merge ref, so a branch opened before this job
  gets `required` on its next push or reopen; only re-running an older run does not.
- `quickstart-release.yml`'s `linux` and `macos` are held exactly as before; whether GitHub
  requires both same-named check runs or one of them is still not measured.
