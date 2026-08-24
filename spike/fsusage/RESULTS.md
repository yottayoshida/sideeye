# Route F1 measured: fs_usage at the four points (#286)

Run on a GitHub Actions macOS runner: macOS 26.5.2 (25F84), arm64, SIP
disabled there, uid 0, `kern.hv_vmm_present` 1 (a virtual machine), the
state directories on APFS (`/dev/disk3s5` on `/System/Volumes/Data`). Every
number below is that machine and that build; the owner's laptop (15.3.1) has
not run this survey. Transcripts: `survey.txt` (unprivileged half) and
`sudo-survey.txt` (privileged half, run 32690217527). Raw captures, probe
accounts and shim traces for every leg are under `captures/`. `BROKEN checks:
0`, measured DEAD verdicts 2.

The survey ran five times. Rounds 1 and 2 (runs 32687071111 and
32687503436) returned ten and eleven failures respectively, every one of them
the apparatus; round 3 (32687827616) was clean and then first-look review
found seven verdicts greener than their predicates; round 4 (32689458393)
carried those fixes and its confirmation review found three more; the
BUILDLOG entry of 2026-08-24 records each. Round 5 is the transcript
committed here, produced by the code beside it.

## The premise held: the runner's sudo needs no human

`sudo -n true` exits 0. `fs_usage` runs and, unfiltered, produces 27,994
lines in two seconds. The privileged leg that yesterday needed the owner at
a terminal ran 27 times here with nobody present.

## P4: failed attempts leave a line

Seven modes issue a call that fails and changes nothing. All seven produced
a line carrying the errno in brackets and the attempted path:

```
open      [  2] (_WC_T__________)  .../P4-fail-open-state/missing-dir/leaf
unlink    [  2]                    .../P4-fail-unlink-state/missing
rename    [  2]                    .../P4-fail-rename-state/missing
mkdir     [ 17]                    .../P4-fail-mkdir-state/subdir
rmdir     [  2]                    .../P4-fail-rmdir-state/missing
link      [  2]                    .../P4-fail-link-state/missing
truncate  [  2]  O=0x00000004      .../P4-fail-truncate-state/missing
```

The counterexample that killed FSEvents (PR #291: a failed attempt has no
event) does not touch fs_usage. The shim records the attempt; the observer
shows it.

## P1: the trailing number is a thread id, and it maps

fs_usage(1) says the number after the process name is a thread id, not a
pid. Two copies of the probe, same file name, same state directory, same
operation, each reporting its own `pthread_threadid_np`:

- Under a name filter covering both, every state-directory line carried one
  of the two reported tids (32490 on 10 lines, 32491 on 10) and nothing
  else. What this measures is that the number fs_usage prints and the one a
  process reads about itself through `pthread_threadid_np` are the same
  namespace. Whether a launcher can enumerate a *target's* threads from the
  outside, in time, and match them is not measured here; a single-threaded
  probe that reports its own id is the strongest statement this survey makes.
- Under a pid filter naming one process, the other leaked nothing (10 lines
  kept, 0 leaked). The pid argument is honoured.
- A forked child is not followed under its parent's pid filter (0 lines for
  the child's file), while the same child write under a name filter that
  covers it produced 4 lines, so the absence is the filter's doing and not
  the child's. An adapter that wants children must not filter by pid; it
  can capture everything and scope by state path, attributing by tid.

## P2: write syscalls are visible, and 1:1 with the shim's records

`write` prints as `write F=3 B=0x7`, with no pathname. Placed through the
`open F=3 <path>` that preceded it on the same thread, the count matched the
shim's own trace in every mode:

| mode | shim writes | capture write lines |
|---|---|---|
| write | 1 | 1 |
| writes-small (three consecutive on one fd) | 3 | 3 |
| writes-two-fd (two fds interleaved) | 4 | 4 |
| write-large (one 4 MiB write) | 1 | 1 |
| write-zero (zero bytes) | 1 | 1 |
| pwrite | 1 | 1 |
| writev | 1 | 1 |
| stdio (fprintf + fflush) | 1 | 1 |
| fsync mode's write | 1 | 1 |

`pwrite` prints as `pwrite` and `writev` as `writev` (an earlier draft of
this file said both print as `write`, from a listing cut at eight entries;
the captures say otherwise). The 4 MiB write is one syscall line and 2 `WrData` disk-io lines;
the disk-io lines are a separate bucket and never counted as syscalls.

`fsync` is its own line (`fsync F=3`), one of one, under `-f filesys` and
under no class filter at all, beside the synchronous `WrData[ST1]` it
causes. An earlier reading of this survey had it invisible; three truncated
reads (a grep that matched the leg's name in a path, a listing cut before
the line, a `head` that dropped a one-count entry) agreed with each other and
were all wrong. The verdict judges by CALL name over the whole thread.

