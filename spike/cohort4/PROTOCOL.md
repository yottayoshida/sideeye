# Criterion 1, fourth cohort: the campaign protocol

This directory is a criterion-1 search under the provenance gate (ADR 0017,
tracked by #140). What this cohort is for, in one sentence (`PREP.md` §2):
**the missing combination is novel × automatically discovered × mini-seal
provenance, in one finding**. Detection has not been the binding
constraint since cohort 3; novelty has. The draft this freeze fills in is
`PROTOCOL-DRAFT.md` (2026-08-22); the preconditions and the mistake
register it is built on are `PREP.md`; both were merged before any target
was named.

Everything below was committed before any probe, explore, or
target-behavior measurement. Pre-freeze contact with the targets was
**install plus `--version` only**, the standing pre-window rule, and it
happened in this file's own image builds; the committed transcript is the
final `--no-cache` build (`freeze-build.txt`). The first build of the day
also installed and version-checked vdirsyncer, then still on the slate:
that contact stayed inside the same window, and the candidate was dropped
by its measured row, not by anything the build observed. Reading a
target's public source and tracker while scouting is not observing a
failure in execution (criterion 1's own text), and every such reading is
recorded in `SCOUT-ROWS.md` and `SCOUT-ROWS-SLOT2.md` with the command
that produced it. The rules that decide what counts are not allowed to
know the results.

## Targets and selection

Selection followed rules 1–13 of #209 unchanged plus this cohort's 14–17
(`PREP.md` §6, `SCOUT-BRIEF.md`): (14) novelty pre-scan as a veto, never a
ranking; (15) interior forecast; (16) wall forecast against the known
list, with lifting apparatus named before the probe or the candidate does
not enter; (17) rule 11 measured on bug reports specifically. The measured
candidate rows, the rejection table, and the transcripts behind every
number are committed beside this file (`SCOUT-ROWS.md`,
`novelty-prescan-*.txt`, `rule11-*.txt`, `write-path-evidence.txt`); the
rejection table is what makes the slate auditable. One class of exception
is named in the rows themselves: a handful of repository-metadata numbers
(stars, commit and author counts, PyPI metadata) are inline with their
`gh` commands rather than in transcript files.

**The selection was corrected by its own measurements twice, before this
freeze.** First: the 2026-08-22 sign-off named himalaya and vdirsyncer on
rows that had not yet been measured to the brief's standard. Measuring
them (2026-08-23) failed vdirsyncer on rule 2 (three commits in six
months, all typo/docs/CI), rule 3 (one author in the window), and rules
11/17 (one of its six recent bug reports answered within a week; four
drew no comment from anyone but their author, and one was answered after
106 days by a non-maintainer: `SCOUT-ROWS.md`, `rule11-vdirsyncer.txt`),
and found the intended checker anchor, `repair`, gated behind an
interactive `click.confirm` (cli/__init__.py:261 in the fetched 0.20.0
wheel). The owner ruled the same day: **vdirsyncer is dropped, and the
second slot is re-scouted before this freeze lands**; no single-target
cohort, no promotion clause. vdirsyncer's row stays in `SCOUT-ROWS.md` as
the rejection it is.

The re-scout measured five more candidates by the same yardstick
(`SCOUT-ROWS-SLOT2.md`): Homebrew fell on rule 5 (its main state is
re-downloadable), trash-cli and pipx on rules 11/17, CocoaPods on rule 3,
and **unison survived rules 1–15**. Its window is carried by two
contributors at comparable weight (stronger than himalaya's rule-3 row);
four of its seven recent defect-labelled issues were answered within a
week; and its writer leaves a commit log for exactly the window this
engine crashes into. The owner ruled it in on 2026-08-23.

**Second correction, from this freeze's own first-sight review
(2026-08-23).** The unison sign-off had leaned on a reading that the
`DANGER.README` commit log is "replayed mechanically by the next
startup". The pinned source says otherwise: on the next run,
`processCommitLog` (files.ml:70) detects the file and **stops with a
Fatal error instructing the user to inspect the named files, delete the
notice, and run again** (the notice itself, written by files.ml:30-46,
names the source, target and temp paths and says "delete this notice when
you've done so"). There is no replay. What remains true, and what the
re-ruling rests on: the tool itself detects the dangerous state on its
own next invocation and refuses loudly; non-interactive read-back exists
(a `-batch` re-run re-scans and reconciles); the one step that is not a
tool command is the deletion of the notice, an action the tool's own
written instruction prescribes. **The owner re-ruled the same day: unison
stays**, with the checker's recovery step defined as following the tool's
own written instruction (that one deletion) and then re-running the tool
for the assert, and with the Fatal refusal itself used as a tool-command
assert leg. This is the third pre-define catch of the same shape (papis
`doctor`, vdirsyncer `repair`, unison replay): the checker anchor a
selection assumes is verified against source before anything runs.

**Order, frozen: himalaya → unison.** Two languages × two write-shape
classes: a mint-named fresh delivery into a maildir (Rust), and a
rename-pair-with-commit-log replica update (OCaml). The bench is
deliberately empty: the owner's 2026-08-22 ruling, unchanged by the
re-scout, because the enumerated pool measured thin (128 of 159
repositories fell to language-wall forecasts recorded in
`CANDIDATES-REJECTED.md`), the re-scout's own funnel came back
one-for-five, and the #201 tripwire for a null outcome is already
recorded there and on #201.

## Provenance: assisted, scout named

Every claim from this cohort carries the assisted label. The scout is a
combination of the targets' own public source and documentation, read
2026-08-22/23 and recorded per candidate in `SCOUT-ROWS.md` (repository
checkouts pinned by tag, crates.io artifacts checksum-matched against the
target's own lockfile), plus tracker reads for rules 11 and 14. Blind is
off the table for the whole cohort and no run under this protocol may be
described with that word. The workspace memory index injects cohort
target names into fresh agents (#221, measured): any cohort-4 step that
depends on an agent not knowing the targets runs out of band, with the
channel named in its record.

## The probe gate

Cohort 2's seven conditions apply with their predicates **sourced in
place** (`spike/cohort2/probes/lib.sh`; no fork, no copy: the cohort-2
drills and this cohort's runs exercise the same lines). Cohort 4 adds
two, implemented in `probes/lib.sh` here and drilled in both colours
before any target contact (`probes/drills.txt`, 5 of 5):

- **Condition 8: shim visibility agrees with the kernel**
  (`preflight.sh visibility`). Every in-root mutation the kernel
  performed must also have passed through a function an `LD_PRELOAD`
  interposer built from the shim's own exported symbols can see. A
  disagreement is a named wall at probe time, costing zero defines; this
  is the condition cargo cost two defines and two explores to discover.
- **Condition 9: the operation has an interior**
  (`preflight.sh interior`). The count of engine-reachable kill points
  inside the state root, reported with its per-class breakdown. A count
  of 1 is not a failure; it is a fact that goes to the owner. That is the
  papis shape, measured at probe time instead of at define time.

Harness continuity, unchanged from cohort 3: **the drills re-run under
this image** (both cohorts' drill sets, because an image change is a
harness change) before any probe verdict counts; one committed transcript
per target (`probes/<target>.txt`), all nine conditions or the probe has
not passed; **the positive control runs first**. The control is cohort
3's: a synthetic operation writing wall-clock bytes into its state root,
which must split the determinism check through the same predicate path as
the targets.

### Probe plans, fixed here (operation, pre-state, state root, expected artifacts)

Apparatus plumbing (exact env variable names, temp paths, the transient
`/etc/ld.so.preload` line) may be corrected at probe time with the
correction recorded in the transcript; the operation, the pre-state shape
**including the fixture bytes inlined below**, the candidate state root
and the expected artifacts are frozen here. The fixture contents are part
of this freeze; a probe implementation may not substitute its own.

1. **himalaya**. The state root is a maildir store in io-maildir's
   default nested-fs layout: the root directory is itself the INBOX. Two
   general observations behind this plan, both from the pinned v2.1.0
   source and its lockfile-matched io-maildir 0.3.0 (readings in
   `SCOUT-ROWS.md` and `write-path-evidence.txt`): the store's writes go
   through `std::fs` (libc-routed, shim-visible), and **`maildir
   messages copy` is the one arm without a tmp stage**. The target file
   is created at its final path and filled in place (io-maildir
   `entry/copy.rs`; the I/O is `fs::copy` at `client.rs:227`), so every
   intermediate state is a visible message file in the target folder.
   save stages through tmp and renames; move and the flag commands are a
   single rename; the papis shape either way. copy is the slot.

   Pre-state: the root holds `cur/`, `new/`, `tmp/` and one subfolder
   `Archive/` with its own `cur/`, `new/`, `tmp/`, all empty except
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
   (`--maildir .` names the root itself, the INBOX in the default fs
   layout; no `--subdir`, so the copy keeps the source's `cur`).

   Expected: exactly one new file under `Archive/cur/`, its body
   byte-identical to the fixture message and its flag suffix `:2,S`
   preserved; the source file untouched; `new/` and `tmp/` everywhere
   still empty. The copy's filename is minted, not preserved
   (`entry/copy.rs`'s own doc), which is why the determinism forecast
   below exists.

   **Determinism forecast, and the apparatus that answers it (rule 16).**
   Minted entry names are `{secs}.#{counter:x}M{nanos}P{pid}.{hostname}`
   (io-maildir `entry.rs:48-56`). secs/nanos are wall clock: libfaketime,
   already in the image, the cohort-2 tier. counter is a process-local
   atomic, constant for a fresh process per run. hostname is the
   container's, fixed. **pid varies per invocation and will split the
   two-run determinism condition on its own.** pid reaches the name via
   `std::process::id()` (`client.rs:239`), the libc `getpid` symbol, so
   the declared apparatus is `pin-getpid.c` (committed beside this
   file): a preload returning a fixed pid, loaded via
   `/etc/ld.so.preload`, the faketime precedent, the engine owning
   `LD_PRELOAD`. Owner-gated per the apparatus policy; the probe
   transcript must show the split without it (the falsification) before
   any run uses it.

   **Copy-mechanism forecast (rule 16), and the owner's ruling on it
   (2026-08-23).** `fs::copy` on Linux prefers `copy_file_range(2)` with
   a `sendfile(2)` fallback before the plain read/write loop, and treats
   ENOSYS as "unavailable, fall back" (rust 1.98.0,
   library/std/src/sys/io/kernel_copy/linux.rs, read while scouting).
   Neither syscall is among the shim's exports, and the oracle reports
   both as unsupported operations (the hg-r2 sendfile precedent;
   `oracle.zig`'s v0.1 model), so an unlifted run refuses rather than
   measures. Three lifts were put to the owner: switch the operation to
   a tmp→rename arm (declined: it surrenders the interior); extend the
   shim and oracle (declined for this cohort; std reaches
   `copy_file_range` through a weak-symbol lookup whose own comment
   invites `LD_PRELOAD` interposition, so the extension is cheap and is
   filed as roadmap, #244, rather than done under a campaign); and **the
   chosen apparatus, `seccomp-enosys.json`** (committed beside this
   file), a container seccomp profile answering exactly
   `copy_file_range`, `sendfile` and `sendfile64` with ENOSYS, landing
   the copy on the libc read/write path the shim exports and the oracle
   models. It is the same accelerated-path-off shape as the pre-declared
   CPython sendfile fallback. Probe-falsified before use: strace must
   show the syscall without the profile and its absence with it. **The
   kill window does not depend on this apparatus**: the destination is
   created (`O_CREAT|O_TRUNC`) before any bytes move, so a kill between
   creation and fill leaves a zero-length message at its final path
   under every copy mechanism, and the stock-reproduction rule below
   stays satisfiable by strace fault injection alone.

   Ambient: `XDG_CONFIG_HOME`/`HOME` at reset-between-runs paths shown
   in the transcript; the config is passed explicitly with `-c` either
   way.

2. **unison**. The state root is one directory holding the two replicas
   *and unison's own state*: `a/` (the changed side), `b/` (the side the
   change propagates to), and `unison/` (the `UNISON` directory:
   archives, fingerprint cache, lock files, and the `DANGER.README`
   commit log). All three inside the root on purpose, the borg
   client-cache lesson: state that decides the target's behaviour must
   live where restore can carry it. And because the commit-log check
   (`processCommitLogs`, files.ml:84, run by the next startup) is where
   rule 9's recovery step begins, the checker's world has to contain the
   log.

   Pre-state: built at setup in two frozen steps, both in the probe
   transcript. Step 1: both replicas hold the same two files, and one
   run of the frozen operation argv below builds the archives (this run
   is part of setup, not the operation; its transcript lines are
   labelled so). Step 2: setup overwrites `a/notes.txt` with the changed
   bytes. The fixture bytes (LF, trailing newline):

   `a/notes.txt` and `b/notes.txt` at step 1, exactly:

   ```
   the original note, fixed bytes
   ```

   `a/stable.txt` and `b/stable.txt` (the bystander that must never
   change), exactly:

   ```
   the bystander, fixed bytes
   ```

   `a/notes.txt` after step 2, exactly (longer than the original on
   purpose, so a torn propagation is visibly torn):

   ```
   the changed note, fixed bytes, deliberately longer than what it replaces
   ```

   Operation: `unison ./a ./b -batch -ignoreinodenumbers=true`, cwd at
   the state root, `UNISON` pointing at `<root>/unison`. One argv,
   frozen here, carried identically by the setup run of step 1 and by
   both probe runs (`-ignoreinodenumbers` is part of the operation, not
   an option a run may drop; its role is in the determinism forecast
   below). The same strings every run: unison derives its archive names
   from a hash of the root descriptors, so the root paths are part of
   the fixture (the cohort-2 borg argv lesson).

   Expected: `b/notes.txt` carries the changed bytes; `a/` untouched and
   `b/stable.txt` byte-identical; no `DANGER.README` after a clean run;
   the archive files under `unison/` updated. The propagation's write
   path is the reason this target has a slot: the local update goes
   through `renameLocal` (files.ml), which runs `Stasher.backup`
   (files.ml:321), `writeCommitLog` (files.ml:322), a rename moving the
   live target aside (renameLocal(1), files.ml:326), a rename moving the
   new content in (renameLocal(2), files.ml:337), `clearCommitLog`, then
   the temp's deletion. Five mutating steps with the final path exposed
   between two of them. The other branch is a single rename
   (renameLocal(3), files.ml:346). **What the commit log buys, stated as
   the source has it**: the next invocation detects a leftover
   `DANGER.README` and refuses with a Fatal error naming the involved
   paths and instructing their inspection and the notice's deletion
   (files.ml:70, files.ml:30-46). There is no automatic replay. The
   checker rules section below carries the owner's ruling on what that
   means for rule 9.

   **Copy-mechanism forecast (rule 16), the wall this target entered
   with.** The temp file that feeds the rename pair is filled by
   unison's C copy stub, which tries `ioctl(FICLONE)`, then
   `copy_file_range` through the raw `syscall(3)` entry point
   (copy_stubs.c:199), then `sendfile` (:204), then a read/write loop;
   the first three are invisible to the shim. **The ruled apparatus is
   the same `seccomp-enosys.json` as himalaya's**: seccomp filters at
   the kernel boundary, so it catches the `syscall(3)` spelling exactly
   as it catches the libc one, which is why one profile lifts both
   targets' walls. The profile also answers `ioctl` with ENOTTY **for
   the FICLONE request argument alone** (an arg-filtered rule, value
   0x40049409), so the reflink arm fails by construction rather than by
   relying on the container filesystem's lack of reflink support; every
   other ioctl passes through untouched.

   **Determinism forecast, from the commissioned source reading
   (`SCOUT-ROWS-SLOT2.md`, 2026-08-23), with one residue no apparatus
   covers.** What the archive marshals is `update.mli`'s type:
   properties, fingerprint, an inode stamp, a resource stamp. The inode
   stamp is removed by **unison's own documented preference
   `ignoreinodenumbers` (alias `pretendwin`)**, fileinfo.ml:231; note it
   is NOT `fastcheck`, which chooses how files are compared and leaves
   inodes in the archive. That preference is on the frozen operation
   argv above, free-tier apparatus. ctime never enters the archive
   (props.ml:672,694). mtime enters via the properties and is
   fixture-pinned. Two nondeterminism sources remain: **`freshDirStamp`**
   (props.ml:1575-1585) folds `(gettimeofday + √2·getpid)·1000 + the
   directory's inode` into one number stored in a changed directory's
   archived properties. Clock and pid fall to libfaketime and
   `pin-getpid.c` (the same two interpositions himalaya's plan declares,
   owner-gated), **but the directory inode is not coverable by any
   declared apparatus and `ignoreinodenumbers` does not reach this
   path**. Whether restored pre-states reproduce inodes on the container
   filesystem is exactly what the probe's two-run comparison measures; a
   split that survives the declared apparatus is a named wall of the
   nondeterministic-writer class, recorded at probe time, costing no
   define. Lock files mint their intermediate name from the pid
   (lock.ml:47; `pin-getpid` covers it); the fingerprint cache compares
   by inode stamp (fpcache.ml:253; whether `ignoreinodenumbers` empties
   that too is a probe reading); `DANGER.README` carries only the three
   paths (files.ml:30-46), nothing volatile.

   **One measured caution about the apparatus itself**:
   `Fileinfo.unchanged` takes the current time at second resolution and,
   when a file's mtime equals it, sleeps one second and reports the file
   changed (fileinfo.ml:246-249). A frozen clock can therefore change
   the target's behaviour; whether that branch is never taken or taken
   for every file depends on what mtimes the restored pre-state carries
   relative to the frozen instant. The probe's first reading under
   faketime measures this rather than assuming it, the
   normalisation-erases-the-anomaly caution applied to our own
   apparatus.

   Ambient: `HOME` at a reset-between-runs path shown in the transcript
   (`UNISON` is set explicitly either way).

A target that fails its probe records a **named wall**: which condition
failed and the raw evidence. Every target installs at the current
upstream stable (Versions below), so the latest-stable recheck a wall
requires before being called terminal is inherent.

## Apparatus policy (frozen before any run)

Three tiers, unchanged from cohort 3:

- **Configuration and environment pinning**: free, uses only switches the
  target documents, declared where used.
- **Pre-declared, used only on the named refusal**: the CPython sendfile
  fallback (`sitecustomize` setting `shutil._USE_CP_SENDFILE = False`)
  for any Python target, on `unsupported_syscall_observed: sendfile`
  only.
- **Interposition (clock, entropy, or identity) is a per-target owner
  decision.** The image carries libfaketime; this cohort adds two
  committed candidates that both targets' plans name (`pin-getpid.c`
  for the pid each target folds into its on-disk names or stamps, and
  `seccomp-enosys.json` for the kernel-side copy paths the shim cannot
  see), each of which must be seen to answer a measured split or
  refusal in the probe transcript before a define carries it. Apparatus
  discovered mid-probe is an amendment that must land before that
  target's first contact.

Whatever the apparatus: **a finding must reproduce against the stock tool
with no apparatus beyond strace fault injection before it is claimed or
reported**, unchanged from cohorts 2 and 3.

## The mini-seal, the claim reading, and the checker rules

The mini-seal is cohort 2's, sharpened for #140, read with
`spike/cohort4/` paths, and extended as cohort 3 extended it. The
operative sentences, inside this freeze rather than behind a reference:

- No engine explore before the target's complete define (toml + checker +
  setup + launcher) is on main; a define revision is a new target
  directory; **a FAIL freezes the define**: later revisions cannot
  produce a criterion-1 claim for that target, and a post-FAIL revision
  is a record-only artifact, stated in advance so it is not re-litigated
  with a fresh FAIL in hand (`PREP.md` §3 B2).
- **An amendment made after a target's first explore cannot change how
  that target's outcome is read, and neither can one made after its
  probe.**
- The checker runs directly on the crashed state; documented recovery
  first, then assert; every leg seen red once, separately; every
  assertion holds on the un-killed baseline. Checkers go through the
  target's own commands: the owner's 2026-08-22 rule-9 ruling, no
  exception clause. **For unison the owner ruled (2026-08-23, after the
  replay misreading above was corrected) that this is satisfied as
  follows**: the Fatal refusal of a post-crash invocation is itself a
  tool-command assert leg (the tool detecting its own dangerous state);
  the recovery step preceding the integrity assert is the one the tool's
  own written notice prescribes, namely deleting `DANGER.README`, the
  single non-tool action, followed by re-running the tool, whose re-scan
  and reconciliation are the read-back.
- At claim time the transcript includes `spike/assisted/verify-assisted.sh
  spike/cohort4/<target>` green and `git log --first-parent -p --
  spike/cohort4/PROTOCOL.md`: every post-freeze amendment visible inside
  the claim.

**Claim reading, frozen before the first explore** (#231 merged
2026-08-22, ADR 0020; the rule `PROTOCOL-DRAFT.md` drafted, verbatim):

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
are not re-read, and the FAIL-freeze rule still binds. `checker_earliest`
changes which world is the exhibit within a run, never which runs are
eligible.

Everything downstream of a candidate is unchanged from the standing
gates: novelty search with a positive control, per-report owner approval
before any upstream filing, author confirmation, fix, replayed regression
case.

## Versions and image

The image (`Dockerfile` here) has an apt layer pinned by BUILD, not by
manifest; the targets are exact-pinned. **himalaya is built from source
in the image, on purpose and with this disclosure carried into any wall,
FAIL, or report: the distributed binaries are static cross-builds, which
`LD_PRELOAD` cannot enter (the aarch64-linux release artifact was
downloaded and read as statically linked ELF during this freeze's
review), so the measured binary is a glibc-dynamic self-build of the same
v2.1.0 tree with the same default feature set. The delta to the
distributed artifact is linkage, not features.** The pin chain, each link
machine-verified: the v2.1.0 tag dereferences to commit
`ca88bee08ad2e92127b46dc6200d1e8201885156` (content-addressed, verified
at fetch); the copied tree is re-verified in the build against a sorted
per-file sha256 digest; the crate closure is vendored with `cargo vendor
--locked` and re-verified by cargo itself at build time against the
checksums in the tree's own committed Cargo.lock; the built binary must
be dynamically linked against glibc or the build fails (the `ldd`
assertion in the Dockerfile). rust 1.98.0 builds it, from the same
channel-manifest sha256 pin as cohort 3, and stays in the build stage:
the runtime image carries the himalaya binary, not cargo.

**unison is also built from source, for a different disclosed reason:
upstream publishes no aarch64-linux binary at all** (measured 2026-08-23:
nine release assets, macOS arm64 and x86_64/i386 Linux only), so on this
architecture a build from the pinned source is the install path, not a
substitution for one. The pin: the v2.54.0 tag names commit
`b1a49141e7eb5334e31efcf4d08073c192d6c1ae` directly (verified at fetch),
the copied tree is re-verified against the same style of per-file digest,
and the build is INSTALL.md's own `make` with the image's apt OCaml
(trixie's 5.3.0; the minimum is 4.08). lablgtk3 is deliberately absent,
which is what selects the text UI. The same `ldd` assertion applies: a
static unison would reproduce himalaya's distribution wall by accident,
so it fails the build instead.

The committed `freeze-build.txt` is the transcript of the freeze build
and the only pre-freeze target contact; the versions that actually run
are re-recorded in each probe transcript and RUNLOG. The digest and pin
checks in the Dockerfile and `fetch-artifacts.sh` were each shown red
once against a synthetic mutation before being trusted
(`guard-reds.txt`).

## Reporting, and delivery

Each upstream report is its own owner-approved gate; nothing in this
cohort authorises contact. The standing table of what has been filed and
what has come back is `spike/upstream-report-status.sh`, which measures
rather than remembers.

**Two of the writes a filing needs are held to each other by CI (#297).** A
report that goes out gets a row in `spike/upstream-reports.tsv` —
`owner/repo`, number, `standing` or `withdrawn`, and the finding spelled
the way `docs/target-classes.md` spells that tool — and an
`<!-- upstream-report: owner/repo#N -->` marker on that tool's row in
`docs/target-classes.md`. `spike/check-upstream-ledger.sh` refuses when
one record names a filing the other does not, when a marker sits on some
other tool's row, and when the ledger does not parse the way its own
header describes, so forgetting either write is red rather than quiet.
Before this the list lived in the status script as a literal, and the
cohort-4 close depended on remembering to edit it by hand (PR #253):
nothing asked, and six of seven printed exactly like six of six.

**A cohort tool needs a third write, held separately**: the disposition
row in `spike/unknown-rate/outcome-map.tsv` that `count.py` already
requires for any corpus tool whose defines come from a cohort. Nothing ties that row's disposition
to this ledger's status, so the two can drift — the checker's subject is
the ledger and the markers, not the corpus map.

What the two records cannot see is a filing written into neither.
**Prose is not one of the records**: a row in `docs/target-classes.md`
written the way the standing six are written, naming a report in its text
and carrying no marker, is invisible to the check. That is the recorded
accident with only its prose half done, so the residue is narrower than
"not in either file" but it is not empty. Deriving the set from a tracker
instead was measured and rejected: a withdrawn report and an unlisted one
have the same shape there, and the search is per-account rather than
per-project.

A withdrawn report keeps its row. It was filed, it exists on a tracker,
and the status column is what separates it from a filing nobody recorded;
`alecthomas/devtodo#9` is the one this project has.

**One lesson from the poetry #11019 close
(2026-08-23) is frozen here as a reporting requirement**: before any
report, measure and state the recovery paths that exist *outside* the
tool, and the conditions under which they do not apply. This is a
non-claim, leg-external measurement; it does not touch claim
eligibility. For these targets concretely: for himalaya, the conditions
under which data is lost before it reaches the synchronized side (send
queues, drafts, maildir-only configurations); for unison, whether a
damaged replica propagates to the healthy side as if it were a fresh
change, which would be the strongest form, the external recovery path
itself breaking.

Merges in this cohort go through `spike/merge-gate.sh`, read as a printed
verdict and never chained to the merge command. BUILDLOG entries open
when the work starts, not at PR time.
