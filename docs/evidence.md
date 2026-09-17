# The evidence bundle

A saved FAIL is reproducible. Turning it into something the tool's maintainer can act on is
a separate job, and it used to be done by hand: read the report, find the damaging boundary,
compare the states, decide whether the old content survives anywhere, read what the checker
said, and write it all out for somebody who has never used Sideeye.

`sideeye evidence <case.json>` does that from what the run already measured.

**Every field of an evidence bundle is either a fact this run measured or the word
`unknown` — never a value inferred from Sideeye's own prose, and never a severity rank.**

That is the whole promise, and the rest of this page is what it costs to keep it.

## Using it

A FAIL writes the bundle beside the case it saves and names it on the report's `evidence`
line, in the text report and in `--json` alike:

```
case        /tmp/sideeye-work/cases/000001.json
replay      sideeye replay /tmp/sideeye-work/cases/000001.json --shim …
evidence    /tmp/sideeye-work/evidence/000001.json
```

```
$ sideeye evidence /tmp/sideeye-work/cases/000001.json
```

Markdown on stdout, for pasting into an upstream issue. It takes the case's path or the
bundle's own — either name reaches the same file. It runs nothing: the target is not
started, the state directory is not touched, and no verdict is produced.

Exit codes: **0** when the bundle is rendered, **3** when it cannot be. Not 2 — that is
UNKNOWN, a verdict, and this command produces none ([docs/contract-freeze.md](contract-freeze.md), surface 3).

## What is in it

| Section | Where it comes from |
|---|---|
| What happened | the define's operation, the crash point and the run's crash-point total |
| Consequence | every path whose before / completed / crashed state differs, with its kind and size in each |
| Where it was interrupted | the operation that completed and the one that never ran, either side of the crash point |
| Built-in invariant | which layer judged it, the subject, and what was seen — the same three strings the report's `earliest` carries |
| Checker | whether the declared checker rejected this world, and its last output line |
| Reproducing it | the `sideeye replay` command and the saved case's path |
| Recovery | `not configured`, or — when the define declared a recovery (#606, ADR 0072) — `pass`, `fail` or `unknown`: what the tool's own recovery did when handed this exhibit's crash state, with a caveat, on `pass` and `fail`, that the rebuilt state carried restore-time timestamps and fixed permissions (not on `unknown`, which may be a recovery that never ran). The value, not a new field: `evidence_version` stays 1 |
| What this did and did not establish | the run's own observation caveats |

The machine-readable form is the bundle file itself (`"schema": "sideeye/evidence"`,
`evidence_version` 1). There is no `--format json`, because that would be a second way to
ask for bytes already on disk.

## The impact columns, and why there is no severity

The consequence table ends in three columns that let a maintainer judge impact without the
tool pretending to know the application's semantics:

- **Existed before** — whether the path was in the state directory before the operation ran.
- **Old bytes elsewhere** — whether that path's pre-operation contents are still present,
  byte for byte, at some *other* path inside the judged state.
- **Declared scratch** — whether the define declared this path as one nobody depends on
  (ADR 0043). The built-in invariants judge no scratch path in any world; the bundle still
  names it, and marks it, so a reader can see that a loss was declared uninteresting rather
  than discover the declaration somewhere else.

A file that existed before, is now empty, whose old bytes are nowhere else, and which was not
declared scratch is a different thing from a regenerable cache entry — and the difference is
in those columns rather than in a label. Sideeye does not emit `critical`, `high` or
`data-loss`: it does not know what the file is for, and a rank it cannot justify would be the
first thing a maintainer argued with instead of reading the measurement.

## When a field says `unknown`

`unknown` is a measurement outcome, not a default. **Old bytes elsewhere** is the only field
that can carry it, and it does so in exactly these cases:

- a recorded `rename` moved a directory into the judged tree from outside it (the report's
  `paths_attributed_to_rename` is non-zero). That source subtree was never snapshotted, so
  "no copy here" would be a claim about a tree nothing read;
- the path's pre-operation entry was not a regular file — a directory's recorded content is
  empty and a symlink's is its target string, so neither has file bytes to look for;
- the path's pre-operation content was empty. Empty bytes match every empty file, so `yes`
  would mean nothing.

A dash (`—`) is not `unknown`. It means the path did not exist before the operation, so it
had no old bytes and the question does not arise — which is itself something the run
measured, from the same snapshot every other column is read from.

## What the search does not cover

**Old bytes elsewhere** searches the regular files of the judged state directory — what is
under `--state` — in the crashed world. It does not leave that directory. A target that
wrote a copy somewhere else on the machine wrote it where nothing was snapshotted, so a `no`
here means "no copy inside the judged state", never "no copy anywhere".

The consequence table lists at most 256 paths. Past that the bundle says so in its caveats
rather than presenting a trimmed list as the whole one.

## Where the bundle lives, and why not in the case

The bundle is `<work>/evidence/NNNNNN.json`, carrying the same id as the case it belongs to
and its own `evidence_version`. It is deliberately not part of the case file, and deliberately
not inside `cases/` either: several readers take `cases/*.json` and one of them takes the first
match, so a bundle sitting there would be handed to something expecting a case. A directory of
its own makes every reader of that directory correct without any of them knowing this file
exists.

A case is a *question*: the define, the crash point and the landing context a later replay
re-asks (ADR 0009). [docs/contract-freeze.md](contract-freeze.md) surface 4 ties a case's version to its shape,
and every rung of that ladder so far — 3 for the argv command form, 4 for `cwd`, 5 for
`scratch` — is a *define* field. An observation is not part of the question. Folding these
fields in would move every case this release writes to version 6, so none of them would
replay on any earlier 1.x, and each later evidence field would move the version again for
every case, including the ones whose defines never changed. ADR 0071 records the decision.

A bundle is written only once its case was written, and takes its name from that case's id,
so it claims no id of its own: the ordering the report documents — in a fresh work directory
`000001` belongs to the overall earliest exhibit — holds however the bundle write turns out.
A FAIL whose bundle could not be written says `-` on its `evidence` line and is otherwise
unchanged. The report and the case are the product; this is an attachment, and an attachment
does not take the verdict down with it.

When a run has two exhibits — the overall earliest and the earliest world the checker
rejected (#231, ADR 0020) — each case gets its own bundle, and `checker_earliest.evidence`
names the second. When the two exhibits are one world there is one case and one bundle.

## The checker's output

To quote the checker's last line, Sideeye has to have it. The checker's output in each
explored world is therefore **also** captured to `<work>/checker-output.txt`, in addition to
reaching your terminal the way it always has — the lines are re-emitted unlabeled, which is
what distinguishes them from the falsification gate's, prefixed `falsify:` since #134. The
file holds whichever world ran last, which is the un-killed baseline; the exhibit's own last
line is in the bundle, read in the world that produced it, and that is the copy worth keeping.

If the capture cannot be opened, the checker still runs — the verdict rests on its exit
status, which is unaffected — and the bundle's checker diagnostic is reported as unreadable.
An attachment does not turn a FAIL into an UNKNOWN.

## What it will not do

- file an issue anywhere;
- rank what it found;
- generate a patch;
- re-run the target, or read anything back out of Sideeye's own rendered report.
