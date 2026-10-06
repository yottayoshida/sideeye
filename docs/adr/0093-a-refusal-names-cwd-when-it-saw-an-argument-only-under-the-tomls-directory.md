# 0093 — A refusal names `cwd` when it saw an argument only under the toml's directory

- **Status:** Accepted (2026-10-06)
- **Amends:** ADR 0086's "What this does not do" ("does not change the refusal's wording"); its
  Alternatives entry "Diagnose the cause in the refusal" is kept, and this ADR says why it does
  not apply. The amendment is recorded on that page as a dated note pointing here.
- **Refs:** #700 (from the 2026-10-05 whole-product review, measured with the v1.8.0 brew binary
  on macOS arm64); ADR 0007 (a toml's paths resolve against its directory); ADR 0030 (a refusal
  reports what was observed).
- **Scope:** `src/refuse.zig` (`toml_dir`, `cwdObservation`, `cwdStep`, `withObservation`),
  `src/main.zig` (four refusals and the toml's directory), `src/contract.zig`
  (`NextStep.declare_cwd`), `spike/acceptance.sh`, `README.md`, `docs/cli.md`,
  `docs/report-schema.md`.

## Context

A toml resolves `[world] state` and each command's argv[0] against its own directory (ADR 0007);
every other argument is handed to the command as written and resolves against the directory the
command runs in — Sideeye's own when no `cwd` is declared. The README's toml example declared no
`cwd`. Run from anywhere but the toml's directory, a define written in its shape with a relative
argument (`setup = "./cfgset ./state/config.json theme light"`) failed — `--setup exited 1`, or
`recording_run_failed` with advice about `--expect-status` — and the `cwd` line ADR 0086 added
said `(none declared: Sideeye's own)` without being referred to.

The root fix would make a toml's commands run in its own directory when none is declared. The
owner declined it (2026-10-06): `docs/contract-freeze.md` surface 1 freezes the meaning of an
accepted spelling, and every toml that relies on running in Sideeye's directory would move
silently.

## Decision

1. **Observe, do not guess.** When a command read from a toml that declares no `cwd` fails, and
   the toml's directory is not the one the command ran in, the engine looks at that command's
   arguments (and the value of an `--opt=value`) for one that is relative, present under the
   toml's directory and absent under the directory the command ran in — or, walking up from it, a
   directory above it that is: the commonest relative argument names a file the command is about
   to create (`./state/config.json`, the shape #700 was measured on), which is under neither, in a
   directory that is under one only. That is a fact about two paths, measured at the refusal —
   not a claim about why the command failed. ADR 0086 declined
   "the operation may need a `cwd`" because the engine did not know; here it states what it saw.
2. **Where**, named branch by branch rather than by a rule: `setup_failed` when the setup exited
   non-zero; `recording_run_failed` for an undeclared exit status or no normal exit;
   `marker_never_observed`; `nothing_could_fail` with no crash point, whose step is otherwise
   `nothing_in_state` (ADR 0091 — an operation that found nothing to do where it ran records
   nothing); `checker_not_falsified` when the checker accepted the corrupted state;
   and `baseline_violates_invariant`'s checker layer. Each looks only at its own command's
   arguments. A config named through a link or read from a pipe (`/dev/stdin` resolves to a
   regular file through its link, and its directory is still `/dev`) is never asked.
3. **What it says.** The detail gains the observation —
   `./seed is under the toml's directory /proj and not under /home/u, where the commands ran` —
   and `next_step` becomes `declare_cwd` ("Add cwd = "." under [define]: …") where the site would
   have said `fix_define`. It never replaces `syscalls_may_have_killed`. A SETUP ERROR has no
   `next_step`, so there the observation and the line to add share the one sentence, as other
   SETUP ERRORs carry their remedy — and so do the refusals under `--observe syscalls`, whose step
   stays the mode's. (The first draft left those naming the observation but not the line; the
   diff review caught it.)
4. **The README's example declares `cwd = "."`**, so a define copied from it means the same thing
   from any directory.

## Alternatives considered

- **Run a toml's commands in its directory by default.** Declined by the owner (Context).
- **Match the argument's shape** (`./…`, or anything with a `/`). Rejected: `origin/main` looks
  relative and `app.db` does not, and a shape is a guess about intent — the thing ADR 0086 kept
  out of refusals.
- **Name `cwd` on every failure of a toml define run from elsewhere.** Rejected for the same
  reason: an operation that exits 1 for its own reasons would be told to add a line that
  changes nothing.

## Consequences

- `next_step` gains a member. It is not a closed set (`docs/contract-freeze.md` closes
  `unknown_reason` and `setup_error_reason`); ADR 0069 added one the same way.
- Seen nowhere: a file the command would create in a directory present in both places, or in
  neither (unless a directory further up is under the toml's only); a relative argument that finds a different file where it ran and succeeds; and an
  operation that writes outside the state directory through an argument that names nothing on
  either side — refused `nothing_could_fail` since ADR 0091, with `nothing_in_state` as its step.
  The README's `cwd` line is what prevents those.
- Not asked under flags (their relative arguments resolve where the operator typed them), on a
  replay (a case carries no toml), or by preflight, which reads no toml.
