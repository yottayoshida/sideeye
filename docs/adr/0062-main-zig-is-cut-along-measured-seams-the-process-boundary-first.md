# 0062 — main.zig is cut along measured seams, the process boundary first, and a ratchet keeps it from growing back

Status: Accepted (2026-09-12)

This ADR records the series #572 asked for — one plan, several pull requests — and the
first seam in full. Later seams amend this file when they land rather than opening one
each; what they will move is written below as measured today and is re-measured before
each is cut.

## Context

#572 asks for `src/main.zig` (9,367 lines at `2adec70`) to stop being the default home for
product boundaries that change for different reasons, without pre-deciding the module
graph: find one boundary whose contract can be stated independently and whose extraction
removes real reasoning or edit coupling, or record that none exists. `main()` alone is
2,529 lines in nine phases; thirty-five module-level variables carry report and run state
because deep refusal paths emit text and JSON.

Measured per candidate. Identifier occurrences, counted three times: the first took the
words `say` and `explored` in comments for calls; the second stripped comments but not the
string `"in an explored world"`; the awk that was meant to refute both used `\b`, which
macOS awk does not read as a word boundary, and matched nothing. The figures below are from
`grep -w` and from a computed closure of the declarations the moved code references:

| candidate | lines | tests | globals read | globals written | outside fns | refs from `main()` | refs from elsewhere | exits inside |
|---|---|---|---|---|---|---|---|---|
| process boundary | ~1,560 | 16 | `rec_image` | 0 | defang ×2 | 36 | 11 | 0 |
| report rendering | 1,198 | 11 | 21 | 5 | `unknown`, `setupError` … | 73 | 113 | — |
| refusal exits | 381 | 2 | 9 | 0 | 9 incl. `writeJsonReport` | 212 | 139 | the bodies |
| CLI | 333 | 2 | 2 | 0 | 5 | 38 | 17 | — |
| capture readers | 521 | 6 | 0 | 0 | 0 | 10 | 3 | 0 |
| saved case | 219 | 0 | 0 | 0 | `jsonCommand`, `jsonString` | 12 | 2 | — |

## Decision

**The order, by measured coupling**: (1) the process-and-thread boundary; (2) the capture
readers, and the CLI if its parse loop's refusals can be returned as values rather than
exiting in place; (3) report state and rendering together with the refusal exits — the
region every other change converges on, and the one that needs a design of its own before
it moves — with the saved-case code, which depends on the JSON primitives; (4) `main()`'s
nine phases into functions, once report state has an owner and the phases no longer need
to be handed a dozen globals. The order after (1) is what today's numbers say; each seam is
re-measured before it is cut and this ADR is amended if the order changes.

