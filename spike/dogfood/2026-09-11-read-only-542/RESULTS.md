# 2026-09-11 — mlr and ocrmypdf past `epoll_ctl` and `faccessat2` (#542, first of two)

Two targets the oracle refused `unsupported_syscall_observed` for a call that changes
nothing: mlr for `epoll_ctl` (Go's netpoller registering its temporary file), ocrmypdf for
`faccessat2` (asking whether it may write its input). This change reads both as reads
(`src/oracle.zig`, `read_only`). Each target was run with the `main` build (`abad4ce`,
"before") and with this change's build ("after"), in the same image, as an unprivileged
user, with state and work on the container's own filesystem.

| target | before | after |
|---|---|---|
| mlr 6.13.0, six explorations of one define | 6 of 6 `UNKNOWN unsupported_syscall_observed epoll_ctl` | 6 of 6 `UNKNOWN oracle_missed_operation`, divergence at operation 1: the `openat` of `mlr-in-place-*` (`divergence_syscall: openat`) |
| ocrmypdf 16.7.0, preflight, both modes | `unsupported_syscall_observed faccessat2` | `recording accepted — 2 state-changing operation(s) observed`, the oracle agreeing on 2 |
| ocrmypdf 16.7.0, explore, both modes | `unsupported_syscall_observed faccessat2` | `UNKNOWN baseline_violates_invariant` — the re-run from the restored state left `a.pdf` holding neither recorded content |
| ocrmypdf 16.7.0, `preflight --twice` (after only) | — | not accepted: `a.pdf (content differs)`, and the same with `SOURCE_DATE_EPOCH=1700000000` |

Both expectations were written down before the runs (BUILDLOG, 2026-09-11, #542). mlr's
came out as written, down to the operation. ocrmypdf's said only "past `faccessat2`, to a
verdict or a different refusal", and did not name the refusal it met.

**mlr** refuses where its real wall is. Linux Go issues its file calls as raw syscalls, so
the shim records none of mlr's operations — five or six threads created, none of which wrote,
in every run — and the oracle's first state-directory operation has nothing on the shim's
side to meet. That is the wall of `docs/target-classes.md`'s "state writes bypass libc" row
(cargo). Counting those writes is the second plan of #542.

**ocrmypdf** is past the refusal and meets the next one: its output is not byte-repeatable.
README, "What the target has to be": *a second clean run from the restored state must leave
the same bytes under `--state`*. Two runs differ on `a.pdf`, and pinning the clock through
`SOURCE_DATE_EPOCH` does not make them agree, so no define tried here reaches a verdict.
Behind the wall there is something worth a later run: in both modes one of the two crash
worlds left `a.pdf` empty — the checker's `a.pdf does not start with %PDF- (0 bytes)` — which
is the shape of a rewrite that truncates the original before it writes the new one. It is
seen, not judged: the baseline's refusal stands in front of every world, and which crash
point it was is not established here. That the empty file was a crashed world and not the
baseline is read off two things: the report counts `violations: 1` (crash worlds are
explored before the baseline), and the baseline's own refusal carries no "the checker
rejected that state too" clause, which it would if the un-crashed world had left a file the
checker refused.
Under `--observe syscalls` the transcripts still carry #556's `SIGSYS` in the children that
probe for absent tools, as on 2026-09-11; ocrmypdf itself carries on.

## Files

- `SELECTION.md` — why these two targets and no others
- `apparatus/mlr.sh`, `apparatus/ocrmypdf.sh`, `apparatus/ocrmypdf-twice.sh` — the scripts
  that ran, each taking the label of the build mounted at `/se`
- `apparatus/Dockerfile` — the ocrmypdf image
- `transcripts/` — every report (`.txt`, and `.json` for explorations), each script's
  console output (`*.console.txt`), and `mutants-one-name-at-a-time.txt`: the unit test and
  the toy's exploration with one name dropped from the oracle's read-only list at a time

Images: mlr in `sideeye-reach:2026-09-07` (`spike/followup-item4/Dockerfile`); ocrmypdf in
`debian:trixie-slim` with strace, file, python3, ca-certificates, procps, ocrmypdf,
tesseract-ocr-eng and ghostscript from apt — the ocrmypdf half of the 2026-09-11 run's
Dockerfile, whose oxipng and Bun binaries were copied from a host that no longer has them.
The input PDF is that run's `apparatus/mkpdf.py`.

The first attempt of both scripts ran as an unprivileged user with state under
`/localrun`, which that user cannot create: every run was a SETUP ERROR. ocrmypdf's second
attempt ran with an unwritable `HOME`, where fontconfig and tesseract could not cache — which
alone could have split the output, so nothing was read off that run. Both are fixed in the
scripts; the transcripts here are from the runs after the fixes, which overwrote the
earlier ones name for name.
