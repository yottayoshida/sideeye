# 2026-10-15 authoring — results (#873)

Three targets, one per contract shape, each authored once by a fresh `claude --safe-mode` session
(claude-opus-5-5) from sideeye v1.13.0's README, CLI page, checker cookbook and apparatus page, and
graded by two more. Every figure below is `tally.py`'s or is read from a named file under `runs/`;
`SYNTHESIS.md` carries the computed block.

## Per target

| | quilt 0.68-1 | gdbmtool 1.24-2 | python3-yoyo 9.0.0 |
|---|---|---|---|
| shape | related files must agree | documented recovery path | multi-step migration |
| result of `sideeye.toml` | **UNKNOWN** `child_touched_state_dir` | **PASS**, 12 worlds, strace agreeing on 11 operations; the checker's alone (the database is `scratch`, so the built-in layer judged no path) | **FAIL**, 80 of 157 worlds, the checker's, strace agreeing on 156 |
| verdicts printed by the subject's `explore` calls, in order | UNKNOWN (default mode), UNKNOWN (`--observe syscalls`), SETUP ERROR (`supervised`) | PASS, then FAIL on a comparison define without its `scratch` line | FAIL, then a replay |
| judged states (`l0` lines, #618's count) | 3 | 4 | 6 |
| `sideeye.toml` revisions the watcher saw | 5 | 2 | 1 |
| controls | 5 | 5 | 4 |
| graders on the checker | both `semantically valid` | both **`wrong question`** | both `semantically valid` |
| controls breaking their leg and no other, both graders agreeing | 4; 1 contested | 3; **2 agreed not** | 2; **2 agreed not** |
| friction rows written by the subject | 17 | 11 | 12 |
| agreed keys (`tally.py`: a row both graders keyed alike, or a row both added within ten events) | 16 (15 of the subject's rows, 1 added) | 9 | 2 — see below |
| session, host clock (a model's seconds) | 563 s, first exploration at 427 s | 317 s, at 243 s | 506 s, at 334 s |

### quilt — a refusal the documents did not predict

The subject's checker reads `.pc/applied-patches` against the files and runs `quilt pop -a` as the
undo; both graders found it asks the card's question. The default mode and `--observe syscalls`
both refused `child_touched_state_dir`; `--observe supervised` was a SETUP ERROR, the box giving its
ordinary user no cgroup v2. `push` runs `patch(1)` from a pipeline subshell, and the subject read
its strace as the child being reaped before the parent appends to `.pc/applied-patches`, while the
refusal says a process wrote in the judged directory "while it was still running — nothing had
collected it"; which account is right is not settled here. Both graders keyed the subject's row to
README's "What the target has to be": the refusal points there, and the subject could not read from
the section why this shape refuses.

### gdbmtool — a PASS on the wrong question

The subject ran `gdbmtool recover` before reading and its five legs went red one by one. Two of
those legs are not the card's: "no other keys" and "the new keys survive as a prefix of k4, k5,
k6". The second rejects states the card admits ("any subset of k4–k6 stored"), so both graders
called the checker `wrong question`, and the two controls built for those legs break no card leg.
The PASS stands as Sideeye's verdict on the subject's question; it is not an answer to the card's.
The preflight first refused `state_changed_without_ops` — GDBM writes through `mmap` by default —
and the subject found `gdbmtool -m` (no mmap) itself; both graders keyed that row to README's
"What the target has to be", which the refusal points to and which says nothing about `mmap`.

### python3-yoyo — a migration recorded behind its own commit

The checker runs yoyo's next `apply` as the recovery and compares the schema, the rows and
`_yoyo_migration`. Explored, 80 of 157 worlds failed in two windows: in worlds 44–83 migration
0002's column and backfill are committed while yoyo records only 0001, and in 97–136 0003's index
exists while yoyo records 0001 and 0002; in both the next `apply` fails (`duplicate column name`,
`index … already exists`) and the database cannot be migrated forward without a hand edit. The
built-in layer judged four paths in every world and found nothing — the database is `scratch`, outside
its judgment — so the FAIL is the checker's. Both graders found the checker asks the card's
question. **Both also found two of its four controls coupled**: `control-record.sh` (`yoyo mark`
of 0003 with no index) breaks the card's next-run leg as well as its record leg, and
`control-schema.sh` (an extra index) breaks no card leg at all — the same shape #861 met and
revised by hand. Not filed upstream (PROTOCOL's bounds).

## Void runs

gdbmtool's and python3-yoyo's first sessions, and quilt's second grader, ended on the account's
weekly usage limit (API 429): `runs/*.void-weekly-limit/`, `grades/void-weekly-limit-*`. Each was
run again under the same seal — the same sealed files, **not the same bytes of everything around
them**: the Claude CLI moved from 2.1.300 to 2.1.301 between the void sessions and their re-runs,
and the box image is rebuilt from the sealed Dockerfile each time (gdbmtool's image id changed), as
each run's `meta.json` records. The void ones are excluded from every figure; void gdbmtool had
stopped at a `preflight` refusal with no exploration verdict.

## The session's configuration

`--safe-mode` did not start the sessions bare. Every subject's `init` event lists an installed
plugin (`frontend-design`) beside the CLI's built-in ones, and a list of skills; PROTOCOL's "plugins
… disabled" is not what this CLI version did. No subject called a skill, an agent, WebFetch or
WebSearch.

## What was not measured

- **The work breakdown by phase.** `watch-defines.py` captures a directory's files only once a
  define exists in it, and all three subjects wrote their recovery, checker and controls before
  their first `sideeye.toml`; every one of those files appears at the define's first snapshot, so
  the time spent writing the invariant, the recovery, the checker and the controls is
  **unmeasured**, and so are the revisions made before the first define. Rebuilding it from the
  transcript's tool calls is not done here: the tally was not written to, and writing it now would
  be one more change after the results.
- **A person's time.** The session lengths are a model's seconds on the host clock.
- **Figures the protocol named and `tally.py` does not compute**: a separate `preflight` column, the
  phase boundaries other than the first exploration, which layer a FAIL came from, and whether a
  replay ran. They are read above from the named files; the protocol listed the transcript as their
  source and the tally was not written to read them.
- **python3-yoyo's agreement is undercounted by a numbering difference, not a disagreement.** The
  sealed grader brief asks for "the 1-based row of final/friction.tsv" and does not say whether a
  header line counts. yoyo's `friction.tsv` has one; its first grader numbered rows 1–12 without it
  and its second 2–13 with it, and the two give the same key to the same row's content in eleven
  of the twelve (their `why` lines match pair by pair; on the last, one gave `cli:missing` and the
  other `cli:refusal-message`). The sealed rule compares row numbers, so `tally.py`
  counts 2 agreed keys for yoyo. Matched by content instead, `cli:--cwd` joins
  `readme:what-the-target-has-to-be` in two targets — a tie, which the sealed vocabulary order
  breaks toward README, so the decision is the same. gdbmtool's graders both numbered without its
  header; quilt's file has none. `tally.py` is not amended for this: it would be a second change made
  after reading the results, and it would not change the decision.

## Disposition

All three counted: no session called WebFetch or WebSearch (server tool counts 0), and no tool call
named the public repository or this directory. The #861 paths in the transcripts are inside the
box's own v1.13.0 checker cookbook, whose recipes 5 and 6 quote #861's checkers; #873 asked that
the checker not be copied from #861, and none of the three targets is one of #861's.