**A ratchet goes in with the first seam.** `spike/check-main-shape.sh` counts the
top-level `fn` and module-level `var` declarations of `src/main.zig` and fails the build if
either exceeds the pinned ceiling — 95 and 32 after this seam — pointing at the module map.
The ceilings only ever come down. This is not a line-count target (#572's non-goal): it
counts declarations, in one direction, and says where new behaviour goes. Same instrument
as the ratchets already in the tree (the build-option count, `RestoreError`'s arity, the
`boundary_cases` floor). Its cost is stated: until seam (3) lands, a change that needs a new
report field cannot put it in `main.zig`, which is pressure to land (3) rather than a reason
for an exception. Tests are not counted, so moving them away from the behaviour they hold
buys nothing. What it counts is the spellings a top-level declaration takes in this tree —
`fn` behind `pub`, `export`, `inline`, `noinline`, and `extern` with or without a library
name (`extern "c" fn`, which is how `src/posix.zig` binds libc); `var` behind `pub`,
`export`, `threadlocal`, `extern` likewise — and a `var` declared directly inside a top-level
container (`struct`, `extern struct`, `packed struct`, `union`, `enum`, `opaque`), which is
module state with a namespace in front of it and is how this repository's shim keeps real
state. Two review rounds falsified the guard against its own predicate, as this repository's
rules ask: the first version counted bare `fn ` and `var ` only and claimed `pub var` does
not exist in Zig while this same change declared two; the second took `extern` but not
`extern "c"`, and three lines in that spelling appended to a copy of `main.zig` read green.
The selftest now goes red in each of those spellings. What it does not count is written in
its header — a declaration nested two levels deep, a hand-formatted one-line container — and
"directly inside a container" means the four spaces `zig fmt` produces, which nothing in CI
checks today. What the ratchet does not say is *where* a declaration
belongs: a function moved from `main.zig` into the wrong module satisfies it. The module maps
say where, in prose, and a review reads them; the ratchet only removes the default of
leaving things in `main.zig`.

**The process-and-thread boundary goes first**, to `src/boundary.zig`: `BoundaryEvidence`,
the module variables `boundary_ev`, `boundary_buf` and `rec_image`, `boundaryAccount` and its
two clauses, `childrenMayBeJudged`, `unattributedWriterReason`, the four refusal-detail
renderers, the four `noShim*` functions, `withOracleCapture`, the constant
`fs_usage_silence` (read by one clause and by nothing else), the `boundary_cases` table, the
sixteen tests that hold them and their one fixture helper, `traceFileForTest`. The list is the
closure of what the moved declarations reference and nothing outside them references —
computed, not recalled: a first list drawn from function and type names alone missed both
the constant and the helper. Bodies move byte-identical with `pub` added; no name changes.
The two exceptions the dry run could not see are nested: `BoundaryEvidence.Kind` and its
`name()` gained `pub` because `main.zig`'s `OracleAsked` and #280's tag test reach them.

**A shared leaf `src/defang.zig`** takes `sanitizeForReport`, `textShown`, `appendSanitized`,
`DefangUnit`, `defangUnit` and the #167 classifier test — the choke point every
target-influenced string passes before it reaches a report line. Boundary sentences and
seventeen other call sites in `main.zig` both need it; inside either file it is an import
from the other. Same shape as `engine/read.zig` in ADR 0047. `main.zig` aliases the three
names it calls, so no call site changes.

Both files sit flat under `src/` and are named in `build.zig`'s `test_sources`. Not because
collection would otherwise fail: in this tree the main root already collects the tests of
the files it imports — the root runs 311 tests while `main.zig` declared 52 — and three
tests that stay (#280's tag test, and two of the #352 oracle-account tests through
`OracleAsked.named: BoundaryEvidence.Kind`) go on referencing `boundary.zig` directly, and
others reach it through helpers (`buildJson` → `boundary.boundaryAccount()`), so its sixteen
tests keep running under the main root as well — and, collection being transitive through a
collected file's tests, so do the tests of what those sixteen import. The prediction was
that the main root's count does not move, and it did not. Naming the file is what
`build.zig` already says naming is for: collection independent of which test happens to
mention what. The plan's first draft claimed ADR 0047's silent-drop shape would apply here;
a reviewer's three-file reproduction and the per-root counts showed it does not.

Why this seam, in the order the numbers decided it: it writes no global and exits nowhere,
so it can be reasoned about as a function of its inputs; it reads one variable from
outside itself, written once; its outward calls are the defang primitives, which belong to
nobody in `main.zig` either; its tests are the largest block in the file and already sit
together; and it is where the next real changes land (#571, #569, the v16 work) and where
the last three did (#553's account classes, #562's mode account, #567's fs_usage threads).

## Alternatives considered

- **Report rendering first** (the issue's first example). Reads 21 globals, writes 5, is
  reached from 186 sites, and `unknown`/`setupError` call `writeJsonReport` while the
  rendering side calls `setupError`: a cycle as the code stands. Restructuring how a
  refusal writes the report is a behavioural question and is not a file move.
- **CLI first.** The parse loop is inside `main()`; `spike/acceptance.sh` greps the argv
  literals out of `src/main.zig`; and `spike/freeze-audit/surface-drift.sh` settles surface
  1 on the byte identity of `src/main.zig` because `splitArgs` and `resolvePathAgainst` live
  there. Moving them without moving that list fails open.
- **Capture readers first.** Zero outward references — the cleanest region — and already a
  leaf: nothing reasons across it, so extracting it removes no coupling. Recorded as the
  next candidate with its numbers.
- **Decisions only, refusal sentences stay.** Avoids `defang.zig` and splits one family's
  sentences across two files, which is the coupling #572 is about.
- **`defang` inside `boundary.zig`.** Wrong owner: most of its eighteen callers render the
  report.
- **`rec_image` as a field of `BoundaryEvidence`.** Probably the right ownership; also a
  change of shape, not a move. Left for the first real change that wants it.
- **`BoundaryEvidence.Kind` relocated to `oracle.zig`** (a reviewer's proposal). The enum
  names witnesses (`.strace`, `.fs_usage`), and the report's oracle and metadata notes in
  `main.zig` use it through `OracleAsked`; moving it would stop `boundary.zig` exporting
  vocabulary to fields that are not about the boundary, and would leave no test in
  `main.zig` referencing `boundary.zig` at all. Probably right, and one declaration — but
  it changes spellings in report code, which this move does not. The first follow-up.
- **Adding the new files to the freeze audit's rung-1 list.** Not done, and recorded rather
  than skipped: that list settles surface 1 (config format) by blob identity because
  `splitArgs` and `resolvePathAgainst` live in `src/main.zig`, and neither moves. Surfaces
  2–5 are read by rung-2 extractors from `contract.zig`, `report-schema.md` and `mcp.zig`,
  and the gate pins those blobs and `config.zig`'s. The `processes` prose and the defang
  primitives are not on any frozen surface. This change alters `src/main.zig`, so rung 1
  reports surface 1 as partly settled rather than settled — the safe direction.
- **Renaming `boundary_ev` to `ev`, splitting `main()` into its nine phases.** Both mix a
  rewrite into a move; neither is a boundary.

## Consequences

- `main.zig` went from 9,367 to 7,652 lines; `boundary.zig` is 1,688 (1,653 moved plus a
  35-line head of module map, imports and aliases) and `defang.zig` 111 — the counts at
  commit time, two comments longer than at the move (0047's counts drifted four times
  between plan and merge; these drifted once). Report, case, CLI, MCP and contract
  surfaces are unchanged: the acceptance suite's failure set is identical before and after.
- **What measures this seam next is #571.** Fixing the Darwin exec/thread-id defect should
  open `src/engine/trace.zig` and `src/boundary.zig`, and `src/main.zig` only at the
  evidence writes if at all. If it needs the world loop or the report renderer, the seam
  was drawn wrong.
- The next seam is not decided here. By these numbers the capture readers are the
  cleanest, the CLI needs the freeze-audit list moved with it, and report rendering needs
  the refusal-writes-report structure looked at first. The one-declaration relocation of
  `BoundaryEvidence.Kind` to `oracle.zig` is the cheapest next step and tightens this
  seam's contract; it is its own change. Doing it changes nothing in the test roots: Zig
  collects through non-test helpers as well as through tests — `main.zig`'s #553 test calls
  `buildJson`, which calls `boundary.boundaryAccount()`, and its #483 test reaches
  `defang.sanitizeForReport` through `setupOutputDetail` — so the main root stays at 311
  with or without `Kind` in `boundary.zig`. Written here because the plan's review predicted
  a drop to 294 from the direct test references alone, and the review of this diff showed
  the helper paths with a three-file reproduction.
- **Test roots.** `zig build test --summary all` gained two `run test` steps on the same
  platform (ten to twelve on macOS; eleven to thirteen on Linux, where
  `shim/src/syscalls.zig` is a root as well). The main root stayed at 311; the boundary root
  runs 253 — its own sixteen, defang's one, the whole engine root of 151 (a reference to
  `engine.zig` collects its three tests, which collect the parts and `posix`), `oracle.zig`'s
  61 and `image.zig`'s 24 — and the defang root 1. The `contract` module is a module, and
  tests are not collected across a module boundary; the main root's 311 holds none of its 26.
  The total is not a criterion — a new root re-runs the tests of every file it imports, so
  the total rises whether or not the sixteen moved.
- **Stop conditions, from #572**: a cycle, a contract type defined twice, glue larger than
  the coupling removed. `defang.zig` is about 120 lines against a family of about 1,650; a
  second leaf forced by this seam would be the signal to stop. For the series: a seam that
  needs a phase function with more than a handful of parameters, or a CLI extraction that
  cannot return its refusals as values, goes back to design rather than forward.
- **What "done" means for the series**: every boundary #572 names other than run
  orchestration has a module whose header states its contract and no body in `main.zig`;
  the ratchet's ceilings have come down with each seam; and at least one real change has
  been measured against each of the two seams that carry product semantics — #571 against
  the boundary, the first new report field against the report module.
- #572 stays open until the last seam. `Refs #572` in every commit and PR, no closing
  keyword.
