# The topydo declaration — Seal B (ADR 0012)

This directory is the declaration the blind-hunt campaign freezes before the
first crash measurement of its selected target. The target is **topydo 0.14**,
picked by the sealed predicate over the committed sweep manifest
(`select.sh` on `sweep-manifest.json` + `priority.txt`; verify-seals B4
recomputes it). Everything here was written from the permitted sources only —
`topydo help`, the project's own documentation, the todo.txt format
specification, and observed *normal* (non-crash) behavior — each consultation
itemized in the campaign ledger and reproduced under `transcripts/`. No trace
of topydo, no crash experiment, no write-ordering inspection, no source
reading, no bug tracker. After this seal merges, editing any invariant,
checker, setup, config or toml here marks the declaration sighted
(ADR 0012 breach handling).

## Sources

| Transcript | What it is |
|------------|------------|
| `transcripts/help.txt` | `topydo help` — the 15-subcommand inventory below |
| `transcripts/help-subcommands.txt` | `topydo -v` + per-subcommand help |
| `transcripts/docs-tiddlers.txt` | the topydo 0.14 documentation (TiddlyWiki), relevant tiddlers extracted; Changelog tiddlers deliberately not extracted (fixed-bug listings are known-issue reports) |
| `transcripts/todotxt-spec.md` | the todo.txt format specification the docs point at |
| `transcripts/normal-runs.txt` | one normal run of each declared operation: invocation shape, exit status, output form, file contents, state-dir filenames |
| `transcripts/config-verification.txt` | the nobackup config observed working (no `.todo.bak`, exits unchanged) |

The `.todo.bak` backup file is never read anywhere in this campaign — its
format is not documented. Only its existence (a filename) is observed.

## The operation inventory

`topydo help` lists fifteen subcommands. Exclusions use only the sealed
vocabulary (`interactive` / `network` / `destructive-by-design` /
`not-stateful`). The `prompt` and `columns` UIs are not in the help list and
are outside this inventory's boundary.

| Subcommand | Verdict | Reason |
|------------|---------|--------|
| add | **declared** | writes todo.txt |
| append (app) | **declared** | writes todo.txt |
| del (rm) | **declared** | writes todo.txt (`-f`: documented no-interaction form) |
| dep | **declared** (`dep add` form) | writes tags into todo.txt; the `ls`/`dot` sub-forms are not-stateful |
| depri | **declared** | writes todo.txt |
| do | **declared** | the cross-file operation: "the completed item is moved to a separate text file" (Archiving) |
| edit | excluded — `interactive` | "Launches a text editor" |
| ls | excluded — `not-stateful` | query (the `-f ical` variant is documented as writing, and is not used anywhere here) |
| listcon (lscon) | excluded — `not-stateful` | query |
| listprojects (lsprj) | excluded — `not-stateful` | query |
| postpone | **declared** | rewrites the due tag |
| pri | **declared** | writes todo.txt |
| revert | **declared** (no-argument form) | the cross-file undo: "revert the todo and archive files to the state before" (help); its `ls` sub-form is not-stateful and serves as a checker query |
| sort | **declared** | rewrites todo.txt |
| tag | **declared** | writes todo.txt |

Eleven operations are declared. The declared shapes avoid the documented
interactive branches: `do` on a task with no dependencies and no recurrence
tag (the question the help describes never triggers — observed non-interactive),
`del -f`, `tag` on a fresh tag name. All eleven exited 0 in normal runs
(`transcripts/normal-runs.txt`), which is the provenance for
`expected_status = "0"` in every toml.

## The backup decision

topydo stores a backup of both files "after each modification"
(Backups tiddler), and the backup store carries times at second precision —
observed through `revert ls` output, which is as far as normal runs can see.
Sideeye's un-killed baseline world must reproduce the recorded final state
byte-for-byte; a second-precision timestamp rewritten on every operation
cannot, so with backups on, every exploration would be refused as
`baseline_violates_invariant` for the timestamp alone (the watson precedent),
before topydo's own behavior is ever measured.

The documentation provides the lever: "Set to 0 to disable backups"
(ConfigBackupCount, default 5). So:

- **Ten operations run with `ops/nobackup.conf`** (`backup_count = 0`, the
  single deviation from default configuration). Their crash surface is
  todo.txt/done.txt only — the backup subsystem is *not* probed by them, and
  this declaration says so rather than discovering it later.
- **`revert` runs with backups on** — they are the operation's own input.
  Its baseline may be refused if revert itself rewrites the backup store
  timestamp; that refusal, if it happens, is a recorded result, not a
  campaign failure.

Both file stamps that remain (creation and completion dates) are dates, not
times, so recording and baseline are byte-reproducible within one calendar
day; `run.sh` says so and a run must not straddle midnight.

## The invariants

Provenance vocabulary per ADR 0012: `source: doc <cite>` is a documented
promise; `source: observed-normal <transcript>` is behavior a normal run
showed. The two are not the same strength and are not conflated. The
checker (`ops/check.sh`) instantiates the sealed wrapper template: target
queries must exit 0 and output properties are stated positively; file-format
checks use ADR 0012's todo.txt carve-out (the format itself is normative
public documentation).

