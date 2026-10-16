# 2026-10-15 authoring — synthesis (#873)

**This page's figures and its decision are `tally.py`'s output, recomputed from the transcripts, the
watcher's records, the subjects' `friction.tsv` and both graders' sheets under `runs/`, by the table
sealed before any subject ran (draft pull request #909, `seal.json`; one amendment after the runs,
which changed how the transcript is read and not the table — `PROTOCOL.md`, Amendments).**
`python3 tally.py --check` fails if the block below is not its output, and if any run's first
timestamped event is not later than the pull request's creation time `seal.json` records — a value
read from GitHub (`gh pr view 909 --json createdAt`) that anyone can read again; CI compares against
the recorded value and does not ask GitHub itself.

<!-- tally:begin -->
```
gdbmtool: counted; judged states 4; revisions: INVARIANT.md 1, check.sh 1, control-a.sh 1, control-b.sh 1, control-c.sh 1, control-d.sh 1, control-e.sh 1, controls.txt 1, explore-1.txt 1, explore-2-noscratch.txt 1, friction.tsv 1, recover.sh 1, replay-2-noscratch.txt 1, run-controls.sh 1, setup.sh 1, sideeye.toml 2; explores PASS, FAIL (another define); result of sideeye.toml PASS; session 317s, first explore 243s (a model's seconds, host clock)
  checker wrong question; controls breaking only their leg: control-a.sh yes, control-b.sh yes, control-c.sh yes, control-d.sh no, control-e.sh no; agreed keys: target, cli:--state, target, readme:what-the-target-has-to-be, cli:--operation, target, target, other, cli:--scratch
gdbmtool.void-weekly-limit: void
python3-yoyo: counted; judged states 6; revisions: 0001-create-notes.sql 1, 0002-add-body-len.sql 1, 0003-index-body-len.sql 1, INVARIANT.md 2, accept-completed.sh 1, accept-recovered.sh 1, accept-start.sh 1, check.sh 1, control-data.sh 1, control-nextrun.sh 1, control-record.sh 1, control-schema.sh 1, controls.txt 1, explore.txt 1, friction.tsv 1, recover.sh 1, replay.txt 1, run-controls.sh 1, setup.sh 1, sideeye.toml 1; explores FAIL; result of sideeye.toml FAIL; session 506s, first explore 334s (a model's seconds, host clock)
  checker semantically valid; controls breaking only their leg: control-data.sh yes, control-nextrun.sh yes, control-record.sh no, control-schema.sh no; agreed keys: target, other
python3-yoyo.void-weekly-limit: void
quilt: counted; judged states 3; revisions: INVARIANT.md 1, check.sh 1, control-applied.sh 1, control-backup.sh 1, control-order.sh 1, control-records.sh 1, control-unapplied.sh 1, controls.txt 2, explore-supervised.txt 1, explore-syscalls.txt 1, explore.txt 1, friction.tsv 2, norecover.txt 1, probe-inner.sh 1, probe-setup.sh 1, probe.txt 1, recover.sh 1, run-controls.sh 2, setup.sh 2, sideeye.toml 5; explores UNKNOWN, UNKNOWN, SETUP ERROR; result of sideeye.toml UNKNOWN; session 563s, first explore 427s (a model's seconds, host clock)
  checker semantically valid; controls breaking only their leg: control-applied.sh contested, control-backup.sh yes, control-order.sh yes, control-records.sh yes, control-unapplied.sh yes; agreed keys: other, cli:--cwd, cli:--oracle, cli:--fresh-state, target, target, target, target, target, readme:what-the-target-has-to-be, cli:--observe, cli:--observe, cli:refusal-message, checker:verification-helper-missing, cli:--observe, other
decision row 1: next change: readme:what-the-target-has-to-be
```
<!-- tally:end -->

## The one next change

**README's "What the target has to be" — the section two refusals send an author to — should
answer the shapes they refused here.** It is row 1 of the table. In quilt, `child_touched_state_dir`
refused a `patch(1)` child, and the author could not tell from the section why; in gdbmtool,
`state_changed_without_ops` refused GDBM's default `mmap` writes, the refusal pointed to the
section, and the section says nothing about `mmap` — the author found `gdbmtool -m` alone.

**By the sealed rule it stands alone; matched by row content it ties, and the sealed order still
puts it first.** `RESULTS.md` explains why python3-yoyo's two graders agree on only two rows by the
sealed rule (one numbered `friction.tsv`'s header, one did not); matched by the rows' content they
agree on eleven of twelve, and `cli:--cwd` — the CLI page saying the working
directory is resolved before the state directory exists — then appears in two targets as well. The
vocabulary order the protocol fixed puts README first. Two targets is the table's bar and the
smallest one: this is the next change the measurement supports, not evidence that the section fails
most authors, and `cli:--cwd` is as well supported.

## The second answer: were the checkers trustworthy?

Not folded into the first, as the protocol fixed:

- **One of three checkers asked the wrong question** (gdbmtool, both graders): it demanded that the
  new keys survive in order, which the target does not promise, and its exploration PASSed. A PASS
  on a stricter-than-documented checker is a PASS on the author's question.
- **Four of fourteen controls do not break their leg alone**, both graders agreeing, and one more is
  contested (quilt). In gdbmtool the two belong to legs the card does not have; in python3-yoyo they
  are the coupling #861 met and revised by hand — a control for the record leg that also breaks the
  next-run leg, and one for the schema leg that breaks no leg of the card. One author per target
  cannot say whether the cookbook prevents this; it did not here.
- **One FAIL, the checker's**: python3-yoyo records a migration only after the transaction that
  applied it, so a crash between leaves a database the next `apply` cannot move forward. The
  built-in layer judged four paths in every world and found nothing; the database was `scratch`.

## What this does not say

- **One author, a language model, once per target.** Authoring usability by that author with these
  four documents; not third-party usability, not adoption, not a person's time.
- **The work breakdown by phase is unmeasured** (`RESULTS.md`): the watcher saw the subjects' scripts
  only once a define existed, and all three wrote them first.
- **Three targets.** A key in two of them is the table's threshold, chosen before the runs; it is
  not a rate.