Ordering: in both `write-then-rename` and `write-then-unlink`, the write's
line precedes the tail operation's.

## P3: two walls, both measured

**A rename line names only its old path.** `rename  .../P3-state/target`;
the destination never appears on any line. ADR 0006 scopes a two-path
operation by either endpoint, so a rename whose old name is outside the
state directory and whose new name is inside it would be invisible to an
fs_usage-based oracle, and a rename within the directory can be scoped but
its destination not checked.

**Wide mode displays at most about 153 characters of a pathname, cut from
the left** (144 in round 3, 153 in rounds 4 and 5; the cap moves, the cut does not).
A state directory whose sentinel path was 259 characters printed
as `ted-component/nested-component/.../state/sentinel-start`; the state
directory's own prefix was gone, so nothing in the capture could be scoped
to it. The man page's "last 28 bytes" is not what this build does in narrow
mode either (58-character paths printed intact there), but narrow mode
prints no thread id at all.

A directory name holding a space and Japanese (`wei rd-ステート`) printed byte
for byte in wide mode.

## What the observer's shadow looks like

Every op the shim records is bracketed on the target's thread by `fstat64
F=n` and `fcntl F=n <GETPATH>` (the shim resolving the descriptor), and the
shim's trace writes appear as `write F=900`. The probe's own stdout appears
as `write F=1`. Descriptors nobody saw opened in the window are exactly
those two. An adapter has to know this is the observer's shadow, not the
target's work; it is classified, never dropped, in every capture here.

## Census

27 of the 28 captures were classified line by line, the narrow-mode one
through its own grammar (no thread id). The 28th, the deep-path leg, is
excluded by construction: every path in it is cut below the state directory,
so state-scoped classification is exactly what that leg shows failing, and a
census of it would report the sentinels missing. `other_state` (a
state-directory line whose CALL the judge does not know) was 0 in all 27;
`unparsed` was 0 in all 27. A census is gated on both sentinels
like every other verdict, so an empty capture cannot report zeroes.

## Second machine: the owner's laptop, SIP enabled, not a VM

Transcripts `survey-laptop.txt` and `sudo-survey-laptop.txt`, captures under
`captures-laptop/`: macOS 15.3.1 (24D70), arm64, **SIP enabled**,
`kern.hv_vmm_present` 0, APFS. `BROKEN checks: 0`, DEAD 2.

Every capability finding reproduced: P4 7 of 7, P2 1:1 in all nine modes and
fsync visible under both filters, P1's pid filter and thread-id mapping and
the child control, census 27 with `other_state` and `unparsed` at 0. The two
DEAD verdicts are the same two walls. The only number that moved is the
display cap: 156 characters here against 144 and 153 on the runner, cut
from the left in both.

Two output shapes appeared here that the runner never produced, and the first
pass of this leg reported both as findings before they were understood:

- **A process name can contain spaces.** `Google Chrome He.64625821` broke a
  grammar that read the process field as `\S+`, so those lines landed in
  `unparsed` and the census refused the capture. The census was right to
  refuse; the grammar was wrong. The runner simply had no such process.
- **macOS 15.x pads a truncated pathname with `>`.** A failed `open` on a
  long path printed `.../missing-d>>>>>>>>>>>>>>>>` with its errno present,
  and exact-path matching missed it, so P4 read as DEAD on this machine.
  The `>` are a truncation marker, not path bytes; what remains is a genuine
  prefix, and `same_path` now accepts a stump against the path it was cut
  from (and rejects a stump of a different path).

Neither is a 15-versus-26 capability difference. Both are general properties
of the format that 26.5.2 happened not to exercise, and both would have
surfaced the first time an adapter ran on a laptop.

## What was not measured

- Any machine other than these two.
- Behaviour under load (event drop), which #181 named and this survey did
  not attempt.
- Non-APFS volumes, network mounts.
- Whether the rename destination is available through any other fs_usage
  mode or flag. This invocation (`-w -f filesys`) does not show it.
- Whether the depth cap moves with terminal width or any flag. 144, 153 and
  156 are what four runs of this invocation printed on two machines.

## Where this leaves #286

Three of the four points hold on both machines: failed attempts are visible
with errno, the thread id fs_usage prints is the one a process can report
about itself (external enumeration unmeasured), and write syscalls match the
shim's records one for one. The
fourth has two measured walls, neither of the kind that killed FSEvents: a
per-class gap (rename's destination) and a length cap sideeye could enforce
on the work directory it hands the target.

Whether an adapter is worth building behind those two walls, and whether it
goes before v1.0, is the owner's decision. The measurement that decision
needed is now on disk.
