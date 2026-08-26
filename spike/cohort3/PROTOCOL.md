# Criterion 1, third cohort — the campaign protocol (#209)

This directory is a criterion-1 search under the provenance gate (ADR 0017,
tracked by #140). Cohort 2 (`spike/cohort2/`) took the search to mature
software with its own transaction machinery and recorded two
null-with-verdicts, three walls and zero candidates under pre-frozen rules.
This cohort points the same discipline at the opposite end on purpose:
**the ordinary stateful CLI sweet spot the tool was designed for** —
current, actively maintained tools whose state is a handful of plain
files, mutated non-interactively, with no transaction engine between the
write and the disk.

Everything below was committed before any probe, explore, or
target-behavior measurement. Pre-freeze contact with the targets was
install plus `--version` only — the standing pre-window rule — and it
happened once, in this file's own image build (versions recorded under
Versions below). The rules that decide what counts are not allowed to know
the results.

## Targets and selection (rules cleared 2026-08-22)

Selection followed the owner's cohort-3 ruleset, thirteen conditions set
and sharpened on 2026-08-21 and frozen with their evidence in
<https://github.com/yottayoshida/sideeye/issues/209>: (1) ≥1,000 GitHub
stars; (2) release or substantive development activity within 6 months;
(3) multiple sustained contributors; (4) CLI as the primary interface;
(5) locally-stored primary data users do not want to lose; (6) main state
in plain text / JSON / YAML / TOML / a directory tree / a few ordinary
files; (7) no SQLite, embedded DB, or own transaction engine as the main
store; (8) non-interactive mutating commands; (9) a checker writable with
the target itself; (10) dynamic linking and single-threaded-ish behavior
expected within the engine's observation range (verified by probe, not
assumed); (11) maintainer responsiveness within ≤1 week, measured on real
issues; (12) currently used, not legacy-only; (13) language diversity
across the cohort. The owner approved the list on 2026-08-22; the
evidence — stars, activity, and first-response receipts with issue
numbers — is recorded on #209 and not repeated here.

**Order, frozen: cargo → black → rustfmt → poetry → papis.**
The matrix is deliberate: two languages × two tool classes
(dependency-manifest editors: cargo/poetry; in-place formatters:
black/rustfmt) plus one personal-data store (papis).

**The bench and the refill rule (new in this cohort).** Cohort 2's
composition was frozen with no substitutions; a wall consumed its slot.
This cohort's purpose is measuring value in the sweet spot, so a probe
wall must not consume the cohort:

- The bench, in order: **taplo → unison → sc-im**.
- The algorithm, fixed so no outcome can shrink or reorder the measured
  set after the fact:
  1. **All five primary targets are probed, in the frozen order,
     unconditionally.** A wall on an earlier primary removes nothing
     later, and reaching four passes early skips nothing — papis is
     probed even if the first four all pass.
  2. After the fifth primary's verdict: if fewer than four primaries
     passed, the bench head is promoted — one target at a time, in bench
     order — until the passed count reaches four or the bench is
     exhausted.
  3. Promotion is a three-step gate, in this order, all before any
     measured contact with the promoted target: (a) rules 1–13
     re-measured at promotion time and posted to #209 — a bench target
     that fails them is skipped, recorded; (b) its probe plan frozen by
     an amendment PR to this file; (c) the probe. The amendment
     discipline below applies.
- Probes are engine-free and kill-free; a wall costs one committed
  transcript. The cohort therefore cannot end "we could not measure" —
  the worst recorded outcome is a smaller measured set plus named walls,
  publishable under #140's honesty note exactly as cohort 2's ledger was.

## Provenance: assisted, scout named

Every claim from this cohort carries the assisted label. The scout is the
targets' own public documentation, read 2026-08-22 and recorded in #209
and the implementation plan: the cargo-add manual (what the command
promises to edit), black's usage documentation (`--no-cache`, worker
behavior), the poetry CLI reference (`add --lock`, path dependencies), the
papis configuration and info-file documentation (`time-stamp`,
`use-cache`, `papis_id`), and the Rust channel manifest (artifact
contents and hashes). No external analysis was used for this selection.
Blind is off the table for the whole cohort and no run under this protocol
may ever be described with that word.

## The probe gate

