# Buildlog

Development journal, newest first. Decisions are recorded when they are made — including the ones that turn out wrong. This file is allowed to be embarrassing in hindsight; that is what it is for.

## 2026-08-15 — The novelty round: four searches, four not-founds, and the boundaries say so

The step the criterion-1 redesign designated ran the same day: recorded
tracker searches with positive controls, campaign-1 method, for all four
assisted findings. Verdict on every one: **not found — novel as far as
each search sees** (`spike/assisted/NOVELTY.md`, terms and hit counts
recorded for re-running). The controls did their job in three different
shapes: buku's proved the vocabulary reaches issue BODIES (a body-only
"corrupt" match), calcurse's found a real existing apts-corruption issue
by the same word that would have found ours, and stow's used the domain's
own vocabulary (twelve live fold/unfold threads) while every
crash/interrupt/atomic term returned zero — the failure class is absent
from that tracker's language entirely. devtodo needed no vocabulary at
all: both its trackers (GitHub upstream, Debian BTS) are small enough
that enumeration is coverage — 8 + 4 items, all read, none about data.

Two honesty notes carried into the record rather than smoothed over:
stow's GNU mailing-list archives were not searched (the one adjacent
thread that exists, #29, ARRIVED from the list — suggestive of funneling,
not proof), and buku's mechanism attribution (buku's sqlite usage vs an
unavoidable tear) is deliberately left for the upstream conversation —
novelty asked whether the finding was already reported, not whose fault
it is. Upstream contact is the next step and needs per-report owner
approval; devtodo's counterparty problem (upstream self-describes as
unmaintained since ~2010) is on the record before anyone drafts that
report.
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
