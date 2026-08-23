# Buildlog

Development journal, newest first. Decisions are recorded when they are made — including the ones that turn out wrong. This file is allowed to be embarrassing in hindsight; that is what it is for.

## 2026-08-23 — #181: the macOS no-oracle claim gets its measurement

The claim decides what a verdict means on half the supported platforms,
lives in four claim sites plus CI and two docs, names one tool, and ADR
0001 has said "to be measured" since 2026-08-10. The 08-10 entry's
objection — a sudo-only oracle is not a CI tool — is an argument about
the product default, not about whether an observer exists, and it was
written without running anything as root.

The survey splits on the privilege line. The unprivileged half ran first
(`spike/macos-oracle/survey.txt`): every candidate refuses without root,
each refusal captured verbatim — including the distinction the issue
called out, that unprivileged `dtrace`'s hard stop is PRIVILEGES while
SIP only limits "some features". OpenBSM is dismissed there without a
sudo leg: auditd(8) on this machine says the subsystem is deprecated
since 11.0, **disabled since 14.0**, and will be removed. The ktrace
invocation for the privileged half is designed from this machine's man
page (filter class `C3`, `-c command`), not from memory, because
unprivileged ktrace refuses before printing usage.

**Predictions, written before the privileged half runs**, so the run can
contradict them:

- `sudo dtruss` on the self-built, ad-hoc-signed toy: genuinely unknown —
  this is the promised measurement. If it traces, four claim sites
  overstate ("SIP refuses dtruss" is then true only of unprivileged
  invocations); if it refuses even as root, the claim survives with the
  privilege nuance corrected.
- `fs_usage` as root: expect visibility with pathnames (kdebug substrate);
  open questions are path truncation in non-tty output and event drops.
- `ktrace -f C3`: same substrate as fs_usage; expect the same visibility
  or a usage error that is itself the measurement.
- `eslogger`: expect either JSON events or a TCC refusal naming Full Disk
  Access; either answers whether ES is reachable without our own
  entitlement.
- A first-party ES client stays out of reach for a survey (the
  entitlement is Apple-granted); eslogger is its measurable proxy.

What the answer changes either way: the four claim sites say "macOS has
no usable oracle" where the measured statement so far is "no unprivileged
oracle, and the privileged candidates were never asked".

**Round 1 (2026-08-23T08:31Z) answered two legs decisively and caught my
harness lying on a third.**

The decisive pair. L2: even as root, DTrace's syscall provider matches
no probes — "probe description syscall:::entry does not match any
probes. System Integrity Protection is on". So sudo does not rescue
DTrace; the 08-10 claim survives at root, though its stated reason
("requires additional privileges") was the unprivileged symptom, not the
cause. L3: **fs_usage is oracle-shaped.** Full paths, operation names
(open / WrData / rename / unlink / mkdir), attribution to `toy.<pid>`,
timestamps, order intact — all three markers in first-appearance order,
nine event lines, zero contamination, no truncation at these path
lengths. The kdebug substrate saw everything this survey's
six-operation toy asked of the oracle role.

The lie. L1 reported dtruss "ok - all 3 tokens present", and every one
of its marker lines began with `op ` — the toy's OWN stdout. dtruss runs
the child itself, the child's output landed in the capture, and the
check judged the target's self-account as the observer's testimony. A
confident false pass on the exact machine where L2 proves the provider
is gone. L4 (ktrace) has the same contamination, and its verdict line
shows only 6 marker lines = the toy's own, which suggests raw kdebug
events carry no resolved path strings — but round 1 cannot prove that,
because the capture was cleaned up and only marker lines were excerpted.
L5 (eslogger) failed with a 1-line capture whose content the transcript
never showed, for the same excerpting reason.

Fixes, each the shape of a lesson already paid for elsewhere: runner
legs now route the toy through a wrapper so captures hold only what the
observer emitted; check-capture rejects a capture whose every marker
line is the toy's own words (seen red on a synthetic copy of round 1's
dtruss capture; the ground-truth control passes `--allow-self-account`
explicitly); verdicts print the capture head verbatim so a refusal
survives into the transcript after the raw file is cleaned up.

**Predictions for round 2, before it runs:** dtruss becomes a measured
refusal (capture = DTrace's own error lines, check FAIL "saw nothing",
toy account showing toy-rc=0 separately); ktrace's clean capture shows
**0** observer lines carrying a marker path, because raw kdebug does not
resolve paths — fs_usage is the front-end that does; eslogger's one line
becomes readable and is expected to name Full Disk Access.

**Round 2 (08:36Z): one prediction confirmed, one measurement settled a
second time, and a guard of the owner's broke three legs while my BROKEN
counter said 0.**

What held: eslogger's one line, now readable thanks to the verbatim
head, names exactly what was predicted — "responsible process needs TCC
Full Disk Access authorization (ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED)".
Root changes the refusal from NOT_PRIVILEGED to NOT_PERMITTED: ES is
reachable only behind root AND an FDA grant to the invoking terminal.
fs_usage passed a second time, this round with the contamination guard
attesting all 9 marker lines came from the observer.

What broke: the transcript's line 14 reads "omamori blocked this command
because it was invoked via sudo/elevated privileges" — the wrapper's
`chmod 755`. The wrapper stayed 0644, dtruss and dtrace died on "failed
to execute run-toy.sh: Permission denied", ktrace on "could not start
process", and none of that reached the BROKEN counter because the chmod
carried no guard: the exact targets-added-after-the-check shape, one day
after writing it down elsewhere. The owner's guard blocking the
measurement is itself the own-guard-blocks-the-next-measurement shape.
Round 2's L1/L4 therefore measure nothing about SIP; round 1's L2
remains the only probe-provider evidence (preserved as
sudo-survey-round1.txt; round 2 as sudo-survey-round2.txt).

Fix: no mode change anywhere. The wrapper is invoked as `/bin/sh
wrapper`, which needs no exec bit — routing around the guard with an
absolute /bin/chmod would be circumvention, needing no chmod is not.
dtruss and dtrace keep the toy as their DIRECT child, because /bin/sh in
front would make the traced root a platform binary, the one case the
SIP question must not be measured on; their contamination fix is stream
separation instead (trace on stderr, toy account on stdout).

**Predictions for round 3:** dtruss, clean streams — capture holds
DTrace's own refusal lines and zero syscall lines, check FAIL "saw
nothing", toy account 7 lines with toy-rc=0; dtrace aggregate rows 0
with the round-1 probe refusal back; ktrace starts this time, and its
observer lines carrying a marker path number **0** (151 non-op event
lines in round 1 held none); eslogger identical FDA refusal; fs_usage
passes a third time.

**Round 3 (08:41Z): complete. Four predictions held; the one that
missed, missed in a direction worth the whole survey.**

dtruss did not refuse. It printed its trace header and **zero syscall
lines**, ran the toy to completion, and **exited 0** — a silent empty
trace, which for an oracle is worse than a refusal, because the exit
code alone reads as success. The prediction said "refusal lines"; the
reality is quieter and more dangerous. The stream separation also failed
— dtruss remixes its child's stdout onto stderr, so the toy's account
landed in the capture after all — and the contamination guard built
after round 1 **fired in production**, turning what round 1 had scored
as "ok" into the correct FAIL. The guard's first real catch is the same
false pass it was built from.

Everything else landed as predicted. dtrace reproduced the round-1
probe refusal verbatim in a clean transcript. ktrace started under the
/bin/sh wrapper (a 337-line capture — a launch line, a column header
and a blank, then events — toy-rc=0 in its separated account) and
carried **0** marker paths in its own event lines — kdebug packs path
bytes into hex args; fs_usage is the shipped resolver. eslogger repeated
its FDA refusal, and fs_usage passed a third time, 9 of 9 marker lines
from the observer.

**The verdicts, and what moved.** The claim "macOS has no usable
oracle" was false as universally stated and is now corrected in seven
places (four claim sites the issue named, plus ci.yml, unknown-rate.md
and an acceptance.sh comment the issue's census missed): no
*unprivileged* oracle exists; SIP leaves DTrace's syscall provider
with no probes even as root, and dtruss fails silently on top of it;
`fs_usage` as root gave an ordered, attributed, full-path account of
the survey's six-operation toy, three runs out of three; Endpoint
Security's shipped CLI refuses without root plus a Full Disk Access
grant (a first-party ES client is unmeasured); OpenBSM is disabled by
Apple since 14.0. The 08-10
product stance — no root demand in a distributable default — survives
untouched, now standing on measurement instead of one sentence about
one tool. Left explicitly unmeasured: fs_usage's drop behaviour under
load, ktrace's --json output, and eslogger with FDA actually granted.

**R1 found eight claims wider than their transcript lines, all
accepted.** The heaviest: "DTrace is dead under SIP even as root" was
measured only for the syscall provider the probes named — every claim
site now says the provider — and "dtruss traced nothing" rested on a
capture the transcript showed only excerpts of. The arithmetic that
makes it checkable from committed data: the 283-byte capture holds the
SIP notice (80 bytes), the trace header (~36) and the toy's seven
`op` lines plus `done` (166) — those sum to the byte count within a
couple of bytes, and a dtruss syscall line runs tens of bytes, so
there is no room for even one. "Endpoint Security sits behind root plus
FDA" is now scoped to its shipped CLI, the thing actually measured.
"337 events" was numerically false (three preamble lines). The man-page
provenance the sudo script's comment cited was never committed —
survey.txt now carries the ktrace filter grammar, the eslogger TCC
paragraph and the fs_usage synopsis it designs from. And two guards no
transcript had shown red — wrapper readability and the residue check —
now fail on their own predicates in `sudo-survey.sh --selftest`, the
residue one against a live process really named fs_usage. observe()
additionally bounds the toy (R1: the 45s watchdog bounded only the
observer) and records whether the observer survived the settle;
rounds 1-3 ran before those two fixes, and no conclusion rests on the
paths they change — fs_usage's passes and eslogger's refusal are
outcome-proven in their transcripts.

The residue selftest's first version produced its own measurement: it
staged the fake observer by copying /bin/sleep to a file named
fs_usage, and the copy died on exec with SIGKILL — a platform binary
at a new path fails its signature identity check, which is the exact
mechanism this repository's platform-binary refusal text describes
("copying the binary elsewhere does not change its signature"). The
selftest now compiles its sleeper, ad-hoc signed by the linker, and
passes in both directions.

## 2026-08-23 — the record catches up with cohort 4, and the denominators get a route

Cohort 4 closed this morning; the top-level record did not move with it.
`PRD.md`'s criterion-1 trail stops at cohort 3, `DESIGN.md`'s status line
still reads "design finalized, pre-implementation" thirteen tags in,
`docs/target-classes.md` carries neither the himalaya verdict nor the
unison probe wall, and its git row cites `#35` as open although that
issue closed 2026-08-17. That page was backfilled for cohorts 2 and 3
yesterday and drifted again within a day, which says the fix is a habit
at cohort close, not a bigger backfill.

Two measurements shaped this change. Both were made while planning it,
before this entry existed — the entry opened with the working tree, which
is the first moment there was a tree to open it in.

**The mini-seal transcript is missing for the one target that needs it
most.** Cohort 2 commits four `verify-transcript.txt` files and cohort 3
commits six — ten, and not one per target: the probe walls never spent a
define and poetry carries two. Cohort 4 commits none:
`git log --oneline --all --diff-filter=A -- 'spike/cohort4/**/verify*'`
returns nothing, so the file was never added there. The check itself
passes — `verify-assisted.sh spike/cohort4/himalaya-r2` returns ALL ORDER
CHECKS PASSED, the define complete at `e445686` strictly preceding the
first artifact at `1949c62`, all four define blobs byte-identical at both
points. What is missing is the evidence, not the property, and it is
missing on the first criterion-1 candidate in four cohorts — the target
whose provenance leg the mini-seal exists to machine-check.

**A hypothesis about severity died in the source, in the useful
direction.** Planning this, I expected `maildir messages move` to be
copy-then-delete, which would make the same crash window destroy mail
outright rather than leave clutter behind. It is not:
`io-maildir/src/entry/move.rs` runs
`Locate → AwaitTime → AwaitPid → AwaitHostname → AwaitRename` and
completes on the rename reply. One rename, no interior to crash inside.
`copy` is the outlier among the crate's arms, which is the opposite of
what I went looking for.

**One correction to my own prose, caught before review.** Both this entry
and the PRD paragraph first said the mini-seal ran on *every* target of
cohorts 2 and 3 — ten transcripts, ten targets, which reads true and is
not. KeePassXC spent no define and has none; poetry carries two. The
count was right and the universal was wrong, and it only became visible
when cohort 4 made the two numbers disagree: twelve targets, eleven
transcripts. Both sentences now state the count and name the exceptions
instead of quantifying over targets.

**The review round, and what moved.** Five P1s, no P0. The reviewer
re-derived every count here independently — eleven transcripts, twelve
targets, thirteen outcomes, five standing walls, seven verdicts, eighteen
post-sweep defines, thirteen release tags — and all of them held. Four
sentences did not:

- The criterion-6 note said the README had changed **twice** since run 1.
  `git log --since=2026-08-17 -- README.md` says **seven** commits, and
  this change is the eighth. Written from memory of what I had touched
  rather than from the log, which is the failure the rule about writing
  numbers from open sources exists to catch, committed inside a paragraph
  whose whole subject is a stale document.
- The same note said run 1 was "no longer the last run before the
  freeze". It is: it is still the only run, and by the criterion's own
  rule it is still the evidence. What moved is the document it measured,
  not its standing, and the note now says that and declines to re-score.
- The load-bearing sentence credited the mini-seal with showing that the
  define "preceded any observed failure". `verify-assisted.sh`'s own
  header says it audits the history as pushed and proves nothing about
  what happened on a private disk first. The claim is now split: the
  pushed ordering is machine-checked, and the protocol statement rests on
  it with the public order as its witness.
- The new README paragraph called the tool "safe to leave running
  unattended", which collides with the MCP section three paragraphs
  above, where this repository says plainly that the root confines which
  config may be named and not what that config's operation does. Narrowed
  to the exit-status distinction, with the boundary named rather than
  implied.

Also scoped, at the reviewer's prompting: criterion 4's status described
the A-group as "every runnable committed define", which stopped being
true when the eighteen later defines landed. It now carries its sweep
date and a pointer to `#239`.

**And the local check lied, in the documented way.** Rather than run the
full acceptance suite outside its container, I re-implemented check 11's
reference sweep to pre-check my own edits — and it reported
`/bin/true` missing from the cookbook, a reference that has been there
untouched all along. The real check skips absolute paths
(`case "$r" in -*|/*) continue`); my copy did not. Nothing was wrong with
the page and nothing needed fixing, which is the point: a check written
by copying production instead of calling it produces findings that belong
to the copy. The pre-check kept its value only as an existence test on
the four references this change adds; the sweep itself is CI's.

**The simplify pass changed the shape of the fix.** Two things came out of
it. One was ordinary trimming: the same conclusion — that what criterion 1
still lacks is no longer the search half — had been written three times in
three consecutive PRD paragraphs, and now appears once where the argument
is. The other is the reason this entry exists at all. Fixing the pages by
hand is the same move that was made yesterday for cohorts 2 and 3, and it
will be the same move again at cohort 5 unless something opens these files
at the moment a cohort ends. `CLAUDE.md` already carries exactly that rule
for `.gitattributes`, bought by exactly this failure; the record and the
verify transcript now sit beside it. That is a scope addition to this
change, deliberate and named here rather than slipped in.

**Then the same class bit a third time, in the rule itself.** Running the
diff through the universal-quantifier scan the claims rule asks for —
before opening the PR, after the commits were already pushed — turned up
the new `CLAUDE.md` sentence saying each define that reached an explore
leaves a verify transcript. Cohort 2 holds nine define directories and
four transcripts: hg's first three revisions and borg's first two all
reached explores and left none, because the transcript belongs to the
revision that produced the recorded outcome. Fixed forward rather than
amended, since the branch was pushed. Three instances in one change —
prose, then prose, then a rule written to prevent the first two — is the
argument for running that scan before review rather than after.

## 2026-08-23 — the formula shipped and the README still said "download the tarball"

`#180`'s whole thesis was that installing takes four steps and one thing
to remember where the ecosystem's answer is one line. The formula landed,
`brew install yottayoshida/tap/sideeye` works, the issue was closed
quoting that line — and the README, which is where anyone would actually
look, still opened with `tar xzf`. Half the issue, shipped as if it were
all of it.

The mechanism is worth naming because it is not "forgot". The release
checklist has a README step and it ran, at bump time, and its conclusion
was correct **then**: the only version-relative string was the tarball
name. The formula merged afterwards. Nothing brought the README back into
view once the thing it described had changed, because the checklist
attaches that step to a version bump and this change was not one.

Fixed here: the install section leads with brew, the tarball path stays
for everyone it still serves and now says *why* it wants you in that
directory (the shim sits beside the binary), and the three usage examples
drop their `./` since the primary path puts sideeye on `PATH`.

Checked before editing, because prose edits have moved test anchors here
before: nothing reads the README's install block. `quickstart.yml` builds
from source and `acceptance.sh` only mentions the README in a comment.
Checked after: `sideeye demo` from `PATH` exits 1 with the shim resolved
out of the Cellar, and `sideeye preflight` on a real state directory
refuses with `no_shim_marker` — which is SIP declining to inject into
`/bin/sh`, a platform binary, and not a shim it failed to find. Zero
complaints about a missing `--shim` in either.

## 2026-08-23 — v0.13.0: a second exhibit, a wider metadata exclusion, a relocatable shim

Minor rather than patch, and the reason is the second of those three: the
oracle's metadata exclusion widens to the timestamp family (#190), so a
run that previously refused with `unsupported_syscall_observed` on a
timestamp write now reaches a verdict. That changes what existing targets
answer, which is not a patch-level change. `checker_earliest` (#231) also
adds a field to the report.

The version lives in three places and all three moved: `build.zig.zon`,
`src/main.zig`, and the tarball name in the README's install block. Found
by grepping for the old version rather than from memory, which also
turned up a dozen mentions that must NOT move, because they name v0.12.0
as a past artifact: the headerpad measurement in `build.zig` and
`release.yml`, this file's own history, and the `sideeye_version` stamped
into every committed case file.

README reconciliation, the step that exists because two releases in a row
forgot it: the install block's tarball name is the only change it needs.
The FAIL report sample stays byte-accurate because its earliest world is
itself checker-red, which is exactly the case #231 leaves untouched, and
its `metadata` line was already about restore rather than about the
oracle's exclusion. `docs/scouting.md`'s table row had already moved with
#221.

The reconciliation also found the README's list of tools with
replay-confirmed counterexamples — timewarrior, topydo, GNU Stow,
calcurse, devtodo — running behind. That is a claim about the project's
record rather than a version-relative string, so it went to the owner
rather than being quietly edited; the ruling was to add himalaya, whose
counterexample replays and whose report is filed as
`pimalaya/himalaya#738`. poetry stays out for now: its report is closed
and its outcome is a separate question from whether the counterexample
stands.

168 tests, and the binary answers `sideeye 0.13.0`, which is the exact
form the release workflow checks against the tag.

## 2026-08-23 — the shim was not relocatable, and only a package manager noticed

`#180` had already measured that a Homebrew formula needs no code change:
the shim search is the binary's own directory then `../lib`, resolved
through realpath, which is exactly a keg's layout. That held. The formula
installs, `sideeye version` answers, and `sideeye demo` finds the planted
bug with the shim resolved out of `../lib`.

**And `brew install` still exits 1.** Homebrew rewrote the shim's install
name to an absolute path under its prefix, and v0.12.0's shim has no
padding in its Mach-O header for a longer name, so the rewrite failed and
the install reported "Failed to fix install linkage". Moving the dylib to
`libexec` does not help; the whole keg is scanned. sideeye's own lookup
does not notice, because it resolves the shim by real path and injects
that path, so the name it carries never enters the search. That is why
this survived to here: nothing that uses sideeye the way sideeye is used
had a reason to read it.

R1 caught two places where I had written that more widely than I had
measured: "the install name is never consulted" is false in general, since
dyld uses `LC_ID_DYLIB` as the library's identity, and "Homebrew rewrites
every dylib in a keg" is false too, since it has exceptions this library
happens not to qualify for. Both narrowed. The causal claim about this
library was never in doubt; the sentences around it were.

The fix is one build flag, `headerpad_max_install_names`, macOS only.
Measured as a pair on the two real artifacts rather than argued: give
both the same long install name, and v0.12.0's dylib keeps
`@rpath/libsideeye_shim.dylib` while the rebuilt one takes the new path.

**The tool lies in a way worth writing down.** `install_name_tool` prints
"larger updated load commands do not fit" on stderr and **exits 0**. Both
halves of the pair returned 0. The only thing that separated them was
reading the install name back with `otool -D` afterwards. So the new
release-workflow check asserts the resulting name, never a status, and
says so in a comment next to itself. It was seen red on v0.12.0's
released dylib, which is a real artifact rather than a synthetic one.

Ordering consequence, recorded because it reverses a decision made an
hour earlier: the formula cannot point at a release that predates this
flag, so Homebrew now lands after v0.13.0 rather than before it. The
formula itself is written and `brew audit --new` clean; only its URLs
and checksums are waiting.

## 2026-08-23 — cohort 4 closes, and stops counting as Shell

The slate is exhausted: himalaya reached a criterion-1 candidate and the
finding is filed upstream as `pimalaya/himalaya#738`, and unison is a
recorded named wall on determinism. `.gitattributes` says a closed cohort
belongs in its list, so `spike/cohort4/**` joins it.

That is 173,168 bytes of shell out of the 425,400 GitHub was still
counting, about two fifths of the visible Shell in a Zig repository. The
live harness stays out of the list on purpose, and the check that it did
was a negative control rather than an assumption: `acceptance.sh`,
`merge-gate.sh` and `campaign-driver.sh` all still report the attribute
unspecified, while all 112 tracked files under `spike/cohort4` report it
set.

**Filing the report left a second thing owed, and it was nearly missed.**
`upstream-report-status.sh` opens by saying it measures rather than
remembers, but the list of reports it measures is hardcoded in the
script. A new report that is not added there does not appear as missing:
the table simply prints five rows and looks complete, which is the exact
failure the file was written to prevent one level down. `#738` is
registered now, and the table prints six.

## 2026-08-23 — the recovery paths outside the tool

The last precondition the freeze's Reporting section puts in front of a
report: measure the recovery paths that exist outside the tool, and the
conditions under which they do not apply. Seven legs. R2, R4, R5, R6 and
R7 each produce the damage for themselves with a real crash rather than
assembling a store by hand; R3 is the deliberate exception and runs the
operation to completion, because what it counts is what the whole
operation does.

**The first thing measured was my own scan.** A three-level walk of the
command tree reported 208 commands; measuring the depth instead of
assuming it found a fourth level with 29 more. (Those two numbers are
this entry's own history, not artifacts: the committed script measures
depth 4 and 216/237.) The loose parse then turned out to be reading
wrapped alias lines as commands, so the enumeration is
indentation-strict and validated in both directions: every node it keeps
answers `--help` (216 of 216), and every node the fix dropped is not a
command (21 tried, 0 real). The dropped-node check printed a reassuring
`0` the first time it ran with its input file missing, which is why it
now refuses on an empty list.

**The answer.** Two recovery paths work and both need the user to notice
first. Repeating the copy restores the message but leaves the empty one
beside it, listed as a message. The empty one can be moved out by the
tool's own delete once the account names a trash mailbox, where it sits
in Trash still at 0 bytes. Meanwhile nothing offers to notice: no
command *name* in the surface is about checking stored mail, and
`account check` reports `maildir: OK` over the damaged store. The one
independent reader tried, python's `mailbox.Maildir`, enumerates the
empty file as an ordinary message as well.

Re-fetching from a server cannot restore the target-folder entry,
because the operation makes no call of the traced `%network` class while
creating it and no name in the surface is a sync. That is about the
entry and not the content: the content still exists in the source
folder, which is the honest limit of this finding's severity.

**Three things went against what I had already written, which is the
entire reason the controls are there.**

`message delete` refused on the empty message with `Cannot determine the
trash mailbox`, and I had written that up as the tool being unable to
remove it. The control refuses in the same words on a healthy message in
the same folder under the same config, so it is a property of an account
with no trash mailbox. The first version of that control was not a
control at all: it targeted the source message without `-m` and failed
with a different error entirely.

The review then found that the network leg counted a hand-written list
of syscall names, which measures "none of the names I thought of" rather
than none. It now counts every syscall line in a log strace was already
told to fill with the `%network` class, and the positive control
promptly caught `getsockname` and `getpeername`, neither of which was in
the old list.

The same review found the walk's `--help` status was being lost through
a pipe, so a failed invocation would have looked like a childless leaf.
Capturing it turned up 21 failures, and the new guard stopped the run.
They are all in the *loose* walk, which descends into the alias
fragments it mis-parses, so the guard's predicate was too wide and now
counts the strict walk. The number is a gift: 21 loose failures against
21 dropped nodes is a second, independent confirmation that the dropped
ones are not commands.

R2 then found the one fix that had not actually landed. I had added a
non-empty assertion to the store snapshot and treated the point as
closed; the reviewer pointed out that `find`'s status was still going
through a pipeline, so a **partial** read would give a short list rather
than an empty one, two short lists would compare equal, and "store
unchanged" would be a statement about an unknown subset. Recording the
status per call fixes it, and drilling it is what turned the point from
an argument into a measurement: with one subdirectory unreadable under a
dropped uid, `find` returns rc 1 **with one file still listed**, which
is exactly the shape the non-empty check cannot see.

That drill is now a `--selftest` mode, because the same rule that says a
define's checker legs must each be watched failing applies to the guards
a measurement script carries. Five cases, all green, and the first
attempt at the drill was written inline in nested shell and printed
`drill ok` from a comparison against an empty string, which is the
failure it exists to prevent.

Left explicitly unmeasured, written into the transcript rather than kept
in my head: whether an external syncer would carry the empty message
outward to a server, whether any reader other than the one tried would
flag it, and whether clap's help is a faithful index of the binary.

## 2026-08-23 — the stock reproduction, and what it corrected about my own argument

The freeze wants a finding to reproduce against the stock tool with
nothing beyond strace fault injection before it is claimed or reported.
Done, with the apparatus checks in the script rather than in a sentence:
no `/etc/ld.so.preload`, `LD_PRELOAD` unset, no shim, no engine, no
seccomp profile.

**And it corrected something I had argued rather than measured.** The r2
toml said the kill window does not depend on the apparatus, because the
destination is created and filled afterwards whichever primitive does
the filling. Stock turns out not to take the path the define measured at
all: it copies the whole 307-byte message in a single `copy_file_range`,
where the apparatus had removed that primitive and forced a read/write
loop. The window is there anyway. Killing at the copy leaves a 0-byte
message at its final path, himalaya lists it as an ordinary envelope
with blank subject, sender and date, and `message read` on it fails.

So the argument held, and it is now a measurement, which is the whole
reason the rule asks for one. The apparatus decided what the engine
could see; it did not make the finding.

Also caught by a gate rather than by me: the first push of this work
changed `spike/` without touching BUILDLOG, and CI's buildlog job failed
the PR. That is the contract this file opens with, enforced.

## 2026-08-23 — himalaya-r2: a FAIL through the declared checker, reproduced twice

The revision ran and the declaration held on every point it made.
**FAIL, 1 of 3 worlds, `oracle_verified: true`, single process**, the
violated invariant being the checker rather than the engine's built-in
atomicity invariant, and the report carrying `checker_earliest` — which
is exactly what this cohort's frozen claim rule asks a criterion-1
candidate to be. Two runs agree on every field that carries a judgement;
the eight that differ are the minted filename, which the checker is
name-agnostic about by design, and the per-run work paths. The exhibit
replays.

The crash lands after the destination is opened and before anything is
written to it, and leaves a message file at its final path in the target
folder with **0 bytes against the source's 307**. `proposals.md` named
that window, that leg and that world count before the engine ran, and
nothing in it was adjusted afterwards.

What is deliberately not claimed yet, and is written into RESULTS rather
than left to be discovered later: the stock reproduction is still owed
(the freeze wants a measurement, and the kill window being
apparatus-independent is so far an argument), the outside-the-tool
recovery paths the Reporting section demands are unmeasured, and novelty
was cleared at selection time rather than here.

One correction to my own procedure, recorded before the good news
because it is the part worth remembering: the first pair of r2 runs
happened with the r2 define on a local branch only. The mini-seal wants
a revision's directory first-parent on main before the engine touches
it, and `verify-assisted.sh` refuses on exactly that. The checker had
been on main since #247, so criterion 1's own text held, but the
mechanical discipline is the part that makes a claim publishable. Those
runs were discarded and repeated after the merge. They cost four
minutes.

## 2026-08-23 — himalaya explores, refuses, and the refusal is a gap between two predicates

The first explore of the merged define came back UNKNOWN:
`unsupported_syscall_observed: copy_file_range`, exit 2. The seccomp
profile was working exactly as the probe measured it — copy_file_range
and sendfile both ENOSYS, the copy falling back to the libc read/write
loop, 307 bytes landing correctly. The refusal was not about the target.

**Two predicates that looked like one.** The probe's condition asked
whether any accelerated copy SUCCEEDED and answered no. The oracle asks
whether the syscall was OBSERVED, and its predicate reads the syscall's
name and never its return value (`changesPersistentState`, oracle.zig).
An ENOSYS from the kernel is still an observation. A profile that makes
a call fail cannot satisfy a rule about calls being made, and the probe
gate could be green on its own terms while the next stage refused.

The owner ruled a revision, the cargo-r2 precedent: a refusal is not a
FAIL, so nothing about the define is frozen by it, and the define
surface — property, checker, setup, fixtures, argv — moves to
`himalaya-r2` byte for byte. Only the apparatus changes.
`no-accel-copy.so` answers the three accelerated primitives in userspace
so the syscall is never made and the tracer has nothing to see, which is
reachable because Rust std resolves them as weak symbols precisely so
`LD_PRELOAD` can interpose them (#244). Measured before the revision was
written: zero copy_file_range/sendfile lines in the trace, strace itself
healthy, the copy still 307 bytes. It rides /etc/ld.so.preload because
the engine owns LD_PRELOAD for its shim, and unlike the pid pin it
defines only those three functions.

What the apparatus does **not** change, since the stock-reproduction rule
turns on it: the destination is created with O_CREAT|O_TRUNC and filled
afterwards on both paths, so the kill window exists whether the fill is
one copy_file_range or a read/write loop. The apparatus decides what the
engine can see, not whether the window is there.

**And a procedural error of mine, recorded because the contract asks for
the reversals.** I explored r2 with its define only on a local branch.
The mini-seal requires a revision's target directory to be first-parent
on main before the engine touches it, and `verify-assisted.sh` refuses
(exit 2) precisely on that. The invariant itself had been on main since
#247 — the checker in r2 is byte-identical to the one that merged — so
criterion 1's own text was satisfied, but the mechanical discipline was
not, and the discipline is the part that makes a claim publishable. Both
runs were discarded rather than kept with a disclosure. They cost four
minutes and had already proved themselves reproducible; provenance costs
more than that.

## 2026-08-23 — himalaya's define: what the checker may use, measured before it is written

Entry opened before the define exists, per the contract. The probe (#246)
established the operation is measurable; the define now has to state the
property, and the mini-seal says nothing may explore until the complete
define — toml, setup, checker, launcher — is first-parent on main.

Two things get measured before a line of the checker is written, because
cohort 3 paid for both. papis's checker rejected `papis doctor` as the
documented recovery on a reading that had never actually run the command
(no selection flag, so it fell to an interactive picker), and papis's own
reader turned out to WRITE — `papis list` minted and persisted a random
papis_id into a document that had lost one, which would have made a byte
assertion after the reader a judgement of the checker's own side effect.
So for himalaya: does the reader this checker wants to use mutate the
store, and does himalaya carry anything that could be called a documented
recovery? Both answered by trials in `pre-define-trials.txt`, before the
property is committed.

**Both answers came back useful, and one of them shapes the property.**
The reader does not write: five states, healthy through zero-length,
with every path, size and checksum snapshotted around each invocation,
and nothing moved. So the ordering papis needed does not bind here, and
the checker says which of the two reasons it is following. There is no
documented recovery either: the enumerated command surface has no
doctor, repair, check, verify or fsck, and the maildir subtree offers
create, rename, delete, list, messages, flags. Nothing is run before the
assert because nothing claims to repair a store.

The measurement that shapes the property is trial G. **A zero-length
message lists as an ordinary envelope** — one row, `0 B`, blank subject,
from and date, rc 0 — and so does one cut mid-headers. Only `message
read` refuses the empty one. That settles the checker's architecture:
the byte assertion is what catches a torn copy, and the tool's own
reader runs beside it rather than instead of it. It also says something
about what a finding here would mean, which `proposals.md` states before
the engine has run: a crash in this arm leaves a message the tool
presents as real and whose content is gone.

Two design decisions recorded with their reasons. The checker is
**name-agnostic**: io-maildir mints the copy's filename from clock,
counter, pid and hostname, and the pins the probe used cannot come along
— the engine owns `LD_PRELOAD` for its shim, and `/etc/ld.so.preload`
was measured to break strace, which the engine uses as its oracle. The
engine does not need cross-run byte identity (it refuses on threads and
on a baseline that violates the invariant), so the checker asserts
content and flag suffix and never the minted name. The **seccomp profile
stays**, and is not optional: without it `fs::copy` reaches
`copy_file_range`, which the shim does not export and the oracle reports
as unsupported. It applies at the container boundary, so the launcher
cannot carry it and the RUNLOG records the invocation that does.

Drills: every leg red once, on its own, with the expected leg named.
**Re-read after two review rounds, per the contract, and two sentences
of this paragraph did not survive them.**

The first draft said "both states the operation can actually leave are
green", and R1 pointed out that both had been measured on stores built
by hand: the operation itself appeared in no transcript in the PR. It
does now, first case in the drills, through the define's own setup and
the toml's own argv, and it is the case that matters most, because a red
checker on the un-killed state is what `baseline_violates_invariant`
costs the target its slot for. The run also demonstrated the
name-agnostic design rather than arguing it: with the probe's clock and
pid pins absent the copy landed as
`1787451722.#0M840838050P17.<host>:2,S`, 307 bytes, and the checker
passed.

The same draft said leg R's predicate was "exercised directly" and left
it there. R1 counted the leg's fail sites: five, with two drilled. All
five are drilled now. Leg C is two drills rather than one, a changed
config and a missing one, because the first version reported a config
that had been deleted as one that had "changed".

R1's first finding was the sharper one, and it was mine: the drills
spawned check.sh as `sh file`, the form CLAUDE.md forbids and campaign 2
bought with a Permission denied at the first sealed exploration, and
they had copied setup.sh's config-writing inline, so the define's own
setup had no green run anywhere and a drift between it and the checker's
leg C would have stayed green in the drills. R2 then proved the fix by
its own predicate rather than by inspection: with check.sh at 644 every
drill fails with Permission denied, so the exec bit is load-bearing and
there is no silent `sh` fallback.

## 2026-08-23 — cohort 4 probes: the plans are frozen, so the scripts are transcription

Entry opened at the start of the probes work, an hour after the freeze
(#245) merged. The probe plans, fixtures, argv and apparatus are all
frozen in PROTOCOL.md, so what this PR adds is their mechanical form: the
positive control (cohort 3's synthetic wall-clock writer, verbatim in
predicate path), one run script per target with the fixture bytes
transcribed exactly, and the transcripts. The one design decision the
scripts do make, recorded now: each target's script takes a mode argument
(the borg precedent), because the falsification order is part of the
frozen plan. himalaya runs `bare` first (no apparatus; the determinism
split on the minted pid and the strace showing `copy_file_range` are the
falsifications that JUSTIFY the apparatus) and `apparatus` second
(ld.so.preload carrying libfaketime and pin-getpid.so, the container
under seccomp-enosys.json, where the accepted verdict lives). unison runs
the same two modes with its own argv. Apparatus plumbing corrections, if
any, land in the transcript per the freeze's own rule.

**himalaya passed every judged condition, and the bare mode earned its keep.**
Without apparatus the two runs split on the minted entry name and the
copy *succeeded* through `copy_file_range` — the shim-invisible path — so
the seccomp profile was justified by measurement before it was used once.
With it: byte-identical roots, the minted name reading
`1767225600.#0M0P4242.<host>` in both (the apparatus visible in the
artifact), condition 8 clean, condition 9 counting two kill points, and 0
of 3 kernel-copy attempts succeeding.

**unison cost four wrong hypotheses and ended as a named wall — which is
the probe gate working.** The first apparatus run hung after "Looking for
changes". Four things were blamed and each was eliminated by measurement
before the next was tried: the equal-second guard in `Fileinfo.unchanged`
(reachable only if libfaketime faked stat, which a direct check said it
did not — and that check was itself wrong, having read the mtimes with
`env -u FAKETIME`, i.e. with the apparatus switched off); pin-getpid; the
seccomp profile; and the frozen clock as such. A bisection down to the
one structural difference found it: **the harness was creating its
fixtures and pristine restores under the frozen clock**, which made their
mtimes equal the frozen instant as the target reads them, arming unison's
own guard — and libfaketime then scaled its one-second sleep by the
frozen speed. strace named it exactly:
`clock_nanosleep(CLOCK_REALTIME, {tv_sec=9223372036})`. libfaketime is
inert without FAKETIME in the environment, so applying the apparatus to
the target invocations only is the whole fix, and it is recorded as a
plumbing correction inside the probe rather than quietly applied.

Then the wall itself. Two runs of the frozen operation on one restored
pre-state leave archives differing by a handful of bytes, the counts printed by
the diagnosis rather than quoted from memory. The freeze forecast
the directory inode inside `freshDirStamp` as the un-coverable residue;
measurement eliminated it: the directory inodes and the propagated file's
inode come back identical, and so does its mtime once `-times=true` is
added — a qualifier worth keeping, since the shipped argv carries no
`-times` and its propagated mtime does differ. **The residue is recorded
as unattributed**, with the four eliminated hypotheses named, because a
fifth would be a guess and the verdict does not depend on it. `-times=true` was measured purely
to answer whether amending the frozen argv would buy determinism: it does
not, so no amendment is proposed. Cost: one transcript, zero defines.
Condition 8 meanwhile passed cleanly for unison too — with the profile
landing the copy stub on its read/write fallback, every in-root mutation
is interposable — and condition 9 counted 62 kill points, a rich interior
the cohort will not get to use.

Three harness defects surfaced along the way, all of the same family:
- An interrupted edit truncated `run-unison.sh` mid-block, deleting the
  whole round-trip check and leaving only comment lines. **The result was
  still valid shell**: it would have run, judged one condition fewer, and
  printed "conditions failed: 0". That bought `check-transcript.sh`,
  which compares the verdict names emitted against the names the plan
  requires and now closes every transcript. It is falsified four ways
  (deleted verdict, renamed verdict, and an extractor control) and its
  own first cut used sed's `\|`, a GNU extension that matched nothing on
  the macOS host — caught by that same extractor control.
- The round-trip check compared the whole state root and went red while
  the tool printed "Nothing to do"; unison rewrites its archives and
  appends to `unison.log` on every invocation, which the freeze's own
  expected-artifacts line already said. It also compared against run A's
  snapshot when the re-run starts from run B's. Both fixed; the scan for
  the same class across both probe scripts found no other comparison
  whose unit was wrong.
- Condition 8 first reported a wall for unison whose own numbers refused
  to add up — `interposed=9` against `unmatched=21`. The harness was
  passing `LD_PRELOAD=pin-getpid.so` into the preflight invocation, which
  **replaces** the visibility logger preflight had just installed, so
  unison ran with no interposer at all. A FAIL can be the harness, and
  the way to tell is that its own numbers disagree with each other.

## 2026-08-23 — cohort 4 begins: the freeze is a fill-in, and one of its citations turned out not to exist

Entry opened at the start of the work, per the contract. The slate has
been signed off since 2026-08-22 (himalaya and vdirsyncer, two slots, the
remaining primaries and the whole bench deliberately empty), and
`PROTOCOL-DRAFT.md` says the freeze should be a fill-in rather than a
write. Two of its three blocked sections unblock with the target list
(per-target probe plans, versions and image); the third (claim reading)
unblocked when #231 merged. So the work here is: scout rows for the two
targets, the image with its freeze-build transcript, the probe plans with
fixture bytes inlined, and the freeze itself.

Division of labour, set today by the owner: this session owns the freeze
and everything downstream (probes, defines, explores); a peer session
supplies the measured scout rows (rules 1-3 and 11-17 receipts, the
novelty pre-scans, write-path readings from public source, checker
sketches), all target-non-contact, delivered on a local branch, with
BUILDLOG left to this session so the head cannot collide (the #238/#231
lesson).

First finding of the day, before any new measurement: **the himalaya
write-path determination this cohort has been leaning on is not on
main.** The 2026-08-22 reading (io-maildir's std driver,
`fs::rename`/`fs::write`, no fsync, the tmp-then-new two-stage window,
static distribution) was made in a session and recorded in workspace
memory, but a grep for its terms across every committed .md and .txt
returns zero lines. A freeze cannot cite a chat. The row was re-derived
from public source and committed like vdirsyncer's: the E4 register row
again, in a new costume. A determination that never became a diff was
never checked as one.

Image plan, decided in the morning: trixie-slim with the apt layer pinned
by build, artifacts fetched host-side against the TLS-intercepting proxy
(the cohort-2 measurement, unchanged); rust 1.98.0 from the same
channel-manifest pin cohort 3 used (the tarball is still in the local
cache and re-verifies against the published sha256); **himalaya built
from the v2.1.0 source tag inside the image**, because the distributed
binaries are static cross-builds the shim cannot enter, so the measured
binary is a self-build and the freeze says so in the versions section,
with the crate closure vendored host-side by `cargo vendor --locked`
against himalaya's own committed Cargo.lock; vdirsyncer at its current
stable with a uv-generated hash lock, the cohort-3 pattern verbatim.

**Same day, and the paragraph above is already stale on one word: the
slate lost vdirsyncer to its own measured row.** The scout rows this
cohort demanded (rules measured, not recalled) came back from the peer
session and failed vdirsyncer on rule 2 (three commits in the six-month
window, all typo/docs/CI), rule 3 (one author in that window), and rules
11/17 (one of its six recent bug reports answered within a week, the
committed row's figure; the peer's first chat message carried a different
count from an earlier cut of the same measurement, this entry briefly
copied it, and the committed transcript outranks the chat, the E4 failure
in miniature, caught by the digits check run early). The checker anchor
the slate had assumed, `repair`, sits behind an interactive
`click.confirm` (re-verified here from the fetched wheel before gating on
it). The 2026-08-22 sign-off was made on rows that had not been measured
to the brief's standard; the measurement outranks the sign-off. Owner
ruling (2026-08-23, AskUserQuestion, both halves): **vdirsyncer is
dropped, and the second slot is re-scouted before the freeze lands**; no
single-target cohort, no promotion clause in the freeze. The FAIL row
stays committed with its transcripts; the rejection table is the audit.

The himalaya half of the freeze filled in meanwhile, and picking the
operation settled on the arm the write-path reading singled out:
**`maildir messages copy` is the one io-maildir arm without a tmp stage**.
The destination is created at its final path and filled in place
(`entry/copy.rs`, the I/O at `client.rs:227` `fs::copy`), so every
intermediate state is a visible message in the target folder. save and
move rename; copy exposes. Two rule-16 forecasts came out of reading the
same sources, each with committed apparatus the probe must first show red
without: minted entry names embed the pid
(`{secs}.#{counter:x}M{nanos}P{pid}.{hostname}`, entry.rs:48-56, via libc
getpid at client.rs:239), answered by `pin-getpid.c` loaded the
libfaketime way; and `fs::copy` prefers `copy_file_range`/`sendfile`,
both of which the oracle reports as unsupported (the hg-r2 precedent,
oracle.zig's own test), answered by `seccomp-enosys.json`, which lands
std on the libc read/write loop the shim exports. The kill window needs
neither: the destination exists empty before any bytes move, so strace
fault injection reproduces the torn state against the stock tool under
every copy mechanism.

**The re-scout came back one-for-five, and the owner closed both open
questions in one gate (2026-08-23, AskUserQuestion).** Homebrew fell on
rule 5, trash-cli and pipx on rules 11/17, CocoaPods on rule 3; **unison
survived rules 1-15**, entering on a strong rule-3 row (two contributors
at comparable weight) and a writer that leaves a commit log for exactly
the window this engine crashes into. Rulings: **unison takes slot 2**,
and **himalaya stays on `messages copy` with the seccomp profile as the
ruled lift**. The peer's correction had meanwhile shown the copy arm
invisible to the shim's 52 exports (`fs::copy` reaching
`copy_file_range`/`sendfile`), and the profile turned out to be the one
apparatus that lifts *both* targets' copy walls, because seccomp filters
at the kernel boundary and cannot be dodged by the `syscall(3)` spelling
unison uses (copy_stubs.c:199) or by the weak-symbol route std uses. That
taxonomy (inline instruction / `syscall(3)` / weak lookup, three
mechanisms the old wall table read as one) is now a row in
`docs/target-classes.md` and roadmap #244: the shim-side lift, an export
plus the oracle op class it would also need.

The unison determinism reading (peer, from source, line-numbered in
`SCOUT-ROWS-SLOT2.md`) found the preference that actually removes inodes
from the archive is `ignoreinodenumbers`, *not* `fastcheck`, and found
the hazard the preference does not reach: **`freshDirStamp` folds
`(gettimeofday + √2·getpid)·1000 + the directory's inode` into one
archived number** (props.ml:1575-1585). faketime and `pin-getpid.c`
cover two of the three terms; the directory inode has no apparatus, so
the freeze names it honestly as the residue the probe's two-run
comparison measures, a possible nondeterministic-writer wall, priced at
one transcript. The same reading flagged that a frozen clock can flip
`Fileinfo.unchanged`'s equal-second branch (a one-second sleep and a
forced "changed" per file, fileinfo.ml:246-249): the apparatus changing
the target's behaviour, to be measured at the probe rather than assumed
away. `seccomp-enosys.json` gained an arg-filtered ioctl rule (ENOTTY for
FICLONE, value 0x40049409, everything else untouched) so the reflink arm
fails by construction instead of by trusting the container filesystem.
The image now builds both targets from commit-pinned trees (unison
because upstream ships no aarch64-linux binary at all; nine release
assets read, macOS arm64 only) and the freeze-build transcript comes from
a single --no-cache build so every quoted line is from one clean build
rather than from cache hits of the vdirsyncer-era layers.

**The first-sight review came back BLOCK, and its P0 was real: the
unison sign-off rested on a misreading of the recovery path.** The rows
and this entry had said the `DANGER.README` commit log is "replayed
mechanically by the next startup". The pinned source says otherwise,
verified here by direct read before gating: `processCommitLog`
(files.ml:70) detects the file and raises Fatal, instructing the user to
inspect the named files, delete the notice, and run again; the notice
itself (files.ml:30-46) says the same. No replay exists. Owner re-ruling
(2026-08-23, AskUserQuestion, on the corrected facts): **unison stays**,
with the checker's recovery defined as following the tool's own written
instruction (the one deletion, the single non-tool action) and then
re-running the tool for the assert, and with the Fatal refusal itself
used as a tool-command assert leg. Third pre-define catch of the same
shape: papis `doctor`, vdirsyncer `repair`, unison replay. The reviewer's
sweep also caught the peer's files.ml call-site line numbers coming from
a newer revision (a 21-line insertion upstream of renameLocal shifted
the citations below it by +21 while the rest sat unchanged, so each was
re-pinned individually by grep against the v2.54.0 tree; a bulk offset
would have broken the unchanged ones), a four-not-three count in the
vdirsyncer rule-11 prose
(#1207 also drew no non-author comment; the committed transcript already
said so), and a bug-set "fastest" figure that belonged to a non-bug
issue. Four of the reviewer's own line numbers were themselves off by
one (:27/:69/:83 and a NEWS.md:169) and were rejected against grep -n
output before any edit: the reviewer's numbers get the same verification
as anyone's.

The review's remaining structural point was that the image gates had
only ever been seen green. Every pin and assert in the Dockerfile and
fetch-artifacts.sh is now shown red once against a synthetic mutation
(`guard-reds.txt`): both tree-digest checks (one flipped hex character
each), the ldd dynamic-linkage assertion (a static hello), the commit
pin (flipped hex in the pinned SHA), and the download sha pin (an
uncached name pointed at a small real file). Two misfires during that
work are kept in the transcript because they are the register working:
the first mutation targeted a variable the rewritten script no longer
has and came back green (a green falsification is a broken falsification
until proven otherwise), and one raw rc was first read through a pipe
and said 0 while FAIL printed, the C1 row stepped in again. LC_ALL=C now
pins the digest sort collation on both sides (host and image digests
re-verified unchanged), and the digest's scope is stated where it is
computed: file contents and names, not symlinks or modes (zero symlinks
in both trees, measured).

Also today, relayed by the session that owns upstream reporting:
**poetry #11019 drew its first comments and was closed not-planned**, so
rule 11 has now been tested on a report of ours exactly once, negatively.
`spike/upstream-report-status.sh` gains the fifth row so the measuring
device stops being blind to it, and the freeze's Reporting section gains
the lesson as a requirement: measure the recovery paths outside the tool,
and when they fail, before reporting (for himalaya, what is lost before
it reaches the synchronized side; for unison, whether damage propagates
to the healthy replica, which would break the external recovery path
itself). A note for cohort-5 selection, not this slate: poetry's manifest
survives corruption because users keep it in version control, a
recoverability class rule 5's current wording does not capture. And the
owner's punctuation ruling (relayed and scope-confirmed today) applied
to everything written today: em dashes are gone from this cohort's new
files; older entries and the verbatim ADR 0020 quotation stay as
written.

## 2026-08-22 — the rejections were thinner than the funnel implied, and six were re-judged

The cohort-4 candidate funnel went out with two numbers I had not counted
and one stage that was not a stage. Recounted from the file the enumeration
actually wrote: 159 unique repositories, not 163 rows; the language wall
forecast removed **128**, not the 64 I reported (that figure was Go plus
TypeScript plus JavaScript and omitted Shell, PHP, Java, Swift, Kotlin, C#,
Nix and six more); and the "~50 left" was never computed — it was written to
keep the column continuous. The owner's audit derived ~89 rejections at the
rules-4/5/7 stage from those numbers, which was correct arithmetic on a
wrong table: the real figure is 31 in, 22 rejected, 2 set aside, 3 unread,
4 already measured.

Worse than the counts: **no project was read at that stage.** Every one of
the 31 was judged from the search result's own one-line description plus
recollection. The brief this cohort runs under says a candidate row missing
a measurement is an incomplete row; by its own standard the whole column
was incomplete, and I had written the word "read" over it.

**Owner rulings that close the selection (2026-08-22, recorded at the moment
they were made rather than when the freeze is written — the contract in
CLAUDE.md).**

- **Rule 9 is pinned to reading (b): a checker must go through the target's
  own commands.** The alternative — reading a plain-text store directly —
  was declined. The precedent held: every cohort-2 and cohort-3 checker went
  through its target's commands. **No exception clause for neomutt**, which
  was offered and refused.
- **The slate freezes at two: himalaya (Rust) and vdirsyncer (Python).** The
  remaining three primary slots and the bench are deliberately not filled.
- **neomutt therefore drops on rule 9**, and it is the only candidate in
  four cohorts to fall to an interpretation rather than to a measurable
  wall: its write path was measured visible (libc `open` + `rename`, no
  mkstemp) and its batch mode measured to write into the judged maildir, and
  neither fact saved it, because it has no non-interactive read-back for a
  checker to use. himalaya has `envelope list` / `message read` and
  vdirsyncer has `repair`, so neither needs the reading that was refused.
  The freeze will carry that record rather than only the outcome.

Worth keeping beside those three: the candidate that moved three times today
moved on my reasoning each time, never on the target. neomutt was rejected
on rule 8 (wrong — batch mode is a first-class mode in its own man page),
returned to the pool with both open questions answered favourably from
source, and then dropped on rule 9. The target never changed.

**Third pass, same day: the two rows left on a judgment were read from
source, and one of them changed the slate.** neomutt returns to the pool
with both of its open questions answered favourably — send/send.c has an
Fcc branch guarded by SEND_BATCH ("Printed when an Fcc in batch mode
fails"), so a non-interactive invocation with a local `record` writes into
the judged maildir; and maildir/message.c opens the temp file with plain
`open(path, O_WRONLY | O_EXCL | O_CREAT, 0666)` and moves it with
`rename()` — libc, no mkstemp, which is the question today's #39
measurement made cheap to ask of any C candidate. What holds it back is
rule 4 (the primary interface is a TUI — a judgment reading cannot settle)
and rule 9 (no non-interactive read-back, so a checker would read the
maildir rather than use the tool). It brings the language the slate lacks.

calcure's rule 8 was simply wrong, not merely unproven: `--task` and
`--event` both add and exit. But calcure/savers.py then argues against the
slot better than my rejection did — every row is written to `<file>.bak`
and moved with `Path.replace()`, so **no window loses the user's tasks**,
and the forecast is PASS with `.bak` noise in the judged root. Overturning
a rejection and finding the target uninteresting are different results, and
this pass produced the second.

The three unread rows closed too: yadm is a `#!/bin/sh` script whose writes
run in git children (the pass wall, #123 — GitHub's "Python" is its test
suite), and bob and proto keep re-downloadable toolchains, which is not
primary data. proto's user-authored `.prototools` is the only part worth
revisiting if slots stay empty.

Slate after three passes: himalaya (Rust), vdirsyncer (Python), neomutt
(C) — three languages, all multi-file coherence, **two primary slots and
the whole bench still empty**. The population argument is unchanged: 128 of
159 enumerated repositories fell to language wall forecasts, and both walls
doing that work are scheduled after v1.0.

The owner's instruction was to re-judge the thin rejections against primary
sources, reading only. Six rows, and the results split:

- **pnpm** — upheld, and now on the project's own sentence: the README
  calls the Rust port experimental, so the shipped CLI is still the Node one
  and the thread forecast applies to what rule 12 says to measure. The doubt
  was real (Rust is the majority language by bytes, with a genuine
  workspace); the answer happened to be the one I had guessed.
- **neomutt** — my rule was **wrong**. "Batch mode" is a first-class mode in
  neomutt's own man page, -e/--command runs commands after config, and draft
  files on stdin are documented as processed identically in batch and
  interactive mode. Rule 8 does not fail. The rejection now rests on rule 4
  — the primary interface is a TUI — which is a judgment about the word
  "primary", recorded as one.
- **ArchiveBox** — my rule was **wrong** in the other direction. The primary
  data is files under the archive directory; the project itself calls its
  SQLite file "your index", so rule 7 passes. It is still rejected, on rule
  4 (five interfaces, browser extension listed first) and more strongly on
  rule 16: the archiving is done by Chrome, wget and yt-dlp — child
  processes writing the state, which is the pass wall (#123).
- **TrendRadar**, **ffsubsync** — upheld, bases upgraded from a search
  summary to the projects' own READMEs.
- **calcure** — **weakened to uncertain.** Its README documents
  argument-driven task and event adding, so rule 8 is unproven; rule 4 is
  the likelier objection. One wiki page would settle it and this pass did
  not open it.

Zero rejections were fully overturned, which is the least interesting part
of the result. The interesting part is that two of them now stand on a
judgment rather than on a rule a measurement can settle, and the owner can
see which.

Two process notes. The register's E4 check — grep the diff for digits and
open the primary source for each — is bound to *diffs*, and the wrong funnel
went out in a chat message, which is not a diff. The check never fired. And
this log's first draft backticked upstream repository names, which is
exactly what acceptance check 11 extracts as repository paths; the
convention `docs/target-classes.md` already follows is now followed here
too, with a note saying why.

## 2026-08-22 — #231: the overall earliest and the claim exhibit are two different things

Entry started before the first line of code, per the contract. The
poetry pair proved that "the run's saved case = the earliest violating
world" promotes an engine implementation detail — one case per run —
into a scoring rule: poetry's lock-first write shape puts an L0-only
precision-limit world structurally ahead of the real checker-red
manifest destruction, and the exhibit slot was already taken. The fix
is to separate the two roles the single case has been playing.
**Overall earliest stays exactly what it is** — the first physical
counterexample, `earliest` in the report, `cases/000001.json` on
disk, every existing consumer untouched. **The claim exhibit becomes
its own thing**: the earliest world whose violation includes the
declared checker, tracked by the invariant bits at world-judgment
time (never by parsing the invariant string), saved as its own case
when it is a different world, and reported as `checker_earliest` —
the `earliest` shape plus its own `case` and `replay` inside, absent
when no checker-red world exists. The write order is fixed (earliest
first), so 000001's owner never changes; if the earliest case cannot
be written, the checker case is not written either, keeping "000001,
when present, belongs to the earliest" as an invariant. Plan R1
measured one assumption dead before it shipped: acceptance's check-4
FAIL fixture runs without `--check`, so a checker-red world is
structurally impossible there and the fixture change is definite
work, not a contingency — with the `--oracle` kept, because the same
fixture feeds the `ov_pin`. (Decisions recorded as they land; the
mutation drill's result is appended below when it runs.)

Two decisions from the implementation itself. The regression toy's
first draft used the existing `write_file` helper, whose `fsync` is
itself a kill point — six crash points instead of the declared four,
with the exhibits at k=2/k=5 instead of the declared k=2/k=4; the toy
now does raw open/write/close so the committed check asserts the
numbers the design named. And the replay leg of the new acceptance
check initially invoked `sideeye replay` bare: a case carries the
define but not the environment, so the fresh recording would have run
the toy's ordinary rotate instead of the split rewrite and refused
with `case_no_longer_applies` — the env rides the invocation, as it
does in every other env-driven toy check.

The three falsification drills, run and measured (all 2026-08-22).
**Pre-change binary** (origin/main in a worktree) against the new toy
and checker: FAIL 2 of 5, earliest k=2 L0-only, **no
`checker_earliest` field, one case file**. Red on that binary, named
rather than totalled (this PR's R1 caught the first draft's "every
new assertion" — six of check 4c's assertions are about the old
behavior and stay green on the old binary): the two
`checker_earliest` field pins, both case-ownership pins on the
second file, the `checker red` text grep, five of the replay leg's
six assertions (the sixth — the replayed-path equality — compares
two empty reads against the old binary and is vacuously green
there), and the same-world control reads as they stood at drill time. **The schema pin, both directions, raw rc**: the new
doc against the old binary's four-report corpus exits 1 with
"documented but never generated" naming all nine `checker_earliest`
rows; the old doc against the new binary's corpus exits 1 with
"generated but not documented" naming the same nine. (The first
measurement of side (a) read the rc through a `head` pipe and printed
0 beside the red message — the exact pipe trap this workspace has on
record; re-measured bare.) **The write-order mutation**: a scratch
mutant writing a checker-world case before the earliest's was built
and run against the committed check 4c; exactly the two ownership
assertions broke — `case: .../000002.json, wanted .../000001.json`
and `checker_earliest.case: .../000003.json, wanted .../000002.json`
— so the 000001-owner invariant is measured by assertions that die
when it does, and the mutant was reverted from the committed base.
## 2026-08-22 — the register was ten measurements behind the measurements

`docs/target-classes.md` says what "supported" means — "supported classes
are exactly the rows of the first table below" — and PRD's UNKNOWN-rate
criterion takes the word from there. It listed thirteen tools, all of them
from the blind campaigns and the assisted cohort. **None of cohort 2's
five and none of cohort 3's five were on it.** Two cohorts of measurement,
closed and recorded in their own RESULTS and RUNLOG files, never reached
the page that summarises what has been measured.

Backfilled here, in the shape the page already uses. Six verdict rows —
Mercurial (FAIL 73/107, all L0-only, contract held 107/107), Borg (FAIL
3/119, same shape, under declared pins), black and rustfmt (FAIL 1/3 each,
the same in-place tear in two languages, both already on their trackers),
poetry (FAIL 2/5, not a candidate because the earliest world is L0-only,
with the checker-red world behind it reported as python-poetry/poetry#11019),
papis (PASS 2/2, the contrast case). Three refusal rows — jj on static
linkage, Bun on threads, cargo on the raw-syscall rename. And one new
section for a distinction the page could not previously express: KeePassXC
never reached a define, because the engine-free probe refused first on
determinism and on 7 unattributable calls. Calling that an engine refusal
would have been a claim about a judgement that never happened.

Two consequences worth stating rather than leaving to be noticed. The
supported set grew by six rows today, so any sentence elsewhere that
counts supported classes is now stale. And `docs/unknown-rate.md`'s
A-group is defined as *every committed, runnable define in the repository*
while its sweep ran on 2026-08-16 — before both cohorts, which have since
committed **16** further defines, several of which reach named refusals
rather than verdicts. That page now carries an as-of note saying so. The
threshold is unaffected: it is set from B-group only, and no cohort-2 or
cohort-3 target is in B-group. Re-running the A-group sweep is filed
separately rather than done here, because doing it inside a documentation
change would bury a measurement in a backfill.

One row on that page was not stale but empty, and it is filled here by
measuring rather than by moving text. `#39` — libc functions that mutate
state through internal calls — carried "no recorded run for any of these
members" since it was filed. Two members are now measured
(`spike/cohort4/mkstemp-class.txt`, on a new toy written for it), and both
are invisible in the way the mechanism predicted. The canonical C
atomic-replace idiom, `mkstemp` + write + fsync + rename, has its
**creation** performed inside libc: the kernel issues
`openat(..., O_RDWR|O_CREAT|O_EXCL, 0600)` in the state root and the
interposer records no `open` for that path. The control is in the same
run and needed no arranging — the write and the fsync on that same temp
file *are* visible, because the program issues those itself. `dprintf`
behaves identically (its `open` is visible, its write is not) and
`tmpfile` left nothing inside the root.

This one matters for cohort 4 before selection rather than after: a C or
C++ target whose atomic write goes through `mkstemp` hits the same wall as
cargo's raw rename, and the idiom is the one a careful C program is
*supposed* to use. `preflight.sh visibility` names it at probe time, which
is the whole point of having built the thing before the cohort rather than
during it — and this is its third falsification shape, distinct from the
raw-syscall toy and the libc-routed one.

Then the same-class scan asked which *other* documents summarise
measurements, and the answer was worse than the two being fixed. Searched
for any mention of cohorts 2 or 3 — by name, by issue number, or by target
— **`PRD.md`, `DESIGN.md`, `docs/kill-criteria-review.md`, `README.md` and
`docs/scouting.md` returned zero each.** PRD's criterion-1 status trail
stops on 2026-08-15 and closes with "what remains is the
novelty/confirmation/fix/replay work on the assisted findings", written
before the two campaigns that were run specifically to close that
criterion. The document that defines the v1.0 gate had no record of ten
targets measured against it.

PRD and DESIGN §17 gain those outcomes here — facts only, no criterion
re-scored — and the closing sentence is corrected to say what remains:
one finding that is novel, automatically discovered and provenance-clean
at once. `docs/kill-criteria-review.md` is deliberately **not** touched:
criterion 3 is scored there against collected data, the data has since
grown by ten targets, and its Row 8 names its own margin as one trial.
Re-scoring a met criterion inside a documentation backfill is exactly the
move this repository refuses; it is filed instead. README needed nothing —
it points at `docs/target-classes.md` rather than restating it, which is
why fixing the register fixed the README too.

**CI caught what the local checks did not: the as-of note broke a machine
check.** `docs/unknown-rate.md` carries a generated results block between
`<!-- unknown-rate:results:begin/end -->` markers whose own first line says
"do not edit between the markers", and acceptance check 12 compares it
byte for byte against `count.py`'s recomputation. The note landed directly
under the `#### A-group` heading — which `count.py` *generates* — so the
block stopped matching and the linux job went red on the drift gate. The
diff was one blank line.

This is the recorded class, happening to the person who wrote the register:
a prose edit moving an anchor that code reads. The fix is not to reword the
note but to move it out of the block entirely — it now hangs off the
A-group *definition* bullet, which is prose the generator does not own, and
says so in its last sentence. The generated block was then restored from
`count.py emit` rather than hand-repaired, and the diff against main is 11
added lines and zero deletions: no published number moved.

Two smaller things worth the ink. The local reproduction was available all
along — `python3 spike/unknown-rate/count.py check` prints exactly what CI
prints — and I did not run it before pushing, which is why a one-blank-line
error cost a CI round. And the first fix attempt was not enough: removing
the note left the extra blank line behind, and the check stayed red until
the block was replaced with the generator's own bytes. A gate that compares
byte for byte does not care which of two edits caused the mismatch.

Two claims of my own were caught by the pre-review check on numbers and
universals before this was committed. "On tools with millions of users"
was not measured anywhere — replaced with the star counts #209 actually
recorded. And DESIGN's arithmetic counted Borg twice, once as a probe wall
and once as the verdict that wall became when #200 lifted it: eleven
outcomes for ten targets. Now four walls that stood, one lifted, six
verdicts.

One measurement error of my own, caught by its own denominator: the local
replication of acceptance check 11 printed "1 slashed refs checked" for a
page with 46 of them. `for r in $refs` does not split on newlines in zsh,
so the whole list arrived as one string. The real check runs under `sh` in
the container and was never affected — but had the output not carried its
denominator, "0 missing" would have read as a pass. Re-run properly: 46
checked, 0 missing, with a planted bad path as the control.

## 2026-08-22 — cohort 4's preconditions, and the gate that caught its own author

This entry is late, and says so first: the contract in CLAUDE.md is to open
the entry when the work starts, and four commits of `spike/` landed before
a word of it existed. Written now, before the pull request, with the
reversal it would otherwise have hidden left in.

**What the work is.** Not a cohort — its preconditions. Every mistake
cohorts 1–3 paid for, mapped to the thing that makes it impossible rather
than merely noticed, plus the four gates that make some of those rows
mechanical. No target is named anywhere in it, deliberately: selection is
the owner's, and it comes after the engine change (#231) and the PROTOCOL
freeze that cites it.

**The reversal, which changed the plan.** The first draft read criterion
1's *author-confirmed* leg as the target's maintainer, counted four
upstream reports sitting at zero comments for 7–10 days, and concluded the
gate was blocked on other people. It is not. PRD glosses the phrase —
"this project's author judges the bug real, upstream confirmation is
sought, not required" — and DESIGN scored timewarrior exactly that way,
clean, with this project's own patch at PASS 25/25. `#140` never
contradicted that; its *Live candidates* paragraph just reads as though
the replies were the path. One clarifying line there settles it, and no
criterion changes. What is actually missing, counted from the record: no
single finding has yet been novel, automatically discovered, and
provenance-clean at once — timewarrior lacks the first, topydo and cohorts
2–3 the second, the assisted cohort the third. That combination is what a
fourth cohort is for, and nothing external stands between here and it.

**The exit rule, decided before the cohort rather than after it.** PRD's
default stands: no criterion-1 find, no v1.0, the kill analysis ships
instead. What the analysis should *conclude* on a null is deliberately
left open — with two facts recorded now so they cannot be discovered
conveniently later. A null fires none of §18's eight conditions (its
antecedent, "finds nothing beyond existing hand-written adversarial
tests", is contradicted by the record and `docs/kill-criteria-review.md`
says so), so the document will not produce a mechanical verdict. And the
two fallbacks considered and declined — pre-authorising an assisted-cohort
finding despite its red provenance, and re-measuring an assisted target
under the mini-seal (barred by the criterion's own text) — are written
down, so that choosing one later reads as a change.

**The gates, each falsified before being believed.**

- `spike/merge-gate.sh`. Three merges went out wrong in two cohorts — #184
  with the review fix unstaged, #194 with a red gate, #216 on "no checks
  reported" read as no failures — and they are one predicate now: at least
  one success, no failure, nothing pending, clean tree, local head equal to
  the PR's. Zero checks refuses; a zero denominator is absence of evidence.
  Self-test 7 of 7 against those three shapes and four more, plus a live
  run against a merged PR, which it refused for two independent reasons.
  It deliberately does not merge: chaining the wait to the merge is how
  #194 happened.
- `spike/cohort4/preflight.sh` + `visibility-logger.c` +
  `preflight-analyse.py`. Probe conditions 8 and 9, engine-free. Condition
  8 asks, before any define exists, whether every state-root mutation
  passed through a function an LD_PRELOAD shim can interpose — the
  question cargo answered only after two defines and two explores. On this
  repository's own toys: `toy.c` PASS, `toy_raw.c` WALL naming the
  unmatched `openat`, `renameat` and `unlinkat`. Condition 9 counts kill
  points; the libc toy reports 4. Stated in the header, because a green
  must be read correctly: the path-bearing classes carry the precision,
  and `write`/`fsync`/`ftruncate` are compared by count, catching a total
  bypass but not a partial one.
- `spike/cohort4/novelty-prescan.sh`. Cohort 3 spent black's slot learning
  that the novelty question belongs at selection, not after the verdict.
  Writing the script surfaced a trap worth the exercise: a space-separated
  query returns **zero** through this API — `disk` gives 30 hits against
  psf/black at `--limit 100`, `disk full` gives 0 — so the natural phrasing
  would have called every known defect novel. Multi-word terms are refused.
- `spike/upstream-report-status.sh`, because a table of dates nobody
  re-measures is indistinguishable from a table nobody re-read.

**The gate that caught its own author.** Running the pre-scan against the
two targets cohort 3 actually burned was meant to confirm it and found a
hole instead. psf/black's issues answer eight or more terms; but
`rust-lang/rustfmt#6041` answers exactly two, `disk` and `disk+full`.
Remove `disk` and rustfmt reads as novel — the one verdict the script
exists to prevent, missed by a margin of one word. So the term list is no
longer a matter of taste: it is derived from the titles of issues this
project has already had to find, and `--validate` holds it to them
(black#2479, black#5207, rustfmt#6041, 3 of 3), shown red by stripping
`disk`. Two smaller measurements from the same run: narrowing with
`in:title` is actively harmful — `truncate in:title` returns 0 against a
repository whose known issue plain `truncate` finds — and a broad term
saturates the page limit, four terms returning exactly 100, a floor rather
than a count, with only the top 20 by relevance listed. Saturation now
prints as SATURATED, counts are no longer summed, and the header says the
scan cannot prove absence. The exploratory full scans are not committed:
they were produced by the term list this run replaced, and a transcript
that does not match its script is worse than none.

**Re-read at PR-open, as the contract asks — and the same-class scan
found three defects in this change's own gate.** The scan's question was
which other lists here were chosen by taste rather than derived. The
interposer's function list was one: it omitted the shim's stdio flush
family (`fclose`, `fflush`, `fseek`, `rewind` and variants), which the
shim exports precisely because buffered bytes reach the kernel from inside
libc, past any PLT — #39's class. Any target writing through stdio would
have been called a false wall. The list now comes from `nm -D` on the
built shim, restricted to the mutating set.

Fixing that hid the second one. Descriptor classes were compared by count,
and once the logger emitted stdio flushes, its own 47 writes to stdout
swallowed the raw in-root write the positive control exists to catch — the
row went quiet while the verdict still read WALL from the path classes, so
nothing looked wrong. Descriptors are resolved through `/proc/self/fd`
now, and every class is compared path to path. That exposed the third:
path extraction keyed on the *class* read `write`'s payload as its path
and dropped every write, which showed up as a missing row and a kill-point
count falling from 4 to 3. Extraction is keyed on the syscall name.

After the three, the raw toy is flagged on all five classes with their
exact paths, the libc toy stays green, and the interior count is 4 again.
Worth stating plainly: two of the three were introduced by the fix to the
first, and only the self-test's own numbers showed it — the verdicts never
stopped being correct.

**Order, recorded so it cannot drift** (the owner's, 2026-08-22): the
BUILDLOG entry for #231 opens before its code; the engine separates the
overall earliest from the claim exhibit, tracking the checker-red class
from the invariant bits at world-judgement time rather than by parsing an
invariant's name; acceptance miniaturises poetry (k=2 L0-only, k=4
checker-red, overall earliest stays 2, checker exhibit is 4, the case for 4
replays) with the new assertion shown red once; that merges; **then** the
cohort-4 PROTOCOL freeze writes the new reading down; then targets. The
engine work is another session's, and this file waits on it.

## 2026-08-22 — cohort 3 leaves the language bar

The `.gitattributes` rule written when cohort 2 closed says "a closed
cohort belongs here; add its directory when it closes", and cohort 3
closed this morning, so `spike/cohort3/** linguist-documentation`
goes in. Measured rather than predicted: the cohort contributes
**123,757 bytes of shell across 38 scripts**, and GitHub currently
counts Shell at 359,264 bytes (37.1%) against Zig's 550,992 (56.9%);
excluding the sealed cohort leaves **235,507 bytes of shell — the
live harness, and only the live harness** (acceptance, the MCP
suite, the campaign driver, the rehearsal, the toy builders), which
is what the rule is for: hide the evidence, keep the maintained code
visible. The effect is display-only — checkout, diff, merge,
`verify-assisted.sh`, CI and code search are all indifferent, and
`linguist-documentation` does not collapse diffs the way
`linguist-generated` would.

## 2026-08-22 — the papis verify transcript: the sixth seal, and the ledger is shut

verify-assisted green on papis (define at 22cec73 strictly before
artifacts at 410def6, all four define files byte-identical). Six
sealed records across the cohort — black, rustfmt, poetry, poetry-r2,
papis, and the poetry pair's shared reading — every one of them a
question frozen on main before the worlds that answered it existed.
Cohort 3 is closed: five primaries measured, no bench promotion,
criterion 1 unmet, and the comparison the cohort was built for on the
record. What moves next is not another target in this cohort but the
three things it filed: the poetry manifest prospect behind the
upstream gate, #217's ptrace-grade observer, and #231's claim reading
for the next campaign's freeze.

## 2026-08-22 — papis passes, and cohort 3 closes

PASS, 2 of 2 worlds, crash points 1 + 1 baseline, single process,
reproduced identically twice — and the report matched the declaration
line for line, including the two things a PASS most needs to prove
about itself: it carried the **non-vacuous headline** (`2/2 explored
worlds satisfied the built-in atomicity invariant`, not "the operation
performed nothing that can change the judged state", which would have
meant the shim never saw the rename), and the metadata line disclosed
`fchmodat x1` as observed-and-excluded, exactly where the declaration
said the unjudgeable seam was. The falsification gate fired through
leg E before any world ran. `papis add` stages the whole document
outside the library and moves it in with one `renameat`; the only
crash world the engine can build is the library before the move.

So the cohort closes 5 for 5 measured, criterion 1 unmet, and the
record is the comparison it was designed to be: four tools that
rewrite files in place — black, rustfmt, poetry, poetry's revision —
and one that stages and renames, all under the same engine, the same
discipline, the same seal. What it leaves behind is worth more than
the verdict count: a live upstream prospect (poetry's manifest
destruction, sealed as a minimal reproduction), a named engine wall
with its after-1.0 issue (#217), a claim-reading design gap the poetry
pair exposed and #231 carries into the next campaign, and — from this
last target — a checker whose every leg came out of measurement that
contradicted intuition, plus the reminder that a rejection is only as
good as the invocation it was measured with.

## 2026-08-22 — the papis define: the target that has no interior to crash inside

The cohort's last define, and the first whose declaration expects a
PASS. Papis builds the whole document in a temp directory outside the
library and moves it in with one `renameat`, then `fchmodat`s it to
0755 — and chmod is not a kill point (`OpClass` in `src/contract.zig`
lists open/write/rename/unlink/fsync/truncate/mkdir/rmdir/link/symlink;
`src/oracle.zig` records chmod as *metadata observed*, disclosed and
not judged). So the engine-reachable crash set is a single world: the
library before the rename. An operation with one atomic mutation has
no interior. Declared as such, with the mode seam written down and
deliberately not asserted — restore flattens permission state, so a
mode leg would fail its own baseline (mercurial's `checkisexec`,
cohort 2, applied before the fact this time).

The checker came out of measurement, and measurement contradicted
every intuition I would have coded. Seven library states through
papis's own reader (`pre-define-trials.txt`): **`papis list` exits 0
in all seven** — an rc assertion would be a check that cannot fail; a
document directory with no `info.yaml` is **silently ignored**, so an
orphaned attachment is invisible to the tool; a document whose
attachment is **gone** is listed happily; and a torn `info.yaml` is
loaded with a **freshly generated random `papis_id` persisted back
into the damaged file** — the reader writes. That last one fixes the
checker's shape: every structural and byte assertion runs before the
reader, or the checker judges its own side effect. And `papis doctor`,
the obvious candidate for "documented recovery first", is measured
unusable as one: in a two-document library it falls to the interactive
picker and returns rc 0 having examined nothing, and where it does run
it reports three type errors **on the untouched baseline** and
auto-fixes zero of them. The rule is satisfied by having looked and
recorded that there is none — not by assuming one exists because the
command does. Drills eleven for eleven, attributed; most reds are
surgery-only shapes, rehearsed anyway because an unseen branch is not
a trusted branch.

**Corrected before merge, on R1's findings and one of my own.** The
paragraph above was right that doctor is not the recovery and wrong
about how I had shown it: the trials ran `papis doctor` with **no
selection flag**, so in every two-document library it fell to the
interactive picker and examined nothing — including state E, the
missing-attachment shape built *for* doctor's `files` check, which
therefore never ran once. The measurement was designed around a check
it then prevented from executing. Re-run with `-a`, doctor is worse
than impotent and the rejection is stronger for being fair: it is red
on the **untouched baseline** (six type errors over two healthy
documents, rc 0 while saying so); its one applicable fix prints
"[FIX] Removing file from document" and leaves `files: []` — the
library made consistent by **forgetting the lost data**, which the
cargo and poetry rulings already refused to call recovery; and on a
torn `info.yaml` **doctor itself dies**, rc 1 with an uncaught
AttributeError, which is precisely the damage a repair would exist
for. Four more corrections landed in the same round. **The
"reader writes" claim was unattributable** — the trials ran list, then
doctor, then doctor --fix, then list, and dumped the file once at the
end — so three states were added: no command run (no `papis_id`),
`papis list` alone (a `papis_id` appears — the reader is the writer),
and a second byte-identical torn state whose id came out **different**,
so "random" is now measured rather than asserted. **The mode-seam
argument had the right conclusion and the wrong mechanism**: restore
creates 0755 directories and 0644 files and never chmods, which are
exactly papis's post-chmod modes, so a mode leg is *vacuous* at this
umask and a *false-candidate generator* under a stricter one — not
"fails its own baseline", the shorthand I had carried over from
mercurial's `checkisexec` and was about to propagate to the next
define. **The checker had dropped the probe's entry enumeration**, so
a stray entry, a `probe-doc` that is a plain file, or a dangling
symlink named `probe-doc` (listed by `ls`, denied by `-e`) walked past
every leg; the guard now enumerates and the two legs that branch on
presence read that one answer instead of testing independently. And
the leg-R drill had to change with it: a third top-level document now
trips the guard first, so the drill became a document **nested inside**
`probe-doc` — measured: papis indexes the library recursively, so that
is a document no filesystem-level leg can see and only the reader
reveals. Drills went from eleven to thirteen. Two claims were also
walked back to what the record supports: the trials arrive *with* this
define rather than ahead of it on main (the scout is the part that
predates it), and "every branch rehearsed" is now stated as what a
count says it is — ten of the checker's twenty failure messages seen
red, per-leg red met, "every branch" not claimed. I wrote "nine"
there first, from the shape of the drill list rather than from a
count; the count is what shipped.

## 2026-08-22 — the poetry-r2 verify transcript: the fifth seal, and the papis off switch

verify-assisted green on poetry-r2 (define at 88447be strictly before
artifacts at 89e8ae2, all four define files byte-identical). Both
poetry records — the primary and its revision — now carry the
complete seal, and the pair is what #231 cites.

Scouted papis in the same window, at the slot RESULTS reserved for it
("3 in-process threads; no off switch measured yet"). Papis documents
one: `PAPIS_NP`, whose own docstring says setting it to 0 disables
multiprocessing on all platforms — an env pin, the free apparatus
tier. Measured with the probe's fixtures and the probe's predicates
(`papis/thread-offswitch-scout.txt`): default = 3 threads, 14 clone
lines, 14 pids; **`PAPIS_NP=0` = 0 threads, 0 clones, one pid**, rc 0,
document landed, read-back exact with the wrong-id drill at zero,
determinism green, closure clean. Both forecast legs assert rc and
landing, so a zero cannot mean "died at startup" — the
zero-without-a-denominator trap, closed in the harness this time
rather than in the prose. The write shape it exposes is the opposite
of the cohort's other four: papis builds the whole document in a
temp directory outside the library and moves it in with **one
`renameat`**, then `fchmodat`s the result to 0755. Two state-root
calls, the first atomic — so the expected verdict is a PASS, and the
one seam worth declaring carefully is the mode, which the engine's
restore flattens by design (the cohort-2 hg `checkisexec` lesson: a
checker that asserts a mode fails its own baseline).

## 2026-08-22 — the poetry-r2 verdict: the wound, sealed, and a rule for the next campaign

FAIL, 1 of 3 worlds, reproduced identically twice — the declared
shape to the letter: the empty manifest at crash point 2, combined
invariant, the whole documented recovery chain failing on a config
whose name and version died with the file, and **no noise world in
front** — the evidentiary contrast with the primary that this
revision existed to buy. Recorded and never claimed, per the
FAIL-freeze ruling the define carries on its face. Two additions
beyond the verdict. First, an outside reading of the poetry pair
(relayed by the owner) named the design gap precisely: the cohort
rule promoted the engine's save-one-case behavior into claim
eligibility, so L0 precision noise can mask a real checker red —
correct as cherry-picking prevention, odd as semantics, and
demonstrated cleanly by these two records. Filed as #231 for the
next campaign's protocol (earliest checker-red world as the
mechanical exhibit, or first violation per invariant class —
engine-side case saving plus a contract-freeze check as
preconditions), freezing before that campaign's first contact and
changing nothing in cohorts 1–3: applying it "before papis" was
considered and declined on the record — papis's rename-shaped write
has no maskable world, r2's disqualifier is the FAIL-freeze rule
(its earliest world *was* checker-red), and the only run it would
help, the primary's, is read-frozen. Second, the run-0 lesson from
the primary held: `--work` was mounted from the first run and the
case survived.

## 2026-08-22 — poetry revision 2: the operation that writes only the manifest

Owner ruling (same day as the poetry verdict, order explicit:
poetry-r2 before papis): take up the deferred revision question. The
revision changes the operation — `version patch` instead of
`add --lock` — which is not cargo-r2's apparatus-swap kind, and the
proposals say so up front: the primary's outcome was a claim-reading
structure (lock-first write order puts an L0-only world ahead of the
checker-red manifest world in every run), so the only way the
manifest wound can become an earliest case is an operation whose only
in-root write is the manifest. Measured before writing anything:
`version patch` works under package-mode=false, bumps 0.1.0 → 0.1.1
byte-deterministically, **leaves poetry.lock byte-identical** (no
lock syscalls; version does not participate in the lock's
content-hash — `check --lock` green after the bump), and mutates the
state root in exactly one truncate-plus-104-byte-write. The full
seven-condition probe harness was re-run for the new operation
(committed in the revision dir): conditions 1–6 machine-green, **0
threads, 0 clones** under venv-off — this operation spawns nothing,
cleaner than the primary. Drills nine for nine with the chain's every
branch re-rehearsed in this define's own state (branch rehearsal is
per-define, not per-copied-code — the heal branches are
engine-unreachable here and rehearsed anyway). Version-shaped novelty
round recorded (four terms, nothing named); the destruction round and
control carry over from the primary. If this define FAILs at the
empty-manifest point, the earliest case is checker-red by
construction — the first candidate-shaped prospect of the cohort
where the claim reading and the write shape point the same way.

**Reversed by R1 before merge — the candidacy was never available.**
The frozen charter's own bullet, the one sentence the first draft's
citation skipped: "a FAIL freezes the define — later revisions cannot
produce a criterion-1 claim for that target" (cohort 2's original
adds the reason: the question would no longer precede the answer;
only refusal and UNKNOWN iteration stay free). Poetry reached its
FAIL verdict before this revision existed, so nothing r2 measures can
be a candidate, and the paragraph above was written by an author who
had read the revision mechanics around that sentence and not the
sentence itself — the same selective-citation shape the novelty scan
lesson warned about, one layer up. Owner ruling, on the record in
proposals.md before the freeze: measure r2 to the end as a **sealed
minimal reproduction for the upstream conversation** (one crash
point, one world, checker-red through the whole documented chain —
no noise world in front), recorded and never claimed; criterion 1
moves to a cohort designed with both poetry lessons — write order
and the FAIL-freeze — in front of the first contact. R1's three P2s
also landed before the freeze: the toml's probe-configuration
sentence had inverted the primary's careful disclosure (main legs
ran venv-ON; venv-off is a third delta, promoted from the forecast
leg), the static "124/137 = timeout" legend in the chain-fail red
collided with the frozen apparatus reading (the candidate-shaped
message would have carried the apparatus trigger tokens on every
ordinary red — now the annotation is conditional on the step's
actual rc), and the pass drills printed only their fragment line,
leaving the healing step unattributable from committed evidence (now
full output).

## 2026-08-22 — The scouting guide stops legislating target selection

docs/scouting.md is the public method page, and its "must never" list was
carrying this repository's own governance dressed as method: the ≥500-star
liveness bar, the human sign-off before measured contact, and the flat "a
dormant project is not a legitimate target at all". Those rules decide
which third parties *this project's experiments* touch and who signs off —
they are recorded, with their history, as the owner rule in
`spike/assisted/PROTOCOL.md` — but a reader pointing Sideeye at their own
dormant tool, or a fork they maintain, is squarely inside the tool's
purpose, and no guide sentence should say otherwise. The page also broke
its own opening rule: the intro says numbers on a guide page go stale and
belong in the records, and the one number on the page was the star bar.
The dormant-target bullet is deleted; the upstream-filing bullet keeps the
part that is genuinely method — reporting is decided at selection, not at
discovery — and now says plainly that the bar and the sign-off bind this
repository's experiments, not the reader. Prompted by the owner asking
whose rules those were.

## 2026-08-22 — the poetry verify transcript: the fourth seal

verify-assisted green on poetry (define at 75b3d19 strictly before
artifacts at f35bf72, all four define files byte-identical;
`verify-transcript.txt` committed beside the ruling). The seal
matters more than usual here: this is the target where the frozen
claim rule refused a claimable-looking number, and the sealed order
proves the rule predates the worlds it refused — the chain ruling,
the moved prospect and the claim reading were all on main before the
engine ran. One target remains: papis.

## 2026-08-22 — the poetry verdict: the rule refuses the number I wanted

FAIL, 2 of 5 worlds, reproduced identically across three runs — and
**no candidate**, because the run's earliest violating world is the
empty lock: L0 red, checker healed (chain step 2 brought it back
green, with poetry's self-prescribing step-1 failure observed in a
real crash world for the first time). The checker-red world is real —
crash point 4 empties user-authored `pyproject.toml` and the whole
documented chain fails on the result — but the write shape puts the
lock first, so the L0-only lock world owns "earliest" in every run of
this operation, and the frozen claim rule (earliest saved case must
have the declared checker as its violated invariant) reads the run as
recorded-not-claimed. This is the hg 73/107 shape again, one cohort
later, refused by machinery instead of willpower. The declaration's
miss, on the record: proposals.md predicted every world's behavior
correctly (A heals at step 1, empty lock at step 2, empty manifest
chain-fails — all confirmed by the engine) and still called the
manifest world "the candidate shape", reading only the checker column
and forgetting that L0 fires independently at an earlier crash point.
Candidacy is a property of the run, not of a world. Two smaller
things: run 0's cases were lost to `--work` defaulting inside the
discarded container (transcript and report retained and matching;
runs 1-2 re-measured with the work dir mounted — operator error,
recorded), and the deferred revision question (a manifest-only
operation like `poetry version patch` would put the checker-red world
earliest; new target dir, owner's call) plus the upstream-report
material (the stale prescription; the manifest wound) sit in
`poetry/RUNLOG.md` behind the standing gates. The cohort closes with
papis.

## 2026-08-22 — scout model sensitivity: the metadata gate checks presence, not truth (#221)

Measured whether the scouting method survives a weaker scout: the assisted
five re-scouted, paper-only, by four fresh agents under identical
conditions (Fable 5 control, Opus 5, Sonnet 5, Haiku 4.5 — protocol frozen
as #221 before the arms ran; record in `spike/scout-model-comparison/`).
Outcome: Opus ≥ the control ≈ the committed baseline (and it re-found
calcurse's measured FAIL shape as its P1, independently); Sonnet usable
with gate-catchable misses; Haiku below the bar — wrong determinism calls
on three of five targets, six of fifteen argvs undrivable as written, every
metadata field present throughout. Owner ruling: scouts run on Opus 5 or
better, Sonnet 5 is the measured floor; now stated in `docs/scouting.md`.

Two things this run paid for. First, the contamination probe before the
arms: the workspace memory index turns out to be injected into fresh
subagents, so the cohort-2/3 targets (walls named in the index) were
unusable for comparison and the assisted five carried a disclosed
existence-of-filing leak for calcurse and stow — disclosure was mandatory,
and all four arms located and quoted the same sentence verbatim. Second,
the grader-bias caveat is recorded rather
than solved: the grader is the orchestrating session, same model family as
the control arm, unblinded; the mitigation is that every judgement in
RESULTS.md anchors to committed text, and six load-bearing citations were
opened against the checkouts (six of six matched) before the tables were
written. The wrong-in-hindsight candidate to watch: opus's four
beyond-record findings are static claims — if one of them fails to
reproduce under a probe, the "exceeded the baseline" line above overstates
it by exactly that much.

## 2026-08-22 — the poetry define: the recovery that prescribes itself

Target 4, the first live criterion-1 prospect. The committed probe
strace pinned the write shape: `poetry add --lock` touches the state
root in four syscalls — **lock first, manifest second, both in-place
truncate-and-write** — so the reachable crash states are empty-lock,
new-lock-plus-old-manifest (the lock knowing a dependency the manifest
does not), and empty-manifest. Five engine-free trials fed each state
to poetry's own reader and its prescribed recovery, and they split the
world exactly where a property should sit: the between-writes state
**heals** — `poetry check --lock` names the fix ("Run `poetry lock`"),
and it works; the empty and torn lock states get the same or a worse
answer and **the prescription itself fails** (rc 1), leaving the
project stuck until a human deletes the lockfile — a step no error and
no document names. The drills then measured the punchline: the failing
`poetry lock` on an empty lock **prints "Regenerate the lock file with
the `poetry lock` command"** — the recovery prescribing itself while
failing. The pre-define novelty scan (recorded in proposals.md) found
no issue naming this recovery failure.

The checker follows the cohort rule to the letter: documented recovery
first — poetry prints its own, so leg R runs it exactly once when
check is red, and the prescription failing IS the red. The
green-heal-A drill pins the other side (state A must heal and end
green, with the transcript carrying the recovery line, so a checker
that never ran the recovery cannot fake the green). One wrong-leg
declaration was caught before commit this time, by applying the black
and rustfmt R1 lessons up front: an empty pyproject parses as an empty
TOML document, so it lands in leg R (invalid configuration, failed
prescription), not leg V — the declaration says so, with the trial
table beside it. Drills ten for ten, attributed.

**Reversed the same day, before merge.** R1's novelty-scan finding
(the recorded terms were corruption-shaped while the claimed-absent
finding was recovery-shaped) forced a re-scan with poetry's own error
text as the query — and "Regenerate the lock file" surfaced #1196 and
PR #6753: **the self-prescribing recovery failure was reported in
2019, fixed upstream (in 1.2.2 via backport #6759; main's fix shipped
in 1.3.0), and the fix's own test fixture is the unparseable "This
lock file is broken!"**. Poetry 2.0 then split the
command on purpose — bare `poetry lock` preserves (and so must read)
the existing lock, `--regenerate` carries the #6753 behavior — and
`test_lock_with_invalid_lockfile` pins both halves as intended.
Re-measured in-container: `--regenerate` heals the empty and torn
lock, rc 0, re-check green; on the empty manifest **everything fails**
— the name the rebuild needs was in the file the crash destroyed. Two
consequences, both frozen by an owner ruling before any engine
contact: leg R became a chain (prescription, then the documented
regenerate — a prescription-only red would be a manufactured
candidate that upstream answers with "intended"), and the live
prospect moved from the lock to the manifest: `poetry add` rewrites
user-authored `pyproject.toml` through the same in-place
truncate-and-write the formatter half died of, and no scan term
(destruction-shaped round recorded in proposals.md, control "cache"
2479) finds it reported. The stale prescriptions (`check.py:184`,
`locker.py:358,365` — while `installer.py:270` already routes through
a dynamic `_lock_fix_command()`) are upstream-report material behind
the owner gate, not a candidate. The near-miss to remember: the
original entry's "leaving the project stuck until a human deletes the
lockfile — a step no error and no document names" was **false** — 
`poetry lock --help` documents the way out, and only the second,
recovery-shaped scan was pointed well enough to break the story. The
drills went from ten to eleven — the two lock-red drills became
heal-through-regenerate greens, the empty-manifest red became the
whole-chain red, and one drill is genuinely new: the persistent-red
branch R1 caught as never-rehearsed, fabricated with a missing-README
state measured before the drill was written — every leg-R branch now
attributed by a branch-specific fragment instead of a shared "leg R"
tail. (R2 caught both of this paragraph's original numbers: "fixed in
1.2.2" without the backport attribution, and "ten to twelve" for what
is a count of eleven — the claims-from-open-sources rule, violated in
the very entry that records a narrative reversed by a better-pointed
measurement.)

## 2026-08-22 — the rustfmt verify transcript: the formatter half sealed

verify-assisted green on rustfmt (define at 9faf204 strictly before
artifacts at 8f33bdb, all four define files byte-identical;
`verify-transcript.txt` committed beside the ruling). Both formatter
verdicts — black and rustfmt, two languages, one wound — now carry the
complete seal: questions frozen on main before the worlds that
answered them existed.

## 2026-08-22 — rustfmt's verdict: the second language, the same wound

FAIL, 1 of 3 worlds, crash point 2 — the empty file, the declared tear
— combined invariant with leg V carrying rustc's own E0601, reproduced
identically twice, replayable case committed. Exactly black's verdict
in a second language, which was the point: the owner sent this target
through with its novelty gate already closed (#6041 has named the
surface since 2024) to buy the cross-language proof, and the engine
delivered it in three worlds. The formatter half of the matrix is
done: two languages, one non-atomic in-place write, both current
stables destroyed by a kill between the truncating open and the
write. Nothing filed upstream; the criterion-1 search moves to poetry
and papis, whose trackers name no crash-destruction surface in the
pre-scans.

## 2026-08-22 — the rustfmt define: measured with the answer's fame declared up front

Target 3 proceeds by owner decision (2026-08-22) with its novelty gate
already known closed — rust-lang/rustfmt#6041 has named the in-place
erasure surface since before this cohort existed, and the recorded
pre-define search sits in proposals.md. The define exists for the
ledger's completeness and as black's cross-language companion: same
class, same discipline, a Rust target. The checker differs from
black's where the language differs: leg V is rustc's own front end
(--crate-type bin, so the empty file — the engine-reachable tear, the
same one-truncating-open-one-write shape as black, probe strace lines
51-52 — fails V with "main function not found" rather than parsing as
an empty module), and leg E is a two-anchor byte comparison against
the frozen source and the probe-measured formatted output (Rust has no
stdlib AST to compare cheaply; both anchors are committed
measurements). Drills six for six, message-attributed; green-new
byte-matches the probe's anchor live.

## 2026-08-22 — the black verify transcript: the cohort's first FAIL under the full seal

verify-assisted green on black (define at 413cdb2 strictly before
artifacts at 32ae2fc, all four define files byte-identical;
`verify-transcript.txt` committed beside the ruling). The first
crash-world FAIL of the cohort carries the complete discipline: the
question — including the R1-corrected torn-file reading and the
empty-file drill — stood frozen on main before the world that answered
it existed.

## 2026-08-22 — black's verdict: the engine finds the right thing; the thing was known

The cohort's first full crash-world FAIL: 1 of 3 worlds, crash point 2
of 2 — after the truncating open, before the single write — the empty
file, exactly the tear the define's R1 forced into the frozen reading
and the `E-red-empty-file` drill rehearsed. Combined invariant
("built-in atomicity, and the checker"), oracle-verified, reproduced
identically three times, replayable case committed. A candidate shape
under the frozen reading.

Then the novelty gate did its job: the recorded tracker search
(positive control included) surfaced psf/black#2479 — open since
2021, "black in-place reformat wipes or corrupts target when disk is
full" — the same non-atomic write surface under a different trigger,
with the maintainer-endorsed temp-file fix now pending as
psf/black#5207 (opened 2026-07-01, after the measured stable shipped).
The candidate closes as not novel; nothing is filed upstream. What
stands: the sweet-spot thesis measured — define to checker-red verdict
in three worlds and minutes on the most-used Python formatter, finding
the defect class its own tracker needed five years to converge on. And
one inherited fact for target 3: that same thread names rustfmt as a
direct in-place writer, so rustfmt's novelty gate gets checked before
its define is written.

## 2026-08-22 — the black define: a formatter's in-place rewrite, the textbook shape

Cohort 3's second define (spike/cohort3/black), pushed before any engine
contact. The shape is what this tool was designed around: black rewrites
the user's source **in place** — no temp file, no rename (the probe's
root holds exactly probe.py before and after), and the write reaches the
file through libc (an interposing logger fired on `open64`, the same
2026-08-22 trial in which cargo stayed silent — named trial, the
explore's own recording re-verifies). The property borrows black's own
`--safe` contract and stretches it across a crash: the source must
survive as a program — it parses (leg V) and its AST equals the frozen
pre-operation program's (leg E). Both the unformatted old bytes and the
formatted output are green on both legs; the green-new drill proves the
AST equality live (black's quote normalization does not touch the AST).
The torn-file reading is declared ahead of any world — and the define's
R1 corrected its first draft before the freeze: the probe strace shows
the rewrite is ONE truncating open plus ONE write, so the
engine-reachable tear is the **empty file**, which *parses* (an empty
module) and fails **leg E**, not leg V as first written; a mid-token
tear (a partial write) fails leg V; either way checker-red, a candidate
shape — with no recovery leg, because black documents no crash recovery
and the source is the primary data (the cargo ruling's principle,
applied where no self-heal exists at all; no open decision fork, so
declared rather than gated). Drills six for six after R1 (the empty
file drilled as its own leg-E red), message-attributed.

Recorded here as promised: the previous batch's verify PR (#216) was
**merged while its CI reported "no checks reported"** — the watch
returned before the checks had started, and a chained
watch-count-merge command read pass=0 fail=0 pending=0 as "no
failures" instead of "no evidence". The post-merge CI came back all
green (transcript-and-BUILDLOG diff), so no harm — but this is the
#194 lesson in a new coat: zero is not a verdict without a
denominator, and merge stays a separate command from the poll that
justifies it. This batch's merges are issued only after a non-empty
check list shows failed=0.

## 2026-08-22 — the cargo verify transcript: a wall measured under the full seal

verify-assisted green on cargo-r2 (define at 24e773f strictly before
artifacts at 0fb9a73, all four define files byte-identical;
`verify-transcript.txt` committed beside the ruling) — the cohort's
first engine outcome, a two-layer wall, carries the same mini-seal
discipline the cohort-2 walls did: the question preceded the answer
even when the answer was a refusal.

## 2026-08-22 — cargo r2: the stand-in lifts one wall and finds another — the manifest rename never touches libc

The r2 explore got past the child-thread boundary (`single process` in
its report — the stand-in doing its job) and refused one layer deeper:
`oracle_missed_operation`. The oracle saw the manifest's atomic rename
(`Cargo.tomlI2K6rq` → `Cargo.toml`); the shim — loaded, recording the
operations on either side of it — had nothing. Diagnosis with a
committed transcript: cargo *imports* libc `rename@GLIBC_2.17`, so the
import table decides nothing (an earlier check that concluded "no
imports" had actually measured a missing `nm` binary — the
zero-without-a-denominator trap, caught before it was written anywhere
that matters); a minimal LD_PRELOAD logger interposing rename and
renameat, with python's libc-routed `os.rename` as the positive
control (fires), stays silent through `cargo add` while strace watches
the renameat reach the kernel. **The rename is a raw syscall.** The
two-witness design earned its keep: one witness saw what the other
could not, and the engine refused rather than judging blind.

Ruling (cargo-r2/RUNLOG.md): a named wall, terminal for the cohort —
the operation under study is invisible to a libc interposer, and a
ptrace-grade observer is engine architecture (the after-1.0 family of
#201/#202). cargo's slot closes with its torn-lock question asked and
not answered: the in-place lock rewrite, the parse-failure brick, and
the silent regeneration of an absent lock are all measured and
committed at the edges (drills, diagnosis, probe strace), but no crash
world could be explored to test them. The cohort order continues with
black — whose probe showed zero threads and zero children.

## 2026-08-22 — cargo r1 refuses on the forecast thread; r2 lifts it with a RUSTC stand-in

The first cargo explore refused as the define disclosed it might:
`UNKNOWN child_process_detected (clone3)`, reproduced on a second run
(`spike/cohort3/cargo/explore-r1-transcript.txt`; the reproduction's
machine-readable form beside it as `explore-r1-repro-transcript.txt`). The boundary is the
probe's forecast wearing a different name: the `rustc -vV` child's
internal thread arrives through a raw `clone3` carrying `CLONE_THREAD`,
which the oracle refuses (a thread past the pthread wrapper). A refusal
is not a FAIL — the define is not frozen — so the disclosed, owner-gated
option came due. **Owner approval (2026-08-22): a RUSTC stand-in**,
cargo's own documented configuration, in a new directory
(spike/cohort3/cargo-r2) per the mini-seal.

Measured before writing r2: with the stand-in, `cargo add` completes
rc 0, records the identical manifest entry, and the strace carries
**zero CLONE_THREAD lines** — the boundary gone, the remaining child a
thread-free /bin/sh. `cargo add` and `generate-lockfile` ask the
stand-in for `-vV` and nothing else; **`cargo metadata` asks for a full
target-info probe** (`--print=file-names ... --print=cfg`) and dies at
the stand-in — measured, and the reason the r2 checker carries `unset
RUSTC`: the apparatus reaches exactly the recorded operation, and the
checker's job is stock cargo's reader. Setup's cache-warm metadata call
went for the same reason (generate-lockfile alone creates both caches —
measured). The r2 drills run with RUSTC exported at the stand-in, the
way the engine's environment will carry it, so the green controls
double as the falsification of the unset line. Seven for seven,
attribution unchanged. Stock reproduction stays mandatory for any
finding: real rustc, no stand-in, strace fault injection.

## 2026-08-22 — the cargo define: manifest survival, asked before any crash exists

Cohort 3's first define (spike/cohort3/cargo), pushed before any engine
contact per the mini-seal. The property is **manifest survival**: kill
`cargo add --offline --path` anywhere and the project must still open to
cargo's own reader — leg V (`cargo metadata --offline` parses and
resolves), leg T (the dependency set is old-or-new: depcrate named zero
times or exactly once, metadata agreeing), leg C (source bytes
conserved). The deliberate omission: **no manifest+lock simultaneity
assertion** — the cargo book says the lockfile "is maintained by Cargo
and should not be manually edited", so lock re-sync is cargo's own job,
exercised by running its reader rather than legislated by the checker;
L0 still judges the lock's bytes. The rejected alternative (asserting
simultaneity) would manufacture FAILs out of cargo's documented
maintenance model.

Checker drills: six for six, each red **attributed to its intended
leg** — the drill asserts the checker's message names the leg it was
aimed at (a red from the wrong leg is a drill failure), which is the
mutation-killed-by-the-wrong-test lesson applied to checker
falsification. The torn-manifest drill red carries cargo's own parse
error; the leg-T red is depcrate named twice in *valid* TOML
(dependencies + dev-dependencies) — the one wrong-set shape metadata
happily resolves, so only T can catch it.

Ambient: CARGO_HOME outside the state root, warmed once by setup so
every world *finds* a warmed CARGO_HOME — shared and mutable across
worlds, deliberately outside the snapshot (borg-r3 put its ambient
inside the root; here the caches would be L0 noise), so cross-world
cache drift can only surface as an engine refusal, and that would be
the recorded outcome. The probe's forecast (the per-add `rustc -vV`
child and its internal thread) rides into this define as a disclosed
possible refusal too; the documented RUSTC override stays an
owner-gated option for a revision, not an assumption.

The define's R1 (fresh subagent) found the thing worth finding before
the irreversible step: **the likeliest FAIL shape — a torn Cargo.lock —
had no decided reading and no measurement.** Measuring settled it hard:
cargo writes `Cargo.toml` through temp+rename but rewrites `Cargo.lock`
**in place** (the probe strace had the evidence all along); a lock torn
mid-entry fails `cargo metadata --offline` with "failed to parse lock
file", rc 101, no recovery hint — while an *absent* lock is silently
regenerated, rc 0. My first tear measurement lied briefly: a 60-byte
truncation lands inside the lock's comment header and parses as valid
empty TOML, which cargo happily re-locks — the tear has to cut into an
entry to measure anything. **Owner ruling (2026-08-22): no recovery
leg.** Cargo's automatic maintenance already gets its turn by running
the reader (it heals an absent lock unprompted); a torn lock is the
state where that maintenance refuses to engage, so it is checker-red —
a criterion-1 candidate shape, with claim and report still behind the
standing gates. The `V-red-torn-lock` drill pins the measured behavior
in the committed transcript. Also from R1: the toml's "determinism and
closure for exactly this shape" overstated the probe (the probed
spelling differs from the define's — now named in the comment), and the
recorded dependency entry is now measured and printed by the drills
rather than forecast in a comment.

## 2026-08-22 — cohort 3 probes: five for five, and the bench stays seated

Drills re-proven on the new image, the synthetic positive control split
as required, then the five primaries: **all five hold probes with all
six machine-judged conditions green** — four on their first probe under
the frozen plan, papis under a plan amended after its first probe
failed (kept as papis-v1). First contact proceeded in cohort order, but
the committed transcripts are final-harness re-runs whose timestamps
are not (each header carries its own; all postdate the freeze merge) —
the first draft of this entry said "in frozen order" and the R1 review
caught the claim outrunning the committed evidence. The refill bench is
not activated either way: even reading papis's first probe as its
outcome, four primaries passed, and the rule promotes only below four.
Engine order stands: cargo → black → rustfmt → poetry → papis.

The probe phase earned its keep twice. First, **papis**: the original
plan's probe failed with a network traceback — `papis add` of a local
text file runs importer auto-matching, and the arxiv importer validates
the local PATH against arxiv.org over HTTPS, so a failed fetch fails a
purely local add (measured here as TLS verification dying under the
intercepting proxy — the network was reached; R2 caught this sentence
still saying "unreachable" after the reword landed everywhere else). No config filters the importer set (measured
in the source); `--from` skips matching structurally. One measured
amendment (metadata via a frozen YAML fixture and `--from yaml`),
recorded in the PROTOCOL with `papis-v1.txt` as evidence — the jj
pattern from cohort 2, again. Under the amended plan the determinism
condition also answered the open question: **the fixture's `papis_id`
pins it** — byte-identical libraries across runs.

Second, **cargo**, where a hypothesis died properly: an ad-hoc
measurement said a warm CARGO_HOME removes the `rustc -vV` child (zero
clones on the second run). Wrong — that second run was a **no-op add on
an already-edited manifest**, short-circuiting before the resolver ever
ran; the measurement did not reach the thing it claimed to measure. The
transcript's forecast loop uses a fresh pre-state per configuration and
shows the child (and its internal thread) in both states. So cargo's
define faces one vfork child per add whose thread the shim will observe;
the documented `RUSTC` override is recorded as gated apparatus, not
assumed.

Also measured: poetry's `add --lock` builds a virtualenv (threads) even
though it installs nothing — `POETRY_VIRTUALENVS_CREATE=false` takes the
thread count to zero with only oracle-accountable discovery forks left.
black and rustfmt run thread-free and child-free. papis carries 3
in-process threads, off switch unscouted. One harness anchor was
corrected mid-probe: bare `papis list` prints folder paths, so the
round-trip check now reads the document back through `papis list
--format` — papis's own reading — instead of grepping for a title in
output that never contains one.

The batch's R1 (a fresh context-free subagent again — Codex still out of
credits) returned three P1s, all adopted: the "in cohort order" claim
above (reworded to what the transcripts show); "unreachable network" in
the papis story, when what v1 measured was a *reached* network dying on
TLS verification under the intercepting proxy (reworded — any fetch
failure propagates the same way, but the claim now names the measured
one); and the cargo/poetry `thread_counts` lines printing `inconsistent`
without RESULTS saying so — the pairing assertion assumes only
CLONE_THREAD clones split into unfinished/resumed pairs, vfork splits
too, the machine judge refused fail-closed, and the thread facts came
from the raw logs and the clone-only forecasts (now disclosed, with the
lib.sh limitation named). Its P2s too: the positive control's gate was
fail-open (any red printed "control ok" — now gated on the determinism
verdict specifically, diff rc = 1, everything else green) and the
corrected papis anchor had never been red in its final form (it now
drills itself against a wrong id in the transcript). The affected four
probes were re-run under the fixed harness; black and rustfmt stand.

## 2026-08-22 — cohort 3 opens: the sweet-spot five frozen, with a bench that refills

Selection frozen in #209 before any contact: **cargo → black → rustfmt →
poetry → papis** under the owner's thirteen-condition ruleset (≥1k stars,
6-month activity, sustained contributors, CLI-primary, precious local
plain-file state, no transaction engine, non-interactive mutations,
self-checkable, probe-verifiable observability — plus the sharpened three:
≤1-week maintainer responsiveness measured on real issues, currently used
rather than legacy-only, language diversity). New over cohort 2: **the
refill rule** — a probe wall promotes the bench head (taplo → unison →
sc-im, re-qualified at promotion) until four targets have passed probes,
so a wall costs a transcript, not the cohort.

The plan's adversarial review ran into something new: Codex completed its
investigation (five interim reports, real repo cross-checks) and then the
provider's content filter blocked the final consolidated findings list.
The interim findings were recovered and each re-verified here before
adoption: the verifier lives at `spike/assisted/verify-assisted.sh` (the
plan had the path wrong); `PYTHON_KEYRING_BACKEND` needs the
fully-qualified `keyring.backends.null.Keyring`; black has an official
`--no-cache` (so the cache class is removed, not relocated); papis
auto-generates `papis_id`, so pinning time alone would not make its add
deterministic — the probe plan pins it via `--set` and lets the
determinism condition judge. The truncation is disclosed in the plan as
an honesty note: the findings list may be incomplete.

One defect in the cohort-2 record surfaced during that review and is
recorded here rather than retro-edited there: all five cohort-2 probe run
scripts call `mutating_paths` — a name the fail-closed closure rebuild
renamed to `closure_paths` — in their informational path listing, and the
committed transcripts carry the `not found` line. Display only; condition
6 was judged by `closure_check` throughout, so the verdicts stand. The
cohort-3 run scripts call the defined name.

Freeze-day measurements that moved the plan: the cargo-add manual
promises **manifest editing only**, so "Cargo.lock also updates" was
demoted from a frozen expectation to a measured observation; the Rust
combined tarball carries rustc/std/cargo but **not rustfmt** (channel
manifest, 2026-08-22) — rustfmt rides its own component tarball, both
hash-pinned from the manifest. The Python closure is a uv cross-platform
lock (74 packages, PyPI-published hashes, `--require-hashes` at both
download and install); exactly two packages ship no wheel at their locked
versions and enter as pure-Python sdists: bibtexparser 1.4.4 and
python-doi 0.2.0 — measured by the wheels-only download refusing them,
one at a time.

Two build mistakes, recorded: the first image build failed at the pip
layer — Debian's apt python ships a `typing_extensions` with no RECORD
file, which pip cannot uninstall; fixed with `--ignore-installed` (the
locked versions land in /usr/local, which precedes dist-packages, and
Debian's copies are left untouched). And the failure was initially
invisible because the build command was piped into `tail`, which
swallowed the exit code — the repo's own pipe-hides-rc lesson, re-enacted
and caught only because the versions were measured afterward against the
image that was supposed to exist.

The freeze PR's own R1 (six P1s, all adopted) reversed one of this
entry's paragraphs within hours: the combined rust tarball **does**
bundle rustfmt-preview — the reviewer listed the shipped artifact's own
`components` file, which the earlier "measured in the manifest" claim
never opened (it had read rustup's network component model instead of
the artifact). The separate rustfmt tarball is gone; `install.sh` now
selects its four components explicitly, and the committed evidence is
the artifact's `components` file plus the in-image `rustfmt --version`,
both in `freeze-build.txt` (R2 flagged the first draft of this sentence
for citing an uncommitted build log).
The same review falsified the pins cover guard against its own
predicate — a deleted `--hash` continuation line sailed through the
name==version comparison — so the guard now compares every line, and
`freeze-build.txt` carries the red drill (rc=1 on the mutated copy) next
to the green run. The other adoptions: the refill algorithm is now
deterministic (all five primaries probed unconditionally, in order;
bench refills toward four passes only after the fifth verdict — no
outcome can shrink or reorder the measured set), the probe fixtures are
inlined in the PROTOCOL byte for byte (a "pre-computed formatted form"
for the formatter targets would itself have been pre-freeze contact, so
the formatter oracle is the tool's own `--check` plus the determinism
condition), the positive-control substitution is scoped explicitly
instead of hiding inside an "applies verbatim", and the freeze build's
evidence is a committed transcript (`freeze-build.txt`) instead of
prose.

## 2026-08-21 — the borg verify transcript closes #200: four mini-seals, four greens, still zero claims

verify-assisted green on borg-r3 (define at f508312 strictly before
artifacts at 79bb7bc, all four files byte-identical), the fourth
verify-green mini-seal of the day after hg-r4, jj and bun. #200 closes
with its outcome: the wall was lifted by declared apparatus, the
strongest documented promise in the cohort was asked 118 ways, and it
held every time. The search stays empty-handed and the record stays
honest — which is the only way an empty hand is worth anything.

## 2026-08-21 — Borg's verdict: FAIL 3/119, all three in the cache we relocated, and the contract held everywhere

The r3 explore ran 118 crash worlds plus baseline and reproduced its
verdict identically on a second run: FAIL 3/119, oracle_verified true,
single process, the #190 exclusion visible (fchmodat x3). The reading
writes itself: **Borg's documented transactional contract held in all
119 worlds** — break-lock fired in 14 and succeeded in 14, borg check
passed everywhere, the base archive extracted byte-identically in every
world, the listing was never a third thing. The three L0 violations sit
in `ambient/.cache/borg/<repo-id>/chunks` — the client cache's in-place
rewrite, a file borg documents as deletable-and-rebuildable, judged at
all only because r2 moved it inside the state root so worlds could run.
The all-5a repo id in the flagged path is the pinned urandom looking back
at us — the apparatus working, visibly.

Under the claim rule frozen before the cohort's first explore: a
precision-limit observation, no criterion-1 candidate. That is the
second null-with-verdict of the day, and the stronger one: the strongest
documented crash promise in the cohort, asked 118 ways under pinned
clocks and entropy, and kept 118 times.

## 2026-08-21 — borg-r3: the sendfile rerun, paid for in one line this time

The r2 explore cleared the cache refusal and stopped one syscall later on
`unsupported_syscall_observed: sendfile` — CPython's shutil fast-copy,
the exact refusal hg-r3 met this morning. The lesson was already paid
for: the sitecustomize gains the same one line
(`shutil._USE_CP_SENDFILE = False`), question bytes unchanged, seven
drills green again. hg needed a fork in the road and an owner ruling to
cross this; borg needed a copy of the receipt.

## 2026-08-21 — borg-r2: the client cache is state, and the engine's restore semantics said so twice today

The r1 explore refused `kill_did_not_land`: the engine restores only the
state root, Borg's client cache lived outside it, and after the recording
every world's `borg create` met a cache newer than its rolled-back
repository and refused (rc 2) before reaching any operation the standing
kill could land on. The same class as hg's wcache this morning — state
that decides the target's behavior must live where restore can carry it.
r2 moves `BORG_BASE_DIR` inside the state root, and the checker gains leg
R0: the crashed world's cache is derived state that can legitimately sit
ahead of the rolled-back repository, Borg's documented handling of a
suspect cache is deletion-and-rebuild, so the checker discards it before
reading and answers the two first-contact prompts with the documented env
overrides. Question bytes unchanged; seven drills green again.

## 2026-08-21 — the borg define: the strongest documented promise in the cohort, asked under the declared pins

The define (`spike/cohort2/borg/`, P1 of three proposals): kill
`borg create` over a repository holding a prior archive, and the
documented transactional contract must hold — stale-lock removal
(`break-lock`, exactly when a lock exists), `borg check`, the
pre-existing `base` archive conserved byte-identically, the listing
old-or-new, a new-side content assertion. The launcher installs the
three-piece apparatus (ld.so.preload + FAKETIME x0 + PYTHONPATH); setup
generates the sitecustomize so its bytes are D2-held (the hg-r3 reason).
Seven drills green on the first run — greens as controls, five reds one
leg each, including the leg V/leg C split (a corrupted segment vs a
VALID repo with different base bytes — the case `borg check` cannot see)
and the as-nobody unremovable-lock red. No explore has run.

## 2026-08-21 — #200: the Borg wall falls to a three-piece apparatus, and the issue's premise was wrong twice

The issue predicted one leak (time_end's monotonic duration). Running
found three, each by measurement rather than reading: the monotonic
duration; the manifest's utcnow; and — after both clocks were provably
frozen — the TAM authentication tag's random salt, present even at
encryption=none (found by diffing `borg debug dump-archive` between two
frozen runs: `salt`/`hmac`/`id` were the only moving fields). The
apparatus that pins all three: libfaketime via `/etc/ld.so.preload` with
FAKETIME `@...x0` (realtime frozen; monotonic deliberately left real so
sleeps and timeouts outside borg stay alive — the first frozen round
proved why by hanging in the harness's own gap sleep while borg itself
had finished fine), plus a sitecustomize pinning `time.monotonic` and
`os.urandom` (Python-scoped via PYTHONPATH; the C world untouched). The
urandom pin crossed a line drawn earlier the same day ("crypto randomness
is where we give up") and went to the owner instead of under the rug:
approved, with the distinction recorded — this is an integrity tag's
salt on an unencrypted repository, not encryption, and the
reproduce-against-stock condition already covers any finding.

The harness paid a tuition too: the first frozen round still split, and
the culprit was the probe itself — borg stores the full command line in
the archive metadata, and a harness that runs A and B in different
directories manufactures a split no real exploration would see. The
probe now runs A and B in place at one canonical path, restored from a
pristine snapshot between runs — which is the engine's own restore
semantics, so the probe got more faithful by being corrected. Final
record: control splits (the check can fail), pinned splits (the wall
stands without the apparatus), frozen is six-for-six green.

## 2026-08-21 — the closing verify transcripts: the mini-seal held on all three engine targets

verify-assisted runs green on jj and bun (define strictly before
artifacts, all files byte-identical at both points), joining hg-r4's
transcript from earlier today. Every engine target in cohort 2 now
carries a machine-checked provenance record — including the two that
ended in walls, where the record's value is exactly that the wall was
measured through the same discipline a find would have been.

## 2026-08-21 — both forecasts land verbatim, and cohort 2 closes with five recorded outcomes

The jj explore refused `no_shim_marker` (static binary — the shim never
initialised) and the bun explore refused `multiple_threads_detected`
("Saved lockfile" printed first: bun's own run was fine, the engine's
single-thread contract was not). Both are the exact refusals the probe
phase forecast, both measured binaries are the latest upstream stable so
the wall rechecks are inherent, and both are terminal for this cohort —
the dynamic-jj build stays an open apparatus decision, not a debt.

Cohort 2 is closed: five frozen targets, five recorded outcomes, zero
criterion-1 candidates, every step from selection to walls under the
committed discipline. The honest sentence for #183 is that the search
came up empty and the record proves the search was real. Criterion 1
continues on the standing upstream reports and any future cohort.

## 2026-08-21 — the jj and bun defines land together: two questions written down under standing wall forecasts

The cohort's last two defines ship in one PR, both with their expected
outcomes declared up front from the probe phase: jj's release binary is
static (`LD_PRELOAD` cannot load — a `no_shim_marker`-class refusal at
recording is the forecast), and bun spawns six threads during `bun add`
(`multiple_threads_detected` is the forecast). The defines exist so those
walls are *measured through the mini-seal*, not assumed — and so that if
either forecast is wrong, the question is already committed and the
verdict counts.

jj's checker asks the op-log contract (readable repo, initial bytes
conserved, description list old-or-new, `jj workspace update-stale`
exactly when jj reports staleness), reads with `--ignore-working-copy` so
observation does not trigger the auto-snapshot, and paid two small
tuitions in its drills: the description-list literals forgot the root
commit's empty row (the exact lesson hg-r4's probe already taught — pin
literals, then let the first contact correct them), and
`description("initial")` resolves nothing because jj matches the full
description including its trailing newline — `subject()` is the right
revset, confirmed in-container before trusting it. bun's checker holds
the triple (package.json/lockfile/node_modules) to
old-or-new-or-repairable with re-run-the-install as the documented
recovery, and its poisoned-cache drill (same tarball name, different
bytes) proves the byte-comparison leg is load-bearing. All nine drills
green across the two targets, greens as controls.

## 2026-08-21 — the verify transcript merged through a red gate, because the merge command never looked at the gate

The hg-r4 verify transcript (verify-assisted green end to end: define
strictly before artifacts, all four files byte-identical, the PROTOCOL
provenance attached in oneline form) went to main in #194 — and #194's
buildlog gate was RED, because the PR touched `spike/` without touching
this file. The gate did its job; the operator did not: the CI-polling
loop broke on "nothing pending" and the merge ran unconditionally in the
same command, so a failed=1 that was printed on every poll line was
scrolled past. Two mistakes stacked — the forgotten entry, and a
poll-then-merge pipeline that never gated on failures. This entry is the
missing BUILDLOG paragraph and the record of the bypass; the operational
fix is the obvious one (a merge command must test the failure count it
just printed), and it goes to the session's learning pass, not to another
layer of harness.

## 2026-08-21 — the first cohort-2 verdict: FAIL 73/107, and the frozen claim rule refuses it on schedule

hg-r4 reached the cohort's first verdict, twice identically: FAIL, 73 of
107 worlds, earliest at crash point 16, `oracle_verified: true`, single
process, the #190 exclusion visibly working in the metadata line
(fchmodat x10, utimensat x2). And the reading is the whole point of the
freeze: **every violation is L0-only, and Mercurial's documented contract
held in all 107 worlds** — recover succeeded in all 62 worlds that had an
abandoned transaction, verify passed everywhere, the checker's transcript
carries zero leg failures (the single red leg V line wears the falsify:
prefix, the #134 labeling doing its job). The torn file behind the
earliest case is `dirstate` holding a valid intermediate between its
pre-transaction rewrite and its final one — the multi-write shape, #35's
class, exactly what the protocol pre-declared as "recorded as a
precision-limit observation and never claimed."

73/107 is a seductive number. It would headline. The claim rule was
frozen before the first explore precisely so that nobody — including the
author on a long day — gets to decide after seeing it whether it counts.
It does not count. Mercurial's outcome is a null-with-verdict: the
contract held, the instrument's byte-atomicity form over-fires on files
written more than once per operation, and both facts are now committed
records. Criterion 1 stays open on the upstream watch and the remaining
targets.

## 2026-08-21 — hg-r4: 101 worlds green, and the baseline check earned its keep on a mode that carries meaning

With #190 merged, the r3 explore finally ran the whole campaign: 101
crash worlds, the checker green in every one — the documented `hg
recover` fired in 62 worlds and succeeded in all of them, verify held,
conservation held, the working copy agreed with the store on every line.
Then the un-killed baseline world died to the standing kill and the run
refused with `baseline_run_failed`.

The trace diff told it straight: the baseline ran a longer operation
stream than the recording, because the engine's restore flattens modes
(documented behavior since #121's note) and hg caches the filesystem's
exec-bit answer AS a mode — an executable `.hg/wcache/checkisexec`. Every
restored world silently re-ran the exec probe the recording had skipped,
shifting every operation index; the baseline was simply the world where
the shifted stream reached the kill that is never supposed to land. The
baseline check exists to say "the restored state is not the recorded
state", and it said exactly that about a state whose bytes matched and
whose *meaning* did not.

The r4 fix is define-side and one line: setup removes `wcache` from the
pre-state, so the recording and every world probe from the same blank
slate. Measured outside the engine before committing: with no wcache, a
mode-flattened copy of the pre-state produces a syscall-name sequence
identical to a mode-preserving copy (167 calls, diff clean); the probe's
temp names still differ per run, which the engine already tolerates by
design (classes gate, paths warn).

## 2026-08-21 — #190: the timestamp family joins the metadata exclusion, the decision the code reserved for itself

The r3 explore cleared sendfile and refused one syscall later:
`unsupported_syscall_observed: utimensat` — CPython's copy machinery
touches timestamps once per transaction-backup copy. The full syscall
inventory of the operation against the oracle's sets showed utimensat as
the *only* remaining blocker (ioctl and the stat family already sit in
the read-only list), and the oracle's own comment had reserved exactly
this call: "#121's ruling covered ownership/permission only; widening the
excluded list is its own decision, not a side effect."

The decision came due and the owner ruled (issue #190): the whole family
— `utimensat`, `futimesat`, `utimes`, `utime`, not just the spelling this
cohort hit — joins the exclusion, same shape as #121 option b. Test
first: the new unit test went red on the pre-change engine with the right
attribution (`unsupported = utimensat`, 167/168), then green after the
list change. Two prose consumers were updated with the mechanism, not
found by luck: the same-class scan for the old wording caught acceptance
check 2w-b's grep anchor (which would have gone red in CI against the
widened note) and README's sample report line — the exact
prose-edit-moves-a-test-anchor shape this workspace has paid for before.

The r2 explore ran deep — recording contained, 23 paths under the
pre-or-post form, 6 under history preservation — and refused:
`unsupported_syscall_observed: sendfile`. The strace hunt pinned it to the
transaction's backup copies (`branch`/`dirstate` → `journal.backup.*`,
then → `undo.backup.*`): hg's `util.copyfile` calls `shutil.copyfile`,
and CPython 3.13 fast-copies through `os.sendfile` with no environment
switch (`_USE_CP_SENDFILE` is a bare module global). Adding sendfile to
the shim is a contract change and the contract is frozen.

The fork was real: record the wall and almost certainly end the cohort
empty (jj's release binary is static, bun runs six threads — both
forecast walls), or bend the target's runtime one documented notch
further than the hgrc configs. The owner chose the workaround, r3: a
setup-generated `sitecustomize.py` sets `shutil._USE_CP_SENDFILE = False`
— identical bytes through supported syscalls, verified by a normal run
with zero sendfile calls — declared in the define, the proposals and here,
with the standing condition that any finding reproduces against stock hg
(strace fault injection, the four filings' method) before it is claimed.
This is a private CPython attribute, not a documented interface, and the
declaration says so plainly rather than dressing it up as configuration.

## 2026-08-21 — hg-r2: the first explore died at hello, and the revision rule got its first customer

The first engine run against the merged hg define stopped at a SETUP
ERROR before touching the target: the engine resolves `--state` to an
absolute path before setup runs, and the launcher had not pre-created the
state root — the exact lesson docs/scouting.md already carries ("create
the state root and the report's directory before exploring") and the
calcurse launcher already embodies. The transcript is committed beside
the r1 define (`explore-r1-transcript.txt`, two lines, rc 3).

The fix is one mkdir in the launcher, and it still gets a new directory
(`hg-r2/`): the launcher is D2-held from the define's anchor, an in-place
edit would read as a tuned question at claim time, and the protocol's
revision rule exists precisely so that nobody has to argue about whether
a given in-place edit was innocent. No test explore ran against the
uncommitted fix — an unpushed define that reaches worlds and FAILs would
burn the target's provenance — so the fix leans on the calcurse
precedent and ships to main before the engine sees it again.

## 2026-08-21 — the Mercurial define: the question is written down before the engine is allowed to ask it

Cohort 2's first define (`spike/cohort2/hg/`, P1 of three proposals): kill
`hg commit` anywhere, and the repository is already valid or returns to
valid through the documented `hg recover` — with the pre-existing
changeset conserved and the tip old-or-new at the contract level, never a
third thing. The shape is exactly the probe's (whole-`.hg` root, working
files outside as unwritten inputs, argv-form operation because the date
argument carries spaces), and the launcher pins `HGRCPATH` because the
operation child inherits the engine's environment, not the setup script's.

Two decisions worth their ink. First, the pinned hgrc is **generated by
setup.sh** rather than committed as a loose file: the provenance verifier
holds toml/check/setup/launcher to byte identity and nothing else, so a
loose config would be editable after the fact without D2 noticing — the
same hole R1 found for the launcher at the freeze, closed the same way
(bytes that live inside a D2-held file are bytes D2 defends). Second, the
checker's recover leg has deliberately **never seen a real interrupted
transaction**: manufacturing one by killing `hg commit` before the define
is pushed would observe exactly the failure class the provenance gate
requires the committed define to precede. Its red drill is synthetic (a
garbage journal in a store made unwritable — as nobody, because to root
every permission is a suggestion), and its first live exercise belongs to
the explore's worlds. Every other leg went red separately in
`checker-drills.txt` — including leg C via a *valid* repository with
different rev-0 bytes, the case `hg verify` structurally cannot catch —
with both greens (rolled-back shape, completed shape) as controls.

## 2026-08-21 — the probes ran, two walls fell where predicted, and the frozen jj plan was wrong twice in instructive ways

All five cohort-2 probes ran (engine-free, positive control first — the
unpinned `borg create` split, so the harness demonstrably flags
nondeterminism). Outcomes, transcripts committed under
`spike/cohort2/probes/`: Borg and KeePassXC record the pre-declared
determinism walls (both re-checked against latest stable in committed
transcripts: the fetched Borg 1.4.5 source carries the same `time_end`
code; KeePassXC 2.7.12 is current and its CLI help carries no determinism
option — the randomness is the format's own guarantee). Mercurial, Jujutsu
and Bun pass all six machine-judged conditions, with the ambient evidence
(condition 7) printed in each transcript — Bun's byte-determinism over a
local-tarball `bun add` was the surprise of the day, and it survives
`--network=none`, so the DNS/443 contact its strace showed is optional.

The jj plan needed amending twice, both times by measurement and both
before any explore (the amendment window the protocol allows): the frozen
`.jj` state root failed the closure condition because jj 0.44 colocates
the git store at `./.git` by default (jj-v1 transcript), and the corrected
repo-wide root then split on a single byte run — the reflog line jj's git
export stamps with wall-clock time (jj-v2). `core.logAllRefUpdates=false`
in the pre-state settles it (jj final transcript). The closure condition
caught a wrong frozen assumption on its first outing, which is the best
argument it will ever make for itself.

Three shim-visibility forecasts go into the define phase, each now
measured inside its own transcript: Mercurial's commit path spawns one
thread by default and the forecast table pins the off switch exclusively
(`storage.revbranchcache.mmap=no` → 0; both `worker.*` switches → still
1). The jj release binary answers `ldd` with "not a dynamic executable" —
`LD_PRELOAD` cannot load into it at all, so jj's slot will open on a
`no_shim_marker`-class wall unless a dynamic build is worth the
apparatus. Bun makes six successful `CLONE_THREAD` creations during
`bun add`, and the shim notes every `pthread_create`. Engine order, fixed
before any define: Mercurial → Jujutsu → Bun.

The probe PR's own R1 returned seven P1 and was right seven times: the
"all seven pass" wording claimed machine judgement the harness only gave
conditions 1–5 (closure is now condition 6 in the FAILS counter, seen red
and green in drills.txt with the other predicates); the mutating-path
listing missed most mutating syscalls and the raw strace logs were not
committed (they are now); KeePassXC's runs shared one HOME (per-run
ambient copies now); the transcripts' timestamps contradicted the "cohort
order" claim (the final transcripts are one clean in-order sweep); the
latest-stable rechecks and the linkage/thread forecasts existed only as
prose (committed transcripts now). Two of my own exactness literals were
wrong on first contact — jj's root-commit row and bun's tarball-path
version display — which is what exact assertions are for.

R2 then caught the closure check itself fail-open — a P0, and the exact
class the predicate exists to forbid: strace shows bare pointers where a
target locks its memory, and the extraction silently dropped those calls,
so an empty allowlist still passed. The rebuilt accounting is fail-closed
(every successful mutating call must be attributed or the condition
fails), drilled red both ways (an undeclared write, an unattributable
pointer call) with a green control, and its first honest sweep produced
three corrections at once: KeePassXC gains a second, independent wall
(7 unattributable calls — the memory locking that makes it a password
manager also makes it unauditable to ptrace); the `/var/lib/libuuid`
"finding" dissolved (the raw log shows ENOENT — the old extraction was
counting failed calls); and hg's lock symlinks taught the parser that a
symlink's first argument is content, not a path. Two sweeps of transcript
numbers also disagreed (bun's thread count, 6 vs 4) because the counter
ignored unfinished/resumed pairs — it now counts them with a consistency
assertion, and every number in RESULTS was re-read from the final
transcripts, not from the terminal scrollback of an earlier sweep.

## 2026-08-21 — cohort 2 opens: the claim discipline is frozen before any measurement, and the plan's first draft was wrong three ways

Criterion 1 is the last v1.0 item and its four upstream reports sit
unanswered (calcurse #529 and stow #139 re-measured today: zero comments),
so a second cohort opens rather than waiting. Selection cleared the owner
hard gate today — BorgBackup, Mercurial, Jujutsu, KeePassXC, Bun, evidence
and sign-off on #183 — and `spike/cohort2/PROTOCOL.md` freezes the rules
before any probe or measurement (pre-freeze target contact was install
plus `--version` in the image build, the cohort-1 pre-window allowance;
measured there: borg 1.4.0, hg 7.2.4, jj 0.44.0, keepassxc-cli 2.7.10,
bun 1.4.0, strace 6.13, Python 3.13.5): probe gate first (engine-free, seven pinned
conditions per transcript, all seven or no pass, positive control before
the first verdict counts, and the five probe plans themselves frozen in
the protocol), claim reading fixed in advance (only a saved
case whose violated invariant is the declared checker is a criterion-1
candidate; an L0-only FAIL is a precision-limit observation, the #35
ruling applied cohort-wide), and the mini-seal sharpened to #140's gate
(no explore before the define is on main; a define revision is a new
target directory; a FAIL freezes the define).

The plan's first draft did not survive review, and the reversals are worth
their lines:

- **The checker was designed to judge a scratch copy** on the belief that
  the quiescence double-sample brackets the checker's state access. It
  does not — `main.zig` takes the crashed snapshot and judges L0 *before*
  the checker runs (the stdout capture is what brackets the checker), and
  buku's committed checker already recovery-opens the crashed db directly.
  A scratch copy would also have handed Borg a relocated-repository prompt
  for free. Reversed: checkers run on the crashed state.
- **Borg was slotted as engine target 1** on the assumption `--timestamp`
  pins the archive clock. It pins the start only; `time_end` is start plus
  a `time.monotonic()` duration and lands in the archive metadata (read in
  both `1.4-maint` and `1.4.5` `archive.py`). Byte determinism is expected
  to fail, and the probe gate now exists to buy that answer for the price
  of two normal runs instead of a define and an explore.
- **The noise model overclaimed**: the draft assumed L0 would flag every
  transactional target's uncommitted partials. DESIGN §12 says otherwise —
  one-sided files are unconstrained, append-extended files are judged by
  history preservation — so the claim rule is framed as "how an L0-only
  FAIL is read if it appears", not as a prediction that it will.

Also reversed in review: an in-place define fix can never satisfy D2 (the
verifier anchors the define at its introduction and demands blob identity),
and a delete-and-re-add inside one merge collapses to `M` on the
first-parent line — so define revisions are new target directories, the
only shape that is an `A` event under every merge style. And the
verification transcript cannot ride the artifacts' own PR: the verifier
reads main, so verification is a follow-up PR after the artifacts merge.

KeePassXC moved from slot 1 to slot 4 (owner decision, recorded on #183
before any measured contact): its save is encrypted with fresh randomness
per write, a determinism wall is the likely outcome, and the binding
constraint on v1.0 is the upstream-response clock on a find — walls can
wait, finds cannot.

The first image build failed and taught the build its shape: the
development machine sits behind a TLS-intercepting proxy whose CA the host
trusts but a stock Debian container does not — in-container pip died on
"self-signed certificate in certificate chain" against PyPI, and the curl
steps for jj/bun would have died the same way one layer later — an
inference from the shared trust store, not a measurement: curl was
dropped from the image instead of tested (apt survived because Debian's
default mirror transport is plain HTTP).
Downloads moved host-side into `fetch-artifacts.sh` with committed sha256
pins (PyPI's published digest for the Mercurial 7.2.4 sdist, upstream's
SHASUMS256.txt for Bun 1.4.0, a stated first-download pin for jj v0.44.0),
and the Dockerfile re-verifies every copy so the build never has to trust
the context. The corporate CA stays out of the image and the repository.

The freeze PR's own review (R1, fresh session) returned six P1 and caught
this entry overclaiming in its first form: "frozen before anything is
installed" was false — the image build had already installed and
version-checked all five targets — so the claim narrowed to what the
cohort-1 rule actually allows (install + `--version` pre-window) and the
measured versions moved into the record. Same round: the Mercurial
eligibility ruling now cites its primary source instead of asserting a
sprint from memory; the five probe plans were frozen into the protocol
(pass conditions chosen before any probe can run, all seven or no pass);
pip gained `--no-index --no-deps` so the no-network claim is enforced
rather than hoped; and the launcher's precedence was demoted from "the
verifier proves it" to "read off D3's listing" — the verifier holds
toml/checker/setup only. R2 then showed the D3 reading still cannot catch
a launcher edited between explore and artifacts, so the rule moved once
more: the launcher ships with the define, present at the anchor, held
byte-identical by D2 like everything else.

And straight into the embarrassing column again: the freeze PR (#184)
merged **without** R2's three residual fixes. The commit was cut from the
staged snapshot taken before the R2 round, while the fixes sat unstaged in
the working tree — so the PR body claimed "R2 confirmed closure" about
content that did not contain the closures. The failed branch switch after
the merge is what surfaced it. The fixes land in the immediate follow-up
that carries this paragraph; the lesson is the usual one wearing new
clothes: a claim about the shipped thing must be measured on the shipped
thing — `git diff --cached` after the last edit, not before it.


Straight into the embarrassing column. The freeze-audit page carried a
standing sentence: *"Before tagging, the sweep is re-run and this page
updated for any issue opened or closed since the snapshot — the audit is a
gate, not a ceremony performed once and aged."* PR #178 replaced it with a
report that the re-sweep **had run**, which converts a standing obligation
into a completed one — the exact transformation the deleted clause names and
forbids. Two external reviews of that PR (R1: one P1, two P2, one P3; R2:
CLOSED) did not catch it; they were looking at the snapshot's arithmetic,
the class narrative, PRD's surface count and the CHANGELOG header.

It took hours to matter: filing `#180` (Homebrew install) and `#181` (the
macOS oracle claim resting on `dtruss` alone) left the page reading "nothing
remains" while two unclassified issues sat outside it. Neither touches a
frozen surface on this author's reading — `#180` is release engineering like
`#161`; `#181` adds capability through `--oracle` and `oracle_verified`,
both already frozen and both already shaped to carry it — so criterion 5's
substance is intact and only the bookkeeping drifted. Restored the sentence,
recorded the two filings with that reading marked as the author's rather
than the sweep's, and reconciled "What remains" so that "criterion 5 is met"
reads as a statement about the audit that ran, not a promise that the
tracker stopped moving.

The general shape, worth more than this instance: **when an edit replaces a
rule with a record of having followed it, the rule is gone.** Both readings
of the paragraph look correct in review, because the record is true. What
distinguishes them is tense, and tense is exactly what a diff review reads
past.

## 2026-08-18 — v0.12.0: the re-sweep ships as a minor

Owner decision: minor, not patch — #169 changes verdict behaviour (a
world-only-forking target that previously reached PASS/FAIL now refuses,
exit 2), the same shape that made v0.11.0 a minor. The version moves in
the usual three places (build.zig.zon, src/main.zig, README's quickstart
tarball name — grepped, no residuals). README cross-check against the
release content (checklist step 3.5): the boundary paragraph's two
sentences both stay true under #169 — a world-only boundary is a boundary
the oracle did not confirm, so it lands on the already-documented UNKNOWN
side; the quickstart name is bumped; adding contract-freeze.md to the
docs table is *declined* under the README's cut-only order (adding a row
would need its own owner call, and the PRD link already carries it).
CHANGELOG promoted with one release-time truth edit ("#86 closes with
this change" → "closed with it").

## 2026-08-18 — the pre-tag re-sweep closes the audit: snapshot replaced, resolved rows struck, the freeze declaration moves to its permanent home

Entry opened at the start of the work, per this file's contract. This is the
third and last PR of the re-sweep batch (#169 and #167+#159 landed first —
their entries below); it executes freeze-audit's What-remains item 3 and
closes #86, meeting v1.0 criterion 5.

Decisions, as adjudicated through plan review:

- **The snapshot and the gate's name move in one commit** — the gate's own
  header calls them one trust root. 13 open issues at the re-sweep capture,
  down from 26; the delta is all accounted: thirteen of the original
  snapshot's rows closed (that count includes #159), and four issues were
  filed *and* resolved inside the inter-sweep window — #164 (fixed with
  #27's measurement), #165 (its accidental duplicate), #167 and #169 —
  enumerated by a closed-issue query over the window, because a final-state
  capture is structurally blind to an issue that opened and closed inside
  it (the implementation review caught #164 missing; the query then also
  surfaced #165, which the review had not named).
- **Resolved rows are struck, not deleted.** A struck row (`| ~~#N~~ …`)
  keeps its adjudication history on the page but no longer matches the
  gate's `^| #` anchor — the gate counts active rows only. Review was right
  that the gate cannot prove a struck row is *genuinely* closed (it proves
  set equality of active rows against the snapshot, nothing more); that is
  commit review's job and the page says so, the same way it already says
  the snapshot itself is trusted by review, not machine.
- **The declaration moves to `docs/contract-freeze.md`.** #86's third ask —
  "the freeze itself lands in the docs" — was unmet in the letter: the five
  surfaces lived only on the audit page, which retires at the tag. Review
  (M-8) also caught PRD's normative list still naming four surfaces; it
  names five now and points at the new page as the single normative source.
- **Criterion 6 and #159 are deliberately separated**: the README change
  does not re-run the onboarding clock — the criterion's evidence is the
  pre-change README's measured run, and the audit row says so.

## 2026-08-18 — the text defang learns UTF-8 (#167), and the README says --shim and --work out loud (#159)

Entry opened at the start of the work, per this file's contract. Both are
pre-tag re-sweep adjudications (owner, 2026-08-18): #167 fixes now rather
than deferring, #159's held call resolves as a minimal Usage addition.

Decisions for #167:

- **One classifier, two spellings.** Plan review found the second predicate
  the issue never named: `sanitizeForReport` (the oracle-divergence detail
  route) has the same C0/DEL-only blindness as `appendSanitized` (the
  l0-note/FAIL route). What is shared is the *classification* — which unit
  of bytes gets defanged — not the replacement: the l0 route keeps its
  1:1-or-shrinking `?` (a hostile name must never bloat the report past its
  buffer), the divergence route keeps its visible `\xNN` spelling.
- **C1 is defanged in both encodings.** A raw 0x80–0x9F byte is invalid
  UTF-8 and defangs as such; the *valid* two-byte encoding (C2 80–C2 9F,
  the codepoints U+0080–U+009F themselves) defangs too — an 8-bit-CSI
  terminal interprets either arrival as an escape introducer. This is one
  class wider than the issue's own suggestion (which stopped at invalid
  bytes), and the reason is on the classifier.
- **Real UTF-8 is the guarded regression, and é cannot guard it.** Plan
  review caught the first draft's control: é is C3 A9, whose continuation
  byte lies *outside* 0x80–0x9F, so a lazy byte-wise widening would pass
  it. The controls are À (C3 80) and € (E2 82 AC) — continuation bytes
  inside the C1 range — plus 0xFF as the invalid-but-not-C1 independent
  pin. Any other invalid byte defangs one byte at a time (resync).

Measured: unit 167/167 native (one new test covering both routes and both
spellings). Seen red by mutation: `defangUnit` replaced with exactly the
lazy byte-wise widening the test exists to kill — 166/167, the only
failure is the new test itself ("the defang classifier covers raw C1,
encoded C1 and invalid bytes, and spares real UTF-8"), on the À/€/0xFF
controls. Reverted, green again.

## 2026-08-18 — a world-only boundary refuses (#169): the recording's clearance cannot cover a boundary the recording never crossed

Entry opened at the start of the work, per this file's contract. The pre-tag
re-sweep classified two issues filed since the 2026-08-17 snapshot; owner
adjudication (2026-08-18): #169 fix, #167 fix, #159's held call resolved as
a minimal README addition — all three land before the tag, then the snapshot
is replaced and #86 closes.

Decisions for #169, as adjudicated through plan review:

- **No new `unknown_reason`.** The refusal reuses `boundary_without_oracle`
  — the issue itself calls the missing refusal "the per-world analog of
  `boundary_without_oracle`", and the token's meaning (a boundary nobody's
  oracle accounts for) applies verbatim: worlds run with no oracle at all.
  The recording-time and world-time refusals differ in `message`, not in
  token, so the schema's closed set does not move — which also dissolves
  the "extend the schema before the freeze" pressure the first draft had.
- **The account is written before the refusal.** Replacing the
  processes-note update with a bare `unknown()` would have shipped a JSON
  whose `processes` field still said "single process" under a refusal
  naming a world boundary (review catch). Order: note first, refuse second.
- **The existing world-only checks: one inverts, one is deleted.** The
  quiet-checker check (exit 1, tolerated-with-observation) inverts to the
  refusal — that inversion *is* the fix's red/green pair. The arming check
  (capture contamination observed) would die silently, because the refusal
  now fires before the capture observation. The first draft migrated it to
  `TOY_FORK`; implementation review caught that the migrated copy was a
  byte-identical re-run of the check directly above it (same toy variable,
  same contaminating checker, same predicates) — the #46 machinery is
  already pinned on the tolerated side, so the world-only arming check is
  deleted with a note, not migrated.
- **The `crossed_boundary=true` window stays, documented.** Review pressed
  to refuse every world boundary; declined as adjudicated scope — ADR 0002
  already accepts the world-divergence window with its cost written down
  (closing it means an oracle on all N+1 worlds), and refusing every
  boundary would unmeasure legitimately-forking targets. ADR 0002 gains
  the clarification instead.

Measured (container, aarch64-linux cross build): full acceptance 150 ok on
the fix — the inverted world-only check green (exit 2,
`boundary_without_oracle`, the world-story `processes` account in the
JSON, the pre-#169 tolerate wording absent from text and JSON both). Seen
red by mutation, twice: first pass removed only the `unknown()` call (note
kept) — the suite failed on exactly one check, "world-only boundary
refusal: exit 1", the full-verdict FAIL headline in its output. Review
correctly objected that this is not the *exact* pre-#169 behaviour (the
note differs) and that the first draft's old-wording negation grepped for
the old *check's* echo text, not the old report wording — both fixed: the
negation now targets the report's own pre-#169 wording ("observed for
quiescence only", text and JSON), and the mutation was re-run with note
AND refusal both restored to their pre-#169 forms — the suite fails the
same single check, on the exit code (1, the full verdict; the old-wording
negations sit later in the predicate chain and guard the narrower
regression where the refusal stays but the tolerate wording returns).
Reverted; unit 166/166 native.

## 2026-08-18 — the last pre-tag narrowing: macOS says its widest limit out loud (#10), and two old issues turn out to be already answered (#6, #12)

Entry opened at the start of the work, per this file's contract; decisions
recorded as they land.

The batch picked #6, #10 and #12 together. Measuring before implementing
reclassified two of the three:

- **#6 (the oracle reads any quoted string as a path) is already fixed** —
  ADR 0006's Context names the issue's false-positive verbatim ("a
  `write(1, "/tmp/s/x")` whose buffer merely contains a state-directory
  string is read as touching the state directory") and the typed resolver
  closed it: `write` is classified, therefore an fd syscall, therefore
  scoped from its descriptor annotation only. The named unit pin exists
  ("a state-directory string inside a write buffer is not scope"). What
  remains of `touchesStateDir` is the conservative whole-line net for
  *unclassified* syscalls, and that route only ever refuses (`unsupported`)
  — fail-closed residue, deliberately kept. Plan: mutation-check the pin
  once (attribution fixed with `zig test --test-filter`, not the build
  graph — build.zig does not forward `b.args` to the test artifact), close
  as measured already-fixed, scoped to the named classified-write case.
- **#12 (the omamori dogfood cannot be agent-driven) is already recorded**
  — PRD's v0.4 status carries the full account (guards fire for a human at
  a terminal exactly as for an agent; measuring one would need break-glass,
  which removes the defence under test; out of scope on discipline), and
  DESIGN says "not measured either way". The close is the documented
  by-design decision, not a fix — the plan review (R1 M-4) caught the draft
  calling it "measured covered", which claimed a measurement nobody made.
  One sentence generalising the audience assumption goes on scouting.md.
- **#10 executes as adjudicated** (class A-adjacent narrow), wider than the
  audit's docs-only wording by owner decision: the `no_shim_marker` detail
  line gains a macOS-only clause naming an Apple-shipped platform binary as
  *one possible cause* — not the first suspect; the review (R1 M-1) killed
  the attributing form, since `no_shim_marker` proves only that `shim_ready`
  never appeared — and the macOS CI job gains a permanent pin (R1 M-2:
  a one-off local measurement is evidence it printed today, not a
  regression pin): exit 2, `unknown_reason` == `no_shim_marker`, the macOS
  clause present, the JSON `message` contained verbatim in the text (a
  containment check, not an extracted-line equality). The Linux wording
  stays byte-identical (comptime branch), so no existing pin moves.

Measurements, as they ran (all on the dev Mac, aarch64-macos):

- **#6 pin mutation**: `zig test --dep contract -Mmain=src/oracle.zig
  -Mcontract=src/contract.zig --test-filter "a state-directory string inside
  a write buffer is not scope"` — green on HEAD (1/1, raw rc 0). Mutating
  `isFdSyscall` to `return false` (dropping every classified fd syscall into
  the whole-line net): the *same filtered invocation* fails 0/1, raw rc 1,
  and the failing assert is the pin's own `classes.items.len == 0` — the
  issue's exact defect shape, attributed to the named test, not to some
  other member of the suite. Reverted; green again; `git status` clean on
  `src/oracle.zig`. First attempt at the single-file invocation failed with
  "no module named 'contract'" — `@import("contract")` is a build-graph
  module, so the direct form needs `--dep`/`-M`, which is also why the
  attribution cannot ride on `zig build test` (build.zig does not forward
  `b.args`).
- **#10 diagnostic, measured on the real binary**: `sideeye explore --state
  <scratch>/state --operation /usr/bin/true --check /usr/bin/true --work
  <scratch>/work --json <scratch>/report.json` against `/usr/bin/true`
  (an Apple platform binary): exit 2, `unknown_reason` `no_shim_marker`,
  the macOS clause on the detail line, and the JSON `message` contained
  verbatim in the text output (checked by substring, one detail line).
  `preflight` was the first attempt and refused `--json` by design
  ("preflight has no machine-readable form"), so the CI pin uses `explore`.
- **Seen red once — per predicate, not per script** (the implementation
  review caught the first pass claiming the guard falsified when only one of
  its four predicates had been): *clause* — the same script against a build
  with the branch stashed fails "the macOS clause is missing from the JSON
  message", raw rc 1; *exit code* — the same script pointed at a self-built
  toy-bug (which FAILs, exit 1) fails "expected exit 2 from an Apple
  platform binary, got 1", raw rc 1; *reason token* — pointed at a run whose
  checker never falsifies (a real UNKNOWN, not a doctored file) it fails
  "unknown_reason is 'checker_not_falsified', wanted no_shim_marker", raw
  rc 1; *containment* — the one synthetic input: a green run's report.json
  with a doctored text.out fails "the text report does not carry the JSON
  message verbatim", raw rc 1. Each failure is the named predicate's own
  message. The step also re-ran extracted from the workflow YAML (what the
  runner will actually execute after dedent): green, raw rc 0.

**The pin's first CI run refuted its single-path assumption.** Local green,
runner red: on the `macos-26-arm64` runner the same `/usr/bin/true`
invocation answered `recording_run_failed`, not `no_shim_marker` — dyld
*terminated the target* ("inserted dylib ... incompatible architecture
(have 'arm64', need 'arm64e')") instead of stripping the insertion
silently the way this dev machine's macOS 15 does. "An Apple platform
binary cannot be observed" is true on both; *how* it refuses is
OS-dependent, and the macOS clause never prints on the terminate path
(it lives on the `no_shim_marker` detail line). The step is now two
measurements: the platform binary pins only the refusal fact (exit 2,
never a verdict), and the clause's four predicates moved to a self-built
hardened-runtime binary — `zig cc` noop, `codesign -s - -o runtime`,
flags `0x10002(adhoc,runtime)` — where the insertion is ignored silently
and the run answers `no_shim_marker` with the clause (measured locally;
the same predicates, so the per-predicate reds above still hold — the
new second `[ "$rc" = "2" ]` is the same predicate form whose red the
toy-bug run produced). target-classes now records the two measured
refusal paths by OS instead of implying one.

**And the replacement was refuted the same way one push later.** The
hardened-runtime carrier claimed "ignored silently on every measured OS" —
technically true with one OS measured, exactly the claim-exceeds-
measurement shape — and the runner promptly measured the second OS the
other way: on `macos-26-arm64` the ad-hoc `runtime`-flagged noop *accepted*
the insertion (the shim loaded, ran, and the refusal came one detector
later as `completeness_not_verified`). Both dyld behaviours are
OS-dependent, in opposite directions. The clause carrier is now the
deterministic synthesis of the marker's absence, dyld's mood not invited:
a decoy dylib that never writes `shim_ready`, handed to `--shim` — whether
it loads or not, the marker cannot appear, so `no_shim_marker` and the
clause follow on any OS. Measured locally through the extracted-YAML form
(exit 2, token, clause, containment — same four predicates, reds standing);
this is the same synthesis philosophy as the MCP doctored-response red.

Entry opened at the start of the work, per this file's contract; decisions
recorded as they land.

#150 as adjudicated (relabel to explored worlds, sweep the greps first) —
and the plan review found the same mislabel on the PASS headline, which the
issue never named: `PASS {explored}/{explored} crash worlds satisfied...`
counts the baseline too, and the public records quote it (taskwarrior's
12/12 against an 11-operation oracle account, the onboarding clock's 4 of
4). Owner decision: both verdicts in this PR — fixing the FAIL line while
knowingly leaving its twin would be the same defect with a paper trail.

Three more review-driven decisions, taken before code: the headline tests
compare the printed numerator/denominator against the same run's JSON
`violations`/`explored` (a wording-only pin passes an implementation that
"fixes" the denominator to crash points); the MCP transport-contamination
check drops its prose anchors — which would have needed to chase this very
relabel — for an exact match of `content[0].text` against a reconstruction
from `structuredContent`, self-falsified by feeding the same predicate a
doctored response; and #157 is pulled forward by owner decision (the same
overtake shape as #58) as one typed `pin()` used by both the seven real
oracle_verified pins and a synthetic string-"True" rejection, so the red
cannot drift from the predicate it falsifies. #156 stays deferred — the
audit accepted the permanence trade explicitly, and nothing new argues
against it; the issue gets an out-of-band note, not code.

The sweep taught two lessons on its first container run. First, a
classification error of mine: dogfood-todoman.sh looked like current
apparatus, but its define bytes are hashed by the frozen unknown-rate
sweep — relabeling one word in a comment broke the corpus digest
(check 12 caught it immediately; the file is reverted and reclassified
as frozen evidence, stale wording being the price of the freeze).
Second, the reverse collision the grep-for-old-text sweep cannot see:
`grep -o 'explored [0-9]*'` matches ZERO digits, so the relabeled PASS
headline's "explored worlds" started matching an extraction that had
only ever seen the "explored N worlds" line, feeding it an empty value.
Sweeping for consumers of the old wording finds half the problem; the
other half is old patterns that newly match the NEW wording. The
extraction is anchored to the unit word now, and the only other
output-parsing pattern in the suite anchors on l1's unchanged phrasing.

## 2026-08-17 — v0.11.0: the day's four batches ship as one minor

Owner-selected minor over patch: the release carries a required new report
field (`oracle_verified`), a new refusal (`unsupported_state_entry`), and an
expansion of what L0 judges (dir-to-dir pairs) — surface additions, not
repairs only. Three version spots moved together (build.zig.zon, main.zig's
banner constant, the README quickstart tarball name); the v0.10.0 strings
that remain are the SIGILL incident's historical records and stay. The
first push of this bump forgot this very file and the buildlog gate caught
it — the gate doing for the journal exactly what it was installed to do.

## 2026-08-17 — the demotion was the easy half; the review found the classifier that would never produce the entry to demote

#5, the audit's last tag-gating fix, measured before written as usual: the
issue's symlink half was stale (#122 restores links, dangling included), and
the live half was `restore`'s catch-all silently dropping `.other`. The
plan-stage adversarial review then found the hole under the hole, a Critical
worth the name: `.other` only exists when `d_type` says so. On a filesystem
that answers `DT_UNKNOWN`, the fallback probed by `open(O_RDONLY)` — which
*hangs forever* on a FIFO with no writer, reads a socket's failed open back
as `.missing` (silently absent from the snapshot), and slurps a readable
device as a regular file. A demotion wired downstream of that classifier
closes #5 in a shape that quietly does not exist on exactly the filesystems
most likely to carry special files. The entrance got repaired first:
`statx(AT_SYMLINK_NOFOLLOW)` on Linux (std binds no libc stat symbol there —
glibc's are versioned aliases; the syscall layout is std.os.linux's to keep),
`std.c.fstatat` on Darwin (where std resolves `$INODE64`), no open, no
follow, and posix.zig's old "stat is unusable here" comment carries the
dated correction: true of hand-rolling, not of what std ships. A real-FIFO
unit test pins all five kinds; a regression to probing would surface as a
test timeout, which the test says out loud.

Two process notes, both cheap and both mine. The first cross-build failure
hid behind a pipe: `zig build ... | tail -1` reports tail's exit code, and
the "success" I read was the pipe's — the stale binary then sailed through a
whole rehearsal answering exit 1 with the demotion nowhere in it. The known
gotcha, performed anyway; raw `rc=$?` on the bare command found `std.c.fstatat`
being `void` on linux-gnu in one look. Second, `E.init` was remembered, not
read — the 0.16 idiom is `linux.errno(rc)`, and the compiler said so on the
first try, which is what the discipline is for.

The three reds are one per detection site because one red proves one call
site: setup-created FIFO (initial), TOY_MKNOD on the no-oracle path (final —
under an oracle the defined-list refusal keeps precedence, pinned by the
untouched 2w-b control), and TOY_MKNOD_TRANSIENT (crashed: mknod invisible,
the remove's unlink a kill point, the world killed between them holding the
FIFO). The symlink discriminator doubles as the green control through the
same apparatus; a newline-named FIFO pins the defang with the forged-line
predicate self-falsified each run against a synthetic raw-shaped line.

The diff review sharpened three edges of the first cut. The classifier
collapsed every syscall failure into "absent" — ENOSYS under an old kernel
or EPERM under seccomp would have deleted a real entry from the snapshot and
routed it around the very refusal being added; only a genuinely-gone path
answers `.missing` now, everything else fails the snapshot loudly, and the
`statx` type mask gets the check std's own doc demands. The crashed-site
refusal sat between the capture's two quiescence samples, so a
still-writing world with a stable FIFO would have refused as the FIFO
rather than as itself — moved below the second sample, restoring the stated
order. And the world loop's last iteration is the un-killed baseline: an
entry only IT leaves (pinned with a flag-file toy whose mkfifo is rotate's
last act, reached by no killed world) now reads "left by the baseline
re-run", not a fictitious crash. The both-platforms unit claim was also
trimmed to what was actually run where.

## 2026-08-17 — the checks that could stop looking, and the class that gets named instead of judged

#58, fixed ahead of the audit's "defer" with the owner's approval (the same
overtake shape as #26, and the audit row carries the same dated correction):
`assert` in a judgment is a check that can be turned off from the outside —
`PYTHONOPTIMIZE=1` strips it and the suite keeps answering green with only
exit codes examined. The counts were re-measured before touching anything
(the issue's 18+3 was stale): five live asserts in the explore suite,
twenty-two in the MCP suite, and one more in the quickstart workflow the
issue never named — the same-class sweep over every committed `*.sh`/`*.py`
found nothing else (the replay suite was converted back when the defect was
first caught there). The conversion is the replay suite's shape verbatim;
the hole was demonstrated once on falsified input before converting, and
the completion bar was raised from "a representative red" to running both
suites end to end under `PYTHONOPTIMIZE=1` — 142 ok and all-passed, so the
judgments demonstrably still look when the switch that silenced them is on.

#39 executes the audit's narrowing, and the writing job turned out to be
about measurement tiers, not platforms: the class's two demonstrated
members carry different evidence (stdio probed on macOS too — ADR 0005's
dyld line; remove(3) measured on Linux only), and the first draft's flat
"measured precedent" would have promoted an inference to a measurement.
The committed sentence separates probed / measured-on-Linux / unmeasured,
and states the macOS consequence for the unmeasured members as mechanism
inference. The issue stays open on purpose: its body is the family's
lookout post, and closing it would orphan the fix pattern it carries.

## 2026-08-17 — the capture joins the quiescence observation, and the straggler that motivated it cannot be built

#46, measured live before implementing (twice bitten by stale issues this
week): the world loop's quiescence double-sample covered the state directory
only, and `stdout-world.txt` — L1 evidence — was read exactly once, by the
marker scan. Then the plan-stage measurement closed the door on the issue's
own reproduction idea: a real straggler cannot be manufactured. The oracle
flags any non-primary `setsid`/`setpgid` as a boundary (oracle.zig, the
"visible nowhere else" comment) and refuses before the quiescence code runs,
and a child that stays in the group cannot outlive `kill(-pgid)` by more
than scheduling noise. The committed red apparatus is therefore the
checker: `--check` runs between the two capture samples, so a checker that
appends to the capture lands its bytes exactly where a surviving writer's
would — deterministic, and it exercises the guard's own predicate (fp1/fp2
disagreement), not a lucky race. Measured pre-fix in the container: the
append sat unread in the capture while the run reached exit 1.

The external plan review found the hole beside the hole: arming was
recording-global. A toy that forks only when `SIDEEYE_KILL_AT` is set (so:
in every world, never in the recording) reached a full verdict pre-fix with
the report's processes line reading `single process` — the recording's story
spoken over worlds that each crossed a boundary. Arming now includes the
world's own trace evidence; whether such a world should refuse outright
(nothing oracle-shaped ever accounts for it) is deliberately not decided
here — filed as #169, because it changes verdicts.

Shape decisions, each with its reason: one `observeCapture` read produces
both the marker verdict and the fingerprint, so the two claims cannot come
from different bytes; the read is bounded by the size measured at open,
because a live writer must never be able to keep the observer chasing EOF
(the hang would replace the refusal); the digest is Blake3, because the
bytes are target-chosen and a same-length rewrite must not be able to keep
a cheap checksum; the refusal reuses `state_not_quiescent` (the closed set
is a frozen surface) with a capture-naming message, which is also what lets
the acceptance red attribute its kill to this check and not the state-dir
one. `fileContains` lost both call sites and is gone — its straddling-marker
test carried over to the new observation, on pid-unique paths this time.

The diff review (R1) then found two real holes in the first cut and one
overclaim. First, the bounded read could be blinded by a truncate: measure
size B, read b < B after a concurrent shrink, and the stored fingerprint
says b — so a later honest size-b sample with the same bytes compares
*equal*, and the change observed mid-read evaporates. The observation now
records both the measured size and the bytes actually read, equality
compares both, and reaching EOF below the measured size is its own refusal
predicate (`sawTruncation`) at every armed comparison — on a regular file
that shape cannot happen without a concurrent writer. Second, the processes
line kept telling the recording's story: a world-only boundary armed the
observation while text and JSON still said `single process`. The note now
corrects itself before any refusal can fire, and a fourth acceptance case
pins the corrected account on the quiet world-only run. Third, the
CHANGELOG draft claimed "a still-live writer surfaces as a refusal" — more
than two samples can promise (a writer that pauses between them passes);
narrowed to what is measured. R1 also named the honest limit of the
committed reds: they all write `stdout-world.txt`, so the recording-side
comparison has no end-to-end pin — nothing external executes between its
two samples, the same structural exclusion as the straggler itself. Its
seen-red is a mutation, run once and reverted: inverting the recording
comparison flips the green control to `state_not_quiescent` with the
recording-specific message, which is the wiring-and-attribution proof the
suite cannot carry.

## 2026-08-17 — a hostile file name forged a report line on demand, and the fix defangs the text while the JSON stays as it was

#26, measured before fixed: a state file named with an embedded newline
(`log`, newline, `not tested  nothing`) drove a real exploration to FAIL
under the strace oracle, and the pre-fix text report printed the second half
as its own line — a forged `not tested  nothing` sitting where a verdict
line sits. The apparatus taught its own lesson first: the obvious shell
script driving rm/mv is refused as `child_touched_state_dir` (children have
no crash-point address — the refusal doing its job), so the committed check
drives the unlink/rename in-process from python. The fix is three operands
wide and display-only: `after_path`, `before_path` and `path_shown` reach
the text through the l0 note's existing defang predicate (one predicate, not
two that drift), while the JSON block keeps reading the raw variables —
`jsonString` behaves as it always did (controls escaped, invalid UTF-8 to
U+FFFD, so a valid name round-trips exactly), and the acceptance check pins
both sides plus the round-trip, with the forged-line predicate falsifying
itself against a synthetic forgery on every run. `?` and not a hex spelling on
purpose: one byte in, one byte out, so a hostile name can never bloat the
report past its buffer and erase the counterexample it names. This overtakes
the audit's same-day "document" adjudication for #26 with the owner's
approval, and the audit row carries the dated correction. #35 rides along
as adjudicated: the scratch-file pattern (git's COMMIT_EDITMSG, measured
2026-08-11, thirty-four worlds, fsck accepting every crash world) joins the
checker cookbook's failure-patterns list, and the issue closes as
documented.

## 2026-08-17 — the audit adjudicated a fix for a hole that was already closed, and the measurement found the real one next door

The freeze audit classified #27 as class A, "fix before the tag" — and the
audit's own sweep had just caught #13 being stale, so the lesson was on the
table and still didn't transfer: the sweep checked open/closed, not whether
an open issue's defect still existed at HEAD. It didn't. #122's pair rule
(kind and content compared together) closed #27's named window two days and
twenty-eight commits before this branch's HEAD (38e1186, 2026-08-15); the
plan-stage measurement — write the issue's own scenario as pins through the
real classify+judge path, run them against HEAD — came back green on the
first run. The pins stay, one test fn per pin so a mutation reports each red
individually (the first round used one shared fn and its single failure
masked the rest — that round's numbers were unobservable and are not
claimed). Measured on the split tests: a kind-blind mutation (both kind
checks removed from the standard arm) reds five tests — the three empty-side
#27 pins, #164's file-replacement pin, and the #122 symlink test — and
spares the non-empty control, which keeps rejecting on content alone. The
audit row, PRD and the unreleased CHANGELOG entry carry dated corrections
rather than silent rewrites; the tag gate shrinks to #46 and #5.

The measurement's real find is the adjacent gap the issue never named:
`classify` skipped every dir-to-dir pair as "nothing to compare", so an
empty directory present in both clean runs had no witness at all — a crash
world could replace it with a file or delete it and PASS stood. Filed as
#164 (the class-A shape, joining the audit table at the pre-tag re-sweep)
and fixed in the same change: the skip is gone, the pair enters under the
standard two-sided rule, and reintroducing the skip as a mutation reds four
tests (the three #164 pins and the #122 kind-change control). The restore
prerequisite went loud with it — the directory mkdir was the only creation
whose failure was ignored, harmless exactly while empty directories were
unjudged and a tool-manufactured `missing` the moment they are judged. Review
then killed the EEXIST tolerance the first version carried: the root never
appears in restore's entries (walk records children only), so an existing
directory there has no legitimate source — tolerating it would let world k
judge world k-1's residue through deleteTree's one silent path. Strict now,
and the guard has its own falsification: a parentless dir entry must refuse,
and silencing the mkdir as a mutation reds exactly that one pin. Same-day
process notes, recorded because they cost redos: the first mutation round
was reverted with `git checkout` on a tree whose base was not yet committed,
which threw away the implementation along with the mutation — the second
round committed the base first. And the batch's own filing tripped GitHub's
closing-keyword parsing twice in one day (#27 accidentally closed the same
day by the merge-commit prose `fix #27` — reopened within fifteen minutes
with the accident named; then a shell precedence slip filed #164's text
twice, #165 closed as the duplicate) — keyword-shaped issue references now
travel in code spans, the one spelling GitHub's autolinker is measured to
skip (entities and backslashes are not — the workspace learned that on the
org migration).

## 2026-08-17 — the freeze audit: twenty-six issues against five surfaces, and nothing deferred under an intact PASS claim

Criterion 5's audit ran as #86 wrote it: sweep first (committed snapshot,
2026-08-17T00:33:15Z — the set includes issues filed the same day, three of
them under half an hour before the capture, and excludes #87, closed
seventeen seconds before it; recalled, the table would have missed both
edges), classify every row, decide every toucher.
The completeness gate is check-12-shaped — a script, run at each sweep
rather than wired into CI, checks the table against the snapshot and judges
a one-row-deleted copy of the page on every run, demanding red there. Ten of twenty-six touch a frozen surface. The class-A
adjudications are the owner's, taken 2026-08-17 with recommendations visible:
fix #27 (the L0 kind hole is a real false-PASS window) and #46 (the capture
quiescence gap), demote #5 (a non-regular entry refuses rather than exploring
an unreproducible tree — the issue's own "more honest and more annoying"
option), narrow #39 and #10 (the macOS promise shrinks on the target-classes
page; the README stays under its cut-only order). The exit-code split — #94's
deliberately deferred half — is rejected permanently: the flag is the
caller's consent, macOS would lose exit-0 passes entirely, and the designed
channel already carries the bit. Two readings are codified so the freeze
cannot be argued around later: a post-1.0 trace-contract bump is honest under
the replay promise (refusal, never a misjudged address), and #156's inert
flag combo freezes as documented behavior — refusing it later would be
breaking, and that trade is accepted out loud. One stale promise died in the
sweep: preflight's refusal text still said a machine-readable form "arrives
with issue #84" — it never did; the text now states the constraint. #13
closes as fixed (ADR 0005 shipped stdio observation; check 2u pins it).
The audit's own gate: #86 stays open until #5, #27 and #46 land and the
pre-tag re-sweep runs — the declaration takes effect at the tag, not today.

## 2026-08-17 — the clock ran: 4 minutes 22 seconds, README to a real verdict on jrnl

Criterion 6's first measurement, under the protocol committed the day before:
a sealed driver (claude-opus-5, 28 turns, not told it was timed) walked from
the README to `explore` returning PASS on jrnl — 4 of 4 crash worlds, oracle
agreed on 3 operations, checker falsified before the run — in 4:22, well
under the ten-minute budget. Met, first try. The number is derived from the
committed event timeline, not written by hand; the extractor flagged three
transfer commands (docker cp / base64-through-exec of driver-authored files)
and the adjudication is on the results page rather than swallowed — the seal
guards what flows in from outside the driver, and nothing did. Two honest
observations from the driver survive as work: `--shim`/`--work` appear only
in the README's Example, not the Usage bullets (filed), and its own PASS
carries the history-form reservation (`appended tails` in not_tested) —
which the driver read, understood, and answered with its own checker; the
account block did its job on a stranger. What did not survive rehearsal is
the entry below this one.

## 2026-08-17 — the release binaries only ran on the machines that built them

The onboarding clock's rehearsal — the step that exists to prove the
apparatus before blindness is spent — found the apparatus broken in the
product's favor of nobody: the v0.10.0 aarch64-linux tarball's binary dies
with Illegal instruction on the fresh box, before printing its banner.
Isolation: the same tarball dies in the spike container too (so not the new
image), a local cross-build runs fine in both (so not the environment), and
v0.9.0's tarball dies the same way (so not this release). Cause: the release
workflow built with a bare `zig build -Doptimize=ReleaseSafe` — no target —
which compiles for the *builder's* CPU. The aarch64-linux artifacts inherited
the Graviton runner's extensions; Apple-Silicon Docker lacks them; SIGILL.
The workflow even smoke-tests the artifact (`sideeye demo`) — on the same
runner that built it, so the claim "the packaged pair works on the OS it
ships for" was measured on the builder's CPU only, and stayed green for
every broken release since the tarballs began. The x86_64-linux artifact has
the same construction and no hardware here to test it on: presumed affected,
unverified. Fix: the matrix now spells `-Dtarget` per artifact, which pins
the architecture's baseline CPU; v0.10.0's assets are rebuilt and replaced
through the workflow's own tag-dispatch repair path (built from the tag's
code, uploaded with --clobber), with the owner's approval recorded in this
batch. The onboarding clock waits for the repaired artifact — measuring a
broken tarball would time the bug, not the docs.

## 2026-08-16 — the onboarding clock: the protocol is committed before the stopwatch starts

Criterion 6 has had its instrument for weeks and no measurement; #87's own
rule is protocol-before-clock, so the protocol went down first
(`spike/onboarding-clock/PROTOCOL.md`) and this entry records its decisions
as they were made, before the first run. The fresh machine is a network-off
Linux container; three deviations are declared rather than hidden — the
release tarball is pre-staged (no network means no download, and the download
would measure a CDN, not the docs), the target arrives installed and
configured (a user measures a tool they already run), and the README is a
staged file (its opening is the session start). The driver is the
loop-closure isolation form — `--safe-mode` headless, allowlist plus denied
network/delegation tools, stream-json transcript as the audit surface — with
one new rule: the driver is not told it is being timed, because a driver
racing a clock skims and the criterion is about the documentation. The
target is jrnl, the owner's pick under the standing selection bar (7,291
stars, pushed 2026-08-14, contributors above the bar — measured, not
recalled, same day). The clock stops only at a real verdict — exit 0 or 1 —
because refusals are what the README teaches you to fix; a refusal loop that
eats the ten minutes is itself the measurement. Rehearsal boundary written
before rehearsing: the apparatus may prove that jrnl accepts an entry and the
tarball's binary runs, but nothing rehearses sideeye against jrnl — the
first exploration of the target happens on the clock or not at all.

## 2026-08-16 — oracle_verified: the report says, as a value, whether a second witness checked

Issue #94's gap, measured before anything was written: a verified PASS and an
`--allow-unverified` PASS were generated on the same clean toy in the spike
container and their JSONs diffed — both exit 0, and the difference confined to
two prose account fields (`oracle` and `metadata_writes`). Grep-able, so the
premise is not "no difference"; it is that neither is a field designed for
branching — the schema page licenses account prose to change wording between
releases. The fix is one required bool on every report: `oracle_verified`,
true at exactly one point in the pipeline (the oracle comparison completed and
agreed — set beside the "agreed on N operations" note), false on every other
path: no `--oracle`, `--allow-unverified` with no oracle, a comparison cut
short by a refusal (the flags are not exclusive — an oracle that ran and
agreed sets true beside an inert `--allow-unverified`; whether that combo
should refuse instead is filed as #156, not decided here). Review then added
two more corners to the pins — the SETUP_ERROR report and the no-oracle FAIL,
each seen red once against a field-less report — bringing the value pins to
seven; the pins' repr comparison cannot see a bool-vs-string type regression,
filed as #157.
The name was the owner's pick from three shapes: `evidence_level` on every
verdict was rejected because a no-oracle FAIL would be stamped "unverified" —
a word that reads as doubt about a counterexample that stands on replay alone;
a PASS-only field was rejected for pushing three-state logic onto every
caller. A fact about the run, never the verdict. The exit codes stay untouched
— whether an unverified PASS should exit differently is the freeze audit's
question (#86), deliberately not this change's. Acceptance pins the value on
all four corners (verified PASS true, oracle-borne FAIL true, no-oracle
UNKNOWN false, --allow-unverified PASS false) plus the ran-but-not-compared
path (empty oracle), and the pins were run against the pre-change binary
first: all five red (the field read as empty on every pin), with check 4's
bidirectional binding firing too — "documented but never generated".

## 2026-08-16 — the README sheds its history: the owner's simplification order

The owner read the front page and ordered it cut: the status paragraph, the
version history, the filing-by-filing accounting of upstream reports, the
inline ADR and issue numbers — none of it serves the person arriving today.
The rewrite deletes, and rewords only downward; nothing gets a stronger
claim than it had. One sentence needed real care: the results line. The old paragraph
enumerated filings, and #147 is open precisely because a committed table
(`outcome-map.tsv`) overcounts reported-upstream rows — so the new sentence
was derived from `spike/assisted/NOVELTY.md`'s upstream round and the live
tracker links instead: four standing filings (timewarrior, topydo, calcurse,
stow), devtodo filed and withdrawn the same day by the owner's fair-play
ruling. The page now says "several of them reported upstream" and carries no
count. The "not measured from this README alone" sentence survives on
purpose: criterion 6's first timed run (#87, this batch) is what replaces it
with a measurement, not an edit.

## 2026-08-16 — v0.10.0: the pre-freeze batch release

Version bump only — the work is in the entries below from the same two
days. The release carries the argv form (#95, ADR 0019 flipped to Accepted
in this commit), criteria 3 and 4 recorded as met, the timew-regression CI
job, the scouting guide, and the follow-up measurements. The choice of
0.10.0 over 0.9.1 follows the house precedent that a define-contract
extension is a minor: the trace contract did not move, but the config
contract grew a value shape and the case format grew version 3. One
process note: the buildlog CI gate correctly refused the first push of
this bump — a version literal in `src/main.zig` is still a src/ touch, and
the gate does not know "it's only a release" from a code change. This
entry is the fix, not an exemption.

## 2026-08-16 — the scouting guide ships: SCOUT.md grows its product form

The batch's last PR promotes the assisted-discovery method to
`docs/scouting.md`. The promotion is a rewrite, not a copy: the experiment's
measurement framing (start timestamps, the 15-minute budget, cohort rules)
stays behind in `spike/assisted/`, and what crosses over is the method — the
five things a scout reads for, propose-before-define metadata, fail-closed
checkers, treat-UNKNOWN-as-a-define-bug — plus every lesson the cohort paid
for and two things this batch added: the argv form for the argument a
space-split string cannot spell, and the routing note that an argv define
skips preflight for `explore --config`. Numbers are deliberately absent from
the guide: measured results live in the records (`spike/assisted/`,
`spike/followup-95/`), which do not go stale when the next cohort runs.
SCOUT.md keeps a pointer forward so the experiment's record and the product
door cannot drift apart silently.

Same PR, a reversal recorded as it happened: on the owner's direction to
sweep the README for contradictions, hnb was first PROMOTED — into the
front page's counterexample list and the target-classes Measured table —
and the owner rejected the promotion within the hour, on a stronger ground
than the reporting rule: **a small, effectively dormant project is not a
legitimate measurement target at all**, and putting one on the product's
front page is wrong even unreported. Both promotions are reverted; the
re-scoring that had briefly taken a half point from the hnb run is
corrected 3.5 → **3 of 5** (RESULTS.md carries the correction, the
selection rule in PROTOCOL.md is tightened from "explorable but
unreportable" to "not a target", and the scouting guide now says so as its
first never-do). The followup-95 record itself stands — it was and remains
the #95 contract measurement — it just names no score and no front page.

## 2026-08-16 — #118 re-scored by the owner, #123 held on measured demand

**The re-scoring (owner adjudication, recorded in RESULTS.md).**
Drivable-slice discovery value 1.5 → **3.5 of 5**; question quality stays
5/5. The mechanics: stow and devtodo graduated from blocked to found when
#121/#122 closed the gaps under their questions; buku counts zero (question
stood, answer sat inside the store's contract, claim withdrawn); pass stays
blocked on #123. The half point is hnb — outside the cohort, same assisted
shape, and the deliberately irregular part of the number: a sixth target
against a five-target denominator, disclosed in the record as
"corroboration the pattern holds beyond them" rather than silently pooled.
The owner also ruled the product decision: **advance** — the agent-facing
scouting guide gets written (next PR), and #118 stays open per its own
tracking note.

**#123 stays open and unbuilt, and now the reason is measured rather than
felt.** The trigger was "build when multi-process friction dominates". The
#84 sweep's two child refusals turned out to be spelling (both op.sh
wrappers; #95 dissolved hnb's live), leaving one direct demand (pass) plus
one potential (lbdb through a wrapper child). Against that: the address
`(subject pid, seq)` is load-bearing across engine, case format and replay;
ADR 0002 already rejected both obvious mechanisms; and the ADR 0018
precedent prices the smaller half of this issue at 1106 PR lines (~370 of
them src/ + shim/ insertions, measured from that PR's own diffstat — the
review caught this entry's first draft carrying "~450" inherited from an
earlier review's estimate, unverified: the remembered-number class again).
The disposition comment carries all of it, with the reopen condition stated
as a data condition, not a mood.

## 2026-08-16 — #95: the argv form, and the wall it was built against turns out to hide a real bug

**The shape of the change (ADR 0019).** One tagged union — `config.Command`,
string or argv — carried from the parser through `Args`, the case file and
the three spawn sites, so the two spellings meet only where both become the
executor's argv. The string path is byte-identical to before: the flags still
bind strings, `splitArgs` still splits them, and a case spelled entirely in
strings still writes `case_version: 2` — the bump to 3 happens only when a
define actually carries the argv form (the ADR 0014 travel-together law,
extended to shape). The parser's array grammar is deliberately narrower than
TOML's: one line, quoted elements, commas, and a named line-numbered refusal
for everything outside that — including the array form on a non-command key,
which a value-first parse would have accepted silently (plan R1's catch,
confirmed against the code: the old parser read the value before dispatching
on the key). Review then caught the refusal *count* claimed in prose
disagreeing between four documents while a reachable refusal sat unpinned —
the counted-claim class; the counts are gone and the branch is pinned.

**Red first, and the instrument lied once.** Before the implementation, the
current binary was fed both an argv operation and an argv `state`: line-named
refusals, exit 3 — measured in the working session, not kept as an artifact;
the durable red is structural, and review verified it: check 2ab's argv toml
exits 3 on any build without the feature, so the acceptance suite cannot go
green pre-feature, and the acceptance refusal checks plus the unit-test
refusal table pin the walls that replaced that one generic refusal. The one stumble: the first followup-95 run reported `rc=0` while
its own log said the apparatus had failed — the raw exit code went to `tail`,
not to the record. The pipe-hides-rc class, re-learned; the re-run reads the
raw rc before any pipe.

**followup-95: the sweep's hnb wall was the spelling, and only the spelling.**
Run in the sweep's own image (hnb 1.9.18 baked in), this branch's engine:
the wrapper spelling still refuses exactly as the #84 sweep recorded
(UNKNOWN, child_process_detected — the control), and the same question
spelled as argv explores fully and lands **FAIL — 1 violation over 3 crash
points, strict oracle agreeing on all 3 operations** (the engine's headline
prints "1 of 4", counting the baseline world — #150): hnb's save path rewrites `notes.hnb`
through truncation, and a kill inside the open→write window leaves the file
neither old nor new — the devtodo/calcurse class on a third target. The v3
case replays in a fresh work directory. Finding kept in-repo, deliberately
unreported (the devtodo target-selection call). One self-caught slip on the
way: the NOTES' Result section was drafted before the run — the
conclusion-before-measurement class R1 flagged on the #123 comment this same
batch — and was reverted to a placeholder until the artifacts existed.

**What did not change, verified rather than assumed.** No trace-contract
movement (no shim or record change; existing saved cases replay untouched),
no report-schema movement (the operation never reached the report), and
preflight is untouched — the plan's original hint-branch idea died in review
as unreachable code, and the real constraint (an argv-form define cannot use
preflight, because preflight is flags-only by its own refusal) is documented
where the argv form is.

## 2026-08-16 — #81: the README's agent section states two measurements and one absence

The batch's last PR adds the agent-onboarding section to the README's MCP
chapter: the two measured agent workflows stated separately (fix-from-report,
twice; define authoring, five targets in minutes), and the unmeasured path —
setup from the README alone — named as unmeasured instead of implied. The
lightweight review caught the draft doing, in miniature, exactly what the
#85 review's R1 caught at scale: "handed only the counterexample" had
dropped the bug-blind replay plumbing from the input list (PRD's own honesty
note says the input set is the report *and what it transitively names*), and
"documentation-reading protocol" implied a docs-only scout when the protocol
grants source, tests and trackers too. Both were claims of *less* access
than measured — flattering compression, the same overclaim class in the
humble direction. Fixed before commit.

The kill-criteria review (`docs/kill-criteria-review.md`) scores all eight
§18 conditions against the collected data — none triggered — and PRD
criterion 3 is checked on it. Three decisions worth recording at the moment
they were made:

**The preamble was checked, not skipped.** §18's own gate ("if Sideeye finds
nothing beyond existing hand-written adversarial tests") never opened — the
record contradicts its antecedent. The review runs anyway because criterion
3 asks for the review unconditionally; the page says so first, so a reader
knows the antecedent was examined rather than quietly bypassed — the class
of failure where a check's precondition quietly becomes false and nobody
re-reads it.

**Row 7 went to the owner, and the adjudication is recorded as one.** The
UX-difference condition is the only row whose wording makes
failure-to-demonstrate itself the trigger — no-data is not neutral there, so
no measurement could score it. Adjudicated 2026-08-16: not triggered, on the
measured in-repo differences (minutes-scale onboarding, agent-driven define
and fix, named refusals) plus the structural arena difference; the missing
head-to-head is disclosed on the page, and a real one supersedes the
adjudication in either direction.

**The wiring honored R2's backticked-ratio trap, and the dry-run lied once
first.** Check 11 now sweeps the new page; before wiring, the extractor was
run over the draft exactly as the plan required (18 tokens, all resolving)
and proven red with one deliberately broken reference. The first dry-run
attempt reported a false MISSING — the interactive shell here is zsh, which
does not word-split an unquoted variable, so the whole 18-line list arrived
in the loop as one "path"; the valid dry-run is the POSIX-sh replica of the
gate's own loop, which is also what CI runs. The one-off measuring
instrument was the broken part — the recurring class where the path you
measured is not the path that runs. Check 11's comment now warns that a
backticked ratio reads as a path — the page keeps every ratio in prose.

**Review round 1 reversed two evidence claims (recorded, per the contract).**
The reviewer verified every number against the primary artifacts and caught
the draft over-counting on both of the rows it was written to strengthen:
row 5 said "all four blocked assisted defines reached verified" where
REMEASURE records three of four (pass stayed refused — the control that is
*supposed* not to move), and row 3 attributed "topydo filings" with
replayable counterexamples where the record shows exactly one filing
(topydo#341, a plain-printf reproduction rewritten for reporting etiquette)
and a deliberate decision *not* to re-file the destruction class
(topydo#318 is a third-party report). Both corrections make the rows
stronger, not weaker — an unmoved negative control is reproducibility
evidence, and the un-filed counterexample is a reporting-policy fact, not a
complexity one. Same lesson as ever: the claims that exceed their artifacts
are the ones written from memory of the result rather than from the
artifact.

## 2026-08-16 — #141 + #144: two follow-up measurements, and both came back the good kind of boring

**#141 — the omamori surface probes, re-measured under v10.** DESIGN §18 had
banned its own calibration sentence from citation until
`spike/dogfood-omamori-surface.sh` re-ran; it ran (omamori 1.0.4, built
offline from a tracked-files archive with host-side `cargo vendor` because
this network's TLS interception kills both git-over-https and rustup inside
containers — the rustup shim kept trying to sync components, so the build
calls the toolchain's real cargo directly). The v8 walls are gone exactly as
the old pins predicted: install, setup and init no longer refuse at
`symlinkat`/`fchmodat` (#122 made symlinks first-class, #121 made the chmod
family recorded-only — three of the four reports' metadata lines name the
excluded `fchmodat x1`; verify observed none), and **all four unguarded
writers explore fully and PASS** (assisted image: install 16 / setup 28 /
init 6 / verify 4 crash points, reports committed under
`spike/followup-141/artifacts/`; the
spike-image family measured higher counts the same day — the counts are
image-sensitive, so the refreshed pins keep verdict+reason as the claims and
demote min_cp to a vacuity floor below both measurements). The citation ban
is lifted: §18's calibration paragraph and the target-classes Rust story now
carry the v10 record.

**#144 — the bogofilter-sqlite counterexample, triaged with the tool's own
reader.** The labeled follow-up (`spike/followup-144/`, outside the #84
corpus, reading the committed define verbatim) re-ran the sweep's define
with a checker asking bogofilter's own tools — `bogoutil-sqlite -d` plus a
real classification. First run was an apparatus lesson the engine caught
for us: bare `bogoutil` resolves through alternatives to the **BDB**
variant, which cannot read a sqlite wordlist at all — the checker was red on
valid state, and the run refused with the checker failing in 25 of 26
worlds rather than minting a false verdict. With `bogoutil-sqlite` named:
**FAIL 3/26 reproduced, and the checker passed in every explored world —
the violating three included** — the git COMMIT_EDITMSG template exactly.
Review caught the first draft of that sentence overclaiming: the report
records only the earliest violating world's invariant, so "never failed in
any world" was an inference over 24 of 26 worlds, not a record. The cheap
fix was the reviewer's own suggestion — the checker now appends one line
per invocation to a log outside the judged state, and the committed log
(`spike/followup-144/artifacts/checker.log`: the falsification gate's red
first, then 26 passes) turns the claim into an artifact, with run.sh
pinning its shape so a re-run that breaks it goes red. sqlite's journal
recovers the wordlist in every crash world; the disposition is
withdrawal-shaped (the buku class lesson, confirmed on a second store),
and nothing goes upstream.

## 2026-08-16 — #82: the timewarrior proof moves into CI, and plan review re-priced the whole issue

Two decisions before any code, both from adversarial plan review. First, the
issue's own framing was stale: #82 was written (and amended) before ADR 0017,
whose ordering requirement keeps the timewarrior finding at "discovered
automatically — partial" permanently — so this work is **regression hygiene**,
not criterion-1 progress, and the amendment's three definitions are
superseded. That is now written where the job lives, not argued here. Second,
the planned committed-case design (record once, replay-only in CI) died in
review: the reviewer measured five failure modes it would create — the case
freezes absolute paths to heredoc-generated scripts, the legs need state
resets, the recording is environment-sensitive (the distro-vs-pinned 19/24 op
split is this repo's own measurement of that), submodules were missing from
the fetch plan, and a shallow-fetched tree breaks the local re-clone — all
five of which `spike/dogfood-timew-replay.sh` had already solved and measured.
So CI runs the proven script itself: a `LEGS` selector (default `abcd`,
unchanged; `a` mandatory since b/c/d replay the case leg A records) and the
`timew-regression` job runs `LEGS=abc` per push. A per-leg detail the review
also caught before it shipped: the distro-timewarrior precondition was
unconditional, which would have killed `LEGS=abc` in exactly the environment
CI provides — it now belongs to leg d.

Measured: `LEGS=abc` in a container **without** the distro package — ALL LEGS
PASSED in **37s** (the +10min CI budget was over-cautious by an order of
magnitude); default `abcd` with the package — ALL PASSED, 35s, behavior
unchanged. Falsified both directions, with one embarrassment kept on the
record: the first red-C harness passed `PATCH=` as an environment variable,
but the script assigns `PATCH=` unconditionally — the override was silently
ignored, the REAL patch applied, and the "falsification" run came back green
with the real patch's sha in its own footer (the measured path did not reach
the thing being varied — the exact class this workspace keeps re-learning).
The second harness bind-mounted the no-op patch (a new-file-only diff) over
the script's hardcoded path; the footer then showed the no-op's sha and leg C
went red on the script's own path — "expected a clean replay PASS", got the
case reproducing, 1 leg failed, rc=1. Leg B's predicate — extracted verbatim
from the script by awk, not re-typed — exits 1 when fed a committed PASS
report. Local-only honesty note: this host's network intercepts TLS, so the
container clone ran with GIT_SSL_NO_VERIFY for these measurements — the
script's content trust rests on the full 40-hex pin (its own header's
argument), and CI verifies TLS normally on GitHub's network.

## 2026-08-16 — #84 sweep: the numbers land, and the composition is the finding

The sweep ran from the apparatus PR's merge (`b5b23fd`, engine 0.9.0 /
contract v10), all 49 corpus rows — one fresh container per executed trial
(36 rows; the other 13 are documented walls that never run), repo mounted
read-only, no SETUP_ERROR anywhere — `count.py check` closes green over the
full with-data path (49 digests, docs in sync).

**A-group: 1/28 UNKNOWN (3.6%).** The one is watson's recorded
nondeterministic-writer refusal, reproduced exactly. Everything else
reproduced its committed record too: topydo 12 FAIL + `ls` PASS with 0
crash points, abook and khal null, the four assisted counterexamples,
timewarrior a-PASS/b-FAIL, todoman both PASS. An engine that drifted from
any of those records would have shown up here; it did not.

**B-group: 13 walls, then 3/7 UNKNOWN (42.9%) — and all three are
define-budget refusals, none target-origin.** hnb and lbdb died on the
exec-chain rule their NOTES predicted before the sweep; cookietool's
recording was refused over its exit convention (10 — apparently the count
of deleted cookies — where the uniform protocol fixed 0). Of the five
targets whose documented invocations could be spelled as operation
strings, four reached verdicts; cookietool, the fifth, was refused on the
declared exit status, not on spelling — the first "4/4" draft of this
sentence was wrong, and review caught it against the frozen definition.
The striking row is **bogofilter-sqlite: FAIL 3/26, oracle agreed on
25 operations** — a fresh counterexample from a never-run target, in
exactly the buku shape (a sqlite store judged by file bytes is judged more
strictly than its journal contract). No checker ran, so no recovery was
measured, and the disposition stays new-this-sweep; its case file was not
preserved (the sweep keeps reports and transcripts, not replay cases — a
labeled follow-up run can re-derive it if triage wants one).

**Threshold (owner, 2026-08-16, set from the B data after seeing it):**
two-part — target-origin UNKNOWNs ≤ 1/7 (measured 0) and overall ≤ 50%
(measured 42.9%). Both hold; **criterion 4 is met**. The two-part shape
was chosen over a single rate precisely because the composition carries
the information: a contract that cannot spell an invocation is an issue
backlog, a tool the engine cannot watch is a product wall, and a single
number reads the two identically. The macOS column derives to 11/28 and
6/7 by the completeness formula — printed by count.py, never typed — which
is the per-platform honesty the #84 amendment asked for.

## 2026-08-16 — #84 apparatus: the corpus is fixed before the sweep, and the first draft could not fail

The UNKNOWN-rate measurement (v1.0 criterion 4) starts with the PR that must
merge before any number exists: `docs/unknown-rate.md` (the frozen rulebook —
unit, four axes, funnel walls, outcome-ratio classification, small-cell rule),
`spike/unknown-rate/` (corpus.tsv with 49 trials, five launchers, sweep.sh,
count.py, a third Dockerfile), and acceptance check 12 (the drift gate).

The first corpus design was killed in plan review, and the reviewer was right
in one sentence: **the measurement could not fail.** Every committed define
that reaches a verdict today is a define whose past refusal drove #121/#122 —
the assisted cohort went 4/5 UNKNOWN → 1/5 in one day when those engine PRs
landed — so a corpus of committed defines measures "did the engine catch up
with its own inputs", and a threshold set from its ~0% is satisfied by
construction. The shipped design splits the corpus: the A-group (28 trials,
10 tools, every runnable committed define — watson counted IN the denominator
as an UNKNOWN, since "supported" is a class property and watson is a Python
CLI) is published as the engine's development-input set and is not the
threshold basis; the B-group (20 targets nobody here ever ran) is, and its
members were selected by a committed debtags predicate over bookworm's own
archive metadata with a deterministic sort — the second review round caught
that "about 10, hand-picked from the predicate's pool" would have moved the
gerrymandering from the rate to the threshold, so no hand touches the list
(select-b.sh, b-candidates.txt, b-targets.txt are all committed; the one
hand-written input is the name-exclusion file carrying the taint ledger and
hledger's sealed eligibility). Of the 20, seven reached a uniform minimal
define (setup + one documented state-changing op + L0 + strict oracle;
grounds quoted per target in defines-b/*/NOTES.md — cookietool's man page
even documents its temp-file rewrite and a "CAUTION NEEDED" direct-overwrite
flag); thirteen are funnel walls (W1 does-not-install ×2 measured, W2
state-not-in-local-files ×9, W3 no-non-interactive-writer ×2), published as
funnel data outside the engine-rate denominator.

Decisions that will read as opinionated later, recorded now: taskwarrior is
in the supported table but has no committed define, and reconstructing one
today from BUILDLOG prose would be answer-known authoring — it joins the
corpus in neither group (the exclusion table says why); the campaign
declarations run through a thin open launcher that replicates exactly what
can move a verdict (HOME, the CHECK_* unsets, the state roots) and
deliberately not the seal machinery — CLAUDE.md now says a post-campaign open
re-measurement is not a campaign phase; macOS gets a derived column from the
requireCompleteness mechanism (every strict PASS → completeness_not_verified,
no oracle exists there), computed by count.py from a formula, never typed.

The gate was seen red before it was trusted, both sides: fixtures/good passes,
tampered-verdict (one report's verdict flipped, docs left stale) dies with
"published results block differs from recomputation", tampered-manifest (one
row deleted) dies with "manifest rows (2) != corpus rows (3)" — and check 12
re-runs all three every CI run, so the red proof cannot rot. Pre-data, the
live check asserts the explicit placeholder line: an empty table can never
read as a measured zero.

**The smoke run found what two review rounds did not.** The first uniform
B-group protocol wrapped every operation in an `op.sh` (for `$TOY_STATE`
expansion) — and the very first real trial (2vcard) came back
`child_process_detected`: a script that performs nothing state-changing
before its `exec` is an image change whose observation chain carries no
operation count, exactly the shape #137's structural rule refuses. The same
define spelled as a direct operation string explores and PASSes (3 worlds,
2 crash points, measured back to back). So the protocol now prefers
`op.txt` — a static command line with `$TOY_STATE` as a launcher-expanded
token — and keeps `op.sh` only where the engine's space-split contract
cannot spell the invocation (hnb's space-carrying command argument, lbdb's
stdin redirect), with the consequence written into those NOTES: a
chain-rule refusal there is the trial's honest verdict, because it is what
any user driving that target through the current contract would get. Also
measured on the way: the stale local `sideeye-spike` image silently lacked
khal at the toml's pinned path (`recording_run_failed`), while the image
rebuilt from the committed Dockerfile explores khal `import` to the same
PASS 10+1 the campaign recorded — the sweep builds its images fresh for
exactly this reason.

## 2026-08-15 — #78/#79/#80: found not plumbed, and two evidence-first pages

Batch b_309cfe196cf1. The shim default is the demo's resolver generalized —
the doc comment on `demoShimCandidates` had already deferred exactly this
move to #78 — plus realpath, so a reproduce line names the real file rather
than a `bin/../lib` spelling. One resolution point (the shared
`args.shim orelse`) covers explore, preflight and replay at once.

The oracle half shipped as a HINT, not a default. The plan-stage adversarial
review measured what silent attach would change: six acceptance checks pin
no-oracle behavior and the container carries strace, so they would all flip;
the MCP child would grow an oracle the server never configured; and
`--allow-unverified` without `--oracle` — an invocation that does pass a
flag — would change meaning, falsifying the "flagged invocations unchanged"
thesis as written. Named-never-attached keeps every verdict byte-identical
and still deletes the plumbing friction: the refusal now hands the user the
exact `--oracle /path` to paste. The deviation from the issue's letter is
recorded in the PR and in #78's close.

The target-classes page dropped the issue's Node/libuv claim — no committed
evidence exists anywhere in this repo — down to a labeled not-yet-measured
row, and the review reversed my own draft's omamori arc against the record:
the nondeterminism refusal came first, the L0 history form (#24/#25)
produced the PASS 143/143, and the 08-12 walls (symlinkat/fchmodat) have
since been removed for other targets without re-measuring omamori. Writing
the evidence table was itself the audit the covenant asks for.

New acceptance: shim found/absent (both sides pinned), hint present/absent
(the rc pin doubles as the not-attached proof), and a path-existence sweep
over the two pages — guarding path rot only; claim drift stays a
review-time axis. Sunset on the sweep: never fired by the freeze → removal
list. Running the suite caught one thing the plan review had predicted for
the oracle and I still missed for the shim: check 2h used a missing --shim
as its SETUP ERROR falsification, and the default turned that run into a
PASS — the trigger moved to a missing --state, and the zig-out layout the
incident exposed became check 9's third leg.

R1 (fresh reviewer, whole diff): no P0. The P1 was this batch's own
covenant applied back at it — two rows stated claims their named artifacts
do not contain (timewarrior's 25/25 lives in the buildlog, not the four
named spike paths; devtodo's "deliberately unreported" lives in NOVELTY /
PROTOCOL) — both fixed by naming the right artifact, plus two Walls
bullets that carried no artifact at all. P2s: the page and the changelog
claimed the sweep covers "every repository path" while the check's own
echo says "slashed backtick references" — the prose narrowed to what is
measured; the sweep's denominator is now asserted (a page whose extraction
yields under five references goes red instead of passing over an empty
loop, seen red on a synthetic page); the omamori arc gained its middle
wall (baseline_violates_invariant) so the page and this entry tell the
same story. The reviewer also ran the extractor for real: 35 tokens, all
resolving, none dropped, none foreign.

## 2026-08-15 — v0.9.0: the release rides a truth-up of the front page

The bump (0.8.0 → 0.9.0, minor by the contract-bump precedent — v8 rode
0.7.0, v9 rode 0.8.0) ships the v10 batch merged earlier today. The
release checklist's README-against-release step turned into real work
rather than a check: the findings paragraph still listed buku (withdrawn
this same morning), counted "two upstream reports" (four are filed — the
stow and calcurse reports went out 2026-08-15), and said novelty was
"deliberately unchecked" (the novelty round ran). Fixing #93 here
surfaced the same-class hits beyond the front page — DESIGN's overview,
its one-sentence definition, and the report schema's `earliest`
description all promised "smallest"/"minimal"; every one now says what
ships: the earliest failing crash point, saved as a replayable case.
#96's sandbox sentence landed in README's MCP section and ADR 0010's
consequences. One piece of bookkeeping: #134 had to be closed by hand —
PR #135 shipped it but referenced the issue without a closing keyword,
so the merge never closed it.

## 2026-08-15 — #123: the judge follows a single pid across execve (contract v10)

Third PR of the b_cd3b31e80b91 batch; the design is ADR 0018 and the
plan carried two adversarial review rounds before a line was written.
The shape that shipped: the shim's exec wrappers carry the operation
count (`SIDEEYE_SEQ_BASE` — subject-only via the armed-pid gate, which
excludes vfork children structurally; execve rebuilds envp in a stack
frame; overflow carries nothing rather than truncating the target's
environment), the re-run init continues numbering, `shim_ready`
re-announces the base as its seq, and the engine tolerates a subject
exec only when exactly that evidence follows. The oracle's own
primary-exec refusal is gone — chain integrity is the shim's evidence,
divergence is the oracle's net. `sequence_numbering_broken` is the new
refusal for the shape prefixHash provably cannot see (it probes 1..k
and stops at the first match; a restarted counter is a duplicate).

First-try measurements in the container, all four exactly as the plan
predicted: TOY_SELFEXEC judged end to end (the planted bug FOUND at
crash point 8 of 8, oracle agreeing on all 8 operations spanning two
images), TOY_FORKEXEC still refused as child_touched, TOY_EXECL (an
uninterposed exec — no record, no carry) caught as
sequence_numbering_broken, and ONE trace header across the image change
(the lseek guard promoted from convenience to load-bearing, now pinned).

The mutant sweep earned its keep twice over. Mutant A (disable the
continuation) failed to COMPILE, the container ran the stale binary,
and the suite came back all green — a textbook "unmeasured green"
caught only because the build's raw exit code was read; the harness now
gates on it and the mutant was rebuilt as a base-off-by-one (killed:
the self-exec check went red at exit 2). Mutants B and C SURVIVED their
single-line forms and both survivals were the two-witness design
working: the fork+exec refusal is held by the shim's foreign-kill-point
AND the oracle's child-touch (disabling both produced a false PASS at
exit 0 — killed), and the numbering refusal is held at the recording
AND in every world (disabling both likewise false-PASSed — killed). The
header mutant broke six checks at once, as a mid-file header should.

The v9→v10 re-record of the four assisted cases went verdict-identical
(2/22, 1/11, 6/8, 2/5; fresh-container replays all `the case
reproduced`) after two instructive trips: replay refuses before setup
when the state root does not exist to resolve, and buku's replay needs
the launcher's XDG environment — the cohort R1's "the toml does not
carry the environment" lesson, now measured on the replay side.
The buku inspection case (#133) stays v9 deliberately: its claim rides
its transcript and worlds log, not replayability.

R1 (fresh subagent) then broke the slice where the oracle's old refusal
used to stand and nothing had replaced it: an execl with ZERO in-scope
operations before it — no exec record, no window, and the numbering
check's two sides trivially equal — reached a **FAIL verdict** with the
second `shim_ready` sitting ignored in the trace (the reviewer decoded
it and pasted the record). The evidence was self-contained all along:
the constructor runs once per image, so a second same-pid announcement
IS an image change. The parse now refuses on exactly that, which also
made TOY_EXECL's refusal structural (the acceptance anchor moved to the
double-announcement message, seen red against the unfixed engine first;
the numbering assert stays as the second net, unit-pinned). The ADR and
CHANGELOG sentence claiming the oracle's completeness comparison covers
broken chains was wider than the code — narrowed to what is actually
computed. Also adopted: the report now DISCLOSES an unbroken chain
("the subject's image replaced N time(s), chain unbroken" in the
processes note — `exec_continuations` had been write-only outside its
own unit test, and the reviewer noted every other note in the report
names what the judgement covered while this one was silent);
`SIDEEYE_SEQ_BASE` is pinned empty in all three spawn env lists so an
ambient value in the operator's shell cannot become the first image's
base (measured: it turned a PASS run into a mis-attributed
sequence_numbering_broken); errno is saved across the failure-path
unsetenv in execv/execvp (glibc measured harmless, musl/darwin not —
the `remove` wrapper's discipline); README/DESIGN's "execs over itself
is refused" and README's v9 badge updated; the world-phase exec message
no longer claims more than its branch checks; TOY_EXECL gets its own
stage variable; the colliding `check 2x` label renamed `check 2ex`.
Not changed: the header-count check's dependence on the preceding run's
work dir — the block rm -rf's it first, so a stale file cannot survive
into the read.

R2 CONFIRMED all ten with its own re-measurements (the zero-op probe
now refuses; ambient SEQ_BASE runs PASS again; the disclosure appears
in text and JSON). Two of its notes acted on: the printed `reproduce`
line now pins `SIDEEYE_SEQ_BASE=` (the acceptance executes that line,
so an ambient value would have made it diverge from the engine's own
runs — the same class as the spawn-env pin), and the image-change
disclosure moved to right after the trace is trusted so the JSON
`processes` field is honest on oracle-refusal paths too, with the
children note now composing around it in either order. One note
recorded rather than fixed, so a stale mutant result is never cited as
current: **the numbering-assert wiring in main.zig no longer has live
acceptance coverage** — the structural double-announcement rule catches
the execl shape first, and R2 measured the both-asserts-off mutant
SURVIVING the current suite. The wiring stays as the second net, its
computation unit-pinned; a live shape that reaches it would need a shim
that renumbers without re-announcing, which no interposed path
produces.

## 2026-08-15 — #130: the assisted funnel gets its verify-seals — and building it hit both failure modes it exists to catch

Second PR of the b_cd3b31e80b91 batch. `spike/assisted/verify-assisted.sh`
machine-checks that an assisted claim's question preceded its answer: D1
(the define's introducing commit strictly precedes the first
report/case/transcript artifact's, on the FIRST-PARENT order of main —
squash and merge read the same, and local commit-splitting cannot
reorder a pushed history), D2 (define blobs byte-identical at both
points; the launcher is D2-held when it exists but never moves the
define point), D3 (every scanned file listed with its introducing
commit). PROTOCOL.md gains the claim rule ("Claiming criterion 1"):
push the define, then explore, then push the artifacts, and a claim
commits the verifier's transcript. Exploration stays ungated.

Building the checker produced two textbook instances of its own subject
matter. First, the D1 comparison shipped inverted (rev-list is
newest-first; "precedes" is a LARGER position) — drill 1, the clean-
order green case, caught it on the first run. Second, on the real
history the walker returned an introduction a day older than the cohort
itself: git's similarity matching recorded fresh cohort reports as
**C071 copies of an unrelated blind-hunt JSON**, my rename handling knew
R but not C, the file silently fell out of the anchor set — and the
narrowed set produced a **false green D1 on devtodo**. Both fixed:
rename/copy hops are honored only inside the target directory (a hop
from outside IS the introduction), and an unresolvable file now stops
the run at exit 2 — a narrowed anchor set is not an answer. Drill 5
pins that. All five drills seen red/green for their own reasons
(`verify-assisted-drills-run-2026-08-15.txt`).

The cohort run
(`verify-assisted-run-2026-08-15.txt`): all five targets red, uniformly
"define and first artifact were introduced by the same commit
(daa6a93)" — the single PR #119 merge, exactly what the plan's reviewer
measured at commit granularity and ADR 0017 admitted in prose while the
check did not exist. A record, not a certification; the rule binds
claims from today.

R1 (fresh reviewer) then broke the first version four more ways, every
one a variation of the class this checker polices. P0: the file sets
came from filesystem globs, so an UNCOMMITTED `rm` of two define files
flipped a red target green — the sets now come from `git ls-tree` of
the anchor ref, and a working-tree difference is noted and ignored.
P1s: the walker took the NEWEST introduction for artifacts, so
delete-and-re-add laundered an artifact's age (an artifact now anchors
at its OLDEST in-target existence event); the out-of-target
rename-terminate rule doubled as an out-and-back laundering path
(rename hops are now followed in both directions, and only in-target
events count — which also lets git's cross-repo similarity noise stop
counting on its own); the five drills killed none of the rename/copy
machinery (six named mutants all survived); and the committed cohort
transcript carried twenty vacuously-true "D2 ok" lines — a same-commit
comparison measures nothing and now says "not evaluated". Drills grew
to twelve, one per mechanism, and all six of R1's surviving mutants
were re-run against them: 6/6 KILLED. Artifacts also match at any
depth below the target now (the answer can sit in inspection/ or
evidence/), and a merge-commit introduction is annotated in D3 since
first-parent order deliberately ignores side-branch author dates.

R2 confirmed seven of eight and caught the eighth half-closed: the
tree-sourced set fixed only the UNCOMMITTED deletion — a committed
deletion removes the path from ls-tree too, and R2 reproduced the same
false green against the fixed HEAD (delete the early report in a
commit, add a dissimilar one). The denominator is now the anchor tree
united with every path the first-parent history introduced under the
target; paths no longer in the tree are annotated in D3. Drill 13 pins
it. R2's independent mutant re-measurement (in-clone, with a no-op
control that correctly SURVIVED) also confirmed 6/6 — and flagged that
an out-of-repo copy of the script makes every mutant look killed
because drill 10 fails for the wrong reason; its in-clone method is
the one to reuse. Verified after the fix: the five-target cohort
transcript is byte-identical (the real histories contain no deleted
artifact-shaped paths — R2's measurement, reconfirmed here). Its one
remaining nit — four mechanisms hang on a single drill each, and
confinement's only kill depends on the C071 record staying in this
repo's history — rides the PR as a recorded follow-up.

## 2026-08-15 — #134: the gate's child output now carries falsify: on every line

First PR of the b_cd3b31e80b91 batch (plan reviewed adversarially twice;
Codex was out of credits, so a fresh subagent carried both rounds — same
fallback as the novelty round). The mechanism this closes is the buku
misread: the falsification gate produces, by design, exactly the output
a real finding would, and a single unlabeled line harvested from the
transcript became "world evidence" that survived four review rounds.

The shape: the gate's checker child now runs through
`posix.runChildCaptureAll` (a new variant that sends both streams to one
file — `runChildCapture` redirects stdout only, and the `dup2(1,2)` that
looked reusable turned out to live inside the minimal-env branch), and
the capture is read back and re-emitted line by line on stdout with a
`falsify: ` prefix, before the probe's verdict is judged so the refusal
path keeps its evidence. A per-line prefix rather than a fence because
the harvested artifact was a single line, and a fence does not travel
with an excerpt. World, recording and setup output are unchanged — the
plan's reviewer wanted the world-phase checker labeled too, and that was
declined with reasons recorded in the plan: the failure class is
gate-vs-world confusion, and labeling the gate side alone makes an
unlabeled checker line unambiguous.

Measured: unit tests green; the container acceptance suite green
including the new two-sided count — the buggy-toy run has the checker
speaking in both places, so the check asserts gate lines labeled (x1)
AND world lines unlabeled (x1), neither side empty (a silent checker
would satisfy a presence-only grep vacuously). Seen red once: committing
first, then mutating the re-emission loop away, the check failed with
`gate falsify-lines=0` — killed, restored. One compile slip worth
keeping: `zig build test` stayed green while the cross-build failed on
an un-updated `runChild` wrapper — Zig's lazy analysis means a green
test step does not prove every call site compiles.

R1 (fresh subagent) found a P0 this change had introduced and measured
it end to end: the capture stub's `_exit(126)` (capture file cannot be
opened) read as "the checker went red", so a directory squatting on the
default /tmp work dir's capture path let **/bin/true pass the gate** —
on main that exit was unreachable at this call site, so a regression,
not a pre-existing hole; the reviewer even showed the sibling 127 case
is netted downstream by the baseline while 126 escapes precisely
because the gate and the worlds now spawn differently. Fixed
fail-closed: exit 126 at the gate is now `checker_not_falsified` with
the stub named in the message (the discrimination mcp.zig already
made). The new acceptance check was seen red first against the unfixed
binary — where the squatting directory produced a clean **PASS** with an
unfalsifiable checker, one step worse than the reviewer's FAIL example.
Its P3s: my "121 ok" count did not reproduce (116 on a clean re-count;
117 after the new check — the verdict reproduced, my number was a hand
count over a file that included more than the suite), and the loud
read-back line now names the 1 MiB cap as a possible cause. Accepted
residuals, recorded: single lines over say()'s 16 KB buffer are dropped
with a generic overflow message (evidence loss, not misattribution),
and the capture opens without O_NOFOLLOW|O_EXCL — the same class as
every existing capture in the work dir, one more instance rather than a
new class; hardening the class is issue-worthy, not this PR.

## 2026-08-15 — buku downgraded to no finding: the "buku could not read it" line was the falsification gate talking

The buku disposition below ("held pending a plain reproduction") ended
today, and not the way either branch anticipated. The open question was
why 38 plain strace kills all recovered while "the engine's recorded
world" showed buku's own `initdb(): file is not a database`. The answer:
**that world never existed.** The committed transcripts contain the
initdb line exactly once each — at the falsification-gate position, where
the engine deliberately corrupts the state and requires the checker to go
red before the run. Every report beside it even says so ("falsified
before the run: corrupted state -> check failed"). The case's
`violation: hybrid` is an L0 content kind (neither-old-nor-new), not "the
checker also fired"; I read it as the latter, and with that reading the
gate's line became a crash world's evidence. The cohort RUNLOG wrote "in
at least one world", NOVELTY.md and RESULTS.md inflated it to "2/22
worlds" by merging it with L0's violation count, and yesterday's entry
below repeated it as the reason the finding was held rather than
withdrawn.

Measured today (committed under `spike/assisted/buku/inspection/`): the
committed define re-run with an instrumented checker that dumps every
visited world before applying the committed logic verbatim. Same verdict
(FAIL, earliest 18 of 21, 2 violations) — and the checker **passed in
all 22 worlds**. Both torn worlds hold a fully-synced hot journal beside
the torn db; buku's recovery-open rolls back, answers the bystander
query, and cleans the journal up. A plain strace of the same add shows
why that is structural: the only neither-old-nor-new windows lie between
sqlite's three db page writes, each bracketed by the journal it just
fdatasync'd. So the L0 hybrid is a true byte observation that sits
entirely inside sqlite's documented recovery contract, buku holds no
finding at all, and the two-day hunt for a plain reproduction was
chasing a transcript misread, not a fragile bug.

The general shape is worth keeping: **a guard that proves the checker
can fail produces, by design, exactly the failure output a finding would
produce — and the transcript interleaves it unlabeled with world
output.** `target-error-line.txt` is a one-line harvest of gate output
promoted to target evidence, and it survived the cohort reviews, the
remeasure reviews, the novelty round and the upstream round, because
every layer read the prose, not the position of the line in the
transcript. Candidate engine fix, not yet filed: label
falsification-gate target output in the transcript (a `falsify:` prefix
or a begin/end fence) so it cannot be quoted as a world's.

R1 on the correction (fresh reviewer, same day) returned one P0, three
P1 and six P2 — all adopted, and two deserve their own record. First,
the P0: my same-class sweep for carriers of the withdrawn claim used
`grep ... | grep -v transcript` to exclude transcript FILES and thereby
dropped every LINE containing the word "transcript" — including
NOVELTY.md's strongest form of the very claim being withdrawn ("the
checker did fail in one world ... and that transcript is committed").
The exclusion excluded a known hit; the filter unit (line) differed
from the intended unit (file). Second, R1 strengthened the correction's
own footing: the committed remeasure transcript alone proves no world
checker failed — check.sh prints only through `fail()`, the line
appears exactly once, the gate must fail or the run ends UNKNOWN
`checker_not_falsified`, and `checks_run` counts exploration-phase runs
only — so the instrumented re-run is corroboration, not the load-bearing
leg, and the RUNLOG now says so in that order. The re-run itself was
redone through a committed launcher (`inspection/run.sh`, environment
as `ops/explore.sh` — the lesson this repo already paid for in
campaign 2) with the verdict transcript and case committed beside the
world dumps, the instrumented checker's leg order restored to the
committed checker's, and the visit-to-world mapping derived in the
RUNLOG rather than assumed. Residue closed across NOVELTY.md (the HELD
section now reads WITHDRAWN), RESULTS.md (a dated note under the
owner's scoring — the numbers stand as scored; re-scoring is the
owner's), PRD.md (a new dated status paragraph: novelty four-for-four,
two reports standing, buku withdrawn, three live assisted findings) and
ADR 0017 (two dated inline notes marking buku's later resolution;
engine-level statements stand).

R2 CONFIRMED all ten and added one strengthening observation adopted
into the RUNLOG: the instrumented case's `prefix_hash` is byte-identical
to the committed remeasure case's — the two runs share the same recorded
trace prefix, a mechanical bridge tighter than matching summary numbers.
Its two non-blocking nits (a dead report.json harvest in run.sh — the
engine writes that file only under `--json` — and the oracle-less
re-run's report wording) were fixed and the inspection re-run through
the updated launcher; the artifacts are identical in structure, gate at
line 7, 22 world PASSes, same prefix hash.

## 2026-08-15 — Three reports filed, one finding held: the report step is a harder gate than novelty

Owner instruction for this round: plain bug reports, no mention of this
project or its experiments, and no AI-slop prose. That constraint turned
out to be a technical gate, not a stylistic one. A report nobody can
reproduce without our shim is not a report, so every finding had to be
re-derived from scratch with tooling a maintainer already has — strace's
`-e inject=` fault injection — before a word was written.

Three survived that and were filed; one of the three was then withdrawn
on a fairness call the owner made and I should have raised before filing
(below). calcurse #529 (interrupted `-P` leaves apts at zero bytes; the
syscall log shows `open(O_TRUNC)` then the kill), devtodo #9 (same shape
on .todo, and the next run says "database corrupt" in the target's own
words — withdrawn), stow #139 (the unfold sequence
`unlinkat(sub)` → `mkdirat(sub)` → `symlinkat` ×2, killed anywhere inside
it, leaves the already-stowed package unreachable). Each carries a
measured reproduction rate — 5/5 with injection, 2/2 clean without — and
each names what was not checked. The stow report says outright that no
atomic symlink-to-directory swap exists and asks whether documenting or
detecting the window is preferable, because pretending not to know that
would waste the maintainer's time.

**buku did not survive, and that is the entry worth keeping.** Thirty
eight plain kill points — eight on db writes, ten on journal writes,
twenty on the two interleaved — all end with sqlite rolling back and buku
reading its store normally. Zero reproductions. The engine's recorded
world is not withdrawn (the checker failure with buku's own `initdb():
file is not a database` is committed), but two things follow. A finding
that only our harness can produce cannot be reported, full stop. And the
earliest violation in that run was L0, a BYTE comparison — for a
journaled database, a mid-transaction byte state is precisely what the
journal recovers from, so L0 is stricter there than sqlite's own
contract. That is a limitation of judging a journaled store by file
bytes, not a defect in buku, and it means the finding rests on the single
checker failure alone until someone reproduces that world plainly.

**And a third question, which the owner asked after the filing and which
belonged before it: should this project be on the receiving end at all?**
devtodo is a legacy project its author calls stable, star count in single
digits, chosen for the cohort because apt had it — not because anyone
here uses it, and not because its users needed the news (Debian's tracker
already carries adjacent reports on the same code path). A data-loss
report from a stranger who does not use your software is work you did not
ask for, and the evidence value of filing it accrued here, not there.
The issue was withdrawn with two sentences (a long apology is more of the
same imposition), the finding stays in this repository, and the rule now
sits in `spike/assisted/PROTOCOL.md` at TARGET SELECTION, where the cost
is actually incurred: explore anything, but decide before running whether
a finding would be reportable, and record that decision with the target.

The general lesson, recorded because it will apply to every future
finding: novelty asks "has anyone reported this", the report step asks
"can anyone else see it", and the step before both asks "is it fair to
send this here". Today the second question killed one of four findings
and the third question killed another — both after they had passed the
first.
## 2026-08-15 — The novelty round: four searches, four not-founds, and the boundaries say so

The step the criterion-1 redesign designated ran the same day: recorded
tracker searches with positive controls, the campaign-1 shape, for all
four assisted findings. Verdict on every one: **not found — novel as far
as each search sees** (`spike/assisted/NOVELTY.md`, terms and hit counts
recorded for re-running). The controls did their job in three different
shapes: buku's proved the vocabulary reaches issue BODIES (a body-only
"corrupt" match), calcurse's found a real existing apts-corruption issue
by the same word that would have found ours, and stow's used the domain's
own vocabulary (twelve fold/unfold threads, ten open) while every
crash/interrupt/atomic term returned zero — the failure class is absent
from that tracker's language entirely.

**The review round earned its keep on the denominator.** The first pass
enumerated devtodo's Debian BTS from the OPEN view — 4 bugs — and called
it the tracker; the combined open+archived view holds ~70, including
grave #511342 among 72 bugs, which sits on the exact code path our finding kills:
`open(".todo", O_TRUNC)` on the in-place rewrite — reported for IGNORED
ERROR RETURNS (EACCES, exit 0, nothing written, no crash anywhere in it;
fixed in 0.1.20-4). Same path, other side of the syscall boundary; the
not-found verdict survives, and the disposal is now written down instead
of lucky. The same round corrected the counterparty claim (the
"unmaintained since 2010" line was the Debian QA opener's — the upstream
maintainer replied "It is maintained, it's just stable" in the same
thread), caught a `--limit 20` ceiling transcribed as a hit count
(calcurse's apts term: 34, and the 14 hits beyond the window contained
two plausible titles, both read, both disposed), and left ~25 extra
probes across the four trackers with no verdict changed. A results
document whose defining property is re-runnable coverage got exactly the
review such a document deserves: the reviewer re-ran it.

Standing notes: stow's GNU mailing-list archives were not searched (the
one adjacent thread, #29, ARRIVED from the list — suggestive of
funneling, not proof), and buku's mechanism attribution (buku's sqlite
usage vs an unavoidable tear) is deliberately left for the upstream
conversation — novelty asked whether the finding was already reported,
not whose fault it is. Upstream contact is the next step and needs
per-report owner approval.

## 2026-08-15 — Criterion 1 is redesigned around provenance (ADR 0017), on the owner's ruling

The §18-class decision #118 reserved for the owner is made: option A of
three presented (redesign / add an OR-route / keep and re-arm blind).
The criterion's gate moves from "the question was posed blind" to "the
question's provenance is recorded and labeled"; novel, author-confirmed,
fixed and replayed stay exactly as they were, and an assisted finding
still may never wear the blind label. The full argument for why this is
a redesign and not a moved goalpost — the order of evidence, the
pre-committed rule in #118, the falsified hypothesis — is ADR 0017; the
PRD's criterion text and status trail now carry it.

Alongside, three bookkeeping debts flagged by review: ADR 0012, 0015 and
0016 still said Proposed after their Seal A PRs merged (the repo's own
convention flips them at merge); flipped now with the flip's lateness
recorded in the status line itself. What this unlocks next is mechanical
and deliberate: tracker searches with positive controls for the four
assisted findings — stow's unfold, devtodo's in-place rewrite, buku's
torn db, calcurse's purge — then upstream contact for whichever survive.

**The adversarial R1 reshaped the ADR more than any review today reshaped
code.** Its charge was to refute the redesign-not-goalpost argument, and
it could — against the draft as written, not against the decision. Three
sentences claimed more than the record: "run to exhaustion" (only the
sealed pool is spent; ADR 0012 leaves the fresh-seals door open),
"before any of the evidence existed" (the nulls WERE known when #118
pre-committed the redesign path — the true margin is eighteen minutes
before the first assisted run, found in the issue's public edit history,
now disclosed rather than discoverable), and "falsified the hypothesis"
(the experiment measured where the constraint was; topydo reached
verified counterexamples blind and still failed on novelty, so reaching
a verdict was never the value claim). Each was rewritten to the measured
statement, which is stronger, not weaker. The review also found the two
structural misses: DESIGN §17 still carried the old criterion (ADR 0012
names PRD/DESIGN as its joint home — the same-class sweep stopped at
PRD), and the new text had a hole the old one covered implicitly — no
requirement that the question precede the answer, through which
timewarrior's "partial" would have silently become a pass. The criterion
now requires the invariant committed before any observed failure, and
the ADR re-scores all three past findings explicitly. The owner's ruling
(option A of three) is posted to #118 with this merge — the review
rightly noted a decision whose defence rests on pre-commitment cannot
live only in a session transcript.

R2 confirmed all sixteen R1 findings closed and then found the guard's
own hole, in this workspace's most familiar shape: the sentence added to
close H5 was itself unlimited — "before any failure of the target was
observed" names no observer and no mode, so read literally it
contradicted the ADR's own re-scorings (topydo's failure surface was on
a public tracker since 2023; every mature assisted target likely has
failure reports somewhere). The wording now says whose observation
counts: "before THIS PROJECT observed any failure of the target IN
EXECUTION (reading a report of a failure while scouting is not observing
one)" — timewarrior still blocked (its strace triage WAS this project
executing and observing), scouting still legal by text rather than by
charity. R2 also caught the ADR naming the wrong proof mechanism for
assisted ordering: the proposal-artifact-first rule it cited was broken
on three of five first-cohort targets (RESULTS.md's own record), and no
verify-seals equivalent exists for the assisted funnel — the ADR now
says the honest weaker thing (committed define + measured windows +
review, not a seal) and names the machine-check as open work. One digit
rounded the wrong way (eighteen → seventeen minutes) — in the sentence
that says "it is the true one", of all places.

## 2026-08-15 — v0.8.0, and the README stops being a changelog

The bump rides the owner's earlier ruling (next engine change ships a
release; contract v9 is that and more). With it, an owner instruction:
the README had gone stale — its Status headline still said "v0.5 — the
loop closes" two minor versions later — and it should be SIMPLE, per the
Utrecht reproducibility workshop's README guidance (title/description →
installation → usage → example → license; plain language; copy-paste
commands; short scannable sections; link out for depth).

The rewrite's structural decision: **the per-version milestone list is
gone.** It was the README's main rot engine — a hand-maintained shadow
changelog that had to be extended every release and wasn't (the v0.5
headline), on top of the sample-report block that missed new report
lines two PRs running. Version-relative narrative now lives where it is
already maintained (CHANGELOG, PRD); the README keeps one Status line.
The sample FAIL report is now REAL regenerated output from this release
(toy-bug cross-compiled, explored in the container with checker +
oracle) — which immediately caught a third drift instance: the old
hand-patched sample was missing the `expected  exit 0` line that reports
have carried since #98. Real output wins arguments that careful editing
keeps losing. The real-tools sentence names the six targets with
replay-confirmed counterexamples and says plainly that only two are
upstream-reported and the rest are novelty-unchecked — the same honesty
budget the reports themselves spend.

The judge-first ruling paid out the same day. The committed defines from
the #118 cohort, re-run unmodified against main `647acbf` (v9 engine +
option b) in the cohort's own container: **stow FAIL 2/5** at the unfold
window (`unlink(target/sub)` → `mkdir(target/sub)` — the fold symlink is
destroyed before the real directory exists, exactly the L0 `missing` R2
forecast, with the L2 checker agreeing), **devtodo FAIL 6/8** (the XML
database rewritten in place through truncation — crashed content neither
old nor new), **buku strict FAIL 2/22 with the oracle agreeing on all 21
operations** (the #120 suspension resolved the way R1's analysis said it
would: the question re-posed fresh, the torn-db answer came back
verified, `fchown x1` observed-and-excluded in the report), and
**calcurse FAIL 1/11 re-recorded under v9** (its cohort case was v8,
dead by contract mismatch — the cost the CHANGELOG named, paid). pass
stayed UNKNOWN on exec detection — the control confirming #123 is real
remaining work, not noise. All four cases replay from committed files in
a fresh container (rc=1, reproduced). One slip recorded: the first stow
run's `--rm` container discarded the saved case; repeated in one session,
identical verdict both times. Full record: `spike/assisted/REMEASURE.md`.
Novelty of all four findings deliberately unchecked (separate step).

## 2026-08-15 — Ownership and permission writes become recorded-only (#121, option b)

The second half of the owner's judge-first ruling. Option b was chosen in
the issue's own terms: the cheap unblocking that declares, in the
contract's terms, that ownership/permission bits are outside the judged
state. The oracle gains a metadata table (chown/lchown/chmod path forms,
fchownat/fchmodat *at forms, fchown/fchmod fd forms — the last scoped from
the descriptor annotation like every fd syscall), and an occurrence on the
state directory is appended to a per-run list instead of routing anywhere
that refuses. Three exclusions travel together, deliberately: not
`unsupported` (the subject's branch), not a touch (the child branch — a
child's chmod changes nothing the verdict judges either), never a kill
point. An UNRESOLVABLE metadata write is counted too: over-reporting an
exclusion is the honest direction, because the report says "excluded",
never "did not happen".

The report grows a constant `metadata_writes` field (text + JSON, §13).
Its no-oracle default is the point of the design: "not observable (no
oracle ran; the shim does not interpose ownership/permission calls)" —
the buku scoring suspended a finding precisely because nothing could see
the fchowns behind an --allow-unverified run, and a field that read "none
observed" there would repeat that lie structurally.

No contract bump: the trace format and every class's meaning are
untouched — the shim records exactly what it recorded before. What
changed is what the ORACLE does with syscalls the shim never saw, and
the report schema (documented, schema-checked in CI by check 4's
field-parity claims).

CI carries the end-to-end pin: acceptance 2w-b drives a toy chmod on
state under strace — PASS with the note in both report forms, where the
pre-#121 binary answered UNKNOWN unsupported_syscall_observed (the
seen-red inversion, same argument as 2v) — plus the control that keeps
the net honest: a toy mknod must still refuse, because the exclusion is
a defined list, not a loosened net.

Mutation record, against the committed code (commit first, then mutate):
chmod removed from the path table, the path form gated to the primary
only, fchown removed from the fd table, and the unresolvable arm demoted
to inside-only — each killed by the #121 unit test's corresponding
assertion. The report-note aggregation in main.zig is deliberately not
mutation-tested at unit level; 2w-b is its proof, against real strace
output on CI.

**R1 (same day) found the same pattern #122's review found — removing a
refusal exposes what the refusal was hiding — three more times.** (1) A
chmod-only operation lands in the zero-op PASS branch, whose headline
("performed nothing that can change the state directory") R1 measured to
be plainly false over a changed mode, and which printed no metadata line;
the headline now says "the judged state" and the branch prints the note.
(2) restore() flattens ownership/permission to the engine's defaults —
crash worlds do not run under the recorded modes, which is both the
likeliest way the cohort re-runs could stumble and, correctly read, just
option b's declaration showing up at world level; the metadata note now
says so per run rather than leaving the next investigator to rediscover
it. (3) deleteTree accepted a PARTIAL failure — an unreadable 0000-mode
directory is skipped silently by opendir, its rmdir fails, and a
deletable sibling made the pass count as success, leaving residue for
the next world to be judged against (the function's own history entry,
survived by its own fix). The pass now requires every collected entry
removed; a non-root test pins it with a locked directory beside a
deletable file. R1 also demanded the exclusion's own predicate be pinned
rather than inferred: a new engine test asserts a chmod leaves the
snapshot byte-identical — if Entry ever grows a mode field, that test
goes red and the report wording has to change with it. Table hygiene from
the same round: fchmodat2 (glibc 2.39 spells flags!=0 fchmodat with it)
joins the table — built from the syscall family, not from what the
cohort happened to hit — and the timestamp family is documented as
deliberately absent (widening the exclusion is its own ruling, not a
side effect). Fix-round mutation: the deleteTree guard reverted to
`removed == 0` is killed by the partial-failure test.

R2 caught the fix under-covering its own finding: the restore-flattening
sentence rode only the writes-observed branch, while flattening is a
property of RESTORE, not of the target's syscalls — a setup-created 0600
file runs its worlds at 0644 whether or not the target ever chmods,
which is precisely the buku shape (sqlite fchowns only as root). The
sentence now rides both branches. R2 also measured that the zero-op
disclosure works end to end, verified the deleteTree strictness has no
false-fail path (an unreadable-but-EMPTY directory still rmdirs on the
parent's permission alone), and noted one behavioural edge worth naming:
a name vanishing between readdir and unlink — a still-writing straggler —
used to pass silently and is now a loud SETUP ERROR, consistent with the
quiescence refusals. And the README's sample report block missed the new
report lines for the SECOND consecutive PR (the string sweeps keep
stopping at acceptance pins); fixed again, and the recurrence is flagged
to the owner as a structure question, not another instance fix.

## 2026-08-15 — Symlinks become a first-class operation; the real gap was restore, not the oracle (#122, contract v9)

The owner's ruling on #118's product decision: close the judge's measured
gaps first (#122, then #121 option b), re-run the blocked committed
defines, and only then decide §18 with a re-measured number. This entry is
the first half.

The oracle table was the visible absence, but the engine was the real
work: snapshot recorded a symlink as "present but opaque" (kind `.other`,
no target) and **restore did not recreate it at all** — a state directory
with links would have started every crash world with the links missing.
That was tolerable only because the oracle refused symlink-touching
targets before any world ran; making the class supported without fixing
restore would have shipped fabricated worlds. So: snapshot content is now
the readlink target (fail-closed on a result that fills the buffer —
truncation cannot be told from an exact fit), restore recreates links
verbatim (a dangling link is restored dangling), and judgeL0 checks kind
before content — a regular file holding the pre-target as *bytes* would
otherwise satisfy the content comparison while being a different thing.
That kind check also closes part of the standard arm's documented
empty-content blind spot (an empty pre file replaced by a directory used
to compare equal).

Decisions made here, with their reasons:

- **Contract v8 → v9.** The v6 precedent (link/linkat) decides it: adding
  a class changes what a trace means, and a v8 shim beside a v9 engine
  must refuse loudly, not diverge positionally. Cost accepted: every
  saved v8 case replays as `case_no_longer_applies` — the assisted
  cohort's two committed cases need re-recording, and #82's pending
  re-record stays pending.
- **`aux` stays empty for symlink.** The target string is content the
  subject chose, not a path this run touches — the oracle already
  excludes it from scoping (its path table lists only the link-path
  argument), and recording it would hand every later consumer a
  plausible-looking "path" that must never be resolved. Symmetry beats
  convenience: nothing that needs the target exists today (restore reads
  it from snapshots, not traces).
- **corruptState retargets links** at a probe name that exists nowhere,
  and the falsification gate counts corruptible entries (files + links)
  instead of files — a stow-shaped state (directories and links, zero
  regular files) used to read as "nothing to corrupt", which would have
  refused exactly the target class this change exists to reach.

Mutation record: four guards, each killed by the test written for it —
judgeL0's kind check, restore's symlink arm, corruptState's retarget, the
oracle's class entries. The first corruptState mutation was invalid (it
left an unused local and died as a compile error — a red for the wrong
reason); re-shot as a compiling no-op branch and killed by the fs test.
The shim wrappers have no unit-test harness (nothing loads the .so in
`zig build test`); their end-to-end proof is the container re-run of the
stow define, which is the next step's acceptance criterion.

**R1 (same day) reshaped the change in two ways worth recording.** First,
the certain CI red: acceptance check 2v still demanded the refusal this
change removes — R1 also measured, on macOS, that the TOY_SYMLINK run now
PASSes with the symlink counted (crash points 4 → 5), which is the first
live evidence of the macOS interposer working. The check is flipped to
assert the v9 contract (PASS + exactly one class-10 record) and becomes
the Linux end-to-end pin. Second, and central: removing the oracle's
refusal EXPOSED a pre-existing silent skip — a shared path whose kind
changes between the clean runs (stow's unfold: fold symlink → real
directory) was outside both built-in invariants and outside the report's
disclosure. The owner ruled to judge it in full rather than disclose-only
or refuse: the identity on each side is the (kind, content) pair, killed
mid-swap the path matches neither, and the file world's delete-then-
recreate window was already judged `missing` — the kind change was an
escape hatch, not a policy. L1's standard arm now promises the post
(kind, content) pair from the plan, and a post-only symlink is judged by
target (the existence-only rationale — content may differ between runs —
does not transfer to a link, whose target is its whole identity).

R1 also caught this entry over- and under-claiming. Over: the readlink
fill-the-buffer guard could never fire on a real platform (`max_path` ==
PATH_MAX), so "fail-closed" was a claim nobody could falsify — the guard
moved into `readLinkTarget(buf)` and the boundary is now hit for real by
a test with an 8-byte buffer. Under: two silent-wrongness fixes this
change makes were never claimed — `snapshotsEqual` now distinguishes two
links with different targets (both read as `.other` + empty content
before), and `kindOfPath` no longer reports a symlink-to-file as a
regular file on DT_UNKNOWN filesystems (it used to read the POINTED-AT
bytes into the snapshot). Both are real fail-open closures that came
along with making the kind first-class. The judgeL0 kind strengthening
also reaches beyond symlinks: an empty pre file replaced by a directory
used to compare equal and no longer does.

Fix-round mutation record: the classify skip-revert, judgeL0's pre-kind
half, L1's post-only target check, and the readLinkTarget `>=`→`>`
boundary — each killed by exactly its own test. One process slip during
the round, recorded because it will happen again if unrecorded:
`git checkout -- src/engine.zig` after a mutation run reverted the file
to the last COMMIT, which silently discarded the not-yet-committed R1
fixes and made the next mutation a no-op against old code (rc=1 for the
wrong reason — a compile error in a neighbouring file). The fixes were
re-applied and committed BEFORE re-running the mutations; the rule is
"commit first, then mutate", and the redo killed all four legitimately.
Left alone on purpose: `spike/assisted/RESULTS.md` still says stow is
blocked — it is the first cohort's sealed record, and the re-measurement
writes its own.

## 2026-08-15 — spike/ gets a map; the cleanup that was NOT done is the point

Three campaigns plus the assisted cohort left spike/ dense enough that the
owner asked for a tidy-up. The honest finding: most of what looks like
mess is sealed design. The per-campaign tool copies are the forward-carry
rule (check-sealed-campaigns.sh fails a campaign that dropped its
checker); sealed directories take no new files (ADR 0012 would mark
campaign 1's checkers sighted); and the assisted `ops/explore.sh` paths
are named by #121–#123 as acceptance tests. So the tidy-up is a README
that says which rules protect what — plus ~37MB of gitignored local run
outputs (`spike/out`, `spike/runs`, `assisted/runs`) sent to the trash,
every committed report and transcript being on the tracked side already.
The dogfood-era scripts stay in place: BUILDLOG and ADR prose cite them by
path, and a stale citation costs more than the directory listing it
saves.

## 2026-08-15 — The #118 scoring lands, on two axes; the gate was aimed at the wrong failure mode (#118)

The owner scored the cohort — and rejected the one-axis form as too kind
before signing. Question quality: 5/5 meaningful (no vacuous-checker trap
appeared anywhere in the funnel). Drivable-slice discovery value, the
harsher axis the product decision actually needs: **1.5 of 5** — calcurse
found (verified), buku *suspended* rather than pending (the strict run's
fchown refusal means the shim's record may be incomplete in exactly the
way that could fabricate the torn-db world — after fchown support the
question gets re-posed, the unverified FAIL is not "a finding awaiting
confirmation"), stow high-but-blocked, devtodo real-but-light (a target-
selection critique, not a question critique), and pass low — its
meaningful contract's engine-drivable slice is the near-trivially-atomic
rename, which the first self-assessment glossed.

The inversion is the finding about the experiment itself: the metadata
gate was built against an agent posing vacuous questions, and that failure
mode never appeared; the binding constraint was the judge's reach. Scoring
recorded in each RUNLOG and RESULTS; next is the engine-gap issues and
then #118's product decision on 1.5/5-today plus minutes-not-hours.

## 2026-08-14 — The assisted-discovery cohort: five targets, five verdicts, the human half still owed (#118)

The #118 experiment's measured half ran end to end (the human
meaningful-question scoring — part of the success signal by the protocol's
own definition — is still owed to yotta, so the signal is NOT claimed
cleared): five fresh apt-installable targets
(buku, pass, calcurse, stow, devtodo — todo-txt verified installable and
excluded because the scout already knows the todo.txt format's crash shapes
from campaign 1), one measured window each, the SCOUT.md loop as the only
instructions. Full record: `spike/assisted/RESULTS.md`.

The headline: **calcurse gave a VERIFIED, replay-confirmed counterexample
109 seconds after first contact** — `-P --purge` ("Read items and write
them back", the help text naming its own window) truncates `apts` in place,
and the crash between open and write destroys the bystander event the purge
never named. The topydo class, strict oracle agreeing 10/10. buku added an
unverified-oracle FAIL (mid-write crash leaves the db unreadable to buku
itself), replay-confirmed but resting on --allow-unverified.

The equally important half: three of five funnels stopped at the ENGINE,
not at the scout. fchown (buku/sqlite), symlinkat (stow/perl), fchmodat
(devtodo) — three measured absences from the trace contract, no common
family claimed (the first draft's "*at family" was technically false and
R1 said so); and pass's measured refusal is exec image replacement —
that shell-script CLIs hit it as a class is inference, labeled as such. Every one of those questions was
posed, with why/what-property/where-from metadata, in under two minutes —
the judge just could not execute them. Against #118's success signal: T0→define landed in 1m25s–5m02s on all
five. The blind-arc comparison sits in RESULTS as context, not a ratio —
the scopes differ in almost every dimension (this branch's own
apparatus-to-results arc was ~25 minutes for five targets; campaign 3's
sealed arc ~1.5h for one). What remains standing after the scout is engine
coverage — issueable, buildable work rather than a skill wall — plus the
human meaningfulness verdict.

Also on the record: DeepWiki was wrong once about the pinned build (buku's
env var — re-measured, corrected); the proposal-artifact-first rule was
broken on THREE of five targets (calcurse, stow, devtodo — the first
summary admitted only calcurse; R1 caught the other two by file birth
times); a grep pipe ate one exit code before the raw-rc habit caught it;
and SCOUT.md gained a measured-lessons section.

R1 of this branch: sixteen findings, all adopted. The load-bearing ones
beyond the above: the committed saved cases embedded gitignored paths and
could not replay from a fresh checkout — every target was RE-RUN from the
committed ops dirs (identical verdicts), committed launcher scripts now
carry the exact environment (the buku/pass defines were irreproducible
without it), and the buku claim chain gained its committed artifacts
(strict report, replay transcript, the target's own error line). The
calcurse "verified" is scoped: the oracle's account covers the declared
data subtree, with the config dir deliberately ambient. The devtodo
checker counted lines, not occurrences; stow's dangling-link scan piped
find into head (fail-open); both hardened, both still unexercised by any
exploration. The Dockerfile's "pinned" claim is corrected to pinned-by-
build with the actually-run versions recorded.

## 2026-08-14 — Campaign 3 explored: khal, three ops, zero violations (#83)

Exploration from Seal B `9028b04b` completed: import 10 crash points +
baseline, update 21 + baseline, new 10 + baseline — **every world PASS,
violations 0** across 41 crash worlds (10+21+10) and 3 baselines. The full verifier
over Seal A, Seal B, the run manifest and the sealed sweep reports says ALL
SEAL CHECKS PASSED (R1 audited) — transcript committed as
`spike/blind-hunt3/analysis/verify-seals.txt`. The engine's falsification
gate fired in all three runs (corrupted state → the checker's I-C leg
failed), closing post-seal the red side the declaration deferred.

The surprise is what did NOT happen: both pre-registered refusal
expectations (update's random-suffixed leftovers, new's random
UID-as-filename) did not fire — the recordings were accepted and explored
in full, wider coverage than the declaration promised itself. The findings
record the acceptance and deliberately not a mechanism: the mechanism was
not measured, and asserting one would be the claim-exceeds-measurement
shape this campaign kept meeting. Update's oracle numbers (170
state-directory syscall lines vs import's 81) are quoted as consistent
with the normal-run temp-file observation, nothing stronger.

A null result, recorded at counterexample precision
(`spike/blind-hunt3/analysis/findings.md`). Campaign accounting: khal
consumed; hledger is the only name left in the order and is unselectable
while its sweep refusal stands (understanding it means unsealing the
refusal reason — deliberately not done). PRD criterion 1: **two
designated-path campaigns have now returned null**; the remaining path —
more campaigns, a different target class, or §18's kill analysis — is
recorded in PRD as an open decision.

## 2026-08-14 — The khal declaration: one live search, two pre-registered refusals (#83)

Campaign 3's declaration phase, from permitted sources only: the full help
set, the version-pinned usage page (the image ships no khal man page —
probed, 0 hits under the man trees, recorded in sources-provenance), and
one normal run per candidate form. Three operations declared, all
reaching the vdir through documented non-interactive argv: **import of a
fixed-UID .ics** — the live search, byte-deterministic in observation, the
event file named `<UID>.ics`; **import-update of the same UID** — declared
with a pre-registered refusal expectation, because the NORMAL update was
measured leaving random-suffixed leftover files in the vdir (names differ
across runs: baseline-irreproducible, the khard/watson shape — and the
observation is quoted in the declaration so nobody later mistakes it for a
crash finding); **new** — pre-registered refusal, random UID-as-filename
plus DTSTAMP=now, measured. `edit` is excluded on the documentation's own
word ("an interactive command"), `configure` and the TUI on observed
prompts, the ask-first and stdin import forms on channel. The recovery-path
rule discharges vacuously over the widest readable base (help set + usage
page: zero recovery-vocabulary hits). The todoman storage-class disclosure
duty is discharged in the declaration itself.

Two khal-specific checker decisions, both measured before being relied on:
khal's search exits 0 even on no match, so I-Q anchors the exact observed
output line (`grep -Fx`) instead of the exit code — and the red suite's
impostor probe measured khal's search as substring-matching, exactly the
tolerance the exact-line anchor exists to reject; and khal's `list` CREATES
a missing configured vdir (measured, filesystem-verified; no other query
was measured doing this), so the checker only ever
queries a vdir its file legs proved populated, with a fresh scratch HOME
per query so the ambient cache is rebuilt cold every time. I-W (queries
write nothing into an existing vdir) is promoted to a declared invariant —
a crash-world query that "cleans" what it reads would violate it. Red: 15
cases, message-pinned, green first try, real khal touching only
khal-written/empty/absent stores, misbehavior through the CHECK_KHAL stub
seam, plus the golden drift-gate. Green: exec-bit spawns throughout (ADR
0016 requirement 3 — the exec bits were set before anything ran), verbatim
toml operations matching expected_status, effects asserted, parse probes
stopping at state resolution with probed paths untouched. Engine and shim
SHA-256 equal the sweep manifest's: R3 pre-verified.

R1 of this declaration: nine findings, all adopted. The claim-exceeds-
measurement class again (the sixth and seventh instances today): the `new`
paragraph asserted byte-difference, UID-as-filename and DTSTAMP=now when §3
had shown two filenames and one file — §3 now prints both files, cmp's
their bytes with names aside, checks UID==stem for both, and brackets the
run with a reference clock, so the claims stand as measurements; the
create-missing-vdir observation is now filesystem-verified and scoped to
`list`; "ships no man pages" became a recorded probe; the transcript line
count is corrected (588). The apparatus-accounting error — the ledger said
the red suite runs real khal "only as search" while the drift-gate runs
real import three times — is corrected in an appended ledger entry. The
red suite gained the branches R1 found unexercised (update/new dispatch,
update's I-T, the missing-sealed-conf environment branch, a parameterized
scribble target): 19 cases, still all message-pinned and green. The green
run now GATES its stages (a failed prerequisite aborts that op's remaining
stages) and its parse-probe claim matches its predicate ($HOME/.cache is
asserted, not just named). The unexercised-variant column is explicitly
inventory disclosure with per-variant reasons — --random-uid is undriven
for the same determinism reason `new` carries a refusal, not silently.

## 2026-08-14 — Campaign 3 swept: khal accepted, hledger refused again (#83)

One sweep, through the driver, from Seal A `2239fba`, displayed per the
harness contract as exit codes only: **khal 0 / hledger 2** — the same
public values as both prior sweeps, hledger's refusal reason still sealed
and unread. Full reports sealed locally; their hashes travel in the
committed manifest, whose engine and shim SHA-256 are byte-equal to
campaign 2's sweep (same pinned image, same binaries). The sealed selector
over this manifest picks **khal**, which triggers the pre-registered
disclosure duty: khal shares the vdir/iCalendar storage class with todoman,
which this project has explored — the campaign report must say so. Process
note, disclosed in the PR too: the sweep-record commit was first created on
the local main by mistake, caught before any push, and moved to its branch;
origin/main was never touched.

## 2026-08-14 — Campaign 3 opens: khal then hledger, the lessons as requirements (#83)

The apparatus for the third campaign (ADR 0016): `spike/blind-hunt3/` is
campaign 2's sealed tooling copied with paths adapted, plus the content that
changes per campaign — the order is khal → hledger (khard burned, abook
consumed), the khal random-`.ics` refusal risk and the todoman storage-class
disclosure duty carry restated, and campaign 2's six paid-for lessons ride as
declaration requirements rather than advice (file-first checker, no
out-of-contract store ever shown to the target, 755 + engine-path green,
audit-order commits, refusal as an `expected_status` operation, fail-closed
runner with engine identity). The adaptation was swept for leftover
`blind2`/`blind-hunt2` strings — zero hits **in the operational apparatus**
(tools, configs, invocations; the ledger's own narrative names campaign 2
legitimately, so a whole-tree grep does hit and the claim is scoped to what
the sweep actually covered) — and `check-config-paths.sh` is green, because
a config still naming another campaign's state root is exactly the class
that voided campaign 2's first seal.

The rehearsal caught the first real defect before the seal, as designed —
and it was in the rehearsal itself: two walker drills fabricate a "new
campaign" to test the checker walk, and they had fabricated it under the
name `blind-hunt3`. With the live campaign now bearing that name, walker3
copied its planted defect onto the real campaign copy (which HAS an
executable checker) and walker4's "pre-sweep" dir already had invocations —
both drills went green-for-the-wrong-reason and the suite failed 2/42. The
fabricated name is now `blind-hunt9`, and "never live" is a run-time guard
rather than a hope: the rehearsal refuses to start if the fabricated name
exists in the real repo or equals CAMP (R1 of this seal pointed out that a
bare rename repeats the same collision one campaign later). A harness note
on the way: the first rehearsal run was piped through `tail -15`, which both
truncated the failures out of view and replaced the suite's exit 1 with the
pipe's exit 0 — the raw-rc re-run is what surfaced the red. 42/42 green
before the Seal A PR opened.

R1 of this seal: five findings, all adopted. The P1 was in the void-class
gate itself — `check-config-paths.sh` resolved config references by
BASENAME, so a stale `/work/spike/blind-hunt2/configs/khal.conf` in a row
would have been checked against campaign 3's file and passed while the sweep
read campaign 2's config: the exact contradiction the gate exists to refuse,
reachable through the gate. The discovery rule now requires the reference to
name THIS campaign's mounted configs dir and the file to exist — refuse
loudly, never remap — and the new predicate was falsified both ways before
this entry was written (stale cross-campaign reference → refused with the
pinned message; missing config → refused; the real rows → green). The P2s:
the mechanical `s/campaign 2/campaign 3/` comment adaptation had rewritten
history (this campaign's tool copies claimed campaign 3 "already voided a
seal" and re-attributed campaign-2 R1/R2 findings — eleven comment sites
restored to honest attribution, "carried" where inherited); the fabricated
rehearsal campaign gained the run-time guard above; the zero-hit scan claim
is scoped; and the verifier's header summary contradicted its own B1 leg
(invocations are sealed at A, only the manifest first appears at B — the
summary now says what the code checks).

## 2026-08-14 — Campaign 2 explored: abook, three ops, zero violations (#83)

The exploration from the re-sealed Seal B `eb51c483` completed: import 2
crash points + baseline, export 2 + baseline, refused 1 + baseline —
**every world PASS, violations 0**. The refusal path ran as a declared
`expected_status = "1"` operation and never damaged the store it refused to
replace. The full verifier over Seal A, Seal B, the run manifest and the
sealed sweep reports says ALL SEAL CHECKS PASSED (R1 audited) — the
invocation transcript is committed as
`spike/blind-hunt2/analysis/verify-seals.txt`, so the
claim is checkable from the repo, not prose — declaration before
exploration, clean tree at the seal, sweep and exploration on
byte-identical engine and shim. The engine's falsification gate fired in
all three runs (corrupted state → the checker's I-C leg failed), closing
post-seal the red side the declaration deliberately deferred.

A null result, recorded at counterexample precision
(`spike/blind-hunt2/analysis/findings.md`): what PASS bounds (the declared
invariants, single process, the engine's crash model — its own not-tested
list rides in every report) and what it does not (abook's crash safety in
general; the TUI and stdin surfaces are undriven). Campaign accounting:
khard burned, abook consumed by exploration, khal the only unconsumed
candidate, hledger's sweep refusal still sealed unread. PRD criterion 1
stays open; a third campaign is a resourcing decision.

## 2026-08-14 — Seal B's first exploration attempt: Permission denied before anything ran (#83)

Exploration from Seal B `84d0f2e1` returned SETUP ERROR for all three abook
ops. Root cause: the engine execs `./setup.sh` and `./check.sh` directly —
no shell — and both were committed mode 100644 (the Write path that created
them does not set exec bits; campaign 1's scripts were 100755). Permission
denied, exit 126, before a single instruction of setup ran. The green run
had proven setup through `sh ./setup.sh` — a shell spawn the engine never
performs. The measured path did not reach what the seal shipped: the same
lesson as the hook-run-by-hand class, now in the one place the campaign
cannot simply patch, because the declaration is sealed.

What makes this recoverable with blindness intact: the run observed nothing.
All three `.out` files hold exactly the engine's SETUP ERROR line; all three
reports parse with `verdict: SETUP_ERROR, crash_points: 0`; abook never
executed. The fix commit changes the two files' git modes and nothing else —
0 insertions, 0 deletions, every blob SHA unchanged, which the PR diff
proves mechanically. The fix PR's merge is the Seal B the exploration
actually runs from. Rule extracted (CLAUDE.md): declaration scripts the
engine execs are committed 755, and a green run must spawn them the way the
engine does — through the exec bit, not through `sh`.

## 2026-08-14 — The abook declaration: refusal as an operation, and a red suite the burn can no longer reach (#83)

Campaign 2's second declaration, written after the khard burn and carrying its
structural fixes as design, not as review patches. Three things decided here:

**The commit order is the audit trail.** Sources (help/formats/man pages from
the pinned deb, normal runs) were committed before a word of declaration
existed; the declaration before the apparatus. The khard round's single batch
commit made "observed then declared" unprovable; this branch makes the
ordering readable from history — local reordering remains possible (ADR
0012's honesty bounds), but the default story is now in the commits.

**Refusal is an operation.** abook's only non-interactive writer is
`--convert`; converting onto an existing outfile refuses ("cannot write
file", exit 1, store byte-identical — normal-runs §4). That observation
became a declared operation with `expected_status = "1"` (the v8 field
shipped for exactly this): an interrupted refusal is where a "harmless" path
could still damage the store it refused to replace. The other two ops are
import (fresh outfile; bystander store conserved byte-for-byte) and export
(the cross-file window: a reader must not scribble what it reads). No
refusal pre-registered — both writers observed byte-deterministic, twice.

**The red suite cannot re-create the burn.** The checker runs file legs
first and the target last, so a red fixture that fails a file leg provably
never reaches an abook invocation (each failure message names its leg — the
pin doubles as the no-execution proof). Real abook touches only
abook-written, empty, or absent NATIVE stores (queries over goldens — the
impostor anchoring probe: `Grace Hopperson`'s real match line is rejected
because the anchor demands the full name bounded by both tabs — and the
provenance case's converts, whose vCard inputs are the committed
hand-authored well-formed files, the documented-normal input class). Every
branch that needs an ill-behaved binary — wrong exit codes, duplicate match
lines, byte-writing queries, hangs, outfile creation — runs through a stub
via the checker's documented CHECK_ABOOK seam: those branches are exercised
and the target never runs. 17 red cases, message-pinned; the khard R1's
other gaps (green-run without setup/parse/binary evidence, missing engine
version in the run manifest) are answered in green-run.txt and run.sh.
Engine and shim SHA-256 already equal the committed sweep manifest's values,
so the R3 leg's comparison is pre-verified at declaration time.

**R1 of this declaration: ten findings, all adopted.** The two fixed review
axes cut into the new work exactly as they did last round. The ones that
mattered: normal-runs §4 had *printed* the store before and after the
refusal but never ran `cmp` — "store byte-identical" exceeded its
measurement (the same claim-vs-measurement shape, caught a third time
today; §4 now measures, and the probe was re-run). The "every store the
target meets is abook-written" rule as first written was false — green
feeds hand-authored vCard *inputs* to `--convert`; the rule now
distinguishes native stores from documented-normal input files. The
committed goldens had no drift gate (make-goldens silently re-baselines; a
red provenance case now regenerates into scratch and byte-compares on every
run). The green harness could pass without its operations doing anything
(setup rc ungated, effects unasserted, an empty extracted command exits 0
via `sh -c ""`) — setup is gated, extraction asserted non-empty, and each
op's documented effect is asserted. run.sh swallowed exploration failures —
it now requires each op's report to exist and parse, records per-op
exit/report state in the manifest, and exits nonzero on a missing report.
Sources provenance (deb version assert + sha256, bare-`abook` resolution)
now lands in a committed transcript instead of a terminal. `--add-email-
quiet` is kept excluded but for the honest reason — a documented stateful
form whose only input channel (stdin) the engine never supplies — and the
inventory says so instead of calling it a prompt. The mutt/muttq
outformat-name discrepancy between abook(1) and --formats is recorded.

R2 confirmed eight of ten and returned two as incomplete: the `interactive`
verdict still contradicted its own evidence text (resolved by stating the
label's sense once — ADR 0012 seals the four words without defining them —
and rewording the row under it), and the parse-probe section heading still
said "no side effects" while the probe inspects three paths (heading now
says "probed paths untouched"; transcript regenerated). R2 also verified
the ledger's append-only property byte-for-byte against the parent commit
and ran `sh -n` over the eight touched scripts.

## 2026-08-14 — khard is burned: the red suite let the checker query a malformed store (#83)

The declaration below shipped with a red suite whose header argued its own
safety: "khard itself only ever runs `list` over these stores." R1 read the
transcripts instead of the header: `checker-red.txt` line 13 ends with khard's
own error message for an unparsable .vcf ("Use --debug for more information or
--skip-unparsable to proceed"). The checker's first step is the `khard list`
liveness query, so the I-F red fixtures — vCards deliberately written
mis-shaped — put khard's failure behavior on record before Seal B. ADR 0012
has no cure for that: blind is once per target. The safety claim named what
the script runs, not what the run touches: the recurring shape where a
verification is trusted without asking what it does not look at.

Corrected after this burn PR's own R1 (the first version of this entry said
campaign 1 was safe "by structure"): campaign 1 ran the same design risk.
Its checker was also query-first — `check.sh` runs the I-Q `ls` before the
I-F file checks — and its red suite also fabricated stores violating its own
I-F predicate (`not-a-completed-task`, `x other-task` in done.txt). The
committed transcript shows the I-F messages firing, which means the I-Q leg
had already passed: topydo's query returned documented-normal output over
those out-of-contract stores, and no failure behavior was committed. Campaign
1 escaped by outcome, not by structure; campaign 2 collected the consequence
of the same red-suite design. (The uncorrected version of this entry was
itself the recurring shape — it asserted a mechanism, "only well-formed
stores, query-first was new", that no committed artifact supports.)

Burn handling per ADR 0012, before Seal B, so the campaign survives:
`burned.txt` now carries khard, the ledger records what leaked, the khard
declaration leaves the tree (history keeps it at a459995), and selection
re-runs with the burned name skipped — abook by the sealed order, if the
selector agrees. The structural fix rides the next declaration, not a review
round: file inspection first, the target query last, and red fixtures that
are well-formed only (an empty store — documented-normal — is the one
permitted refusal shape). The next declaration also inherits R1's independent
P0/P1s: pin every red case to the message of the guard that fired, exercise
the counting branches, complete the unexercised-form inventory, and keep
every claim inside what its transcript actually shows.

## 2026-08-14 — The khard declaration, written blind, with two refusals pre-registered (#83)

Campaign 2's declaration phase, from permitted sources only: the sixteen-command
help, three man pages, two docs pages, RFC 6350 through the carve-out, and one
normal run per declared form. Four operations declared — `new`, `remove
--force`, `move`, `copy` — with `move` as the cross-file window (one contact,
two addressbooks: after a crash it must be in exactly one place). Three
subcommands excluded as interactive on hard evidence: `edit` waits for
confirmation even with `-i` and no stdin; `add-email`'s prompt loops unbounded
on EOF (~200MB of `Select?` in five seconds); `merge` is documented as needing
an interactive merge editor and errors without one.

The two honesty-first moves:

- **The recovery-path rule discharges vacuously, and the enumeration proves
  it**: no recovery, undo, restore or repair command form exists anywhere in
  the sealed documentation transcripts. The consequence is stated in the
  declaration instead of implied — a crash-damaged khard store has no
  documented in-tool recovery at all, which cuts both ways and the report will
  have to weigh it.
- **Two of the four declared operations carry pre-registered refusal
  expectations.** Measured in normal runs: `new` mints a random UID (filename
  and content) plus a second-precision REV, `copy` re-mints both, and
  khard.conf(5) offers no setting to fix either. The byte-reproducible
  baseline should refuse them — the watson shape — and that refusal is #84
  data the campaign wants, not a failure. `remove` and `move` measured
  deterministic (identical stores end byte-identical; move preserves filename
  and bytes), so they are the live searches.

Verification stayed inside the blind rules: the checker's red side is twelve
committed cases over hand-fabricated vCard files (khard only ever ran `list`,
and an empty book exiting 1 is documented-normal — it is also why every
declared state keeps a conserved bystander); the green side runs
setup → verbatim toml operation → checker for all four; the tomls parse on
the binary built from this very tree, inside the pinned container — not on a
host binary, which is the exact mistake campaign 1's declaration phase had to
correct after review. No preflight touched any declared define.

## 2026-08-14 — Campaign 2 between the seals: khard, by the sealed predicate (#83)

The sweep ran once against the re-sealed apparatus (Seal A = the #107 merge,
`8878df82`), through the phase driver, and displayed what the harness contract
allows: **khard 0 / abook 0 / khal 0 / hledger 2** — the refusal reason sealed
and unread, as it has been since campaign 1. `select.sh` over the committed
manifest recomputed **khard**: first in the sealed order, accepted, in-image.
With the config/invocation contradiction fixed, khard's verdict returned to
campaign 1's public value — consistent with the voided sweep's refusal having
been our apparatus, and nothing stronger than consistency is claimed.

The attempt also bought one more driver fix, live: with the docker daemon
stopped, `image_id`'s die was swallowed by the command substitution and an
**empty image name reached `docker run`**. Both call sites now stop the driver
(`|| exit 2`), red-measured against an unreachable DOCKER_HOST — the driver
dies naming the image, runs no container, creates no outdir. The rehearsal
cannot unplug docker, so this red lives in the PR record, not a drill; said
here rather than implied. (And this entry itself exists because the buildlog
CI check went red on the sweep PR — the same check that PR #103 was merged
over; this time it was read before the merge.)

Next, deliberately in its own session: the khard declaration — inventory,
invariants with provenance, the recovery-path rule's full form enumeration,
and Seal B. The pre-registered risk stands: per-entry random filenames may
refuse the byte-reproducible baseline, and a full-refusal exploration is a
recorded result, not a failure of the campaign.

## 2026-08-14 — #28: the version-mismatch test stops sharing its path, measured at 82% (#28)

The contract-version unit test wrote to a fixed `/tmp/sideeye-version-test/` and
`zig build test` runs the engine's tests in more than one concurrent binary. It
cost three CI round trips today alone — different assert lines each time, which
is what losing a race at different points looks like. The fix is the issue's own
prescription: a pid-suffixed directory (`posix.getpid()`, one new extern).

The measurement is the part worth recording. The first reproduction harness — an
external loop deleting the shared path — never landed in the microsecond windows:
its positive control stayed green at 0/15, which means it measured nothing, and
a "0 failures" from the fixed binary under that harness would have been the
day's fourth verified-nothing claim. The real adversary is another copy of the
same test binary, in phase over the same sequence (its `rmdir` is also the only
thing that can make `open(O_CREAT)` fail, explaining the `fd2 >= 0` variant).
Two old binaries racing: **66 of 80 runs failed**. Two fixed binaries racing:
0 of 80. The flake was never rare — CI was just rolling one die per push.
## 2026-08-14 — The campaign becomes a program: rehearsal, driver, R3, and a ledger pen (#83)

The re-verification question was blunt: what would let a blind hunt run without
the mistakes this session kept making? The answer that survived scrutiny is not
another checking layer — it is moving every apparatus error to before the seal,
where errors cost nothing, and removing the hand-typed procedure where the
sequencing errors lived. Four pieces, shipped together on the re-seal branch:

- **`spike/rehearse-campaign.sh`** — the whole pipeline against synthetic
  targets in a scratch git repository that mimics the real layout, so the REAL
  sealed tooling runs byte-for-byte unmodified. Defects planted one at a time
  (a sealed path edited between seals, a rewritten ledger, a tampered manifest
  hash, a wrong declaration, a wrong-head run manifest, a wrong-engine run
  manifest, a voided anchor, a cross-row config, a dropped checker, a vandalized
  ledger under the append tool, three driver refusals), each required to turn
  its guard red — with the guard identified by its MESSAGE, not just the exit
  code — then the real pipeline through the driver: container sweep, selection,
  a Seal B carrying a real runner, a real exploration, and the full battery's
  ALL SEAL CHECKS PASSED (R1 audited) over artifacts the shipped code produced.
  Forty-one drills. The first two versions each failed honestly: run one caught
  real behavior (this host's docker answers `image inspect <name>` flakily —
  both resolvers now accepted — and bookworm's /bin/cp is *correctly* refused
  by preflight because it copies via copy_file_range; the toy now writes
  through dd); the delta review then caught the rehearsal itself lying twice —
  two driver drills passing on the dirty-tree guard while claiming to test two
  other guards, and an "entire pipeline" whose exploration was a fabricated
  manifest. Both are the same shape as everything else today, inside the tool
  built to stop it. The current suite pins every red to its guard's message
  and runs the exploration for real.
- **`spike/campaign-driver.sh`** — every phase behind preconditions that refuse:
  dirty tree, uncommitted inputs, existing output directories, a manifest that
  already exists, a HEAD that is not the seal being explored. Unsealed by
  design: it carries no verdict logic, only the sequencing that was previously
  typed by hand — which is exactly where the fused-chain failures lived. It
  never merges and never commits.
- **verify-seals R3** (sealed, amended pre-merge on this branch): the run
  manifest's engine/shim SHA-256 must equal the committed sweep manifest's.
  The machine half of "measure the thing you ship" — the class that started
  today's chain.
- **`spike/ledger-append.sh`** — appends and proves the prefix against HEAD,
  restoring on refusal. The append-only discipline has now been broken twice by
  well-meant edits; the pen replaces the discipline.

CLAUDE.md gained the operating rules, including the two review axes external
review has repeatedly out-detected self-checks on (claims vs. what the
measurement looked at; guards falsified against their own predicate). What
stays honest: the rehearsal covers the apparatus, not the declaration's
completeness, and prose outside Verified sections still depends on review.

## 2026-08-14 — The same mistake three times in one session, and where the stop now lives (#83)

Three failures today share one shape, and naming it matters more than any of them
individually:

1. "All thirteen tomls parse" — measured with the host binary, not the revision
   being sealed.
2. "The configs carry no campaign-1 dependency" — measured by resolving
   references and checking files exist, never by opening the files, where
   `/tmp/blind` sat in two of them the whole time.
3. "The new guard is falsified" — measured against the defect that produced it,
   never against its own predicate. External review then found seven holes in it.

The common shape: **when I say "verified", I do not check what the verification
did not look at.** Each time the net was finer than the thing I claimed to have
caught, and nothing came up, so I reported safety. A rule against this already
existed ("measure before trusting a check"), and existing prose did not stop the
third repeat — which is the measurement that decides where the fix belongs.

So the stop moved out of prose in two places:

- **CI**: `spike/check-sealed-campaigns.sh` walks *every* campaign directory
  present, requires each one that seals invocations to carry an executable
  consistency checker, runs it, and **fails when no campaign is found at all**
  (a path typo would otherwise pass over an empty set). Campaign 1 is exempt by
  literal name — its seals are closed and adding files there would mark its
  checkers sighted — and the exemption cannot be inherited, which is one of the
  cases the suite proves. Falsified across seven cases, and deliberately not
  only against the accident that motivated it: a campaign that drops the
  checker, one whose checker is not executable, an empty tree, a *new* campaign
  trying to inherit the exemption, and a pre-sweep campaign that must be skipped
  rather than failed.
- **The PR template** (`git-delivery` skill): the Verified section now asks for
  the claim, the command that measured it, and what that command did not look
  at. All three failures above were written into a Verified section; that is
  where the discrepancy would have had to be spelled out.

What this does not fix, stated because the honest scope is the point: CI covers
the config/invocation class only. Classes 1 and 3 are caught by the template, or
not at all — the template is a prompt to notice, not a machine check, and its
effect is unmeasured until the next time I claim something.

## 2026-08-14 — Campaign 2's first seal was void within the hour, by its own sweep (#83)

The between-seals sweep ran once against the sealed rows and displayed its four
exit codes: khard 2, abook 0, khal 0, hledger 2. khard's flip against campaign 1's
public verdict (0 there) sent me to our own committed artifacts — the sealed
reports stayed unread — and the contradiction was inside the seal:
`configs/khard.conf` and `configs/khal.conf` still hardcoded campaign 1's
`/tmp/blind/...` state roots while the sealed invocations watch `/tmp/blind2/...`.
That does not prove the mismatch produced the refusal — the reports stayed unread
and no controlled re-run was made — but it does mean the verdict is
uninterpretable, which is the only property the decision needed.

Voided, not proceeded with. The machine had selected abook, and following it
would have been indefensible: the khard refusal risk was pre-registered, so an
apparatus bug that knocks khard out is — to any skeptical reader —
indistinguishable from steering. And the seal design itself forbids the quiet
fix: configs ride the A2 no-touch set. So the exit is the loud one — void before
any declaration exists (blindness cost: four displayable exit codes), fix the
two paths, re-seal, and give khard its fair shot.

The part worth keeping: **my own R1 fix created this trap and certified it
safe.** Sealing the invocations at Seal A was finding 5's remedy; I "verified"
the rows resolvable and wrote that the freeze "does not risk a spelling-error
dead end"; R2 confirmed the configs "contain no campaign-1 workspace
dependency". `/tmp/blind` sat in two of them the whole time. The verification
checked command resolution and file existence — not the paths inside the
configs, the one place a path could still disagree. Falsified within the hour
by the first real run. The re-seal adds the mechanical consistency check
(config `/tmp` paths ⊆ invocation state roots, green on the fixed tree), and
the ADR now says what a frozen apparatus actually guarantees: not that it
cannot dead-end, but that its dead end is public and the exit is a recorded
re-seal rather than a quiet tune.

Two more things the void surfaced, both about checks that could not see what they
claimed to cover. `check-config-paths.sh` is the new Seal A artifact — every
absolute `/tmp` path in every sealed config must sit under a state root named in
the sealed invocations — and it was falsified before being trusted: red on the
voiding defect itself, red on a sibling-but-wrong root, and **exit 2 rather than
success when it cannot look** (no roots, or no configs), with a green control on
the fixed tree. And `.gitignore` was campaign-1-specific, so campaign 2's sealed
sweep reports and hledger's import sidecar both walked into the staging area; the
patterns are now `spike/blind-hunt*/`, verified with `git check-ignore` to cover
campaigns 1, 2 and a hypothetical 3 while leaving sealed configs and manifests
tracked. A guard written against one instance of a hazard does not cover the
hazard.

One more, from asking what actually invalidates a voided seal. Measured before
writing anything: passing the voided anchor to `verify-seals.sh` already failed,
because the re-seal edits sealed paths and A2 walks the whole range — the lock
was there, it just said the wrong thing. So the re-seal adds `voided-seals.txt`
plus a verifier preamble that refuses a listed anchor by name, and both
directions were falsified: voided anchor exits 2 with the reason, a live anchor
still runs the full battery (a new guard that swallowed the old checks would be
the exact ADR-0012-era failure this repo has already paid for once).

R1 on the re-seal then found eight more, seven of them in the guard I had just
written and falsified — a guard tested against the defect it was born from, and
not against its own predicate. It compared each config path against *any*
invocation root (so a config could agree with a different row's state and pass);
its containment accepted any *ancestor* of a state root and never considered
`..`; and its cannot-look contract leaked four ways (extra args ignored,
unreadable files and malformed rows exiting 1 through Python, the bare path
`/tmp` unmatched by the regex). Rewritten per-row with strict normalized
containment, and re-falsified across twelve cases — one red per hole, a green for
a deeper path inside the row's own root, four cannot-look refusals.

Two findings were about the void rather than the guard, and both mattered more.
The sweep harness accepted an existing output directory and truncated it, so
re-sweeping would have destroyed the voided run's evidence — the very artifacts
the ledger promises are retained. It now refuses, as it already refused existing
state roots, and the voided run was moved aside and re-verified against the
superseded manifest (four hashes, still matching, still unread). And my account
overclaimed: with the reports unread and no controlled re-run, the path mismatch
does not prove it produced the refusal. What it proves is that the apparatus
contradicted itself, so the verdict is uninterpretable — which is all the void
decision ever needed, and the weaker claim is the one now in the ADR, the ledger
and this entry.

The last one is small and my favourite. Fixing the ledger's stale "none yet"
placeholder into a self-aware annotation *broke the append-only prefix* — the
exact property the annotation was bragging about. The pre-commit self-check
caught it, the sealed bytes went back verbatim, and the explanation moved into an
appended entry where it belongs. A rule you are describing is still a rule you
can break in the sentence describing it.

## 2026-08-14 — Campaign 2's Seal A: an inherited selection, and the recovery-path rule (#83)

The strict ruling made the second campaign the designated criterion-1 path, so it
starts now. ADR 0015 records the two ways it differs from a naive re-run of
ADR 0012, both forced by honesty rather than convenience:

- **The selection seal is inherited, not re-performed.** The four remaining
  candidates have been installed, normally run, and swept once — publicly, under
  campaign 1's rules. Claiming a fresh "nothing has run yet" seal would be theater.
  Instead the candidate list, order, and predicate come byte-inherited from
  campaign 1's Seal A (merged before anything ran), minus the consumed target; the
  only knowledge gained since is ledger-recorded permitted-source contact and the
  public sweep exit codes. The khard random-filename observation is deliberately
  NOT allowed to touch the predicate — dodging a known refusal shape with observed
  behavior is the leak the seals exist to close. The risk is pre-registered
  instead: a full-refusal exploration is a recorded result, and campaign 3
  inherits the same way.
- **The recovery-path rule.** Campaign 1's sharpest behavior lived in the path its
  declaration scoped out. Campaign 2's declaration MUST declare, where the docs
  name a recovery/undo/repair command, that running it once after a crash
  preserves the tasks the crash left intact — declarable from docs alone, so the
  misfire class moves inside the blind checker's reach.

Mechanics: `spike/blind-hunt2/` is self-contained (fresh candidates/priority/
ledger/configs, tooling copied and re-sealed — each campaign freezes its own
verdict logic; campaign 1's directory stays untouched so its checkers stay
unsighted). The adapted tooling was falsified before being trusted: select.sh
green (picks khard from a 4-candidate manifest) and red twice (all-refused exits
3, missing-candidate exits 2); verify-seals2 pointed at campaign 1's seals fails
on every blind-hunt2 path — the proof it audits the new namespace, with the FAIL
lines as the evidence (the pipeline's displayed rc was head's, worthless, the
same trap as ever).

R1 (external, covenant-instructed; no breach) found eight holes — seven P1, one
P2 — and every one was the inherited apparatus trusted a step too far:

- The recovery-path rule allowed choosing the convenient command form; campaign 1
  itself proved two documented forms behave differently. Now: enumerate every
  documented form with citations, freeze exact argv per checker, per-form
  invariants, fixed-vocabulary exclusions, and an honest note that coverage is
  review-enforced, not machine-checked.
- Nothing consumed a selected target after a null/refusal campaign — the
  inherited selector could pick the same name twice. Consumption is now a
  normative rule, distinct from burns.
- ADR 0012 governed the campaign but sat outside the A2 no-touch set; the
  inventory now lists it — and itself (the P2).
- The environment that decides selection was unpinned prose. The sweep manifest
  now records the engine version and binary/shim SHA-256 (stub-tested: valid
  JSON, fields present), the run manifest must mirror them, the ledger records
  the image ID at sweep time, and the ADR states exactly what that does and does
  not prove.
- The inherited invocation rows were prose-bound. They are now sealed at Seal A
  itself (public since campaign 1; resolution-verified in the image with no
  target executed — the freeze cannot dead-end on a typo), and select.sh rejects
  manifest names outside the sealed order (red-tested, exit 2).
- sweep.sh's header still instructed copying the manifest into campaign 1's
  directory — following it would have touched the closed campaign — and claimed
  a freshness ("before any candidate has been installed") that ADR 0015 exists
  to deny. Both rewritten.
- "Knows ... exhaustively" overclaimed a self-reported ledger; now "the
  repository records", with the ADR 0012 bounds restated beside it.

## 2026-08-14 — Ruled: the misfire does not count as "found by Sideeye" (#83)

The open fork in the PRD's criterion-1 status was closed today, on the strict
side. The recovery misfire (novel, upstream as topydo#341) was reached by a
human following the automated FAILs into the recovery path; counting that as
"discovered automatically" would read the same scale two ways — timewarrior's
find was scored *partial* because a human formed the specific hypothesis, and
the arrows being reversed here (tool search first, human hypothesis second)
does not change who formed it. The sealed declaration also pre-committed to
calling recovery measurements analysis; promoting them to findings after the
fact is the goalpost-shaped move this campaign built two seals to prevent.

Consequence: criterion 1 stays open. The designated path is a second blind
campaign under fresh seals, whose declaration includes recovery-path
invariants — declarable from documentation alone, and exactly the coverage
this campaign's declaration listed under "what this does not check". The
remaining candidates (khard, abook, khal, hledger) are still blind-eligible:
permitted-source contact only, hledger's refusal reason still sealed unread,
no bug tracker opened for any of them. Keeping them that way is a standing
discipline until the next campaign picks one up. Timing deliberately not
fixed.

## 2026-08-14 — The misfire went upstream (topydo#341), and a red check got merged over (#83)

Two things to record, one good and one not.

The recovery misfire was filed upstream as `topydo/topydo#341`, with the text
approved verbatim beforehand: observation, a plain-printf reproduction (verified
in the container before the text was shown for approval), conditions, risk, a
confirmation request. No fix proposal, no tooling named, #318 referenced as
related context. The crash-window destruction itself was deliberately not
re-reported — #318 already covers that phenomenon, and a duplicate adds noise,
not information.

The process slip: the ledger entry recording that filing went in as PR #103,
and PR #103's `buildlog` check **failed — correctly** (it changes `spike/`
without touching this file; that is exactly the contract in CLAUDE.md) — yet
the PR got merged anyway. The merge command was chained after the check
*display* in one invocation, and a display exits 0 whether the checks passed
or not. This is the third occurrence of the same fused-chain class (#51: watch
exits 0 before checks register; #61: rollup query and merge in one command;
now #103: an until-loop that waited for "not pending" but gated nothing on
pass/fail). The structural fix this repo's discipline demands: **merge is its
own invocation, issued only after reading the pass/fail column** — never
appended to the command that prints it. This entry is also the BUILDLOG entry
PR #103 should have carried.

## 2026-08-14 — The novelty check: the phenomenon was known, the recovery misfire was not (#83)

The bug-tracker restriction was lifted as its own recorded step (ledger: fourteen
search terms over title+body, comments-inclusive passes for the revert terms, a
positive control proving the instrument can see what it looks for, full bodies
read for the three candidates). The answer split the campaign's result in half:

- `topydo/topydo#318` — open since 2023-10, zero comments — already reports the
  active list being destroyed by an interrupted write (disk full there, SIGKILL
  here; same failure surface). The reporter had not read the code; there is no
  mechanism and no reproducer. So the blind search's headline finding is real but
  **not novel as a phenomenon** — what this campaign adds is the deterministic
  window and a case that replays in a pinned container.
- The recovery misfire — plain `revert` after a crash undoing an *older* command
  and deleting data the crash left intact, on documentation that contradicts
  itself about the matching rule — appears **nowhere in the tracker**. Novel as
  far as the recorded search sees; also the one finding that came from post-seal
  human analysis rather than the blind search.

The uncomfortable consequence, written into the PRD status rather than smoothed
over: **no single finding currently holds "found by Sideeye" and "novel" at
once.** The automated find is known upstream; the novel find is human analysis.
Whether the recovery misfire still counts as "found by Sideeye" (its FAILs are
what pointed the analysis there) is the author's judgement, not this file's.

## 2026-08-14 — The blind hunt ran: twelve of thirteen operations produced a counterexample (#83)

Seal B merged as `5a034aff`, and the exploration ran from that commit in a clean
tree, in the pinned container. `verify-seals a21b0933 5a034aff <run-manifest>
<sealed-reports>` prints **ALL SEAL CHECKS PASSED (R1 audited)** — the first time
the verdict line has come back without PARTIAL, because the run manifest finally
exists to audit. The declaration order is now a checked fact rather than a claim.

**Result: twelve FAIL, one PASS.** The ten single-file operations each violated
the declared conservation invariant in the window between opening the active list
and writing it; `do` and `revert` failed across the file pair (2 of 5 and **5 of
8** worlds). `ls`, declared read-only, recorded zero state-changing operations and
passed — the one declared operation whose expected result was "nothing to explore"
delivered exactly that, which is the honest control this run needed.

**The saved cases replay in a fresh container with nothing else installed** —
exit 1, `the case reproduced`, for every case tried. That is the property the
timewarrior finding never had (`#82`: a recipe bound to a built binary). The
in-image resolution leg of the sealed predicate was a structural proxy for this,
and the proxy held.

Then the part that matters more than the truncation window, and the part that is
**analysis, not automated discovery** — I followed the FAILs into the documented
recovery path, after the seal, and `analysis/findings.md` keeps the two halves
apart on purpose:

- The data is recoverable, but through the *numbered* form: `revert 1` restored
  the intact pre-crash state every time, including worlds where the active list
  had been emptied. My first reading of the measurements was "unrecoverable" —
  the forced form is documented one sentence below the one I had leaned on, and
  measuring it before writing is the only reason this entry does not contain a
  false claim.
- The no-argument form — the one the docs lead with — does something else. For
  `add`, in **3 of its 5 crash worlds**, the crash left the pre-existing task
  intact and plain `revert` then deleted it, exiting 0 with `Reverted to state
  before: add seed-task`: a command the user never pointed at. In 2 worlds it
  refused. The cause is legible from the outside: after the interrupted write
  the file is byte-identical to an *older* snapshot, so the search for "a backup
  corresponding to the current state" matches the older entry and rolls past
  work the crash never touched.
- The target's own two documentation sources disagree about this case — the help
  text promises refusal when the latest backup does not match; the documentation
  tiddler describes searching for any backup that corresponds to the current
  state. The behavior follows the second; under the first it should have refused.
  Whether upstream knows is **not checked** — the reference rules forbade the bug
  tracker, and lifting that is a deliberate step before any report, not a thing
  to do while writing up.

**What the campaign may and may not claim.** Declared-before-known: yes, and
machine-checked. Found by the search: yes for the crash windows. Novel: unknown,
and the file says so. Real bug: yotta's judgement, not asserted here. And ten of
the twelve ran with `backup_count = 0` — our own declared config, safety net off
by our choice — so their weight is bounded by exactly the thing the declaration
said it would not check. `do` and `revert` ran at the default and did not need
that caveat.

## 2026-08-14 — The topydo declaration, written blind (#83, toward Seal B)

The declaration phase ADR 0012 authorizes: everything the exploration will be
judged by — invariants, operation inventory, checkers, setups, tomls, the
runner — written from permitted sources only and frozen in
`spike/blind-hunt/declaration/topydo/`. The consultations are itemized in the
ledger; the raw material (help output, doc tiddlers, the todo.txt spec, one
normal run per subcommand) is committed under `transcripts/` so every
`source:` line points at something a reader can open.

Shape of the declaration (after R1, below): thirteen operation forms across
twelve of the fifteen help-listed subcommands are declared (excluded whole:
`edit` interactive; `listcon`/`listprojects` not-stateful — and every
unexercised form of a declared subcommand is listed, not silently dropped).
Six invariants — query survives (I-Q), conservation across the
file pair (I-C), no duplication for the two cross-file operations (I-D2),
archive holds only `x `-marked lines (I-F), the backup listing answers after a
crash (I-B, revert only), and claimed durability via L1 markers where the
operation prints a past-tense success line (I-M). Severity is pre-registered
(loss over duplication) so a finding cannot be inflated afterwards.

Decisions worth recording, made while still blind:

- **Backups off for ten operations, on for revert.** The docs say the backup
  store is rewritten on every modification, and `revert ls` shows its times at
  second precision — that alone would make the un-killed baseline world
  irreproducible and refuse every run (`baseline_violates_invariant`, the
  watson shape) before topydo's behavior was ever measured. The documented
  `backup_count = 0` switch is the declared config for the ten; revert keeps
  backups because they are its input. The cost — the backup subsystem's crash
  surface rides on revert alone — is stated in the declaration instead of
  being discovered in the report.
- **Conservation greps the files, not the listing.** A normal run showed
  `ls -x` omitting a task that had just acquired a dependency; the todo.txt
  carve-out (the format is normative public documentation) makes the files
  the honest inventory.
- **No preflight on the declared defines.** The temptation was real — eleven
  tomls, why not check they will be accepted? Because acceptance-checking is
  observation, and tuning the declared set against it is the exact leak Seal B
  exists to close. The sweep stays the only sideeye↔topydo contact; a refusal
  at exploration time is #84 data, not a defect. What did get verified without
  touching the target: all eleven tomls parse (host binary, nonexistent shim,
  stops at state resolution), and the green side — setup, the verbatim
  operation string, checker — exits 0 on normal state for all thirteen.
  (An earlier draft of this entry said the checker had never been seen to
  fail; that was superseded the same session: its red side is now proven on
  hand-fabricated, user-authored states — `checker-red-test.sh`, committed
  with its fixtures — while the red side against real *crash* states still
  belongs to sideeye's falsification gate, after the seal.)

R1 (external review, covenant-instructed; it complied — no burn) then bent
the declaration in four places, all recorded in the ledger:

- **The parse validation had measured the wrong binary.** "All tomls parse"
  was run against the host's v0.7.0 sideeye — but this branch based on the
  Seal A merge, which predates `expected_status`. The sealed revision would
  reject every toml. The green run that was supposed to protect the seal was
  itself the measured-a-different-path shape this workspace keeps meeting.
  **Resolved, with the decision on record**: the branch was rebased onto the
  v0.7.0 merge (`a21b093`) — every Seal A artifact is byte-identical between
  the two anchors and the criterion wording did not move (PRD untouched;
  DESIGN's two new lines are the §12 define-key note), so verify-seals runs
  with A=`a21b093` and every leg stays mechanical. The alternative — keeping
  the old base and dropping the key — would have sent the exploration out on
  an engine whose PASS-side soundness bugs v8 had just fixed, and recorded a
  case the current contract refuses (#82's hole, re-dug). Because the engine
  moved, the sweep was re-run once, recorded (ledger): identical invocations
  by hash, identical verdicts, topydo again — and the superseded manifest
  stays committed beside the new one.
- **The backup-refusal certainty was an overclaim.** Normal runs only show
  that `revert ls` prints second-precision times; whether backups-on would
  actually refuse the baseline is deliberately unmeasured. Downgraded to a
  pre-registered risk everywhere it was stated.
- **The inventory was neither complete nor honestly granular** — `ls` was
  excluded as not-stateful while a documented form writes, and `dep rm`/
  `dep clean` were unmentioned. Now: `ls` and `dep rm` are declared (the
  former with its zero-op expectation stated), `dep clean` and every other
  unexercised form is named per subcommand, and the lscon/lsprj tiddlers
  were pulled so the two remaining not-stateful verdicts are doc-backed.
- **The checker was hardened without unsealing anything**: padded list
  numbers accepted (the docs' own example pads), conservation demands a
  whitespace-delimited token (an embedded substring is not survival), and
  I-F now enforces the completion date the spec's rule 2 requires. Red
  cases for each new tooth ran before they were trusted.

## 2026-08-13 — v0.7.0: minor, because the number must predict the case refusals

Version 0.6.0 → 0.7.0, both hand-written strings at once (the unit test holds
the pair). 0.6.1 was proposed and rejected: a patch number reads as a safe
drop-in, and this release changes what saved cases do — every v7 case now
refuses as a contract mismatch and must be re-recorded, and the countable
operation set itself moved (contract v8). A new user-facing define key
(`--expect-status`, case schema v2) rides along; the 0.6.0 precedent already
chose minor for less. README reconciliation (checklist step 3.5): the tar
example moved to v0.7.0 and the Status list gained the release's claim; the
two other v0.6.0 mentions are historical ("entrance paved at", "releases from
v0.6.0 on ship binaries") and stay.

## 2026-08-13 — expected_status: the fifth define key, spent against §12's budget sentence (#3)

The recording run and the baseline world both demanded exit 0, which made every
git-convention target unjudgeable — refused on sight, no opt-out
(`--allow-unverified` weakens completeness, not the success convention). The fix
is one declared value with two spellings (`--expect-status 3` /
`expected_status = "3"`), one shared digit parser so the spellings cannot drift,
and one meaning: *un-killed runs of the operation must exit N.* That sentence is
the answer to #3's own worry ("one flag governing two checks with different
meanings") — the recording run and the baseline are the same command over the
same state, so they were always one check wearing two names.

The wiring is the work, not the comparison: the flag, the toml key, the
`--config` exclusivity list, replay's define-surface rejection list, the saved
case (schema v2 — the declaration is written even at the default, because a case
must replay identically years later without consulting anything outside the
file; v1 cases read as "0 was the contract"), preflight (accepts it, and the
graduation hint carries it — a hint without it would hand explore a define that
refuses the recording preflight just blessed, the known hint-drops-the-define
class), MCP (rides for free: the server self-execs through `--config` and the
case file), and the report (`expected_status`, always present, so a PASS over a
non-zero convention is machine-distinguishable from one that required 0).

Measured on macOS first, then pinned in the container as acceptance check 8
(nine legs): undeclared exit-3 refuses naming both statuses; declared-3 explores
5 worlds with the baseline held to 3; declared-2 refuses naming 3 and 2; the
toml spelling explores and the JSON report carries the field; 256/-1/abc refuse
in both spellings; preflight accepts, carries, and refuses without; the case
round-trips at v2 with the field frozen; a real case stripped to v1 replays
(absent means 0); and `_exit(137)` under `--expect-status 137` explores in full
— an exit status is not a SIGKILL, and every killed world still dies by the
signal. The baseline-forgot-the-declaration mutant (comparing against 0 again)
died loudly in three legs at once, with a diagnostic that read "exited 137 where
137 was expected" — the mutant's own fingerprint, since the message printed the
declared value while the comparison ignored it.

DESIGN §12's sentence — "If Define ever needs more than this, that is movement
toward the kill criteria in §18, and we should notice" — is quoted and answered
in ADR 0014 rather than silently outgrown: `expected_status` is a fact about the
operation, not a new verb, and the sentence now records that it has been faced
twice (marker, ADR 0008; this, ADR 0014).

The blind review round returned three real holes and four loose claims, all
taken. The version and the field did not travel together — a v1 case carrying
`expected_status` and a v2 case missing it were both read under a guessed
contract; both now refuse as malformed. The report mirror was set too late: a
refusal *after* the declaration was read (a status-3 case dying at the contract
gate) said `expected_status: 0` — the mirror now sets at each source the moment
it resolves, and reordering the replay block also fixed a pre-existing wart
where a contract-mismatch refusal did not name its case. And the field lived in
the JSON only, against DESIGN §13's text/JSON parity — the three verdict text
forms now carry it (`expected status: 3` / `expected    exit 3`), pinned by
grep in three legs. The loose claims: the help tail still demanded exit 0 two
paragraphs under the flag that says otherwise; the README's "exactly this
shape" toml omitted the new key and the exclusivity list omitted the new flag;
"diagnostics always name both statuses" overclaimed what a signal death can
name; and the mismatch message blamed `--expect-status` even when the value
came from the toml or the default.

R2 held five of the seven closed and sent two back for a second pass, both
finished here: the zero-operation PASS — a fourth verdict emitter the parity
fix had missed — now carries the status line (and its acceptance leg greps for
it), and the shape gates' claim was honest only for numbers, because a JSON
`null` is indistinguishable from an absent field after parsing. A v2 `null`
refuses like an absence (pinned in the leg); a v1 `"expected_status": null`
passes deliberately — null is not a declaration and the meaning is the same —
and the gate's message now says "declaration", not "field". One R2 remark is
left as-is on purpose: SETUP_ERROR's text form is a single line by original
design and carries none of the classification fields the JSON does; adding
this one there would be inventing a parity the form never had.

## 2026-08-13 — Contract v8: no descriptor number is exempt, and "could not tell" stops passing as "not ours" (#4)

Measured first, on the pre-fix binary, with the new `TOY_DUP2` toy (state writes
through fd 1, fd 2, fd 0, and a stdio leg on rebound stdout):

    no oracle, --allow-unverified:  PASS 9/9   ← the false PASS, real
    with oracle:                    UNKNOWN oracle_missed_operation
                                    (divergence at operation 2: the oracle saw
                                    write(1</tmp/.../dup-fd1.txt>); the shim
                                    recorded open of the *next* file)

Both halves of the hypothesis held: on Linux with the oracle the second witness
already refuses — fail-closed doing its job — and the genuinely wrong verdict
lives on the oracle-less side (macOS, `--allow-unverified`), where four state
files were written through standard descriptors and the report said PASS.

The fix that review shaped (two Criticals deep, past the original one-line
plan): `noteFd`'s early returns shrink to `fd < 0` only — both the `fd <= 2`
skip and the `trace_fd` comparison go, because each was a *number*-based
exemption and a target can rebind any number (the shim's own trace writes never
pass through the wrappers, so the trace_fd check defended nothing). And fd
resolution becomes three-valued: a descriptor **proven** to be a socket, pipe
or character device is evidence the operation is elsewhere; a regular file or
directory whose path cannot be read is **unresolvable** and gets recorded, so
the engine refuses instead of passing; and `st_nlink == 0` now marks unlinked
files on both platforms — closing the macOS gap F_GETPATH left, which this
file previously documented as known-but-open. The harness also refuses
`--work` inside the state directory before running: with the exemptions gone,
the engine's own stdout captures would otherwise become countable state
operations. Trace contract v7 → v8 — the countable set changed, the same
class as v5 (stdio) and v7 (remove) — and saved v7 cases refuse honestly.

Post-fix, same toy, first run: the four descriptor-borne writes are counted
(crash points 8 → 12), and **the oracle agrees on all 12 operations** — the
worry that the shim's own per-operation `statx` would trip the oracle's
unknown-syscall net was measured away, absorbed like the readlink calls before
it. The plain toys' sequences are unchanged (toy-bug still FAILs at crash
point 5 of 5), and `--work` inside state refuses before anything runs.

One toolchain find worth its line: Zig 0.16's std.c deliberately exports **no
libc fstat on Linux** (`.linux => {}` in std/c.zig — the __fxstat legacy), so
the shim asks via the raw `statx` syscall there and libc `fstat` only on
Darwin, where std.c handles the $INODE64 decoration. The local std source
answered in one grep what the compile error alone did not.

The blind review round then broke this entry's own sentence "the trace_fd
check defended nothing" — true for protecting the trace, false as a conclusion.
The *number* is the channel's identity, and with the check gone nothing
defended the channel at all. Measured with a daemonize-style `close(3..255)`
sweep: the shim's trace fd sat at 3, the sweep closed it, the toy's next open
took the number, and `key.json` came back with the shim's binary trace records
spliced between its own bytes — the harness corrupting the data it judges,
refused only by the accident of `state_changed_without_ops`. The channel now
defends its identity itself: relocated at init (`F_DUPFD` ≥ 900, fallback
≥ 200 under macOS's 256 rlimit), and every descriptor-retiring wrapper (close,
fclose, freopen) treats closing it as the channel dying — one final
`unresolved` record while the fd still works, then trace_fd = -1 and silence.
Sweep below the floor: verdict untouched, 5 worlds. Sweep at 1023: refused
`unresolvable_path` with `key.json` byte-identical to what the toy wrote.

The same round found three more, all measured red first: `fdKind` sent
anon-inode descriptors (type bits zero — eventfd, epoll; the kernel's own
spelling, while macOS kqueue stats as a FIFO and never hurt) to
`unresolvable_path`, so one eventfd close refused an innocent run — every
epoll-based target was unjudgeable until type 0 and `S_IFLNK` joined the
proven-non-path class. The `--work` vet destroyed evidence before refusing:
`replay --fresh-state` emptied the state directory and *then* noticed --work
sat inside it (sentinel file: gone), and plain explore planted `<state>/work`
before refusing — the vet now runs before the deletion and removes the one
directory its own resolution creates. And the vet's hand-rolled prefix test
answered "outside" for a state directory of `/` (the byte after `/` in `/tmp`
is `t`); it now uses `isInsideDir`, whose root case the acceptance leg runs
for real — the mutant with the old expression sailed past the containment
message and died on a snapshot error instead, which is exactly why the leg
asserts the message and not the exit code. The same-class scan for the
null-conflation found a second instance in `resolveAt`'s dirfd base — the
`*at()` family answered "not ours" where it could not measure — fixed with the
same three-way split, though no toy can drive that branch (a live directory
whose path query fails is not constructible on demand; recorded as the one
unmeasured edge). The first version of that fix shared one `deleted` flag
between `fdKind` and `fdPath` — and `fdPath` resets its out-param on entry, so
fdKind's nlink==0 finding (the macOS deleted-directory carrier) was erased on
the successful-path branch; caught in the simplify pass by reading `noteFd`,
which had kept the two flags separate all along. The schema page said "v7 today" over a v8 binary; claims 1-3
stayed green because none of them read the version prose, so check 4 now pins
the doc's version words to `contract_version` — seen red against the v7
wording, red again with the anchor prose deleted, green on the real page.

## 2026-08-13 — A sweep dropping walked into the release commit

Caught right after merging the 0.6.0 bump, before the tag: the bump commit
carried `spike/blind-hunt/configs/.latest.hledger-in.journal` — one line, a
date. It is hledger's import-dedup sidecar, written **next to its input
file**, and during the sweep the input file lives inside this repository; the
sidecar sat untracked in the working tree across a branch switch and a
`git add -A` swept it into a commit about something else entirely. Content
harmless (the date of our own committed test transaction), no sealed path
touched — but a release tag should not carry runtime droppings, so it is
removed here and the pattern is ignored before the tag lands. The general
shape is worth the entry: **a target that writes beside its inputs turns the
repo into its scratch space the moment the inputs are committed files**, and
`git add -A` does not ask whose file that is.

## 2026-08-13 — v0.6.0: the first release that ships binaries

Version 0.5.0 → 0.6.0, both hand-written strings at once (the unit test holds
the pair). Minor, not patch: the release carries four new user-facing pieces —
`sideeye demo`, `sideeye preflight`, `sideeye version`, and the release
workflow itself. The version number was an explicit decision, not an
assumption (the owner flagged it for consideration; minor won because the
content is features, and a patch number would under-report it).

This is the release where `release.yml`'s upload leg runs for the first time:
until tonight, the prebuilt tarballs existed only as CI artifacts on a pull
request. The ceremony therefore grows its recorded new step — after
publishing, verify the workflow went green and `gh release view` actually
lists the assets, because the failure mode this trigger design accepts is a
published release standing empty. Also new to this ceremony: the shipped
artifact itself gets exercised — download a tarball, unpack, run the demo,
expect exit 1 — because "the workflow uploaded something" and "a visitor can
run what was uploaded" are different claims.
## 2026-08-13 — Between the seals: five invocations from permitted sources, committed before the sweep (#83)

Seal A merged this evening (PR #89); this entry is the between-seals phase it
authorizes. All five candidates installed pinned (`spike/Dockerfile`), their
invocations assembled from `--help`, two official-docs pages, and normal-run
observation only — the ledger itemizes every consultation — and committed
*before* the sweep runs, so the manifest's invocations hash has something to
bind to (ADR 0012).

What the permitted sources decided, without touching a trace:

- **topydo** drives its two files (`-t` todo, `-d` archive) into one state
  directory; `do 1` completes-and-archives — assembled exactly as hoped.
- **khard** and **khal** both name their state through a config file (formats
  from their readthedocs pages) and mint randomly named files per entry —
  observed from the filenames alone, which normal runs are allowed to show.
- **abook**'s only stdin-free writer is `--convert`; the interactive book
  editor and `--add-email` both need what the exploration engine does not
  provide (a terminal, stdin).
- **hledger** appends via `import`; its journal is seeded by `/bin/cp` in
  setup, where any tool is allowed.

The sweep ran once, with the oracle, and this is everything the experimenter
has seen of it:

    topydo exit=0 resolved=yes
    khard exit=0 resolved=yes
    abook exit=0 resolved=yes
    khal exit=0 resolved=yes
    hledger exit=2 resolved=yes

Four recordings accepted; hledger refused — **why is sealed**. The refusal
detail sits unread in the hashed artifact until Seal B, exactly because a
refusal reason is knowledge about how a target behaves under observation.

`select.sh` applied the sealed predicate to the committed manifest:
**topydo** — first in the sealed priority order with exit 0 and in-image
resolution. Nobody chose it; the choice was merged five hours before the
sweep existed. Next (a fresh phase, deliberately not tonight): the
declaration — invariants with per-line provenance, the operation inventory,
the concrete checkers — then Seal B, and only then the first crash world.

## 2026-08-13 — Seal A: everything about the blind hunt is decided before a target runs (#83)

§17's first condition — "Sideeye discovered it automatically" — is the one part of
the primary criterion the timewarrior finding could not honestly claim, and the one
piece of remaining v1.0 work with no guaranteed outcome. This entry seals the
procedure for measuring it (ADR 0012): the campaign that will try to find a real bug
from an invariant declared before anyone knew the bug existed.

**The design died twice in review before it was right, and both deaths are worth
recording.** Draft one swept candidates with preflight and picked the promising one —
but preflight's operation counts and refusal reasons correlate with how breakable a
target looks, so choosing after seeing them is choosing informed; the same direction
of leak as reading traces, only politer. Draft two sealed the *information sources* —
and the reviewer pointed out that source rules alone let the declarer run the tool,
watch what happens, and then pick, from those same permitted sources, exactly the
invariants that fit. Hence two seals: the procedure (candidates, priority, a
discretion-free selection predicate, reference rules, wrapper template, audit
tooling) frozen before any candidate is installed; the declaration (invariants with
per-line provenance, operation inventory with a fixed exclusion vocabulary, concrete
checkers) frozen after the permitted contract reading and before the first crash
measurement. Exploration runs only at the second seal's commit, from a clean tree.

Choices made here, and the shape of their honesty:

- **The selection predicate takes the first exactly-one candidate** (preflight exit 0
  ∧ commands resolve to absolute paths inside the image). Not "one or two" — a count
  with slack is a stopping decision made after seeing how the first target went. The
  in-image leg is the structural proxy for "a saved case will replay here without
  external builds" (the timewarrior regression case is still recipe-bound; #82 —
  that hole does not get re-dug on a new target).
- **The sweep shows exit codes only.** Full reports go unread into a hashed local
  artifact. Unread is a working rule, not a proof; the hash makes a later swap
  detectable while the reports are retained, nothing more. Said so in the ADR,
  said so in §17.
- **The criterion was widened before the campaign, not after.** PRD criterion 1
  named "omamori or the calibration target"; a blind-protocol target now counts,
  and the sentence itself records the date and the reason. Author-confirmed is
  fixed to the timewarrior reading (project author judges; upstream sought, not
  required) — the same answer #82 needs, decided once.
- **These are high-risk blind targets, not average ones.** topydo, khard, abook,
  khal, hledger — file-backed state chosen on purpose from web docs alone, several
  spanning multiple files, two single-file counterweights. The §18 average-target
  calibration already stands on timewarrior; this campaign does not claim it twice.
- **The taint ledger names what cannot be blind anymore** (timewarrior, taskwarrior,
  git, todoman, watson, jrnl, omamori) and admits what carries over anyway: class
  knowledge, and a language model's training data. The seals make the *recorded*
  consultations and the commit order auditable — the ledger is self-reported, and
  an unrecorded consultation is exactly what it cannot detect. They cannot make
  the experimenter forget. §17 carries the claim at exactly that strength.
- **Reviewer covenant with breach handling**: a reviewer who names target internals
  or known issues burns that target; so does an experimenter who touches a
  forbidden source. The ledger records it and the campaign moves down the sealed
  order. No cure — blind is once per target.

Also recorded, from the review mechanics themselves: the first adversarial-review
call on this plan came back as a 258 KB transcript that quoted engine source at
length and then died on the reviewer platform's safety filter — zero findings,
reported as success. A long response is not evidence a review happened; the verdict
was at the tail, and the tail was an error. The re-run, phrased neutrally and told
not to quote source in its reply, went through on the same model.

Code review on the seal itself found eight P1s — all protocol holes or
document-vs-tooling gaps, all fixed before the seal merged, which is the one
moment they were still fixable:

- The sweep's *inputs* were the unguarded loop: nothing stopped tuning
  invocations against exit codes and committing only the final spelling. Now
  the manifest embeds the SHA-256 of the invocations it ran against, the
  committed file must match (verifier B3), the sweep runs once, and a re-run
  after a broken invocation keeps both manifests committed with a ledger entry.
- The verifier audited endpoints, not history: it never checked that Seal A is
  an ancestor of Seal B (A0, new), compared only the two trees so a
  change-and-revert inside the range hid (A2 now walks `git log A..B` over the
  sealed paths), accepted a declaration for *any* candidate (B4 now recomputes
  the selection from the committed manifest + priority + burned list, using the
  committed selector, and requires the single declaration directory to match),
  and could print an unqualified pass with the run manifest simply not supplied
  (the verdict line now says PARTIAL unless R1 was audited).
- The seal was narrower than the ADR said: PRD/DESIGN — the criterion wording
  the campaign is scored against — now ride the A2 no-touch set, and the ledger
  gets an append-only check (A3: Seal A's ledger must be a byte prefix of
  Seal B's; entries cannot be deleted en route).
- The implemented predicate was weaker than the declared one: the oracle is now
  mandatory in the harness, and resolution covers the binary, the setup's and
  operation's first words, and the shim (loaded, not executed — checked as
  absolute-and-readable, since `command -v` would demand an execute bit a
  shared object need not carry).
- Breach handling contradicted the one-target rule. Resolved by phase: a
  pre-Seal-B burn appends to a committed `burned.txt` and selection re-runs
  with it as an explicit selector input; a post-Seal-B burn ends the campaign.
- Two claims were stronger than their machinery: the report hash "proves"
  became "makes later substitution detectable while the reports are retained"
  (with an R2 verifier leg that actually recomputes when they are supplied),
  and "what was consulted is checkable" became "recorded consultations and
  commit order are auditable; the ledger is self-reported". The criterion's
  "no hand-written adversarial crash tests" became "documentation does not
  advertise crash-injection testing" — verifying the stronger phrasing would
  require reading the target's test suite, which the source rule forbids.

Next: merge = Seal A. Then install the candidates into the container, read only what
the rules allow, assemble invocations, sweep, and let the predicate pick.

## 2026-08-13 — The entrance gets paved by shrinking a claim, not growing the tool (#75 #76 #77)

Three entrance features in one branch — release tarballs, `sideeye demo`,
`sideeye preflight` — because v1.0's criterion 6 (a fresh machine reaches its
first exploration in under ten minutes from the README) currently dies at the
first cliff: install a pre-1.0 compiler to see anything at all.

**The plan-review reversal worth recording: preflight's claim was wrong before a
line was written.** The draft said preflight answers "explorable, or refused for
reason X". The adversarial plan review pointed at what the cut point cannot see:
`kill_did_not_land`, world-side boundary refusals, `baseline_run_failed`,
`baseline_violates_invariant` and checker falsification all live in or after the
exploration loop, which preflight never enters. "Explorable" was therefore a
claim the command does not earn — the same overclaim shape §17's scoring polices.
The fix was to shrink the claim: preflight says **"recording accepted"**, and a
fixed-vocabulary `not checked` block names the four exploration-only classes
every time. Acceptance check 6 pins the wording both ways: a target that is
recording-clean but exploration-refused (`TOY_NONDET_REWRITE` on the fixed toy —
recording gates all pass, the baseline world refuses) must be *accepted* by
preflight with baseline behavior named as unchecked, while `explore` on the same
define exits 2 with `baseline_violates_invariant`. A preflight that mirrored
explore's verdict fails the first half; one that claims everything fails the
second. Measured: the vocabulary mutation (dropping "baseline behavior" from the
block) went red in the container before the wording was trusted.

**Preflight's mechanics**: a third mode sharing the explore pipeline, cut at one
place — after `n = kill_point_count` is known, before the zero-op PASS branch —
with an unconditional exit. No detector is duplicated; a refusal exits through
the same `unknown()` with the same name a real run prints. The define-shaped
flags (`--check`, `--marker`, `--config`, `--json`, `--allow-unverified`) are
refused by name, not ignored — an accepted-but-inert flag would be a declared
intention that silently never fires, the shape the toml parser already refuses.
`--json`'s rejection sits *before* the `removeFile` in its parse branch: a
refusal that had already deleted the caller's previous report would be a refusal
with a side effect.

**The demo compiles its toy on the visitor's machine and self-execs explore.**
The embedded assets are `spike/toys/toy.c` and `spike/check.sh` — the same files
the acceptance suite drives, so the demo cannot drift from what CI proves (both
now listed in build.zig.zon's `.paths`, or a fetched package would not build).
Choices that review corrected before they became bugs: the checker is invoked as
`/bin/sh <path>` (a Written file has no execute bit and posix.zig has no chmod),
and `TOY` is baked into the script's first line rather than passed through the
environment (the checker runs a fresh process several layers down; a baked value
cannot be lost to an exec-model change). The self-exec is plain `execvp` with
the inherited environment — the MCP minimal-env helper exists to withhold
credentials from an untrusted config's operation, and the demo's operation is
our own toy. Compile ladder: cc → gcc → clang, each with `-lpthread` then
without; no compiler at all refuses by name with the install hint. Measured on
this Mac first try: exit 1, crash point 5 of 5, same numbers as the README
showcase — and the first run's output opened with a screenful of clang's vfork
deprecation warnings, so the compile now carries `-w` (the toy's warnings are
addressed to this repo's developers, not a demo viewer's terminal). The
checker's own stderr ("doctor says 'healthy' but the key is unloadable") stays:
that is the instrument speaking, twice — once at falsification, once in the
violating world.

**The release workflow builds on three native runners** (`ubuntu-latest`,
`ubuntu-24.04-arm`, `macos-latest`) rather than cross-compiling from one: a
cross-built artifact cannot be *run* where it was built, and the per-artifact
smoke test is the demo itself — exit 1 on the runner, through the shim the
binary just found beside itself, exercising the ReleaseSafe build the acceptance
suite (Debug) never touches. Trigger is `release: published` so the manual
ceremony stays the origin; the failure mode that leaves a published release
without assets gets two answers: `workflow_dispatch` with a tag re-uploads, and
the ceremony gains a step — after publishing, verify this workflow went green
and `gh release view` shows the assets, before announcing anything. The upload
job carries `permissions: contents: write` explicitly. `sideeye version` (one
line, exit 0) exists because the workflow must hold each artifact's binary
against its tag, and the usage banner — the only place the version appeared —
exits 3. The tarball inventory is diffed against an expected list before upload:
a tarball without the shim is half the product, silently. The
`ubuntu-24.04-arm` runner is an assumption until the PR's build-only trigger
runs; if it is unavailable, the fallback recorded in the plan is a cross-build
with the smoke honestly marked absent, not a silent drop of the architecture.

Container measurements for the whole batch: acceptance checks 5 and 6 (six legs)
green; both source mutations KILLED (`-DBUGGY` removed → demo exits 2 with no
window named; vocabulary dropped → wording assert red); four synthetic reds
(refuse leg fed an in-bounds toy → 0, compiler-absent leg with a normal PATH →
1, fallback leg with cc and gcc both failing → 3, honesty pair's explore side
without the rewrite → 0). mcp-acceptance untouched and green — the only mcp.zig
change is `canonicalSelf` going pub for the demo's self-exec.

Code review (R1) found three real ones, all fixed and confirmed in R2:

- The release workflow's repair path (`workflow_dispatch` with a tag) checked
  out the default branch, so a "repair" would have rebuilt current main and
  uploaded it under the old tag's name — an artifact whose content is not the
  tag's, with `--clobber`. The checkout now takes the dispatch tag as its ref,
  and the version-against-tag assert runs on tag-named dispatches too, not
  only on release events.
- The preflight graduation hint dropped `--setup`: the define it suggested was
  silently different from the define it had just accepted. The hint now
  carries it, and acceptance check 6 greps for it — seen red against the
  unfixed binary before the fix was written.
- The demo baked `TOY=<path>` into the checker unquoted; a `$TMPDIR` carrying
  shell metacharacters would have handed them to `/bin/sh`. Now single-quoted
  through a complete POSIX escape (`'` → `'\''`), unit-tested, and the space
  guard on `$TMPDIR` stays for the separate splitArgs constraint. Same-class
  scans for all three classes found no further instances (the FAIL report's
  replay line is structurally immune — the define travels inside the case).

## 2026-08-13 — v0.5.0: the README stops introducing the tool as v0.1

Version 0.4.0 → 0.5.0, both hand-written strings at once (the unit test holds
the pair). The release carries the docs catch-up (#67), on the discipline the
repo already owes its examples to: the README's showcase FAIL was regenerated
with the 0.5.0 binary rather than trusted — and the regeneration itself proved
the point, because the stale example was missing five lines the report has
grown since v0.1 (atomicity, l1, case, replay, processes) and showed old
prose in two it rewrote (oracle now records a real agreement where
`--allow-unverified` used to apologize; checker now counts its worlds). The Status
section now tells the five-milestone story instead of the feasibility spike's;
the target-constraints section drops "for v0.1" and folds in what the
observation surface learned since (stdio at flush granularity, the hard-link
family, rustix-class raw syscalls as the canonical refusal example); the toml
gains equal billing with `--state`. The CHANGELOG's `[Unreleased]` became
`[0.5.0]` with the milestone summary; the PRD's v0.5 heading carries
"delivered". Everything else in this release rode earlier PRs the same day —
this one is the ceremony.

## 2026-08-13 — v0.5's last two items: the report as a schema, the quickstart as a workflow

The milestone's remaining scope line — "the report JSON documented as a
schema; a quickstart for CI (GitHub Actions example)" — closed with the same
discipline the README learned in v0.1: a document nothing executes is a claim
nobody measured.

**`docs/report-schema.md`** documents every field the report carries, per
verdict, plus the closed `unknown_reason` set — and acceptance check 4 holds
the page to reality in both directions: four fresh reports covering all four
verdicts (their union of fields must all be documented, every documented field
must appear in one of them), and the doc's `unknown_reason` list must equal
the contract's enum exactly. The comparison lives in
`spike/check-report-schema.py` taking paths, so the doc side falsifies in
isolation; three mutations seen red (a deleted field row, a deleted enum
value, a phantom field nothing generates) and green on the real page.

**The check caught two real drifts before it was even trusted.** First, its
own field regex `[a-z_.]` silently dropped `l0` and `l1` — a digit in a field
name — and reported them undocumented while they sat in the table (the
checker's first red was against itself). Second, the doc's `unknown_reason`
list was **seven values short**: the sed extraction used to WRITE the page
(`sed -n 'X,+40p'`) truncated the enum at forty lines and the page inherited
the truncation — the doc-writing pipeline was fail-open, and only the check
comparing against the enum itself exposed it. Also learned en route:
"toy-bug without an oracle" is NOT an UNKNOWN recipe — a FAIL stands on its
own evidence without completeness; the oracle gates only the would-be PASS
(the check's verdict-coverage guard fired on this, correctly, before the
comparison could go vacuous).

**`docs/ci-quickstart.md`** documents `.github/workflows/quickstart.yml` — a
REAL workflow that runs on every push to main and every pull request, against
a committed `docs/ci-quickstart/sideeye.toml` and this repo's planted-bug toy,
so the quickstart example is executed by CI rather than trusted. The demo job passes
iff sideeye finds the counterexample (exit 1, the gate a reader inverts for a
clean target); measured in the container before the workflow existed: FAIL at
crash point 5, the unlink→rename window — re-measured with no extra
environment after review showed the workflow's `TOY_STATE` was dead weight
(sideeye itself exports it to its children, pointed at the resolved state).
The doc carries the exit-code table and the honest default for UNKNOWN in CI:
fail the job — treating a refusal as green is how a target quietly leaves the
tested set.

**Review corrected the corrector.** The first-look pass found the digit bug
this entry brags about catching still alive in the enum regex fourteen lines
below the field-regex fix — a `[a-z_]` that would let a future digit-bearing
refusal (`l2_*`) slip out of the closed-set claim, and whose failure message
pointed the wrong way ("doc-only" reads as "delete it from the doc"). Fixed by
scoping the extraction to the whole enum block (values declared after a
`pub fn` count now) with strict member indentation, and falsified against a
mutated contract carrying `l9_added_after_fn` after the fn — red, in the
right direction. Smaller corrections in the same round: `explored ==
crash_points + 1` does not hold for a zero-operation PASS (both counters 0 —
now stated); `earliest.invariant` has five values, not three (the two
combined-layer forms are now listed, literals verified against main.zig); the
quickstart's short replay command was missing the required `--shim`; and
"every push" was the kind of rounding-up this repo dislikes — it runs on
pushes to main and pull requests.

## 2026-08-13 — The MCP-mediated run: two product gaps first, then the loop closed through the surface

The optional follow-up to the loop-closure measurement — drive the same sealed
experiment through `sideeye mcp` instead of the replay.sh plumbing — was
attempted the same day. It did not reach an agent. Probing the wiring against
the recorded loop-1 stage (read-only) surfaced two product gaps, which is the
kind of result the confirmation run exists to produce:

- **#68 — the minimal-env child cannot serve env-located-state targets.** The
  server hands its child PATH only (deliberate, ADR 0010: a config's operation
  must not read the server's credentials). But timewarrior finds its state
  through `TIMEWARRIORDB`; the sealed case replayed as `UNKNOWN
  (case_no_longer_applies): the recording now counts 0 state-changing
  operation(s)` — setup and operation ran against timew's env-free fallback,
  not the case's state dir. The 08-12 over-the-wire measurement used the toy
  scenario, whose operation takes its path as an argument; the gap was
  invisible from there.
- **#69 — no per-call state freshness.** `sideeye replay` re-runs setup onto
  whatever the state dir holds; every CLI caller so far provided a pristine
  dir (fresh container per replay), so the precondition was never written
  down. An MCP server is started once per client session: the second replay in
  the same session died in setup (`timew: You cannot overlap intervals`) —
  measured over the CLI with correct env, so it is not a symptom of #68. An
  agent's edit → rebuild → re-check loop through this surface dies on its
  second check.

**Decision (approved): fix the product before running the experiment**, rather
than scaffolding around the gaps (an env-free state location plus an
out-of-band state reset would have carried the run, but three more moving
parts to prove, and the honest conclusion would still have been "the surface
alone is not ready"). The fix directions, fixed before implementation:
`SIDEEYE_MCP_CHILD_ENV` — a comma-separated allowlist of variable NAMES,
values resolved from the server's own environment, so the operator who already
owns the trust boundary decides what the target needs and the agent never
touches it; a name listed but absent from the server environment is a loud
tool error, not a silent skip (a typo must not reproduce the silent 0-ops
failure). And `sideeye replay --fresh-state` — the state dir is already
sacrificial by contract (exploration kills processes mid-write into it), so
the flag empties and recreates it through the engine's existing guarded
deletion (`assertSafeRoot` + the same deleteTree the restore path uses); the
MCP server always passes it for replay children, the CLI default is unchanged.
Both changes get their acceptance checks red first.

**Harness facts measured on the way, for whoever wires an agent to MCP next:**
`--safe-mode` never starts `--mcp-config` servers (zero traffic on the snoop —
the config is not even read). The working seal replacement, measured:
`--disable-slash-commands` + `--settings '{"disableAllHooks":true,
"enabledPlugins":{...off}}'` + `--strict-mcp-config` from a foreign cwd gives
plugins [], skills 0, zero hook events across a real Write, OAuth intact, MCP
connected — residue: user agent names stay visible in the init event, inert
once Task is denied. Claude Code 2.1.229 speaks the 2026-07-28 stateless
protocol natively (first client frame is `tools/list` with `_meta`, snooped
verbatim — the missing-`initialize` worry was empirically unfounded). `--bare`
is not usable here: it skips keychain reads, so OAuth dies — same wall as the
scratch config dir. And a `:ro` DIRECTORY bind mount silently mounted nothing
on this docker/virtiofs stack — the container saw an empty path where the
stage should be; the same run's plain rw mount of the same directory worked,
and judge.sh's `:ro` FILE mount (the pos control's patch) demonstrably works,
so the failure is narrower than ":ro is broken" — measured for the directory
case only, cause not isolated. The stage mounts stay rw.

**Implemented and measured the same day (ADR 0011).** Three new acceptance
asserts were seen red against the pre-fix binary first: the allowlisted var
did not reach the child (check 7), a listed-but-absent name was not refused
(check 7), and the replay triple came back FAIL / SETUP_ERROR / SETUP_ERROR —
the toy's deliberately non-idempotent setup (mkdir of a fixed name) reproduced
the timew overlap shape exactly (check 8). After the fix: all 8 mcp-acceptance
checks green in the container, including check 4's isolation claim unchanged —
the unlisted secret still does not reach the child, now asserted in the same
run as the pass-through. Unit side: `freshDir` sits behind `assertSafeRoot`
(pinned with I/O-free guard tests; the behavioral half is pinned at the call
site by check 8, which is where the workspace discipline wants it). The
real-target contrast then held through the MCP channel against the recorded
loop-1 stage with `SIDEEYE_MCP_CHILD_ENV=TIMEWARRIORDB`: the reverted
(unpatched) tree replays **FAIL, crash point 19, twice in one server
session**; the agent's fixed tree replays **PASS, explored 2, twice** — same
code path, opposite answers, repeatable. One reading trap for whoever repeats
this: the loop-1 stage's `repo/` is the agent's FIXED tree, so PASS there is
the expected answer, not a broken probe.

**The confirmation run's protocol, fixed before the run (VARIANT=mcp).** Same
judgement, same seal discipline, same primary three-condition AND as the first
run — nothing about how the verdict is reached changes. What changes is the
agent's re-check button and its wiring, declared here before any agent runs:

- **Input set**: report JSON + the case it names + the define's setup/check +
  the pinned repo + `build.sh` (bug-blind rebuild-and-install plumbing) + the
  `sideeye_replay_case` tool served by `sideeye mcp` — started by the client
  from `mcp.json` at the root (outside the stage; the agent never reads it),
  with `SIDEEYE_MCP_CHILD_ENV=TIMEWARRIORDB` and PATH carrying `$STAGE/bin`,
  where build.sh installs the rebuilt binary. The seal stays seven files;
  replay.sh is simply replaced by build.sh.
- **Controls**: the judge's neg/pos pair as before, plus a third — the MCP
  channel itself must give opposite answers on this stage (unpatched: FAIL at
  the case's k, twice in one server session, because per-call freshness is
  part of what is proven; patched: PASS) before any agent runs. `finalize`
  refuses an mcp-variant record without it.
- **Seal recipe**: `--safe-mode` never starts `--mcp-config` servers, so the
  measured replacement is `--strict-mcp-config` + `--disable-slash-commands` +
  settings (hooks off, plugins off by name) + foreign-cwd project namespace.
  Residue stated: user agent names remain visible in the init event, inert
  with Task/Agent denied. Canary 1 asserts the measurable parts from the init
  event; canary 2 observes the enforcement once before the stage is burned
  (half of #63). **Canary 2 fired on its first form and was recalibrated** —
  the "nothing may fetch the page" assertion conflated two channels with
  different owners. What the probe actually showed: **in this configuration**
  the disallowed tools are ABSENT from the presented set (init carries no
  WebFetch — stronger than the allowlist, which leaves tools visible). Scoped
  deliberately: run 1's init, same CLI and the same five `--disallowedTools`
  but under `--safe-mode`, still presented all five — the removal was not
  isolated to the flag alone. The page arrived through allowed Bash + host
  network instead (`curl`), which is the declared soft-seal residual the
  AUDIT owns in the sealed run. The
  canary now asserts absence-from-init for the launcher's whole deny list plus
  no WebFetch attempt, and records the Bash residual instead of failing on it.
  The miscalibrated form did its one job correctly — it refused to burn the
  stage until the failure was understood. After the run, review widened the
  deny list to eleven names (the outbound/delegation surface: SendMessage,
  PushNotification, RemoteTrigger, ScheduleWakeup, CronCreate, CronDelete
  join the five) — and because removal is the configuration's behaviour, not
  the flag's, the widened list was MEASURED in a throwaway session before
  being trusted: all eleven absent from init, core tools intact. The recorded
  run itself used the five-name list; its six new names were merely
  void-by-audit then, denied-at-launch now.

**The run (same day): the loop closed through the MCP surface.**
`spike/runs/sideeye-loop-2/manifest.json`; numbers below are from the
manifest or the transcript's result event (the launcher now records
num_turns / duration / cost into agent-meta so the next run's headline is in
an artifact, not hand-read). Fresh stage at the pin reproduced the finding
(FAIL, k=19 of 24); all three controls held (judge neg with the crash-point
pin, judge pos, and the MCP channel contrast: unpatched FAIL@19 twice in one
server session, patched PASS). The agent: **claude-fable-5** (CLI 2.1.229) —
a different model than run 1's claude-opus-5, both Claude 5 family;
`models_billed` also carries a $0.0009 haiku sliver (CLI internals). **38
turns, 8.9 minutes, $4.43** (run 1, same num_turns metric: 75 turns, 16.6
min, $5.97). Tool ledger: Bash 19 / Edit 10 / Read 5 / Grep 1 /
**`sideeye_replay_case` 1** / ToolSearch 1 — the ToolSearch loaded the MCP
tool's schema (recorded `off_allowlist`, a local tool, not a void; it sits on
the path to the surface, so it is named here). Audit: clean — zero network
reaches, zero context reads, `server_tool_use` 0/0. The stage's only extra
file was `bin/timew` — present since the channel contrast installed the
agent's starting world, rewritten by the agent's one `build.sh` run; the diff
cannot and need not distinguish the two, the judge builds from `repo/` alone.
Judgement: replay gate **pass**, non-degeneracy gate **pass**, **loop_closed:
true**. **What the ledger actually shows — no iteration happened**: calls
1–33 read the tree and made 11 edits, call 34 was the first and only build,
call 36 the first and only replay — **PASS on the first attempt**; the MCP
call was the agent's only verification (plus one normal-world sanity check
after). The honest limit riding that: the edit→rebuild→re-check loop that
`--fresh-state` (#69) exists to support was exercised by the channel contrast
(two calls, one session), not by this agent. The fix is the third independent
derivation of the same three targets as the human patch, each part
implemented differently — journal-before-data via a `finalize_first` mark
and a two-pass `finalize_all` (vs opus's `commit_first` + `stable_partition`,
vs the human patch's reversed rename order); a stale-`tags.data` tolerance in
`Database::deleteInterval` (a tag absent from the index already has a zero
count — the human patch and opus both reordered instead, opus via
`commitTagDatabase`); and a no-op undo for an intent
that never landed (a `hasInterval` probe like opus's, arrived at
independently). Its final message names the rename-order root cause and both
violation windows precisely. The same cosmetic leak as run 1: the agent
answered in Japanese to an English prompt (path still not identified).
- **Audit**: `--allow-mcp sideeye` admits exactly the one trusted server's
  tools; every other `mcp__*` stays a void by name; all other void conditions
  unchanged (seen red/green against synthetic transcripts and re-run green on
  the recorded loop-1 transcript).
- **Acknowledged wrinkle**: `$STAGE/bin/timew` is executed from the virtiofs
  mount. The syscall-fidelity invariant covers the OBSERVED state dir, which
  stays container-local (`/tmp/loop-state`); executing a binary from the mount
  is not observation, and the channel contrast measures this wiring end to end
  before the agent does.

**The first-look review reversed one piece of the design; recorded here per
the contract.** The first implementation handed `freshDir` the case's raw
`define.state`. Review showed `assertSafeRoot` is lexical — "/tmp/../etc"
counts three slashes and passes, then the kernel resolves it to /etc; a
symlinked root walks past the same way — while every other destructive engine
call receives the realpath'd `state_abs`. The call moved to sit after the
existing mkdir-then-resolve and now receives `state_abs`, which also put every
setup validation ahead of the one destructive step and closed the symlinked
root that `deleteTree`'s child-level symlink refusal could not see. In the
same round `freshDir` stopped returning success when it could not do its job:
a regular file or a missing parent at the state path is a loud
`DeleteFailed` now — the silent no-op was the exact shape this flag exists to
remove. ADR 0011 Decision 2 carries the resolved-path requirement as part of
the decision, and the unit test pins the fact that makes it load-bearing
(`assertSafeRoot("/tmp/../tmp")` passes — the guard alone is not the
protection). The mutual contrast and the acceptance suite were re-measured
after the relocation: identical results.

## 2026-08-13 — Loop closure: the protocol is fixed before the run

The v0.5 milestone's remaining item is the loop-closure test itself (DESIGN §17,
second criterion; PRD v0.5). The protocol is written down here BEFORE any agent
runs, so that no gate moves after the measurement starts.

**The input set, declared.** §17 says "the counterexample report (JSON + replay
command) and the repository". As run, the set is: the report JSON, the case file
the report names, the define's `setup.sh` / `check.sh` (the declared invariant —
the case points at them and the replay cannot run without them), the timewarrior
checkout at the pinned commit `db7751cb`, and `replay.sh` — bug-blind plumbing
that rebuilds `./repo` and replays the sealed case in a `--network none`
container. The result will be reported with this set as its subject, not as
"the report alone". The stage carries the sideeye binary and shim as `.harness/`
(the plumbing has to run something); they contain no knowledge of the finding.

**Primary judgement, three conditions AND, fixed now:** (1) *originality* — the
judge trusts only `repo/` as the agent's work; every other staged file is
verified against a seal (sha256 manifest + pristine copies taken at stage time)
and restored from the seal before judging, so doctoring the checker or the
plumbing cannot reach the verdict; (2) *replay* — the judge's own fresh replay of
the sealed case must satisfy the leg-C predicate (PASS, explored 2, no
unknown_reason, crash_points == the case's ops_total); (3) *non-degeneracy* — in
a normal crash-free world, seed → track → undo must remove exactly the newest
interval. The checker's non-destruction form deliberately admits an undo that
always no-ops (2026-08-12 entry); a "fix" that silences the checker by
lobotomizing the feature fails gate 3 and is declared a failure up front. The
agent's prompt warns about this in general words only ("a change that disables
or degrades a feature does not count") — the checker already shows the agent
that undo is being exercised, so nothing about the finding leaks.

**Controls before the agent.** The judge must produce opposite answers on the
same code path before any agent runs: the unpatched tree must reproduce the
failure (gate 2 red, gate 3 green), the known patch must pass all three gates.
A constant-answer apparatus cannot satisfy both; the mutual contrast is the red
for these checks.

**Seal is soft, void is hard.** The agent host is a fresh headless Claude Code
session: `--safe-mode` (no user memory, no MCP, no hooks — the plan said scratch
config dir; that reversed, the dead-ends below carry the measurement), cwd = the
stage, a six-tool allowlist (Bash/Read/Edit/Write/Glob/Grep). An allowlist is
not a menu: the harness still presents its full tool set, web tools included, so
what a clean run proves is recorded non-use, not inability — all tool calls land
in a stream-json transcript and the audit reads every one of them. This is not a network namespace — Bash could reach the network — so
the invalidation condition is declared instead: the audit enumerates every call,
and one network reach or one read into this workspace voids the run. If a void
actually happens, the next run moves into a container with an egress allowlist;
building that fortress first was rejected as cost without a demonstrated need.
The upstream issue (timewarrior#778, filed 2026-08-12) postdates the model
cutoffs, so with the web closed it is unreachable; the model id is recorded in
the manifest either way.

**One deviation from the plan as approved:** the plan put the explore's work dir
container-local; as built, `work/` lives in the stage (mounted at the identical
absolute path in host and container) so that the report's `case` and `replay`
fields name paths that are real in the agent's world — the report telling the
truth about where things are IS the thing under test. The state dir stays
container-local (`/tmp/loop-state`): it is the directory under observation and
its syscall semantics must not ride a virtiofs mount. After the explore, the
work dir's traces and captures are moved out to `spike/runs/` — the input set is
the report, not the trace — and only the case file survives in place.

**The run (same day): the loop closed.** `manifest.json` in
`spike/runs/sideeye-loop-1/`; every number below is from the judge's own
measurements, not the agent's claims.

- **Stage**: fresh explore at the pin reproduced the finding exactly as in v0.4
  — FAIL, case k=19 of 24, two violating worlds. Seven files sealed.
- **Controls held**: unpatched tree → replay `fail_reproduced` + functional gate
  pass; known patch → all three gates pass. Opposite answers from one code path.
- **The agent**: claude-opus-5[1m] (CLI 2.1.229), headless `--safe-mode`, cwd =
  the stage, a six-tool allowlist (Bash/Read/Edit/Write/Glob/Grep), no MCP, no
  memory. The transcript's init event shows the full tool set was still
  presented — web tools included, no denial ever recorded — so the claim is
  non-use, with two independent witnesses: every one of the 74 tool calls is on
  the six (Bash 37 / Read 17 / Edit 19 / Grep 1), and the server-side counters
  read `web_search_requests: 0, web_fetch_requests: 0`. 75 turns, 16.6 minutes,
  $5.97. Audit: clean — zero network reaches, zero reads into this workspace,
  zero edits outside `repo/` within the stage (the only extra file was its own
  `replay-latest.json`; it did write two scratch logs under the host's `/tmp`,
  against the prompt's letter, and read them back itself only).
- **Judgement**: replay gate **pass** (PASS, explored 2, crash_points 24 ==
  ops_total, fresh state, rebuilt from the agent's tree with everything else
  restored from the seal); non-degeneracy gate **pass** (normal-world undo still
  removes exactly the newest interval). **loop_closed: true.**
- **Secondary observations**: judge-side full explore of the agent's tree —
  **PASS 25/25 worlds** (24 crash + 1 baseline; both violating worlds gone).
  Upstream suites on the agent's tree: AtomicFileTest 18 pass / 0 fail /
  6 skipped — the six are the fault-injection cases (`FIU_ENABLE` is compiled
  out without libfiu, which the image lacks), and they cover exactly the error
  paths the agent's change touches, so that 0-fail is lighter than it reads —
  data.t 96/96, Datafile.t 2/2, TagInfoDatabase.t 8/8 (`test/AtomicFile.t`, a
  bash launcher for the same binary, errored on a path it hardcodes; ignored as
  a duplicate of the directly-run binary, not counted as a pass). The agent's own broader
  before/after comparison (undo.t 29/29, track.t 15/15, config.t 22/22, ~1055
  C++ asserts, pre-existing chart.t/help.t failures identical on both sides) is
  recorded in the transcript but is its claim, not the judge's.
- **The fix itself**: the agent independently re-derived the same three-part
  mechanism as `spike/timew-undo-ordering.patch` — journal renamed before the
  data it describes (write-ahead), tags.data ordered ahead too, and an undo of
  an intent that never landed becomes a no-op — implemented differently
  (a `commit_first` flag + `stable_partition` in `finalize_all`, and a
  `hasInterval` probe in CmdUndo). Its final message names the root cause
  precisely: the rename order was first-touch order, so data files (touched by
  load) renamed before the journal. Nothing in its world named undo except the
  declared invariant (`check.sh`), the report's crash-window paths — and,
  because the stage carries a full clone, the upstream branch name
  `issue/772-undo-command-documentation`, which its `git branch -a` did print
  (a documentation issue, different mechanism; harmless here, but a full clone
  also means an older pin would ship upstream's own later fixes inside the
  stage — a shallow-fetch stage is filed as follow-up).
- **Apparatus checks that had not fired were fired deliberately** (on a copy of
  the root, so the real run's records stay untouched): a doctored all-pass
  `check.sh` was detected, restored from the seal, and re-verified by hash. The
  copy's replay then refused with SETUP_ERROR — a case pins absolute paths and a
  relocated root is not the recorded world (the identical-path mount invariant,
  demonstrated rather than argued) — which also means the end-to-end
  proposition "a doctored checker still cannot reach a *completed* replay
  verdict" was not carried through on the copy: what is measured is detect →
  restore → re-verify, plus the refusal. `finalize` on a results dir missing
  the controls exits nonzero — the record's completeness rides the exit code.
- **Two apparatus dead-ends, measured**: a scratch `CLAUDE_CONFIG_DIR` cannot
  authenticate (the keychain credential is keyed to the config dir; seeding the
  account keys from `~/.claude.json` does not help), and running under the
  default config would have loaded this workspace's own SessionStart hooks into
  the agent — `--safe-mode` disables every customization while auth works. The
  isolation evidence is the transcript's init event, an artifact: `mcp_servers:
  []`, default output style, built-in agents only. The committed canary proves
  auth and nothing more (its one-word reply was not kept; the next staging
  saves it). One leak, path not identified: the agent answered in Japanese to
  an English prompt — some user-level preference survives safe mode; nothing
  about the finding rides on it.

What this does and does not claim: the loop closed once, on this finding, for
this input set (report + case + declared invariant + repo + bug-blind plumbing
— not "the report alone"), under a soft seal with a declared void condition
that did not fire. v1.0 entry criterion 2 is met by this measurement; the
remaining v0.5 scope (report schema doc, CI quickstart) is untouched by it.

**The first-sight review corrected this entry** (a fresh-context proxy — Codex
was out of credits). The one finding that mattered: "tools limited to" was
false — `--allowedTools` is an allowlist, not a menu, and the transcript's init
event shows the full tool set presented, web tools included — and the audit
that should have caught a web call only examined Bash commands. The reviewer
proved the fail-open with a synthetic transcript (WebFetch, WebSearch, a Task
delegation, a home-dir bind mount: `audit: clean`), and proved the real run
clean by independent means (server-side web counters 0/0, every one of the 74
calls on the six allowed tools). The audit now judges every call, per escape
channel: network/delegation tools void by name, Bash text by the network
markers, any tool input by the repo and user-config paths, docker by absolute
mount sources outside the stage — while variable mount sources ("$PWD") are
recorded as unresolved rather than voided, because a transcript holds shell
text, not resolved paths, and the real clean run mounts "$PWD:$PWD" from inside
the stage. An empty transcript is now unauditable, not clean. Seen red on the
synthetic transcript and green (verdict unchanged, 74 calls) on the real one.
The negative control now also pins the reproduced crash point to the case's k
(crash_point 19 == case_k: green; mutated k: red) — a checker broken for an
unrelated reason no longer opens the agent gate. The recorded run's artifacts
in `spike/runs/sideeye-loop-1/` are NOT rewritten: `audit.json` there is the
pre-review auditor's output (old field names), kept as the record of what
judged the run at the time; the rewritten auditor applied to the same
transcript returns the same verdict — clean, 74 calls — measured independently
twice (this session and the R2 reviewer). Smaller corrections riding the
same round: the stale scratch-config-dir sentence in the protocol paragraph,
the canary's quoted evidence (no artifact existed — the isolation evidence is
the init event; the canary now saves its reply), the full clone printing
`issue/772-undo-command-documentation` under `git branch -a`, "25/25 crash
worlds" (24 crash + 1 baseline), the unexplained AtomicFileTest skips, and the
host-/tmp scratch logs the prompt's letter forbade. Apparatus work that needs a
fresh staging to verify honestly — shallow-fetch stage (#62), a canary that
probes the seal red (#63), a committed generator for the secondary
observations (#64) — is filed as issues rather than silently absorbed.

A cleanup pass after the review tightened three things (each seen red against
the recorded artifacts, none touching a judgement): the define's operation is
written once and rides `protocol.json` to the functional gate instead of a
second hand-written copy; the seal now pins the exact expected inventory, not
its size (a one-in-one-out swap passed the count check and fails the list
check); and the judge's usage text is derived from the header structurally
instead of a line-number constant. The class it declined to fix in this PR —
the declared invariant existing as three byte-identical copies across the
dogfood scripts and this experiment, and the leg-C predicate implemented twice
— is #65, because the fix direction runs through shipped measurement scripts
this plan pledged not to touch.

## 2026-08-12 — v0.4.0: the milestone is the measurements; the tag carries a passenger

Version 0.3.0 → 0.4.0, both hand-written strings at once (the unit test holds the
manifest and the CLI banner together — that is why the bump cannot be forgotten in
one place). What the release claims is the v0.4 milestone: §17 evaluated honestly
across omamori's full surface (the enumeration entry above) and regression-case
stability measured across the real timewarrior fix (the four-legs entry). What the
tag *carries* besides that claim is the MCP adapter and its post-merge fixes — v0.5's
surface landed on main before v0.4 was cut, and a tag cannot pick its passengers, so
the CHANGELOG and PRD both say so rather than letting the numbering imply v0.5
happened. The 0.5.0 tag waits for the loop-closure test, which is v0.5's own
acceptance. Repaired in passing, because the release links now exist to be checked:
the CHANGELOG's bottom link references had never gained `[0.3.0]` — the release that
introduced the section forgot the pointer to itself.

## 2026-08-12 — Every omamori surface, counted twice: the enumeration closes, three probes hit the same named wall

PRD v0.4's status has carried an honest parenthesis since this morning — "other
state-changing surfaces beyond `exec` were not enumerated exhaustively". Closed now,
by counting from two directions and requiring the counts to meet.

**From the command side** — every dispatch arm in `run()`, nested subcommands
included, plus the two non-command entrypoints: test, exec, install, uninstall, init
(plain and `--force`), config list/validate/add/disable/enable, override
disable/enable, audit verify/show/key-rotate/hash-cwd/unknown, break-glass
activate/`--status`/`--clear`, doctor (and its fix arms), setup, explain, report,
status (and `--refresh`), cursor-hook, hook-check, version/help — and the argv0 shim
mode plus the shim-routed hook-check.

**From the write side** — a sweep for write primitives (fs::write / OpenOptions /
rename / remove_file / create_dir / atomic_write / set_permissions / append) over the
non-test sources hits 12 files, and every hit maps to a command above: quarantine
moves (actions.rs ← exec/shim), the audit-chain append and the hwm
temp-create_new-rename (audit/mod.rs ← the whole append family), the retention prune
(below), key rotation (audit/secret.rs ← guarded), the warn-throttle and hook-verify
markers (← shim/hook), installer writes and the integrity baseline (← install,
doctor's fix arms, status `--refresh`), config writes (← the guarded config family),
break-glass state (← activate / guarded clear) and its denial-path audit append, the
shell-profile append (← setup), and doctor's transient writability probe. The
util.rs / context.rs hits are `#[cfg(test)]` code.

**Classification.** Read-only: test, explain, report, audit show/hash-cwd/unknown,
config list/validate, break-glass `--status`, version/help. Guarded — and the guard
refuses a human at a terminal exactly as it refuses an agent (#12), so driving one
would remove the defence under test: uninstall, init `--force`, config
add/disable/enable, override, audit key rotate, break-glass `--clear`. One asymmetry
worth naming: break-glass activation's *denial* path appends an audit event with no
guard in the way — but it exits non-zero, which is #3's wall, so it is recorded
rather than driven. Unguarded writers: **install, setup, plain init, and audit
verify** (plain init because creating a config where none exists is deliberately not
"modification"; audit verify because a missing or unusable high-water mark makes it
re-create the mark — a bootstrap write the first draft of this enumeration missed,
caught in review: the write site was mapped to "the append family" by file, and the
same `write_hwm` serves a second caller. Mapping files to commands is not mapping
call graphs to commands).

**The probes** (`spike/dogfood-omamori-surface.sh`: container, L0 + strace oracle,
disposable HOME inside the state directory, each expected outcome pinned):

- **install** and **setup**: UNKNOWN `unsupported_syscall_observed` — `symlinkat`.
  The installer creates the PATH shims as symlinks, which is outside the trace
  contract; the oracle sees an operation the shim cannot record and the account
  refuses (the #39/#5 wall family, named).
- **init**: the same refusal one step earlier, on `fchmodat` (the config directory
  and file permissions).
- **audit verify**: **PASS — 6 crash points, 7 worlds explored, 0 violations.** The
  bootstrap re-write of the mark is a single atomic publish (temp, `create_new`,
  rename), and every crash world keeps a database that is pre or post, never torn.
  This is the first omamori surface sideeye has fully explored to a verdict rather
  than met at a wall — a real §17-side data point, and it holds.

The probes' first version measured something else entirely, and the correction is
the part worth keeping: every probe initially answered `child_process_detected`
("the target replaced its own image") — which was about to be documented as
omamori's structure, until the pinned PASS prediction for audit verify failed and
forced a second look. The image being replaced was the harness's own: the operation
was wrapped in a shell script whose `exec "$OMAMORI"` is exactly an execve inside
the recorded process. The wrapper is gone (HOME/SHELL reach the child by inheritance,
the same wiring the timewarrior recipe uses for TIMEWARRIORDB), and the outcomes
above are the target's, not the recipe's. A measurement harness lies quietly; a
pinned expectation is what made this one speak up. One recipe detail that survives:
setup's own safety guard refuses a cargo build artifact as the hook source, so the
probe passes `--source` explicitly — without it the recording run exits non-zero
before hooks are touched, which is that install-time defence doing its job (measured
both ways).

**The one non-atomic write the sweep surfaced — recorded, not driven.**
`audit/retention.rs`'s `try_prune` rewrites the audit log **in place** (seek(0),
write_all, set_len, flush; no temp file, no fsync), and it sits on the append path,
firing every PRUNE_CHECK_INTERVAL appends once retention is configured. Everything
else in omamori goes through `atomic_file`; this is the exception. A crash inside
that rewrite leaves a mixed old/new log, which `verify_chain` would read as
tampering-shaped corruption — a false alarm on an honest log. Driving it under
sideeye needs entries older than the retention cutoff, and entries are hash-chained
with real timestamps, so it takes clock control this measurement does not have.
Recorded as the enumeration's one open finding, for the author to take to the
omamori side.

## 2026-08-12 — The saved case works across the real fix: replay-across-fix, four legs, measured

PRD v0.4's second scope item — regression-case stability *in practice* — had never
actually been exercised: the replay context gates were pinned by synthetic changes
(v0.3 acceptance), and the timewarrior fix was verified by a full re-explore, never by
replaying the saved case across the patch. `spike/dogfood-timew-replay.sh` closes that,
in the container, one saved case through four legs:

- **A** — timewarrior built at the pinned upstream HEAD `db7751cb` (still upstream HEAD
  at run time; `git ls-remote` returned the same hash), explored with the undo-contract
  checker: FAIL at crash point 19 of 24, case saved.
- **B** — replay against the same build: FAIL, "the case reproduced".
- **C** — `spike/timew-undo-ordering.patch` applied in a SEPARATE checkout, rebuilt,
  installed over the same PATH name, same case replayed: **PASS, explored 2, no
  unknown_reason, crash_points still 24.** The paths-only-warn rule (ADR 0009) did
  exactly what it was written for: the fix reorders same-class renames, the class
  prefix hash held, and the case stayed addressable across the real code change.
- **D** — negative control: the distro 1.4.3 package at the same PATH name: UNKNOWN
  `case_no_longer_applies`, exit 2. A recording with a different operation count gets
  a refusal, never a verdict.

The four legs demand three different outcomes from one code path (FAIL / FAIL / PASS /
refuse), so no constant-answer replay satisfies them — that mutual contrast is the red
for these checks. Leg C's PASS rests on the checker's contract as written (the
non-destruction form: undo must not remove an older committed interval; removing
nothing is allowed, because a crash may have beaten the intent's commit). That form
deliberately admits a hypothetical "undo that always no-ops" — sound for measuring the
crash windows, but it means leg C alone does not prove the fix *restores* undo, only
that the counterexample stops reproducing. The fix's positive behaviour is what leg
A's FAIL-then-PASS pair and the 25/25 patch measurement (this morning's entry) carry;
this script measures case portability across the change, not undo's full semantics. Wiring facts the recipe depends on, learned while writing it: the
case stores the operation as the PATH name `timew`, so a directory at the head of PATH
is the lever that swaps builds; TIMEWARRIORDB is not part of the case's identity (env
is not captured) and the recipe must re-export it; the setup is additive, so the state
directory is MOVED aside between legs, never deleted. For the record: aarch64
container, g++ 12.2.0, timew 1.10.0-dev vs 1.4.3, patch sha256
`586040127c56bac45a49595573837438e61e852583bb987e5814cfa32912ec96`. One environment
wall worth writing down: the corporate network intercepts TLS (Netskope), so the
container has to trust that CA before the clone can run — the measurement's integrity
does not rest on the transport, because the pin is the full 40-hex commit hash and the
recipe enforces it with `git rev-parse HEAD` after checkout (an abbreviated hash would
be a lookup convenience, not a content address — review caught the first version using
one while making this exact claim).

What this clears and what it does not: v0.4's regression-stability scope item is now
measured, not argued. It does **not** make the counterexample CI-resident (the case
still needs a built timewarrior), so v1.0 entry criterion 1's "kept as a replayed
regression case" stays open — the same two §17 gaps as this morning, with the replay
half now demonstrated.

## 2026-08-12 — The MCP green was partly vacuous: a reused work dir served a stale verdict

A post-merge adversarial re-review of PR #55 (its own PR, re-read cold) found the worst
defect a truth-telling tool can have: the wrong answer delivered confidently. Two
`sideeye mcp` processes sharing `SIDEEYE_MCP_WORK` collide on `report-N.json` /
`child-N.out` — the artifact counter is per-process — so the second server's `O_EXCL`
capture aborts its child at 126, and the parent then reads the *previous* server's
report back as *this* call's verdict, `isError:false`. Measured twice: natively (run 2
answered while neither work-dir file was rewritten — mtimes identical to the
nanosecond) and in the container (a call for `env.toml` answered with toy-bug's FAIL
report, a stale verdict about a different target).

Worse, the acceptance suite itself reused `/tmp/mcp-work` across checks, so its own
green was carrying two checks that could not look — a correction to the entry below,
which claims "env isolation, canonical self-exec" among the green: check 4's child
never ran (its "file absent → ok" soft branch is exactly what fired) and check 5's
"real report proves self-exec" assert was satisfied by check 1's leftover file. The
suite also ran in no CI job at all.

Fixes, each seen red first against the pre-fix binary: stale artifact names are
unlinked before the child runs (whatever exists there afterwards was written by this
call's child or by nobody — the work dir is operator-owned by ADR 0010's precondition),
the fork stub's own exits (126 capture / 127 exec) become tool errors instead of a
report read, check 4 fails when the env file is absent, and a new check 6 pins the
cross-server reuse case (server A explores toy-bug → FAIL; server B, same work dir,
explores toy-fixed and must answer PASS — the pre-fix binary answers A's stale FAIL).
The suite now runs in CI.

Same review, same class — the check and the code sharing an assumption: `isError` was
decided by substring-matching six `unknown_reason` strings, while the acceptance
asserts `isError ⟺ verdict ∉ {PASS, FAIL}`; the two agreed only on the one path the
suite exercised. `UnknownReason` has ~20 values, and the first from outside the list to
show up live (`no_shim_marker`, a macOS hardened binary) returned `isError:false` —
which an agent reads as a settled verdict. Replaced with the structural property (the
report's `verdict` field), fail-closed for unparseable reports, unit test seen killing
a mutation. And the spec half, verified against schema.ts raw rather than any summary:
`DiscoverResult` and `ListToolsResult` both extend `CacheableResult`, whose `ttlMs` and
`cacheScope` are *required* — both responses omitted them (and discover omitted
`resultType`), so a schema-validating client would have rejected the handshake before
anything worked. Smaller tightenings while in there: the `jsonrpc` tag is validated,
`clientCapabilities` must be an object, a transport write failure exits instead of
leaving a half line on fd 1, and `sideeye mcp` refuses extra argv.

## 2026-08-12 — `sideeye mcp`: a stateless MCP server, over paths not commands (ADR 0010, v0.5)

The agent-facing surface DESIGN §3 promised, and the first half of §17's second
criterion. `sideeye mcp` is a single-binary subcommand — a stateless loop over
`server/discover` / `tools/list` / `tools/call` (MCP 2026-07-28 dropped the
`initialize` handshake and exempts stdio from OAuth, which made a hand-written Zig
server small and killed the case for an SDK wrapper).

The plan's adversarial review (three Criticals) reshaped it before a line was written,
and building it caught two more failures that only a real run surfaces:

- **Design (review):** raw `operation`/`shim` as tool input is confused-deputy RCE, so
  the tools take *paths* (`config_path`/`case_path`), confined inside
  `SIDEEYE_MCP_ROOT`; the operation lives in the config, a human-inspectable file. The
  child is self-exec'd through the canonical binary (`/proc/self/exe`, not argv[0] —
  PATH hijack), with its stdout captured to a file (fd 1 stays the pure MCP transport)
  and a minimal environment (execve, PATH only — the server's credentials do not reach
  a config's operation). Acceptance pins all three: a PATH-planted fake `sideeye` is
  ignored, a secret env var does not reach the child, a path outside the root is
  refused before any exec.
- **Build (measured):** the PoC's first real `explore` call returned no response.
  Cause: the report is pretty-printed (newlines), and embedding it raw in
  `structuredContent` split the single-line JSON-RPC frame — the transport invariant
  the PoC exists to prove, broken by my own serializer. Fix: minify the report before
  embedding. Then a second real-run bug: the stdin loop dropped a final message not
  terminated by a newline (many writers omit the trailing `\n`), so a single unframed
  request produced silence. Fix: flush the buffer at EOF. Both are the class that
  passes unit tests and dies on first contact — which is why the plan raised the PoC's
  bar to "a real explore, self-exec'd, with fd 1 uncontaminated".

Measured end-to-end (Linux container): MCP `explore` with an oracle returns FAIL and
saves a case under the server root; MCP `replay` of that case reproduces the FAIL —
the loop-closes surface (§17 second criterion) works over the wire. Full MCP
acceptance green (transport framing, `_meta` validation on every method, version
negotiation, path confinement, env isolation, canonical self-exec). isError separates
a real verdict (PASS/FAIL) from an actionable one (SETUP ERROR / retryable UNKNOWN) so
the model can self-correct. Cancellation of a long explore is deferred (the sync loop
blocks; **parent-death cleanup of the self-exec'd group is not implemented** — a server
killed mid-explore can leave the target group behind, tracked honestly as a limitation,
not claimed as done) — the Tasks extension is future work.

Review R1 (Codex) then caught what the design draft got wrong about the *spec itself*,
which is the part I had read only in summary: `_meta` lives under `params`, not at the
top level, and `server/discover` returns `supportedVersions` + `capabilities`, not a
bare `supported` — as written, the server would have refused every spec-compliant
client (P0×2, fixed against schema.ts). And it found real hardening gaps: the child
still inherited fd 0/2 (a config's operation could read the MCP transport) and other
fds — now stdin→/dev/null, stderr→capture, higher fds closed, capture opened
`O_NOFOLLOW|O_EXCL` in a 0700 work dir; the report read is capped (4 MiB) and an
oversized stdin line is drained rather than mis-parsed. One review point (a
copy-into-work-dir TOCTOU defence) was tried and reverted: it breaks a config's own
relative resolution, and the residual window needs an attacker-writable root, which
SIDEEYE_MCP_ROOT is not by contract — stated in ADR 0010 rather than papered over with
a fix that breaks the common case.

## 2026-08-12 — §17 substantially met on the calibration target (two gaps), and why omamori was the wrong place to demand it

A wrong turn corrected first. The plan had "omamori §17 evaluation, human-driven at a
raw terminal" as remaining work. That is not real work — it cannot be done. omamori's
guard on config-modify / `init --force` / key rotate (#12) fires for a human at a
terminal exactly as it does for an agent; the guard is not a session check, it is
omamori refusing to modify its own defence, whoever asks. Making one of those a
Sideeye `operation` means the operation exits non-zero when not killed, which Sideeye
refuses to explore. Break-glass would "work" and would mean disabling the defence to
measure the defended operation's crash-consistency — self-defeating, and against the
discipline. So omamori's guarded surface is not evaluable by this tool at all, and the
plan item was struck.

That reframes what "§17 on omamori" could ever have been. The state mutation this
session actually drove is `exec`'s audit append, and yesterday's recon showed it
crash-safe by construction; the guarded self-modification commands are walled off by
design, and other state-changing surfaces beyond `exec` were not enumerated
exhaustively. Zero findings on the path we drove is exactly what §18 calls survivable
— and now with a mechanism, not a shrug.

Where §17 is *substantially but not fully* met is the calibration target §18 required
all along: timewarrior, a stateful CLI with no hand-written adversarial tests. Scored
honestly rather than generously, four conditions hold and two have real gaps — not
cosmetic qualifications — and the DESIGN/PRD text now says so instead of leading with
"met". **Reproducible / small / judged real by this project's author / stops-after-fix**:
clean (reproduce line + `cp`; one op, two-file window; filed as timewarrior#778, not
yet maintainer-confirmed; PASS 25/25 on the patch). **"Discovered automatically" —
partial**: this is the honest one. A human read the plain strace, confirmed by hand
with `cp` file surgery that `undo` destroys committed data, and *then* wrote the
checker; Sideeye automated the crash-world search, not the hypothesis (§4.1). Writing
this as "met" would have been the over-claim the first draft made and review caught.
**"Kept as a regression" — a recipe, not a replayed case**: the recipe and patch are
in the repo and reproduce it, but it needs a built timewarrior, so it is not a
CI-resident `sideeye replay` case — which means v1.0 entry criterion 1 is not yet
satisfied by it either.

§18's calibration test — does "no findings" mean the tool is weak or the target strong
— resolves to strong-target: hardened where we can drive omamori, a real find on the
deliberately-average target. That clears the calibration *kill* condition and lets the
project continue; it is not the same as clearing the v1.0 entry criterion, and the two
gaps above are what stand between them.

## 2026-08-12 — Why omamori's audit survives every crash window: hwm is confirmed *after* the body

Reconnaissance for v0.4, done the timewarrior way: read the write pattern with plain
strace before pointing sideeye at it, looking for a window before hunting a bug. The
question is whether omamori's `exec` audit append has a multi-file window like the one
that broke timewarrior this morning. It does not, and the reason is the exact inverse
of timewarrior's bug.

Measured (omamori 1.0.2 Linux, one `exec -- /bin/true`, isolated HOME): the audit
record is written to `audit.jsonl` first — 134 one-byte writes, no O_APPEND, no fsync
on the body — and only *then* is `audit.jsonl.hwm` (a high-water mark, contents "3"
for the third entry) advanced through the durable temp+fsync+rename+dir-fsync dance.
Body at trace lines 102–235, hwm confirmation at 245–249: the confirmation strictly
follows the content it confirms.

That ordering is what makes every crash window safe, and it is precisely the ordering
timewarrior got backwards. timewarrior renamed its journal (its hwm equivalent) *before*
the data, and `undo` trusted the journal — so a crash between the two renames left the
journal ahead of the data and undo destroyed committed work. omamori confirms after, so
whatever the crash leaves, verify stays conservative:

- body torn, hwm at the old value → verify trusts up to the hwm and drops the torn tail
- body complete, hwm still old → the last entry is treated as unconfirmed and dropped
  (data lost, but never inconsistent — the conservative direction)
- body complete, hwm advanced → all confirmed

This is why the run has been PASS 143/143 since #25 and stays there through contract
v5/v6/v7. **On the `exec` operation, no §17-class window exists — not for want of
looking, but by construction.** It is a clean instance of DESIGN §18's kill criterion 4
(the target may be too hardened to yield a novel bug): the same discipline sideeye
exists to check, applied correctly by the target.

The §17 primary criterion is not thereby closed. `exec` is the one state-mutating
omamori subcommand an agent can invoke (#12: config-modify / init --force / key rotate
are all guarded, and the guard is intended); pointing sideeye at those needs a human at
a raw terminal. What this session *can* conclude is the "written analysis of why none
was found" that v0.4's acceptance explicitly allows for — for the append path, and with
the mechanism named. And it strengthens the standing note that timewarrior — a
calibration target with no hand-written adversarial tests (DESIGN §18, PRD v0.5) — is
the live §17-class find, now with a mechanical contrast to omamori: confirm-after-body
holds, confirm-before-body breaks.

## 2026-08-12 — v0.3.0 ships

Version bump to 0.3.0 in both hand-written places (the drift test held them
together, as designed), `[Unreleased]` confirmed into `[0.3.0]`, tag and GitHub
Release (`v0.3.0 — The full Define contract`) to follow on the merge commit. No
workflow fires on tags here and nothing publishes to an external registry; the
release is the record.

## 2026-08-12 — v0.3 closes: the worked example runs from the toml, and the budget holds on a fresh target

Fifth and last PR of the plan. Two acceptance runs carry the milestone's claims.
The DESIGN §12 worked example — doctor cross-examined against reality — now runs end
to end with the define coming entirely from a `sideeye.toml` (check 2aa: FAIL, the
checker falsified first, the case saved). Seen red by synthetic input: the same check
aimed at the fixed toy exits 0 and the check demands 1.

The define budget (PRD kill criteria 3) got its measurement on a fresh target.
Watson (td-watson, a Python time tracker sideeye had never touched) is driven by
`spike/dogfood-watson/sideeye.toml`, one checker script and one environment variable
(`WATSON_DIR`) — and is refused honestly: every frame carries a fresh uuid4 and an
updated-at stamp, so the operation is not byte-reproducible and the un-crashed
baseline cannot match the recorded final (`baseline_violates_invariant`, the class
the first omamori run surfaced). The falsification probe fired loudly on the way in
("Invalid JSON file … frames"), which is watson's own reader earning the checker
seat. A refusal that names the right reason is the budget working, not failing — the
define fit the file, and nothing needed a recipe script's worth of glue.

PRD's v0.3 section flips to delivered with one deliberate narrowing recorded:
shrinking means the earliest failing crash point; "simplest" and measured
reproducibility counts stay future work and the report claims neither.

## 2026-08-12 — Replay: the same pipeline, one world, and a case that knows when it no longer applies (ADR 0009)

Fourth PR of v0.3, the last functional piece. A FAIL now saves its counterexample —
schema/versions, the resolved define, k, and a landing context of three parts: the
operation count, an FNV-1a hash over the class sequence 1..k, and the classes+paths
adjacent to k. `sideeye replay <case.json>` is `explore` with the kill set restricted
to {k, baseline}; the restriction is a `continue` in the world loop and nothing else,
so the oracle comparison, structural detectors, checker falsification, landing
evidence and quiescence all run — the acceptance pins that with a case whose stored
checker is `/bin/true`, which must die at falsification inside the replay exactly as
it would in an explore.

The plan's two review Criticals shaped the context design: adjacent-only matching is
aliased by one same-class insertion earlier in the sequence (every later index shifts
by one), so the prefix hash gates; and paths only warn, because pid-embedded temp
names differ between runs while naming the same operation — and because a fix that
*reorders* same-class operations (the timewarrior patch, measured this morning) keeps
classes while moving paths, which is precisely the replay-after-fix this exists for.
A case from a different trace contract refuses outright: v4 and v5 both changed what
`SIDEEYE_KILL_AT` counts, and a hash cannot vouch for a counting rule it was not
computed under. The context check sits before the zero-crash-points early PASS, so a
case whose operations all vanished cannot be answered with a green.

Measured: toy-bug's FAIL saves `cases/000001.json` and prints the replay line;
replaying unchanged reproduces (FAIL, "the case reproduced"); `TOY_EXTRA_FIRST=1` —
one extra write at the head of the sequence — answers `case_no_longer_applies` with
no verdict; the gated-checker case refuses `checker_not_falsified` inside the replay.

## 2026-08-12 — L1: the program is held to its own words, across the whole post snapshot (ADR 0008)

Third PR of v0.3. A success marker (`marker` in the toml, `--marker` as a flag) makes
the post-success invariant real: in worlds where the marker's bytes reached stdout
before the kill, the *new* state must survive — shared files on post content, history
files longer than their pre, created files present, deleted files gone (`not_durable`).
Judging the whole post snapshot is the point: the plan's own adversarial review
(Critical 1) caught that a strengthened L0 over shared files would miss a created file
vanishing — exactly what a success claim covers.

Two honesty edges did the design work. **"Not applicable" and "not observable" are
different absences**: a crash world killed before the marker is the normal shape of a
conditional invariant (L0 and the checker judged it anyway), but a marker the clean
recording run cannot produce refuses as `marker_never_observed` — a misspelled marker
must not make every L1 obligation silently vacuous behind a PASS. **The plan was wrong
about one case and the measurement fixed it**: the no-flush variant was slated to be
`marker_never_observed`, but a recording run completes normally, so libc's exit-time
flush delivers even an unflushed buffer to the capture — the honest verdict is a PASS
with `marker observed in 0 of N crash worlds`, and that is what ships (the buffer dies
with the process in every killed world, which is true of the real program too).

Mechanics: every operation run — recording, worlds, baseline — writes stdout to the
work directory through the same redirection (`runChildCapture`), so an isatty branch
cannot make the recording describe a different execution than the worlds; stdout
writes consume no crash-point address, so addressing is untouched. A rolling-window
`fileContains` scans the capture without holding a chatty target's output in memory
(the boundary-straddling marker is pinned by a unit test). The toy grew four L1
shapes; measured: the correct shape passes with the marker observed in 4 of 8 crash
worlds (the anti-vacuity bounds hold on both sides), claim-before-commit and
claim-before-create both FAIL as `not_durable`, and the misconfigured marker refuses.
Target stdout no longer leaks into the engine's console — the dogfood noise is gone.

## 2026-08-12 — sideeye.toml: the parser's width is the contract's width (ADR 0007)

Second PR of v0.3. The define surface gets its file form: `[world] state`,
`[define] setup / operation / check`, parsed by a hand-written strict subset
(~100 lines, `src/config.zig`) that refuses everything else with the offending line
named — unknown sections, unknown keys, bare values, duplicates, empty values,
escape sequences, trailing junk. The refusals are the design: a full TOML dependency
would accept arrays and dotted keys whether the contract wants them or not, and an
ignored key is a declared invariant that silently never fires, which is this tool's
worst shape wearing config clothes.

Three decisions worth their ink. **Keys exist only once they are enforced** —
`marker` is deliberately not in the schema until the PR that makes L1 judge
something; today it refuses as an unknown key, and the acceptance suite pins exactly
that, so the L1 PR will have to flip a red check rather than un-forget a parser.
**The file owns the define surface only** — `--shim`/`--oracle`/`--work`/`--json`/
`--allow-unverified` stay flags and combine with `--config`; the define-surface
flags are mutually exclusive with it, because a precedence merge would make the file
unreadable on its own (which line is in effect becomes invisible). **Relative paths
resolve against the toml's directory**, and command argv[0] resolves only when it
names a place (`./check.sh`), never a program (`mytool` stays a PATH lookup) — the
same file has to mean the same thing from anywhere, or a replayed define points at a
different state.

Measured: red first (the pre-change binary answers `--config` with "unknown
option"), then the DESIGN §12 example parses inline comments and all, a toml-driven
toy-fixed run reaches the byte-identical PASS verdict line the flags reach, and the
three refusal classes name their lines. Full acceptance green.

## 2026-08-12 — v0.3 begins: a refusal names the operation it refused on (#41)

First PR of the v0.3 plan. The account comparison already computed the divergence
index (`oracle.compare` returns it); everything after that index was thrown away on
the way to a one-line refusal, and the reader — twice now a whole dogfood session —
had to decode `trace-record.bin` with a copy of the acceptance suite's struct reader
and grep `oracle.txt` to learn which operation split the accounts. Now the oracle's
`parse` keeps the raw strace line behind each class entry (index-aligned), the shim
side keeps its records alongside the filtered class list, and both refusals
(`oracle_missed_operation`, `oracle_saw_phantom`) say: the 1-based divergence index,
the raw line the oracle holds there, and what the shim's account holds at the same
position — or that either account simply ends. The detail travels through the
existing `message` plumbing, so text and JSON carry it identically (DESIGN §13) with
no schema change and no trace-contract change (v7 stays).

One deliberate asymmetry: on allocation failure the naming is dropped and the bare
lead sentence survives — the refusal is the point, the naming is the courtesy, and
the courtesy must never cost the refusal.

Measured on toy-mixed (the mixed-visibility target): red first on the pre-change
binary (generic message in both forms), then
`divergence at operation 3: the oracle saw: openat(… "/tmp/acc/state/key.json",
O_WRONLY|O_CREAT|O_TRUNC …); the shim's account ends after 2 operation(s)` in text
and JSON alike. The timewarrior wall would have named its four ENOENT unlinkats on
the first run. Full acceptance green; the parse test now pins line/class alignment.

## 2026-08-12 — The fix experiment closes: reorder the renames, tolerate the unlanded intent, and the counterexample stops reproducing

The author's verdicts on the morning's finding, recorded before the experiment they
triggered: the timewarrior counterexample is judged a real bug (an undo that reports
success while deleting an interval committed the day before is genuinely incorrect
failure semantics), and §17 keeps omamori as its subject — this finding is recorded as
proof of the class, and the primary criterion is evaluated for real at the v0.4
dogfood, not retrofitted onto a different target. Upstream reporting waits until the
fix leg is measured, which is this entry.

Upstream HEAD reproduces it. timewarrior 1.10.0-dev (db7751cb), built from source in
the container: FAIL 2 of 25 worlds, earliest at crash point 19 of 24 — the same
window, after the month-data rename and before the undo rename. HEAD's `finalize_all`
wraps the rename loop in `sigprocmask` (PR #316, "Mask signals while updating
database"), which is evidence upstream knows this window must be atomic — and measures
as no defence here, because SIGKILL cannot be masked. Neither can OOM or power loss.

The checker's contract had to be refined first, and the refinement is a reversal worth
recording: the first checker demanded that undo always remove the newest *visible*
interval, but a correct recovery may find that the newest intent never landed (the
crash beat its data-file rename) and discard the intent without touching visible data
— the strict form would condemn that correct behaviour along with the bug. The
non-destruction form — undo runs, adds nothing, removes either nothing or exactly the
interval timew's own export names most recent — still fails the unpatched build 2/25
(both faces named: alpha deleted at point 19, the decrement abort at point 20), so the
red is preserved, and it passes a correct recovery.

The patch (kept as `spike/timew-undo-ordering.patch`, three small changes): finalize
in reverse registration order, so the undo journal reaches its final name before the
data files it describes — a crash may now leave the journal *ahead* of the data, never
behind; `Database::deleteInterval` deletes from the datafile before decrementing tag
counts, so the not-found check runs before anything mutates; `undoIntervalAction`
treats "failed to find" as the change never having landed — popping the intent is the
whole undo. Measured on the patched build: PASS 25/25 in both explorations (the same
counterexample stops reproducing), and upstream's own suite holds — 37 bash behaviour
tests, AtomicFileTest 24, data.t 96, Datafile.t 2, TagInfoDatabase.t 8, all green.

Known-issue check before any report, as directed: #772 (open, 2026-08-03) is the
nearest neighbour and a different mechanism — a missing fsync lets an unclean
*shutdown* zero-fill undo.data (content durability, power loss, filesystem-dependent);
this finding is rename *ordering* under process crash (filesystem-independent, and
untouched by adding fsync). #182 wants a consistency doctor and names mismatched tag
counts as a symptom without the crash-window cause; #480/#292 are disk-full and an old
truncation. Nothing covers the ordering mechanism or undo aiming at the wrong
transaction. The maintainer engaged constructively with #772's explicitly AI-generated
analysis five days after filing.

Reported upstream as GothenburgBitFactory/timewarrior#778, in the shape the author
directed: what was found, the two `cp`-only reproductions, the risk, and a request to
confirm — no fix proposal in the opening post; the tested patch stays here until the
maintainer engages.

## 2026-08-12 — A fifth target picked by reading commit tails: timewarrior's undo desyncs from its data across a crash

Four targets in, §17 is still open, so the fifth is chosen for bug likelihood rather
than coverage: strace the candidates' write patterns bare, before sideeye enters the
picture, and only aim at a commit shape that actually has a window. Two candidates,
one survivor:

- **jrnl 4.6 (Python): rejected.** Guessed to rewrite its journal in place; measured
  otherwise — whole journal into a random-named temp (`O_EXCL`), one write, rename.
  No fsync anywhere, which is invisible under a process-crash model. Predicted PASS,
  so not a §17 candidate.
- **timewarrior 1.4.3 (C++): selected.** One `timew track` rewrites three files —
  month data, `undo.data`, `tags.data` — each atomically via pid-named temp + rename,
  but the three renames run in sequence at the very tail: data, undo, tags. Every
  crash between them leaves files that are individually pre-or-post (L0 passes by
  construction) and mutually inconsistent.

The window that matters was then measured by hand, with file surgery and no sideeye:
restore the state to "month data has the new interval, undo.data still ends at the
previous transaction" and run `timew undo`. It deletes the OLD interval — committed
long before the crash — and keeps the one whose commit crashed. The documented
contract is "The undo command will undo the most recent change"; after this crash it
destroys data it was never asked to touch. The other window is stale `tags.data`, and
it is deliberately not part of the checker: `timew tags` recomputes from the interval
database (measured — hand-staling `tags.data` changed nothing), so that staleness has
no reader to lie to.

The checker (`spike/dogfood-timew.sh`) states the undo contract and nothing else:
undo must remove exactly the interval timew's own export names as most recent. Two
measured facts make it workable: `timew export` dies loudly on garbage (exit 255,
"Unrecognizable line …"), so falsification passes with no strict wrapper — the
opposite of todoman's `todo list`; and the engine snapshots the crashed state before
the checker runs, so a checker that mutates state (undo rewrites the database) cannot
contaminate the L0 judgement (main.zig takes the snapshot at the top of the world
loop, judges that snapshot after the checker).

For the record, since §17 asks what was discovered *automatically*: the window was
first spotted by reading a plain strace and confirmed by hand; sideeye's part is to
find it blind from the declared contract and hand back a minimal reproducible
counterexample. The claim under test is "point the declared invariant at the tool and
the exploration lands on the bug", not "nobody looked at a trace first".

The first run refused — and surfaced a sixth-through-tenth cousin of #30. Both
explorations came back `oracle_missed_operation`: timewarrior's AtomicFile cleanup
removes every registered temp name at exit through `remove(3)` — including
`timewarrior.cfg.<pid>-1.tmp`, which this run never created — and libc implements
remove as unlink-then-rmdir *internally*, behind the PLT. Four failed unlinkat
attempts (all ENOENT, the renames had already consumed the temps) were visible to
strace and invisible to the shim. The account conventions are symmetric on purpose —
the shim records before the call, outcome-blind, and `syscallSucceeded` in the oracle
only gates cwd tracking — so the honest fix is to interpose remove and reimplement
its documented two-step through the shim's own unlink/rmdir wrappers: every attempt
recorded pre-call, matching strace attempt for attempt, EISDIR probe included (glibc
falls through on EISDIR; Apple's BSD libc on EPERM — each platform's wart kept). On
macOS this is not ergonomics but soundness: there is no oracle there, and a
mixed-visibility target (some ops seen, removals not) keeps `mutation_count != 0`, so
`state_changed_without_ops` stays silent — the same mixed-case PASS hole R1 closed
for raw syscalls in v0.1. TOY_REMOVE pins it (check 2w): refused as
`oracle_missed_operation` before the interpose (seen red), PASS 12/12 with the exact
kill sequence — the never-created path's failed attempt an address on both accounts —
after.

The re-run landed where the hand measurement said it would, and one window deeper.
(a) L0 alone: PASS 20/20, oracle agreed on 19 operations — no single file is ever
torn; the bug is not in any file, it is between them. (b) undo contract: **FAIL, 2 of
20 worlds**, earliest at crash point 14 of 19 — after `rename(2020-01.data.tmp)`,
before `rename(undo.data.tmp)` — where `timew undo` prints "Undo", exits 0, and
deletes the alpha interval committed the day before, keeping beta whose commit
crashed. Replayed end-to-end from the reproduce line: kill 137 at point 14, export
shows both intervals, undo, alpha is gone. Crash point 15 (before the tags rename) is
the reversal this file exists to record: the claim two paragraphs up that stale
`tags.data` "has no reader to lie to" was measured against `timew tags` and was wrong
by one command — `timew undo` reads it to decrement the cached counts, errors with
"Trying to decrement non-existent tag 'beta'", exits 255 and undoes nothing. It
undoes nothing *atomically* (both intervals and the txn survive — the good half), but
undo stays unusable until tags.data is repaired by hand. One declared contract, two
distinct failure semantics: an undo that succeeds and removes the wrong thing, and an
undo that cannot run at all. Falsification passed bare — `timew export` on garbage
exits 255 — the opposite of todoman's lenient reader.

## 2026-08-11 — todoman reaches a verdict: a fourth target, and falsification rejects a lenient reader

Re-ran todoman 4.1 (Python) after #34; the calibration sweep had ended in an honest
refusal (`unsupported_syscall_observed: linkat`, filed as #31). The wall is gone. The
operation (`todo new` against a seeded list) confirms its entry the atomicwrites way —
temp created `O_EXCL`, reopened, written (302 bytes), fsynced, link(2)ed to the final
name, temp unlinked, directory fsynced — seven state-directory operations, and the
linkat that used to stop the whole run is now a kill point like any other. PASS 8/8
crash worlds, oracle agreed on 7 operations (6273 syscall lines examined, 38 in scope).
Fourth real target with a full verdict, the first in Python, and the field confirmation
that #34 closed the wall it named. No new bug: atomicwrites holds under every crash
point, so the §17 primary criterion is still open.

The checker leg measured something better. `todo list` as `--check` is rejected by
falsification: with every state file overwritten with junk it prints a traceback —
"Failed to read entry …" — and exits 0, answering "nothing wrong" precisely when it
could not look. Sideeye refuses the checker (`checker_not_falsified`, UNKNOWN) rather
than let eight crash worlds pass vacuously against a reader that skips what it cannot
parse. A wrapper that fails on the skip message restores the contract: falsified before
the run, then PASS 8/8. That is DESIGN §14-13 doing its job against a real target's own
diagnostic — the first real checker the gate has rejected, as opposed to a synthetic
`/bin/true`.

The recipe lives in `spike/dogfood-todoman.sh` now; this session had to reconstruct it
from scratch because the sweep ran it ad hoc. Two environment walls worth keeping: pip
inside the container needs `--trusted-host` for pypi.org and files.pythonhosted.org
(the host network intercepts TLS with a self-signed chain — the same wall rustup hit),
and todoman 4.1 with the current icalendar imports `pytz` at runtime, which neither
package declares. `TODOMAN_CONFIG` must end in `.py`; todoman loads it with importlib.

## 2026-08-11 — The oracle resolves paths instead of scanning lines (#31, in progress)

With stdio observed (#32), git's account stopped splitting on `COMMIT_EDITMSG` and split
one wall later, on `mkdirat(AT_FDCWD</g1/repo>, ".git/objects/cc", …) = 0`: a relative
path with no absolute state-directory spelling anywhere in the line, and a return value
of 0, so no result-fd annotation either. The oracle's `touchesStateDir` scans the whole
line for a `"…"` or `<…>` string starting with the state directory, finds none, and
declares the mkdir out of scope. The shim records it (it resolves against the cwd); the
accounts diverge; the run refuses. Same mechanism as the `linkat` that todoman surfaced
(#31), and the more dangerous direction — the tool's whole premise is *refuse what you
cannot see*, and this silently didn't.

The measurement that shaped the fix: on aarch64 every relative call comes through an
`*at` syscall and strace's `-y` annotates `AT_FDCWD</current/dir>` per line, following
relative `chdir` and `fchdir` both (measured). On x86-64 it does not — glibc 2.36's
`mkdir`/`link`/`unlink`/`rmdir`/`symlink`/`chdir` are generic and issue the legacy
syscalls (confirmed in the source, since qemu-user can't be ptraced to measure it), so
the line is `mkdir("state/sub", …)` with no annotation at all and the cwd has to be
tracked. CI runs on x86-64, which makes CI the measurement: a relative-spelling toy that
must reach the same verdict as its absolute twin can only pass there if the tracking is
right.

Adversarial review of the plan (three Critical, five Major) turned "add relative
resolution" into "replace the scope test". The first Critical is the reason: leaving
`touchesStateDir`'s whole-line scan in place as `scope = old ∨ resolved` re-lets every
hole the typed table was meant to close — a `write(1, "/state/path")` buffer string, a
`symlinkat` whose *link content* names the state dir — because the old scan still says
yes. The typed table is only authoritative if it is the *only* authority: path syscalls
resolve their real path arguments, fd syscalls read only their `<fd>` annotation, and
the whole-line scan survives solely as the conservative net for syscalls in neither
table (a net that only ever routes to `unsupported`, so a false hit refuses rather than
passes). Two more Criticals: two-path operations (`rename`, and the new `link`) had no
scope rule and the shim's `observe` judged only the first path — an `outside → state`
rename is a real mutation the first-path test drops — so "in scope iff either path is
inside" goes into both observers, closing a rename blind spot as a side effect. And
`link`'s record order (`path`=new, `aux`=old) invited a natural-order implementation
that would silently miss `outside → state`; making scope independent of argument order
removed the hazard structurally rather than with a careful comment. Adopted too:
`AT_EMPTY_PATH` refuses, `CLONE_FS` joins the boundary refusals (a child sharing the fs
context can move the subject's cwd), the oracle finally sees `state_alt`, and the ADR
states plainly what hard links cost — restore splits them into independent files, and
inode identity, `nlink` and hardlink topology are outside the model.

**Implemented, and git reached a verdict for the first time.** The mutation pair split
along the architecture line the design predicted: unclassifying `link` reddened the link
checks on aarch64 directly, but *disabling the typed resolver* (forcing `pathSpec` to
miss, so path syscalls fall to the whole-line scan) left every acceptance case green on
aarch64 — because there strace annotates an absolute path on every relative line, and the
scan still finds it. Its four unit tests went red, because the legacy-form half of
"relative paths resolve by annotation and by tracked cwd" has no annotation to lean on —
it is x86-64 in miniature. So the resolver's scoping value is genuinely CI's to prove;
what aarch64 pins locally is the direction the scan got *wrong*, the false positives, and
those are unit-tested (a state path inside a write buffer, a symlink whose content spells
the state dir). One measured surprise: `TOY_RELATIVE` refused at first with
`unsupported: getcwd`, because after the toy chdir'd into the state directory `getcwd`
returned a state-directory string and the conservative net scoped it in — it is a read,
now listed as one.

git commit, pinned dates, no oracle wall left: **the two accounts agree on 33 operations,
34 worlds explore, and the verdict is FAIL — one world, at `COMMIT_EDITMSG`, "holding
neither the old nor the new content".** It is not a git bug. `COMMIT_EDITMSG` is git's
editor scratch file, opened `O_TRUNC` and then written, so a kill in that window leaves
it empty; git rewrites it on the next commit and never reads a torn one. Run again with
`git fsck --connectivity-only` as the L2 checker: the falsification probe rejects a
corrupted object store, and then fsck passes *every* crash world — the report's invariant
stays "built-in atomicity (L0)", never "and the checker". So git's real integrity holds
across all 34 worlds; the loose objects (write-tmp, link-into-place, unlink-tmp), the
refs (lock + rename), the index and the reflogs (history form) are all crash-consistent,
and L0's one complaint is about a file whose atomicity does not matter. That is an L0
precision limitation on scratch files — the thing an ignore-list or an L1 marker is for —
not a defect, and worth filing as its own note rather than dressing up as a find. Every
regression held: taskwarrior PASS 12/12 with its own reader as the checker, omamori PASS
143/143, macOS parity exact (`link` in the same six kill-point addresses for the link
toy, relative and absolute spellings identical). 83 unit tests, 69 acceptance assertions.

## 2026-08-11 — The shim learns stdio, at flush granularity (#30, in progress)

The calibration sweep put a number on the wall: taskwarrior's writes are invisible above
its `fdatasync` (the shim recorded 4 of ~20 in-scope operations), and git — which writes
almost everything through raw syscall wrappers — lost its whole run to the **two** stdio
operations behind `COMMIT_EDITMSG`. Libc-internal calls never cross the PLT, so
interposing `write` says nothing about `fprintf`. One stdio call anywhere is enough to
split the two accounts, and most C programs have at least one.

The design was measured before it was written, and one measurement chose it. glibc's
buffer cannot hold more than its own size, so **the flush of pending data is normally
exactly one `write(2)`** — flushes are the one place where stdio granularity and syscall
granularity coincide. So the shim records `.open` at a write-capable `fopen`, `.write`
at `fflush`/`fclose` **when and only when the stream has pending bytes** (recording an
empty flush would invent an operation the oracle never sees), and `.close` at `fclose`.
Recording happens before the call, so the kill lands *before* the flush — what dies with
the process is the unflushed buffer, which is exactly what a real crash loses. What
bypasses the buffer (a large `fwrite` going direct, an overflow flush inside `fprintf`,
the exit-time cleanup of never-closed streams) is deliberately not modelled: on Linux
the oracle sees the extra writes and the run refuses, same as today, just from a much
smaller class. The alternative that would have made everything 1:1 — forcing streams
unbuffered — was rejected for the best reason this project has: it would explore crash
states the natural execution cannot produce.

Plan review (two Critical, eight Major) fixed a real bug before any code existed:
`freopen` with pending data issues **[write, close, open]**, and the draft recorded only
the last two — an instant `oracle_missed_operation`. It also forced the macOS caveat
into the open (no oracle there, so the not-modelled classes fall inside
`--allow-unverified`'s already-weaker claim rather than being caught), added the
missing glibc symbols (`fopen64`, `freopen64`, `fflush_unlocked`), and demoted
"one flush = one write" from an assumption to an expectation whose violation is
detected. Declined once, with reasons recorded: shipping this Linux-only. macOS goes
from zero stdio visibility to everything inside the boundary, under a claim whose
wording does not change.

**Implemented — and the first dogfood run found the flush point the plan did not
know about.** The toys all passed on the first full suite (six new acceptance cases,
kill-point sequences asserted with the decoder against exact predictions, the fopen64
alias exercised through an LFS build), the mutations landed red in both directions —
removing the pending check turned out to be caught by *three* checks, because it also
records a phantom write for the read-control stream's fclose — and then taskwarrior
refused again. The diff of the two accounts showed its `pending.data` write reaching
the disk inside an **fseek**: the file is updated through an `"r+"` stream, and libc
flushes a dirty stream as a side effect of repositioning it. `fseek`/`fseeko`/
`rewind`/`fsetpos` are flush points too, now wrapped with the same pending rule and
pinned by a toy in the taskwarrior shape ("r+", dirty, seek) whose check was shown its
own red once. The macOS pending fallback earned its keep immediately: the `__sFILE`
arithmetic passed the two-byte pin test on the first run, and parity came back exact —
the same six kill-point addresses for the stdio toy on both platforms.

**Review round, re-read as the contract demands.** Four findings, all adopted, one of
them the best catch of the day: recording freopen's whole [write, close, open] triple
before its one real call meant a kill aimed at the new `.open` died before *any* of the
syscalls — a world whose address claims the flush already happened, over a file that is
still empty. The wrapper now flushes explicitly first (record `.write`, real `fflush`,
then `.close`/`.open`, then the real freopen, whose own flush is empty), which keeps
the oracle's sequence identical and makes every address honest — the remaining gap
between the recorded close and the real one is disk-neutral, which is what ADR 0003's
close rule is for. The new acceptance pin kills at the open's address and asserts the
flushed line is durable; mutating the wrapper back to record-all-then-call went red on
the new pin while the sequence check stayed green — a measured demonstration of the
reviewer's point that recording order alone cannot see this. Also adopted: inactive/
re-entered shims no longer touch stream internals before refusing; `freopen(NULL)`
joined the documented not-modelled list; and the mode-predicate comment stopped
claiming the two predicates agree on inputs libc rejects before any syscall. taskwarrior: **PASS 12/12 worlds**,
oracle agreed on 11 operations, all three data files under the history form — and with
`--check "task list"` the falsification probe rejected the corrupted state
("Unrecognized Taskwarrior file format") and taskwarrior's own reader judged every
crash world. The second real target, judged end to end. git: `COMMIT_EDITMSG` no
longer splits the accounts — the shim now records all 31 in-scope operations — and the
run refuses one wall later, on #31's class: `mkdirat(AT_FDCWD</g1/repo>,
".git/objects/cc", …)` has no absolute state-directory spelling anywhere in the line,
so the oracle cannot see it (the result-fd annotation that saves relative `openat` does
not exist for calls returning 0). The wall moved from #30 to #31, exactly as scoped.
omamori: PASS 143/143 twice over, numbers unchanged — a Rust target never enters the
new wrappers.

## 2026-08-11 — L0 learns a second per-file form: history preservation (#24, in progress)

The plan was measured before it was written, and the measurement deleted two of the
issue's three directions. Re-running `omamori exec -- /bin/true` twice from the same
restored state, plus one straced run: the only non-reproducible file in the state
directory is `audit.jsonl`, and its shape is a strict extension — pre is a byte prefix
of post. The HWM sidecar is rewritten, but through temp+`rename` and with deterministic
content (`0` → `1`); the secret never changes; the lock and the `.hwm.tmp` exist in only
one snapshot and are outside L0 anyway. So the class "non-reproducible rewrite" — the
one that would need a per-world fresh baseline (direction 1) or L2 delegation
(direction 3) — has no representative in the first real target. Direction 2 alone
closes #24.

Two more measurements sharpened what the change means. The 142 operations are real: one
audit line is written through **134 separate `write(2)` calls**, so a kill lands inside
the line and leaves a torn tail — the "crashed content still begins with the pre
content" invariant holds there too, and whether a torn tail is acceptable becomes the
checker's question, not L0's. And `omamori audit verify` already answers it: fed an
audit log with a half-written last line, it reports "chain intact. (1 torn lines
skipped)" and exits 0. The dogfood prediction is therefore PASS, and a deviation from
that prediction would itself be a finding.

Adversarial review of the plan (two Critical, seven Major) forced one rename and one
reversal before any code. The form is **not** called "append-only": a snapshot proves a
shape, never a write mechanism, so the name now claims exactly what is checked —
**history-preservation form**. (The reviewer's "soundness regression" framing was
declined with a reason worth keeping: to a snapshot judge, the intermediate states of a
sequential rewrite are byte-identical to those of a true append — mechanism is not
observable in principle, and rename-rewrites, unlink-recreates and truncate-rewrites
all still land in violations.) The reversal: a file that is **empty in pre** does not
enter the form. `startsWith(anything, "")` is vacuously true, so the "history" of an
empty file constrains nothing; such files keep the standard pre-or-post rule, and a
non-deterministic fresh log stays an honest UNKNOWN instead of a silent no-check. Also
adopted: classification happens once (`classify → L0Plan`) and both the judgement and
the report read from it, so the two cannot drift; the report's `not tested` line grows
"appended tails" dynamically whenever the form is in play.

**Implemented; the mutation pair landed where the plan said it would.** The engine
change is `classify(pre, post) → L0Plan` plus a `judgeL0(plan, crashed)` that reads it,
a third violation (`rewritten`), and a report that carries the classification in text
and JSON alike. The shim is untouched and the contract stays v4. Disabling
classification alone sent the append toy back to `baseline_violates_invariant` — the
measured pre-fix class — and turned the rewrite toy's verdict into a *hybrid*-worded
FAIL, red on wording. Disabling the violation check alone let the rewrite toy PASS
with its truncate window open (red), while the non-deterministic rewrite toy **stayed
refused** — the boundary of the relaxation is held by the classification, not by the
arm that was just mutated, which is exactly the separation the L0Plan design bought.
While fixing the baseline gate's surroundings, its comment turned out to already be
wrong before this change: it claimed the gate is "only reachable through a checker",
and the first real target reached it with no checker at all — the baseline is a fresh
execution, not the recorded snapshot. The comment now says what was measured. 60 unit
tests, 57 acceptance assertions, all green on Linux.

**The wall is down, measured end to end.** The dogfood script now lives in the repo
(`spike/dogfood-omamori.sh`) and runs two explorations. Without a checker: **PASS
143/143**, the report naming `audit.jsonl` as the one history-form file and the oracle
agreeing on 142 operations — the same run that was structurally UNKNOWN yesterday. With
`--check "omamori audit verify"`: the falsification probe fails loudly on the corrupted
state ("audit secret must be exactly 64 hex characters"), and then the target's own
verifier judges all 143 worlds — visibly, one line per world: the early worlds hold one
entry, roughly 130 hold one entry plus a torn line it skips by design, the last few
hold two. PASS, as the torn-tail probe predicted. This is the first time a real
target's own invariant has been cross-examined in every crash world sideeye can
construct — and the first exploration where the question "is a half-written audit line
acceptable after a crash?" was actually asked 130 times and answered. One stumble on
the way: the first dogfood run ended in SETUP ERROR because a fresh HOME has no
`.local/share` and the engine creates only the final component of `--state` — the
script now makes the parents, and the error's JSON incidentally showed the `l0` note's
"not classified" state doing its job in the wild.

**Review round, re-read as the contract demands.** Two findings, both adopted. The
UNKNOWN text report carried no `atomicity` line while the UNKNOWN JSON did — the exact
"two forms, one content" rule this codebase keeps citing, broken by the surface that
was added to honour it; both lines now appear in `unknown()`, the acceptance pins the
text, and the pin was shown red once via a spelling mutation. And the l0 note embedded
target-chosen file names into the text report unescaped — a Unix file name may contain
newlines, enough to forge report lines. The note now defangs control bytes
(`evil\nname` prints as `evil?name`), with a unit test. The same-class scan found the
FAIL block's own path fields (`after`/`before`/`path`) have carried that exposure
since v0.1 — pre-existing, off this change's thesis, filed as its own issue rather
than widened into this diff. macOS parity: the append toy passes under the history
form and the rewrite toy fails at **the same logical address as Linux** (crash point 3
of 8, after truncate, before write). One environmental find that cost an hour of
suspicion: on this development machine, `DYLD_INSERT_LIBRARIES` is silently ignored
for binaries produced by `zig cc` (dyld prints nothing, no shim, no trace) while the
same source compiled by the system `cc` interposes fine — CI's zig-cc path stays
green, so it is pinned to this host's policy, not to the toolchain in general.

The plan, before the code: crash-point addressing and the completeness comparison move to
cover **state-changing operations only**. A write-incapable open — accmode is `O_RDONLY`
and neither `O_CREAT` nor `O_TRUNC` is set — mutates nothing, so the world killed
immediately before it is byte-identical to the world killed at the next address; it stops
being a crash point and stops being compared, on both sides, under one predicate. `close`
leaves the comparison too (it stays recorded): the simulation over omamori's accounts
showed read-only-open exclusion alone leaves the close of a raw-opened descriptor
stranded on the oracle's side, and fd-provenance tracking dies on `dup` and inheritance.
Simulated result to beat: **142 vs 142, aligned**. Contract bumps to v4 — the recorded
set changes meaning, and a v3 shim under a v4 engine should refuse loudly, not drift.

Adversarial review of the plan (one Critical, eight Major) reshaped two things before any
code: the oracle-side predicate is **fail-closed** — a symbolic `O_` token must be
present before anything is excluded; numeric-only flags (`0x241`), missing arguments and
unknown shapes are counted as before, so a parse failure ends in UNKNOWN, not a pass. And
the predicate moved from a flag-list to accmode, which keeps `O_RDONLY|O_CREAT` (creates
but cannot write) addressable and drops `O_APPEND` from the set (append without write
access cannot write). Rejected with reasons: recording flags in `aux` and projecting
later (a type pun that makes `aux` mean different things per op, and a third place the
predicate must agree), and fd→flags tracking (leaks on dup/inheritance).

**Implemented, with one prediction corrected.** The mutation pair went red in both
directions, but the plan mislabelled one: disabling the shim-side exclusion was predicted
to surface as `oracle_saw_phantom`, and it surfaces as `oracle_missed_operation`, because
`compare()` reports any mid-sequence divergence as "missed" and reserves "phantom" for a
shim account that is a pure suffix-extension. The discrimination is intact — the
read-first toy flips from FAIL at 5-of-5 to UNKNOWN under either one-sided mutation — the
label prediction was just wrong, and the acceptance comments say what actually appears.
Two count anchors moved exactly as the run-first sweep found them: "agreed on 6
operations" is 5 (close left the comparison), and the zero-op PASS wording is now "no
state-changing operations". 55 unit tests, 52 acceptance assertions.

**Review round, re-read as the contract now demands.** Three findings, all adopted. The
ADR overclaimed `O_RDONLY|O_CREAT` as "a mutation": it keeps its crash-point address, but
`OpClass.open` has never counted toward `isMutation()` (deliberately — it makes
`state_changed_without_ops` stricter), so a target whose only state change is creating
files via open is refused by that detector, before and after this change; the ADR now
says addressable, not credited. strace spells an *invalid* access mode as `O_ACCMODE`
(its own xlat says so), which the fail-closed token set did not contain — the one input
on which the two predicates would have split, now in the write set with a test. And
"state-changing operations" oversold the set — a write-capable open may change nothing —
so the public wording is "operations that can change state". The confirmation round then
caught the ADR still listing the old token set two paragraphs below the sentence that
described the new one — fixed; a document can contradict itself as easily as two
documents can.

**The measurement this PR exists for, and the wall behind the wall.** omamori again,
under the new rules: the oracle **agreed on 142 operations** (615 syscall lines examined,
183 in scope — the exact number the simulation predicted), one tolerated child, and the
engine explored **all 143 worlds with every kill landing, in about one second**. The
verdict is `UNKNOWN baseline_violates_invariant`, with 138 of 142 crash worlds reading as
violations — and that is the *correct* answer, not a defect: omamori's audit line carries
a timestamp and an HMAC chain, so re-running the operation writes different bytes, every
crash world's partial line matches neither the pre nor the post content, and the baseline
world differs from the recorded final for the same reason. The baseline gate built during
v0.1 release prep is precisely what stood between this target and a monstrous false
"FAIL 138 of 142". The next wall is therefore not observation but **operation
non-determinism versus L0's byte comparison** — filed as its own issue; candidate
directions include a per-world fresh baseline and an L0 form for append-only files.

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
