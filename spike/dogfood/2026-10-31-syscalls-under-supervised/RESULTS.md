# Results — the `--observe syscalls` verdicts under `--observe supervised` (#938)

Run 2026-10-31 on Apple silicon (Docker Desktop, cgroup v2), every box `aarch64` Debian, with
the released **v1.17.0** `aarch64-linux` tarball (`transcripts/<target>/engine.txt`). Rows,
images and defines as `SELECTION.md` fixed them before the first run; predictions in
`PREDICTIONS.md`, written before it too.

## The table

`syscalls` is the control, run by the same engine in the same box; `supervised` is the
measurement. "Failing" is failing worlds of explored; "earliest" is the earliest failing crash
point.

| Row (line at `651ad406`) | Target (version in the box) | `syscalls` (control) | `supervised` | Same? |
|---|---|---|---|---|
| 59 | zstd 1.5.7 `--rm`, default threads, a 300,000-byte input | PASS 9/9, 8 points | PASS 9/9, 8 points | yes |
| 86 | todo.txt-cli 2.14.0 `add` | PASS 4/4, 3 points | PASS 4/4, 3 points | yes |
| 128 | podman 5.4.2 `system connection default` | PASS 7/7, 6 points | PASS 7/7, 6 points | yes |
| 130 | SolveSpace 3.2 `solvespace-cli regenerate` | FAIL 15/17, earliest 2 of 16 | FAIL 15/17, earliest 2 of 16 | yes |
| 156 | skopeo 1.18.0 `logout` | PASS 5/5, 4 points | **UNKNOWN `multiple_threads_detected`** | **no** |
| 163 | ntfs-3g 2022.10.3 `ntfslabel` | FAIL 1/5, earliest 3 of 4 | FAIL 1/5, earliest 3 of 4 | yes |
| 185 | ziptool (libzip 1.11.4) `delete` | PASS 6/6, 5 points | PASS 6/6, 5 points | yes |
| 188 | alacritty 0.17.0 `migrate` | PASS 9/9, 8 points | PASS 9/9, 8 points | yes |
| 189 | zsh-z 2.0.1 `zshz --add` | FAIL 1/7, earliest 5 of 6 | FAIL 1/7, earliest 5 of 6 | yes |
| 192 | acme.sh 3.1.6 `--set-default-ca` | FAIL 3/5, earliest 2 of 4 | FAIL 3/5, earliest 2 of 4 | yes |
| 252 | zstd 1.5.7 `--rm --single-thread --no-asyncio`, a checker | PASS 8/8, 7 points | PASS 8/8, 7 points | yes |
| 278 | shadow-utils 4.17.4 `useradd --prefix` | FAIL 21/71, earliest 46 of 70 | FAIL 21/71, earliest 46 of 70 | yes |
| 281 | isync 1.5.1 `mbsync` | FAIL 28/46, earliest 6 of 45 | FAIL 28/46, earliest 6 of 45 | yes |
| 282 | dpkg 1.22.22 `update-alternatives --install` | PASS 10/10, 9 points | PASS 10/10, 9 points | yes |

Every run was `oracle_verified` except skopeo's supervised one, which refused before any
world. `transcripts/versions.txt` (written by `apparatus/versions.sh`) holds the engine
tarball's sha256, each image's id and architecture (all `arm64`), and the version each box
reports for its tool; every one it reports is the version the row names. Three report none
that way — SolveSpace, libzip's ziptool and zsh-z — and are the builds their records' images
installed. Row 59 names no version; the box's zstd is 1.5.7. The raw work directories
(traces, oracle captures, the FAILs' cases) were not committed, as in the other records here.

**The control reproduced the page on all 14 rows**: the same verdict, explored count and
failing count, and for a FAIL the same earliest crash point. So no row here mixes drift with a
mode difference.

**`supervised` reached the same verdict on 13 of 14**, with the same crash-point count on all
13: the two modes counted the same operations from opposite sides of the kernel boundary.

**The one difference is skopeo**, a Go binary. Under `syscalls` the account named 8 threads
created and 1 writing the judged directory; under `supervised` the engine recorded 3 thread
ids of the subject's process writing it — `open` of `.tmp-auth.json<n>` on one and its
`write` on another — and refused, because under `supervised` no join is recorded, nor which
thread a creation made, so nothing orders the two writes (#687, ADR 0138). Why the two modes
attribute the same writes to one thread and to three was not measured: one run each, and the
Go scheduler moves goroutines between threads from run to run. `GOMAXPROCS=1`, which the
refusal names as the next step and which judged other Go rows on the page under `supervised`,
was not tried. podman, also Go, wrote from one
thread id in both modes and reached its PASS in both.

## Against the predictions

- Control reproduces the page on all 14: **held**.
- Same verdict on the single-threaded C, shell and Python targets: **held** (10 of 10).
- Refusals predicted for podman, skopeo and row 59's zstd: **one of three** — skopeo refused;
  podman and zstd at its default thread count (two threads created, one writing, on row 59's
  300,000-byte input — row 332's larger zstd runs meet the thread wall) were judged under
  `supervised` as under `syscalls`. alacritty, the uncertain one, was judged too.
- "At least 10 of 14 match" (60%): **13 of 14**.

## What this does and does not settle

It settles the measurement #938 asked for: each of the 14 rows whose verdict only `syscalls`
reached now carries a `supervised` result. On today's page, `syscalls` is the only mode that
judged one of them in this run — skopeo `logout` — and what refused it under `supervised` is the
thread-ordering rule, not an operation `supervised` failed to count.

No finding is new: every FAIL here is the row's own, whose upstream state the row records.
skopeo's row stays in the first table as it was — its verdict was a `syscalls`-only one before
this run too, like the other thirteen.

It does not settle whether `syscalls` should be retired; that is the owner's ruling, recorded
on `docs/target-classes.md` beside the table. It measured one run per mode per target, on one
architecture, with one engine; the five rows of SELECTION.md's group (b) with no
`supervised` verdict were not run.
