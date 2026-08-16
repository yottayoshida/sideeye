# The onboarding clock — criterion 6's protocol, declared before the first run

PRD v1.0 entry criterion 6: *a fresh machine reaches its first exploration in
under ten minutes from the README.* Issue #87 fixed the strict reading — the
clock measures an **external target**, not the embedded demo — and required
this document to exist before any timed run. Everything below was written,
committed and left unchanged before the first measurement; a change to this
protocol after a run voids nothing retroactively but starts the run count over.

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
the criterion is about the documentation, not the driver's nerves. Tools: the
Bash/Read/Edit/Write/Glob/Grep allowlist with the network and delegation
tools denied by name, and one standing instruction — every command that
touches the machine goes through `docker exec` to the box. The audit reads
the transcript afterwards: a command that is not a `docker` invocation of the
box, a read into this repository's checkout, or any denied-tool attempt voids
the run.

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