The probe gate of cohort 2 applies (`spike/cohort2/PROTOCOL.md`, "The
probe gate") **with one substitution, stated below: the positive
control**. What carries over unchanged: each target, in cohort order,
gets an engine-free probe before its define is written — normal execution
only, no kill, no crash, no checker, so no failure of any target can be
observed and the provenance gate stays clean; one committed transcript
per target (`probes/<target>.txt`) must pin all seven conditions defined
there, all seven or the probe has not passed. Cohort 2's designation of
unpinned `borg create` as the control names a tool this image does not
carry, which is why the control — and only the control — is replaced.

Harness continuity, stated precisely:

- The judging predicates are `spike/cohort2/probes/lib.sh`, sourced in
  place — no fork, no copy. The cohort-2 predicate drills and this
  cohort's runs therefore exercise the same lines.
- **The drills re-run under this image** (`probes/drills.txt` here) before
  any probe verdict counts: a predicate's red was measured on cohort 2's
  image, and an image change is a harness change.
- **Positive control, first**: cohort 2's control (unpinned `borg create`)
  is not in this image. The control here is a synthetic operation that
  writes wall-clock bytes into its state root, run through the full
  determinism check, which must split. The predicate path is identical to
  the targets'; only the operation is synthetic, and the transcript says
  so.
- Cohort 2's run scripts called `mutating_paths` — an undefined name left
  by the fail-closed rebuild's rename to `closure_paths` — in their
  informational path listing, and the committed transcripts carry the
  `not found` line. It was display only (condition 6 is judged by
  `closure_check`), the cohort-2 verdicts stand, and the cohort-2 record
  stays untouched; this cohort's run scripts call `closure_paths`. The
  fact is recorded in BUILDLOG (2026-08-22).

### Probe plans, fixed here (operation, pre-state, state root, expected artifacts)

Apparatus plumbing (exact env variable names, temp paths) may be corrected
at probe time with the correction recorded in the transcript; the
operation, the pre-state shape **including the fixture bytes inlined
below**, the candidate state root and the expected artifacts are frozen
here. Two general rules close the gaps a loose plan would leave:

- **The fixture contents are part of this freeze.** Where a plan below
  says a file has fixed content, that content is written out here — a
  probe implementation may not substitute its own. The run scripts and
  the materialized fixtures are committed with the transcripts in the
  probes PR, where this section is the standard they are read against.
- **No "expected formatted output" exists for the formatter targets, on
  purpose**: computing one would itself be pre-freeze target contact.
  The formatter oracles are the tool's own `--check` contract plus the
  determinism condition — the output must satisfy the tool's check and
  be byte-identical across the two runs; its exact bytes are recorded by
  the probe, not predicted by this plan.

1. **cargo** — pre-state: an application directory (the state root)
   holding `src/lib.rs` with content `pub fn probe() -> u32 { 42 }`, a
   `Cargo.lock` generated at setup by `cargo generate-lockfile
   --offline`, and this `Cargo.toml`:

   ```toml
   [package]
   name = "app"
   version = "0.1.0"
   edition = "2021"
   ```

   A path-dependency crate as a fixture **outside** the root: directory
   `depcrate/` with `src/lib.rs` containing `pub fn dep() -> u32 { 7 }`
   and this `Cargo.toml`:

   ```toml
   [package]
   name = "depcrate"
   version = "0.1.0"
   edition = "2021"
   ```

   Operation: `cargo add --offline --path ../depcrate`. Expected:
   `Cargo.toml` names depcrate exactly once, and `cargo metadata
   --offline` lists it. **Whether `Cargo.lock` also updates is measured
   and recorded, not expected** — the cargo-add manual promises manifest
   editing only (read 2026-08-22); the lock sits inside the root either
   way, so determinism and closure judge it. Ambient: `CARGO_HOME` at a
   reset-between-runs path; the reset shown in the transcript.
2. **black** — pre-state: one file `probe.py`, alone in the state root,
   with exactly these bytes (deliberately unformatted):

   ```python
   x=[1,2,3]
   def f(a,b):
       return {'k':a+b,'l':[v   for v in x]}
   y = f( 1 ,2 )
   ```

   Operation: `black --no-cache probe.py` (single file, in place;
   `--no-cache` is black's own flag — the cache class is removed by not
   creating one). Expected: the file's bytes change (the fixture is not
   already black-formatted), and `black --check --no-cache probe.py`
   exits 0 afterward.
3. **rustfmt** — pre-state: one file `probe.rs`, alone in the state
   root, with exactly these bytes:

   ```rust
   fn main(){let x=vec![1,2,3];let s:u32=x.iter().sum();println!("{}",s);}
   ```

   Operation: `rustfmt probe.rs` (in place). Expected: the file's bytes
   change, and `rustfmt --check probe.rs` exits 0 afterward.
