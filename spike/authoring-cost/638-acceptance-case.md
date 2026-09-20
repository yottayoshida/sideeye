# #638's acceptance case, measured

Issue #638 asked for one thing to be shown rather than argued: **a report from
`runs/lmdb-utils`' final state names `lock.mdb` as a judged path, in the JSON, without the
run having to fail.** This is that measurement. The scripts are
`reproduce-lmdb-judged-set.sh` and `lmdb-case-from-transcript.sh` beside this file.

## What was run

`runs/lmdb-utils/revisions/02.toml` unchanged — the define the watcher observed at
`2026-09-19T07:49:50Z`, the last state the subject reached. It declares `data.mdb` scratch
and, having done so, judges exactly one path.

The target is `lmdb-utils` from `debian:bookworm-slim`, version **0.9.24-1** — the same
version `runs/lmdb-utils/meta.json` recorded, checked rather than assumed. The engine is a
local build of this branch, cross-compiled `-Dtarget=aarch64-linux-gnu`. The oracle is
`strace`, as the subject's own invocation had it.

## What it said

```
atomicity: 1 path(s) judged pre-or-post; 1 path(s) matched by scratch, not judged (declared: data.mdb)

"verdict": "PASS"
"scratch": ["data.mdb"]
"l0_judged_paths": ["lock.mdb"]
"l0_judged_paths_omitted": 0
```

PASS over 14 worlds (13 crash points and the baseline); the oracle agreed on 13 operations,
153 syscall lines examined, 46 in scope of the judged state; the checker was falsified before
the run and ran in all 14 worlds.

**The `atomicity` line is byte for byte what the subject saw** — `1 path(s) judged
pre-or-post`, the count with no name. The judged path is `lock.mdb`: the file the subject
had already written off in its own words four minutes earlier ("lock.mdb writes go through a
shared mmap invisible to file syscalls, recreated as needed"), believed it had taken out of
the state behind a symlink, and left judged. It never violated, so no FAIL named it, and the
run PASSes here too — which is the point of the acceptance condition. Nothing about this run
is a failure; the field is the only thing in it that says what was judged.

## What this is not

- **A reconstruction, not the original box.** The define's `setup.sh`, `check.sh`, `base.txt`
  and `load.txt` are not in the repository — `watch-defines.py` snapshots `*.toml` only, which
  is #639. They are quoted verbatim from `runs/lmdb-utils/transcript.jsonl` with the timestamp
  of the Bash call each came from (`07:46:14.379Z` for the data, `07:49:00.156Z` for both
  scripts, written 49 seconds before the define under test). Check them against the transcript,
  not against the script that carries them.
- **Not the study's image.** No man pages, no `watch-defines.py`, no README: none of those
  affect what the engine judges, and rebuilding the study's box would have meant rebuilding the
  authoring task around a define that already exists.
- **Not evidence that the field removes the authoring cost.** ADR 0078 says that plainly: the
  measurement is of a subject that could not see the set, and whether one that can see it
  writes the define correctly is a second experiment. What is measured here is that the set is
  reported, on the case that motivated reporting it.
- **Not in CI.** It wants Docker, the network for one apt install, and a cross-built engine.
  The permanent legs are in `spike/acceptance.sh` and the unit tests in `src/report.zig`.
