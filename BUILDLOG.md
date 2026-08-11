# Buildlog

Development journal, newest first. Decisions are recorded when they are made — including the ones that turn out wrong. This file is allowed to be embarrassing in hindsight; that is what it is for.

## 2026-08-11 — The guard's own contract had the hole it was built against

Hours after the guard below merged, review of the practice caught its wording: "write the
entry before opening the PR" *permits batch-writing at delivery* — which is not a lesser
form of compliance but the documented failure mode itself. The containment entry was
written exactly that way, once, at PR-open; its central argument was reversed in review
two hours later; and the reversal never made it back in, because the entry was already
"done". A delivery-time log loses precisely the things that happen after delivery-time.

The contract now says what the journal's own header always said: append at the moment of
the decision, in the same working tree as the change it describes, and **re-read the
entry at PR-open and after every review round** — the reversal window is after writing,
so the re-read is the load-bearing clause. CI cannot see when a line was written, only
whether the file changed; the timing half of the contract lives in `CLAUDE.md` and in the
habit, and this entry is the first one written under it.

## 2026-08-11 — This log stopped being written, and a guard now keeps it written

The last entry written at the time it happened is six entries down, four pull requests ago.
Between it and now: the containment fix merged with its most instructive reversal
unrecorded, a defect that killed observed targets was found and fixed, boundary tolerance
shipped with a contract bump, and v0.2.0 went out — none of it logged. The catch-up entries
below were reconstructed from the session transcripts, the PR bodies, and the git history,
and each states only what was measured at the time.

Why it happened is worth a line: the delivery routine that produced those PRs carried the
CHANGELOG, the ADRs and the PR bodies — artifacts every repository has — and this log is an
artifact only this repository has. Nothing in the routine asked for it, so nothing wrote it.
The fix is structural, not resolutional: CI now fails any pull request that changes
`src/`, `shim/`, `spike/` or the build files without touching `BUILDLOG.md`, and the
repository carries a `CLAUDE.md` stating the contract — the entry is written before the PR
is opened, failures and reversals included. The guard was shown its red once, against a
synthetic diff with no log entry, before being trusted.

## 2026-08-11 — The opened boundary reveals the next wall: a dependency that bypasses libc

With #18 merged, omamori was pointed at again. It travelled: `child_process_detected`
(v0.1.0, nothing explored) → `unsupported_syscall_observed: flock` → after classifying
`flock` as read-only (advisory locks live in the kernel and die with the process, so no
crash world can be told apart by one) → `oracle_missed_operation`. The oracle saw a
state-directory operation the shim did not record.

The missed line is an `openat` of the state directory itself —
`O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY` — issued between taking the audit lock and
reading the secret. omamori's dependency tree includes **rustix**, whose Linux backend
issues raw syscalls; there is no libc entry point for `LD_PRELOAD` to reach. The shim
recorded the libc-reached operations around it faithfully, the oracle compared the two
accounts, and the refusal is exactly what the design promises for a target that bypasses
libc. But it is also categorical in the way the boundary refusal used to be: rustix sits
under a growing slice of the Rust ecosystem, so "a Rust program whose state handling is
partly rustix-backed" is a class, and the whole class is UNKNOWN. Filed as #19.

**The way through was measured before being planned.** The operation the shim missed
cannot change state: a read-only open mutates nothing, so the world killed immediately
before it is byte-identical to the world killed at the next address — a redundant world.
Simulating "read-only opens leave the numbering, on both sides" over the recorded accounts
brought them from divergence at index 3 to within one operation; the residue was the
**close of the raw-opened descriptor**, which the shim never saw born. Tracking fd
provenance dies on `dup` and inheritance, so the simulation instead dropped `close` from
the comparison on both sides — close is neither a kill point nor a mutation, and its only
role was positional corroboration. Result: **142 vs 142, aligned**.

The plan that came out of this — make addressing and the completeness comparison cover
state-changing operations only — went through an adversarial review that caught the
predicate being fail-open: the oracle-side read-only test would have accepted numeric
flags (`0x241`) as read-only. It now requires a symbolic token before excluding anything;
what it cannot parse, it counts, and a miscount is an UNKNOWN, not a pass.

## 2026-08-11 — v0.2.0: the version number was already promised to something else

