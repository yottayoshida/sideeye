# The UNKNOWN rate, measured

v1.0 entry criterion 4 (`PRD.md`) requires the UNKNOWN rate on supported
targets to be **measured and published**, with a target threshold **set from
that data** — and DESIGN §18 names "UNKNOWN dominates" as a kill condition.
This page is the measurement's fixed rulebook and its published numbers. The
rules in this page were committed and merged **before** the sweep ran; the
results were merged after, in a separate PR, so the first-parent history
proves the order (the same shape `spike/assisted/verify-assisted.sh` checks
for assisted claims). Every number between the results markers is recomputed
from the committed reports by `spike/unknown-rate/count.py`, wired into the
acceptance suite — a published figure that drifts from its artifacts goes
red in CI.

## Why two groups

A single corpus of already-measured targets cannot carry this criterion.
The committed defines that reach verdicts today are the same defines whose
refusals drove the engine's own development — the assisted cohort stood at
4/5 UNKNOWN on 2026-08-14 and 1/5 one engine release later
(`spike/assisted/REMEASURE.md`), and #121/#122 name those exact refusals as
their motivation. Measuring only that set answers "did the engine catch up
with its own inputs" — the answer is near 0% before the sweep runs, and a
threshold set from it would be satisfied by construction. So:

- **A-group** — every committed, runnable define in the repository. Its
  rate is published **as the engine's development-input set**, and is *not*
  the threshold basis.
- **B-group** — targets this project has never run, selected mechanically
  (no hand-picking; see below). **The threshold is set from B-group data
  only.**
- A-group and B-group are never pooled; no combined headline number exists
  on this page or anywhere else.

## The rules (frozen before the sweep)

- **One trial = one committed explore invocation** (target × operation ×
  judge configuration), enumerated in `spike/unknown-rate/corpus.tsv`. The
  per-trial rate is primary; per-tool, per-class and per-judge slices are
  published beside it.
- **Axes**: `unknown_reason` (the closed set `docs/report-schema.md`
  documents — count.py parses the enum from that page, so the two docs hold
  each other), target class (`docs/target-classes.md` — its first table is
  the definition of "supported"), platform, and judge configuration
  (`l0` = built-in atomicity only, `l0c` = + declared checker; the axis
  matters because `checker_not_falsified` can only fire under `l0c`).
- **Small cells**: any slice with n < 5 prints counts only, never a
  percentage.
- **A PASS with 0 crash points** (a declared operation that performed
  nothing state-changing, e.g. topydo `ls`) stays in the denominator and is
  flagged in the per-trial table.
- **SETUP_ERROR is an apparatus failure, not a refusal**: fix the apparatus
  and re-run that trial; if unfixable, the row is published as excluded,
  with the reason. It never counts as UNKNOWN.
- **Strict oracle everywhere**: every trial runs with
  `--oracle /usr/bin/strace` and never `--allow-unverified`. The sweep
  manifest records each trial's full launcher argv; `count.py` reads only
  machine fields (never the report's prose accounts — #94 tracks the
  machine-readable evidence level for PASS).
- **Funnel walls (B-group)**: a mechanically-selected target that never
  reaches an explore is published as a wall row, outside the engine-rate
  denominator: **W1** install fails in the pinned container; **W2** its
  documentation names no local-file state (state lives in a server, a
  remote account, or hardware); **W3** its documentation names no
  non-interactive state-changing command. Grounds are quoted in
  `spike/unknown-rate/defines-b/<target>/NOTES.md`. The walls are data —
  they measure the acquisition funnel — but they are not engine refusals.
