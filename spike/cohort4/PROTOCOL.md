# Criterion 1, fourth cohort — the campaign protocol

This directory is a criterion-1 search under the provenance gate (ADR 0017,
tracked by #140). What this cohort is for, in one sentence (`PREP.md` §2):
**the missing combination is novel × automatically discovered × mini-seal
provenance, in one finding** — detection has not been the binding
constraint since cohort 3, novelty has. The draft this freeze fills in is
`PROTOCOL-DRAFT.md` (2026-08-22); the preconditions and the mistake
register it is built on are `PREP.md`; both were merged before any target
was named.

Everything below was committed before any probe, explore, or
target-behavior measurement. Pre-freeze contact with the targets was
**install plus `--version` only** — the standing pre-window rule — and it
happened once, in this file's own image build (`freeze-build.txt`).
Reading a target's public source and tracker while scouting is not
observing a failure in execution — criterion 1's own text — and every such
reading is recorded in `SCOUT-ROWS.md` with the command that produced it.
The rules that decide what counts are not allowed to know the results.

## Targets and selection

Selection followed rules 1–13 of #209 unchanged plus this cohort's 14–17
(`PREP.md` §6, `SCOUT-BRIEF.md`): (14) novelty pre-scan as a veto, never a
ranking; (15) interior forecast; (16) wall forecast against the known list,
with lifting apparatus named before the probe or the candidate does not
enter; (17) rule 11 measured on bug reports specifically. The measured
candidate rows, the rejection table, and the transcripts behind every
number are committed beside this file (`SCOUT-ROWS.md`,
`novelty-prescan-*.txt`, `rule11-*.txt`, `write-path-evidence.txt`) — the
rejection table is what makes the slate auditable.

**The selection was corrected by its own measurements once, before this
freeze.** The 2026-08-22 sign-off named himalaya and vdirsyncer on rows
that had not yet been measured to the brief's standard. Measuring them
(2026-08-23) failed vdirsyncer on rule 2 (three commits in six months, all
typo/docs/CI), rule 3 (one author in the window), and rules 11/17 (one of
its six recent bug reports answered within a week; three drew no comment
from anyone but their author, and one was answered after 106 days by a
non-maintainer — `SCOUT-ROWS.md`, `rule11-vdirsyncer.txt`) — and found the
intended checker anchor, `repair`, gated behind an interactive
`click.confirm` (cli/__init__.py:261). The owner ruled the
same day: **vdirsyncer is dropped, and the second slot is re-scouted
before this freeze lands** — no single-target cohort, no promotion clause.
vdirsyncer's row stays in `SCOUT-ROWS.md` as the rejection it is.

**Order, frozen: himalaya → [SLOT 2 — pending re-scout, owner sign-off
required before this file merges; a pending slot here is a reason not to
freeze].** The bench is deliberately empty — the owner's 2026-08-22
ruling, unchanged by the re-scout: the enumerated pool measured thin (128
of 159 repositories fell to language-wall forecasts recorded in
`CANDIDATES-REJECTED.md`), and the #201 tripwire for a null outcome is
already recorded there and on #201.

## Provenance: assisted, scout named

Every claim from this cohort carries the assisted label. The scout is a
combination of the targets' own public source and documentation, read
2026-08-22/23 and recorded per candidate in `SCOUT-ROWS.md` (repository
checkouts pinned by tag, crates.io artifacts checksum-matched against the
target's own lockfile), plus tracker reads for rules 11 and 14. Blind is
off the table for the whole cohort and no run under this protocol may be
described with that word. The workspace memory index injects cohort target
names into fresh agents (#221, measured): any cohort-4 step that depends
on an agent not knowing the targets runs out of band, with the channel
named in its record.

## The probe gate

Cohort 2's seven conditions apply with their predicates **sourced in
place** (`spike/cohort2/probes/lib.sh` — no fork, no copy: the cohort-2
drills and this cohort's runs exercise the same lines). Cohort 4 adds two,
implemented in `probes/lib.sh` here and drilled in both colours before any
target contact (`probes/drills.txt`, 5 of 5):

- **Condition 8 — shim visibility agrees with the kernel**
  (`preflight.sh visibility`): every in-root mutation the kernel performed
  must also have passed through a function an `LD_PRELOAD` interposer
  built from the shim's own exported symbols can see. A disagreement is a
  named wall at probe time, costing zero defines — the condition cargo
  cost two defines and two explores to discover.
- **Condition 9 — the operation has an interior**
  (`preflight.sh interior`): the count of engine-reachable kill points
  inside the state root, reported with its per-class breakdown. A count of
  1 is not a failure; it is a fact that goes to the owner — the papis
  shape, measured at probe time instead of at define time.

Harness continuity, unchanged from cohort 3: **the drills re-run under
this image** (both cohorts' drill sets — an image change is a harness
change) before any probe verdict counts; one committed transcript per
target (`probes/<target>.txt`), all nine conditions or the probe has not
passed; **the positive control runs first** — cohort 3's control, a
synthetic operation writing wall-clock bytes into its state root, which
must split the determinism check through the same predicate path as the
targets.

### Probe plans, fixed here (operation, pre-state, state root, expected artifacts)

Apparatus plumbing (exact env variable names, temp paths, the transient
`/etc/ld.so.preload` line) may be corrected at probe time with the
correction recorded in the transcript; the operation, the pre-state shape
**including the fixture bytes inlined below**, the candidate state root
and the expected artifacts are frozen here. The fixture contents are part
of this freeze — a probe implementation may not substitute its own.

1. **himalaya** — the state root is a maildir store in io-maildir's
   default nested-fs layout: the root directory is itself the INBOX. Two
   general observations behind this plan, both from the pinned v2.1.0
   source and its lockfile-matched io-maildir 0.3.0 (readings in
   `SCOUT-ROWS.md` and `write-path-evidence.txt`): the store's writes go
   through `std::fs` (libc-routed, shim-visible), and **`maildir messages
   copy` is the one arm without a tmp stage** — the target file is
   created at its final path and filled in place (io-maildir
   `entry/copy.rs`; the I/O is `fs::copy` at `client.rs:227`), so every
   intermediate state is a visible message file in the target folder.
   save and move are tmp→rename (the papis shape); copy is the slot.

   Pre-state: the root holds `cur/`, `new/`, `tmp/` and one subfolder
   `Archive/` with its own `cur/`, `new/`, `tmp/` — all empty except
   root `cur/`, which holds exactly one message under the pinned
   filename `1700000000.#0M0P1.probehost:2,S`, with exactly these bytes
   (LF line endings, trailing newline):

   ```
   Return-Path: <probe@example.invalid>
   Date: Sat, 01 Mar 2026 09:00:00 +0000
   From: Probe Author <probe@example.invalid>
   To: Probe Target <target@example.invalid>
   Subject: Existing message, fixed bytes
   Message-ID: <existing0001@example.invalid>

   This is the existing message. Its bytes are part of the freeze.
   ```

   The account configuration is this fixture (`config.toml`, outside the
   state root, `maildir.root` pointed at the root by the run script):

   ```toml
   [accounts.probe]
   default = true
   maildir.root = "<state root>"
   ```

   Operation: `himalaya -c <config.toml> maildir messages copy
   1700000000.#0M0P1.probehost --maildir . --target Archive`
   (`--maildir .` names the root itself — the INBOX in the default fs
   layout; no `--subdir`, so the copy keeps the source's `cur`).

   Expected: exactly one new file under `Archive/cur/`, its body
   byte-identical to the fixture message and its flag suffix `:2,S`
   preserved; the source file untouched; `new/` and `tmp/` everywhere
   still empty. The copy's filename is minted, not preserved
   (`entry/copy.rs`'s own doc), which is why the determinism forecast
   below exists.

   **Determinism forecast, and the apparatus that answers it (rule 16).**
   Minted entry names are `{secs}.#{counter:x}M{nanos}P{pid}.{hostname}`
   (io-maildir `entry.rs:48-56`). secs/nanos are wall clock — libfaketime,
   already in the image, the cohort-2 tier; counter is a process-local
   atomic (constant for a fresh process per run); hostname is the
   container's (fixed); **pid varies per invocation and will split the
   two-run determinism condition on its own**. pid reaches the name via
   `std::process::id()` (`client.rs:239`), the libc `getpid` symbol, so
   the declared apparatus is `pin-getpid.c` (committed beside this file):
   a preload returning a fixed pid, loaded via `/etc/ld.so.preload` — the
   faketime precedent, the engine owning `LD_PRELOAD`. Owner-gated per
   the apparatus policy; the probe transcript must show the split without
   it (the falsification) before any run uses it.

   **Copy-mechanism forecast (rule 16).** `fs::copy` on Linux prefers
   `copy_file_range(2)` with a `sendfile(2)` fallback before the plain
   read/write loop. The oracle reports both as unsupported operations
   (the hg-r2 sendfile precedent; `oracle.zig`'s v0.1 model), so a stock
   run may refuse rather than measure. The declared apparatus is
   `seccomp-enosys.json` (committed beside this file): a container
   seccomp profile answering exactly `copy_file_range`, `sendfile` and
   `sendfile64` with ENOSYS, which Rust's std treats as "unavailable,
   fall back" — landing the copy on the libc read/write path the shim
   exports and the oracle models. Owner-gated, probe-falsified the same
   way (strace must show the syscall without the profile and its absence
   with it). **The kill window does not depend on this apparatus**: the
   destination is created (`O_CREAT|O_TRUNC`) before any bytes move, so
   a kill between creation and fill leaves a zero-length message at its
   final path under every copy mechanism — the stock-reproduction rule
   below stays satisfiable by strace fault injection alone.

   Ambient: `XDG_CONFIG_HOME`/`HOME` at reset-between-runs paths shown in
   the transcript; the config is passed explicitly with `-c` either way.

2. **[SLOT 2 — pending re-scout.** The probe plan for the second target
   is written into this section, with its fixture bytes inlined, before
   this file merges. A section still pending at freeze time is a reason
   not to freeze — `PROTOCOL-DRAFT.md`'s own rule.**]**

A target that fails its probe records a **named wall**: which condition
failed and the raw evidence. Every target installs at the current upstream
stable (Versions below), so the latest-stable recheck a wall requires
before being called terminal is inherent.

## Apparatus policy (frozen before any run)

Three tiers, unchanged from cohort 3:

- **Configuration and environment pinning** — free, uses only switches the
  target documents, declared where used.
- **Pre-declared, used only on the named refusal**: the CPython sendfile
  fallback (`sitecustomize` setting `shutil._USE_CP_SENDFILE = False`) for
  any Python target, on `unsupported_syscall_observed: sendfile` only.
- **Interposition — clock, entropy, or identity — is a per-target owner
  decision.** The image carries libfaketime; this cohort adds two
  committed, target-named candidates (himalaya's `pin-getpid.c` and
  `seccomp-enosys.json`, above), each of which must be seen to answer a
  measured split or refusal in the probe transcript before a define
  carries it. Apparatus discovered mid-probe is an amendment that must
  land before that target's first contact.

Whatever the apparatus: **a finding must reproduce against the stock tool
with no apparatus beyond strace fault injection before it is claimed or
reported** — unchanged from cohorts 2 and 3.

## The mini-seal, the claim reading, and the checker rules

The mini-seal is cohort 2's, sharpened for #140, read with
`spike/cohort4/` paths, and extended as cohort 3 extended it. The
operative sentences, inside this freeze rather than behind a reference:

- No engine explore before the target's complete define (toml + checker +
  setup + launcher) is on main; a define revision is a new target
  directory; **a FAIL freezes the define** — later revisions cannot
  produce a criterion-1 claim for that target, and a post-FAIL revision is
  a record-only artifact, stated in advance so it is not re-litigated with
  a fresh FAIL in hand (`PREP.md` §3 B2).
- **An amendment made after a target's first explore cannot change how
  that target's outcome is read, and neither can one made after its
  probe.**
- The checker runs directly on the crashed state; documented recovery
  first, then assert; every leg seen red once, separately; every assertion
  holds on the un-killed baseline. Checkers go through the target's own
  commands — the owner's 2026-08-22 rule-9 ruling, no exception clause.
- At claim time the transcript includes `spike/assisted/verify-assisted.sh
  spike/cohort4/<target>` green and `git log --first-parent -p --
  spike/cohort4/PROTOCOL.md` — every post-freeze amendment visible inside
  the claim.

**Claim reading, frozen before the first explore** (#231 merged
2026-08-22, ADR 0020 — the rule `PROTOCOL-DRAFT.md` drafted, verbatim):

> A criterion-1 candidate is a run whose **`checker_earliest`** exhibit
> exists — that is, a run in which some violating world's violation
> includes the declared checker — and the exhibit named there is the
> claim's exhibit. An **L0-only FAIL is a precision-limit observation,
> recorded and never claimed** (#35's ruling, applied cohort-wide in
> advance); a run whose only violations are L0-only has no
> `checker_earliest` and therefore no candidacy. The overall `earliest`
> remains the first physical counterexample and is reported as such,
> whether or not it is the exhibit.

Two non-changes, restated so they are not read into the rule: cohorts 1–3
are not re-read, and the FAIL-freeze rule still binds — `checker_earliest`
changes which world is the exhibit within a run, never which runs are
eligible.

Everything downstream of a candidate is unchanged from the standing gates:
novelty search with a positive control, per-report owner approval before
any upstream filing, author confirmation, fix, replayed regression case.

## Versions and image

The image (`Dockerfile` here) has an apt layer pinned by BUILD, not by
manifest; the targets are exact-pinned. **himalaya is built from source in
the image, on purpose and with this disclosure carried into any wall,
FAIL, or report: the distributed binaries are musl-static cross-builds,
which `LD_PRELOAD` cannot enter, so the measured binary is a glibc-dynamic
self-build of the same v2.1.0 tree with the same default feature set — the
delta to the distributed artifact is linkage, not features.** The pin
chain, each link machine-verified: the v2.1.0 tag dereferences to commit
`ca88bee08ad2e92127b46dc6200d1e8201885156` (content-addressed, verified at
fetch); the copied tree is re-verified in the build against a sorted
per-file sha256 digest; the crate closure is vendored with `cargo vendor
--locked` and re-verified by cargo itself at build time against the
checksums in the tree's own committed Cargo.lock; the built binary must be
dynamically linked against glibc or the build fails (the `ldd` assertion
in the Dockerfile). rust 1.98.0 builds it, from the same channel-manifest
sha256 pin as cohort 3, and stays in the build stage — the runtime image
carries the himalaya binary, not cargo.

**[SLOT 2 — pending: the second target's pin and install layer, and the
regenerated `freeze-build.txt`, land with the slot.]** The committed
`freeze-build.txt` is the transcript of the freeze build and the only
pre-freeze target contact; the versions that actually run are re-recorded
in each probe transcript and RUNLOG.

## Reporting, and delivery

Each upstream report is its own owner-approved gate; nothing in this
cohort authorises contact. The standing table of what has been filed and
what has come back is `spike/upstream-report-status.sh`, which measures
rather than remembers.

Merges in this cohort go through `spike/merge-gate.sh`, read as a printed
verdict and never chained to the merge command. BUILDLOG entries open when
the work starts, not at PR time.
