# Prediction — 2026-09-27 supervised-static

Written and committed after the entry measurements (`SELECTION.md`) and **before any run under
`--observe supervised`**. One outcome per target. A prediction is met when at least 4 of the 5
preflights, and the explores, show it.

| target | predicted under `--observe supervised` | why |
|---|---|---|
| jj | **reaches a verdict** (accepted, explores agree) | Rust; the one non-Go tool on the page. Nothing measured says which threads write — this is a forecast from the language, not from a run |
| chezmoi | **`multiple_threads_detected`** | Go schedules one file's `open` and `write` onto different OS threads (mlr, `docs/target-classes.md` row 95: five of six runs) |
| gopass | **`multiple_threads_detected`** | Go, as above |
| gh | **`multiple_threads_detected`** | Go, as above; the Homebrew build met the thread row under the rule of the time |
| lefthook | **`multiple_threads_detected`**, or **`child_touched_state_dir`** if the `git` it runs writes `.git/hooks` | Go. The informal prototype count on the page ("one thread in 3 of 3") is known, and the prediction is made against it: the prototype did not use the engine's writer rule |
| busybox `sed -i` | **reaches a verdict** | static, single-threaded C |
| sh → busybox `sed -i` | **reaches the same verdict as the direct spelling** | the `exec` leaves one process; supervised has no in-process handler to lose |
| lefthook-sh (reference) | the same as lefthook | the `exec` changes nothing for a Go image |

#217 closes only if, in this run, jj or busybox `sed -i` (a target the current engine refuses
`no_shim_marker`) **and** sh → busybox `sed -i` (the unsafe target) are each accepted in 5 of 5
preflights and reach one verdict in 3 of 3 explores. Otherwise #217 stays open and the rows move to
whatever was measured.
