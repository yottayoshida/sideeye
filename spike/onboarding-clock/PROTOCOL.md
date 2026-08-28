# The onboarding clock — criterion 6's protocol, declared before the first run

PRD v1.0 entry criterion 6: *a fresh machine reaches its first exploration in
under ten minutes from the README.* Issue #87 fixed the strict reading — the
clock measures an **external target**, not the embedded demo — and required
this document to exist before any timed run. Everything below was written,
committed and left unchanged before the first measurement *(sections amended
since are dated in the Amendments section, under this paragraph's own rule)*;
a change to this protocol after a run voids nothing retroactively but starts
the run count over.

## What is measured

Wall-clock from a context-free driver's first sight of the README to an
exploration of the external target returning a **real verdict** — exit 0
(PASS) or exit 1 (FAIL). A refusal (exit 2) does not stop the clock: refusals
are named and fixable, and a fresh user keeps going; if the ten-minute budget
expires mid-refusal-loop, that is the measurement. The criterion's number is
the wall-clock of the **first** qualifying exploration.

- **Start**: the timestamp of the driver session's init event in its
  transcript. The README is the first thing the driver is pointed at, so
  session start and "README open" coincide to within seconds. *(Amended
  2026-08-28: run 1's init event carried no timestamp, so what was actually
  derived was the first timestamped event — the first assistant turn. The
  launcher now stamps its own start as well, and the amendment names which
  of the two the criterion reads.)*
- **Stop**: the timestamp of the tool result carrying the qualifying
  exploration's exit. Both timestamps come from the committed transcript —
  the wall-clock is derived, never hand-written.
- **Outcome forms**: `met` (qualifying verdict, under 10 minutes), `not met`
  (qualifying verdict, over 10 minutes), `DNF` (the driver stopped or the
  session ended without one). All three publish with the same detail.

## The fresh machine

A network-off Linux container (`docker run --network=none`), built by the
`Dockerfile` beside this protocol. Inside, at `/home/user/onboarding`:

- `README.md` — the repository's front page at the measured commit, verbatim.
- `sideeye-v0.13.0-aarch64-linux.tar.gz` — the current release tarball,
  fetched at image build from the GitHub release and pinned by sha256 in the
  Dockerfile *(v0.10.0 at run 1; moved with the second 2026-08-25 amendment
  below, so the pinned artifact is the one a fresh machine downloads today)*.
- The target, **jrnl** (selected by the owner 2026-08-16 under the standing
  bar: ≥500 stars, more than one contributor, activity within the last month;
  7,291 stars, pushed 2026-08-14, installed from PyPI at image build with the
  installed version recorded), **pre-configured** with a plain-text journal at
  a known path — the wizard answered at build time, not on the clock.
- A C compiler and strace, present as on any Debian dev box.

## Declared deviations, and why each is honest

1. **The tarball is pre-staged.** The sealed run has no network; the download
   is one `curl` whose duration measures GitHub's CDN, not this repository's
   documentation. The clock starts after the artifact exists, exactly as the
   criterion's sentence starts at the README.
2. **The target arrives installed and configured.** The criterion measures
   sideeye's onboarding; a user measuring their own tool has it working
   already. jrnl's own setup wizard is not sideeye documentation.
3. **The README is a staged file, not a browser tab.** "README open" becomes
   the session's first read of that file.

## The driver

A fresh `claude --safe-mode -p` headless session (no CLAUDE.md, no hooks, no
MCP, no skills — the loop-closure runs' isolation form, BUILDLOG 2026-08-13),
launched by `run-clock.sh` with the prompt in `prompt.md`, verbatim. The
driver is **not told it is being timed** — a driver racing a clock skims, and
the criterion is about the documentation, not the driver's nerves. Tools:
Bash **scoped to `docker exec onboarding-box` invocations** (Amendments,
2026-08-25) plus Read/Edit/Write/Glob/Grep, with the network and delegation
tools denied by name, and one standing instruction — every command that
touches the machine goes through `docker exec` to the box.

**The permission flags are not a seal, and the audit is the detector**
(Amendments, 2026-08-28). What the audit promises is bounded and exact:
**a tool call outside the run's declared allow-set is recorded in that run's
evidence with its name and its whole input — serialised, unabridged, with the
host home directory spelled `~`.** Those three words are the whole
transformation; nothing is dropped, shortened or summarised. A path into this repository's
checkout, or a denied tool attempted, voids the run; everything else the audit
surfaces without being able to judge — a command the box predicate cannot pass
clean, a tool nobody declared — is carried for adjudication. The audit does not
claim to detect escape: a declared tool used badly is inside the allow-set and
outside what any predicate here can see.

## Rehearsal boundary

Before the first timed run the apparatus may be proven — the image builds,
`jrnl` accepts a non-interactive entry, the tarball's binary prints its
banner, `sideeye demo` finds its planted bug, strace and cc exist. The
apparatus rehearsal must never run `sideeye` **against jrnl**, author a
define for it, or read jrnl's file layout with sideeye in hand: the first
exploration of the target happens on the clock or not at all.

## What one run proves

One timed run is one measurement, not a distribution. A `met` says the path
exists and was walked once; a `not met` or `DNF` names which door is
load-bearing (issue #87's stated purpose for measuring early). Re-runs after
doc changes use a fresh box and append — earlier numbers are never edited.

## Amendments

### 2026-08-25 — the escape paths close at the permission layer (#160)

Per this protocol's own rule, these changes restart the run count. Run 1's
evidence stands untouched as the measurement of its own date; the next timed
run is run 2 — run directories continue the numbering, and each run's
`meta.json` carries `protocol_version` naming the amendment date it ran
under.

1. **The driver's Bash is scoped, and the launcher refuses to start
   nested.** The allowlist names `Bash(docker exec onboarding-box *)`; the
   CLI's documentation says the pattern gates before execution (the trailing
   ` *` binds at a word boundary, compound commands match per subcommand,
   a newline is a separator). **The environment that was actually measured
   is a different one**: launched from inside another Claude session
   (2026-08-25), the scoped pattern refused none of the escape shapes, and
   the one denial that occurred names the parent's auto-mode classifier —
   it blocked the legitimate in-box heredoc author. So the
   launcher now refuses outright when it detects a nested session, the
   audit's predicate — independent of any permission layer — carries escape
   detection in every environment, and **probing the pattern from a plain
   terminal is a named precondition riding with run 2's preflight**. Run
   1's transfer idiom (host-side `docker cp`, base64 pipelines) is outside
   the declared scope either way; a driver authors files inside the box,
   which run 1's driver also did (its heredoc form). Two documented CLI
   bounds stay on the run-2 DNF suspect list: a command the permission
   layer cannot parse, or longer than 10,000 characters, prompts — which a
   headless run experiences as a refusal.
2. **The audit reads quotes.** The extractor's box predicate is no longer a
   string prefix: it tokenizes with quoting in force and flags a leading
   token triple that is not exactly `docker exec onboarding-box`, any
   top-level shell operator (`;`, `&&`, `|`, redirects), an unquoted
   newline, and any command-substitution marker (`` ` `` / `$(`) wherever
   it appears — a quoted substitution runs inside the box legitimately and
   is still surfaced, because the audit cannot tell the two apart and
   prefers a flag over silence. A command the tokenizer cannot parse is
   flagged as unparseable rather than crashing the extraction mid-run.
3. **The violation vocabulary splits.** `audit_void` carries what this
   protocol voids outright: a denied tool attempted, a read into this
   repository. `audit_adjudicate` carries everything the box predicate
   surfaces — including shapes the permission layer legitimately allows,
   such as a redirect into the driver's own empty scratch — for the
   adjudication run 1's precedent established: a genuine escape voids;
   driver-authored bytes moving into the box stand.
4. **The target's installed version is a meta field** (`target_version`,
   read from the box before the clock starts), which deviation 2 always
   promised.
5. **The launcher's scratch is actually removed** after the run, with any
   leftover names echoed into the run log first; and the extractor's
   selftest runs before every launch, so a predicate regression stops the
   launch rather than surfacing at adjudication.

One attribution note for reading run 2: the driver keeps its host-side
Write tool, and a driver that reaches for run 1's transfer idiom will be
refused until it re-derives in-box authoring. That detour is apparatus, not
documentation. If run 2 runs slow, check the timeline for refused transfer
attempts before reading the number as a README verdict.

### 2026-08-25 (second, same day) — the artifact moves with the README

The pinned tarball becomes the current release (v0.13.0, sha256-pinned in
the Dockerfile as before). The reason is validity, not a defect: this
criterion asks what a fresh machine does from the README, and a fresh
machine today downloads the current release — pinning a three-releases-old
artifact measures a pairing no real user has, and the gap widens with every
release. **It is deliberately not claimed that the old artifact mismatched
the README.** Measured before this amendment was written: v0.10.0 and
v0.13.0 print identical usage text apart from the version string, the
five README-documented flags exercised (`--oracle`, `--allow-unverified`,
`--check`, `--marker`, `--fresh-state`) parse on both, and `demo`
produces the same report on both. The README names thirteen long flags;
the other eight were not exercised, and this sentence claims only the
five that were. The run count is already restarted by the amendment above;
this changes which binary run 2 measures, not the count. Run 1's evidence —
measured against v0.10.0, named in its own transcript — is untouched.

### 2026-08-28 — the confinement never existed, and the audit stops enumerating what to fear

The 2026-08-25 amendment named one precondition for run 2: **probing the
scoped pattern from a plain terminal.** That probe ran on 2026-08-28, four
pairs, `CLAUDECODE` unset, and returned a negative answer. Two sentences of
that amendment are withdrawn below, and the instrument they described is
rebuilt. Per this protocol's own rule the run count restarts again; no run has
been taken since run 1, so **the next timed run is still `run2`** — the count
that restarts is the number of measurements standing under the current
protocol, which is zero, not the directory numbering.

**What was measured, from a plain terminal.** `--allowedTools` grants; it does
not confine — a command outside the declared scope runs. `--permission-mode
manual` does not change that. The only restriction observed at all was a
working-directory sandbox, which refuses a read outside the launcher's scratch
and does not stop a host command from running. `--disallowedTools` does remove
the tools it names, and that much works — but removing one execution tool
relocates execution rather than ending it: with `Bash` denied, the driver
reached for `Monitor`, a tool on neither the allow list nor the deny list, and
ran the same host command through it. **Run 1 is not evidence either way**: its
allow-set was the bare `Bash`, and the scoping arrived with the first
2026-08-25 amendment.

**Two withdrawn sentences.**

1. *"the audit's predicate — independent of any permission layer — carries
   escape detection in every environment"* (2026-08-25, item 1). False as
   written. Two of the three predicates enumerated what to reject: denied
   tools by name, and this repository's root under two specific input keys.
   `Monitor` matched neither, and its host command was invisible to all three.
   Replaced by the bounded promise in **The driver** above.
2. *"the launcher refuses when it detects a nested session [because] the scoped
   pattern refused none of the escape shapes [there]"* (2026-08-25, item 1) —
   the **diagnosis** is withdrawn, not the guard. Nesting was never the cause;
   the pattern refuses nothing from a plain terminal either. The guard stays on
   the other half of that measurement, which still holds: the parent session's
   own permission classifier refused a **legitimate** in-box command, so a
   nested run times the parent's configuration rather than this repository's
   README.

**What changed in the instrument.**

1. **The audit enumerates what was allowed, not what to fear.** A tool call
   whose name is not in the run's declared allow-set is surfaced with its name
   and input. The list of names to fear cannot be written in advance — that is
   what 2026-08-28 measured — while the launcher knows the allowed names
   exactly. Off-allowlist calls are **adjudicated, not voided**: a benign tool
   the CLI grants without asking should not destroy a run that costs a box,
   and a real escape is still a human's call to void. This is the rule
   `spike/loop-closure-timew/judge.sh` already applied ("recorded, not void");
   this instrument was the one that had not.
2. **Classification is ordered, and the order is load-bearing.** Denied by name
   voids; then not-allowed adjudicates; then an allowed tool meets its own
   predicate. Without the order a denied tool is demoted to adjudication. And
   the allow spec must reduce to a tool **name** — the launcher declares
   `Bash(docker exec onboarding-box *)` while the transcript says `Bash` — or
   every legitimate box call lands off-allowlist and never reaches the box
   predicate, a failure that still satisfies item 1's promise. The selftest
   asserts that a legitimate box invocation carries no finding at all.
3. **A finding carries the whole input**, serialised and home-spelled and
   otherwise untouched. Findings were truncated at 160 characters, and the raw
   transcript is not committed, so anything past that was unrecoverable at
   adjudication time. The record is a **string**, not a structure: rewriting a
   structure key by key can collide — an input holding both `<HOME>/k` and
   `~/k` normalised to one key and lost a value — and a record that silently
   drops part of what it is recording is worse than the leak it was closing.
4. **The timeline carries every tool call.** The previous projection wrote one
   row per event and overwrote its note with each content block, so only the
   last call in an event survived into the committed record; a call carried
   anywhere but `message.content` was absent from the record entirely. Both are
   fixed, and the collector now walks the event recursively. **Run 1's
   `timeline.tsv` is the older projection and is not edited** — it has no
   `protocol_version` field either, since that field arrived on 2026-08-25.
   Read it as one row per event, with the extractor at its own commit.
   A consequence for anything ever said about run 1: a census taken from that
   file counts **the last content block of each event**, not the calls made.
5. **A transcript with no tool calls is `unauditable`, not clean**, and refuses
   to publish; so does a policy that names no tool. Nothing-to-see is not
   clean.
6. **The policy has one definition.** The launcher's `ALLOWED` and `DISALLOWED`
   strings go to the CLI and, unchanged, to the audit, which records them in
   `meta.json`. The extractor's own copy of the denied list is deleted — it had
   already drifted from the launcher by run 1, which `RESULTS.md` records.
7. **The audit publishes its own scan volume**: lines read and rejected, events,
   content blocks, tool calls, timeline rows, and a per-name census of the tools
   used, beside the inventory the init event reports as available. Zero findings
   over zero examined calls and zero findings over four hundred read identically
   before this.
8. **The repository void covers reach in either direction, and only what the
   audit can attribute.** A path-shaped key **at the top level of a call's
   input** — the call's own parameters — pointing at or into this checkout
   voids the run. The finding does not say "read": `Write` and `Edit` carry
   `file_path` too, so the direction is not determined, and writing into this
   repository is not the lighter half. This repository's root appearing
   anywhere *else*, nested payload included, is adjudicated rather than voided:
   a call carrying a path is not a call reaching it, and the audit cannot
   assume the input schema of a tool it could not enumerate. Both matches
   require a path boundary — stated as the complement of a delimiter set, since
   nearly any byte is legal in a filename — so neither `<root>-old` nor
   `<root>+backup` is this checkout.
9. **The launcher stamps its own start.** `meta.json` carries both
   `launch_started_at` and the transcript-derived `clock_start`. **The
   criterion reads `clock_start`**, as it always did; `launch_started_at`
   exists so the gap between the two is visible rather than assumed to be
   nothing. At run 1's 4:22 the gap did not matter; near ten minutes it decides
   the outcome.
10. **`prompt.md`'s access sentence becomes normative.** It said the driver
    *can only* reach the machine through `docker exec` to the box. Run 1
    disproved that in its own transcript — it reached the box with host-side
    `docker cp`. The sentence now instructs rather than describes. This changes
    the stimulus, deliberately and on the record: what run 2 measures is a
    driver told to use one form, not a driver discovering that a false
    statement was false.

**On confinement, so this is not re-attempted.** The driver is an API client;
it cannot be network-isolated while it works at all. The box is sealed
(`--network=none`); the driver is not, and no combination of tool allow and
deny lists will seal it — denying one execution tool leaves the others.
Confining the driver would mean running it inside its own container with the
CLI and its credentials, which is a different apparatus and would restart the
count again. **The audit as detector is not a fallback here; it is the only
design available**, and the promise in **The driver** is written to claim
exactly what it delivers.