Releasing the boundary work hit a problem no test catches: **the v0.1.0 release notes had
already promised v0.2 to the Define contract** — `sideeye.toml`, L1 markers, case storage
and `replay`. Published release notes are history and do not get rewritten. The options
were to ship as v0.2.0 anyway and say so, to mislabel it a patch, or to sit on a merged
defect fix (#17 — sideeye was killing the targets it observed) until the promised scope
existed. Holding a shipped fix hostage to milestone naming lost.

v0.2.0 went out with its own notes opening on the change of plan; the PRD now records the
queue-jump and the reason ("roadmaps yield to measurements; that is what they are for"),
moves the Define contract to v0.3 with its scope unchanged, and marks the macOS milestone
absorbed into v0.1 — its one remaining item is #10, the report's silence about *why* an
Apple platform binary shows `no_shim_marker`. Ceremony verified from the outside: fresh
clone of the tag, 53/53 tests, the banner reads `sideeye 0.2.0 (trace contract v3)`, the
planted bug still FAILs at crash point 5 of 5, and a forking target without an oracle
answers `boundary_without_oracle`.

## 2026-08-11 — Boundary tolerance ships: a child is judged by what it did

The tolerance rule designed after the first real-target run is now merged (#18, contract
v3): a fork or spawn boundary is explorable when an oracle is present and **no process
other than the subject touched the state directory**. A child that stays out of the state
directory consumes no sequence numbers, so the numbering that refusal was protecting stays
unique — the safety condition and the honesty condition are the same condition. Everything
else refuses with its own detector: a child that writes (`child_touched_state_dir`, from
either witness), any boundary without an oracle (`boundary_without_oracle` — the shim only
sees processes that load it, and "was not seen" is not "did nothing"), the subject
exec'ing over itself, threads, and anything that leaves the containment group.

**Two design pieces did not survive contact with the implementation.**

The planned arming mechanism — the engine sets `SIDEEYE_PRIMARY_PID` before exec — cannot
work at all under an oracle: the engine's direct child is *strace*, the subject is strace's
child, and the engine never knows its pid at setenv time. A trace-file marker ("whoever
wrote the header is primary") died in thought for a familiar reason: the engine does not
delete the reproduce line's trace file, so the printed command would silently stop arming
on its second run — the exact class of quiet inertness the reproduce line has been fixed
for twice. What shipped is the pid captured at the shim's own `init()`: a forked child
inherits the value but answers `getpid()` differently, and the fork is the only child that
inherits a mid-count `seq`. A spawned child re-inits and arms itself — tolerable, because
the kill fires only on a state-directory operation and a child's state-directory operation
already refuses the run. The arm can only go off in a world that is thrown away.

The second was found by the acceptance suite going red: `TOY_DETACH` — fork a child, child
calls `setsid` — was *explored*. The trace's first boundary record is the tolerable
`.fork`, and the engine's refusal switch read only the first boundary; the `.detached`
that must refuse the run arrived later and was masked. `hard_boundary` is now tracked
separately, pid-aware — a **child's** exec is a spawn doing what spawns do and must not
refuse, while the subject's exec must.

**The witnesses are independent, and a mutation proved it.** Disabling the oracle-side
touch check alone let exactly one case through: the spawned child that receives a clean
environment, never loads the shim, and writes into the state directory — the case only the
oracle can see. The shim-side check survived its own mutation under these toys (for
shim-visible children the oracle is a superset) and is kept anyway, with the reason in a
comment: the oracle reads paths textually and misses a child's *relative* spelling, which
the shim resolves against the child's cwd. Neither witness subsumes the other. Disabling
the no-oracle gate produced the most instructive red: the quiet-fork target explored and
the report printed `processes: single process` — the lie the gate exists to prevent,
verbatim.

Outside review: five P1, two P2, all adopted — a raw `clone(CLONE_THREAD)` walked past the
thread refusal; an unshimmed child's `setsid` is invisible to `%process` (measured; both
are now traced explicitly); oracle-only children skipped the quiescence sampling;
`mmap(PROT_WRITE|MAP_SHARED)` of a state file is a mutation with no later write syscall —
a PASS-side hole that predates this PR for the subject itself; a child's read-only open
was refused against the stated rule. The confirmation round then caught the two remaining
fixes reading flags **from the whole strace line instead of the flags argument** — the
same class as v0.1's `AT_REMOVEDIR` fix, which even left behind a test named for the rule.
Corrected with the argument splitter and pinned by a test in which a file named
`O_CREAT.bak` changes nothing.

53 unit tests, 50 acceptance assertions, 12 distinct detectors. The six tolerance cases
run one binary with one environment variable of difference, so an engine that decides by
anything but the child's behaviour cannot pass them all.

## 2026-08-11 — Observing a vfork killed the target; the fix is a call with no frame

Probing the boundary classifications for the tolerance work found a v0.1.0 defect worse
than any misclassification: **interposing `vfork` kills the target.** A vfork child runs
on the parent's stack while the parent is suspended, and the call returns twice. An
ordinary wrapper's frame spans that double return: the child pops the frame on its way
back into the target, runs, and overwrites the memory it occupied — including the saved
frame pointer and return address the parent's resume path will restore. The parent then
resumed into the *child's* branch and exited 127 with no output and no signal. sideeye
reported `UNKNOWN recording_run_failed` — blaming the target for a death it caused.

The control that placed the fault: vfork+exec of `/bin/true` exits 0 without the shim,
127 with it — **and 127 with the shim loaded but inactive**, recording nothing. The
corruption is the wrapper's stack frame itself, not anything the shim does inside it.
glibc's own `vfork` is hand-written frameless assembly for exactly this reason.

The first fix was removal: stop interposing `vfork` entirely, and let the child's exec and
the oracle carry detection. It worked, and it was the wrong trade — counted only after the
question "can this be broken through?" forced a second look. Removal leaves a
vfork-then-`_exit` child invisible on the platform with no oracle. What shipped instead:
record the boundary first (an ordinary call, safely before the fork), then reach the real
`vfork` through a **guaranteed tail call** — `@call(.always_tail)`, which is a compile
error on any backend that cannot honour it. At the jump the stack is exactly as if the
target had called vfork directly; both returns land in the target and the wrapper's frame
never exists across them. The guarantee promptly fired for real: Zig's self-hosted x86_64
backend (the Debug default) refused with "does not support tail calls", so the shim pins
`use_llvm`. Disassembly on both architectures ends in `br x0` / `jmpq *%rax` after a full
epilogue — a jump, not a call.

Also learned, each the hard way: `posix_spawn` survives an ordinary wrapper because glibc
hands its `CLONE_VM|CLONE_VFORK` child a freshly mmap'd stack, and `fork`'s child runs on
a copy — only `vfork` shares. The toy built to pin the fix committed the same class of
crime it was testing (its argv was constructed *in the vfork child*, on the shared stack;
now static and fully initialised before the fork — found in review). macOS has no
`/bin/true`, only `/usr/bin/true`, and the toy looked green anyway because the parent
discards the child's status — the test was quietly measuring less than it claimed. And one
measurement round was voided entirely by a 0-byte probe binary: the shell executes an
empty file as a successful no-op, so every "exit 0" in that round was the measurement of
nothing. `file(1)` before trusting a binary's exit code.

## 2026-08-11 — The structural argument in the entry below was wrong at the only moment that mattered

The entry below records, with some satisfaction, that the `getpgid` guard was removed
because "a freshly allocated pid cannot equal the id of a live process group". Review of
the containment PR (#14) found the flaw: that argument is true at the moment of `fork` and
**false after the reap**. The first implementation signalled the group *after* `waitpid`;
reaping releases the pid, an unrelated process can be allocated it and become a group
leader, and the `SIGKILL` meant for something that no longer exists lands on a stranger.

The fix is ordering, not another guard: `waitid(P_PID, pid, … WEXITED | WNOWAIT)` waits
for the child to exit while leaving it reapable, so the pid — and with it the group id —
stays spoken for across the signal. Kill, then reap. `WNOWAIT` differs between platforms
(`0x01000000` in glibc's headers, `0x00000020` in the macOS SDK) and was read out of both
rather than recalled; `P_PID` and `WEXITED` agree, and the comment says which is which.
The same-class scan — a wait-family call whose side effect is trusted without checking the
call happened — found one more: `waitpid`'s discarded result left `status` zero on
failure, reading a killed world as a clean exit. Now retried, bounded at 8 because nothing
in that file can tell an interruption from a permanent failure.

Merged with every pre-existing verdict unchanged and both directions measured: the
late-writing grandchild's file appears with the group kill disabled and never appears with
it in place. The suite also grew a guard for its own blind spot — `zig-out` holds one
platform's build, so a host build silently replaces the Linux cross-build and 36 checks
fail for one reason that reads like a tool regression; asked directly, the answer is one
line ("CANNOT RUN … built for this platform?"), confirmed against a wrong-architecture
binary on purpose. Two residues were filed rather than widened into the PR: a descendant
that calls `setsid` escapes the group undetected (#15), and quiescence is signalled, not
observed (#16). Both were closed by the tolerance work later the same day.

## 2026-08-10 — The first real target, and a hazard that was there all along

Pointed sideeye at omamori, the v0.4 dogfood subject. Two attempts, two UNKNOWNs, for two
different correct reasons — and the investigation cost three of my own claims.

**The issue I wrote about this was wrong.** I described omamori as "does its file work,
then execs". Decoding the trace: `posix_spawn` twice, **no `exec` at all**, at records 1–2
of 152, *before* any state work. All 143 kill-point operations happen in the process
sideeye already watches. The refusal was throwing away a complete picture.

**And the reason for the refusal was not what the code says.** The comments frame it as
"v0.1 explores single-process targets". The measured reason is *addressing*: `seq` is a
per-process counter while a crash point has to be a globally unique address. `fork` makes
parent and child both number their operations 3 and 4; `exec` resets to 1 and collides with
the parent's early numbers. `SIDEEYE_KILL_AT=3` names two operations, so it names none.

Two adversarial review rounds then broke two premises of the design I wrote for this.

**`runChild` waits for the direct child only.** Everything the target spawns outlives it.
After the subject is killed at crash point k, a grandchild keeps running while the engine
snapshots, restores for the next world, and runs the checker — so the "crashed state" is
whatever happened to be on disk when the engine looked. This is not a new hazard introduced
by tolerating children; **it is present today**, hidden only because such targets are
refused before any world is explored. The recording run still had it.

Confirmed both directions before believing it: a toy whose child sleeps 300 ms and then
writes `late.txt` produces that file with the group kill disabled, and never produces it
with the group kill in place.

**The guard I planned for it turned out to be unnecessary.** The plan said to confirm
`getpgid(child) == child` before signalling, because a failed `setpgid` would leave the
group id equal to the engine's own and `kill(-pgid)` would kill the engine. That cannot
happen: the id being signalled is the child's freshly allocated pid, and POSIX keeps a pid
out of circulation while it is in use as a group id, so it can never be the engine's group.
Removed the check and wrote down the argument instead. A structural reason beats a guard,
and it is one fewer thing that has to stay true.

**The second review found the acceptance condition itself was non-deterministic.** The
design had each child announce itself, and read "no announcement" as "unobserved". A child
killed by the group kill before it announces leaves no announcement, so the same target
would produce different verdicts on different runs. For a tool whose product is
determinism, that is worse than a wrong answer. It also conflates "died before doing
anything" with "ran unobserved" — the confusion this project exists to avoid, one level
down. Replaced by letting the oracle decide, which removed the announcement marker, the
race and the ambiguity together. **The design after two rounds of attack is smaller than
the one before.**

One measurement worth keeping: **the oracle changes the timing of the recording run.**
`strace -f` does not exit until its tracees do, so the same stray child makes the recording
run take 310 ms and its write lands inside the measured window. The recording run and an
explored world are therefore not timing-equivalent. The containment check deliberately runs
without an oracle for that reason — otherwise it would be measuring strace.

## 2026-08-10 — v0.1.0: four documentation gaps, one real defect, and a tag verified from the outside

Release preparation was mostly reading the documents as a stranger would, and the stranger
kept winning. **The PRD contradicted itself**: v0.1 listed `sideeye replay <case>` while
v0.2 listed the case storage a replay would need — a case that was never stored cannot be
replayed, so `replay` moved to v0.2 whole. **DESIGN §12's L0 was wrong as written**: "the
state directory must equal the pre or post snapshot" fails the *corrected* toy, whose
atomic write leaves `key.json.tmp` behind in every world killed inside the window; the
text now matches the implementation (per file, over files present in both snapshots) and
names what the narrower form does not catch. **Two version strings had already drifted**
(`0.1.0` in the manifest, `0.1.0-dev` printed) — a tag would have disagreed with the
binary it tagged; a test now embeds the manifest and holds them together. **And the README
showed a command that does not exist** — the report ended in a mocked
`sideeye replay 000042`; replaced with real output, and the `check.sh` beside it was
executed before being pasted.

**The defect was found while generating that README example, not by review.** A checker
that rejects the operation's normal output produced `FAIL 6 of 6 crash worlds violated an
invariant` — but one of those six is the baseline world, which was never killed. Nothing
that fails there is a consequence of crashing, and attributing it to a crash is the exact
misattribution this tool exists to refuse. It is now `UNKNOWN baseline_violates_invariant`,
paired in acceptance with a control: the same checker, correctly configured, must still
find the planted bug at crash point 5, so the gate cannot be satisfied by swallowing every
L2 finding.

The same-class scan (claims a document makes that the implementation does not support)
walked the CHANGELOG's feature list and found the third structural detector,
`contract_version_mismatch`, had no test and had never been seen firing — the precise
thing PRD says a gate must not be. Unit test with control added, confirmed by making the
decoder ignore the version field.

Tagged `v0.1.0`, released as "v0.1.0 — Deterministic crash points, and a refusal to
guess", and verified from the outside: fresh clone of the tag, build, 45/45 tests, the
buggy toy found at crash point 5 of 5, text and JSON agreeing. The project image landed
separately (640×640, metadata stripped) after declining both social-preview variants.
Two claims measured for the release but *not* asserted by the suite are recorded as such:
ten runs produced an identical crash point and window (the suite compares three), and two
recording runs' traces were byte-identical at 1129 bytes (the suite does not compare
traces at all).

## 2026-08-10 — Second review: the fix that was never run, and the scan that stopped one function short

A second review of the fix branch found fifteen more defects. Three of them are worth
recording because of *how* they survived, not what they were.

**The `reproduce` line still did not reproduce.** The previous entry says it was fixed
and verified by running it. It was neither. The line had been missing
`SIDEEYE_STATE_DIR`; adding that left `SIDEEYE_TRACE_PATH` missing, and the shim returns
from `init()` before arming itself when it has nowhere to write — so the printed command
runs to completion, changes nothing, and looks like an ordinary successful run. The
"verification" was done in a shell that still had those variables exported from an
earlier experiment. **An environment that has been used for experiments is not a place
to check whether a command carries its own environment.** Both the acceptance suite and
the macOS CI job now execute the printed line with `env -i`.

That mistake repeated inside this session. A local check of the same line reported
failure, and the cause was the check: it rebuilt the state in a *different* directory
from the one the report names in `SIDEEYE_STATE_DIR`, so every operation fell outside
what the shim watches. Two probes in a row measured a path that did not reach the thing
under test.

**The same-class scan stopped at the two functions the finding named.** `restore` and
`deleteTree` were fixed for silently ignoring failed writes. `corruptState`, twenty lines
away in the same file, does the same thing for the same reason and was not looked at —
and its failure mode is worse than the others: an uncorrupted state is one the checker is
*right* to accept, so the run reports `checker_not_falsified`, blaming the caller's
checker for the engine's own failed write. A scan driven by the finding's file list is
not a scan of the class.

**Two variables that had to agree, disagreeing.** The text report read a local
`checker_note`; the JSON read a global copied from it on the success path only. An
UNKNOWN therefore printed `unknown_reason: checker_not_falsified` beside
`checker: none configured` — the report contradicting itself about whether a checker
existed. Fixed by deleting one of each pair rather than by copying at the two sites where
it showed.

**A limit fixed in the wrong direction.** The previous round turned a silent truncation
at 256 directory entries into a hard error. That removed the silence and introduced a
worse limit: any state directory with more than 256 entries became unexplorable, reported
as a setup error that named nothing. Deleting in passes removes the bound entirely. A
directory of 301 entries is now in the acceptance suite, because the suite's own state
directories hold one file and would never have noticed.

**The check found a third defect in the same line.** Running the printed command in CI —
the step added by this round — failed on macOS with exit 0 and an untouched state
directory. Not a flaw in the check: `/tmp` is a symlink to `/private/tmp`, the engine
resolves `--state` and the shim filters on the resolved spelling, and a target told the
unresolved one passes *that* to `unlink` and `rename`. Only descriptor-based operations
matched, so no crash point 5 existed to die before. Exploration never showed it because
the engine hands the target the resolved path through the environment; the reproduce line
cannot, because there the target finds its state its own way. The shim now accepts either
spelling and records one, and Linux grows an explicit symlink to reach the same case.

Half of that new check does not discriminate: the "same crash point" assertion stays
green with the fix reverted, for the same reason the defect hid — the toy is handed the
resolved path. Labelled as a baseline rather than left looking like proof.

**And the check killed the suite.** Written with a `set +e` … `set -e` pair around a
command whose failure is expected — a habit from the CI steps, which do start with
`set -eu`. The acceptance suite does not; it runs under `set -u` alone. So the
"restoring" `set -e` switched errexit *on* from that line, and the very next check runs
the buggy toy, where sideeye correctly exits 1. The script ended there. What it printed
was its last *passing* line, followed by nothing, with exit status 1 — indistinguishable
at a glance from an ordinary failing run, and the missing summary was the only clue.

Six increasingly desperate theories went by before measuring: environment leakage (no),
a broken stdout (no), the shim loaded into the shell (no). `strace -f -e trace=%process`
answered it in one run — the shell reaped sideeye's expected exit 1 and immediately called
`exit_group(1)`. The suite now carries an EXIT trap that says so when it stops without
reaching a verdict, confirmed by injecting an early exit.

The shim also gained its first unit tests. It had none, which is backwards for the half
that runs inside somebody else's process, and every defect found in it so far produced a
plausible value rather than an error. Both new tests were confirmed by mutation.

Two smaller notes. The review recommended replacing the hand-written JSON escaper with
`std.json.Stringify.encodeJsonString`; that was checked against the pinned standard
library and is wrong — its default options pass bytes ≥ 0x80 through unchanged, the same
defect, and `escape_unicode` decodes them with `catch unreachable`, so invalid UTF-8 is a
panic instead of a bad document. And the new gate for a non-executable oracle appeared not
to fire inside the container: the same 0644 file on a real filesystem is refused, but
`access(X_OK)` over the Docker bind mount answers permissively. The gate is right; the
mount reports something the filesystem does not.

## 2026-08-10 — Review after merge: four ways to reach PASS, and the report the caller reads

A code review run against the merged branch found fifteen defects. Four of them reached
PASS, which is the failure this project is built to prevent, so they are worth naming.

**The recording run's exit status was discarded.** An operation that failed immediately —
bad argument, missing input, EACCES — still wrote its `shim_ready` marker, recorded no
operations, changed nothing, and every structural detector stayed quiet. The run reported
`PASS  the operation performed no state-directory operations`, exit 0. A partial failure
was worse: five operations become two, and the exploration is confidently complete over a
sequence the target never finishes. `--setup`'s exit code was checked; the operation's,
which the entire trace depends on, was thrown away.

**The state directory was resolved before it existed.** `realpath` failed and the code
fell back to the argument as written. On macOS `/tmp` is a symlink to `/private/tmp`, so
the engine filtered on one spelling while the shim — asking the descriptor via
`F_GETPATH` — saw the other. Every operation fell outside the state directory. The oracle
could not save it, because it was handed the same wrong string and also found nothing:
two views agreeing on nothing is indistinguishable from two views agreeing.

**`deleteTree` stopped silently at 256 entries.** `restore` then wrote the snapshot over
whatever remained and returned success, so every world after the first started
contaminated. An L2 checker would report a violation at crash point k that was residue
from k-1.

**The oracle reported agreement over zero examined lines.** `acceptance.sh` asserts by
hand that more than ten lines were scanned; the tool shipped without the check its own
suite considered necessary.

Also fixed: `AT_REMOVEDIR` was the Linux constant on both platforms, so macOS recorded
`.unlink` where Linux recorded `.rmdir` — the parity claim in the README, the CHANGELOG
and the CI job name was false for any target removing a directory, while the two lines
of context around it *were* platform-branched. And the oracle mapped `unlinkat` to
`.unlink` by name alone, which disagrees with the shim on aarch64 Linux, where glibc
implements `rmdir(3)` as `unlinkat(AT_REMOVEDIR)`: a correct target would have been
reported UNKNOWN.

### The two acceptance conditions that were never checked

PRD's v0.1 acceptance asks for every verdict path to be falsified once — "a gate whose
failure paths were never seen firing is not a gate". UNKNOWN had seven detectors behind
it. **SETUP ERROR had none**, and neither did the new recording-run check. Both now do,
and the second went from red to green when the fix landed, which is the only way to know
a check pins anything.

### JSON report

DESIGN §13 asks for both forms carrying identical content. The acceptance check reads the
fields a caller would branch on and compares them against the text report, rather than
inspecting the document by eye — a report that looks right and does not parse is worse
than no report. UNKNOWN reaches it too, which took wiring, because that verdict exits from
deep inside the run rather than at the end, and it is the one a CI caller is most likely
to be branching on.

Written by hand rather than generated from a type: the schema is explicitly experimental
until v1.0, and generating it would imply a stability this release does not offer.

## 2026-08-10 — CI, green on both platforms, first run

```
linux: success    37/37 tests, ALL ACCEPTANCE CHECKS PASSED
macos: success    37/37 tests, crash point 5 of 5, explored 6 worlds
```

The Linux job runs on **x86_64**, and everything before this had been arm64 — Docker on
an Apple Silicon host, and the host itself. So this is the first evidence that the
verdict holds across architectures as well as across operating systems. The libc symbol
variants that differ between architectures were the specific risk the plan named there.

Two decisions in the workflow are worth keeping:

**Parity is asserted, not described.** The macOS job greps for `crash point 5 of 5` and
`explored 6 worlds`. A sentence in the README claiming parity would have said the same
thing while `fcntl` was quietly making macOS count three operations instead of five;
the numbers would have caught it.

**macOS asserts FAIL, not PASS.** There is no oracle on that platform, so the only claim
it can support is that a real counterexample is found. "No counterexample" needs a
completeness check that SIP makes unavailable, and making PASS the pass condition would
have quietly weakened what green means. The job also checks the report labels the weaker
claim (`NOT VERIFIED`) so that the two kinds of PASS stay distinguishable.

## 2026-08-10 — Same-class scan for the remaining variadic declarations

Three occurrences of one mistake is enough to stop fixing them individually. Every
`extern "c" fn` in the tree, plus every `@extern` in `darwin_libc.zig`, checked against
whether C declares that function variadic.

**23 `extern "c" fn` declarations, 25 `@extern` entries, 48 total. Two are variadic in
C — `open` and `fcntl` — and both are now declared that way. No further instances.**

The ones worth naming as deliberately *not* variadic, since they look similar:
`creat(path, mode)`, `mkdir(path, mode)` and `execvp(file, argv)` are all fixed-arity in
POSIX. (`execl` and friends are the variadic members of that family and are not used
here.) `openat` appears only in the shim, already variadic; the engine never calls it.

A count is recorded rather than "none found", because a scan that examined nothing
produces the same sentence.

## 2026-08-10 — Parity: both operating systems land on the same crash point

`fcntl` was the third instance of the same mistake. Declared with a fixed third
argument, `F_GETPATH` never received its buffer on arm64, so every fd-based operation —
`write`, `fsync`, `close` — failed to resolve a path and was dropped. That is why macOS
counted three operations where Linux counted five, and nothing anywhere reported an
error.

With it declared variadic:

```
                         Linux            macOS
FAIL                     1 of 6           1 of 6
earliest crash point     5 of 5           5 of 5
                         after  unlink(state/key.json)
                         before rename(state/key.json.tmp)
explored                 6 worlds (5 + 1 baseline)
```

**Two entirely different interposition mechanisms — `LD_PRELOAD` with `dlsym` on one
side, a `__DATA,__interpose` table on the other — landed on the same logical crash
point.** That is what acceptance check 3 was written to demand, and it is not something
reusing one implementation could produce.

### The same mistake, three times

`open` in the shim, `open` in the engine, `fcntl` in the shim. Each fixed one changed
the symptom rather than removing it, which is what kept sending the investigation
somewhere new:

| declaration fixed | symptom before | symptom after |
|---|---|---|
| shim `open` | files created mode 0 | files created mode 0251 |
| engine `open` | snapshot fails, looks like shim | works; N=3 against Linux's 5 |
| shim `fcntl` | fd-based ops silently absent | N=5, parity |

Fixed-arity declarations of variadic C functions are correct on Linux and wrong on
arm64 macOS, and wrong in the specific way that produces plausible values rather than
errors. Any remaining one in this codebase is a latent version of this bug; the three
here were found by symptom, not by search. **That search is worth doing once,
deliberately.**

## 2026-08-10 — macOS finds the bug. The defect was in the engine all along.

Inverting the approach found it in one step. Instrumenting the shim showed `mode` read
as `0x1a4` and forwarded as `0x1a4`, and the file landing `-rw-r--r--`. **The shim was
correct.** What was wrong was `src/posix.zig`: the engine's own `open` declaration was
fixed-arity, so every file `restore()` wrote lost its mode — and since the engine then
could not read back what it had just written, the symptom appeared during a snapshot and
looked like the shim's doing.

Five rounds were spent examining the component that was not at fault, because the first
symptom appeared under injection and "macOS interposition is the new thing here" was too
easy an assumption. The engine runs without the shim; it was never a suspect. Calling a
variadic function correctly needs no `@cVaStart` — only receiving does — so the fix is
one declaration and a few literal casts.

macOS now produces the finding:

```
FAIL  1 of 4 crash worlds violated an invariant
invariant   built-in atomicity (L0)
earliest    crash point 3 of 3
            after  unlink(.../state/key.json)
            before rename(.../state/key.json.tmp)
explored    4 worlds (crash points 3 + 1 baseline)
```

Same bug, same logical crash point, second platform.

**But N is 3 here and 5 on Linux.** The shim is not seeing `write` and `fsync` on
Darwin — most likely the `$NOCANCEL` symbol variants, which are their own entry points.
So detection works while observation is incomplete, which is precisely the situation the
completeness rule was written for: this run is only allowed to report FAIL, and it did.
A PASS would have required `--allow-unverified`, and would have carried the label.

Fixing the missing variants is the next macOS task. Linux is unaffected: 37 tests and
the acceptance suite green.

## 2026-08-10 — Where the macOS investigation stands

Four candidate explanations tested against a probe that is walked step by step toward
the shim. Each addition kept `mode` at 0o644 and the file at `-rw-r--r--`:

| added to the probe | result |
|---|---|
| nothing (one interposer, immediate forward) | correct |
| a call between reading and forwarding (`getcwd`, as `note1` does) | correct |
| forwarding through an inline wrapper | correct |
| interposing `openat` alongside `open` | correct — and `openat` never fired, so macOS's `open` does not route through it |

So the defect is not in variadic passing, not in doing work between the two calls, not
in the wrapper, and not in `open`/`openat` interacting. What is left is the remaining
distance between a two-symbol probe and a twenty-five-symbol shim.

**The approach should invert here.** Building the probe up has cost four rounds and
removed four hypotheses without arriving. Taking the shim apart — instrument it directly,
print `mode` where it is read and again where it is forwarded, then remove interposers
until the corruption stops — starts from the artefact that actually misbehaves. The
probe has served its purpose: it established that every mechanism the shim relies on is
sound in isolation, which is why the answer must be in the composition.

Linux is unaffected by all of this and stays green throughout.

## 2026-08-10 — Narrowing: the work done between the two calls is not the problem either

Second step of walking the probe toward the shim. The shim does something between
reading `mode` and forwarding it — `note1`, which resolves the path and therefore calls
`getcwd`. Adding exactly that to the probe:

```
flags=0x00000601
 recv=0x000001a4        still 0o644
                        file lands -rw-r--r--
```

So a call sitting between `@cVaArg` and the forward does not disturb the argument. Two
differences remain between the probe and the shim:

- the shim forwards through an inline wrapper (`common.callOpen`) rather than calling
  the extern directly, and the replacement is reached via a `pub const` alias of a
  function inside a comptime-selected struct;
- the shim installs twenty-five interposers, not one.

Both are testable the same way, one at a time. The pattern of this whole investigation
has been that each measurement removes a plausible explanation, and the plausible ones
are the dangerous ones: promotion and rebinding were both "fixable", and fixing either
would have hidden the defect rather than removed it.

## 2026-08-10 — Variadic passing is not the problem: measured, at last

The probe that earlier panicked before reaching its measurement now runs, because it no
longer depends on a constructor. It reports what the replacement receives:

```
flags=0x00000601      O_WRONLY | O_CREAT | O_TRUNC
 recv=0x000001a4      0o644
```

and the file lands as `-rw-r--r--`.

So variadic passing works. `@cVaStart` and `@cVaArg` read what the caller pushed, and
forwarding through an `@extern` pointer preserves it. Three hypotheses have now been
eliminated in order — dyld rebinding the stored original, argument promotion, and
initialisation order (that one was real and is fixed) — and the remaining defect is
specific to how the shim itself is assembled, not to the platform's calling convention.

That is a much smaller search space than "macOS is different", which is where this
started. The next step is to narrow from the probe toward the shim: the probe replaces
one symbol and calls the original immediately; the shim replaces twenty-five, runs
`note1` in between, and routes through an inline wrapper. Whatever the difference is, it
lives in that gap.

Worth noting how little of this could have been reasoned out. Every step that moved the
investigation forward was a measurement, and two of the three discarded hypotheses were
plausible enough to have been "fixed" — which would have left the real defect in place
under a layer of unnecessary changes.

## 2026-08-10 — The pointer table is gone from the macOS path; one defect remains

The `real` table now exists only where it is needed. It was always a Linux construct —
somewhere to keep what `dlsym(RTLD_NEXT)` returns — and on macOS it introduced a
dependency on initialisation order that the platform does not honour. The replacements
reach the original through `common.call*` wrappers, which go through the table on Linux
and call `darwin_libc.zig` directly on macOS. `bindReal` and the constructor's part in
this are gone.

The wrappers are also what the trace writer uses, so writing a record no longer depends
on the table being populated either.

The failure moved: the run used to die snapshotting the *final* state, and now dies
snapshotting a *crashed* state. The recording run completes, which it never did before.

**Files are still created with mode `--w-r-x---`.** So something remains wrong with how
`mode` crosses the boundary — 0o644 going in, 0o251 landing on disk, and those two share
no obvious relationship (not a shift, not a mask, not umask). It needs the measurement
the last probe never reached: print the value as received inside the replacement, and
again as passed to the original. Guessing at promotions has already cost one wrong
hypothesis.

Linux remains unaffected throughout: 37 tests and the acceptance suite green after every
one of these changes.

## 2026-08-10 — The macOS failure is an initialisation-order problem, not an ABI one

Both hypotheses from the previous entry were wrong, and finding that out took a probe
that separated receiving from forwarding: print the `mode` as received, and compare the
stored "original" pointer against the replacement.

The probe never got that far. It panicked on `real_open.?` — **null** — with a stack
coming from `libxpc.dylib`.

**Interposition takes effect the moment the library is loaded. The constructor that
fills the pointer table runs much later.** Between those two points, system libraries
are already calling `open`, and every one of those calls reached a replacement whose
"original" was still null. `ops.zig` dutifully returned `missing()` — that is, `-1` —
for each of them.

That explains everything that looked like an ABI defect: files created with nonsense
permissions, a state directory the engine could not read, a `mode` that seemed to be
"something, but not what was passed". None of it was about argument passing.

Linux does not show this because `.init_array` runs early enough that the shim is ready
before anything interesting happens. `__DATA,__mod_init_func` does not offer the same
guarantee, and the difference is invisible until a system library gets there first.

### What it means for the design

The `real` table is a Linux construct: it exists because `dlsym(RTLD_NEXT)` has to be
called from somewhere. macOS never needed it — the original is directly callable — and
routing through a stored pointer introduced a dependency on initialisation order that
the platform does not honour.

So on macOS the replacements should call the `extern` declarations directly, with no
table and no constructor in the path. That touches all twenty-six entry points, so it
is the next piece of work rather than a patch squeezed in here.

Worth recording that the earlier standalone probe — the one that proved interposition
works at all — did not catch this. It called `open` directly from the replacement,
which is exactly the shape that turns out to be correct, and so it sailed past the
problem the real shim would hit. A probe that validates a mechanism does not validate
the way the mechanism is used.

## 2026-08-10 — Variadic handling: correct per platform, still not correct enough

`@cVaStart` / `@cVaArg` work in Zig 0.16 — confirmed with a round-trip before touching
the shim — but only on some targets. For `aarch64-linux` the compiler refuses outright:
*"disabled due to miscompilations"*. Which is itself informative: the fixed-arity form
that has been working on Linux is the form Zig trusts there.

So `open` and `openat` now use whichever declaration is correct for the target — variadic
on macOS, fixed on Linux — selected at comptime, with the bodies otherwise identical.
Both build. Linux is unaffected: 37 tests and the full acceptance suite still green.

**macOS still gets `mode` wrong**, differently than before: files now come out `--w-r-x---`
rather than `----------`. Something is being read, and it is not what was passed. Two
candidates, neither confirmed:

- `@cVaArg(&ap, c_uint)` may not match how the argument was promoted, though `mode_t`
  promoting to `int` is what C promises here.
- `common.real.open` holds a function *pointer*, and dyld's interposition rewrites
  pointers in `__DATA`. The original may be getting rebound to the replacement — the
  early standalone probe did not recurse, but it also did not route through a stored
  pointer.

The second explanation would mean the whole `real`-table design needs a different shape
on macOS, so it is worth resolving properly rather than guessing. Recorded here rather
than left as a puzzle for whoever looks next.

## 2026-08-10 — The macOS shim builds, runs, and gets the mode argument wrong

The structure is in place: replacement functions live in one file (`ops.zig`) with
identical bodies on both platforms, and only the installation differs — `linux.zig`
exports the symbols for `LD_PRELOAD`, `macos.zig` lists them in a `__DATA,__interpose`
table and fills `common.real` from `extern` declarations. The constructor section
switches between `.init_array` and `__DATA,__mod_init_func`; `fdPath` switches between
`/proc/self/fd` and `fcntl(F_GETPATH)`; the engine switches between `LD_PRELOAD` and
`DYLD_INSERT_LIBRARIES`. It builds, injects, and the target completes.

Then the engine failed to snapshot the state, and the reason turned out to be the whole
point of testing on the second platform.

**Every file created under the shim had mode `----------`.** Not a crash, not an error
return — the files existed, held the right bytes, and were unreadable. `open` is a
variadic function, and on arm64 macOS variadic arguments are passed **on the stack**,
while the fixed-arity declaration used here passes them **in registers**. So the third
argument was read from a register the caller never wrote, and `mode` came out zero.
Both directions are affected: the target's `mode` never reaches the replacement, and
the replacement's `mode` never reaches the real `open`.

The same code is correct on Linux, where variadic arguments do go in registers. This is
the class of defect that only appears when the second platform arrives, and the reason
the plan put macOS inside v0.1 rather than after it. Discovering it in v0.3 would have
meant discovering it on top of a codebase built around the wrong assumption.

The fix is real variadic handling — `@cVaStart` / `@cVaArg` in the replacements, and
variadic function-pointer types for the originals — which touches every `open`-family
entry point. Left for the next pass rather than rushed. Linux is unaffected: the full
acceptance suite is still green with seven distinct detectors.

Also corrected while here: `O_CREAT`, `O_APPEND` and `O_CLOEXEC` had Linux's values
compiled into the shim unconditionally. On Darwin those constants differ, and the
failure mode would have been a trace file opened with the wrong semantics — records
missing rather than a bad flag reported.

## 2026-08-10 — macOS, measured: interposition works, the oracle does not

Two things the plan said would be decided by running them rather than by reading about
them. Both are now decided.

**`__DATA,__interpose` works from Zig.** A minimal library exporting one replacement for
`open` gets it called, and the control run without injection does not. Two details:
`@intFromPtr` cannot be evaluated at comptime for a function address, so the table holds
`@ptrCast` pointers; and calling `open` from inside the replacement does **not** recurse.
Same-image calls are not interposed, which means macOS needs no `dlsym(RTLD_NEXT)` dance
at all — the original is simply callable.

`fcntl(fd, F_GETPATH, buf)` supplies what `/proc/self/fd` supplies on Linux, including
the same symlink resolution (`/etc/hosts` comes back as `/private/etc/hosts`).

**`dtruss` is not usable.** SIP is enabled and DTrace refuses: *"DTrace requires
additional privileges"*. `sudo dtruss` may work, but a tool that demands sudo to reach
its own correctness check is not a tool anyone will run in CI. The alternatives —
Endpoint Security and friends — need an entitlement a freely distributed binary cannot
carry. The plan predicted this and built the structural detectors so they would not
depend on an oracle; that decision is now load-bearing rather than precautionary.

### The consequence, and the shape of the answer

Requiring an oracle for PASS — the fix from the first review — would mean **macOS never
produces a PASS at all**. FAIL would still work, so the tool would report bugs and never
report their absence. That is not a usable half.

Branching on the platform was the obvious repair and the wrong one: the whole point of
acceptance check 3 is that the same scenario yields the same verdict on both operating
systems, and a rule that only applies to one of them destroys the comparison.

`--allow-unverified` instead. The caller states the weaker claim deliberately, and the
report carries it:

```
oracle: NOT VERIFIED (--allow-unverified) — nothing checked what the shim reported
```

Two PASSes are now distinguishable by reading them, which is the property that matters.
FAIL is untouched by the flag — a counterexample sitting in front of you does not become
less real because the account of the run was incomplete — and that is asserted rather
than assumed.

Still to build: the macOS shim itself. The mechanism is proven; what remains is the
symbol table and the `F_GETPATH` path resolution.

## 2026-08-10 — L2: the checker, and the requirement that it be shown to work

The domain checker runs after each crash, in a fresh process, and its exit code is the
verdict. On the buggy toy the report now reads:

```
invariant   built-in atomicity, and the checker
earliest    crash point 5 of 5
            after  unlink(/tmp/l2/state/key.json)
            before rename(/tmp/l2/state/key.json.tmp)
checker     falsified before the run (corrupted state -> check failed)
```

with `doctor says 'healthy' but the key is unloadable` on stderr. That is DESIGN §13's
worked example arriving on its own — the diagnostic contradicting reality, in the world
where the key is briefly absent. Both invariants fail in the same world, which is what
they should do when they are describing the same bug from different angles.

**Falsification runs first, and refuses to proceed without it** (DESIGN §14-13). A
checker that cannot tell a corrupted state from a healthy one will call every world
fine, and a PASS built on that is a statement about nothing. `/bin/true` as a checker
is the purest case and is now an acceptance check: it must produce UNKNOWN.

The way the state gets corrupted for that probe took a correction. Emptying the
directory is the obvious method and it is wrong here: `check.sh` compares a diagnostic
against reality, and an empty state is perfectly *consistent* — the diagnostic says
unhealthy, nothing loads, they agree. The probe overwrites each file's contents instead,
keeping the structure. Breaking the agreement is the point, not removing the subject.

**Configuration is `--check <cmd>`, not `sideeye.toml`.** The plan called for the file;
Zig has no toml parser and hand-writing one does not advance the spike. What L2 actually
has to demonstrate — a fresh process after restart, an exit code as the verdict, and the
falsification gate — is fully exercised through the flag. The three-commands-and-a-
directory contract of DESIGN §12 is a v0.2 concern.

Seven distinct detectors now fire across the acceptance suite.

## 2026-08-10 — First outside review: three ways to reach PASS while blind

An adversarial review of the whole branch found six real defects, three of them capable
of producing PASS on a target that had not been fully observed. That is the specific
failure this project exists to avoid, so they are worth recording individually.

**PASS was reachable without any completeness check.** `--oracle` was optional and its
absence only produced a line in the report. The reviewer pointed out the case the toys
did not cover: a target that performs *one* ordinary libc operation and then bypasses
libc for the rest. Something was mutated, so `state_changed_without_ops` stays quiet;
the trace is short but not empty, so nothing looks wrong. Every toy so far was either
entirely visible or entirely invisible, and the gap between those was invisible too.
`spike/toys/toy_mixed.c` now occupies it. PASS requires an oracle; FAIL does not,
because a counterexample is real whether or not the account of it was complete.

**The oracle could not see a raw `clone`.** It was invoked with
`-e trace=%file,%desc` and no `-f`, so process creation was outside its view — the same
blind spot the shim documents for itself. A child touching the state directory while
the parent performs ordinary operations passed everything. Now `-f` and `%process`,
with the check placed *before* the state-directory filter, since the child's work never
mentions the directory in the parent's account.

**`restore()` could delete outside the state directory.** It asked `isDirPath`, which
calls `opendir` and therefore follows symlinks; a link inside the state directory
pointing anywhere else would have had its target's contents deleted, once per explored
world. `assertSafeRoot` never had a chance — it only inspects the root string.
Deletion now decides from `dirent.type`, which has not followed anything yet.

Three smaller ones: a truncated trace was parsed as far as it went and then judged; an
operation whose path could not be resolved was dropped silently (`unresolvable_path`
existed as a value and was never produced); and the acceptance suite ran without an
oracle, so none of the above was pinned.

### Two regressions the fixes introduced, both found by running them

Fixing the oracle's blind spot broke the oracle twice, and neither showed up as an
error — both produced confident wrong answers.

`strace -f -o file` prefixes lines with `13    `, not `[pid 13]`. Only the bracketed
form was handled, so every line failed to yield a syscall name, the oracle's view came
back empty, and it reported that the *shim* had invented operations. And strace's own
`execve` of the target was counted as the target creating a child process, so every run
returned `child_process_detected` — the measuring apparatus flagging the act of
measuring.

Both were caught by running the acceptance suite, not by reading the diff. The first
one is a good illustration of why: the code looked right, the tests for it passed, and
the format it parsed was one that documentation and memory both agree exists.

### Where this leaves the boundary

`spike/acceptance.sh` is green with **six distinct detectors** firing across the
out-of-bounds cases, up from four. Two of them cover the same target from different
sides on purpose: `toy-raw` is caught by the oracle when one is available, and by
`state_changed_without_ops` when it is not. macOS is expected to have no usable oracle,
so the second path has to work alone, and now that is asserted rather than assumed.

## 2026-08-10 — Spike-2: the oracle agrees, and disagrees where it should

The completeness comparison is in. The recording run goes through
`strace -y -e trace=%file,%desc`, its output is normalised to the same `OpClass` the
shim records, and the two class sequences are compared position by position.

On the supported toy:

```
oracle      agreed on 6 operations (61 syscall lines examined, 9 touching the state directory)
```

The scan size is in the report on purpose. "Agreed" over zero examined lines reads
exactly like agreement, and there is no way to tell them apart afterwards.

On `toy-raw` the oracle names what was missed and the run ends UNKNOWN. That target is
already caught by `state_changed_without_ops` without any oracle, so running it *with*
one is how the oracle path itself gets exercised rather than assumed — otherwise the
comparison code would sit there having never fired.

Details worth keeping:

- **strace must not have the shim loaded.** Environment reaches the target through
  strace's `-E`, not through the engine's own `setenv`: `LD_PRELOAD` set on the engine
  side would load the shim into strace, and strace's own file operations would land in
  the trace as if the target had produced them.
- **Read-only syscalls are excluded by name** (`newfstatat`, `read`, `access`, …). They
  cannot be crash points in any meaningful sense, and counting them would make the two
  views disagree for no reason. The exclusion is a fixed list, so a syscall that is
  neither modelled nor listed becomes `unsupported_syscall_observed` — UNKNOWN, not a
  silent skip.
- **The oracle comparison runs before the structural detectors**, because when both can
  catch something the oracle can say *which* operation was missed.
- The oracle's two verdicts got their own reasons (`oracle_missed_operation`,
  `oracle_saw_phantom`) rather than reusing `state_changed_without_ops`. Sharing a name
  would have defeated the acceptance check that requires distinct detectors to fire —
  the check would have passed while proving less.

`spike/acceptance.sh` now covers all of it and is green end to end. What remains for
v0.1: the L2 checker, macOS, the JSON report, and CI.

## 2026-08-10 — The engine judges, and the internal gate is passed

All three v0.1 acceptance checks now run for real, in the container, from
`spike/acceptance.sh`:

```
toy-bug   FAIL  crash point 5 of 5, after unlink(...key.json), before rename(...tmp)
toy-fixed PASS  explored (5) == N (4) + 1
toy-raw / toy-static / fork / thread   all exit 2, four *different* detectors
determinism                            3/3 identical reports
```

The distinctness of the four reasons is the part worth keeping honest about: an
implementation that always answers UNKNOWN passes check 2 on its own, and one that
decides everything from `ldd` gives the same reason four times. Requiring four
different detector names makes both of those visible.

### The engine does not use std.Io

`std.fs` no longer holds `File` or `Dir` in 0.16; spawning a child goes through an
`Io` vtable; `std.process.argsAlloc` is gone. Meanwhile everything the engine needs is
plain POSIX — walk a directory, read a file, fork, exec, wait — and the shim had
already shown that `extern "c"` works fine. So `src/posix.zig` binds libc directly and
the engine sits on that. ADR 0001's retreat condition ("two blocks from standard
library churn moves the engine to Rust") is much less likely to be reached now, because
the churning layer is not in the path.

`std.c.Stat` turned out not to describe Linux's `struct stat` usably here, so entry
kinds come from `dirent.type` instead — same information, no extra syscall, defined
identically on both target platforms, with `opendir` as the fallback for filesystems
that report DT_UNKNOWN.

### A real bug, caught by the tool's own detector

The engine first ran the target through `/bin/sh -c`. Every single run came back
`child_process_detected` — correctly, because the shell *forks* to start the program
and LD_PRELOAD applies to the shell too. Switching to `sh -c "exec …"` only trades the
fork for an exec, which the same detector catches. The target has to be executed
directly, so the engine now splits the command itself and calls `execvp`.

Two things fell out of that. The boundary detector was proven to fire on a real
occurrence rather than a contrived one. And the limitation is now explicit: arguments
cannot contain spaces until the CLI takes an argv instead of a string.

### Tests that were not running

`zig build test` reported 19 passing while five more tests sat uncollected: Zig
analyses declarations reachable from the root module, and a `test` block inside an
imported file is not reachable that way. Naming each file with tests explicitly in
`build.zig` took it to 26. Nothing was red at any point — the count was the only
signal, which is the whole argument for asserting how much was measured rather than
that the result was green.

### An acceptance check that was wrong in the safe direction

The first version asserted the corrected toy would report "crash points 5 + 1". It
reports 4 + 1, because without the `unlink` it has one fewer operation — the
implementation was right and the check was wrong. Rewritten to compare `explored`
against `N + 1` as a relation, so it stays true whatever the toy does.

Still open from the plan: the strace oracle comparison (Spike-2). The structural
detectors carry the load in the meantime, and `toy-raw` shows they carry it — its
trace is 30 bytes of "nothing happened" while the state directory visibly changed.

## 2026-08-10 — Spike-1: the interposition ground holds (Linux)

The biggest risk retired first, as PRD.md promised. Measured, not argued.

**The shim works.** A recording run of the buggy toy produces this, in order:
`shim_ready`, `open`(seq 1), `write`(2), `fsync`(3), `close`(seq 0), `unlink`(4),
`rename`(5). `close` carries seq 0 because it is recorded but never a crash point, so
N = 5. The delete-before-rename window is visible in the trace as the gap between
seq 4 and seq 5.

**The kill lands where it is asked to.** `SIDEEYE_KILL_AT=k` for k = 1..5 exits 137
(SIGKILL) with a `kill_landed` record present; k = 6 — that is N+1 — runs to completion
with no marker, which is the baseline world. At k = 5 the state directory contains
`key.json.tmp` and no `key.json`: the bug, caught in the act. **10/10 repetitions land
in the identical state.** The corrected toy keeps `key.json` present at every k.

**Two recording runs produce byte-identical traces.** The determinism claim is a byte
comparison, not an impression.

**Out-of-bounds targets are visibly out of bounds**, and each for its own reason:

| target | what the shim sees | what makes it detectable |
|---|---|---|
| `toy-raw` (syscall(2) directly) | 30 bytes: `shim_ready` and nothing else | the state changed while zero operations were recorded |
| `toy-static` | no trace file at all | the shim never loaded, so no marker exists |
| `toy-bug` + fork | a `fork` record | the boundary detector fired |
| `toy-bug` + thread | a `thread` record | ditto |

`toy-raw` is the one that justifies the engine carrying detectors that do not depend on
interposition: its trace is indistinguishable from "this program touched no files".

**Rust's standard library did not route around the supported operation set.** The
plan rated that a high risk — `open64`, `statx`, `openat2` were all plausible. The
stand-in target produced *exactly* the same operation sequence as the C toy:
`open`, `write`, `fsync`, `close`, `unlink`, `rename`. One measurement is not a
guarantee for every Rust program, but the expected divergence did not happen here.

### What the `zig` skill got wrong

The skill was adopted the same day to reduce the risk of generated code targeting old
APIs, and the plan required recording the first discrepancy rather than quietly working
around it. Three showed up, all in the same area:

| skill says | 0.16.0 actually has |
|---|---|
| `std.mem.trimRight` | `std.mem.trimEnd` (`trimLeft` → `trimStart`) |
| `std.fs.File` | `std.Io.File` — `std.fs` has no `File` member |
| `file.writer(&buf)` | `file.writer(io, buf)` — a `std.Io` instance is required |

The skill states that every 0.16.0 stable pattern in it still holds; its I/O section is
0.15-era. Worth knowing before the engine, which cannot avoid that API the way the shim
can.

### A design correction found by building it

DESIGN §12 defines the L0 invariant as: after restart the state directory equals the
pre-operation snapshot or the post-operation result, never a hybrid. Implementing that
literally fails the *corrected* toy — an atomic write leaves `key.json.tmp` behind at
several crash points, so the directory equals neither snapshot.

The invariant that separates the two toys is narrower: **for every path present in both
the pre and post snapshots, the crashed state must contain it, with content equal to one
of the two.** Paths belonging to neither snapshot (temporaries) are ignored. Under that
reading the buggy toy fails at k = 5 (`key.json` missing) and the corrected toy passes
everywhere, which is the distinction the tool exists to draw. DESIGN will be amended.

### Also decided

- **No `anyzig`.** The plan called for it to fetch the pinned compiler, but Homebrew's
  `zig` 0.16.0 — the exact version wanted — was already installed, and `anyzig` conflicts
  with it (both provide a `zig` binary). The declaration in `build.zig.zon` is what other
  environments need; the fetching mechanism is interchangeable.
- The link-type check in `build-toys.sh` first used `file`, which is absent from the
  image; grep matched nothing and every binary was reported as wrongly linked. It failed
  loudly, which is the right direction, but the check now reads the ELF program headers
  (`readelf -l | grep INTERP`) so it does not depend on an optional tool.

## 2026-08-10 — Inception

Design finalized after an adversarial review pass over the first draft. Eight axes were settled; together they define what Sideeye is:

1. **Primary battleground: an automatic gate in the coding loop.** Non-interactive operation, machine-readable output, and the exit-code contract are v0 core requirements — not future polish. The caller is often an agent or CI; the reader is a human.
2. **LLM boundary.** The core (exploration, verdicts, shrinking, replay) is deterministic and LLM-free, permanently. LLMs are allowed at the edges only: proposing invariants on the way in, explaining reports on the way out.
3. **Pure black-box, elevated to principle.** Sideeye sees a binary, a state directory, and the execution's observable behavior. Nothing else. Language-agnostic by construction.
4. **Counterexamples are the whole product.** A PASS is a search record, not a badge, and we will not build a badge culture around it.
5. **Power failure / torn writes: out of v0, named as a long-term candidate.** v0's crash model is process crash — the OS survives, completed writes persist. Every report says so.
6. **v0 runs natively on macOS and Linux.** This was chosen knowingly: it pushes the mechanism toward userspace interposition (macOS forces every language through libSystem, which makes one mechanism cover Rust/Go/Python; the cost is that hardened-runtime macOS binaries and statically linked Linux binaries are declared unsupported rather than silently mishandled).
7. **Public design doc, in English.** This repository is the document.
8. **Define converges on built-in invariants.** L0 = zero-config atomicity judged from state-dir snapshots; L1 = the program's own success message on stdout, held against it; L2 = domain checker scripts. The whole user-facing contract is three commands and one directory.

Practical decisions the same day:

- **Name check:** crates.io free, GitHub free of significant collisions (max 3 stars). PyPI and npm are taken by unrelated projects (an eye-tracking library and an actively updated package, respectively). Shipped as `sideeye` anyway — distribution will be a single binary, so those registries matter little.
- **License:** dual MIT OR Apache-2.0.
- **Biggest known risk:** the interposition spike — kill a toy binary deterministically at the k-th file operation, on both OSes. It is deliberately the first milestone task in PRD.md; if it fails, better to learn that in week one.
