# 2026-09-11 — selection

**The question is narrower than the earlier runs'.** v1.3.0 (2026-09-09) moved
three walls: threads (contract v16, ADR 0055 — one writing thread per process is
judged, a second refuses), awaited children (contract v15, ADR 0053 — writing
children that are reaped and do not interleave are judged), and stdio past the
flush under `--observe syscalls` (contract v14, ADR 0052). So the pool here is not
the selection rules' pool. It is **every target an earlier dogfood run turned away
on one of those walls that no later record has re-measured**, plus cohort 2's Bun,
because #540 asks for it beside joplin. Two targets outside the dogfood runs fit the
same description and are named in the table as not taken. The rules 1–3
metadata was measured when those runs screened them and is not re-measured here,
and nothing below claims novelty in the cohort sense.

## The pool

| Target | Turned away by | For | Re-measured since | Taken |
|---|---|---|---|---|
| joplin | 2026-09-05, slate 1 | any thread (contract v13) | no — #540 | ✅ |
| Bun | cohort 2 (2026-08-21) | any thread | no — #540 | ✅ |
| newsboat | 2026-09-05, slate 2 screen | 2 threads | no | ✅ |
| oxipng | 2026-09-05, slate 2 screen | 11 threads (2 with `-t 1`) | no | ✅ |
| rsync | 2026-09-05, slate 2 screen | 2 forked children | no | ✅ |
| ocrmypdf | 2026-09-06, slate 1 screen | `execve` 31, `clone` 12 before the operation | no | ✅ |
| ansible | 2026-09-06, slate 2 screen | 2 threads, 43 `execve` | no | ✅ |
| sqlfluff, libvips, zstd, bundler, git-annex | 2026-09-06, slate 2 screen | threads | `spike/followup-item4/` (2026-09-08) | no |
| beets | 2026-09-05, slate 1 | threads | `spike/followup-item4/` — two threads write `library.db`; #539 | no |
| mlr | 2026-09-06, slate 1 screen | 6 threads | `spike/followup-item4/` — `epoll_ctl` refuses before the thread rule; #542 | no |
| metaflac, fontforge | 2026-09-06, slate 1 | stdio past the flush | `spike/followup-527/` (2026-09-07) | no |
| mutool | 2026-09-06, slate 1 | `unresolvable_path` (a `close`) | `spike/followup-522/` (2026-09-08) | no |
| cargo | cohort 3 | a child's thread, then a raw `rename` | not a dogfood target; #538 asks for its re-measurement, and its second wall did not move | no |
| `gh` (Homebrew) | the toy section of `docs/target-classes.md` | threads | macOS, and this run is Linux in Docker | no |
| chezmoi, gopass, shfmt, dasel | 2026-09-05, 2026-09-06 | static linkage | the wall did not move (#217) | no |

Seven taken. The earlier runs took slates of four; this one takes the whole pool,
because the pool is the question.

## Install

- **Sideeye**: the release tarball, not a build. RESULTS has the digest.
- **Debian trixie packages** (every version below is in
  `transcripts/probes/probes-review.txt`): newsboat `2.36-1.1`, rsync `3.4.1+ds1-5+deb13u4`,
  ocrmypdf `16.7.0+dfsg1-3` (with tesseract-ocr `5.5.0-1+b1` and ghostscript
  `10.05.1~dfsg-1+deb13u1`), ansible-core `2.19.4-0+deb13u1`, python3 `3.13.5-1`,
  libc6 `2.41-12+deb13u3`.
- **oxipng is not packaged in trixie** (`MISSING oxipng` in `transcripts/runs/build.log`). The
  10.2.1 release binary for `aarch64-unknown-linux-gnu` — dynamically linked — was
  downloaded on the host, as the 2026-09-05 screen's was.
- **Bun** 1.4.2, the latest stable (released 2026-09-05): `bun-linux-aarch64.zip`
  from the release, downloaded on the host, because the container's TLS goes through
  an intercepting proxy. Cohort 2 measured 1.4.0.
- **joplin** from npm with the four fixes the 2026-09-05 run needed on trixie; npm
  installed 3.7.1, under node 20.19.2. The first build's `joplin --help` check exits 1
  (`transcripts/runs/build.log`) and the second build's `joplin version` exits 0
  (`build2.log`) — 3.6.x had failed that command on a missing `package.json`.

## The screen: two instruments, before any checker existed

Each target ran once under `strace -f -y`, read by `apparatus/screen-strace.py` for
threads, processes, and **which tids of which process wrote the state directory** —
the count v16 asks — and once under `sideeye preflight --oracle strace` in each
observation mode (`apparatus/screen.sh`; `transcripts/runs/screen-run1.txt` and
`screen-run2.txt`).

| Target | Linkage | Threads / processes created | tids that wrote the state | preflight, both modes |
|---|---|---|---|---|
| newsboat | dynamic | 0 / 0 | 1, the subject | accepted, 403 operations |
| oxipng | dynamic | 10 / 0 | 1, the subject's main thread | accepted, 2 operations |
| rsync | dynamic | 0 / 2 | 1, a child | accepted — contract v15 |
| ocrmypdf | script → `python3` | 9 / 14 | 1, the subject | `unsupported_syscall_observed` (`faccessat2`) |
| ansible | script → `python3` | 1 / 26 | 1, a module's `python3` | `child_process_detected` |
| joplin | script → `node`, dynamic | 10 / 0 | **4**, all in the subject | `multiple_threads_detected`, two named |
| Bun | dynamic | 6 / 0 | 1, the subject | `oracle_missed_operation` (`openat`) |

Two screening results differ from the earlier runs' and are not contradictions:

- **newsboat creates no thread here.** The 2026-09-05 screen reloaded an `https://`
  feed and counted two; this run reloads a `file://` feed and counts none. The
  thread count belongs to the operation, not to the tool — the same reading mid3v2
  gave against beets on 2026-09-06.
- **The screen names rsync's writer as a child.** That is what contract v15 admits,
  and what the earlier screen, counting children and nothing else, could not tell
  apart from a refusal.

The first screen made two apparatus errors — `mkpdf.py` copied into the build
context instead of the mounted directory, and rsync's same-size, same-second setup —
and both are in RESULTS. The second screen is clean.
