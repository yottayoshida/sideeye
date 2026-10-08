# #690 — four targets whose result moved between runs of one define

#690 named three recorded targets whose verdict or crash-point count changed between
identical runs, and a fourth whose refusal had no measured cause: tombi, mogrify, isort and
dotter. Its promise: each gets a recorded cause, or a recorded statement that the
instability is the target's. This directory re-measures all four with every run's traces
decoded, and names where two runs part.

## How it was measured

- **The box**: `Dockerfile` (Debian trixie; tombi 1.5.6 and dotter 0.13.5 as the recorded
  rows ran them, the suite's ImageMagick 7.1.1-43 and isort 6.0.1 — `results/engine.txt`
  lists them), built by `build.sh`, run by `host.sh` the way the recorded rows ran theirs:
  `--privileged --cgroupns=private --network none`, as root.
- **The engine**: this branch at `7b53c9a` (v1.9.0 plus #688 and #689), built for
  aarch64-linux with `-Dtrace-ops`, mounted at `/se`. `trace-ops --records` gained each
  record's sequence number, process and thread for this.
- **The defines are the recorded ones**: tombi's and dotter's seeds and commands as the
  2026-10-02 and 2026-10-03 runs had them; mogrify's and isort's with their `--setup` and
  checkers as in `spike/followup-527/` and the 2026-09-06 run (`setup-*.sh`, `check-*.sh`
  here). dotter adds a control: the same files with dotter's own directory inside the state.
- **The counts were fixed in `run.sh` before any result was read**: tombi 20 explores and
  40 replays of the first FAIL case (the 2026-10-02 run met the refusal 1 time in 36
  explores and 3 in 20 replays); mogrify 20 explores and 10 `preflight --twice`; isort 10
  explores of each of the two recorded defines; dotter 10 explores of the recorded define
  and 10 of the control. One set was added after the first reading, to test the cause read
  off it: mogrify with its date and time chunks left out (10). A first pass of mogrify and
  isort seeded the state outside the run; review pointed out the recorded defines used
  `--setup`, and they were run again that way (one attempt stopped at once on a state
  directory whose parent did not exist) — the results here are that run's.
- **`tally.py` recomputes the block below from `results/`** — verdicts, refusals, crash
  points, failed worlds, the earliest failing crash point and the operations around it, and
  for the runs that part from the others, the first record where they part, named by the
  trace's own `seq`. `python3 tally.py results --check NOTES.md` fails if the block is not
  what the files say. The prose after it is not checked by the script: it rests on the
  block, on `results/date-chunks.txt` (`date-chunks.sh`: which input times mogrify copies
  into which chunk, and where each chunk sits) and on `results/dotter/A*.dotter-in.txt`
  (dotter's directory after each run). `results/` holds every run's report and JSON and the
  decoded traces the tally reads, not the work directories.

<!-- tally:begin -->
```
## tombi
explore (20 runs): 19 x FAIL - cp=3 worlds=1/4 earliest=3/3; 1 x UNKNOWN multiple_threads_detected cp=- worlds=- earliest=-
replay (40 runs): 40 x FAIL - cp=3 worlds=1/2 earliest=3/3
  explore 2 refused: trace-4.bin seq 3 write a.toml by p0/t2 is the second writing thread's first record
    against 19 of 19 judged explores, same trace: part at seq 3: judged seq 3 write a.toml by p0/t1, refused seq 3 write a.toml by p0/t2
## mogrify
explore (20 runs): 10 x UNKNOWN baseline_violates_invariant cp=- worlds=- earliest=-; 10 x FAIL - cp=12 worlds=6/13 earliest=2/12
explore, date and time chunks left out (10 runs): 10 x FAIL - cp=12 worlds=6/13 earliest=2/12
  explore 1 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (39 and 34)
  explore 3 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (34 and 38)
  explore 6 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (41 and 39)
  explore 8 refused baseline_violates_invariant: first differ at byte offset 213, in a stretch 60 byte(s) long in the recording and 60 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (8 and 11)
  explore 9 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (40 and 36)
  explore 11 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (36 and 37)
  explore 14 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (36 and 35)
  explore 16 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (35 and 33)
  explore 17 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (33 and 39)
  explore 19 refused baseline_violates_invariant: first differ at byte offset 143, in a stretch 182 byte(s) long in the recording and 182 in the re-run (of 337 and 337 bytes), both holding bytes outside printable text (39 and 38)
twice (10 runs): 10 split
  twice: 1 x img1.png from offset 142, first byte +1
  twice: 9 x img1.png from offset 143, first byte +2
## isort
A (10 runs): 10 x PASS - cp=8 worlds=9/9 earliest=-
B (10 runs): 10 x PASS - cp=8 worlds=9/9 earliest=-
  write-class records of the recording, by file name: 20 of 20 runs identical to A1's
  A1: open a.py.isorted, write a.py.isorted, rename a.py.isorted, unlink a.py.isorted, open b.py.isorted, write b.py.isorted, rename b.py.isorted, unlink b.py.isorted
## dotter
A (10 runs): 10 x UNKNOWN kill_did_not_land cp=- worlds=- earliest=-
B (10 runs): 10 x FAIL - cp=18 worlds=12/19 earliest=2/18
  A 1 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 2 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 3 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 4 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 5 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 6 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 7 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 8 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 9 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  A 10 kill_did_not_land: 10 write-class records recorded, 8 in trace-9.bin; first part: recording seq 2 mkdir home by p0/t0, world seq 2 open .bashrc by p0/t0
  B earliest failing world, 10 runs: after unlink(.bashrc) before mkdir(home)
```
<!-- tally:end -->

## What each one is

**tombi — the target's scheduling, meeting #687's wall.** In the one refused explore, the
baseline world's `write` of `a.toml` (seq 3) came from a different thread of tokio's pool
than in every one of the 19 judged explores (t2 against t1). Under `--observe supervised`
no thread order is recorded, so two threads writing one file is refused
`multiple_threads_detected` — the mechanism #687 holds. Which worker writes is the
runtime's choice: 1 explore in 20 and none of 40 replays here, against 1 in 36 and 3 in 20
on 2026-10-02. Nothing new filed.

**mogrify — the times it writes into its output.** Every refusal is
`baseline_violates_invariant` over bytes #688 now locates in the PNG. `results/date-chunks.txt`
reads the chunks of one output back: `tIME` at 129 (its seconds byte at 143), the
`date:create`, `date:modify` and `date:timestamp` text chunks at 175, 224 and 273, 337 bytes
in all — and which time each holds.
- 9 of the 10 refusals start at offset 143, the seconds of `tIME`: the time mogrify wrote
  the file, which `date:timestamp` repeats. `preflight --twice`, whose runs start at least
  two seconds apart, split 10 times in 10 — the seconds byte two apart nine times, and once
  the minutes byte one apart, at offset 142. That part is the target's: it writes the clock.
- 1 starts at offset 213, inside `date:create` and `date:modify` with `tIME` equal. Those
  two are the *input* file's change time (ctime) and modification time — `date-chunks.txt`
  shows an input whose mtime was set to 2020 giving `date:modify` 2020 and `date:create` the
  moment of that change. The recording reads the times the setup left on its inputs; the
  baseline reads the times of the restore that rewrote them (the `metadata` line of this
  define's judged reports says restore assigns timestamps). Restoring the modification time
  would not remove it: the change time is the kernel's, set by any rewrite of the file,
  which no restore can reproduce. So this one is the target's too — it copies into its
  output a time of its input that only stays put while nobody rewrites the file. Nothing
  for an issue: the part a restore could reproduce (the mtime) would not change the outcome.
- With both left out (`-define png:exclude-chunks=date,time`), 10 runs of 10 reach a verdict.
  The verdict itself does not move: all 20 that reached one, with dates or without, are FAIL
  6 of 13 at crash point 2 of 12, the row's numbers. How often a run refuses depends on
  where the seconds fall — the recording's write against the baseline's, and the setup's
  against the last restore's — 10 in 20 here, 1 in 7 on 2026-09-07.

**isort — no instability between runs.** Both recorded defines, ten runs each on one
image, give PASS 9/9 over 8 crash points, and all 20 recordings hold the same write-class
records by file name: per file, the open, write, rename and unlink of `<file>.isorted`. The
6 the 2026-09-06 row recorded does not come back from either define. That run's engine
commit is not recorded and its image cannot be rebuilt, so neither axis can be excluded for
the old row; what is established is that the count does not move between runs of a define.

**dotter — the define, not the engine.** The recorded define put the state at the deployed
files and left dotter's own directory outside it — where dotter keeps `.dotter/cache.toml`
and `.dotter/cache/` beside its configuration (`results/dotter/A*.dotter-in.txt` lists them
after each run). The recording run writes that cache; restore does not touch it; every world
then starts from a cache that says the files are deployed. The recording and the last world
part at seq 2 — the recording's `mkdir` of `home`, the world's `open` of `.bashrc` — and the
last world performs 8 write-class operations where the recording performed 10, so the kill
aimed at the ninth never lands: `kill_did_not_land` in 10 runs of 10. The 2026-10-03 row's
"preflight accepted both recorded runs at 10 operations" does not say otherwise:
`preflight --twice` counts the first run's operations only (its second run's capture is
written and not compared) and compares the two runs' bytes, which the cache does not change. With both directories under
one state (the control), 10 runs of 10 reach FAIL 12 of 19, the earliest at crash point 2 of
18: after the `unlink` of `.bashrc` and before the `mkdir` of its directory, so neither the
old file nor the new one is there. #678 (restore resets permission bits) is not the cause:
the control runs under the same restore and is judged. Not reported upstream: a second
`dotter deploy` writes the file again from its template.

## What moves

`docs/target-classes.md`: the four rows say the above and point here. No row of
`spike/outcome-funnel.tsv` changes — this is a re-measurement of rows already there, as
`spike/followup-527/` was. No issue is filed: tombi's wall is #687's, and none of the other
three is the engine's.
