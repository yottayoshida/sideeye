# 0092 — A define command that cannot be started is refused before it runs

- **Status:** Accepted (2026-10-06)
- **Refs:** #701 (from the 2026-10-05 whole-product review, measured with the v1.8.0 brew binary
  on macOS arm64); ADR 0030 (a refusal reports what was observed); ADR 0041 (the apparatus
  check, the precedent for a SETUP ERROR raised after `setup` has run); ADR 0090 (`searchPath`).
- **Scope:** `src/image.zig` (`startable`), `src/posix.zig` (`isRegularFollowing`),
  `src/refuse.zig` (`unstartable`, the sentence), `src/main.zig` (its two call sites), `src/contract.zig`,
  `spike/acceptance.sh`, `docs/cli.md`, `docs/report-schema.md`.

## Context

The engine spawned `setup`, `operation` and `check` and read back how each ended. When the
file named was not there, or had no execute bit, the fork stub's failed `exec` exited 127, and
each gate downstream took that number for a fact about the target:

- an absent or mode-644 checker passed the falsification gate — 127 is non-zero, which the gate
  reads as "the checker went red on a corrupted state" — and the baseline world then refused
  `baseline_violates_invariant`, "the checker rejected the state the operation leaves on its
  own". A judgement by a checker that never ran;
- an absent operation was `recording_run_failed`, whose detail points at `--expect-status`;
- an absent setup was `--setup exited 127; it wrote nothing`, which is true and names no file.

ADR 0030 keeps a refusal to what was observed. What was observed in all three is that `exec`
failed; what was reported was what a running command would have meant by that status.
`CLAUDE.md` already records the 644-script accident from campaign 2, where exactly this cost a
sealed exploration.

## Decision

1. **Ask before running.** `image.startable(argv0, cwd, PATH)` resolves argv[0] the way the
   spawn does — a name with a `/` against the directory the command runs in, a bare name along
   `PATH` with `PathSearch` (`searchPath`'s walk one candidate at a time — the search `__filter-exec` uses, ADR 0090) — and answers `ok`,
   `missing` (ENOENT, ENOTDIR), `not_regular`, `no_exec_bit`, `unreachable_path` (any other
   `access` failure, with its errno and no instruction built from it), `not_on_path`, or
   `not_judged`. A file that passes is read once for a `#!` line and the interpreter it names
   is put to the same test, as is the single name a `#!/usr/bin/env NAME` line hands to `env`.
   A bare name follows execvp's rule rather than stopping at the first file: execvp moves past
   a candidate whose `execve` fails ENOENT or EACCES — what a missing or non-executable
   interpreter makes it fail with — so the name is refused only when every executable file of
   that name on `PATH` fails that way. A failing `env NAME` line stops the search where it is,
   because `env` itself executes and then exits 127. (The first draft stopped at the first
   candidate and refused a define execvp would have run; the diff review caught it.)
2. **Refuse as `environment`.** The closed set (ADR 0057) already defines that class as "the
   engine asked the machine for something and was refused … a path that would not resolve";
   `define_invalid` excludes path resolution by its own definition, and `setup_failed` is a
   setup that was handed to `exec`. No class is added. The sentence names the define key, the
   resolved file, and which fault — under `--config` argv[0] is already the toml-resolved
   absolute path, so the key and the file are what identify the command.
3. **Where.** The setup in phase 0, after the state directory has resolved and `assertSafeRoot`
   has passed, before `--fresh-state` — with the state and work directories this run made
   undone, so nothing is left on disk — and under `--fresh-state` asked once more after the
   emptying, because a setup that lived inside the state directory is gone by then and would
   otherwise read `--setup exited 127` again. Not earlier: the CLI self-description check pins the base
   command's first refusal (a `--state` that does not resolve), and a refusal of a dummy
   `--setup` raised ahead of it would read as a flag no mode accepts — the shape `src/cli.zig`
   records for `--oracle-fs-usage` (#406). The operation and the checker after the setup has
   run, before the first snapshot (beside the apparatus check): a setup that builds the
   operation or writes the checker is a define this must not refuse.

## Alternatives considered

- **Report the exec failure from the child**, an errno over a close-on-exec pipe. It would also
  catch an image built for another CPU. Rejected: under `--oracle` strace execs the operation and
  under `--observe supervised` `__filter-exec` does, so the engine's fork stub is not on every
  path; and it changes all five spawn variants, one of which every world runs through.
- **All three before phase 0**, as #701 first proposed. Rejected for the reason in Decision 3.
- **Read 127 from the checker as "could not start"** at the falsification gate. Rejected: 127
  is also the honest exit of a checker whose `sh -c` did not find a command. A guess.

## Consequences

- Exit codes move for these inputs (the freeze fixes verdict-to-code, not which input reaches
  which verdict): an absent or mode-644 checker 2 → 3, and 0 → 3 on the zero-operation PASS path,
  which never runs the checker; an absent operation 2 → 3 under explore, replay and preflight.
  An absent setup stays 3, with a sentence that names the file.
- Not judged, and still arriving as the status they always did: a bare name when `PATH` is unset
  (the libcs' default lists differ, ADR 0090), an `env` line with a flag or a second word (Linux
  hands the rest of the line to `env` as one argument, macOS splits it), a relative interpreter,
  an image built for another CPU, a second level of `env`.
- The `[recovery]` commands are not asked about. A recovery changes no verdict and no exit code
  (ADR 0072); refusing the run over one would make a found FAIL exit 3. One that cannot start
  stays `recovery.result` `unknown`. (Owner decision, 2026-10-06.)
- A file present at the check and gone at the spawn still reaches the old readings. The check
  narrows the window; it does not close it.
- A checker the operation itself would create is refused, where it used to be found by the time
  the falsification gate ran it. The question has to come before the recording run: a SETUP
  ERROR after it would claim that none of the define had run (#363). Writing the checker in
  `setup` is the way past it.
- Under `--observe supervised` and `--oracle` the operation is launched from the first file on
  `PATH`, with no execvp to move past it; a broken `#!` there with a working file later passes
  this check and fails at the spawn as before — a refusal missed, never one added.
