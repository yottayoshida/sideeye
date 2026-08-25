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
  session start and "README open" coincide to within seconds.
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
- `sideeye-v0.10.0-aarch64-linux.tar.gz` — the release tarball, fetched at
  image build from the GitHub release and pinned by sha256 in the Dockerfile.
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
touches the machine goes through `docker exec` to the box. The audit reads
the transcript afterwards, independently of the permission layer: a read
into this repository's checkout or any denied-tool attempt voids the run;
every command the box predicate cannot pass clean is surfaced for
adjudication (Amendments, 2026-08-25).

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
