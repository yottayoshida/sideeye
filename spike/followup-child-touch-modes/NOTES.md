# `child_touched_state_dir` is two walls, and only one of them is about where operations are counted

**Measured 2026-09-18.** Three targets, two observation modes each, six runs — the defines
exactly as committed, `strace` as the oracle, one run per cell. `run.sh` is what produced
`artifacts/`.

Not a sweep. Generation g3 is complete and is never re-measured in place; nothing here
writes into `artifacts-g3/`, no manifest is produced, and no figure on
`docs/unknown-rate.md` moves because of this. What it answers is the question g3's own
prose left open: it named `child_touched_state_dir` the dominant wall among the engine's
refusals (two of B2's five) and filed nothing from it.

**Apparatus, recorded from inside the box rather than asserted here**, the way
`spike/followup-527` does it: `artifacts/apparatus.txt` holds the engine's own version
line (**sideeye 1.5.0, trace contract v18** — the released build g3 was swept with, fetched
by `spike/unknown-rate/fetch-engine.sh g3` and verified against the published digest), the
sha256 of the binary and the shim as the container sees them, and one line per run giving
the argv the engine was given — all of that written from inside. The two image ids on the
first lines are the host's view (`docker images`), because a container cannot read its own
image id; they are in the same file for convenience, not because the box reported them.
The argv lines are what make "the flag reached the engine" readable rather than claimed:
**each target's two lines differ only in `--json` and the presence of `--observe
syscalls`** — across targets they differ in everything a different target implies.

## What ran, and what came back

| target | define | default mode | `--observe syscalls` |
|---|---|---|---|
| `lbdb` | `defines-b/lbdb` | UNKNOWN `child_touched_state_dir` | **PASS**, 8 crash points, 9 worlds, `oracle_verified_subject_only` |
| `pacpl` | `defines-b2/pacpl` | UNKNOWN `child_touched_state_dir` | UNKNOWN `child_touched_state_dir` |
| `mail-expire` | `defines-b2/mail-expire` | UNKNOWN `child_touched_state_dir` | UNKNOWN `child_touched_state_dir` |

The three default-mode cells reproduce the verdict and reason g3 recorded for the same
defines (`artifacts-g3/b-lbdb`, `b2-pacpl`, `b2-mail-expire`), which is the control this
measurement needed: the difference below is the flag's, not the environment's.

## The two shapes

**Visibility — `lbdb`.** Its default-mode refusal says the other process "mutated the
judged directory in the oracle's account and **recorded nothing of its own**": the writing
child is `/usr/lib/lbdb/fetchaddr` (the define's `op.sh` execs `lbdb-fetchaddr`, which runs
it), it writes through the parent shell's redirected stdout and never loads the shim, so the oracle sees writes that hold no crash-point number. Counting at the kernel
boundary gives those writes numbers, and the run reaches a verdict — `processes` on the
passing report reads "those operations hold crash-point addresses: no two processes'
operations interleaved and every writing child was reaped (contract v15)". This reaches
the PASS `docs/target-classes.md` already records for this target under ADR 0054 — from a
different engine (that record is contract v15 at `41b9a8b`; this is the released 1.5.0,
contract v18) and in the same `sideeye-ur-extra` image g3 used, whose id in
`apparatus.txt` matches `artifacts-g3/apparatus.txt` byte for byte. The `sideeye-ur-b2`
image the other two ran in was rebuilt since g3 and its id differs.

**Ordering — `pacpl`, `mail-expire`.** Their refusals say something else, and each target's
two runs carry it **byte for byte identically** (the reports were compared as whole
strings; both runs of a target share one state path, so nothing in the message varies with
the mode): "a process other than the subject (pid N) performed open(…), and process M wrote
in the judged directory **while it was still running — nothing had collected it yet**. Two
processes writing at once are ordered by the scheduler…". That is an ordering fact. Where
the operations are counted does not change that they overlapped. The children are named by the defines rather than by an
`execve` line read here: pacpl's `packages.txt` lists `flac` as the encoder it calls, and
`defines-b2/mail-expire/NOTES.md` records the manual's "compressed with gzip or xz" beside
the authoring run's own `I: using compressor: gzip -9`. The oracle's capture holds the
child's lines, its `execve` among them — the refusal says where, and it stays in the
container.

**The mode was installed in all three.** `src/main.zig` refuses with `platform_unsupported`
or `environment` the moment the subject's announcement does not say the filter is armed,
and that check sits in the phase **before** the one this refusal comes from (the structural
phase runs ahead of the oracle phase, `src/main.zig`'s own call order) — so a run that
reaches `child_touched_state_dir` under `--observe syscalls` is a run whose filter was
installed. That is structural, not an inference from the messages being equal. The argv
lines in `apparatus.txt` say the flag was passed; this says the engine acted on it.

## What this does not say

- **One run per cell.** Nothing here is about flakiness; a second run could differ and was
  not taken.
- **Three targets, and only one of them is in the class this record annotates.** `lbdb` is
  the row's second target. `pacpl` and `mail-expire` are Perl programs, not shell CLIs over
  helper processes: they meet the same refusal, which is the point, but they are not
  members of that class and this measurement does not move its "two of two". Whether the
  split generalises beyond three targets is not measured.
- **`lbdb`'s PASS is the weakest kind the tool produces**: `oracle_verified_subject_only`,
  meaning the oracle compared only the subject's own operations. The verdict is real; the
  second witness did not cover the child's writes.
- Nothing was filed from this. Whether the ordering wall is worth crossing — and what
  crossing it would mean for a judgement that rests on one numbering — is the owner's call.

`expected-before-reading.md` holds the prediction — its table is what was written before
the runs finished, committed unedited; the section under it was added afterwards to say how
it came out. `lbdb` held, and the pacpl / mail-expire guess was wrong.

**What the artifacts cannot distinguish.** A refused report carries no field naming the
observation mode, so two byte-identical reports are equally consistent with two runs and
with one run copied. What separates them here is the `run` lines in `apparatus.txt`, which
the script wrote from inside each container as it went. A future run of this shape should
stamp each of those lines with a time or the container id; this one does not.
