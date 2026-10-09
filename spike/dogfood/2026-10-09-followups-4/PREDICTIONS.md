# Predictions — 2026-10-09 follow-ups 4

Written before each run. The fourth "おわり？": the three targets left waiting on #678 (the restore does not
rebuild modes or owners) were said to be beyond any define on 2026-10-03, but a FAT filesystem has no
per-file mode or owner — its mount gives every file the same ones — so the restore cannot change what the
target sees.

| target | step | prediction |
|---|---|---|
| upx 5.2.1 `-q prog` | state on FAT, `fmask=0022` (every file 0755) | past `recording_run_failed`; FAIL or PASS by how upx replaces its input (it writes a temporary and renames: PASS) |
| argocd 3.5.3 `context work` | state on FAT, `fmask=0177` (every file 0600) | past it; FAIL (the config rewritten with `os.WriteFile`) |
| arkenfox prefsCleaner.sh 2.1, `--observe supervised` named | state on FAT, `uid=1000` (every file the user's) | past the second run's owner difference; FAIL (prefs.js moved to the backup, then written; a crash between leaves no prefs.js, though the backup holds it) |
| lz4 1.10.0 | its full help read for a switch beside `-T#` | none |
| lz4 `-T1 -BD` (dependent blocks cannot be compressed in parallel) | the page's path | still `multiple_threads_detected` (a guess: the I/O may have its own thread) |

## Round 2: who the second writer is, behind the threads wall

Follow-ups 3 left seven targets at `multiple_threads_detected` with their one-thread switch set, and two
Python ones with none tried. The README judges threads "where a creation or a join the shim saw orders
their writes", so the question for each is which threads write the state and whether a switch the tool
documents stops one of them. Measured with `strace -f` on the state's paths, outside Sideeye
(`apparatus/writers.sh`); a switch found is then explored on the page's path.

| target | prediction |
|---|---|
| gemini-cli 0.62.0, vercel 62.2.0, Bitwarden CLI 2026.8.0 (`UV_THREADPOOL_SIZE=1`) | two writers: the main thread with Node's synchronous calls, and libuv's one pool thread with the asynchronous ones. No switch moves one to the other: still a wall |
| OpenTofu 1.13.1 (`GOMAXPROCS=1`) | the state's writes spread over several of the Go runtime's threads, as a blocking call hands its P on. No switch: still a wall |
| electrum 4.8.2 `--offline` | the wallet written from the asyncio loop's own thread, beside the main one. No switch |
| basic-memory 0.23.2 | the note from one thread, the SQLite index from aiosqlite's connection thread. No switch |
| goaccess 1.12 `--persist` (read, not run) | the shared mapping is the tpl library's, which writes every database file through one: no switch |
| rrdtool 1.9 `update` (read, not run) | the mapping is compiled in (`HAVE_MMAP`); no switch at run time |
