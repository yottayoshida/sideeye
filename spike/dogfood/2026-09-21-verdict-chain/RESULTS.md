# Results — 2026-09-21 verdict-chain

**What this run is.** The follow-up to [2026-09-21-release-path](../2026-09-21-release-path/).
That run took the adoption route `docs/ci-quickstart.md` tells a project to take — the
vendored `install-sideeye.sh`, a pinned version, the digest GitHub publishes — and then
stopped at `attempted` on a statically linked target. This run keeps that route and changes
the entry gate: a candidate now enters only when three measurements return **0**, and the
gate is shown turning away the binary the previous run admitted.

Selection, the ledgers, and every candidate's gate row: [SELECTION.md](SELECTION.md).

## The gate, before anything else this page says

`apparatus/gate.sh`, seven legs, each seen (`transcripts/gate-selftest.txt`):

| leg | target | expected | measured |
|---|---|---|---|
| visibility green | the libc-routed toy | 0 | 0 |
| visibility **RED** | **lefthook 1.13.6** | 1 | **1** |
| interior green | `spike/toys/toy.c` (4 kill points) | 0 | 0 |
| interior **RED** | `apparatus/toy_single_op.c` (1 kill point) | 1 | **1** |
| threads green | one writing thread | 0 | 0 |
| threads **RED** | two threads writing the judged root | 1 | **1** |
| threads green | two threads writing **siblings** of the root | 0 | 0 |

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

*This section landed in commit `e064dee`, which also carries the selection transcripts —
the freshness screen, the gate legs, the novelty sweep — and **none of the explore
transcripts**: `overcommit.json`, `overcommit.run2.json`, `overcommit.txt`,
`consequence.txt` and `sigint-reachability.txt` all arrive in a later commit.
`git log --oneline -- <this file> <transcripts/overcommit.json>` shows the two commits in
that order. What that proves is that the conclusions were written before the explore ran —
not that the result was unseen, because the run happens outside git.

The earlier wording here said "ahead of the transcripts", which was false of `e064dee`
itself: that commit carries eight of them. Only this note was rewritten; the three branches
below are byte-identical to what `e064dee` holds, and `git show e064dee:spike/dogfood/2026-09-21-verdict-chain/RESULTS.md`
is how a reader checks that rather than taking it from this sentence.*

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

| target | stage reached | verdict | stopped at |
|---|---|---|---|
| `overcommit` 0.73.0, 4,004★ | **novel** | **FAIL** 10 of 32 explored worlds | `report_worthy` — an owner's judgement, not a wall |

`oracle_verified`, 31 crash points plus the baseline, and **reproduced identically**: both
reports are committed — `transcripts/overcommit.json` and `transcripts/overcommit.run2.json`
— and they agree on verdict, exit code, `oracle_verified`, crash points, explored,
violations and the earliest exhibit's crash point and operation. A reader can diff them.

**The earliest exhibit is crash point 4 of 31** — after the truncating `open` of
`.git/hooks/overcommit-hook` and before its `write`. What that leaves is a hook file that
exists, is executable, and is empty.

**What that costs a user, measured with a control in the same run**
(`transcripts/consequence.txt`, every exit status the command's own — no pipe between it
and `$?`):

| state of `.git/hooks/pre-commit` | `git commit` | what the user sees |
|---|---|---|
| a complete overcommit hook | **exit 1** | `Check for trailing whitespace … [TrailingWhitespace] FAILED`, the commit is refused |
| zero bytes, executable | **exit 0** | the offending commit is created; the pre-commit hooks are never mentioned |

The repository looks protected and is not: the file is present, it has its exec bit, and
nothing reports anything.

## Why this was not reported, and what was measured to decide it

The finding is novel on `sds/overcommit`'s tracker — the single-word sweep with green
controls found nothing about install being interrupted, and `install` and `hooks` saturate
so they were read by hand (`transcripts/novelty-overcommit.txt`; that file also carries six
space-separated queries that returned zero, kept and struck through, because a zero from a
space-separated query through this API is the API's behaviour and not a fact about the
tracker — `novelty-prescan.sh`'s own header says so and this run worked around it once).

Three measurements decided the report question, and the owner's call followed them.

1. **The data comes back.** Re-running `overcommit --install` takes the checker from rc=1
   to rc=0 on exactly the crash state.
2. **Nothing the user authored is at risk.** The single path that touches a user-authored
   file is one `renameat` — atomic, measured under `strace` — and the file is intact in
   `.git/hooks/old-hooks/` afterwards. No crash can lose it.
3. **An ordinary interruption did not reach the window in 153 attempts.** Three sweeps of
   51, each 40–90 ms in 1 ms steps against a ~69 ms install: SIGINT, SIGKILL, and a third
   SIGKILL sweep that recorded the hook count per attempt. **Zero incomplete hooks in all
   three.**

   The three are not one measurement and this page does not merge them. The first two
   report `fewer hooks 0`; the third shows kills landing *inside* the install — 48 ms leaves
   1 hook of 10, 49 ms leaves 10, 50 ms leaves 1, 51 ms leaves 0. Those disagree, which says
   the timing is not stable between runs at this granularity rather than that either is
   wrong. What the third sweep establishes is that the kills do land mid-install, so the
   zeros are not the vacuous kind; what all three establish together is that none of 153
   kills landed inside one file's `open`→`write`. That window is under a millisecond. The
   shape that *is* reachable — fewer hooks, none of them partial — is one this run's
   checker accepts as legitimate and one `overcommit --install` repairs.

So: **a crash point exists and a crash does not land there.** Sideeye measures the first
and says in every report that it does not measure the second (`not tested: power loss`).
The report question turns on the second, which is why it was measured separately.

The funnel row therefore reads `novel` / `not_worth` — the first row in that ledger at
`novel`, because the stage exists for *judged and not already known* and no earlier run
both established novelty and declined to file.

## The chain, end to end

| stage | reached | what carried it, or what stopped it |
|---|---|---|
| `attempted` | ✓ | the define ran under the engine the vendored installer put there |
| `explored` | ✓ | 32 worlds, `"explored": 32` in the report |
| `judged` | ✓ | FAIL, `oracle_verified`, reproduced twice |
| `novel` | ✓ | the tracker sweep, controls green |
| `report_worthy` | **✗** | the owner's call, on the three measurements above |
| `filed` | — | nothing to file |

**This is the first time the chain has been carried past `attempted` from the adoption path
#620 ships.** The 19 rows that reached `filed` all mounted a tarball an operator had
unpacked; this one met the engine through `install-sideeye.sh`, at a pinned version, checked
against the digest GitHub publishes, and the verdict is tied to that binary by file
(`transcripts/overcommit.engine.txt` carries the installer's own stdout).

And the leg that stopped it is a judgement, not a wall. That is a different answer from the
previous run's, where the engine could not reach a verdict at all.

## What this run did not measure

- **A define with a pre-existing user hook.** `overcommit --install` moves such a hook into
  `.git/hooks/old-hooks` with one `renameat`, which is why point 2 above holds — but the
  window where the user's hook has moved and the replacement is not yet written was not
  explored. Under that define `old-hooks` holds user data and could not be declared
  `scratch`, so it is a different define, not a variation of this one.
- **Power loss.** The report says so in `not tested`, and `overcommit --install` issues no
  `fsync` — so even a completed install's durability is a separate question this run does
  not answer.
- **Any second target.** One slot, spent deliberately.
