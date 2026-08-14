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
| `transcripts/topydo-readme.md` | the topydo 0.14 README (the "fully todo.txt compliant" claim I-F leans on) |
| `transcripts/docs-tiddlers.txt` | the topydo 0.14 documentation (TiddlyWiki), relevant tiddlers extracted; Changelog tiddlers deliberately not extracted (fixed-bug listings are known-issue reports) |
| `transcripts/todotxt-spec.md` | the todo.txt format specification the docs point at |
| `transcripts/normal-runs.txt` | one normal run of each declared operation: invocation shape, exit status, output form, file contents, state-dir filenames |
| `transcripts/config-verification.txt` | the declared artifacts observed working on normal state: setup, the toml operation strings verbatim, the checker's green side, and the nobackup config (no `.todo.bak`, exits unchanged) |
| `transcripts/checker-red.txt` | the checker's red side proven by `../checker-red-test.sh` (committed — fixtures and commands are in the transcript, not summarized) on hand-fabricated states; topydo itself only ever ran `ls` over user-authored text files, which its own docs treat as a normal scenario ("modified with other editors") |

The `.todo.bak` backup file is never read anywhere in this campaign — its
format is not documented. Only its existence (a filename) is observed.

## The operation inventory

`topydo help` lists fifteen subcommands; the `prompt` and `columns` UIs are
not in that list and are outside this inventory's boundary. The unit below is
the subcommand; for each declared subcommand the table names the exercised
form, and every documented form that the declaration does *not* exercise is
listed explicitly under "forms not exercised" — no exclusion claim is made
about those, they are unexplored surface of a declared subcommand, stated
rather than hidden. Whole-subcommand exclusions use only the sealed
vocabulary (`interactive` / `network` / `destructive-by-design` /
`not-stateful`).

**Declared — thirteen operation forms across twelve subcommands:**

| Subcommand | Exercised form | Forms not exercised |
|------------|----------------|---------------------|
| add | `add water-plants` | `-f FILE` / `-f -` (file/stdin import) |
| append (app) | `append 1 urgently` | — |
| del (rm) | `del -f 1` (documented no-interaction flag) | `-e`/`-x` expression forms |
| dep | `dep add 1 to 2` **and** `dep rm 1 to 2` | `dep clean` (a third write form); `dep ls`/`dep dot` are query forms |
| depri | `depri 1` | `-e`/`-x` expression forms |
| do | `do 1` (no dependencies, no recurrence — the documented question never triggers; observed non-interactive) | `--date`/`--force`/`--strict`, `-e`/`-x`, the recurrence and dependency branches |
| ls | `ls` (text output; a read-only recording — expected to record zero state-changing operations, which is a verdict, not a failure) | `-f ical` (documented as writing — never invoked anywhere in this campaign), `-f dot`/`-f json`, `-x`, `-i`, `-n`/`-N`, filter EXPRESSION arguments, sort/group/format flags (`-s`/`-g`/`-F`) |
| postpone | `postpone 1 1w` | `-s`, `-e`/`-x` |
| pri | `pri 1 A` | `-e`/`-x` |
| revert | `revert` (no-argument form) | `revert <NUM>`; `revert ls` is the query form, used by the checker |
| sort | `sort text` (explicit expression, no config dependence) | configured-expression form |
| tag | `tag 1 due 2026-09-01` (fresh tag — no interaction) | `-a`/`-f`/`-r` |

**Excluded subcommands, sealed vocabulary:**

| Subcommand | Verdict | Why the verdict holds for every documented form |
|------------|---------|--------------------------------------------------|
| edit | `interactive` | every documented form launches a text editor (`-d` opens the archive in the editor — same class) |
| listcon (lscon) | `not-stateful` | "Prints a sorted list of all contexts" — a query in its only documented form |
| listprojects (lsprj) | `not-stateful` | "Prints a sorted list of all projects" — a query in its only documented form |

All thirteen declared forms exited 0 in normal runs
(`transcripts/normal-runs.txt`), which is the provenance for
`expected_status = "0"` in every toml.

## The backup decision

topydo stores a backup of both files "after each modification"
(Backups tiddler), and the backup-listing query prints times at second
precision (`revert ls`, observed — which is as far as normal runs can see;
the backup bytes themselves were never read). Sideeye's un-killed baseline
world must reproduce the recorded final state byte-for-byte, so a backup
store rewritten on every operation and carrying sub-day times is a
**pre-registered refusal risk**: if those times live in the watched bytes,
every exploration would be refused as `baseline_violates_invariant` for the
timestamp alone (the watson precedent) before topydo's own behavior is ever
measured. Whether it *would* actually refuse is deliberately unmeasured —
measuring it means running the engine over the target, which is sealed until
after this declaration.

