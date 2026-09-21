# Results — 2026-09-21 verdict-chain

**What this run is.** The follow-up to [2026-09-21-release-path](../2026-09-21-release-path/).
That run took the adoption route `docs/ci-quickstart.md` tells a project to take — the
vendored `install-sideeye.sh`, a pinned version, the digest GitHub publishes — and then
stopped at `attempted` on a statically linked target. This run keeps that route and changes
the entry gate: a candidate now enters only when three measurements return **0**, and the
gate is shown turning away the binary the previous run admitted.

Selection, the ledgers, and every candidate's gate row: [SELECTION.md](SELECTION.md).

## The gate, before anything else this page says

`apparatus/gate.sh`, six legs, each seen (`transcripts/gate-selftest.txt`):

| leg | target | expected | measured |
|---|---|---|---|
| visibility green | the libc-routed toy | 0 | 0 |
| visibility **RED** | **lefthook 1.13.6** | 1 | **1** |
| interior green | `spike/toys/toy.c` (4 kill points) | 0 | 0 |
| interior **RED** | `apparatus/toy_single_op.c` (1 kill point) | 1 | **1** |
| threads green | one writing thread | 0 | 0 |
| threads **RED** | two threads writing the judged root | 1 | **1** |

Two of those legs are not the ones this campaign's plan named, and the reasons are the
measurements:

- **The interior red needed a new toy.** `spike/cohort4/preflight-selftest.txt:51` measures
  the repository's own toy at `INTERIOR kill points inside the state root: 4` — green. A
  gate whose red has never been seen says nothing about what it passed, so
  `toy_single_op.c` builds its file outside the root and moves it in with one `rename`:
  the papis shape, one kill point, no interior.
- **The threads gate counted the wrong thing first.** Its first version counted clones
  carrying `CLONE_THREAD` and went red at one. Measured against `overcommit --install`, it
  went red on two — both of them the Ruby VM's own startup threads, neither touching the
  judged directory. That is a proxy for a question the engine stopped asking: since
  contract v16 a run that creates threads is judged when **one thread wrote the judged
  directory**, and since v18 two writers are judged when a creation or a join orders them
  (`docs/report-schema.md`, ADR 0067). Counting creations would disqualify every Ruby,
  Python and Node candidate there is. The gate now counts thread ids that *write inside the
  state root*, which is where the engine takes its own count.

**What the gate still does not decide**: the v18 ordering question. Two writers is a red
here and not a refusal — it says admission depends on something a pre-run probe cannot
check. And one line of `preflight.sh`'s own output is wrong for this target and was left
alone: its exit-1 reading calls the wall *"the cargo class (#217)"*, which is
raw-syscalls-past-libc. lefthook is statically linked, so the shim never loads at all —
the same wall reached by a different road. That text belongs to `preflight.sh`, which
cohort 4's sealed records cite, and is not this campaign's to edit.

## What this run concludes, decided before the explore ran

*This section was committed before `apparatus/explore.sh` was executed; `git log` over this
file shows it landing ahead of the transcripts. That proves the conclusions were written
first, not that the result was unseen — the run happens outside git, and this page says so
rather than implying more.*

The chain this campaign is named after is `docs/outcome-funnel.md`'s:
`attempted → explored → judged → novel → report_worthy → filed`. It has reached `filed` 19
times, but never once starting from the adoption path #620 ships — every one of those rows
mounted a tarball an operator had unpacked.

- **If the verdict is FAIL**: the row reaches `judged`, and novelty is decided against
  `transcripts/novelty-overcommit.txt` plus a fresh read of the tracker for the exact
  window found. If novel, the report question goes to the owner as its own decision, and
  `sds/overcommit`'s CONTRIBUTING and any LLM policy are read first — recorded here with
  the file that was read, whatever the answer.
- **If the verdict is PASS**: the row reaches `judged` and stops. The chain's remaining
  stages are not reachable without a counterexample, and **that is a result, not a
  shortfall**: it would be the first target to carry the #620 adoption path all the way to
  a verdict, which is the leg the previous run could not test at all.
- **If the verdict is UNKNOWN**: the refusal is named and the row stops below `judged` — and
  the gate's own claim is falsified in the direction that matters. `spike/dogfood/README.md`
  says so already: *"Delete the ordering rule … if a run ever produces a candidate table
  where the screening measurement and the rule-16 forecast disagree in the direction that
  matters: the screen says a target is measurable and the engine then refuses it."* If that
  happens here, the gate goes in front of the owner with that sentence attached, and this
  page records which of the three measurements was the one that lied.

## The verdict

*Not yet run. Filled in from `transcripts/` after `apparatus/explore.sh` executes.*
