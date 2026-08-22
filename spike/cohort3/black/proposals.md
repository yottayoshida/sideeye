# Cohort-3 define: black (target 2)

Target: black 26.5.1 (the image's pinned current stable). Probe:
conditions 1–6 machine-green with condition 7's ambient evidence
printed, `../probes/black.txt` — byte-deterministic, closure clean,
**zero threads** (the transcript's count) and **zero children** (the
committed raw log, `../probes/raw/black.strace`: one execve, no
clone/fork/vfork). Scout sources: black's usage documentation
(`--no-cache`, `--safe`) and the probe transcript. Assisted provenance,
per the cohort protocol.

## Why this target, this operation

A formatter rewriting source **in place** is the textbook shape this
tool exists for: the input is the user's primary data, and the rewrite
is a single truncate-and-write with no transaction machinery. Measured
2026-08-22 (an engine-free logger trial, **uncommitted**, named here as
such; the explore's own two-witness recording re-verifies the same
fact): black's write reaches the file through libc — `open64` with
write flags fired an interposing logger of the same form whose
rename-interposition stayed silent for cargo's manifest rename
(`../cargo-r2/raw-rename-diagnosis.txt` is that committed cousin). So
the whole operation sits inside the shim's reach. The probe found no
temp file and no rename: the root holds exactly `probe.py` before and
after.

## The property (P1, chosen)

**Kill `black --no-cache probe.py` anywhere; the source must survive as
a program.** After the crash:

- **guard**: `probe.py` exists;
- **leg V**: the file parses as Python — a truncated tail that no
  interpreter can read again is the destruction this define exists to
  catch;
- **leg E**: the parsed AST equals the frozen pre-operation program's
  AST — black's own `--safe` contract (paraphrased: the reformatted
  code must be a valid AST equivalent to the original; leg E is
  deliberately **stricter** than black's own check, which carves out
  effects like docstring re-indentation — this fixture has no
  docstrings, so the two coincide, and the green-new drill proves it)
  applied across a crash: formatting, interrupted or not, must never
  change the program.

Both the old bytes and black's formatted output satisfy V and E (the
green drills prove each side); a torn intermediate fails one of the two
— which one depends on where the tear lands.

## The torn-file reading, declared before the explore

The probe's raw strace pins the write shape: the whole rewrite is one
`openat(O_WRONLY|O_CREAT|O_TRUNC)` followed by **one** 88-byte `write`
(`../probes/raw/black.strace`). At the engine's between-syscall kill
granularity the reachable tear is therefore the **empty file** — the
kill between the truncating open and the write — and an empty file
*parses* (an empty module): **leg V green, leg E red**. A partial
write, if the engine's model ever produces one, tears mid-token and
fails leg V; a line-boundary tear parses as a different program and
fails leg E (R1 swept every byte-prefix of the formatted output: 25 of
89 prefixes parse, 23 of those are different programs, and only the
full content and content-minus-final-newline are AST-equal). Declared
now, ahead of any world: a torn `probe.py` fails **leg V or leg E —
checker-red, a criterion-1 candidate shape, whichever leg names it**
(the
earliest case's violated invariant would name the checker, possibly in
the combined "built-in atomicity, and the checker" form, which the
frozen claim rule reads as a candidate: it excludes L0-only). No
recovery leg exists because black documents no crash recovery and the
source file IS the primary data — the cargo precedent's principle (the
checker asserts directly what the tool's own contract promises; a
manual repair step no document prescribes is not a recovery), applied
where no self-heal mechanism exists at all. Whether any resulting
candidate is claimed or reported stays behind the standing gates.

## Where the crash lands

Every kill point inside the single in-place rewrite.

## Rejected shapes

- *Asserting `black --check` passes after the crash* — the OLD bytes
  legitimately fail `--check` (they are unformatted); old-or-new byte
  identity is L0's job, and the checker's job is the program's
  survival, which both sides satisfy.
- *A multi-file pre-state* — multiple files engage black's
  multiprocessing (threads, the refusal class); the single-file shape
  is both the probed shape and the sweet spot.

## Stock reproduction

Any finding must reproduce against stock black with no apparatus beyond
strace fault injection before it is claimed or reported — the cohort
rule, unchanged.
