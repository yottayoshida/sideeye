# The UNKNOWN rate, measured

v1.0 entry criterion 4 (`PRD.md`) requires the UNKNOWN rate on supported
targets to be **measured and published**, with a target threshold **set from
that data** — and DESIGN §18 names "UNKNOWN dominates" as a kill condition.
This page is the measurement's fixed rulebook and its published numbers, and
it lands in two merges: the rulebook and apparatus first, the sweep's
results after, in a separate PR (three for the B2-group added by #619, whose
list merges before its defines — its section below says why) — so the
first-parent history proves the corpus predates the numbers (the same shape
`spike/assisted/verify-assisted.sh` checks for assisted claims). Until the
results PR merges, the Results section below carries an explicit
not-yet-measured placeholder that the CI gate asserts; everything else on
this page describes procedure, not completed measurement. Every number that
eventually appears between the results markers is recomputed from the
committed reports by `spike/unknown-rate/count.py`, wired into the
acceptance suite — a published figure that drifts from its artifacts goes
red in CI.

The three sentences **outside** those markers that name the ledgers state how
the cohort defines are sorted across them: the one counting what was committed between
the two generations, the one placing each of them into a ledger, and the one
under the g2 table naming what remains. `PRD.md`'s criterion-4 paragraph
states the same four counts again. Those eleven figures are recomputed from
the ledgers and the defines on disk by `spike/check-ledger-prose.sh`, which
goes red in CI when they drift and when the sentence it reads has moved (#342).
The rest of the prose on this page is still held by review. Delete that script
when these pages stop stating the counts in prose, or when the counts move
inside the markers — there the byte comparison already holds them, and two
gates on one fact is one too many.

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

  **Measured twice: generation g1 on 2026-08-16 and generation g2 on
  2026-08-26** (#239). Eighteen further defines were committed between the
  two — cohorts 2, 3 and 4 (`spike/cohort2/`, `spike/cohort3/`, `spike/cohort4/`; the
  `ops/*.toml` directories under each). They are now sorted across the three
  ledgers the rules describe: eight enter the corpus as generation **g2**,
  six are recorded in `supersession.tsv` as earlier revisions of targets the
  corpus carries, and four in `class-exclusions.tsv` as targets whose class
  the first table of `docs/target-classes.md` does not list.

  **g2 ran on 2026-08-26** and its figures are below beside g1's, both
  dated. The corpus and the ledgers merged first and the results after, so
  the first-parent order shows the corpus was fixed before the figures
  moved. The **threshold** is untouched: it is set from B-group data only,
  no cohort target is in B-group, and g2 does not cover B.

  **What the committed oracle logs carry.** They are strace output, so their
  paths are the ones the tool saw — which on this apparatus means the sweep
  machine's layout, the operator's home directory included. From this change
  on, `sweep.sh` folds that prefix once the container has exited — to `<repo>`
  where the path is whole, and to `<repo-truncated>` where strace cut the
  string at 32 bytes; the container's own `/work` mount is left alone, being
  the same on every machine —
  and `spike/acceptance.sh` check 2al holds that no committed log outside a
  named list carries one. The eight logs that predate the fold keep their
  paths and are that list: rewriting a committed measurement is the one thing
  this apparatus is built not to do, and the raw text is what makes a FAIL
  checkable by someone who was not there. The scope is the sweep's own
  artifacts; other records under `spike/` are other measurements' evidence and
  are not covered here.

  **What the difference between the two is, and is not.** A generation
  re-measures every row it covers, so g2 re-ran the twenty-eight g1
  measured as well as the eight that entered with it. That makes the
  difference separable, and it was separated once rather than left to a
  reading:

  - **The twenty-eight shared trials: 1/28 in g1, 1/28 in g2, with no
    trial changing verdict or reason.** Those two runs differ by engine
    (v10 era to v12), by rebuilt images against mutable base tags, and by
    ordinary run-to-run variation — and none of that moved a single
    judgement among them. That is a measurement about those twenty-eight
    and not a statement about the other causes generally.
  - **Within g2, holding engine and images fixed: 1/28 over the shared
    trials, 2/36 over all of them.** So the movement is **located in the
    eight trials that entered at g2** — which is where the arithmetic ends.

  **It does not follow that the corpus addition caused it**, and the next
  paragraph is why that distinction is not pedantic. Locating the movement
  in the new eight is not the same as attributing it to their being new:
  no counterfactual exists in which those eight ran on g1's engine and
  images, so their contribution and the engine's cannot be separated from
  each other the way the shared twenty-eight separate from both.

  **The eight moved the rate in both directions.** One added to the
  numerator and seven added only to the denominator: the shared twenty-eight
  plus himalaya alone would read 2/29 (6.9%), and the other seven bring it
  to 2/36 (5.6%). So the published rise from 3.6% is smaller than the single
  new UNKNOWN would have made it, and saying "the corpus addition raised the
  rate" flattens a set that pushed both ways.

  **The trial that added to the numerator is not the one the issue expected,
  and it refused for an engine reason.** #239 reasoned that the rate would
  rise because several added defines reach named refusals — jj, Bun and
  cargo. All three are outside the corpus by class, so none of them entered
  the denominator at all. The added UNKNOWN is himalaya, whose define
  carries the `apparatus_superseded` flag: its `no-accel-copy.so` answers
  the kernel copy primitives **the shim now interposes itself** (#244), and
  the two collide into `oracle_saw_phantom`. That refusal is an engine
  change meeting an older apparatus — a new trial exposed it, and the
  engine is what made it refuse. The flag was set from `PRD.md`'s
  instrument note before this sweep ran; the sweep is where it stopped
  being a note and became a number.

  This note sits outside the generated block on purpose — `count.py` owns
  everything between the results markers and compares it byte for byte.
- **B-group** — targets this project has never run, selected mechanically
  (no hand-picking; see below). **The threshold is set from B-group data
  only.**
- **B2-group** — a second never-run set, selected mechanically from Debian 13
  after v1.5 shipped (#619, ADR 0073; its own subsection below). Measured in
  generation g3 on the released v1.5.0 engine, beside a re-measurement of the
  B-group on the same engine that is published as a historical comparison and
  not as fresh evidence. No threshold is set from B2.
- A-group, B-group and B2-group are never pooled; no combined headline number
  exists on this page or anywhere else.

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
  with the reason. It never counts as UNKNOWN. Which of those two happened
  is recorded rather than assumed: the reason lives in
  `spike/unknown-rate/exclusions.tsv`, one row per waived trial, and a
  generation carrying a SETUP_ERROR that file does not name cannot be
  marked complete. Re-running is the default and leaves no row; the ledger
  is only the exception, so a rate published over fewer trials than were
  attempted always has a committed sentence saying why.
- **Strict oracle everywhere**: every trial runs with
  `--oracle /usr/bin/strace` and never `--allow-unverified`. The sweep
  manifest records each trial's full launcher argv; `count.py` reads only
  machine fields (never the report's prose accounts — #94 tracks the
  machine-readable evidence level for PASS).
- **Each report is bound to the sweep that wrote it** (#349). The manifest
  carries the report's sha256 beside its path, written by `sweep.sh` from the
  file the trial had just produced, and `count.py check` recomputes it. Before
  this, `rpath` said only where a report should be: a report could be
  substituted between generations and every check still passed — measured, with
  the twenty-eight A-group reports shared by g1 and g2 copied byte-for-byte
  from one to the other. The rows that share an id across generations are the
  vulnerable ones, because the part of a re-measurement that stays the same is
  the part a substitution leaves no trace in. A funnel wall runs no engine and
  carries `-`.

  **What this binds, and from when.** The hashes for g1 and g2 were computed
  from the files as they stand today, not by the sweeps that wrote them — those
  ran before the column existed. So for the two generations already published
  the column says "not substituted since this was added", and for every
  generation after it says "this is the file the sweep wrote". The two-merge
  discipline still carries the other half: the corpus provably predates the
  numbers.

  **What it does not bind is the manifest itself.** The column ties a report to
  its manifest row; the row is trusted because it is in the history, not
  because anything here checks it. Rewriting a report and its recorded hash in
  the same commit passes this check and is visible where such things are
  visible — in the diff, and in the order the merges landed. That is the same
  footing the define digests have always had, and it is why the two-merge rule
  is the load-bearing part rather than this column.
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
  labeled sample — never pooled. A tool whose FAILs are not in that map
  counts as `new-this-sweep` (pending triage) — and for a tool whose
  disposition the repository already records, writing that value is an
  error `count.py check` refuses, so the map cannot be satisfied by
  declaring everything untriaged. **The disposition describes the tool's
  upstream story, which is not always the story of the FAIL verdicts
  counted under it** (#147): **none of topydo's twelve A-group FAILs was
  filed** — ten destroy the active list in its crash window, which a
  third-party report from 2023 already covers; `revert` is the same
  destruction on the done file, and `do` is not a destruction at all, the
  task ending up in both files. Neither of those two was scored for novelty
  or for filing. The `reported-upstream` value comes from this project's
  one topydo filing, a different finding reached by post-seal analysis
  rather than by any trial counted here. The map's `source` column carries
  that, so a reader is not left to infer it. The counts below are therefore
  coarser than the record — they say how many FAILs sit under a tool whose
  dealings were upstream-facing, not how many reports were filed. Twelve is
  per generation: the same trials are re-measured in each, so the two
  tables below are not additive.
- **Generations** (added with #239): a generation is one run of
  `sweep.sh` — one engine build, one set of images, one artifacts
  directory — enumerated in `spike/unknown-rate/generations.tsv`. The
  "one sweep, one engine build" rule holds *per generation*, not across
  the page: **A and B need not be measured in the same generation**, and
  each published figure carries its generation's date and apparatus
  identity. A generation's expected trial set is every corpus row whose
  `since` is that generation or earlier, in a group it covers. A generation
  is `complete` when its manifest matches that set exactly, or `unstarted`
  when no manifest exists (the docs then carry the not-yet-measured
  placeholder), and **those are the only two values the file accepts**.
  There is no third one for the state between them: a manifest covering
  some of its expected rows is a half-measured sweep, and a rate computed
  from one is indistinguishable, once published, from a rate computed from
  all of them — so that state is detected and refused rather than recorded.
  A half-finished sweep has nowhere to be written down, and therefore
  nowhere to be published from. Completed generations are never edited:
  re-measuring means a new generation and a new artifacts directory, with
  both dates published.
- **Corpus membership is decided by three ledgers**, and every committed
  cohort define appears in exactly one of them: `corpus.tsv` (measured),
  `supersession.tsv` (a later revision of the same target is in the
  corpus), and `class-exclusions.tsv` (the target's class is not a
  supported class). `count.py check` holds their union to the set of
  committed cohort defines on disk and holds them disjoint, so a define
  cannot be dropped by being left out of all three, and each file's own
  criterion is checked rather than trusted — a supersession row must name a
  successor that exists in the corpus, and a class-exclusions row must rest
  on its target's own row of `docs/target-classes.md`: a row outside the
  first table that cites the define's cohort directory and carries the
  quoted class, with nothing in the first table reaching it — no row there
  citing that directory or naming the same tool, and the quoted class not a
  Class cell there as well (#598).
- **Declared apparatus is marked, not judged** (`flags` in `corpus.tsv`):
  `apparatus_declared` records that a define carries apparatus beyond its
  toml, and `apparatus_superseded` that an engine change has overtaken it,
  set only where a primary source says so. A superseded define is neither
  rebuilt (that is a cohort re-run, not a re-sweep) nor dropped (dropping
  deletes the finding). It runs as committed and its outcome is published
  as measured, refusal included — and the flag reaches the arithmetic:
  a marked row sits in the denominator, its slices and the outcome ratio
  exactly once, like any other.
- **Class membership follows `docs/target-classes.md`'s first table, and
  one row predates that rule.** watson is in the A-group denominator as a
  Python CLI, and that page lists watson under its refusal tables, which
  it says are not supported classes. The two readings disagree. The
  denominator keeps watson, which is the direction that does not lower the
  rate — and this is disclosed rather than resolved: the choice was made
  after the 2026-08-16 sweep had run, so it is a post-hoc inclusion, and
  saying so does not make it otherwise. New rows do not follow it: they
  take a first-table row or they go in `class-exclusions.tsv`.
- **B-group is not re-swept by #239.** The A-group's corpus drifted; the
  B-group's did not, and the threshold is set from B alone. Re-measuring B
  would put a criterion whose margin is one trial back in play as a side
  effect of correcting a published figure that is not its basis. A future
  B measurement is its own decision, with its own generation — and that
  decision is #619's, the next bullet.
- **B2-group, and the g3 re-measurement of B (#619, ADR 0073).** A second
  mechanically selected group, frozen the same way as B and one step earlier:
  its selection protocol and its target list merge before any define exists,
  the defines merge before the sweep runs, and the results merge last, so the
  first-parent order shows the names were fixed before anything ran against
  them. Generation g3 measures B2 and re-measures B on one engine — the
  released v1.5.0 build, pinned in `engine-pins.tsv`, not a build of the
  checkout — and publishes the two in separate tables, never pooled: B's g3
  figures are a historical comparison against the names g1 measured, B2's the
  fresh reading. No threshold is set from B2, and none is set before its
  number is published. B's g3 figures are evaluated against the threshold below
  as any B sweep's are, and what that comes to is recorded rather than decided
  here. The protocol is in the corpus section, under B2; all three merges
  have landed, and g3's tables are in the Results section with the prose
  beside the protocol.

## The corpus

### A-group — entering at g1: 28 trials, 10 tools

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

### A-group — entering at g2: 8 further trials, 7 further tools

The cohort defines the three ledgers assign to the corpus. Their classes are
the behavioural rows of `docs/target-classes.md`'s first table, one slug per
row (the mapping is written out in `corpus.tsv`'s header).

| tool | class | define | trials |
|---|---|---|---|
| hg | DVCS with its own transaction engine | `spike/cohort2/hg-r4/ops` | 1 |
| borg | Deduplicating backup with a repository format | `spike/cohort2/borg-r3/ops` | 1 |
| black | Python in-place formatter | `spike/cohort3/black/ops` | 1 |
| papis | Python personal-library store | `spike/cohort3/papis/ops` | 1 |
| poetry | Python manifest + lock manager | `spike/cohort3/poetry/ops`, `poetry-r2/ops` | 2 |
| rustfmt | Rust in-place formatter | `spike/cohort3/rustfmt/ops` | 1 |
| himalaya | Rust mail client over a maildir store | `spike/cohort4/himalaya-r2/ops` | 1 |

**Measured in g2 on 2026-08-26**: six FAIL, one PASS, and one UNKNOWN —
himalaya, on `oracle_saw_phantom`, which is the `apparatus_superseded`
flag turning into a measurement. The remaining ten cohort defines are in
`supersession.tsv` (six) and `class-exclusions.tsv` (four).

watson is **in** the denominator: "supported" is a class property
(`docs/target-classes.md`), watson is a Python CLI, and its known refusal
(`baseline_violates_invariant`) counts as an UNKNOWN — the honest
direction. **That reading and `docs/target-classes.md` disagree**, because
that page lists watson under its refusal tables and says those are not
supported classes; the inclusion also postdates the sweep it affects, which
makes it a post-hoc one. It stands, disclosed on both pages rather than
settled on one (#239, ADR 0025). **pass** runs as the control trial, outside
every denominator: its behavioral class (shell CLI over helper processes)
is a refusal-table row of `docs/target-classes.md`, not a first-table row,
so it is not a supported class. When g1 ran, that class had no verdict at
all; its row now records one for both targets it names, pass and lbdb, and
the class stays where it is (#598).

### Exclusions (every one named, with the reason)

| candidate | why not in the corpus |
|---|---|
| `docs/ci-quickstart/sideeye.toml` | drives the demo toy, not a third-party tool |
| `docs/ci-quickstart/release/sideeye-clean.toml` | same: the release quickstart's PASS lane drives the demo toy (#620) |
| `docs/ci-quickstart/release/sideeye-bug.toml` | same: the release quickstart's FAIL lane drives the demo toy with its bug planted (#620) |
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
argument carrying a space — hnb; a stdin redirect — lbdb). The two `op.sh`
targets refused, and the sweep read that refusal as a property of the
spelling: a script wrapper performing nothing state-changing before its
`exec` was taken to be an image change the v10 observation rules refuse
structurally. **That rule is false as stated, measured 2026-09-07.** A
wrapper of exactly that shape, naming its target by an absolute path,
reaches a verdict. What refuses is a wrapper whose `exec` names a program
to be found on `PATH`: the shell then execs once per entry, the shim
records before each call, and the engine counted the attempts that
returned ENOENT as further image changes (ADR 0018's amendment carries the
measurement, and the reader no longer does this). Both `op.sh` files here
name their program that way. **What the same two defines do on today's
engine was measured on 2026-09-07**, and the two answers differ: hnb reaches
**FAIL over 3 crash points** — the verdict and the count the argv spelling of
the same question reached on 2026-08-16 — while lbdb advances one wall further
out, to `child_touched_state_dir`, its image change followed and another pid
unlinking a temp file in the judged state. So one of the two was refused by the
engine and one is refused by the target's process structure, which the sweep's
single reason could not distinguish. That re-measurement ran under a **rebuilt**
`sideeye-ur-extra` (image id `9fec97c7`, not the sweep's `df66b6e1`), so it
speaks for the recipe rather than for the sweep's own apparatus, and the
transcripts are not committed. **The sweep itself was re-measured on
2026-09-18** — generation g3, the released v1.5.0, all seven trials; the
leg-by-leg comparison is in the B2 section under *What g3 measured — the
B-group* — and the g1 figures below remain what that engine measured on that
image, with g3's standing beside them. The define the original rule cites
as its evidence is neither of these two — `defines-b/hnb/NOTES.md` names
2vcard, whose define carries only an `op.txt`, so the rule cannot be re-derived
from the corpus at all. Both `op.sh` files here are present and unchanged.
The figures below stand as measured on that day's engine; the grounds
recorded in `defines-b/hnb/NOTES.md` and `defines-b/lbdb/NOTES.md` carry
the superseded rule, and are left untouched because the sweep's audit
trail hashes those directories. The
`sideeye preflight` answer (#77) is recorded beside each verdict as the
funnel instrument — in text + exit code, since preflight has no
machine-readable form (a deliberate constraint: `explore --config` answers
strictly more, and `--json` lives there).

### B2-group — 30 targets, machine-selected on trixie (#619)

**Every B2 verdict, rate and slice on this page is recomputed from reports the
released v1.5.0 engine wrote against targets whose selection was committed
before any of them was run** — the one B2 table not drawn from reports, the
authoring clock, says so in its heading. That sentence is the group's promise;
what follows is what holds it.

**Where this section stands.** Three merges carry B2, and this revision of the
page is the third: the protocol, the list, the exclusions and the engine pin
came with the first (`315f244`); the thirty defines under `defines-b2/`, the
two-leg launcher, `legs.tsv`, the readers of the engine pin in `sweep.sh` and
`count.py check`, the authoring clock, and the corpus rows with the second
(`0b9e5e6`); and this one brings `artifacts-g3/` — the sweep run from a clean
worktree at that second merge commit, under the released v1.5.0 — the g3
tables in Results, and the paragraphs headed **What g3 measured** below.

**What the thirty are, as authored** (`corpus.tsv`, the `b2-*` rows, in the
keyed order; every directory under `defines-b2/` carries a `NOTES.md` quoting
the manual it was decided from). Nineteen reached a define; eleven are walls,
none of them W0 or W1 — five W2 (a DVD or CD drive, a web server, a Debian
mirror: dvdbackup, httrack, debmirror, mp3roaster, crip) and six W3 (readers
that print, packages with no command of their own, an interactive
configurator: zbar-tools, aggregate, pgdbf, debian-cd, migrationtools,
emacspeak). Two defines carry the shell's redirects as their documented
invocation (roffit, zh-autoconvert — their `NOTES.md` say what a verdict is
then about); one declares a measured exit convention (otf2bdf, `8`); one is
committed knowing its recording fails (unmass — the binary dies with SIGSEGV
on every archive built to the formats it documents, on this platform); five
name in `packages.txt` a package their environment needs and their Depends
do not pull in (a font, the `paper` command, an encoder, a preprocessor, a
Perl module), which the sweep image installs. Each define's `preflight
--twice` under the released engine is recorded in its `NOTES.md`: fourteen
accepted, five refused — and the refusals are already a reading of the
funnel, taken before the sweep and not counted as it: a directory the default
mode does not count (bs1770gain, `unsupported_syscall_observed`), a write
from inside stdio whose `next_step` names `--observe syscalls` (otf2bdf), a
recording that fails (unmass), and two Perl scripts whose encoder or
compressor is a child that writes the state (pacpl, mail-expire,
`child_touched_state_dir`). The sweep is what turns those into rows.

**Why a second group.** The B-group above was swept on 2026-08-16 by the v0.9.0
engine (contract v10). Since then the define surface and the engine moved —
argv operations, exec chains, child-process accounting, the thread rule,
`--observe syscalls` — and the seven B targets that reached an explore are no
longer fresh: their refusals are on this page, two of them motivated later
work, and hnb has since reached a verdict on a newer engine (the correction
above). Re-running them measures how far the engine widened on that sample; it
cannot say how often today's product reaches a verdict on a target it has never
met. B2 asks that, and the two readings are published apart.

**Selection** is `spike/unknown-rate/select-b2.sh`, run inside a
`debian:trixie-slim` container against Debian 13's own package metadata
(debtags; the release identity of the lists it read is in
`b2-selection-record.txt`). The predicate: `role::program`; `implemented-in::`
one of c, c++, python, perl, ruby, php, haskell, java, ecmascript — the
languages the rows of `docs/target-classes.md`'s first table are written in;
`use::` one of editing, converting, compressing, organizing, storing,
synchronizing — a program that changes something; `works-with::` one of the
file-shaped families (file, text, db, pim, mail, archive, image, image:raster,
image:vector, software:source, software:package, vcs, logfile, font,
dictionary, spreadsheet, calendar, audio, video); `interface::commandline`; not
daemon, x11, graphical or web; and the same name filters as before. The pool
is `b2-candidates.txt` (289 packages). Then the committed exclusions
(`b2-exclusions.txt`) are removed and the **first 30** of the keyed order are
the group, `b2-targets.txt`. Whatever the predicate produced is the group; no
hand touched it at any stage, and `count.py b2-selection` holds the list to
that derivation in CI.

**The order is a keyed hash, not the alphabet.** Each candidate is ranked by
`sha256("<package>\t<key>")`, the key being the commit the v1.5.0 tag points
at (`b2-order-key.txt`): fixed and public before the pool was generated, and
unrelated to any name. The first pool's alphabetical head was heavy in
database-server tooling, which is why nine of its twenty were W2 walls.
Choosing the key was a human decision — what it closes is reordering a list
after seeing it, no more.

**The bias, published.** Debtags coverage is partial: a package with no
`use::` tag is not in the pool, `implemented-in::rust` is absent from trixie's
vocabulary so no Rust target can be selected this way, and
`interface::text-mode` programs (hnb's kind) are out. The predicate was chosen
from tag semantics and the pool's size and language split — 289 packages, of
which 275 carry one first-table language tag (155 C, 58 Perl, 30 C++, 23
Python, 4 Haskell, 3 Java, 2 Ruby) and 14 carry two or more, the one PHP
among them; counted by tag occurrence, so that a package with two tags counts
in both, 166 C, 71 Perl, 33 C++, 26 Python, 5 Haskell, 4 Ruby, 3 Java, 1 PHP
— never from a candidate's name. The pool size is held to `b2-candidates.txt`
by `count.py b2-selection`, which reads the sentence above that states it; the
split was counted once from the archive's tags on 2026-09-18 (`BUILDLOG.md`
carries the counting) and no check recomputes it. N is 30 because the first pool's funnel put 7 of 20 into an
explore and a single trial should not move the rate by a seventh; that is an
expectation, and the funnel table is where it is measured.

**Fresh means never met, under any name.** `b2-exclusions.txt` carries every
package this project has already run, read or sealed — the twenty of the
B-group, the A-group and its control, every target in `spike/outcome-funnel.tsv`
and `spike/upstream-reports.tsv`, every tool in a table of
`docs/target-classes.md`, the candidates the dogfood and cohort selections
turned away, and the campaign taint ledger. Tool names and Debian package
names differ (`GNU Stow` is `stow`; `mid3v2` is `python3-mutagen`), so
`b2-exclusion-aliases.tsv` maps every ledger spelling to its packages, or to
`-` where no Debian package exists, and `count.py b2-selection` holds four
things: the target list is the keyed first-N derivation of the pool minus the
exclusions; every name in the five machine-readable ledgers (`b-targets.txt`,
`b-exclusions.txt`, `corpus.tsv` — the A-group and its control — the outcome
funnel, the upstream reports) is excluded either directly or through the alias
table; no alias names a package the exclusions do not carry; and the pool size
this section states is the size of `b2-candidates.txt`. The prose sources — a dogfood run's rejection table,
a cohort's candidate list — were read by hand into the exclusions and are
held by nothing but that file. The alias table is written from memory of the
archive and can be wrong in the direction that matters: a target selected here
that this project already met under a name the table does not map becomes
**wall W0**. Authoring each define therefore starts with a search of this
repository for the package name and the binaries it ships, pasted into the
define's `NOTES.md`; a hit is a W0 row, never a replacement. A W0 row means
the alias table was short; it is recorded, and the table is not corrected
after the fact. And, as for the B-group: **this page is the record** that the
30 names in `b2-targets.txt` were read by this project.

**The run contract**, for every target past the walls, is
`launchers/bgroup.sh` — its name and its arguments unchanged, so the B rows of
`corpus.tsv`, held to their g1 manifest by the argv binding above, do not
change; the launcher finds the define under `defines-b/` or `defines-b2/` by
which exists — with one uniform minimal define under `defines-b2/<t>/`:
`setup.sh`; the one representative state-changing command from the target's
own documentation as `op.txt` or, where the space-split contract cannot spell
it, an `op.sh` naming its program by absolute path (the correction above); an
optional `env.sh`; an optional `expect-status.txt` carrying the target's exit
convention (cookietool's refusal was the uniform protocol's `0`, not the
target's — where the manual states none, the measured status and the
measurement are in the `NOTES.md`); and an optional `packages.txt` naming the
Debian packages the define's environment needs beyond the target, which
`b2-preflight.sh` installs while authoring and `Dockerfile.b2` installs for
the sweep (authoring runs the launcher itself, stopped after its first leg,
so a define is read while it is written exactly as the sweep will read it).
Judge `l0`, strict oracle. Three legs, each recorded: `preflight
--twice`, whose answer is the funnel instrument and never the verdict; an
`explore` under the default observation mode; and, only when that explore
refuses with the `next_step` that asks for `--observe syscalls` (matched on
that step's opening sentence, because the `syscalls_may_have_killed` step
names the flag too, in a sentence that says the opposite), a second `explore`
under that mode. **The verdict is the last leg's.** `legs.tsv` beside the
reports names each leg's mode, verdict, reason, report path and sha256, and
`report.json` — the file the manifest binds — is a copy of the last leg's;
`count.py check` opens each leg, recomputes the digests, holds the verdict
and the reason to the leg's own report, and refuses a trial whose second leg
exists without the first having asked for it, is missing when the first did,
or whose `report.json` is not the last leg's bytes — and a B2 trial with no
`legs.tsv` at all, since the launcher writes one for every trial it runs and a
verdict without legs behind it did not come through the protocol. The mode
column is the
one cell the report cannot confirm — a report has no field for the flag it
ran under — so it is the launcher's record of which flag it passed. When
the second leg refuses too, the tables print both reasons; a second leg
refused `syscalls_may_have_killed` is read as the mode's side effect and not
as the target's own wall — its wall is the first leg's reason, and the first
leg, being the default-mode run that refusal's own `next_step` says to
compare against, is the comparison. No invariant is weakened to reach a
verdict. The B rows re-measured in g3 run through the same launcher, so their
first leg is the g1 protocol plus the `--twice` answer, and any second leg is
recorded the same way.

**The engine is the released build.** `engine-pins.tsv` names, per
generation, the release tag, the asset and its sha256 as GitHub publishes it.
`fetch-engine.sh`, given the generation, reads that row, fetches the asset
once, refuses on a digest mismatch, and extracts the engine and the shim
under `spike/unknown-rate/engine/<asset>/` (ignored by git; keyed by the
asset, so two assets of one tag never share a directory) in the `zig-out`
layout; `sweep.sh` mounts that read-only at
`/work/zig-out` in place of a build of the checkout, so the banner and the two
digest lines in `apparatus.txt` describe the shipped binary, and a further
line — `engine: release <tag> <asset> <sha256> …` — records the pin it was
checked against. `count.py check` refuses a complete generation with a pin
whose record lacks that line.

**Authoring time is recorded, self-reported.** `spike/unknown-rate/b2-clock.tsv`
carries one line per event per target — `setup_started`,
`first_accepted_recording` (the first `preflight` that exited 0), `final` (the
define committed, or the wall decided) — appended by `b2-clock.sh` (and by
`b2-author.sh` and `b2-preflight.sh`, which stamp the first two) when the
author reaches that point. It sits outside the define directories, whose bytes
the manifest's define digest covers. It is what the author wrote down, and
nothing checks it against a clock; it is published so that reach and authoring
friction are not read as one number. Two things about how it was written:
the candidates were probed in batches of up to six at a time, so a target's
`setup_started` is its batch's, and a target read later in the batch carries
its wait; and the thirty were authored in one sitting — the file's own
stamps run from the first `setup_started` to the last `final` in twenty-two
minutes of wall time — so the minutes are that sitting's, not a per-target
cost in isolation. (The first draft of this sentence said "about an hour and
a half", the author's impression of the sitting; the file said otherwise and
the file is the record.)

**No threshold.** The threshold section below is evaluated on the B-group, and
g3's B figures are held to it as any B sweep's are — including the sentence
that a sweep failing part 1 is DESIGN §18 material. Whether criterion 4's status
moves on that is the owner's call, made after the number exists and recorded
in `PRD.md` with the date. B2 gets no threshold on this page, and any threshold
or widening issue the frozen result suggests is filed from that result, not
before it. Rows that reach an explore here do not join `spike/outcome-funnel.tsv`,
as the B-group's did not: that record is one row per campaign and target and
this sweep is not a campaign; folding the two funnels into one is its own change.

**What g3 measured — B2** (`artifacts-g3/`, 2026-09-18, engine v1.5.0 from
the pinned asset; the tables are in Results). The funnel: thirty candidates,
eleven walls (the five W2 and six W3 whose grounds are authored above), no W0
and no W1 — and nineteen explored: **13 PASS, 1 FAIL, 5 UNKNOWN (5/19,
26.3%)**. The five reasons. `child_touched_state_dir` twice — pacpl and
mail-expire, Perl scripts whose encoder `flac` and compressor `gzip` are
children that write the judged state. The refusal's own step says to invoke
the wrapped command instead, which the run contract does not allow (the
operation is the documented invocation); and the mode that does see such a
child's writes, `--observe syscalls`, is on record for this class
(`docs/target-classes.md`, the lbdb row, with committed artifacts) — but that
step does not name the mode, and this sweep ran a second leg only where the
engine's step did, so neither trial met it. `recording_run_failed` once —
unmass: outside the engine every archive built from its documented formats
ends in a segmentation fault (exit 139); inside the recording the engine
decoded the status as 1, and the uniform `0` refused it. Its notes record both
numbers and file the refusal as the target's own failure on this platform, not
a define miss. `unsupported_syscall_observed` once — bs1770gain calls
`mkdirat`, a README class wall. `kill_did_not_land` once — apt-utils:
`apt-ftparchive generate` orders its state-directory calls differently between
runs, so a crash point at a fixed index does not name the same operation twice;
the target's own nondeterminism, and the message names the declaration it
contradicts. The one FAIL is sgml-base: `update-catalog --add` renames
`central.cat` aside and then opens its replacement, and a crash between the two
(crash point 2 of 3) leaves the catalog absent — present before and after the
operation, gone from the crashed state — the L0 built-in atomicity invariant.
That is a window of absence, a file moved away before its successor exists,
and not the truncate-then-write window the 2026-09-16 dogfood records found,
which leaves the file empty; in g3 that second shape is hnb's and
bogofilter-sqlite's ("holding neither the old nor the new content").
**Final-leg mode**: 25 trials ended on the default mode and one on `--observe
syscalls` — otf2bdf, whose first leg refused `oracle_missed_operation` (the
oracle saw a 4096-byte `write` to `out.bdf` the shim's account did not carry)
with the `next_step` that asks for the mode, and whose second leg reached PASS
over 175 crash points with the oracle verified; `count.py check` holds that
shape. Of the thirteen PASSes, c2hs's is `oracle_verified_subject_only` — its
`cpp` child's operations carry crash-point addresses and were explored, but
the oracle compared only the subject's own — the weakest kind of PASS the tool
produces, and the funnel table's narrow shape has no column for the flag.
**Preflight `--twice`**: 14 accepted, 5 refused (bs1770gain, otf2bdf, unmass,
pacpl, mail-expire) — the same five as the authoring runs; four of the five
were then refused by the explore for the reason preflight had shown, and
otf2bdf's second leg turned the fifth into a verdict. **Class slices**: the
table prints them; c-cli (1/11) and perl-cli (2/5) are the two above the
five-trial floor. **Authoring time** (self-reported, `b2-clock.tsv`): from
`setup_started` to the first accepted recording a median of 5 minutes over the
fourteen that reached one, to `final` a median of 5.5 minutes over all thirty,
the longest 8 — batch wall time, so the minutes are the sitting's and not a
per-target cost.

**What g3 measured — the B-group, leg by leg** (a historical comparison against
the names g1 measured, on the g3 engine and the g3 image; not fresh evidence).
Every B trial's first leg ran under the default mode and none was asked for a
second, so each row is one leg against one leg. Five of seven are identical to
the crash-point count: 2vcard PASS (2), bogofilter-bdb PASS (7),
bogofilter-sqlite FAIL (25), emboss PASS (2), cookietool UNKNOWN
`recording_run_failed` (exit 10 against the uniform `0`; `expect-status.txt`
could declare 10 now, and the B define is left as g1 measured it). Two moved:
hnb UNKNOWN `child_process_detected` → **FAIL over 3 crash points**
(`notes.hnb` holding neither the old nor the new content at crash point 3) —
the verdict the 2026-09-07 re-measurement above reached on a rebuilt image, now
reached by the sweep itself on the pinned release; and lbdb UNKNOWN
`child_process_detected` → UNKNOWN `child_touched_state_dir` (its child
`fetchaddr` writes the judged file through the parent shell's redirected
stdout and records nothing the shim can number), one wall further out, as that
re-measurement also said. Under `--observe syscalls` the same lbdb operation
reaches PASS over 8 crash points (`docs/target-classes.md`, its own row, with
the artifacts committed under `spike/followup-trapwitness/`); this sweep did
not run that mode for it, because the run contract takes a second leg only from
a `next_step` that names the mode and `child_touched_state_dir`'s does not.
Both moves happened without a define change — the manifest's define digests
are the bytes g1 hashed — and with the engine (0.13.0 → 1.5.0) and the image
(`df66b6e1` → `e124ccf0`) both changed, so the movement is located and not
attributed. B's per-trial rate reads **2/7** on g3 against 3/7 on g1.
Preflight `--twice`, an instrument g1 did not run: 5 accepted, 2 refused
(cookietool, lbdb — the same two the explore refuses, for the same reasons).

**The thirteen B walls, one line each** (no engine runs for a wall; these are
the grounds as recorded in `defines-b/<t>/NOTES.md`, unchanged by g3):
audiolink, bucardo, check-postgres, goobook and ldap-utils have no local-file
state (W2); cricket has no local-file state of a drivable kind — a monitoring
collector for network devices (W2); gammu's
state is on a phone (W2); hobbit-plugins are plugins for a monitoring server
(W2); ldap-git-backup's state source is a server (W2); flamerobin is a GUI
with no non-interactive writer (W3); gnupg-agent is a transitional package
with no operations of its own (W3); icinga2-ido-mysql and icinga2-ido-pgsql
do not install without a database server (W1). Thirteen walls of twenty in B
against eleven of thirty in B2. By composition, nine of B's thirteen are W2
rows — state on a server, on network devices, or on a phone — and two more do
not install without a database server; B2's five W2 rows are a DVD or CD drive
(dvdbackup, mp3roaster, crip), a web server (httrack) and a Debian mirror
(debmirror). Two predicates, two archives and two engines differ between the
groups, so the difference is described here and not attributed.

**The dominant remaining wall, named and not filed.** In the funnel it is W3 —
no documented non-interactive state-changing command — at six of B2's thirty,
the largest single bucket; nothing in the engine reaches a target that offers
no such command, and the six are listed above with their grounds. Among the
engine's refusals it is `child_touched_state_dir`, two of the five — the
pacpl / mail-expire pair above — the class `docs/target-classes.md` records at
its "Shell CLIs over helper processes" row, whose measured reach is two
targets of two with the weakest kind of PASS; here two of two refused, because
the wrapper and the child write in the same directory rather than the shell
writing nothing, and the mode that class reaches verdicts in was not asked for
by the refusal's step. That is the observation; what to do about it is filed
from the result, if at all, by the owner, and not here.

## Method

The protocol: one sweep per generation, one engine — a build (`zig build
-Dtarget=aarch64-linux-gnu` at that sweep's HEAD) for g1 and g2, the released
asset `engine-pins.tsv` names for g3 (fetched, verified against the published
digest, mounted read-only; the pin line in `apparatus.txt` records it) — fresh containers
per trial, driven by `spike/unknown-rate/sweep.sh <generation>` — the repo
mounted read-only, with only that generation's artifacts tree writable.
Apparatus identity (engine version + sha256, shim sha256, image ids) goes
into `<artifacts_dir>/apparatus.txt` and per trial into
`<artifacts_dir>/manifest.tsv`, where `<artifacts_dir>` is the generation's
own directory from `generations.tsv` — g1's is `artifacts/`; the
manifest also records each trial's define digest, which `count.py check`
recomputes from the checkout — that is how "the committed defines ran
verbatim" becomes machine-checked once the artifacts exist — and the
report's sha256 beside it, recomputed the same way, which is how "this is
the file the sweep wrote" becomes machine-checked rather than assumed from
the path (#349). The images are pinned by build, not by manifest (the base tags are mutable — the same
honesty note `spike/assisted/Dockerfile` carries), so environmental
identity with past runs is recorded, never claimed. `count.py check`
refuses a complete generation whose `apparatus.txt` is absent, or which
lacks any of: both digest lines, a `head:` resolved to a commit id, and a
line naming each image the manifest uses. Those are the four things asked
for, rather than "not truncated" — a record that lost only image lines the
manifest never used still passes, and the sweep lists every
`sideeye-ur-*` on the host rather than the ones it ran, so what this
establishes is that the record is intact, never which images the trials
ran under.

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
  is usable by default on macOS (SIP leaves DTrace's syscall provider with
  no probes even as root; the candidate measured oracle-shaped, `fs_usage`,
  is root-gated — #181), and `requireCompleteness`
  (src/refuse.zig) guards every path that ends in PASS — so under this page's
  strict protocol every Linux PASS derives to UNKNOWN
  (`completeness_not_verified`) while a FAIL stands on its own evidence.
  The derived rate is printed from that formula by `count.py`, never
  hand-written, and is labeled derived wherever it appears.
- **Linux x86_64**: no real-target measurement exists; named absent.

## Results

<!-- unknown-rate:results:begin -->
_Generated by `spike/unknown-rate/count.py emit` — do not edit between the markers._

### Generation g1 — measured 2026-08-16 (A,B,control)

#### A-group (the engine's development input — not the threshold basis)

| trial | tool | class | judge | verdict | unknown_reason | flags |
|---|---|---|---|---|---|---|
| a-topydo-add | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-append | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-del | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-dep-add | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-dep-rm | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-depri | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-do | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-ls | topydo | python-cli | l0c | PASS (0 crash points) | - | - |
| a-topydo-postpone | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-pri | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-revert | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-sort | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-tag | topydo | python-cli | l0c | FAIL | - | - |
| a-abook-import | abook | c-cli | l0c | PASS | - | - |
| a-abook-export | abook | c-cli | l0c | PASS | - | - |
| a-abook-refused | abook | c-cli | l0c | PASS | - | - |
| a-khal-import | khal | python-cli | l0c | PASS | - | - |
| a-khal-update | khal | python-cli | l0c | PASS | - | - |
| a-khal-new | khal | python-cli | l0c | PASS | - | - |
| a-buku-add | buku | python-sqlite | l0c | FAIL | - | - |
| a-calcurse-purge | calcurse | c-cli | l0c | FAIL | - | - |
| a-devtodo-remove | devtodo | cxx-cli | l0c | FAIL | - | - |
| a-stow-unfold | stow | perl-cli | l0c | FAIL | - | - |
| a-watson-add | watson | python-cli | l0c | UNKNOWN | baseline_violates_invariant | - |
| a-timew-a | timewarrior | c-cpp-cli | l0 | PASS | - | - |
| a-timew-b | timewarrior | c-cpp-cli | l0c | FAIL | - | - |
| a-todoman-a | todoman | python-cli | l0 | PASS | - | - |
| a-todoman-b | todoman | python-cli | l0c | PASS | - | - |

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

| trial | tool | class | judge | verdict | unknown_reason | flags |
|---|---|---|---|---|---|---|
| ctl-pass-mv | pass | shell-helper | l0c | UNKNOWN | child_touched_state_dir | - |

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

Formula (mechanism: `requireCompleteness`, src/refuse.zig — no oracle exists on macOS,
so every strict PASS becomes `completeness_not_verified`; a FAIL stands on its own
evidence and is unchanged; a Linux UNKNOWN is not re-derived):
- A-group derived UNKNOWN rate on macOS: 11/28 (39.3%)
- B-group derived UNKNOWN rate on macOS: 6/7 (85.7%)

### Generation g2 — measured 2026-08-26 (A)

#### A-group (the engine's development input — not the threshold basis)

| trial | tool | class | judge | verdict | unknown_reason | flags |
|---|---|---|---|---|---|---|
| a-topydo-add | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-append | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-del | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-dep-add | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-dep-rm | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-depri | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-do | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-ls | topydo | python-cli | l0c | PASS (0 crash points) | - | - |
| a-topydo-postpone | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-pri | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-revert | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-sort | topydo | python-cli | l0c | FAIL | - | - |
| a-topydo-tag | topydo | python-cli | l0c | FAIL | - | - |
| a-abook-import | abook | c-cli | l0c | PASS | - | - |
| a-abook-export | abook | c-cli | l0c | PASS | - | - |
| a-abook-refused | abook | c-cli | l0c | PASS | - | - |
| a-khal-import | khal | python-cli | l0c | PASS | - | - |
| a-khal-update | khal | python-cli | l0c | PASS | - | - |
| a-khal-new | khal | python-cli | l0c | PASS | - | - |
| a-buku-add | buku | python-sqlite | l0c | FAIL | - | - |
| a-calcurse-purge | calcurse | c-cli | l0c | FAIL | - | - |
| a-devtodo-remove | devtodo | cxx-cli | l0c | FAIL | - | - |
| a-stow-unfold | stow | perl-cli | l0c | FAIL | - | - |
| a-watson-add | watson | python-cli | l0c | UNKNOWN | baseline_violates_invariant | - |
| a-timew-a | timewarrior | c-cpp-cli | l0 | PASS | - | - |
| a-timew-b | timewarrior | c-cpp-cli | l0c | FAIL | - | - |
| a-todoman-a | todoman | python-cli | l0 | PASS | - | - |
| a-todoman-b | todoman | python-cli | l0c | PASS | - | - |
| a-hg-commit | hg | dvcs-transactional | l0c | FAIL | - | apparatus_declared |
| a-borg-create | borg | dedup-backup-repo | l0c | FAIL | - | apparatus_declared |
| a-black-format | black | python-inplace-formatter | l0c | FAIL | - | - |
| a-papis-add | papis | python-library-store | l0c | PASS | - | - |
| a-poetry-add | poetry | python-manifest-lock | l0c | FAIL | - | - |
| a-poetry-version | poetry | python-manifest-lock | l0c | FAIL | - | - |
| a-rustfmt-format | rustfmt | rust-inplace-formatter | l0c | FAIL | - | - |
| a-himalaya-copy | himalaya | rust-maildir-client | l0c | UNKNOWN | oracle_saw_phantom | apparatus_declared;apparatus_superseded |

UNKNOWN rate, per-trial: **2/36 (5.6%)**

| slice | UNKNOWN |
|---|---|
| tool: abook | 0/3 (counts only, n<5) |
| tool: black | 0/1 (counts only, n<5) |
| tool: borg | 0/1 (counts only, n<5) |
| tool: buku | 0/1 (counts only, n<5) |
| tool: calcurse | 0/1 (counts only, n<5) |
| tool: devtodo | 0/1 (counts only, n<5) |
| tool: hg | 0/1 (counts only, n<5) |
| tool: himalaya | 1/1 (counts only, n<5) |
| tool: khal | 0/3 (counts only, n<5) |
| tool: papis | 0/1 (counts only, n<5) |
| tool: poetry | 0/2 (counts only, n<5) |
| tool: rustfmt | 0/1 (counts only, n<5) |
| tool: stow | 0/1 (counts only, n<5) |
| tool: timewarrior | 0/2 (counts only, n<5) |
| tool: todoman | 0/2 (counts only, n<5) |
| tool: topydo | 0/13 (0.0%) |
| tool: watson | 1/1 (counts only, n<5) |
| class: c-cli | 0/4 (counts only, n<5) |
| class: c-cpp-cli | 0/2 (counts only, n<5) |
| class: cxx-cli | 0/1 (counts only, n<5) |
| class: dedup-backup-repo | 0/1 (counts only, n<5) |
| class: dvcs-transactional | 0/1 (counts only, n<5) |
| class: perl-cli | 0/1 (counts only, n<5) |
| class: python-cli | 1/19 (5.3%) |
| class: python-inplace-formatter | 0/1 (counts only, n<5) |
| class: python-library-store | 0/1 (counts only, n<5) |
| class: python-manifest-lock | 0/2 (counts only, n<5) |
| class: python-sqlite | 0/1 (counts only, n<5) |
| class: rust-inplace-formatter | 0/1 (counts only, n<5) |
| class: rust-maildir-client | 1/1 (counts only, n<5) |
| judge: l0 | 0/2 (counts only, n<5) |
| judge: l0c | 2/34 (5.9%) |

| unknown_reason | count |
|---|---|
| baseline_violates_invariant | 1 |
| oracle_saw_phantom | 1 |

#### Outcome ratio (A-group, per the committed disposition map)

| outcome | count |
|---|---|
| FAIL, reported-upstream | 17 |
| FAIL, withdrawn | 1 |
| FAIL, kept-unreported | 5 |
| FAIL, new-this-sweep | 0 |
| UNKNOWN | 2 |
| PASS | 11 |

#### macOS column (derived, not measured)

Formula (mechanism: `requireCompleteness`, src/refuse.zig — no oracle exists on macOS,
so every strict PASS becomes `completeness_not_verified`; a FAIL stands on its own
evidence and is unchanged; a Linux UNKNOWN is not re-derived):
- A-group derived UNKNOWN rate on macOS: 13/36 (36.1%)

### Generation g3 — measured 2026-09-18 (B,B2)

#### B-group (mechanically selected; the threshold basis)

_Re-measured in g3 on this generation's engine — a historical comparison against the names an earlier generation measured, not fresh evidence; the threshold basis is unchanged._

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
| hnb | c-cli | explored | FAIL | - |
| lbdb | perl-cli | explored | UNKNOWN | child_touched_state_dir |

UNKNOWN rate, per-trial: **2/7 (28.6%)**

| slice | UNKNOWN |
|---|---|
| tool: 2vcard | 0/1 (counts only, n<5) |
| tool: bogofilter-bdb | 0/1 (counts only, n<5) |
| tool: bogofilter-sqlite | 0/1 (counts only, n<5) |
| tool: cookietool | 1/1 (counts only, n<5) |
| tool: emboss | 0/1 (counts only, n<5) |
| tool: hnb | 0/1 (counts only, n<5) |
| tool: lbdb | 1/1 (counts only, n<5) |
| class: c-cli | 1/5 (20.0%) |
| class: perl-cli | 1/2 (counts only, n<5) |
| judge: l0 | 2/7 (28.6%) |

| unknown_reason | count |
|---|---|
| child_touched_state_dir | 1 |
| recording_run_failed | 1 |

#### B2-group (mechanically selected on trixie after v1.5; measured, no threshold)

| target | class | funnel stage | verdict | unknown_reason |
|---|---|---|---|---|
| dvdbackup | c-cli | wall W2 | - | - |
| httrack | c-cli | wall W2 | - | - |
| zbar-tools | c-cli | wall W3 | - | - |
| debmirror | perl-cli | wall W2 | - | - |
| debian-cd | perl-cli | wall W3 | - | - |
| aggregate | c-cli | wall W3 | - | - |
| mp3roaster | perl-cli | wall W2 | - | - |
| crip | perl-cli | wall W2 | - | - |
| emacspeak | perl-cli | wall W3 | - | - |
| migrationtools | perl-cli | wall W3 | - | - |
| pgdbf | c-cli | wall W3 | - | - |
| roffit | perl-cli | explored | PASS | - |
| bs1770gain | c-cli | explored | UNKNOWN | unsupported_syscall_observed |
| txt2html | perl-cli | explored | PASS | - |
| otf2bdf | c-cli | explored | PASS | - |
| psutils | c-cli | explored | PASS | - |
| unmass | cxx-cli | explored | UNKNOWN | recording_run_failed |
| tcpslice | c-cli | explored | PASS | - |
| enscribe | c-cli | explored | PASS | - |
| clzip | c-cli | explored | PASS | - |
| giflib-tools | c-cli | explored | PASS | - |
| pngcrush | c-cli | explored | PASS | - |
| pacpl | perl-cli | explored | UNKNOWN | child_touched_state_dir |
| c2hs | haskell-cli | explored | PASS | - |
| apt-utils | cxx-cli | explored | UNKNOWN | kill_did_not_land |
| mail-expire | perl-cli | explored | UNKNOWN | child_touched_state_dir |
| conv-tools | c-cli | explored | PASS | - |
| sgml-base | perl-cli | explored | FAIL | - |
| zh-autoconvert | c-cli | explored | PASS | - |
| icnsutils | c-cli | explored | PASS | - |

UNKNOWN rate, per-trial: **5/19 (26.3%)**

| slice | UNKNOWN |
|---|---|
| tool: apt-utils | 1/1 (counts only, n<5) |
| tool: bs1770gain | 1/1 (counts only, n<5) |
| tool: c2hs | 0/1 (counts only, n<5) |
| tool: clzip | 0/1 (counts only, n<5) |
| tool: conv-tools | 0/1 (counts only, n<5) |
| tool: enscribe | 0/1 (counts only, n<5) |
| tool: giflib-tools | 0/1 (counts only, n<5) |
| tool: icnsutils | 0/1 (counts only, n<5) |
| tool: mail-expire | 1/1 (counts only, n<5) |
| tool: otf2bdf | 0/1 (counts only, n<5) |
| tool: pacpl | 1/1 (counts only, n<5) |
| tool: pngcrush | 0/1 (counts only, n<5) |
| tool: psutils | 0/1 (counts only, n<5) |
| tool: roffit | 0/1 (counts only, n<5) |
| tool: sgml-base | 0/1 (counts only, n<5) |
| tool: tcpslice | 0/1 (counts only, n<5) |
| tool: txt2html | 0/1 (counts only, n<5) |
| tool: unmass | 1/1 (counts only, n<5) |
| tool: zh-autoconvert | 0/1 (counts only, n<5) |
| class: c-cli | 1/11 (9.1%) |
| class: cxx-cli | 2/2 (counts only, n<5) |
| class: haskell-cli | 0/1 (counts only, n<5) |
| class: perl-cli | 2/5 (40.0%) |
| judge: l0 | 5/19 (26.3%) |

| unknown_reason | count |
|---|---|
| child_touched_state_dir | 2 |
| kill_did_not_land | 1 |
| recording_run_failed | 1 |
| unsupported_syscall_observed | 1 |

#### Observation legs (trials whose launcher recorded them; the verdict above is the last leg's)

| target | group | first leg | second leg | final mode |
|---|---|---|---|---|
| 2vcard | B | wrappers: PASS | - | wrappers |
| bogofilter-bdb | B | wrappers: PASS | - | wrappers |
| bogofilter-sqlite | B | wrappers: FAIL | - | wrappers |
| cookietool | B | wrappers: UNKNOWN (recording_run_failed) | - | wrappers |
| emboss | B | wrappers: PASS | - | wrappers |
| hnb | B | wrappers: FAIL | - | wrappers |
| lbdb | B | wrappers: UNKNOWN (child_touched_state_dir) | - | wrappers |
| roffit | B2 | wrappers: PASS | - | wrappers |
| bs1770gain | B2 | wrappers: UNKNOWN (unsupported_syscall_observed) | - | wrappers |
| txt2html | B2 | wrappers: PASS | - | wrappers |
| otf2bdf | B2 | wrappers: UNKNOWN (oracle_missed_operation) | syscalls: PASS | syscalls |
| psutils | B2 | wrappers: PASS | - | wrappers |
| unmass | B2 | wrappers: UNKNOWN (recording_run_failed) | - | wrappers |
| tcpslice | B2 | wrappers: PASS | - | wrappers |
| enscribe | B2 | wrappers: PASS | - | wrappers |
| clzip | B2 | wrappers: PASS | - | wrappers |
| giflib-tools | B2 | wrappers: PASS | - | wrappers |
| pngcrush | B2 | wrappers: PASS | - | wrappers |
| pacpl | B2 | wrappers: UNKNOWN (child_touched_state_dir) | - | wrappers |
| c2hs | B2 | wrappers: PASS | - | wrappers |
| apt-utils | B2 | wrappers: UNKNOWN (kill_did_not_land) | - | wrappers |
| mail-expire | B2 | wrappers: UNKNOWN (child_touched_state_dir) | - | wrappers |
| conv-tools | B2 | wrappers: PASS | - | wrappers |
| sgml-base | B2 | wrappers: FAIL | - | wrappers |
| zh-autoconvert | B2 | wrappers: PASS | - | wrappers |
| icnsutils | B2 | wrappers: PASS | - | wrappers |

#### B2 authoring clock (self-reported; minutes from setup_started)

| target | to first accepted recording | to final |
|---|---|---|
| aggregate | - | 3 |
| apt-utils | 5 | 7 |
| bs1770gain | - | 8 |
| c2hs | 5 | 7 |
| clzip | 3 | 5 |
| conv-tools | 5 | 6 |
| crip | - | 3 |
| debian-cd | - | 5 |
| debmirror | - | 3 |
| dvdbackup | - | 4 |
| emacspeak | - | 3 |
| enscribe | 3 | 5 |
| giflib-tools | 5 | 6 |
| httrack | - | 2 |
| icnsutils | 5 | 6 |
| mail-expire | - | 6 |
| migrationtools | - | 7 |
| mp3roaster | - | 3 |
| otf2bdf | - | 5 |
| pacpl | - | 7 |
| pgdbf | - | 6 |
| pngcrush | 5 | 6 |
| psutils | 5 | 5 |
| roffit | 4 | 4 |
| sgml-base | 5 | 6 |
| tcpslice | 4 | 6 |
| txt2html | 4 | 4 |
| unmass | - | 8 |
| zbar-tools | - | 2 |
| zh-autoconvert | 5 | 6 |

#### macOS column (derived, not measured)

Formula (mechanism: `requireCompleteness`, src/refuse.zig — no oracle exists on macOS,
so every strict PASS becomes `completeness_not_verified`; a FAIL stands on its own
evidence and is unchanged; a Linux UNKNOWN is not re-derived):
- B-group derived UNKNOWN rate on macOS: 5/7 (71.4%)
- B2-group derived UNKNOWN rate on macOS: 18/19 (94.7%)
<!-- unknown-rate:results:end -->

**The `ctl-pass-mv` control above predates contract v15, and its reason has moved twice.**
The trial ran without `--oracle` (its flags column says so), and that is the shape of the
change: a run whose children write is now decided by both witnesses together, so with no
oracle to consult it refuses `boundary_without_oracle` — which names the flag to pass — and
with one it is judged (ADR 0053). The row is left as it was measured rather than re-run:
this page is a record of a sweep, and re-measuring one control inside it would make the
denominator something other than what the sweep sampled. The note sits outside the results
markers for the same reason — everything between them is recomputed byte for byte, so prose
belongs on this side of the line.

**Reading the B-group's three UNKNOWNs** (swept 2026-08-16, engine 0.9.0 /
contract v10 at main `b5b23fd`; apparatus identity in
`spike/unknown-rate/artifacts/apparatus.txt`): all three are
**define-budget refusals, none are target-origin**. hnb and lbdb refused
after their documented invocations could not be spelled inside the
engine's space-split operation contract, which sent both to an `op.sh`
wrapper — the outcome their NOTES predicted, on a rule about wrappers that
2026-09-07 measured to be false as stated (see the correction above; what
refuses is the `PATH` lookup inside the wrapper, and these two trials were
not re-measured). **The classification in this paragraph is against the engine
of the sweep's day.** The engine no longer refuses that shape at all, so a
re-run would not reproduce these two refusals — from which nothing follows
about the figures, which are what that engine measured, and everything follows
about reading "define-budget refusal" as a property of the define rather than
of the pairing. cookietool's
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
line per invocation outside the judged state (as measured then; since
2026-08-22 the report also carries the earliest *checker-red* world as its
own exhibit, `checker_earliest` — #231, ADR 0020 — which does not replace
this technique: the per-world log covers every world, the exhibit covers
one): the falsification gate's red
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

**Held to on g3 (2026-09-18), B re-measured on the released v1.5.0.** Part 2
reads **28.6% (2/7)** and holds. Part 1 turns on how the two UNKNOWNs are
filed, and g1's filing does not carry over unchanged: g1 filed all three of
its UNKNOWNs as define-budget (**0/7**) — hnb and lbdb as spellings the
operation contract could not carry, cookietool as the uniform exit convention.
On g3 hnb is a verdict; cookietool is the same exit-convention refusal, filed
here as define-budget as in g1; and lbdb's `child_touched_state_dir` reads two
ways on this repository's own pages — the target's process structure (this
page's 2026-09-07 paragraph), or a spelling-and-mode gap, since the same
operation reaches PASS under `--observe syscalls` (`docs/target-classes.md`,
the lbdb row). Filed as target-origin, part 1 reads **1/7** and holds at its
edge, and g1's robustness note ("re-filing cookietool as target-origin still
satisfies part 1") does not survive: re-filed, it is 2/7 and fails. Filed as
define-budget, part 1 reads **0/7** and g1's note stands. Both readings are
drawn after the sweep, as g1's was; this page records the number under each
and draws neither for the criterion. Whether criterion 4's status moves is the
owner's call; `PRD.md` carries the dated line.

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
