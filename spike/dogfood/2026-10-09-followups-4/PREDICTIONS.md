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
