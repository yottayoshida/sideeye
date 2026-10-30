# #987: predictions and criteria, written before the first run

Written before any capture of this run was taken; its sha256 was printed in the working session
before `run.sh` was first started, and the file is committed unchanged. `RESULTS.md` is the
measurement.

## The question

Under `--observe supervised`, eight static Go tools of the 2026-10-25 shipped-v1160 run are refused
`multiple_threads_detected` with `GOMAXPROCS=1` declared. Could a rule built from evidence the
supervising engine could have — no overlap between the two thread ids' writes, and every world's writes
the same as the recording's — judge them? This run measures that evidence without Sideeye, so ADR 0138
can say *build* or *do not build*.

## What is measured

Each target in `sideeye-gh1029` (`apparatus/Dockerfile`: 2026-10-25's assets, layer for layer), seeded by
2026-10-25's own `seed.sh` before every run, with `GOMAXPROCS=1` from its `env.sh`, ten runs in each of
two arms of `strace -f -ttt -T -y`:

- **arm 1** keeps the bytes out of the capture (`-e raw=` on the data writes), for the hand-overs and Q1;
- **arm 2** carries them (`-s 1048576 -x`), for Q2. strace's slowness can change how often the runtime
  hands a goroutine over, so both arms' hand-over counts are recorded side by side.

`apparatus/handoff.py` reads the captures (`--selftest`: 20 checks, three fixed readers each caught).

- **Q1**: hand-overs whose earlier write had not returned when the later one started.
- **Q2**: the ten arm-2 sequences compared — *sequence* (call, path, offset or return differs),
  *order* (only bytes differ, and they are another write's bytes of the same shape: a trade of places),
  *content* (bytes no other run wrote there), *same*. Paths the define declares scratch are compared
  without bytes or offset; runs of six or more digits in a name are folded.
- **Q3**, described only: what the earlier thread did next, and whether it had started that before the
  later write.

## Each target's result

- **pass**: at least one arm-1 run has a hand-over, no arm-1 hand-over overlaps, and Q2 is *same* or
  *content*;
- **fail**: an overlap, or Q2 *sequence* or *order*;
- **unmeasured**: the box does not build it, its seed fails, or no arm-1 run has a hand-over.

## The criteria

- Five or more measured, two-thirds of those *pass*, the race control *fail* and the turn-taking control
  *pass* → **build** (a separate plan; ADR 0138 records the direction).
- Five or more measured, otherwise → **do not build** (ADR 0138 records the numbers and what would
  reopen it).
- Four or fewer measured, or a control not as stated → no conclusion; the owner decides.

## Controls

- `ctl-race` (`apparatus/controls/race.c`): two threads released together write their own eight bytes
  to offset 0 of one file three times each. **Predicted fail** (Q2 *order* or Q1 overlap). Its 20 plain
  runs are read for which thread won before it is used.
- `ctl-condvar` (#687's `controls/condvar.c`): two threads write `a`, `b`, `c` in turn through a
  condition variable. **Predicted pass.** It checks the reader, not whether the engine ought to judge this
  shape (ADR 0138 decision 1 keeps a recorded hand-over out of the order).

## Predictions, per target

From the records read before the run, not from any capture of it:

| target | prediction | from |
|---|---|---|
| etcd `etcdutl defrag` | pass | lab-s1-writers.txt: one run of pwrites moves between tids, the rename follows on the second |
| Dolt `dolt gc` | fail | the main manifest and the stats database written by two tids: two goroutines, in whichever order they meet |
| Grafana `cli admin reset-admin-password` | pass | one SQLite connection; the timestamp is in `grafana.db`, which the define declares scratch |
| vmrestore | fail | its preflight named an open and an unlink on two tids; a restore's deletions and copies may run apart |
| Gogs `restore` | fail | set-2-notes: writes other than the database's come from two threads even in the dynamic build |
| gqlgen `generate` | pass | its generated files are written in a fixed order; the second tid is the runtime's |
| JuiceFS `config` | pass | one SQLite connection, rollback journal |
| Navidrome `backup restore` | pass | SQLite's online backup API, one call |

Five of eight predicted to pass: below two-thirds, so the prediction is **do not build**.
