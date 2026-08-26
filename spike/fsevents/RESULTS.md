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

---

# H2 measured: FSEvents as a veto rather than an oracle (#293)

Added 2026-08-25. The section above killed H1 — a capture cannot be rebuilt
into the `OpClass` sequence `src/oracle.zig` compares. `#293` asked the weaker
question, and it needed a weaker relation. The one measured here is **path set
containment**: every path FSEvents reports must be one the shim's account
already names. Containment passes through coalescing and reordering by
construction, because it never asks which event belongs to which operation —
the two properties that killed H1.

Both legs take their ground truth from the probe's own record of what it did,
never from the shim. Judging FSEvents against the shim in an experiment about
the shim's incompleteness is circular: an event with no matching operation is
either a false alarm or a real miss, and that comparison cannot say which.

`spike/fsevents/survey-veto-1.txt` through `-3` are the transcripts, each
produced by the committed `survey.sh`, `judge.py` and `bypass.c`. Every number
below is recomputable from them.

## The planted mutation is invisible to the shim, measured rather than assumed

The sensitivity leg needs a mutation the shim provably does not report. If that
were wrong, a silent capture could not be told from a capture of something the
shim already saw, and the leg would prove nothing in either direction.

`clonefile(2)` is the one used. It creates a file and, at the time of this
survey, was absent from the then-40 symbols `shim/src/macos.zig` interposed. The
table is read but not trusted: the probe runs **under the shim** first, and the
trace is checked.

> **Superseded as a live leg by trace contract v12 (#333, 2026-08-26):** the
> shim now interposes the clone family, so the L7a precondition refuses with its
> own "pick another mutation" message. Every number below was measured under
> v11 and stands as taken, on its date. A re-run needs a mutation the v12 shim
> still cannot see — the mmap/msync class — which is filed with #293.

    trace names:        seen-by-shim.txt, clone-src.txt
    trace never names:  clone-dst.txt

The control matters as much as the absence. A trace missing everything would
"prove" the bypass for the wrong reason, so the leg requires the control file to
be present before the absence is read.

This is also a finding about sideeye rather than about FSEvents: `clonefile`
creates a file in the state directory that the shim never reports. It is the
macOS instance of the class `#244` named on Linux. (Closed by v12: the shim now
records the clone's destination, which is what retired this leg.)

## Sensitivity holds: the veto sees what the account misses

5 of 5 runs in each of the three transcripts, 15 of 15. Each capture names `clone-dst.txt` with two events, against an
account of two paths that does not contain it.

## Containment does not hold on a clean run

Three transcripts, each produced by the committed `survey.sh`, `judge.py` and
`bypass.c`: `survey-veto-1.txt`, `-2`, `-3`. Each is 11 probe modes x 5 runs.

| run | containment held | outside, `link` | outside, other 10 modes |
|---|---|---|---|
| 1 | 49/55 | 5/5 | 1/50 |
| 2 | 47/55 | 5/5 | 3/50 |
| 3 | 49/55 | 5/5 | 1/50 |

Every outside path in all three is the **state directory itself** — an ancestor
of paths the account names. Over the 165 runs the `unrelated` bucket saw
nothing. (`/selftest-only/stranger` appears once per transcript: that is the
judge's own selftest fixture, printed before any measurement. The prefix is
there so a transcript-wide grep for "unrelated" does not need a reader who
remembers which line was which.)

`link` was outside on 15 of the 15 runs it had. The other ten modes were outside
5 times in 150, spread over `mkdir`, `rmdir`, `symlink`, `truncate-same` and
`truncate-shrink`, one each. **Which** modes is not a property worth reading:
the three runs disagree about them, and two earlier sets of runs disagreed with
these.

The instability is the evidence. A low rate spread across modes is what makes
different modes light up as more samples arrive; a property of one mode would
keep selecting that mode. `link` never moved. The reading is:

> Over three runs, `link` was outside on every run it had, the other ten modes
> on 5 of 150, and which modes never do it is not measured.

That is deliberately weaker than "`link` always reports the parent". 15 of 15 is
an observation about 15 runs. This document measured elsewhere that an event
cannot be attributed to an actor, so no mechanism is claimed either — only that
the path reported was the parent directory.

Five runs per mode answers "does this reproduce", not "how often". A behaviour
appearing one run in five is missed entirely by five runs about a third of the
time, so a mode reading 0/5 is not a mode that does not do it.

**5 of 150 is a count, not a rate, and 150 runs does not determine one.** Two
earlier sets of three runs, made while the leg was being built and not committed
here, gave 6 and 23 with the same relation on the same machine. Three sets of
150 runs: **5, 6, 23.** No percentage taken from one of them survives the other
two, and quoting one would make the next reader call another a regression. What
survives all three is `link`, outside on every run it had in each. The rest is
"it happens, and how often is not measured".

The middle set was misread once, which is why this is stated so flatly. A draft
of this section had only two sets, called the first "a quiet stretch" and took
the larger number as the real one. The third set put it back at the bottom of
the range. Two samples were enough to notice that the number moves and not
enough to say which way.

**An earlier and much thinner version of this measurement is worth recording.**
The first containment leg ran one mode, `write`, and reported 5/5 clean. Each
run was 2 operations over **one path**: five repetitions of one path are five
observations of one path, and the repetition bought nothing. `write` is outside
zero times in the three runs above, so that 5/5 was not even a wrong answer
about `write` — it was a true answer whose scope was then read as "containment
holds". The predicate was too thin to be able to fail, and the failure was in
the generalisation rather than in the measurement.

## The two buckets are shapes, not causes

An outside path is reported as an *ancestor of an account path* or as
*unrelated to the account*. Both are facts about strings. Neither is a claim
about what caused the event, and the tempting reading — ancestor means the
relation is stated too tightly, unrelated means a neighbour wrote here — does
not follow: **a neighbour touching the parent directory lands in the ancestor
bucket too.** Attributing an event to an actor is what the section above
measured FSEvents cannot do. That a neighbour writing into the parent directory
would be filed as an ancestor is a property of the classifier, readable from its
two lines of code; it is not measured here, and measuring it would only
re-derive the definition.

The `unrelated` bucket reading zero over the 165 measured runs is the number a working
classifier gives in a directory only the probe uses, and also the number a
classifier that never reaches that branch gives. A second actor is run for that
reason: with the watcher live, `/usr/bin/touch` writes a path the account will
never name. It lands in `unrelated`, and the state directory lands in
`ancestor`, in the same capture. Both branches are reachable, so the zero above
is a measurement.

## Where this leaves #293

Not settled, and not close-able on this evidence.

Containment as stated does not hold on a clean run. Widening the relation to
"an account path or an ancestor of one" would make every measured run pass, and that
is a design decision rather than a measurement: it also excuses a real
neighbour writing into the parent directory, which is precisely the case a veto
exists to catch. The measurement gives both numbers and does not choose.

What is still missing is the thing `#293` asked for and this does not build: a
rate over a corpus. Sensitivity was measured on **one** planted mutation, and
containment in a directory nothing else was using. A busier directory, an
editor, a backup daemon or a second process would each be a path outside the
account, and none of them was present here.

No report vocabulary follows from any of this. Naming a claim weaker than
`oracle_verified` reopens the contract (`#201`, `#202`, `#156`), and nothing
measured here licenses that.
