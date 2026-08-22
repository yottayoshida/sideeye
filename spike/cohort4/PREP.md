# Cohort 4 — the preconditions, written before any target is named

This file is **not** the PROTOCOL. The PROTOCOL freezes selection, rules
and targets before first contact; this file is what has to be true, built
and merged **before that freeze is written**. Nothing here has contacted a
target, and no target is named in it.

Written 2026-08-22, while cohort 3's last target (papis) is still in
flight. The order matters: a precondition register assembled after the
cohort's outcome is known is a rationalisation, one assembled before it is
a design. Cohort 3's own outcome for papis is therefore *not* an input to
anything below — where a cohort-3 fact is used, it is one already recorded
on main.

## 1. The ledger this design starts from

Read the outcomes, not the effort. Every row is a committed record.

| Campaign | Targets | Outcome | Criterion-1 candidates |
|---|---|---|---|
| Blind 1–3 (ADR 0012/0015/0016) | topydo, abook, khal | topydo 12/13 counterexamples (filed `topydo/topydo#341`; not novel as a phenomenon — `topydo/topydo#318`), abook null, khal null | 0 claimed |
| Assisted cohort (`spike/assisted/`) | buku, calcurse, devtodo, pass, stow | calcurse FAIL (`lfos/calcurse#529`), stow FAIL (`aspiers/stow#139`), devtodo FAIL (deliberately unreported), pass wall (`child_touched_state_dir`), buku withdrawn | 0 — provenance red by the mini-seal's own checker (define and first artifact in the same merge) |
| Cohort 2 (#183) — transaction machinery | Mercurial, Borg, jj, Bun, KeePassXC | five frozen targets, six recorded outcomes: two probe walls, two engine walls, two full verdicts (hg FAIL 73/107 all L0-only, contract held 107/107; borg FAIL 3/119 all L0-only, contract held 119/119) | **0**, said plainly |
| Cohort 3 (#209) — the sweet spot. **Closed 2026-08-22**, all five measured (main `bcf2ae1`) | cargo, black, rustfmt, poetry (+r2), papis | cargo two-layer named wall (terminal); black FAIL 1/3 checker-red — **known upstream** (`psf/black#2479` open since 2021, fix `psf/black#5207` since 2026-07-01); rustfmt FAIL 1/3 checker-red — **known surface**, gate closed before the define (`rust-lang/rustfmt#6041` since 2024-01-24); poetry FAIL 2/5, earliest world L0-only ⇒ no candidate; poetry-r2 FAIL 1/3, barred by the FAIL-freeze rule; papis **PASS 2/2** — one crash point, the contrast case | **0** |

Three readings that the design must answer, not restate:

1. **Detection is not the bottleneck.** Cohort 3 went from a frozen define
   to a reproduced checker-red verdict in minutes, twice, in two
   languages. The engine finds the thing.
2. **Novelty is the bottleneck.** Both checker-red finds were already on
   their trackers. The class "a formatter rewrites a file in place" is
   public knowledge with years-old issues.
3. **The gate is closer than the record reads.** Nothing external blocks
   it — §2. What is missing is one finding that is novel, automatically
   discovered, and provenance-clean at the same time.

## 2. Where criterion 1 actually stands (#140)

**Corrected 2026-08-22 against the primary sources, because the first
draft of this file got it wrong in the direction that would have changed
the plan.** "author-confirmed" does **not** mean the target's maintainer.
PRD's criterion 1 glosses it (the sentence entered 2026-08-13 in the
Seal A commit and ADR 0017 left it standing):

> "author-confirmed" reads as §17 scored it for timewarrior: **this
> project's author judges the bug real, upstream confirmation is sought,
> not required.**

DESIGN §17 scored timewarrior that way in practice — "judged a real bug /
stops after the fix — **clean** ... judged real by this project's author
(not yet confirmed by timewarrior's maintainers) ... a three-part patch
reaches PASS 25/25 (measured)". So conditions 4 and 5 of §17's six are
closable by this project, and have been closed once.

`#140` does not contradict this. It quotes the ADR's words unchanged; what
it adds is a *Live candidates* paragraph about four upstream reports
awaiting a response, which reads as though the maintainers' replies were
the live path. They are not the gate. One clarifying line on `#140` —
naming the PRD gloss — removes the drift; no criterion changes.

### What is actually missing

Counted from the record, three near-misses each lack a **different** leg,
and no single finding has yet held all three at once:

| Finding | automatic | novel | provenance | missing |
|---|---|---|---|---|
| timewarrior (#778) | **partial** — a human read the strace to seed the target and the window | yes | — | automatic discovery |
| topydo (blind campaign 1, sealed) | yes | **no** — `topydo/topydo#318` reports the same surface | machine-checked seals | novelty |
| assisted cohort: calcurse, stow, devtodo | yes | yes — `spike/assisted/NOVELTY.md`, four for four, positive controls throughout | **red** — `verify-assisted.sh` reports define and first artifact in the same merge; and `spike/assisted/RESULTS.md` records that these same three had their `proposals.md` written *after* their explorations (one self-reported, two caught by R1 from file birth times) | provenance |
| cohorts 2 and 3 (mini-seal) | yes | **no** on both checker-red finds (black, rustfmt) | clean — `verify-assisted.sh` green | novelty |

**The missing combination is novel × automatic × mini-seal provenance, in
one finding.** That is what cohort 4 is for, and it is entirely within
this project's reach — no maintainer's reply stands between here and the
gate.

### The upstream reports, and why they are still tracked

They are evidence of practice, not a gate condition. Their status is
**measured, not remembered** — `spike/upstream-report-status.sh` prints
the table below with its measurement date, so a stale copy cannot pass for
a current one:

| Report | State | Comments | Last activity |
|---|---|---|---|
| `GothenburgBitFactory/timewarrior#778` | OPEN | 0 | 2026-08-12 |
| `topydo/topydo#341` | OPEN | 0 | 2026-08-14 |
| `aspiers/stow#139` | OPEN | 0 | 2026-08-15 |
| `lfos/calcurse#529` | OPEN | 0 | 2026-08-15 |

*measured 2026-08-22T06:52Z by `spike/upstream-report-status.sh`*

Four filings, zero comments of any kind. Cohort 3 added selection rule 11
(measured maintainer responsiveness) partly against this, and then
produced nothing reportable — so the rule has still never been tested on a
report of ours. Worth keeping, worth not over-reading.

## 3. The register — every mistake that cost a measurement, and what makes it impossible here

Rules are cheap; the column that matters is the last one. "Recorded" is
the weakest enforcement in the table and is used only where no mechanism
exists.

### A. Selection spent slots that could not have paid

| # | What happened (recorded at) | Requirement for cohort 4 | Enforcement |
|---|---|---|---|
| A1 | **black**: probe → define → explore → checker-red verdict → *then* the novelty search found `psf/black#2479` (2021). The slot was spent before the question "is this already known?" was asked. rustfmt, one target later, had its gate checked **before its define existed** and it worked (BUILDLOG 2026-08-22, both entries). | The novelty search is a **selection-time gate**, run and recorded before a target enters the frozen list — tracker search with a positive control, for the *operation's write shape*, not only the tool's name. A target whose shape is already on its tracker does not enter the cohort. | `novelty-prescan.sh`, transcript committed with the PROTOCOL freeze; the PROTOCOL cites the transcript per target |
| A2 | **papis**: probed and defined before anyone counted the kill points. The operation builds outside the library and moves in with a single `renameat`, followed by an `fchmodat` the engine records as metadata and does not judge — exactly one engine-reachable kill point, i.e. no interior to crash inside (`spike/cohort3/papis/thread-offswitch-scout.txt`, lines 21-22, on main). | **Interior gate**: the probe's own strace decides how many in-root kill points the operation has. `1` ⇒ the target is a contrast measurement, not a criterion-1 slot; keeping it is an owner decision made at the probe, with the bench available. | `preflight.sh interior`, run inside the probe, its count pinned in the probe transcript |
| A3 | **cargo**: two defines and two explores were spent discovering that the manifest's atomic rename is a raw syscall the shim cannot interpose (`spike/cohort3/cargo-r2/raw-rename-diagnosis.txt`). The cohort-2 probe gate only *notes* raw-syscall patterns; nothing gated on them. | **Shim-visibility agreement is a probe condition, not a note**: every in-root mutation strace sees must also be seen by an interposer built from the shim's own export list. A disagreement is a named wall at probe time, costing zero defines. | `preflight.sh visibility` (new probe condition 8), with the ad-hoc cargo diagnosis promoted to committed tooling |
| A4 | Rule 11 measured maintainer responsiveness on *any* recent issue. Our own four reports: zero replies (§2). | Keep rule 11, measure it on **bug reports** specifically, and record the counter-evidence in the same table so the rule is never read as a prediction about our reports. | PROTOCOL text + the §2 table restated in the freeze |

### B. The rules read a result the wrong way

| # | What happened | Requirement | Enforcement |
|---|---|---|---|
| B1 | **poetry**: a world where the declared checker genuinely breaks existed and was reproduced; the run is not a candidate because an L0-only world structurally precedes it in every run of that operation (#231). The claim rule inherited the engine's "save the earliest violating world" behaviour. | The claim exhibit is the **earliest checker-red world**. L0-only worlds stay recorded precision-limit observations. This requires the engine to save a case per invariant class — §4. | Engine change + tests + report-schema note, merged **before** the PROTOCOL freeze cites it (#231's own order of work) |
| B2 | **poetry-r2**: a clean, sealed, minimal reproduction that could never have been claimed, because its target's FAIL froze the define first. Correct under the rules — and worth stating up front so it is not re-litigated with a fresh FAIL in hand. | The PROTOCOL says in advance: a post-FAIL revision is a **record-only** artifact. A question that must be claimable is a different target, not a revision. | PROTOCOL text, frozen before first contact |
| B3 | **hg 73/107** (cohort 2): a large, seductive number that the frozen reading correctly refused. | Unchanged — the rule keeps working precisely because it is frozen before the first explore. | PROTOCOL text |
| B4 | The amendment rule ("an amendment after a target's first explore cannot change how that target's outcome is read", extended in cohort 3 to probes) held under pressure in both cohorts. | Carried forward verbatim, plus: **the claim-reading change of B1 applies to cohort 4 only** — cohorts 1–3 are not re-read. | PROTOCOL text; #231 already records the non-goal |

### C. Measurement traps — the tooling lied and the number looked fine

| # | What happened | Requirement | Enforcement |
|---|---|---|---|
| C1 | `docker build \| tail` hid a non-zero exit; the failed build was caught later by actually running the image (BUILDLOG 2026-08-22). | No gate output goes through a pipe. Exit status is captured before any formatting. | `preflight.sh` and `merge-gate.sh` capture rc first; PROTOCOL states the rule for hand-run commands |
| C2 | `nm` was absent and stderr was discarded, producing "no symbols imported at all" from an empty result (same entry). | Any zero-count claim needs a **tool-presence positive control** in the same transcript. | Both new scripts refuse to print a count when their own tool probe fails |
| C3 | Counts printed without denominators ("failed=0") are indistinguishable from "nothing was measured". | Every count in a gate's output carries its denominator. | Script output format |
| C4 | A same-class scan with a leading `--` in the pattern silently returned zero (recorded in the workspace's gotcha register). | Scans use `grep -e`, and every scan ships with a positive control hit. | Script + PROTOCOL text |
| C5 | **Measured during this preparation, 2026-08-22**: the tracker search the novelty gate depends on returns **zero for any space-separated phrase**. Against `psf/black` at `--limit 100`: `disk` → 30 hits (including both known issues), `disk full` → **0**, `disk+full` → 5, `full disk` → **0**. A pre-scan written the natural way would have reported zero for every term and called a known defect novel — the precise failure cohort 4 cannot afford. | Terms are single tokens or `+` joins; a multi-word term is **refused**, naming the `+` form. Every scan runs a fixed positive control (`psf/black` + `disk` must return 2479 and 5207) and a negative control before any target term is believed. | `novelty-prescan.sh`, controls run on every invocation |

### D. Delivery hygiene — three merges in two cohorts went out wrong

| # | What happened | Requirement | Enforcement |
|---|---|---|---|
| D1 | **#184** was merged with its R2 fix still unstaged: the commit was built before the last edit. | The commit for a PR is cut **after** the final edit, and the tree is clean at merge. | `merge-gate.sh`: refuses on a dirty tree or when local HEAD ≠ the PR's head SHA |
| D2 | **#194** was merged with the buildlog gate red: watch → count → merge were chained unconditionally. | Merge is a separate decision from waiting, taken on a printed verdict. | `merge-gate.sh` prints one PASS/REFUSE line; the merge command is not chained to it |
| D3 | **#216** was merged on "no checks reported" — 0 pass, 0 fail, 0 pending read as "nothing failed". | Zero checks is **absence of evidence**, and refuses. A pass requires at least one successful check and no failures and nothing pending. | `merge-gate.sh` |

### E. Provenance and apparatus hygiene

| # | What happened | Requirement | Enforcement |
|---|---|---|---|
| E1 | The workspace memory index injects the cohort's target names into every fresh subagent, which was measured to make blind arms impossible (#221's record). | Any cohort-4 step that depends on a fresh agent not knowing the targets runs **out of band**, and the leak channel is named in its record. | PROTOCOL text for that step |
| E2 | Scout capability was measured (#221): Opus 5 or better; Sonnet 5 is the floor; Haiku 4.5 is below the bar. The metadata gate passes fields that are present but false. | The cohort-4 scout runs on Opus 5 or better, and its output is checked by the probe/falsification layer, never by the metadata gate alone. | `docs/scouting.md` already carries the floor; the scout brief pins the model |
| E3 | Switching branches in the shared checkout broke concurrent readers (workspace gotcha register). | While another session holds this repository, cohort-4 work happens in a `git worktree`. | This preparation was done that way |
| E4 | "Claim exceeds measurement" — numbers and universals written from memory — is the most frequently repeated defect in this project's reviews. | Before every R1: grep the diff for digits and for all/every/never/only/both, and open the primary source for each hit. | PROTOCOL text; the same check the workspace rule already requires |
| E5 | Apparatus tiers (free / pre-declared / owner-gated) worked in both cohorts and were never abused. | Carried forward verbatim, with one addition: apparatus discovered mid-probe is an amendment that must land **before that target's first contact**. | PROTOCOL text |

### F. Walls now known in advance

Cohort 4 should not re-discover these. They are measured, each with a
recorded artifact (`docs/target-classes.md`):

- static linkage (`no_shim_marker`) — jj, Go's default
- threads (`multiple_threads_detected`) — Bun; libuv is forecast, unmeasured
- child processes doing the writing (`child_touched_state_dir`) — pass, #123
- raw syscalls past libc (`oracle_missed_operation`) — cargo's manifest rename, #217
- nondeterministic writers (`baseline_violates_invariant`) — watson
- encrypted / memory-locked state — KeePassXC's probe wall

A target whose forecast lands in this list enters only with the apparatus
that lifts the wall named **before** the probe, or does not enter.

## 4. Engine prerequisite (#231), as the owner specified it (2026-08-22)

Today the engine saves the run's earliest violating world, and the claim
rule reads that saved case. B1 is the consequence. The work is owned by
the session that closed cohort 3; the procedure below is the owner's, and
this file records it because cohort 4's PROTOCOL freeze is downstream of
it.

**The framing**: separate the **overall earliest** from the **claim
exhibit**. The existing earliest is not a mistake to remove — it is the
first physical counterexample of a FAIL and keeps that meaning. What is
missing is a second, machine-readable exhibit: the earliest **checker-red**
world.

- **Shape — to be compared, not assumed**: keep `case`/`replay` intact and
  add the second exhibit additively (`checker_case`, `checker_replay`,
  `checker_earliest`), *or* reorganise into a `cases` structure now, while
  the freeze has not landed. Both are on the table; the comparison is part
  of the work.
- **Implementation**: track the checker-red class from the **invariant bits
  at world-judgement time** — never by parsing the string "built-in
  atomicity, and the checker" after the fact. The first L0-only case and
  the first checker-red case are saved independently.
- **Acceptance**: a synthetic regression that miniaturises poetry's own
  structure — **k=2 is L0-only, k=4 is checker-red**. Assert that the
  overall earliest stays 2, that the checker exhibit is 4, and that **the
  case for 4 replays**. Per the repository's rule, the new assertion is
  **shown red once** before it is trusted.
- **BUILDLOG first**: the entry is opened *before* the code is touched —
  writing it up at PR time is too late under this repository's rule. The
  opening thesis is exactly "separate the overall earliest from the claim
  exhibit"; that is enough to start.
- **Contract check**: `docs/contract-freeze.md` surface 2 (report schema)
  freezes *at the v1.0 tag*; before it, changes are allowed by the
  CHANGELOG's standing header. Case output is still touched, so the change
  lands with a `docs/report-schema.md` note and tests.
- **Order, not to be inverted**: BUILDLOG opened → engine change →
  acceptance regression → merged to main → **then** the cohort-4 PROTOCOL
  freeze, which is where the new reading is first written down as a rule →
  then target contact. Nothing here re-reads cohorts 1–3.

## 5. Two new probe conditions

Cohort 2's seven conditions carry over. Two are added, each with the
falsification the repo requires of a new guard — a synthetic case that
fires it, in the same transcript:

- **Condition 8 — shim visibility agrees with the kernel.** Build an
  interposer from the shim's **own exported symbol list** (never a
  hand-written copy — #65's class), run the operation under it and under
  `strace`, and compare the in-root mutations. Anything the kernel
  performed on the state root that the interposer did not see is a named
  wall, recorded at probe time. Falsification: a control that performs a
  raw-syscall write must make the condition red.
- **Condition 9 — the operation has an interior.** Count the
  engine-reachable kill points inside the state root (the classes
  `src/contract.zig` counts). Report the count with its denominator. `1`
  is not a failure; it is a finding that goes to the owner with the bench
  in hand. Falsification: a control operation with a single atomic rename
  must report `1`.

Both stay **engine-free** — no kill, no checker, no define — so the
provenance gate is untouched. The engine's own recording pass would answer
condition 8 too, but it needs a define to exist, which is the thing the
mini-seal requires to come later.

**Both are already built and already falsified** (`preflight.sh`,
`visibility-logger.c`, `preflight-analyse.py`, transcript in
`preflight-selftest.txt`, run 2026-08-22 on linux/aarch64):

- `spike/toys/toy.c`, whose rotation goes through libc — **PASS**, every
  in-root mutation matched an interposed call.
- `spike/toys/toy_raw.c`, the same rotation through `syscall(2)` — **WALL**,
  naming the unmatched `openat`, `renameat` and `unlinkat` lines. This is
  the cargo shape, caught with no define written.
- interior on the libc toy: **4** kill points, with the per-class
  breakdown.

**What condition 8 does not see**, recorded so a green is read correctly:
the path-bearing classes are compared path by path and carry the
precision; `write`, `fsync` and `ftruncate` reach the interposer as a
descriptor rather than a path, so they are compared by count and catch a
total bypass but not a partial one.

## 6. Selection rules, v4 — delta from #209 (owner sign-off required)

Rules 1–13 of #209 carry over. The deltas:

- **14. Novelty pre-scan (A1).** Recorded tracker search on the operation's
  write shape, with a positive control, before the target is frozen.
- **15. Interior forecast (A2).** The operation must plausibly have more
  than one in-root kill point; confirmed at probe by condition 9.
- **16. Wall forecast against §3F.** Any forecast wall enters with its
  lifting apparatus named before the probe, or the target does not enter.
- **17. Rule 11 measured on bug reports**, with our own zero-reply record
  stated beside it.

Target *names* are deliberately absent from this file: selection is the
owner's call, and the scout brief that proposes candidates is written
after §7 is decided, because the exit rule changes what a good target is.

## 7. The exit rule — decided 2026-08-22: the default stands

**PRD's default is unchanged**: "If criterion 1 cannot be met, v1.0 does
not ship — the kill analysis ships instead." No ADR, no re-scoring, no
pre-authorised fallback. Recorded here so the decision is dated before the
cohort runs rather than discovered after it.

What the owner decided **not** to decide in advance: what the kill analysis
should conclude if cohort 4 comes back null. That judgement waits for the
document. Two facts belong on the record now, so they are not discovered
as convenient later:

- **§18 will not fire on a null.** Its antecedent is "Sideeye finds
  nothing beyond existing hand-written adversarial tests", and the record
  contradicts it — timewarrior, topydo, calcurse, stow, devtodo, black,
  rustfmt. `docs/kill-criteria-review.md` already says the antecedent was
  checked and did not hold (2026-08-16, none of the eight triggered).
- **So the kill analysis will not produce a mechanical verdict.** It will
  say the tool works and the self-set gate measures something narrower,
  and the choice among §18's own "stopped or redesigned" — or a third,
  narrowing the claim — will be a judgement made after seeing the result.
  PRD's warning applies to exactly that moment: "A failed search is a §18
  data point, not a reason to soften the scoring."

Two paths were considered and declined for now, both recorded so that
choosing one later is visibly a change rather than a discovery:
pre-authorising an assisted-cohort finding (calcurse/stow/devtodo) despite
its red provenance, and re-measuring an assisted target under the
mini-seal — the latter barred by the criterion's own text, since this
project has already observed those targets failing in execution.

## 8. What this preparation already built

Merged as one PR, before any target exists. Every one of them is the
mechanical form of a row above, and each was exercised before being
believed:

| Artifact | Closes | Falsified by |
|---|---|---|
| `spike/merge-gate.sh` | D1, D2, D3 | `--selftest`, 7 of 7: the empty rollup (#216), a failure among successes (#194), a running check, a legacy pending context, a null rollup, malformed JSON, and an all-green case. Exercised against a real merged PR, which it refused for two independent reasons. |
| `spike/cohort4/preflight.sh` + `visibility-logger.c` + `preflight-analyse.py` | A2, A3, and C1–C3 in its own output | `--selftest` on this repository's own toys: libc-routed PASS, raw-syscall WALL, interior count 4. Transcript: `preflight-selftest.txt`. |
| `spike/upstream-report-status.sh` | the stale-table risk in §2 | `--selftest`: a control issue known to carry comments must not read back as zero. |
| `spike/cohort4/novelty-prescan.sh` | A1, C5 | `--selftest`: the fixed positive control returns both known issues, the negative control returns 0, and the multi-word refusal path was exercised. |

## 9. Order of work

1. This file and the tooling in §8 merged (no target named).
2. ~~Owner decides §7~~ — **done 2026-08-22: the default stands** (§7). No ADR.
3. Engine change (#231) merged with tests and the schema note.
4. `preflight.sh`, `novelty-prescan.sh`, `merge-gate.sh` merged, each with
   its falsification transcript.
5. Scout brief written against §6 (Opus 5 or better, `docs/scouting.md`);
   candidates proposed; **owner signs off on the target list**.
6. PROTOCOL frozen, citing 2–5 by merge.
7. Probes, in cohort order. Then defines. Then explores.
