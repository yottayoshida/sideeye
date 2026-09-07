# followup-527 — the reach question #526 and #527 both left open

**What this is.** Two changes shipped on 2026-09-07 widened what Sideeye can
observe: #526 stopped reading a shell's `PATH` lookup as several image changes,
and #527 added `--observe syscalls`, which counts the write family at the kernel
boundary instead of at the libc entry points. Each was measured against the
targets its own defect refused. Neither answered the questions a sweep answers:

1. **Does the new mode change the verdict of a target the default mode already
   judges?** #527 pinned that on toys only — the planted-bug toy and `TOY_LINK`
   — and disclosed it: "the mode does not move the count for a target the
   default path already handles" was measured on apparatus, not on a real tool.
2. **How much reach does it buy across the targets already recorded**, and which
   recorded walls does it *not* cross?
3. **#526's third define.** Its own record says "one of three, not three of
   three": of the three real defines whose refusal it removed, hnb reached a
   verdict, lbdb moved out to the multi-process wall ADR 0018 declines, and
   fontforge — reached through a wrapper written for an argument carrying spaces
   (#506) — hit the stdio flush boundary instead. #527 lifted that boundary, so
   the third define is answerable now and was not then.

**Apparatus.** Engine at `main` `05ed142`, cross-built
`zig build -Dtarget=aarch64-linux-gnu`. Its identity is recorded from inside the box
rather than asserted here: `artifacts/engine-identity.txt` holds the version line
and the sha256 of both artefacts, and `artifacts/engine-identity-4083db2.txt`
holds the same for the pre-change build the isort comparison below uses. The two
are separable by the version line alone — **contract v14 against v13** — which is
the bump `--observe syscalls` shipped. One `debian:trixie-slim` image
(`Dockerfile`) holding the fourteen targets the 2026-09-05 and 2026-09-06
dogfood runs measured. `run.sh` runs each target twice — once per mode — with
the same setup, operation and checker text as the run that first recorded it,
and `--oracle /usr/bin/strace` in both. `followup.sh` and `isort-old.sh` chase
the three rows whose default-mode result needed a second look.

**The state directory is on a container-local filesystem, and that is
load-bearing.** #528 measured that a macOS bind mount makes a restored file's
`/proc/self/fd/N` resolve to `… (deleted)`, which raises `unresolvable_path` in
*either* mode. Only the engine arrives through the host mount here.

**This is not a dogfood run.** `spike/dogfood/README.md` requires a run there to
measure the shipped build and to record its selection; this measures `main`,
because the mode it is about is unreleased, and it selects nothing — every
target here already has a row in `docs/target-classes.md`. Hence a followup
directory in the `spike/followup-95/` shape.

## What the sweep measured

One run per target per mode unless the row says otherwise. Verdict lines are
transcribed from the engine's own output in `artifacts/`, not recomputed — the
2026-09-07 correction to `docs/target-classes.md` was needed because a script
that recounted a column inflated it.

| Target | `--observe wrappers` (default) | `--observe syscalls` | Reading |
|---|---|---|---|
| metaflac 1.5.0 | UNKNOWN `oracle_missed_operation` | **PASS 13/13**, 12 crash points, oracle agreed on 12 operations | the wall #527 is about, crossed |
| fontforge 20230101 | UNKNOWN `oracle_missed_operation` | **FAIL 183 of 185**, 184 crash points, oracle agreed on 184 operations over 40187 syscall lines | same wall, crossed |
| fontforge **through a shell wrapper that `exec`s a bare name** | UNKNOWN `oracle_missed_operation` | **FAIL 183 of 185**, 184 crash points, 184 operations over 40251 syscall lines | #526's third define. Same verdict and the same counts as the direct spelling. Its `processes` field carries the image change — "the subject's image replaced 1 time(s), chain unbroken (#123)" — where the direct spelling's says "single process", so the exec chain was exercised |
| mutool (mupdf) | UNKNOWN `unresolvable_path` (`unlinked-fd close fd:3`) | UNKNOWN `unresolvable_path` (`unlinked-fd close fd:3`) | **the one wall that did not move.** See below |
| mid3v2 (mutagen) | PASS 10/10, 9 crash points, 9 operations, 2020 syscall lines, 123 in scope | PASS 10/10, 9 crash points, 9 operations, 2020 syscall lines, 123 in scope | identical to the digit |
| bsdtar (libarchive) | PASS 3/3, 2 crash points, 2 operations, 207 lines, 12 in scope | PASS 3/3, 2 crash points, 2 operations, 207 lines, 12 in scope | identical to the digit |
| isort 6.0.1 | PASS 9/9, 8 crash points, 8 operations, 2737 lines, 73 in scope | PASS 9/9, 8 crash points, 8 operations, 2737 lines, 73 in scope | identical to the digit; the count differs from the recorded row, see below |
| fonttools | FAIL 1 of 3, 2 crash points | FAIL 1 of 3, 2 crash points, 2 operations | same |
| bean-format | FAIL 1 of 3, 2 crash points | FAIL 1 of 3, 2 crash points, 2 operations | same |
| pyupgrade (`--expect-status 1`) | FAIL 1 of 3, 2 crash points | FAIL 1 of 3, 2 crash points, 2 operations | same |
| jpegtran | FAIL 1 of 3, 2 crash points | FAIL 1 of 3, 2 crash points, 2 operations | same |
| exiv2 | FAIL 3 of 7, 6 crash points | FAIL 3 of 7, 6 crash points, 6 operations | same |
| rdiff-backup | FAIL 4 of 69, 68 crash points, 68 operations | FAIL 4 of 69, 68 crash points, 68 operations | same |
| mogrify (ImageMagick) | first run UNKNOWN `baseline_violates_invariant`; then **FAIL 6 of 13 in 3 of 3 further runs** | **FAIL 6 of 13 in 3 of 3 runs**, 12 crash points, 12 operations | the target is not byte-repeatable in either mode, see below |
| qpdf | UNKNOWN `recording_run_failed` on this run's PDF; **FAIL 1 of 9, crash point 7 of 8** on the 2026-09-05 apparatus's PDF | the same two results in the same order | the first PDF was mine, not qpdf's, see below |

**Counted.** `docs/target-classes.md` records **eighteen** targets from the two
dogfood runs; **fourteen** are re-run here, and the four left out are the walls
this mode is not about (chezmoi and gopass, static; beets and joplin, threads).
Of the fourteen, **eleven reach a verdict in the default mode and all eleven reach
the same verdict under `--observe syscalls`** — nine of them in the sweep as run,
plus mogrify and qpdf once the two apparatus faults below were removed. All eleven
match on the world count, the crash-point count and the oracle's operation count.
**The syscall-line count is equal across modes for ten of the eleven** (mid3v2
2020, fonttools 4031, bsdtar 207, bean-format 2169, isort 2737, pyupgrade 1728,
jpegtran 87, exiv2 286, mogrify 672, qpdf 525); the sole exception is
**rdiff-backup, 6862 against 6859**, the largest account in the set. **Two of the
three that the default mode refuses cross** (metaflac and fontforge, the latter
in both spellings). **One does not** (mutool), and it refuses identically in
both modes.

## What this also settles: the bind mount did not distort the ledger

The entry that corrected #527's rates left a standing suspicion — "every dogfood
number in `BUILDLOG.md` measured on that bind mount is suspect for the same
reason". For these fourteen rows it can be retired, because the sweep ran on a
container-local filesystem and **twelve of the fourteen reproduce their recorded
result exactly, down to the earliest crash-point index wherever the row states
one**: mogrify 6 of 13 at crash point 2 of 12, qpdf 1 of 9 at 7 of 8, exiv2 3 of
7 at 2 of 6, fonttools / bean-format / pyupgrade / jpegtran each 1 of 3 at 2 of
2, mid3v2 10/10, bsdtar 3/3, metaflac and fontforge as #528 recorded them, and
mutool's refusal. Every index is identical between the two modes as well.

**Two do not reproduce, and neither difference is the mount or the mode:**

- **isort** — 8 crash points today against the row's 6, in both modes, and the
  pre-change engine gives 8 as well (below).
- **rdiff-backup** — this sweep used the **verify-only** checker from
  `explore.sh`, not the `regress`-first checker whose result the row's headline
  reports. It answers **FAIL 4 of 69, earliest crash point 60 of 68** in both
  modes, where the 2026-09-05 run's verify-only variant flagged **5** worlds and
  its regress variant left **1** at crash point 51. One world's difference
  against a same-shaped checker, equal in both modes, not chased — the recovery
  contract that row is about was measured that day and is not re-opened here.

## The three rows whose default-mode result needed a second look

- **mogrify is not byte-repeatable, in either mode — and the first version of this
  measurement did not measure that.** `followup.sh` originally called
  `preflight --twice` without `--observe`, so both runs were the default mode
  while three documents said "in both modes"; the two outputs were **byte
  identical**, which is what one measurement copied looks like, and the initial
  review caught it. That pair is kept as
  `artifacts/tw-mogrify.SUPERSEDED-no-observe-flag.*.txt` — the file name carries
  the mark, because `followup.sh` now passes the flag and no longer reproduces
  those two files. Re-run with the flag (`fix-p0.sh`,
  `artifacts/tw2-mogrify.*.txt`): **both modes refuse**, all three PNGs
  `content differs`, **2010 ms apart under `wrappers` and 2007 ms apart under
  `syscalls`** — the delta is now the only difference between the two files,
  because a preflight report **does not name its observation mode** unless
  `--oracle` was given, which is exactly why the omission was invisible in the
  artifact. So the `baseline_violates_invariant` the first sweep run hit is the
  target's own non-determinism arriving in whichever run it arrives in: seven
  explore runs the same day, **six FAIL 6 of 13 and one refused** — one of four
  under `wrappers`, none of three under `syscalls`. Those seven all carried
  `--observe`. This is a caveat on the recorded row, not on the mode:
  `docs/target-classes.md`'s mogrify row was measured on a target that fails the
  README's byte-repeatable-writes limit.
- **qpdf's first refusal was my PDF.** The minimal PDF `mkpdf.py` writes is read
  by mupdf and rejected by qpdf, which recovers the stream length, warns, and
  exits 3 — so the operation did not exit its declared status and the run was
  refused `recording_run_failed` in **both** modes. Re-run with the PDF the
  2026-09-05 apparatus generates (`magick` from a PNG), both modes answer
  **FAIL 1 of 9, earliest crash point 7 of 8, 8 crash points** — which is the
  recorded row exactly.
- **isort's crash-point count moved, and not because of these changes.** The
  2026-09-06 row records PASS 7/7 over 6 crash points; today both modes give
  PASS 9/9 over 8. The engine **before** #526 and #527 (`4083db2`) gives the
  same 9/9 over 8 crash points on the same apparatus (`isort-old.sh`), so
  whatever moved the count is older than the two changes this directory is
  about. Not chased further: the isort in this image is 6.0.1 and the 2026-09-06
  image was built a day earlier from the same suite, so the package version is
  the first place to look, and the mode question does not depend on it.

## What does change for a target that was already judged

The evidence field, by design and as documented. Under `--observe syscalls` a
PASS carries `oracle_verified_across_runs` and leaves `oracle_verified` false,
because a trapped write reaches strace twice and the comparison is positional,
so the oracle account is of a **separate untrapped run** of the same operation.
The verdict, the counts and the oracle's own agreement are identical; which
field carries the claim is not. `docs/report-schema.md` (v14) states this, and
a consumer keyed on `oracle_verified` alone would read the weaker field as
absent rather than as weaker.

## What this does not cover

- **x86_64 and macOS.** Everything here is aarch64 Linux in a container; CI is
  the x86_64 verifier for this mode, and the flag is refused as a setup error on
  macOS.
- **The four recorded walls this mode is not about**, none of them re-run here:
  chezmoi and gopass (`no_shim_marker`, every Linux artefact their projects
  publish is static) and beets and joplin (`multiple_threads_detected`).
- **Repetition.** One run per target per mode, except mogrify (four `wrappers`,
  three `syscalls`) and qpdf (two apparatus, two runs each). metaflac and
  fontforge were measured eight and four times respectively in #528, on this
  same filesystem arrangement, and reproduced here.
- **Which mode produced a preflight transcript.** The report does not print it
  unless `--oracle` was given, and even then it says only what the second run was
  watched by, not the mode's name — so `tw2-mogrify.wrappers.txt` and
  `tw2-mogrify.syscalls.txt` differ **only in the millisecond gap**. That the flag
  was passed rests on `fix-p0.sh`, not on the artifact. It is how the omission the
  first review caught went unnoticed, and a second omission would no longer leave
  the byte-identical pair that gave it away.
- **The mode's shipped costs**, which are limits rather than measurements and
  are listed in the README: an image the shim cannot be loaded into dies of
  `SIGSYS` on its first write, `pwritev2` / `copy_file_range` / `sendfile` stay
  at the libc boundary, and a 32-bit compat process is not readable by the
  filter.

## The one wall that did not move, and what it turned out to be

`docs/target-classes.md`'s mutool row was written when the refusal could not say
which operation it was about, and it predicted the fix: "#485 has since made the
refusal name it in the message itself … so a re-run of this target would say
which operation it was". It does, and in both modes, verbatim:

```
UNKNOWN  unresolvable_path
         an operation was observed whose path could not be determined
         (unlinked-fd close fd:3, pid 1997, last named .../mutool/a.pdf),
         so it cannot be placed among the crash points
```

The unplaceable operation is a **`close`**. `mutool clean` opens the input,
reads it, then `unlinkat`s it while still holding fd 3, and creates the output at
the same name on fd 4 — so by the time fd 3 is closed the descriptor's file has
no name to resolve. Measured under `strace -y`, the whole sequence in
`artifacts/strace-mutool-fd3.txt`: **after the `unlinkat`, fd 3 receives fifteen
`read`s and one `close`, and nothing else.** Read-only calls are not recorded at
all (ADR 0003's predicate), so the *only* recordable operation on the unlinked
descriptor is that `close`. Everything else in the run is placeable: the `open`,
the `unlinkat`, the `openat(O_RDWR|O_CREAT|O_EXCL|O_TRUNC)`, the single `write`
of 563 bytes, and the close of fd 4.

**This wall is one `close` wide**, and a `close` cannot be a crash point:

- `docs/adr/0003-what-counts-as-a-crash-point.md` §2 — "`close` is neither a
  kill point nor a mutation; its only role in the comparison was positional
  corroboration. It is now excluded from both class sequences."
- `src/contract.zig:382` — "lifecycle ops: recorded, never a crash point",
  directly above `close = 100`.
- `src/fsusage.zig:837` and `:850` — the macOS oracle's reader **already
  exempts it**: an unresolvable path or an unresolved descriptor raises its
  defect only `if (c != .close)`. The shim path has no such clause, which is why
  the same target refuses under Linux and the two readers disagree about a rule
  both cite.

This directory does not fix that. What it establishes is that a real tool, on a
normal filesystem, in both observation modes, is refused for the address of an
operation the engine has already decided it does not need an address for. The
plan written for this rule on 2026-09-07 was killed at its own step 0 because
its motivating target (metaflac) turned out to be the bind mount; mutool is the
target it should have named.
