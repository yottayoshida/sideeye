# Selection — the thread and unsupported-syscall walls still standing, for #944

Fixed before any target was measured. `apparatus/select.py`, run from the repository root at `44e0ae7c`,
reads `spike/outcome-funnel.tsv` and prints this selection; its output is
`transcripts/select.txt`.

**Which rows.** A wall row (`stop` = `wall`) whose record names `multiple_threads_detected` or
`unsupported_syscall_observed` on its `UNKNOWN` line, or, where the record names no reason, whose note
does. 73 rows on 43 targets (57 threads, 16 syscall). The issue counted 73 with 56 and 17 by each row's
first-named reason; the split was not reproduced. Six rows are where the record and the note name a
different reason first (`2026-09-11-past-walls` joplin: the record says `baseline_violates_invariant`;
`2026-10-02-unjudged-on-v170` zstd and lz4: the note names `oracle_missed_operation` first; three
`2026-09-16` rows carry no reason in their record). None of the six changes which targets remain.

**Which targets are measured.** Each target's last wall is taken from the latest campaign that met it
(the order of `spike/outcome-funnel-campaigns.tsv` breaks a tie on one date). A target is not measured
when a different campaign, on the same date or later, has a PASS or FAIL row for it: 27 targets. On
`2026-09-16` that order puts `threads-take-turns` before `userview-3`, and virtualenv's PASS is in the
former; it is counted as judged because the two ran the same day and the userview-3 note says the wall
was answered later by contract v18. DuckDB and dpkg's upgrade crossed their walls on `main` in #970
(`spike/dogfood/2026-10-22-gate-calls/`) and are not re-measured; on v1.15.0 they stay refused. The
owner's ruling (2026-10-22) narrowed #944's "every row carries a v1.15.0 result" to these 14.

| target | wall | last met in | box | procedure (inside the box) | define |
|---|---|---|---|---|---|
| basic-memory | threads | 2026-10-05-user-data-2 | `sideeye-ud1005` | `gate-all.sh` | `basic-memory` |
| Bitwarden | threads | 2026-10-09-followups-3 | `sideeye-fu3-1009` | `run.sh` | `bitwarden` |
| codex | threads | 2026-10-09-followups-4 | `sideeye-fu4-1009` | `run.sh` (its next step is `--observe supervised`) | `codex-scratch` |
| electrum | threads | 2026-10-03-user-data | `sideeye-ud1003` | `gate-all.sh` | `electrum` |
| flatpak | syscall | 2026-10-09-followups-3 | `sideeye-fu3-1009` | `run.sh` (the seed mounts a FAT filesystem) | `flatpak-fat` |
| goaccess | syscall | 2026-10-07-user-data-3 | `sideeye-ud1007` | `gate-all.sh` | `goaccess` |
| logrotate | syscall | 2026-10-14-mechanisms | `sideeye-m1014` | `gate-all.sh` | `logrotate` |
| lz4 | threads | 2026-10-09-followups-4 | `sideeye-fu4-1009` | `run.sh` (its next step is `--observe syscalls`) | `lz4-bd` |
| ostree | syscall | 2026-10-09-followups-3 | `sideeye-fu3-1009` | `run.sh` (FAT) | `ostree-fat` |
| prek | threads | 2026-10-09-followups-3 | `sideeye-fu3-1009` | `run.sh` | `prek` |
| rrdtool | syscall | 2026-10-02-unjudged-on-v170 | `sideeye-uj170` (on `sideeye-sv170`) | `run.sh` | `rrdtool` |
| rustic | threads | 2026-10-09-followups-3 | `sideeye-fu3-1009` | `run.sh` | `rustic` |
| steamguard | threads | 2026-10-09-followups-3 | `sideeye-fu3-1009` | `run.sh` | `steamguard` |
| vercel | threads | 2026-10-09-followups-3 | `sideeye-fu3-1009` | `run.sh` | `vercel` |

Each box is rebuilt from its campaign's own `Dockerfile` and given one more layer that installs v1.15.0
with the page's installer (`apparatus/v1150.Dockerfile`), so every procedure reads v1.15.0 through
`/install.path` unchanged. The procedures run straight from `docker run`, never through a campaign's
host script, whose output directory is that campaign's own `transcripts/`.
