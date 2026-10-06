# 0094 — Preflight reads a toml as explore reads it

- **Status:** Accepted (2026-10-06)
- **Amends:** ADR 0019's Consequences ("`sideeye preflight` cannot take an argv-form define …
  refuses `--config`"), and ADR 0093's Consequences ("… or by preflight, which reads no toml").
  Each is recorded on its page as a dated note pointing here.
- **Refs:** #704 (from the 2026-10-05 whole-product review); the detectors this reuses:
  #682/#683 (ADR 0091, a state that is not a directory, no crash point), #701 (ADR 0092, a
  command that cannot be started), #700 (ADR 0093, the `cwd` a toml's define needed);
  ADR 0072 (a recovery is never a refusal).
- **Scope:** `src/cli.zig` (the preflight refusals, the synopsis and the help text),
  `src/main.zig` (`phasePreflight`, `preflightReport`, the recovery note, the define's
  `config_dir`), `src/refuse.zig`
  (`checkerArgv`, `refuseNothingToCorrupt`), `spike/acceptance.sh` (#273's bases, check
  6c), `docs/cli.md`,
  `docs/ci-quickstart.md`, `docs/scouting.md`, `spike/assisted/SCOUT.md`.

## Context

`sideeye preflight` asks one question — does the recording phase accept this target? — from
the define flags, and refused `--config`: "once a sideeye.toml exists, `sideeye explore
--config` answers strictly more". ADR 0019 wrote the consequence down when it added the argv
form, which only a toml can spell: such a define went straight to explore.

That made the toml a one-way door. A user who had moved the define into a file — the README's
own next step after preflight — could no longer ask the quick question of it, and a mistake in
the file (a check that is not executable, a `state` that names a file, a marker the operation
never prints) surfaced only from a full exploration, or not until after one had explored
worlds. The issue measured it with the v1.8.0 binary: `preflight --config` exits 3 before
reading the file.

Every detector that can name such a mistake already runs before the first crash world, in phases
explore and preflight share: the config parser, the `cwd`/`apparatus`/`scratch` checks, the
state-directory check, `startable`, the marker scan of the recording's stdout, the
zero-crash-point refusal, and the `cwd` observation. What kept preflight from them was one
refusal in the parser.

## Decision

**`sideeye preflight --config <toml>` reads the toml through the same code explore does and
refuses the define mistakes those shared detectors see, before any crash world, in explore's
words.** `docs/cli.md` lists them; the list says only what is true at this change, and grows with
the detectors.

1. **The parser's refusal of `--config` goes.** `--check`, `--marker` and `--recovery` keep
   their by-name refusals when there is no `--config`, reworded to say a toml's are read by
   `preflight --config`. With `--config` they are define-surface flags beside a config, and
   the refusal is explore's own ("mutually exclusive"), reached first.
2. **Two of explore's refusals are added to preflight, where explore reaches them.** With a
   declared check and a crash point, explore's first refusals for the check come from
   `phaseChecker`, in this order and before any world: a command with no words in it (`check =
   " "` passes the parser), `--check is empty`; then an initial state with nothing to corrupt,
   `checker_not_falsified`. Each is one function, `refuse.checkerArgv` and
   `refuse.refuseNothingToCorrupt`, called from both, after the zero-crash-point refusal as in
   explore: with no crash point both answer `nothing_could_fail` and neither reaches the checker.
   The first was found by the change's review, after the second was written.
3. **Nothing a toml declares is run.** The check goes through the refusals above and #701's
   start check, and is not run; preflight explores no world, so there is nothing to falsify
   against. The report says it was not refused, not that it will start: the start check leaves
   some files unjudged (an execute-only one; the script an interpreter is handed), and such a
   check fails only when explore runs it (the change's second review). A
   `[recovery]` is not started either: a recovery that cannot be started is explore's
   `unknown`, with no effect on the verdict or the exit code (ADR 0072), so refusing it here would
   be a detector explore does not have. The report names each as declared.
4. **The `next` hint names the toml** — `sideeye explore --config '<path>'`, quoted for /bin/sh —
   since the toml is the define. The path is the toml's resolved directory joined with its own
   name: that directory is what its relative paths were resolved against, here and when the line
   is pasted. A toml that is a symlink to another directory keeps its own side; named by its
   target, the pasted command would resolve against the target's directory and run another
   define (the change's review). A toml read from `/dev/stdin` — piped, or redirected from a
   file, its directory `/dev` either way — from a shell's `<(…)`, or through a link whose chain
   passes through `/dev` or `/proc` (read link by link: Linux's realpath follows
   `/proc/self/fd/0` to the redirected file), may not read the same way twice, and a name
   `textShown` would rewrite cannot be pasted as printed; the hint says which, and to save or
   copy the define to a plain file instead. zsh's `=(…)` is an ordinary temporary file and is
   named as one; it is gone once the command ends, and the pasted command says so.

## Alternatives considered

- **A new command (`sideeye check-config`).** Rejected: a second entry point for the same
  question, with a second description to keep true.
- **Refuse a world-dependent mistake from the recording too** — an operation whose recording
  touched nothing the verdict judges, in a toml with no check or marker. Rejected: a crash world
  can take a branch the recording did not, so explore can reach a verdict on that define, and
  refusing it here would say something explore does not. ADR 0091 keeps that judgement out of
  the recording for the same reason.
- **Report every mistake in one run.** Rejected: every refusal exits, in explore as here, and
  changing that is a different promise. Preflight refuses one mistake per run, the first met.
- **Ship before the detectors it reuses.** Considered: the list could carry only what was
  merged. Not taken because each later merge would have had to add its row here from another
  session; this change waited for #682/#683, #700, #701 and #702 instead.

## Consequences

- The flags' preflight accepts and refuses the inputs it did, and its accepted report is byte
  for byte what it was (measured against the parent commit, with and without `--twice`; the
  existing preflight legs pin it). Its three by-name refusals of `--check`, `--marker` and
  `--recovery` are reworded to name `--config`, and flags given beside `--config` get explore's
  "mutually exclusive" refusal, where the parser refused `--config` itself before.
- A toml's preflight report adds `marker`, `checker` and `recovery` lines for what it declared,
  and drops #682's parenthesis on `nothing_could_fail` from `not checked` when a check or a
  marker is declared — the sentence is about a define that declares neither.
- `--twice` reads the toml's state, and its lines say `[world] state` where the flags' say
  `--state`.
- Not on the list, and said there: what only a crash world shows, and anything `startable` does
  not look at (`sh check.sh` names `sh`, not the script).
- Check 6c of `spike/acceptance.sh` runs one toml per listed mistake through both commands and
  compares the exit code, the refusal line and its detail, with the check counting its own
  starts. The same suite against the parent commit with only the `--config` refusal removed fails
  twelve of its legs, and #273's check with them, and passes the rows the merged detectors
  already held.
