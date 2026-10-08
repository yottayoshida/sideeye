# 0096 — The account sentences carry their figures as optional fields beside them

Status: Accepted (2026-10-08)

Part of #711. Numbered 0096 by agreement with the session working #688–#690 at the same time,
which takes 0098 onward (the collision #373 recorded is the reason it was agreed rather than
taken).

## Context

The JSON report gives a caller `verdict`, `exit_code`, `violations` and `earliest` as data, and
`oracle_verified` as the one boolean to gate on. The three account fields a caller most often
wants to read further — `oracle`, `checker` and `processes` — are sentences. How many operations
the two witnesses agreed on, whether a checker was declared and how many worlds it ran in,
whether another process's operations were admitted and how many threads wrote: each is a number
or a yes/no inside prose whose wording `docs/report-schema.md` says may improve between releases.
A caller that wanted the number parsed the sentence, and a reworded sentence would break it
silently.

The schema is frozen (surface 2 of `docs/contract-freeze.md`): a field may not change meaning, a
closed set may not gain a member, and a new optional field is allowed.

## Decision

**Eight optional fields, flat, each written from the value its sentence prints and present only
where it was measured.**

- `oracle_witness` (string, an open set: `strace`, `fs_usage`) — present from the argument that
  names an oracle; `oracle_operations_agreed` (integer) — present when the comparison completed
  and agreed.
- `checker_declared` (bool) — present once it is known; `checker_worlds` (integer) — present
  when the checker ran in the exploration.
- `processes_children_admitted` (bool), `processes_image_changes`, `processes_threads_created`,
  `processes_writer_threads` (integers) — the recording run's figures, present once every check
  on the recording's trace has held: the line `l0_judged_paths_touched` is set on, for that
  field's reason (ADR 0091). A refusal raised on a trace cut short, renumbered or never announced
  carries none, rather than counts read from part of it.

Each value comes from the variable its sentence prints — assigned beside the line that writes
the number into the sentence, or read from the same struct when the report is written — so the
field and the sentence share one value: `parsed.classes.items.len` for the
agreement, `checks_run` for the worlds, `boundary_ev` for the process account — which is the
struct the `processes` sentence is already rendered from. (An allocation failure that cuts a
sentence to its short fallback leaves the field with the figure the sentence lost.) The
sentences do not change. The process figures are the recording run's alone: the `processes`
sentence also says what an explored world showed, a thread created there or a boundary that
appeared there, and no field carries that — the schema says so beside the fields.

**Absent, never zero, for "not measured".** A run that stopped before the comparison has no
agreement count, not an agreement of 0; a run whose shim never announced itself has no thread
count, not 0 threads. `docs/report-schema.md` already says of `processes` that the absence of a
boundary from the note is never the absence of a boundary; a field that wrote 0 there would say
the opposite. The join, hand-over and detach counts are left out for the same reason: under
`--observe supervised` they are not counted at all, and the sentence already declines to print
them as zeros there.

## Alternatives considered

- **One `account` object holding three objects** (the plan's first draft). Rejected in review:
  twenty-one members would join the frozen surface at once, several of them states rather than
  figures, and a `null` member would have to mean both "not yet read" and "none" — the first
  draft conflated an oracle never named with arguments never read. Flat fields with presence
  rules say each of those once, and match how the schema already spells its additions
  (`oracle_verified`, `oracle_verified_subject_only`, `l0_judged_paths_*`).
- **A state name per sentence** (`oracle_state: "agreed" | "not_compared" | …`). Rejected: a new
  closed set, which surface 2 freezes by name, so the next state the engine learns to report
  would be a break.
- **Turning `oracle` into an object.** Rejected: a documented field would change meaning, which
  surface 2 forbids — it would have to change name, and then the sentence would be gone.
- **Rendering each sentence from a struct** so the prose is derived from the data. Not taken:
  the acceptance suite holds these sentences word for word, and writing both from the same
  variable on the same line already keeps them from disagreeing.

## Consequences

- `docs/report-schema.md` gains "The account as data"; `docs/contract-freeze.md` records the
  addition under surface 2. `contract_version` does not move.
- `oracle_operations_agreed` is not a gate. On a run whose writing children were admitted it is
  present while `oracle_verified` is `false`; the schema row says to gate on `oracle_verified`.
- The MCP surface passes the fields through in `structuredContent` unchanged.
