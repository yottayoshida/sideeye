# 0100 — A case records the observation mode it was counted under

Status: Accepted (2026-10-09)

Closes #691. A case saved by a run under `--observe syscalls` or `--observe supervised` is
`case_version` 6 and carries a top-level `observe`; a replay given no `--observe` replays it
under that mode, through the CLI and through `sideeye_replay_case` alike. A case counted under
the default is written exactly as before.

## Context

A crash point is a number in one mode's count. `--observe wrappers` counts at the libc entry
points, `syscalls` at the kernel boundary, `supervised` from outside the process, and the same
target can produce different sequences under each — that is why the modes exist. The case
recorded the define, the crash point and the landing context, and not the mode, so the number
in it meant something only beside a fact the caller had to keep elsewhere. ADR 0052 named this
as a known limit when `syscalls` arrived and ADR 0089 again for `supervised`: a case replayed
without its flag refuses — `case_no_longer_applies` for `syscalls`, `no_shim_marker` for a
static target under `supervised` — never with a wrong verdict, but with a remedy that is not
the real one. The report's `replay` line names the flag, which helps a reader of the report and
nobody holding only the file. And `sideeye_replay_case` takes no mode and passes the engine
none, so a supervised case could not be replayed through the MCP server at all (ADR 0074 left
the question open).

ADR 0071 had already declined a version 6 once, for the evidence bundle, on two grounds: every
FAIL that release wrote would stop replaying on any earlier 1.x, and the ladder would start
moving for things that are not part of the question. This record has to answer both.

## Decision

**The mode is written into the case, and only when it is not the default.** `writeCase` puts
`"observe": "syscalls"` or `"supervised"` at the top level, after `contract_version`, and the
case is version 6. A `wrappers` case stays at the version its define asks for, byte for byte —
the ladder's rule that a define declaring nothing keeps the case it always got. The field sits
beside `contract_version` and not inside `define` because it is the same kind of fact (how the
numbering `k` was produced) and because a `sideeye.toml` has no key for it: surface 1 is frozen,
and `define` is what a toml can spell.

**Version 6 keeps version 5's two keys.** From version 5 a case spells `cwd` (null when none was
declared) and `scratch`, because a version holding independent optional fields cannot be held
honest by a one-field gate. Version 6 holds three, so the same law: `cwd` and `scratch` are
spelled, `scratch` as an array that may now be empty — version 5's "non-empty" belonged to the
version that existed for scratch. The reader refuses as malformed a version-6 file whose mode is
missing or `wrappers`, whose `scratch` is missing or not an array (the typed parse cannot tell
an absent key from `null`, so the untyped parse version 5 already makes asks), and an older file
carrying a mode.

**The case's mode wins over silence and refuses a contradiction.** With no `--observe` the
replay takes the case's mode. The same mode named on the command line is accepted — the report's
`replay` line still names it, and so do scripts written against it. Another mode is refused,
`define_invalid`, naming both and the case: a different mode would address a different
operation, which is the shifted address surface 4 promises never to judge. The refusal is
raised after the case is named (`case_note`), so its JSON carries the case in `case` like every
refusal after it; its sentence names the file as well, because a SETUP ERROR's text prints no
`case` line. Only a case that records a mode refuses a flag: a case without one — every case
saved before this change, and every `wrappers` case — takes the flag as it always did, and a
flag that shifts its numbering is caught where it always was, by the prefix hash, as
`case_no_longer_applies`.
The observer named in the oracle account is re-derived at that point too, so a refusal raised
between the case and the recording phase does not name the shim as the observer of a supervised
case, and the platform refusals say the mode came from the case when nobody typed it.

**Nothing changes on the MCP surface.** The server's replay passes no `--observe`, so the engine
takes the case's mode; `--shim`, which the server always passes, is unused under `supervised`.
The one change is a sentence in `sideeye_explore_config`'s `observe` description, which said a
supervised case could not be replayed through `sideeye_replay_case`; it now says such a case is,
and that a case saved before cases recorded the mode replays there under the default. The schema's keys and types
are unchanged (surface 5).

**ADR 0071's two grounds, answered.** The ladder moves for the *question*: under another mode a
case's crash point names a different operation, so the mode is part of what a replay re-asks —
the evidence is not, and ADR 0071's decision stands for it. And the version moves only for the
cases that need it: a `wrappers` case, the default and the large majority, replays on every
earlier 1.x as before. What is given up is real and stated: a `syscalls` case could be replayed
by v1.10 with the flag, and a version-6 case cannot — the strict parse refuses it as a file it
cannot read, before the version gate, the way version 5 was refused by every reader before it.
That is surface 4's honest refusal, never a verdict.

## Alternatives considered

The owner chose among three on 2026-10-09:

**Write the mode beside the case, in a file of its own.** No version moves, and an older binary
keeps replaying with the flag. Declined: a case copied or moved without its neighbour loses the
mode and is back to the caller remembering it, and through MCP the neighbour would also have to
sit inside the root. The promise would shrink to "when the other file is there".

**Record nothing, and make the refusal name the right mode.** Declined: the refusal cannot know
which mode the case was counted under — that is the missing fact — and `sideeye_replay_case`
would still be unable to replay a supervised case. The issue's promise would not hold.

**Let `--observe` override the case.** Declined above: the other mode's count addresses another
operation.

**Give `sideeye_replay_case` an `observe` parameter.** Declined: the caller would still have to
know the mode, and the case is the only thing that does.

**Write `observe` in every case.** Declined: every case would become version 6, including those
whose defines never changed, and none of them would replay on an earlier 1.x — ADR 0071's first
ground, in full.

## Consequences

- `docs/contract-freeze.md` surface 4 records version 6 and its gates. ADR 0052's known limit,
  ADR 0089's two statements about it and ADR 0074's open question carry amendment notes; ADR
  0071's reasoning, `src/evidence.zig` and `docs/evidence.md` stop calling every rung a define
  field.
- A case saved before this change records nothing and replays exactly as it did: under the flag
  given, or the default. Through `sideeye_replay_case` an old `syscalls` or `supervised` case
  still refuses as before; the command line with its `--observe` is the way.
- `spike/acceptance.sh` holds the replay with and without the flag and the contradiction refused
  — for `supervised` in the leg that runs where the suite is contained, and for `syscalls`
  wherever it runs on Linux, with the refusal's JSON `case` checked there — and the seven
  malformed shapes; `spike/mcp-acceptance.sh` mcp 21 replays a `syscalls` case
  through `sideeye_replay_case`. A `wrappers` case is still version 2 with no `observe` key
  (the existing check that pins version 2).