4. **poetry** — pre-state: a project directory (the state root) holding
   a `poetry.lock` generated at setup by `poetry lock` and this
   `pyproject.toml` (package-mode false: a dependency-set project, no
   package of its own to build):

   ```toml
   [project]
   name = "app"
   version = "0.1.0"
   requires-python = ">=3.13"

   [tool.poetry]
   package-mode = false
   ```

   A path-dependency package as a fixture outside the root: directory
   `deppkg/` with an empty `deppkg/__init__.py` and this
   `pyproject.toml`:

   ```toml
   [project]
   name = "deppkg"
   version = "0.1.0"
   requires-python = ">=3.13"

   [build-system]
   requires = ["poetry-core"]
   build-backend = "poetry.core.masonry.api"
   ```

   Operation: `poetry add --lock ../deppkg` (`--lock` updates the
   manifest and lockfile without installing — the mutation under test is
   exactly the two files). Expected: `pyproject.toml` and `poetry.lock`
   both name deppkg, and `poetry check --lock` exits 0. Environment:
   `POETRY_CACHE_DIR` and `POETRY_CONFIG_DIR` at reset-between-runs
   ambient paths; `PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring`
   (the fully-qualified name — a bare `null` is not a backend).
5. **papis** — pre-state: a papis configuration with `time-stamp: False`
   (no add-time stamping; default is True) and `use-cache: False` (no
   cache layer exists at all — stronger than relocating it; the library
   is small), XDG directories pinned; the library directory is the state
   root and holds one existing document, added at setup from a fixture
   file with content `existing document, fixed bytes` and this frozen
   metadata fixture (`existing-meta.yaml`):

   ```yaml
   title: Existing
   author: Probe Author
   papis_id: existing0001
   ```

   Operation: `papis add --batch --from yaml <probe-meta.yaml>
   --folder-name probe-doc` of a second fixture file **outside** the
   root with content `probe document, fixed bytes`, where
   `probe-meta.yaml` is this frozen metadata fixture:

   ```yaml
   title: Probe
   author: Probe Author
   year: 2026
   papis_id: probe0001
   ```

   papis auto-generates `papis_id` when missing; whether the explicit
   value pins it is exactly what the determinism condition measures.
   Expected: exactly one new document directory (an `info.yaml` plus the
   copied file), and papis reads it back — `papis list --all --format`
   returns the fixture's title and papis_id (the bare listing prints
   folder paths only, measured at probe time). *(Amended before this
   target's accepted probe, 2026-08-22, in one measured step: the
   original plan carried the metadata via `--set` key-value flags and no
   `--from`. Its probe (`probes/papis-v1.txt`) failed conditions 1-4:
   with no `--from`, `papis add` runs importer auto-matching on the
   file's URI, papis 0.16's arxiv importer treats the path as a
   candidate arXiv identifier and **validates it against arxiv.org over
   HTTPS** — `add.py` line 483 → `get_matching_importers_by_uri` →
   `arxiv.py is_arxivid` → a GET of `/abs/<the local path>` — and a
   failed fetch fails the whole add (what the transcript measured is TLS
   certificate verification failing under this machine's intercepting
   proxy; the network was reached and the fetch still died — any fetch
   failure propagates the same way, the exceptions being uncaught). The importer set has no
   config filter (measured in `papis/importer/__init__.py`: every
   plugin is tried, exceptions propagate). Passing `--from` skips URI
   matching structurally (`add.py`: `if from_importer:` precedes the
   matching branch), and the `yaml` importer reads a local fixture —
   the same fixed metadata, no network. The v1 probe is read as what it
   is: a failed probe of the original plan, kept as evidence.)*

A target that fails its probe records a **named wall**: which condition
failed and the raw evidence. Every target here installs at the current
upstream stable (Versions below), so the latest-stable recheck that
cohort 2 required before calling a wall terminal is inherent: the measured
binary is the current release.

## Apparatus policy (frozen before any run)

Three tiers, in increasing order of gate:

- **Configuration and environment pinning** — cache off or relocated,
  keyring nulled, timestamp options off, fixed metadata via the target's
  own flags — is free apparatus: it uses only switches the target
  documents, and each use is declared in the probe plans above or in the
  define that carries it.
