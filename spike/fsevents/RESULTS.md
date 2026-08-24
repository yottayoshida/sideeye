# Route B measured: what FSEvents can and cannot verify (#286)

Run on macOS 15.3.1, arm64, SIP enabled, entirely unprivileged. Transcript:
`survey.txt`, `BROKEN checks: 0`. Apparatus: `watcher.c` (FSEventStreamCreate
direct, JSON Lines out, dispatch queue since ScheduleWithRunLoop is deprecated
as of macOS 13), `probe.c` (one operation per run, failures included, and a
sentinel mutation closing every run), `judge.py` (verdicts plus a 25-case
selftest), `survey.sh` (the driver).

Two hypotheses, kept apart, and only the first is judged.

- **H1** FSEvents can produce a full OpClass sequence, good enough to drop
  into `src/oracle.zig`'s `compare()`.
- **H2** FSEvents can act as an independent veto, catching a mutation the
  shim failed to report.

Every `--run` ends by creating one file whose event must arrive. Without that
sentinel an empty capture cannot be told from a run where delivery did not
work, and this survey produced exactly that failure before the sentinel
existed: a settle shorter than the stream's latency gave five consecutive
empty captures that read as "FSEvents reported nothing". A capture whose
sentinel is missing is now BROKEN, never a finding.

## H1 is dead

### The decisive counterexample: a failed attempt produces no event

Seven modes issue a call that fails and changes nothing: `fail-open` (ENOENT),
`fail-unlink` (ENOENT), `fail-rename` (ENOENT), `fail-mkdir` (EEXIST),
`fail-rmdir` (ENOENT), `fail-link` (ENOENT), `fail-truncate` (ENOENT). In each,
the sentinel's event arrived and the operation's own path produced **no event**.
Delivery worked; there was nothing to deliver.

`shim/src/ops.zig` records each attempt before it runs and states why: a failed
attempt has to count on both sides or the two accounts desync. So the shim's
sequence carries an entry this capture does not, and `compare()` diverges
there. Each failing mode ran once; the repeated legs are L2 and below.

This alone settles H1. The rest is corroboration, and is reported as such.

### Corroboration 1: two different sequences collapse to the same observation

The `write` mode issues `open`, `write`; the `fsync` mode issues `open`,
`write`, `fsync`. Both are against one path, and in L1 both produced a single
entry carrying the same decoded flags (`ItemCreated`, `ItemIsFile`,
`ItemModified`). Two different OpClass sequences, one identical observation.

Across 30 runs of the `fsync` mode (6 configurations, 5 repetitions each), 25
delivered one entry and 5 delivered two. `gap=200ms` between the syscalls did
not reliably separate them.

**The distribution is not stable between sweeps.** Four sweeps of the same 30
configurations, during the development of this apparatus, gave 29/1, 30/0,
28/3 and 26/5 before the committed 25/5. No single count here is a property of
the platform. What the leg establishes is that one run at these settings
cannot distinguish collapse from separation, which is why it repeats and why
this paragraph exists instead of a cleaner number.

`FSEvents.h` says the collapsing is intended: latency exists to "reduce the
chance that the client will see an intermediate state, like those that arise
when doing a safe save of a file". A safe save is the write pattern this
project judges.

### Corroboration 2: a two-path operation is reported on one path

`link` creates a second name for an existing file. `src/contract.zig` treats it
as one operation. The capture holds two entries and neither belongs to the
source: the new name reports `ItemCreated`, `ItemIsFile`, `ItemIsHardlink`,
and the **source path produced no event at all**. `rename` also produced two
entries for one call.

So the entry count diverges from the operation count in both directions, and
the paths a capture names are not the paths an operation touched.

This one was found by the judge only after it was rewritten. The earlier
version scored mapping as "any of this operation's paths was seen", which
counted `link` as fully observed. The review that prompted the rewrite is
the reason it is in this document.

## Attribution is not available

Two runs performed the same operation on the same absolute path, differing
only in which program did it: the probe in run A, `/bin/sh` in run B, both
creating `state/target` and `state/sentinel` from the same cleared directory.
The captures agree in path and in flags. The output cannot say who acted.

Getting this leg to mean anything took two corrections, both harness bugs
rather than findings. Giving each side its own parent directory made the
absolute paths differ; leaving the first run's sentinel in place turned the
second run's create into a truncate and added `ItemInodeMetaMod` to it. Both
produced "the captures differ" for reasons with nothing to do with attribution.

`MarkSelf` and `IgnoreSelf` do not close this. Both concern the watcher's own
process: with `--mark-self` the watcher's own write carried `OwnEvent` and the
probe's did not; with `--ignore-self` the watcher's own write vanished and the
probe's remained. The framework separates exactly one process, itself, from an
undifferentiated everyone-else.

This reaches past H1. `src/main.zig` refuses a run when the oracle reports
`child_touched`, and `src/oracle.zig` calls the oracle "the only observer that
sees it whether or not the child loaded the shim". FSEvents cannot supply that
predicate.

## The flag word describes the path, not the delivery window

In L1, every mode whose setup created the file before the watcher started
carried `ItemCreated` on the event for the operation under test. Two
explanations fit: the flags summarise what is known about the path, or the
setup's own event was still in flight. L6 separates them by waiting. **In the
single run measured**, a 3 second pause between the setup and the watcher's
start still produced an event carrying `ItemCreated` for a later `open`+`write`.
One run does not establish a rule, and no longer pause was tried.

This is the finding with the longest reach, because H2 rests on reading a
capture as "what changed here, now".

## What was not measured

- **H2 itself.** The apparatus is what it needs; "what fraction of unreported
  mutations does this catch" is a different measurement against a different
  corpus.
- **`fsync` alone.** In the 32 runs that issued it (1 in L1, 30 in L2, 1 in L3)
  no entry was attributable to it. FSEvents has no flag for a durability
  barrier, and the entry that arrived carried the union of the flags for the
  whole sequence. The transcript cannot say whether `fsync` produced one.
- **Whether `write` and `truncate` are separable.** Both carry `ItemModified`;
  both truncate modes additionally carried `ItemInodeMetaMod`, and so did a
  create over an existing file. Whether that separates them reliably is
  untested.
- **Whether the L1 result is stable under repetition.** Each of the 18 modes
  ran once. L2 repeats because coalescing proved timing-dependent; the
  failing-attempt result is not obviously timing-dependent, but it was not
  repeated and this sentence is the only thing saying so.
- Behaviour under load, on non-APFS volumes, over a network mount, and after a
  Full Disk Access grant. A grant would end the unprivileged premise, which is
  why it is out of scope rather than merely unmeasured.
- Any other macOS version. Every number here is one machine, one OS build.

## Where this leaves #286

H1 is dead. Route B cannot be a drop-in replacement for the oracle, and the
failing-attempt leg settles it without the rest of the matrix.

H2 is not judged, and is not obviously alive: the two findings above (no
attribution, and flags that describe the path rather than the window) bear on
it directly. Anyone picking it up should read those two sections first.

Route C, the one-time `sudo` calibration against `fs_usage`, still stands on
the measurement `#181` gave it. Route B has now been measured and the
measurement killed H1; route A remains a sketch. Route C is the one route in
`#286` that is both measured and still standing.