The documentation provides the lever: "Set to 0 to disable backups"
(ConfigBackupCount, default 5). So:

- **Twelve operation forms run with `ops/nobackup.conf`** (`backup_count = 0`,
  the single deviation from default configuration). Their crash surface is
  todo.txt/done.txt only — the backup subsystem is *not* probed by them, and
  this declaration says so rather than discovering it later.
- **`revert` runs with backups on** — they are the operation's own input.
  Its baseline may be refused for exactly the risk above; that refusal, if it
  happens, is a recorded result, not a campaign failure.

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
  list shape — number padding optional (the documentation's example pads,
  the observed non-tty runs do not; both are the documented shape).
  `source: doc` — ls tiddler, GettingStarted example; output shape
  `source: observed-normal` normal-runs.txt.
- **I-C — conservation.** A task that existed before the operation appears in
  todo.txt or in done.txt, never in neither — as a whitespace-delimited
  token on a line, not as a substring inside other text. Applied per
  operation to the tasks its documentation gives no license to remove (for
  `del`, the deletion target is deliberately not protected — its removal is
  the documented effect).
  `source: doc` — Archiving ("moved to a separate text file"); each
  subcommand's documented effect names the task it touches; todo.txt spec
  (one task per line, whitespace-separated fields).
- **I-D2 — no duplication** (`do`, `revert`). The completed/reverted task
  lives in exactly one of the two files.
  `source: doc` — Archiving ("moved"), revert help ("revert the todo and
  archive files to the state before").
- **I-F — the archive holds only completed tasks.** Every non-blank done.txt
  line starts with `x`, a space, and the completion date directly after
  (`x YYYY-MM-DD `).
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
  `postpone`) or print nothing (`sort`, `dep`, `ls`) declare no marker — an
  echo is not a success claim.
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
| dep-add | add parent-task; add child-task | `dep add 1 to 2` | parent-task, child-task | — | — |
| dep-rm | add parent-task; add child-task; dep add 1 to 2 | `dep rm 1 to 2` | parent-task, child-task | — | — |
| depri | add water-plants; pri 1 A | `depri 1` | water-plants | — | `Priority removed.` |
| do | add water-plants | `do 1` | water-plants | I-D2 | `Completed:` |
| ls | add water-plants | `ls` | water-plants | — | — |
| postpone | add water-plants; tag 1 due 2026-09-01 | `postpone 1 1w` | water-plants | — | — |
| pri | add water-plants | `pri 1 A` | water-plants | — | `Priority set to A.` |
| revert | add water-plants; do 1 (backups on) | `revert` | water-plants | I-D2, I-B | `Reverted to state before:` |
| sort | add zebra-task; add alpha-task | `sort text` | zebra-task, alpha-task | — | — |
| tag | add water-plants | `tag 1 due 2026-09-01` | water-plants | — | — |

Conservation checks grep the files, not `ls` output: a normal run showed
that `ls -x` does not list a task that acquired a dependency
(normal-runs.txt, dep-add section), so the listing is not a reliable full
inventory — the files are, under the todo.txt carve-out. The grep requires
the task as a whitespace-delimited token, so text embedded inside a damaged
or unrelated line does not count as survival (proven red in
`transcripts/checker-red.txt`, case 2).

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
- **The unexercised forms** named in the inventory — unexplored surface,
  stated per subcommand.
- **`sideeye preflight` was not run on these defines.** The sweep's single
  sealed run is the only pre-seal contact between sideeye and topydo.
  Operations beyond the swept shape (`add`/`do`) may be refused by the
  engine at exploration time; a refusal is honest #84 data, not a
  declaration defect, and no invocation here was tuned against acceptance.

## Running the exploration

`run.sh` (sealed with this declaration) explores all thirteen operations
from the Seal B commit in a clean tree, inside the pinned container, refuses
a reused output directory, and writes the `run-manifest.json` that
verify-seals R1 audits. Saved cases pin the absolute
`/tmp/blind/hunt/<op>/...` paths, which resolve in the image by
construction — the replay-in-image property the selection predicate's
resolution leg was a proxy for.
