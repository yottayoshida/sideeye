# 0128 — Paths through macOS's `/tmp`, `/var` and `/etc` links are placed under `--oracle-fs-usage`

- **Status:** Accepted (2026-10-14)
- **Refs:** #795 (measured in the platform probe, #697, ADR 0105); `docs/cli.md`'s
  `--oracle-fs-usage` paragraph, which says a single-process run "is explored and judged under it
  as under `--oracle`" and now holds however `--work` is spelled and wherever under those links the
  target writes; the platform table's macOS row.
- **Scope:** `src/main.zig` (`Run.Define.work_abs`, the recording run's trace and standard-output
  paths), `src/fsusage.zig` (`operandOf`, `isTruncated`, `capturesPath`, `read`),
  `spike/fsusage/acceptance-local.sh` (checks 10 and 11), `.github/workflows/ci.yml`,
  `docs/cli.md`.

## Context

Under `--oracle-fs-usage`, the reader finds the subject as the thread that opened the shim's trace
file for writing. When `--work` was reached through a symlink — the default `/tmp/sideeye-work`
(macOS's `/tmp` is a link to `private/tmp`), or `$TMPDIR` as macOS sets it (through `/var`) —
every single-process run was UNKNOWN `oracle_saw_nothing`: no thread in the capture wrote to the
trace file.

The plan assumed fs_usage prints the resolved path, so that comparing against `--work` resolved
would be enough. That assumption was wrong. Measured on GitHub's `macos-26` runner with the
capture kept (run 38519698057), an open that went through `/tmp` is printed as the link's text
followed by the rest, with no leading slash:

    open  F=3  (RWCA__N_F__X___)  private/tmp/platform-measure-ni3YO5/default/trace-record.bin

The reader read that as no operand at all. With the trace path alone resolved, the run went one
step further and was refused on the engine's own open of the standard-output capture,
`private/tmp/…/stdout-record.txt`, read as a pathname cut at the display width
(run 38520588693). The first review then pointed out that the same reading meets any write the
target makes through those links, inside the state or not — a log under `$TMPDIR`, for one — and
that the refusal names the wrong cause.

## Decision

- **The engine opens nothing under `--work` through a link while fs_usage watches.** `phaseDefine`
  keeps `--work` resolved (`Run.Define.work_abs`, the `realpath` it already took to refuse a work
  directory inside the state). The recording run's trace path, which the shim opens, and its
  standard-output capture, which the engine opens for the operation, are built from it.
  Everything else under `--work` keeps the spelling given: cases, evidence, the `reproduce`
  line's trace, and the worlds' traces.
- **The reader places an operand that begins `private/tmp/`, `private/var/` or `private/etc/` as
  that path with a slash in front**, and does not take it for a cut pathname. These are what
  macOS's root links `/tmp`, `/var` and `/etc` point to. A pathname cut on the left is slashless
  too. One cut just below `/` or `/System/Volumes/Data` names the same file, since the reader
  already treats those two as one. One cut at a `private/tmp/` deeper in a longer path is placed
  wrongly. The state directory's length check before the run keeps such a path out of the
  state.

## Alternatives considered

- **Compare the trace path against `--work` resolved, in the reader.** The plan's first design;
  measured not to help, since the printed path is neither spelling.
- **Read every slashless operand as absolute, or both ways.** A pathname cut on the left is
  slashless, so this would place stumps as paths it guessed. The three roots are the shapes the
  links produce. Any other slashless operand stays what it was.
- **Resolve `--work` for everything.** This changes the paths printed on `replay`, `evidence` and
  `reproduce`, and the case paths the MCP adapter checks against its root, to fix two files.

## Consequences

- Measured on GitHub's `macos-14`, `macos-15` and `macos-26` runners, paired in each run with
  `main` at `e371ffe4` (run 38524109551):
  - The probe's GNU `dd` define, with `--work` under `$TMPDIR` as given, `/tmp`, `/private/tmp`
    and `$TMPDIR` resolved. Before: the first two UNKNOWN `oracle_saw_nothing`, the other two
    FAIL. After: all four FAIL with `oracle_verified` true and 2 crash points.
  - A toy that appends to a log under `$TMPDIR`, outside the state, and then rewrites its state
    file. Before: UNKNOWN `oracle_saw_nothing`. After: PASS 3 of 3.
  - The fs_usage acceptance suite passes all eleven checks on all three runners. Check 10 gives
    `--work` through `/tmp`, through `/var`, and relative. Check 11 is the log under `$TMPDIR`.
- A refusal that names the recording run's trace file names it resolved.
- What `openat(AT_FDCWD, …)` through one of the links prints was not measured. The reader still
  joins a relative `[-2]/` operand to the operation's directory, as before. If fs_usage prints
  `[-2]/private/tmp/…` for one, that line is placed under the operation's directory without a
  word, not refused.
- A target that writes its state through a spelling that goes through one of the links is placed
  by the unit tests only. Every run above wrote its state under `$HOME` or by its resolved path.
- A `--work` deep enough that fs_usage cuts the trace's open still refuses as no subject found,
  and the refusal does not give that reason. The state directory has a length check before the
  run; `--work` has none. This was so before this change.
- CI's macOS job no longer resolves its work and state directories by hand (`pwd -P`) to get past
  this. That step's state is reached through `/var` now, which the runs above did not measure.
  The pull request's CI does.