- **I-Q — the query survives.** After a crash and no repair, `topydo ls`
  exits 0 and every printed line keeps the documented `|<number>| <text>`
  list shape.
  `source: doc` — ls tiddler, GettingStarted example; output shape
  `source: observed-normal` normal-runs.txt.
- **I-C — conservation.** A task that existed before the operation appears in
  todo.txt or in done.txt, never in neither. Applied per operation to the
  tasks its documentation gives no license to remove (for `del`, the deletion
  target is deliberately not protected — its removal is the documented
  effect).
  `source: doc` — Archiving ("moved to a separate text file"); each
  subcommand's documented effect names the task it touches; todo.txt spec
  (one task per line).
- **I-D2 — no duplication** (`do`, `revert`). The completed/reverted task
  lives in exactly one of the two files.
  `source: doc` — Archiving ("moved"), revert help ("revert the todo and
  archive files to the state before").
- **I-F — the archive holds only completed tasks.** Every non-blank done.txt
  line starts with `x` + space.
  `source: doc` — todo.txt spec, Complete Tasks rules 1–2; README ("fully
  todo.txt compliant").
- **I-B — the backup query survives** (`revert` only). `revert ls` exits 0
  after the crash.
  `source: doc` — revert tiddler ("You can retrieve a numbered list of all
  commands when running `revert ls`").
- **I-M — claimed durability** (marker, L1; `do`, `del`, `pri`, `depri`,
  `revert`). Where the operation printed its past-tense success line before
  the kill, the new state must survive. Marker strings are the observed
  success lines; operations that only echo the item (`add`, `append`, `tag`,
  `postpone`) or print nothing (`sort`, `dep`) declare no marker — an echo is
  not a success claim.
  `source: observed-normal` normal-runs.txt.

**Severity, pre-registered** (so a finding cannot be inflated after the
fact): loss (I-C) is data destruction — the severe direction. Duplication
(I-D2) is moderate: a re-completion after the crash would duplicate an
archive entry. I-Q / I-F / I-B violations are store-integrity findings whose
severity depends on what recovers them, which is exactly what the report
will have to show. If a crash point makes one of these unavoidable for any
non-atomic implementation, that is the finding class this product exists to
surface (the timewarrior precedent) — the report states which invariant
fired and at what point, nothing more.

## Per-operation declaration

| op | setup (`ops/setup.sh`) | operation | conserved | extra legs | marker |
|----|------------------------|-----------|-----------|-----------|--------|
| add | add seed-task | `add water-plants` | seed-task | — | — |
| append | add water-plants | `append 1 urgently` | water-plants | — | — |
| del | add water-plants; add keep-me | `del -f 1` | keep-me | — | `Removed:` |
| dep | add parent-task; add child-task | `dep add 1 to 2` | parent-task, child-task | — | — |
| depri | add water-plants; pri 1 A | `depri 1` | water-plants | — | `Priority removed.` |
| do | add water-plants | `do 1` | water-plants | I-D2 | `Completed:` |
| postpone | add water-plants; tag 1 due 2026-09-01 | `postpone 1 1w` | water-plants | — | — |
| pri | add water-plants | `pri 1 A` | water-plants | — | `Priority set to A.` |
| revert | add water-plants; do 1 (backups on) | `revert` | water-plants | I-D2, I-B | `Reverted to state before:` |
| sort | add zebra-task; add alpha-task | `sort text` | zebra-task, alpha-task | — | — |
| tag | add water-plants | `tag 1 due 2026-09-01` | water-plants | — | — |

Conservation checks grep the files, not `ls` output: a normal run showed
that `ls -x` does not list a task that acquired a dependency
(normal-runs.txt, dep section), so the listing is not a reliable full
inventory — the files are, under the todo.txt carve-out.

## What this declaration does not check

- **Recoverability after a crash.** Whether `revert` can actually restore a
  crashed state (the docs promise reverting *committed* states, and refuse
  when the file "was modified with other editors") is not asserted either
  way; a finding's report may measure it afterwards, as analysis.
- **The operation's own payload.** A crashed `add water-plants` may leave
  the new task present, absent, or torn; only pre-existing tasks are
  protected. The todo.txt format has no checkable torn-line criterion — any
  text is a task.
- **The backup file's content** — never read; format undocumented. Only
  `revert ls`'s exit code speaks for it, and only in the revert run.
- **`sideeye preflight` was not run on these defines.** The sweep's single
  sealed run is the only pre-seal contact between sideeye and topydo.
  Operations beyond the swept shape (`add`/`do`) may be refused by the
  engine at exploration time; a refusal is honest #84 data, not a
  declaration defect, and no invocation here was tuned against acceptance.

## Running the exploration

`run.sh` (sealed with this declaration) explores all eleven operations from
the Seal B commit in a clean tree, inside the pinned container, and writes
the `run-manifest.json` that verify-seals R1 audits. Saved cases pin the
absolute `/tmp/blind/hunt/<op>/...` paths, which resolve in the image by
construction — the replay-in-image property the selection predicate's
resolution leg was a proxy for.
