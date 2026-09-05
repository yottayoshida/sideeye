# 0049 — The judges are the third seam, and the walk and the restore go last

Status: Accepted (2026-09-05)

## Context

Two seams of #491 are out of `src/engine.zig`: the trace reader (ADR 0047) and the
snapshot types (ADR 0048). What is left, at `a2cf824`, is 3,553 lines holding two of the
issue's parts and the facade: the walk with its caps, the destructive restore with its root
vets and the corruption probe (the issue's `state_fs`), and the classification with the
L0/L1 judges (the issue's `judge`). ADR 0048 numbered them the other way round — "seam 3"
for the walk and restore, "seam 4 (`judge.zig`) will import `snapshot.zig`" — and said the
next plan would measure whether the walk and the restore could leave importing
`snapshot.zig` alone. This ADR records that measurement and reverses the order.

## Decision

**The judges go third**, to `src/engine/judge.zig`: `Violation`, `FileForm`, `PlannedFile`,
`L0Plan`, `classify`, `classifyWith`, `judgeL0`, `judgeL1`, the four private helpers behind
them (`isJudgedKind`, `snapWith`, `expectHybridAgainstCrashedKind`, `testJudge`), and the
twenty-four tests that hold them. **The walk and the restore go last**, together, as the
issue's `state_fs`.

Measured (line numbers are `origin/main` at `a2cf824`):

- **The two remaining parts are independent in code.** The judge region (1161–1404 and its
  tests at 1405–1586 and 2618–3022) names nothing from the walk or the restore in code —
  `walk` and `read` occur only in its comments. The walk and restore region names nothing
  from the judges in code either: `judgeL0` appears in two comments (1072, 1590), and the
  `#164 pin: restore goes loud` test (1587–1613) calls `restore` once and mentions `judgeL0`
  only in the second of those. Either could go first without a cycle.
- **So the smaller and cleaner one goes first.** About 830 lines against about 2,550;
  eight public names against nineteen; and five documents that will have to be re-pointed
  when the walk and the restore move — ADRs 0011, 0022, 0042 and 0046 name
  `src/engine.zig`, and `docs/freeze-audit.md` names `engine.zig`, as where the root vets
  and `freshDir` live. The judges are named that way in one place, a dated run record
  (`spike/assisted/buku/RUNLOG.md:95`), which is left as written for the reason below.
- **What the judges reach outward.** `posix.Kind`, and four names from `snapshot.zig`
  (`Snapshot` 43 mentions, `Entry` 1, `testSnapshot` 45, `scratchMatches` 4). `judge.zig`
  imports `std`, `../posix.zig` and `snapshot.zig`, and takes the four names by private
  alias so the forty-odd call sites keep their spelling. **The aliases must stay private**:
  a `pub` alias would not fail the facade walk — the same name is already re-exported from
  `snapshot.zig`, and the identity check passes on the same declaration — so the check for
  it is the count of `pub` declarations in `judge.zig`, which is eight.
- **What the judges are reached by.** `main.zig` spells `engine.L0Plan` three times,
  `engine.Violation` three, `engine.classifyWith`, `engine.judgeL0` and `engine.judgeL1`
  once each (`engine.classify` appears in a comment only); `mcp.zig` none. All through the
  facade; none change.

**Answering 0048's question.** The walk and the restore can leave `engine.zig` importing
`snapshot.zig` alone: their code reaches outward to `std`, `contract`, `posix`, `read`,
`trace`, `snapshot` and `engine_build_options` — the last a module import, resolved from
under `src/engine/` the way `snapshot.zig` resolves `contract` — and to nothing in the
judges. The three symlink-agreement tests 0047 and 0048 wrote about (the rebuild refusing
to write through a link, `corruptState` refusing a planted link, the three regions carrying
links as links) exercise `takeSnapshot`, `restore` and `corruptState` only, so they move
with `state_fs` and cross nothing.

**Two things stay in `engine.zig` that the word "judge" might claim.** `WorldResult`
(1695–1701) holds a `?Violation`, but its content is a kill's outcome — `k`, `term`,
`landed` — and `main.zig`'s world loop is what produces it; it is the orchestrator's type
and stays with the facade. `SnapshotError.ClassifyFailed` is raised by `walk` (322) when an
entry's kind cannot be classified, and `main.zig` renders it as "an entry inside the state
tree could not be classified"; the name shares a word with `classify` and nothing else.

**The facade test walks three parts**, and `refAllDecls(judge)` joins the block that makes
collection unconditional.

**This ADR supersedes two sentences of ADR 0048**: "Seam 4 (`judge.zig`) will import
`snapshot.zig`; that is the right direction" — the direction stands, the number does not,
and the judges import `snapshot.zig` directly rather than reaching it "through the
facade"; and "For seam 3. `SnapshotError` and the four cap/diag types go with the walk …
now they are the cost of the next seam rather than this one" — those types and those
tests are the cost of seam 4, deferred once more. 0048 is not edited; this is the same
shape as 0048 correcting 0047's prediction about the symlink tests.

## Alternatives considered

- **The walk and the restore third.** No cycle either way, so the choice is cost: the
  larger region, more public names, and five documents to re-point. A first draft of the
  plan gave a third reason — that the `restore goes loud` test would be stranded if the
  judges went second — and a first-look reviewer showed it empty: the test does not call
  `judgeL0`, it names it in a comment.
- **Both in one change.** #491 says one seam per change.
- **`WorldResult` into `judge.zig`.** It holds a verdict but is not one.
- **The `restore goes loud` test into `judge.zig`.** It measures `restore`'s `mkdir`
  failure; it needs nothing from the judges.
- **Rewriting the judge tests to spell `snapshot.testSnapshot`.** Forty-five sites for
  what four alias lines do.

## Consequences

- `engine.zig` loses about 830 lines and gains eight re-exports; exact counts are written
  at commit time. `main.zig` and `mcp.zig` are unchanged; the report, the case format, the
  CLI and the MCP surface are untouched.
- `snapshot.zig`'s header changes in two sentences and nowhere else: the judges now import
  it rather than reaching it through the facade, and `classify`, `classifyWith` and
  `L0Plan` are named as living in `judge.zig`.
- `spike/assisted/buku/RUNLOG.md` names `judgeL0` as `engine.zig`'s in a dated run
  record; it is left as written.
- **For seam 4 (`state_fs`)**: it imports `snapshot.zig` and nothing from `judge.zig` —
  nothing in the walk, the restore or their tests names a judge in code. The documents to
  re-point are ADRs 0011, 0022, 0042 and 0046 and `docs/freeze-audit.md`;
  `engine_build_options` needs nothing. The three symlink-agreement tests and the
  `restore goes loud` test move with it.
- **Open, for seam 4's plan**: after `state_fs` leaves, `engine.zig` is the facade plus
  `WorldResult`. Whether the orchestrator's one type belongs in the facade or in
  `main.zig` is that plan's call; this one does not decide it.
- **Stop conditions, restated from #491**: a cycle, a contract type defined twice, glue
  larger than the coupling it removed. None arose; none was close.
- **#491 stays open after this change**, with one seam left. The commit message and the PR
  body say `Refs #491` and keep every closing keyword out of the clause that names it.
