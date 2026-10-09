# Results — 2026-10-09 follow-ups

What could be measured right after the 2026-10-09 user-data-4 run, counted first (the owner's ruling of
2026-10-02 that a dogfood run measures everything it can measure now): three upstream fixes this project
had not re-measured, four walls of that run not yet asked under `--observe supervised`, and one upstream
report closed without a fix whose record still said it was awaiting a reply. Released **v1.10.0**,
installed by the page's installer, in one box (`apparatus/Dockerfile`, `transcripts/build.txt`; the first
build linked the bash-completion file named `mkdwarfs` instead of the binary, `build-first.txt`).
`PREDICTIONS.md` was committed before any run (`63648a7`); **all ten predictions held**.

## Upstream fixes, each beside the build its report was measured on

| report | build | verdict | where |
|---|---|---|---|
| neovim/neovim#41940 | v0.12.5 (the release measured on 2026-09-16) | **FAIL** 2/13, crash point 4 of 12, on the checker | `unlink` of `main.shada`, and the kill before `main.shada.tmp.a` is renamed in: `main.shada` absent (142 bytes before), the new one whole beside it. 2026-09-16's define: checker v2, falsified before the run, `main.shada` scratch. Replayed twice |
| | nightly v0.13.0-dev-1824+g27ee55c09d (48 commits past the fix `1dc9728dbd`, "do not remove destination file before rename") | **PASS** 11/11, the checker in every world | 10 operations where v0.12.5 has 12 |
| schrodinger/pymol-open-source#520 | PyMOL 3.1.0 (Debian, the build measured on 2026-10-05) | **FAIL** 1/3, crash point 2 of 2 | `model.pse` opened `O_TRUNC` and the kill before its write: 6,078 → 0 bytes. Replayed twice |
| | master `edcda80f3a` (the merge of PR #521), built with pip | **PASS** 4/4 | `_write_file_atomic`: a temporary created `xb` beside the session, written, `os.replace`d over it; no `fsync` |
| mhx/dwarfs#388 | 0.15.8 (the release measured on 2026-10-03) | a plain run, no Sideeye: `mkdwarfs --recompress -f -i X -o X` exits 1 and **`X` is 0 bytes**; `dwarfsck` finds no filesystem | the finding as filed |
| | the `mhx/work` CI build at `f7689c9a20`, 10 commits past the fix `fe09fbbc05` (artifact 11445581881, digest matched) | the same run exits 1 with "refusing to overwrite input file system", **`X` intact** (2,109 bytes) and read whole by `dwarfsck` | the fix is on the `mhx/work` branch, not on `main` or in a release yet |

`transcripts/followups.txt` has every line; the engine's reports are in `transcripts/explore/`.

## The walls, asked under `--observe supervised` by name

As 2026-10-07 asked it of roswell, whose `unresolvable_path` gave way to supervised (`apparatus/probe-supervised.sh`).
None gave way here:

| target | supervised |
|---|---|
| Kvantum 1.1.4 `kvantummanager --set` | **UNKNOWN `unresolvable_path`** — "unlinked-fd write fd:5": Qt's `O_TMPFILE` has no name for the supervising engine either |
| Hydrogen 1.2.2 `h2cli -u` | **UNKNOWN `unresolvable_path`**, the same |
| yarn 4.18.1 `config set` | **UNKNOWN `multiple_threads_detected`** — tid 27 opened `.yarnrc.yml`, tid 28 wrote it, nothing recorded orders them |
| trash-cli 7.2.0 `trash` | **UNKNOWN `multiple_threads_detected`** — two threads made the trash's directories |

So roswell's way past (a static parent whose dynamic child supervised can count) is not a way past these:
an unnamed file and unordered writer threads are refused in both modes.

## The record moved without a run

`mbloch/mapshaper#706` was closed by its owner on 2026-10-07 as `wontfix` ("This failure mode has never
been reported in actual use … and the proposed solution (writing to temp files and renaming) has
downsides"). The 2026-10-03 row moves from `awaiting` to `declined`. Nothing to reply to: the owner closed
it, and the report had said closing it was fine.
