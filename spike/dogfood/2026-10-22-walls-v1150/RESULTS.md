# Results — 2026-10-22, the thread and unsupported-syscall walls no later run judged, on v1.15.0 (#944)

#944 asked whether the outcome funnel's thread and unsupported-syscall walls still block, since most of
them predate later engine work. Of the 44 targets behind such a wall (74 rows), 28 have a PASS or FAIL in
a later campaign and DuckDB and dpkg's upgrade have one in `spike/dogfood/2026-10-22-gate-calls/`, on
#970's build (`transcripts/select.txt`). The other **14 were run again on the released v1.15.0, and all 14
meet the wall they met before** — the outcome `PREDICTIONS.md` committed to before the first run
(`transcripts/fixed-before-measuring.txt` holds the four files' sha256 at 11:40 UTC; the first target ran
at 11:44).

**How.** Each campaign's box was rebuilt from its own `Dockerfile` and given one layer that installs
v1.15.0 with the page's installer (`apparatus/v1150.Dockerfile`, `apparatus/build-boxes.sh`), so every
procedure ran unchanged and read v1.15.0 from `/install.path`. Each target ran its own campaign's
procedure on the define that met its last wall, straight from `docker run` into this directory
(`apparatus/measure.sh`, `apparatus/measure-all.sh`); work directories were left out of the record.
Every `engine.txt` names `sideeye 1.15.0 (trace contract v19)` and the installer's
`downloaded digest matches (5bdb0f70…)`. Every target is at the version its original record names: read
from the rebuilt box's `/versions.txt` (`transcripts/versions/`), or asked directly where its first line
names none (`transcripts/versions/asked-directly.txt`), or, for basic-memory, whose box keeps no
`/versions.txt`, from its `Dockerfile`'s pin `==0.23.2`. ostree is Debian's 2025.2, as follow-ups 3 ran
it; the 2026.4 in `docs/target-classes.md` is the 2026-10-07 source build. The rebuilds rewrote each
campaign's vendored `install-sideeye.sh` with the current page's; those writes were reverted and no file
of an earlier campaign changed.

| target | define (campaign) | v1.15.0 | predicted | next step |
|---|---|---|---|---|
| logrotate 3.22.0 | `logrotate` (2026-10-14) | `unsupported_syscall_observed`: `fsetxattr` | yes | #947 (a ruling on attribute writes) |
| goaccess 1.12 | `goaccess` (2026-10-07) | `unsupported_syscall_observed`: `mmap(PROT_WRITE\|MAP_SHARED)` | yes | none: refused by design (ADR 0098) |
| rrdtool 1.7.2 | `rrdtool` (2026-10-02) | `unsupported_syscall_observed`: `mmap(PROT_WRITE\|MAP_SHARED)` | yes | none: refused by design (ADR 0098); its copied checker has never run green on the seed either |
| flatpak 1.16.6 | `flatpak-fat` (follow-ups 3) | `unsupported_syscall_observed`: `fallocate` | yes | model `fallocate`, which libglnx calls for every non-empty file it writes on a filesystem without `O_TMPFILE` |
| ostree 2025.2 | `ostree-fat` (follow-ups 3) | `unsupported_syscall_observed`: `fallocate` | yes | the same |
| Electrum 4.8.2 | `electrum` (2026-10-03) | `multiple_threads_detected` | yes | order two threads' writes by something other than a creation or a join (ADR 0067's limit; Python has no switch) |
| basic-memory 0.23.2 | `basic-memory` (2026-10-05) | `multiple_threads_detected` | yes | the same |
| Bitwarden CLI 2026.8.0 | `bitwarden` (follow-ups 3), `UV_THREADPOOL_SIZE=1` set | `multiple_threads_detected` | yes | the same; and the refusal's next step names `UV_THREADPOOL_SIZE=1`, which the run already had |
| prek 0.5.5 | `prek` (follow-ups 3), `RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1` set | `multiple_threads_detected` | yes | ADR 0067's limit; the refusal's next step names only Node's and Go's switches |
| rustic 0.11.4 | `rustic` (follow-ups 3), the same two set | `multiple_threads_detected` | yes | the same |
| steamguard-cli 0.18.4 | `steamguard` (follow-ups 3), the same two set | `multiple_threads_detected` | yes | the same |
| lz4 1.10.0 `-T1 -BD` | `lz4-bd` (follow-ups 4) | `oracle_missed_operation`, then `multiple_threads_detected` under `--observe syscalls` | yes | ADR 0067's limit: the main thread writes the frame header and an I/O thread the blocks |
| vercel 62.2.0 | `vercel` (follow-ups 3), `UV_THREADPOOL_SIZE=1` set | `multiple_threads_detected` on two `mkdir(/s/vercel)` | yes | not an order: one of the two is the `mkdir` of the state root that fails `EEXIST` and changes nothing (follow-ups 4); the threads gate counting a failed call is what refuses it. The refusal also names `UV_THREADPOOL_SIZE=1` again |
| codex 0.160.0 | `codex-scratch` (follow-ups 4), the same two Rust switches set | `no_shim_marker`, then `multiple_threads_detected` under `--observe supervised` on a link in `tmp/arg0` and `mkdir(/s/codex)` | yes | not an order either: the link is in `tmp`, which the define declares scratch, and the `mkdir` is the same failing one; and under supervised no join is recorded at all |

