# The UNKNOWN rate, measured

v1.0 entry criterion 4 (`PRD.md`) requires the UNKNOWN rate on supported
targets to be **measured and published**, with a target threshold **set from
that data** — and DESIGN §18 names "UNKNOWN dominates" as a kill condition.
This page is the measurement's fixed rulebook and its published numbers, and
it lands in two merges: the rulebook and apparatus first, the sweep's
results after, in a separate PR — so the first-parent history proves the
corpus predates the numbers (the same shape
`spike/assisted/verify-assisted.sh` checks for assisted claims). Until the
results PR merges, the Results section below carries an explicit
not-yet-measured placeholder that the CI gate asserts; everything else on
this page describes procedure, not completed measurement. Every number that
eventually appears between the results markers is recomputed from the
committed reports by `spike/unknown-rate/count.py`, wired into the
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
| omamori surface (`spike/dogfood-omamori-surface.sh`) | Rust is not a supported class (the first table); DESIGN §18's demand to re-run it before citation was answered by #141 (re-measured 2026-08-16, all four writers PASS under v10), separately from this measurement |
| omamori dogfood (`spike/dogfood-omamori.sh`) | same class exclusion as the surface script — Rust is outside the first table |
| `spike/dogfood-timew-replay.sh` | records and replays one case as a single replay-stability measurement (since #82 also run on every push to main and every pull request by the timew-regression CI job); its exploration exists to feed the replay legs, and no run of it joins this page's frozen corpus |
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
documentation — the same kind of recorded contact the campaign taint
ledger disqualifies blind candidates for. **This page is the record**: the
20 names in `b-targets.txt` are hereby documented as read by this project,
and any future blind-candidate selection must treat this list the way the
campaign ledgers treat theirs. hledger is excluded by name precisely so
this measurement cannot spend the one remaining blind candidate.

Each B-group target that passes the walls gets one uniform minimal define
(`defines-b/<t>/`): `setup.sh` seeds the state, the operation is the one
representative state-changing command named by the target's own
documentation, judge configuration `l0` (no checker), strict oracle. The
operation has two committed spellings, and the difference was measured
while authoring (BUILDLOG 2026-08-16): `op.txt` — one static command line
(with the literal `$TOY_STATE` standing for the state directory, expanded
by the launcher) that the engine spawns directly — is used wherever the
documented invocation fits the engine's space-split contract; `op.sh` is
the ADR 0007 fallback for invocations that cannot be spelled that way (an
argument carrying a space — hnb; a stdin redirect — lbdb). A script
wrapper that performs nothing state-changing before its `exec` is an image
change the v10 observation rules refuse structurally, so for the two
`op.sh` targets that refusal, if it comes, is the trial's honest verdict:
the define budget could not spell the target inside the contract. The
`sideeye preflight` answer (#77) is recorded beside each verdict as the
funnel instrument — in text + exit code, since preflight has no
machine-readable form yet (still open; `src/main.zig` names this issue for
it).

## Method

The protocol: one sweep, one engine build (`zig build
-Dtarget=aarch64-linux-gnu` at the apparatus PR's merge), fresh containers
per trial, driven by `spike/unknown-rate/sweep.sh` — the repo mounted
read-only, with only the artifacts tree writable. Apparatus identity
(engine version + sha256, shim sha256, image ids) goes into
`artifacts/apparatus.txt` and per trial into `artifacts/manifest.tsv`; the
manifest also records each trial's define digest, which `count.py check`
recomputes from the checkout — that is how "the committed defines ran
verbatim" becomes machine-checked once the artifacts exist. The images are
pinned by build, not by manifest (the base tags are mutable — the same
honesty note `spike/assisted/Dockerfile` carries), so environmental
identity with past runs is recorded, never claimed.

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
| watson | the committed toml + checker run from a staged copy (its relative paths resolve against the working directory); `WATSON_DIR` set as the BUILDLOG run did. The launcher records the staged copies' sha256 beside the report, and the manifest's define digest covers the checkout originals — two records a reader can compare; the copy step itself is `cp` | a committed launcher never existed — `launchers/watson.sh` is new apparatus, labeled |

## Platform

- **The measured platform** is Linux aarch64, in containers — this page's
  sweep runs there, and it is the only platform with real-target
  measurements in this repository (CI's x86_64 job runs the acceptance
  toys, not real targets).
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
_Generated by `spike/unknown-rate/count.py emit` — do not edit between the markers._

#### A-group (the engine's development input — not the threshold basis)

| trial | tool | class | judge | verdict | unknown_reason |
|---|---|---|---|---|---|
| a-topydo-add | topydo | python-cli | l0c | FAIL | - |
| a-topydo-append | topydo | python-cli | l0c | FAIL | - |
| a-topydo-del | topydo | python-cli | l0c | FAIL | - |
| a-topydo-dep-add | topydo | python-cli | l0c | FAIL | - |
| a-topydo-dep-rm | topydo | python-cli | l0c | FAIL | - |
| a-topydo-depri | topydo | python-cli | l0c | FAIL | - |
| a-topydo-do | topydo | python-cli | l0c | FAIL | - |
| a-topydo-ls | topydo | python-cli | l0c | PASS (0 crash points) | - |
| a-topydo-postpone | topydo | python-cli | l0c | FAIL | - |
| a-topydo-pri | topydo | python-cli | l0c | FAIL | - |
| a-topydo-revert | topydo | python-cli | l0c | FAIL | - |
| a-topydo-sort | topydo | python-cli | l0c | FAIL | - |
| a-topydo-tag | topydo | python-cli | l0c | FAIL | - |
| a-abook-import | abook | c-cli | l0c | PASS | - |
| a-abook-export | abook | c-cli | l0c | PASS | - |
| a-abook-refused | abook | c-cli | l0c | PASS | - |
| a-khal-import | khal | python-cli | l0c | PASS | - |
| a-khal-update | khal | python-cli | l0c | PASS | - |
| a-khal-new | khal | python-cli | l0c | PASS | - |
| a-buku-add | buku | python-sqlite | l0c | FAIL | - |
| a-calcurse-purge | calcurse | c-cli | l0c | FAIL | - |
| a-devtodo-remove | devtodo | cxx-cli | l0c | FAIL | - |
| a-stow-unfold | stow | perl-cli | l0c | FAIL | - |
| a-watson-add | watson | python-cli | l0c | UNKNOWN | baseline_violates_invariant |
| a-timew-a | timewarrior | c-cpp-cli | l0 | PASS | - |
| a-timew-b | timewarrior | c-cpp-cli | l0c | FAIL | - |
| a-todoman-a | todoman | python-cli | l0 | PASS | - |
| a-todoman-b | todoman | python-cli | l0c | PASS | - |

UNKNOWN rate, per-trial: **1/28 (3.6%)**

| slice | UNKNOWN |
|---|---|
| tool: abook | 0/3 (counts only, n<5) |
| tool: buku | 0/1 (counts only, n<5) |
| tool: calcurse | 0/1 (counts only, n<5) |
| tool: devtodo | 0/1 (counts only, n<5) |
| tool: khal | 0/3 (counts only, n<5) |
| tool: stow | 0/1 (counts only, n<5) |
| tool: timewarrior | 0/2 (counts only, n<5) |
| tool: todoman | 0/2 (counts only, n<5) |
| tool: topydo | 0/13 (0.0%) |
| tool: watson | 1/1 (counts only, n<5) |
| class: c-cli | 0/4 (counts only, n<5) |
| class: c-cpp-cli | 0/2 (counts only, n<5) |
| class: cxx-cli | 0/1 (counts only, n<5) |
| class: perl-cli | 0/1 (counts only, n<5) |
| class: python-cli | 1/19 (5.3%) |
| class: python-sqlite | 0/1 (counts only, n<5) |
| judge: l0 | 0/2 (counts only, n<5) |
| judge: l0c | 1/26 (3.8%) |

| unknown_reason | count |
|---|---|
| baseline_violates_invariant | 1 |

#### Control trials (outside every denominator)

| trial | tool | class | judge | verdict | unknown_reason |
|---|---|---|---|---|---|
| ctl-pass-mv | pass | shell-helper | l0c | UNKNOWN | child_touched_state_dir |

UNKNOWN rate, per-trial: **1/1 (counts only, n<5)**

| slice | UNKNOWN |
|---|---|
| tool: pass | 1/1 (counts only, n<5) |
| class: shell-helper | 1/1 (counts only, n<5) |
| judge: l0c | 1/1 (counts only, n<5) |

| unknown_reason | count |
|---|---|
| child_touched_state_dir | 1 |

#### B-group (mechanically selected; the threshold basis)

| target | class | funnel stage | verdict | unknown_reason |
|---|---|---|---|---|
| audiolink | perl-cli | wall W2 | - | - |
| bucardo | perl-cli | wall W2 | - | - |
| check-postgres | perl-cli | wall W2 | - | - |
| cricket | perl-cli | wall W2 | - | - |
| flamerobin | cxx-cli | wall W3 | - | - |
| gammu | c-cli | wall W2 | - | - |
| gnupg-agent | c-cli | wall W3 | - | - |
| goobook | python-cli | wall W2 | - | - |
| hobbit-plugins | perl-cli | wall W2 | - | - |
| icinga2-ido-mysql | cxx-cli | wall W1 | - | - |
| icinga2-ido-pgsql | cxx-cli | wall W1 | - | - |
| ldap-git-backup | perl-cli | wall W2 | - | - |
| ldap-utils | c-cli | wall W2 | - | - |
| 2vcard | perl-cli | explored | PASS | - |
| bogofilter-bdb | c-cli | explored | PASS | - |
| bogofilter-sqlite | c-cli | explored | FAIL | - |
| cookietool | c-cli | explored | UNKNOWN | recording_run_failed |
| emboss | c-cli | explored | PASS | - |
| hnb | c-cli | explored | UNKNOWN | child_process_detected |
| lbdb | perl-cli | explored | UNKNOWN | child_process_detected |

UNKNOWN rate, per-trial: **3/7 (42.9%)**

| slice | UNKNOWN |
|---|---|
| tool: 2vcard | 0/1 (counts only, n<5) |
| tool: bogofilter-bdb | 0/1 (counts only, n<5) |
| tool: bogofilter-sqlite | 0/1 (counts only, n<5) |
| tool: cookietool | 1/1 (counts only, n<5) |
| tool: emboss | 0/1 (counts only, n<5) |
| tool: hnb | 1/1 (counts only, n<5) |
| tool: lbdb | 1/1 (counts only, n<5) |
| class: c-cli | 2/5 (40.0%) |
| class: perl-cli | 1/2 (counts only, n<5) |
| judge: l0 | 3/7 (42.9%) |

| unknown_reason | count |
|---|---|
| child_process_detected | 2 |
| recording_run_failed | 1 |

#### Outcome ratio (A-group, per the committed disposition map)

| outcome | count |
|---|---|
| FAIL, reported-upstream | 15 |
| FAIL, withdrawn | 1 |
| FAIL, kept-unreported | 1 |
| FAIL, new-this-sweep | 0 |
| UNKNOWN | 1 |
| PASS | 10 |

#### macOS column (derived, not measured)

Formula (mechanism: `requireCompleteness`, src/main.zig — no oracle exists on macOS,
so every strict PASS becomes `completeness_not_verified`; a FAIL stands on its own
evidence and is unchanged; a Linux UNKNOWN is not re-derived):
- A-group derived UNKNOWN rate on macOS: 11/28 (39.3%)
- B-group derived UNKNOWN rate on macOS: 6/7 (85.7%)
<!-- unknown-rate:results:end -->

**Reading the B-group's three UNKNOWNs** (swept 2026-08-16, engine 0.9.0 /
contract v10 at main `b5b23fd`; apparatus identity in
`spike/unknown-rate/artifacts/apparatus.txt`): all three are
**define-budget refusals, none are target-origin**. hnb and lbdb refused
exactly as their NOTES predicted — their documented invocations cannot be
spelled inside the engine's space-split operation contract, and the op.sh
wrapper is an exec chain the v10 observation rules refuse; cookietool's
recording was refused because the tool's exit convention (10, apparently
its deleted-cookie count) does not match the protocol's fixed
`expected_status 0`. Of the five targets whose documented invocations
could be spelled as operation strings, **four reached a verdict; the
fifth (cookietool) was refused not on spelling but on the exit status the
uniform protocol declared** — a define-budget miss of a different kind,
and unlike hnb/lbdb one its NOTES did not predict. Every UNKNOWN names a
contract gap; the origin split itself is a line drawn **after** the sweep
(the frozen rulebook predicted only the hnb/lbdb spelling class), and
cookietool is the arguable case — a nonstandard exit convention is also a
fact about the target. Counted either way, the threshold below holds
(part 1 becomes 1/7 at worst). That split is threshold material, not a
reason to re-file the refusals. *(Since this sweep: the argv form — #95,
ADR 0019 — can spell hnb's invocation without a wrapper, measured in
`spike/followup-95/`; the record above stands as measured under the
contract of its day. lbdb's stdin redirect remains outside any argv
shape's reach.)*

**The bogofilter-sqlite FAIL** (3/26 worlds, oracle agreed on 25
operations, L0: `wordlist.db` "holding neither the old nor the new
content" between two writes) is a fresh counterexample from a
never-before-run target — and it has the exact shape of the buku lesson in
`docs/target-classes.md`: a sqlite-backed store judged by file bytes is
judged more strictly than its journal contract. This sweep's uniform
protocol carried no checker and measured no recovery, so the disposition
here was recorded as new-this-sweep. **Triaged 2026-08-16 (#141's sibling
follow-up, `spike/followup-144/`): recovery holds.** The same define
re-run with bogofilter's own reader as the checker (bogoutil dump + a real
classification) reproduced FAIL 3/26 with the earliest violated invariant
"built-in atomicity (L0)" and **a committed per-world log** — the report
alone records only the earliest violating world, so the checker writes one
line per invocation outside the judged state: the falsification gate's red
first, then 26 passes, one for every explored world including all three
violating ones (`spike/followup-144/artifacts/checker.log`) — the git
COMMIT_EDITMSG template exactly. The disposition is
withdrawal-shaped: the class lesson confirmed on a second sqlite store,
no upstream claim — the outcome-ratio table is A-group-only by its
committed rule, so this paragraph, the B-group table and the follow-up's
committed artifacts are the finding's record.

**What the artifacts do and do not keep**: each executed trial's report
and transcript (and preflight text for the explored B-group trials) are
committed; saved
counterexample case files lived under the containers' scratch work
directories and were not preserved — the sweep records verdict
distributions, not replay cases (the A-group's cases are already committed
in their own records; bogofilter-sqlite's would need a labeled follow-up
run if its triage wants one).

## Threshold

**Set 2026-08-16 by the project owner, from the B-group data above, in
that order.** The threshold is two-part, evaluated on the B-group's
explored trials:

1. **Target-origin UNKNOWNs ≤ 1/7** — an UNKNOWN whose named reason is the
   target's own behavior (a nondeterministic writer, an unobservable
   store), as opposed to a define-budget refusal (an invocation the
   operation contract cannot spell, a mis-declared exit convention).
   Measured: **0/7**.
2. **Overall per-trial UNKNOWN rate ≤ 50%.** Measured: **42.9% (3/7)**.

Both parts hold, so **v1.0 entry criterion 4 is met** on this measurement.
The two-part shape is deliberate: the composition is the finding. Every
UNKNOWN in this sample names a contract gap (hnb and lbdb cannot be
spelled inside the space-split operation contract; cookietool's exit
convention was mis-declared by the uniform protocol), and four of the
five spellable targets reached verdicts. Two honesty notes, in the
repository's own style: the origin classification was drawn after the
sweep, and cookietool is its arguable case — re-filing it as
target-origin still satisfies part 1 at exactly 1/7, so the verdict on
this criterion is robust to that choice. And the merge order (rulebook
PR first, results PR after) proves the threshold postdates the rules; it
does not prove the threshold was not chosen to pass — that part is the
owner's recorded call, made with the margins visible. A future sweep
where target-origin UNKNOWNs dominate fails part 1 whatever the total
rate does — and per issue #84 step 4, a measured rate failing this
threshold is DESIGN §18 material; the threshold itself does not move.

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
