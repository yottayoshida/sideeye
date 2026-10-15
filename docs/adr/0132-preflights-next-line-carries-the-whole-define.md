# 0132 — Preflight's `next` line carries the whole define, each word quoted as a shell reads it back

- **Status:** Accepted (2026-10-15)
- **Refs:** #823 (found in the 2026-10-11 survey); `docs/cli.md`'s "ends with a `next` line, the
  `explore` command for the define it just accepted"; `docs/mcp.md`'s "names what to call next on a
  `next:` line"; ADR 0130 (a shim found on its own is not named on the printed lines).
- **Scope:** `src/report.zig` (`NextDefine`, `NextRun` and the two functions that spell them),
  `src/main.zig` (`preflightReport`, `PreflightHint`), `src/cli.zig` (`work_named`, `synopsisFlags`
  made public for a test), `src/mcp.zig` (`summarizePreflight`), `spike/acceptance.sh`,
  `docs/cli.md`.

## Context

The flags form of the line was built from four of the define's parts — state, setup, cwd,
operation — plus `--expect-status`. `--apparatus` and `--scratch` were dropped, so explore ran a
different define: without the scratch declaration its baseline met the divergence preflight had
been told to ignore. `--state-under` was dropped in both forms. It only narrows what explore may
empty, so nothing refused; the pasted command simply ran without the bound the operator asked for.
The state was printed bare and the other parts in double quotes. A `$` or a backquote was expanded
by the shell the line was pasted into — on main before this change, a state path holding
`` `id` `` ran `id` and passed its output to explore as four words.

The MCP server's `next:` said "with the same config_path". A call that carried `observe` was
followed under the default mode, on both the accepted and the `runs_differ` answer.

## Decision

- The line carries the flags that change the define (`--state`, `--setup`, `--operation`, `--cwd`,
  `--expect-status`, `--apparatus`, `--scratch`) and those explore needs to accept the same run in
  the same place under the same bounds (`--observe`, `--shim` when given, `--oracle`, `--work` and
  `--state-under` when given). A `--work` left off sends explore to the default directory, which
  may be the one another user owns or another run holds — often why the run was given its own.
  It leaves out `--json`, whose file would receive explore's report in place of preflight's
  document, and `--twice`, which explore does not take.
- The words are spelled in one place, `report.nextDefineWords` and `report.nextRunWords`, from two
  structs the caller fills; the call site no longer picks parts one by one, which is how four flags
  went missing. A unit test fills every field, spells the line, and fails when a flag in preflight's
  synopsis is neither on that line nor one of preflight's own, so a flag added to preflight has to
  reach the line.
- `--work` is carried when it was named on the command line (`work_named`), not when its value
  differs from the default: a default written out by hand is still the operator's choice.
- Every word goes through `report.shellWord`, the quoting the `replay` line uses: bare where a
  shell reads it back unchanged, single-quoted otherwise.
- The MCP `next:` names the `observe` the call carried, and names none when the call carried none.

## Alternatives considered

- **Repeat preflight's own arguments verbatim.** explore does not take `--twice`, `--json` would
  replace preflight's document, and the line would still need its own quoting.
- **Leave `--work` off, as an output path.** It is where explore keeps its cases and traces too,
  and the default has refusals of its own (#692, #816) that a run given `--work` may have avoided.
- **Single-quote every word.** Correct, but it changes every line a reader or a test matches
  against for paths that need no quoting. `shellWord` changes only the words that were wrong.

## Consequences

- A word a shell reads back unchanged is printed bare, as before for the state. A command with
  arguments holds a space, so the setup and the operation keep their quotes, now single ones.
- The acceptance leg runs the printed line against a `sideeye` that records its argv and compares
  it word for word with what preflight was given; on main before this change it differs in the
  state, the apparatus, the scratch and the bound.