**What this says about the funnel.** None of the 14 walls moved between the engines they were met on
(v1.7.0 to v1.12.0) and v1.15.0. The other 30 targets have a later verdict in the record, which is all
this run claims for them: they were not run on v1.15.0, and some of those verdicts were reached by going
around the wall rather than through it — fitscheck without its shared mapping (`use_memmap = False`),
vim on FAT where it writes no ACL, OpenTofu on one supervised run of two, gemini-cli with `mcp add` at
its default project scope where the main thread is the only writer, not the form that met the wall — so
the wall itself can still stand for them. The funnel's generated counts count every
(campaign, target) encounter, so the 14 rows this run adds raise the wall count rather than lower it;
`python3 spike/outcome-funnel.py summary --campaign dogfood/2026-10-22-walls-v1150` reads this run
alone.

**The next steps, by mechanism.** Seven of the fourteen are two threads of one process writing with
nothing recorded ordering them, with the tool's own one-thread switch set wherever the earlier runs
found one: ADR 0067 judges threads only where a recorded creation or join orders their writes, and
crossing these needs an order the engine does not record today (follow-ups 7 traced Jujutsu's to a
futex hand-over). Two more — vercel and codex — are refused by the threads gate for calls that change
nothing or touch a declared scratch path, which follow-ups 4 named and which is a narrower change. Two
meet `fallocate`, which the engine does not model. Two write through a shared mapping, refused by
design. One writes an extended attribute, which #947 is to rule on. Separately, the threads refusal's
next step names `UV_THREADPOOL_SIZE=1` to the two Node runs that already set it, and only Node's and Go's
switches to the four Rust ones.

The campaigns' own verdict tables did not all read v1.15.0's threads refusal: 2026-10-03's and
2026-10-05's `entry.sh` map it to `gate=2 detail=unmapped preflight answer (rc 2)` (`stdout.txt` of electrum and
basic-memory), because the refusal's `next` sentence changed since those scripts were written. The
refusal itself is the `UNKNOWN` line of each `preflight.txt`, which is what the rows above read.

DuckDB and dpkg's upgrade were not run here. Their later verdicts are the FAILs of
`spike/dogfood/2026-10-22-gate-calls/` (DuckDB 3/13; dpkg's upgrade 16/170 under `--observe supervised`),
reached on #970's build, which is not v1.15.0 and is not a funnel campaign; no run of v1.15.0 itself on
either is recorded.

## Erratum, after the run

`SELECTION.md` was fixed before the run with counts its selection script got wrong: the script read a
row's refusal from the first `UNKNOWN` anywhere in the record, and four 2026-09-11 rows cite that
campaign's whole `RESULTS.md`, whose first `UNKNOWN` belongs to another target — the trap
`spike/outcome-funnel.py` names beside its own reader. Read as that reader reads (a `.txt` record's first
line-start `UNKNOWN`, a report's field, a Markdown record's own row only), the funnel holds 74 such rows
(57 threads, 17 syscall — the issue's 17) on 44 targets, not 73 on 43: ocrmypdf's 2026-09-11 row
(`faccessat2`) was missed, and it has a later FAIL. `SELECTION.md`'s sentence that joplin's 2026-09-11
record says `baseline_violates_invariant` is wrong for the same reason; and its "on v1.15.0 they stay
refused" about DuckDB and dpkg was not measured. **The 14 measured targets are the same either way**
(`transcripts/select-before-run.txt` is the output the run was fixed by and `apparatus/select-before-run.py`
the script that printed it, both at the sha256 `fixed-before-measuring.txt` records under their earlier
names `transcripts/select.txt` and `apparatus/select.py`; run today it also counts this campaign's own
rows. `transcripts/select.txt` and `apparatus/select.py` are now the corrected ones). The scripts in
`apparatus/` were also tidied after the run: `select.py` reads as above and skips this campaign's own
rows, and `build-boxes.sh` now restores the vendored installer itself and stops on a failed base build
rather than continuing, where this run restored by hand and had no base build fail.