- **Outcome ratio** (issue #84's amendment): beside the UNKNOWN rate, the
  A-group FAIL verdicts are classified by their committed disposition
  (`spike/unknown-rate/outcome-map.tsv`: reported-upstream / withdrawn /
  kept-unreported), so a low UNKNOWN rate cannot silently coexist with a
  high false-positive rate. Third-party-contributed targets (#87) are not
  part of this measurement; if #87 ever supplies any, they are a separate,
  labeled sample — never pooled.

## The corpus

### A-group — 28 trials, 10 tools

| tool | class | defines | trials |
|---|---|---|---|
| topydo | Python CLI | campaign 1 declaration, 13 op tomls | 13 |
| abook | C CLI | campaign 2 declaration, 3 op tomls | 3 |
| khal | Python CLI | campaign 3 declaration, 3 op tomls | 3 |
| buku | Python + sqlite | assisted `buku-add.toml` | 1 |
| calcurse | C CLI | assisted `calcurse-purge.toml` | 1 |
| devtodo | C++ CLI | assisted `devtodo-remove.toml` | 1 |
| stow | Perl CLI | assisted `stow-unfold.toml` | 1 |
| timewarrior | C/C++ CLI | `spike/dogfood-timew.sh`, legs a/b | 2 |
| todoman | Python CLI | `spike/dogfood-todoman.sh`, legs a/b | 2 |
| watson | Python CLI | `spike/dogfood-watson/sideeye.toml` | 1 |

watson is **in** the denominator: "supported" is a class property
(`docs/target-classes.md`), watson is a Python CLI, and its known refusal
(`baseline_violates_invariant`) counts as an UNKNOWN — the honest
direction. **pass** runs as the control trial, outside every denominator:
its behavioral class (shell CLI over helper processes) has no recorded
verdict, so it is not a supported class.

### Exclusions (every one named, with the reason)

| candidate | why not in the corpus |
|---|---|
| `docs/ci-quickstart/sideeye.toml` | drives the demo toy, not a third-party tool |
| `spike/assisted/buku/inspection/inv.toml` | instrumentation from the buku-withdrawal analysis, not a corpus question |
| taskwarrior | in the supported table, but **no committed define exists** — only BUILDLOG prose. Authoring one today would be answer-known authoring: added to A it only lowers a rate that is already not the threshold basis; added to B it contaminates the threshold basis with a known PASS |
| omamori surface (`spike/dogfood-omamori-surface.sh`) | Rust is not a supported class (the first table); DESIGN §18's demand to re-run it before citation is answered by a follow-up issue, not smuggled into this measurement |
| hledger | its sweep refusal is sealed unread and it is the last blind-eligible candidate; even scouting it spends that (standing taint rule, `spike/README.md`) |
| khard | burned (campaign 2); its declaration history is public but its blindness is spent |

### B-group — 20 targets, machine-selected

The selection is `spike/unknown-rate/select-b.sh`: Debian bookworm's own
package metadata (debtags), filtered by a fixed predicate — `role::program`,
`implemented-in::` one of c / c++ / python / perl (the supported language
classes), `works-with::` pim or db (the file-backed-state family), minus
daemons (`interface::daemon`), X11/graphical interfaces, and `lib*`/`-dev`/
`-doc`/`-common` packaging names — then minus the committed name exclusions
(`b-exclusions.txt`: measured, tainted, sealed), deterministic sort, first
20. The generated pool and list are committed (`b-candidates.txt`,
`b-targets.txt`, `b-selection-record.txt`). No hand-picking happened at any
stage; whatever the predicate produced is the group.

**The predicate's bias is published, not denied**: `works-with::pim|db`
aims at the same file-backed-personal-data family the measured set came
from, and the alphabetical head of the pool happens to be heavy in
database-server tooling — which is why the funnel-wall rules exist. A
target that turns out to be out of domain becomes a W-row, never a silent
substitution.

**Taint note**: authoring a B-group define requires reading the target's
documentation, which makes these 20 targets ineligible for any future
blind campaign (the taint ledger's own rule). hledger is excluded by name
precisely so this measurement cannot spend the one remaining blind
candidate.

Each B-group target that passes the walls gets one uniform minimal define
(`defines-b/<t>/`): `setup.sh` seeds the state, `op.sh` is the one
representative state-changing operation named by the target's own
documentation, judge configuration `l0` (no checker), strict oracle. The
`sideeye preflight` answer (#77) is recorded beside each verdict as the
funnel instrument — in text + exit code, since preflight has no
machine-readable form yet (still open; `src/main.zig` names this issue for
it).

## Method

One sweep, one engine build (`zig build -Dtarget=aarch64-linux-gnu` from
the apparatus PR's merge), fresh containers per trial, driven by
`spike/unknown-rate/sweep.sh`. Apparatus identity (engine version + sha256,
shim sha256, image ids) is recorded in `artifacts/apparatus.txt` and per
trial in `artifacts/manifest.tsv`; the manifest also records each trial's
define digest, recomputed from the checkout by `count.py check` — "the
committed defines ran verbatim" is machine-checked. The images are pinned
by build, not by manifest (the base tags are mutable — the same honesty
note `spike/assisted/Dockerfile` carries), so environmental identity with
past runs is recorded, never claimed.

The campaign declarations run through
`spike/unknown-rate/launchers/campaign.sh`, **not** through the sealed
runners or `campaign-driver.sh` — campaigns 1–3 are consumed, this is an
open re-measurement, and the driver's preconditions (HEAD = Seal B) are
about blindness this sweep does not claim. What the launcher replicates
from each sealed runner is exactly what can move a verdict; the divergence
table:

| declaration | replicated | deliberately absent |
|---|---|---|
| topydo (bh1) | `HOME=/tmp/blind/home`, state roots `/tmp/blind/hunt/<op>` | HEAD/CLEAN env, `run-manifest.json` (verify-seals shapes) |
| abook (bh2) | `HOME=/tmp/blind2/home`, `unset CHECK_ABOOK CHECK_TIMEOUT`, roots `/tmp/blind2/hunt/<op>` | same |
| khal (bh3) | `HOME=/tmp/blind3/home`, `unset CHECK_KHAL CHECK_TIMEOUT`, roots `/tmp/blind3/hunt/<op>` | same |
| assisted ×5 | nothing to replicate — their committed `ops/explore.sh` launchers run as-is (the REMEASURE invocation) | — |
| timewarrior / todoman | nothing — the dogfood recipes run as-is with `RUN` pointed into the artifacts | — |
| watson | the committed toml + checker run from a staged byte-verbatim copy (its relative paths resolve against the working directory); `WATSON_DIR` set as the BUILDLOG run did | a committed launcher never existed — `launchers/watson.sh` is new apparatus, labeled |

## Platform

- **Measured**: Linux aarch64, in containers, on this page's sweep. That is
  the only platform with real-target measurements in this repository (CI's
  x86_64 job runs the acceptance toys, not real targets).
- **macOS**: derived, not measured. The mechanism is structural — no oracle
  exists on macOS (SIP refuses dtruss), and `requireCompleteness`
  (src/main.zig) guards every path that ends in PASS — so under this page's
  strict protocol every Linux PASS derives to UNKNOWN
  (`completeness_not_verified`) while a FAIL stands on its own evidence.
  The derived rate is printed from that formula by `count.py`, never
  hand-written, and is labeled derived wherever it appears.
- **Linux x86_64**: no real-target measurement exists; named absent.

## Results

<!-- unknown-rate:results:begin -->
_Not yet measured: the sweep has not run. This line is asserted by count.py check._
<!-- unknown-rate:results:end -->

## Threshold

_Set after the B-group data exists, from that data, by the project owner —
in that order. Once set it does not move: a measured rate that fails the
threshold the data itself set is DESIGN §18 material, not a reason to
adjust the threshold (issue #84, step 4)._

## Limitations, out loud

- The A-group rate measures the engine against its own development inputs;
  it cannot say how often a *new* target reaches a verdict. That is the
  B-group's job, and the B-group's own limit is its size (~a dozen engine
  trials) and its predicate's family bias, both published above.
- The B-group's minimal defines are authored by this project from each
  target's documentation; a poorly-chosen operation depresses nothing (a
  bad setup is a SETUP_ERROR, excluded loudly) but an unrepresentative one
  narrows what the trial can see. The uniform one-op protocol trades
  coverage for comparability, deliberately.
- One sweep, one platform, one engine build. The numbers date; the page
  records when they were produced, and the corpus can be re-swept against
  a later engine by re-running the committed apparatus.