- **The CPython sendfile fallback** (a launcher `sitecustomize` setting
  `shutil._USE_CP_SENDFILE = False`) is pre-declared here for the Python
  targets, to be used only when the engine refuses on
  `unsupported_syscall_observed: sendfile` — the hg-r3/borg-r3 precedent,
  approved in the implementation plan (2026-08-22).
  **Superseded from trace contract v11 (2026-08-26, #244): that refusal no
  longer happens.** The shim interposes `sendfile` and `copy_file_range` and
  the oracle classifies them, so a run reaching either is judged rather than
  refused, and this apparatus has no triggering condition left. A cohort
  running under v11 or later should not declare it; the paragraph stays
  because hg-r3 and borg-r3 were run under it and their records cite it.
  Any define using it
  says so.
- **Clock or entropy interposition** (libfaketime, pins on
  `time.monotonic` / `os.urandom`) is a **per-target owner decision**,
  the #200 precedent. The image carries libfaketime so such a decision
  does not require a rebuild, but nothing below uses it without that
  gate.

Whatever the apparatus: **a finding must reproduce against the stock tool
with no apparatus beyond strace fault injection before it is claimed or
reported** — unchanged from cohort 2.

## The mini-seal, the claim reading, and the checker rules

The three sections of `spike/cohort2/PROTOCOL.md` — "The mini-seal,
sharpened for #140", "Claim reading, frozen before the first explore",
and "Checker rules for this cohort" — apply to this cohort verbatim, with
every `spike/cohort2/` path read as `spike/cohort3/`. Re-stated here so
the operative sentences are inside this freeze rather than behind a
reference:

- No engine explore before the target's complete define (toml + checker +
  setup + launcher) is on main; a define revision is a new target
  directory; **a FAIL freezes the define** — later revisions cannot
  produce a criterion-1 claim for that target. After a revision merges and
  before exploring: `git log --first-parent --diff-filter=ACR --
  spike/cohort3/<dir>` must show the introduction standing on main.
- A **criterion-1 candidate** is a run whose saved case — the earliest
  violating world — has the **declared checker** as its violated
  invariant. An **L0-only FAIL is a precision-limit observation, recorded
  and never claimed** (#35 ruling, applied cohort-wide in advance).
- The checker runs directly on the crashed state; documented recovery
  first, then assert; every leg seen red once, separately; every
  assertion holds on the un-killed baseline.
- The honesty bounds are cohort 2's, unchanged: discipline plus public
  history, not machinery. At claim time the transcript includes
  `spike/assisted/verify-assisted.sh spike/cohort3/<target>` green and
  `git log --first-parent -p -- spike/cohort3/PROTOCOL.md` — full
  patches, every post-freeze amendment visible inside the claim. **An
  amendment made after a target's first explore cannot change how that
  target's outcome is read**, and (this cohort's addition) **an amendment
  made after a target's probe cannot change how that probe is read** —
  the promotion amendments of the refill rule land before their target's
  first contact, which is what keeps them on the right side of this line.

Everything downstream of a candidate is unchanged from the standing
gates: novelty search with a positive control, per-report owner approval
before any upstream filing, author confirmation, fix, replayed regression
case.

## Versions

The image (`Dockerfile` here) has an apt layer pinned by BUILD, not by
manifest; the five targets are exact-pinned by hash. The pins: rust
1.98.0 from the Rust channel manifest's published sha256 (read
2026-08-22); the combined standalone tarball bundles rustfmt-preview —
measured in the shipped artifact's own `components` file after the R1
review caught an earlier claim to the contrary that had read rustup's
network component model instead of the artifact; black 26.5.1, poetry
2.4.1 and papis 0.16.0 with their
full 74-package closure locked by uv (`pins-all.txt`, PyPI-published
hashes, enforced at host download and again at image install by pip's
`--require-hashes`). Exactly two packages in the closure ship no wheel at
their locked versions and enter as pure-Python sdists (measured
2026-08-22): bibtexparser 1.4.4 and python-doi 0.2.0.

The freeze build (2026-08-22, arm64) measured: cargo 1.98.0, rustc
1.98.0, rustfmt 1.9.0-stable (rustfmt's own version scheme; the
combined tarball's rustfmt-preview component), black 26.5.1, poetry
2.4.1, papis 0.16.0, strace 6.13, Python 3.13.5. The committed
`freeze-build.txt` is the transcript of that pass. It is
the only pre-freeze target contact. The versions that actually run are
re-recorded in each probe transcript and RUNLOG. Every target is the
current upstream stable at the freeze date, so any wall or FAIL is
already measured on the release a report would name.
