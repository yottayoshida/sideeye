# 0133 — The MCP server keeps its work inside the root, and hands back steps in its own terms

- **Status:** Accepted (2026-10-15)
- **Refs:** #824 (found in the 2026-10-11 survey); `docs/mcp.md`'s "One value is yours to supply
  … Nothing else has to be set"; `docs/report-schema.md`'s "retry after doing what `next_step`
  says"; ADR 0010 (the server answers with the report), ADR 0011 (the child's environment),
  ADR 0022 and 0106 (the root and the destruction range), ADR 0099 (the work directory is the
  runner's own, amended here).
- **Scope:** `src/mcp.zig` (the work directory's default, `forServer`, `serverStep`, the tool
  descriptions), `src/main.zig` (the apparatus refusals), `spike/mcp-acceptance.sh`,
  `docs/mcp.md`, `docs/report-schema.md`, `skills/sideeye-scout/SKILL.md`.

## Context

An agent given a server set up as `docs/mcp.md` sets it up — `SIDEEYE_MCP_ROOT` and nothing else
— met three walls after its first FAIL. The case and the evidence bundle were saved under
`/tmp/sideeye-mcp`, outside the root, so `sideeye_evidence` and `sideeye_replay_case`, which read
only inside it, refused them. The report's `replay` was a command line for the host, which the
evidence tool deliberately never offers. And a refusal's `next_step` was written for the command
line: `completeness_not_verified` said to re-run with `--oracle`, `--oracle-fs-usage` or
`--allow-unverified`, none of which a tool takes, while `docs/report-schema.md` told the caller
to retry after doing what it says. Measured on main before this change: the case path came back
under `/tmp/sideeye-mcp/server-…/cases/`, both tools answered "the path is outside the server
root", and the step named the three flags.

## Decision

1. **The default work directory is `.sideeye-mcp` inside the resolved root.** `SIDEEYE_MCP_WORK`
   still overrides it, and ADR 0099's question is asked of it unchanged. When the server creates
   it, it writes a `.gitignore` holding `*` into it — only then, through the directory it opened
   with `O_DIRECTORY | O_NOFOLLOW` and with `O_EXCL`, so neither a link swapped in after the
   mkdir nor a file already there is written through.
2. **The server puts three fields in its own terms before it summarises or answers**:
   `next_step`, `replay` and `checker_earliest.replay`, in the text block and in
   `structuredContent` alike, and `completeness_not_verified`'s `message`, whose closing flags
   the rewritten step says the server cannot take, keeps only what was not checked. A step is recognised by matching the sentence against every
   `contract.NextStep` this binary renders; a step that names a flag, or the environment Sideeye
   runs in, is rewritten to what the server's caller can do (an argument, a config key, a
   variable the operator sets) or says the server cannot and points at the command line. A
   sentence that matches no step passes unchanged. A replay naming a case inside the root
   becomes `sideeye_replay_case {"case_path": …}`, the form `sideeye_evidence` returns; one
   outside it, or one whose path holds bytes outside printable ASCII, says the case is not
   offered and which of the two. A replay that carried `[recovery]` loses it: the server's
   replay runs none, as `docs/mcp.md` already says. The fields are spliced into the engine's
   bytes; every other byte is the engine's.
3. The documents say what is still not reachable through a default server: a PASS needs
   `SIDEEYE_MCP_ORACLE` on Linux and cannot be reached on macOS; of the server's environment
   only `PATH` and the names in `SIDEEYE_MCP_CHILD_ENV` reach the target, which the apparatus
   refusals now say too.

## Surface

`contract-freeze.md` surface 2 lets the account prose improve and forbids a machine field's
meaning to change. `next_step` keeps its meaning — what to do about this refusal — said for the
surface the caller is on; `replay` keeps its meaning — how to replay this case — in the form the
evidence tool already returns. This record reads the change as a different spelling on the MCP
surface, not a change of meaning, and adds no row to `surface-changes.tsv`; `contract-freeze.md`
surface 5 records the reading. A preflight
document's own `next` is a command line and is not rewritten; the text block's `next:` line has
always been the server's.

## Alternatives considered

- **Keep `/tmp/sideeye-mcp` and let the evidence and replay tools read the server's own
  directory there.** The destruction range stays where it was, but a server restarted between
  the FAIL and the follow-up cannot read the case, and the root stops being the one name the
  tools are confined to.
- **Check, in `mcp.zig`, that a state does not name the work directory.** ADR 0022 and 0106
  reject a second reader of the state's resolution; the root is documented as safe to lose,
  and that now covers the evidence kept in it, which the root's paragraph says.
- **Add an `allow_unverified` argument.** Whether a PASS may stand on the weaker claim stays the
  operator's choice, made at the command line.
- **Rewrite only the text block's `next:` line.** `docs/report-schema.md` tells a caller to act
  on `structuredContent`'s `next_step`, which would have kept the flags.
- **Give the report a field naming the step.** A schema change for a name this binary can
  recover from its own sentences.

## Consequences

- Existing cases under `/tmp/sideeye-mcp` stay there; `SIDEEYE_MCP_WORK` reaches them. A root
  mounted read-only now needs `SIDEEYE_MCP_WORK` set, and the refusal says so. A config whose
  state is the root itself — possible when `SIDEEYE_MCP_STATE_ROOT` is set wider than the root —
  now holds the work directory and is refused, as the engine refuses any state holding its
  `--work`.
- `server-XXXXXX` directories accumulate in the root as they did in `/tmp`, where the system
  cleaned them; deleting them is the operator's.
- A case or config whose state names `.sideeye-mcp` or a directory under it can empty evidence
  another call left there; the engine still refuses a state holding its own work directory.
- A unit test fails when a step that names a flag or the environment passes unchanged, or when a
  rewritten one still names a flag outside the three quoted document headings; a new step has to
  be placed.
