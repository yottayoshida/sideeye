# 0126 — The engine drops `SIDEEYE_KILL_AT` and `SIDEEYE_KILL_GROUP` from its own environment

- **Status:** Accepted (2026-10-14)
- **Refs:** #822 (found by reading the source in the 2026-10-11 survey; reproduced 2026-10-14);
  the `run_by_hand_signalled` step in `src/contract.zig`, which this makes hold; `docs/cli.md`'s
  `reproduce` paragraph.
- **Scope:** `src/contract.zig` (`env.removed_at_start`), `src/main.zig` (`main`), `src/posix.zig`
  (`unsetenv`), `src/mcp.zig` (`SIDEEYE_MCP_CHILD_ENV`), `spike/acceptance.sh`,
  `spike/mcp-acceptance.sh`, `docs/cli.md`.

## Context

The engine starts every child with its own environment plus the variables it sets. For the
recording run it pins four of the shim's control variables empty — `SIDEEYE_SEQ_BASE`,
`SIDEEYE_BEFORE_CONSTRUCTOR`, `SIDEEYE_KILL_CGROUP`, `SIDEEYE_KILL_ASIDE` — so an ambient value
cannot steer the recording, but not `SIDEEYE_KILL_AT` or `SIDEEYE_KILL_GROUP`. The shim reads
`SIDEEYE_KILL_AT` in every process it is loaded into and kills itself at that operation number.

An operator who exported the two (the `reproduce` line pasted in pieces) had every later run
refused. Measured on 2026-10-14 in `debian:bookworm-slim` (aarch64) at `e371ffe4`, with
`SIDEEYE_KILL_AT=1 SIDEEYE_KILL_GROUP=1` exported: `sideeye demo`, `explore` with and without
`--oracle`, and `preflight --twice` on the demo's toy were all UNKNOWN `recording_run_failed`,
"killed by signal 9"; without the variables the same commands gave FAIL 1 of 6 three times and
exit 0. The refusal's step sends the operator to run the operation by hand, where no shim is
loaded, the variable does nothing, and the operation succeeds.

## Decision

`main` removes both variables from the engine's own environment, after the filter installer's
early exit and before anything else runs. Every child the engine starts inherits the engine's
environment (the libc `environ` before `execvp`) or one built from named pairs only (the MCP
adapter's child), so none of them carries either variable unless the engine sets it — and only a
world's spawn does.

## Alternatives considered

- **Pin them empty on each spawn, as the other four are.** `SIDEEYE_KILL_GROUP` arms the group
  kill on its presence, so an empty value still arms it. Removing it on each spawn needs a new
  "names to remove" parameter through `runChildImpl` and its callers, and every spawn site added
  later has to remember it.
- **Refuse to start when either is set, naming it.** The only thing the operator can do with that
  refusal is unset the variable and run again, which the engine can do itself; the four pinned
  variables are already overridden without a word.

## Consequences

- With either variable exported, every run gives the verdict it gives without it. After this
  change, the four measurements above gave FAIL 1 of 6 three times and exit 0, the same as
  without the variables.
- A Sideeye explored by Sideeye no longer passes the outer world's `SIDEEYE_KILL_AT` to the children
  the inner engine starts. The outer shim in the inner engine's own process has already read it, so
  a crash point in that process still lands; one that falls in a child of it is expected not to,
  and to be refused `kill_did_not_land`. Not measured.
- `SIDEEYE_MCP_CHILD_ENV` refuses to name either variable, saying why. The server removes them at
  start like any engine, so without this the refusal for a listed name the server lacks would
  have said the server environment did not have it, although it was exported.
- The `reproduce` line is unchanged: it sets `SIDEEYE_KILL_AT` itself and unsets
  `SIDEEYE_KILL_GROUP` for the operator's own shell, as before.
