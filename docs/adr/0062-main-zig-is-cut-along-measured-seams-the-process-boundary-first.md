# 0062 — main.zig is cut along measured seams, the process boundary first, and a ratchet keeps it from growing back

Status: Accepted (seam 1 merged as `dbcfe7a`, 2026-09-12; amended for seam 2 the same day — see Amendments)

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
target-influenced string passes before it reaches a report line. Boundary sentences (six call
sites in `boundary.zig`) and the report side (thirty-four call sites across fourteen
functions of `main.zig`, tests excluded, counted at the move) both need it; inside either
file it is an import from the other. Same shape as `engine/read.zig` in ADR 0047. `main.zig` aliases the three
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
- **`defang` inside `boundary.zig`.** Wrong owner: thirty-four of its forty call sites are
  in `main.zig`, rendering the report.
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
  35-line head of module map, imports and aliases) and `defang.zig` 112 — the counts at
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

## Amendments

### Seam 2 — the capture readers (2026-09-12)

Re-measured at `dbcfe7a` before the cut, as the Decision requires. What moved to
`src/capture.zig`: `observeCapture` and `CaptureObservation`, `readFileAllocCapped` and
`ReadMode`, `readFileAlloc`, `readFileFrom` and `Appended`, `readSetupCapture` with
`SetupCapture`, `setup_capture_cap` and `lastNonEmptyLine`, the two `config_read_*`
constants, and the six tests that hold them — thirteen declarations, 617 lines. The closure
again found what the list in this file had not: `readFileFrom` (the #400 test names all
three readers under one title, "at every call site", so leaving one behind would split the
sentence that test holds across two files) and the two constants
only `readFileAllocCapped` reads. The setup-capture reader went on ownership rather than
closure: its three answers (`unreadable`, `empty`, `line`) are the reader's contract and its
doc comment says "one reader for both callers"; the renderer that turns them into a
sentence, `setupOutputDetail`, is the report's and stays. Bodies moved byte-identical with
`pub` on nine declarations and on two nested methods (`fingerprintEql` and `sawTruncation`,
which `main.zig` compares captures with at four sites); two lines changed — the
`observeCapture` tests' `defer removeFile(path)` became `defer _ = posix.unlink(z.ptr)` on
the handle each test already held, because `removeFile` is the orchestrator's glue with
twenty-five callers and this file imports nothing of `main.zig`. Imports: `std`, `contract`,
`posix`; no global read or written, no exit. `main.zig` calls in at nineteen lines and went
from 7,652 to 7,046 lines (641 out — the 617 moved, the rewritten call sites and the old
module map — and 35 in: one import and a longer module map); `capture.zig` is 664, counted
after its header was rewritten twice in review.

**Why this seam removes coupling after all.** The Alternatives above called the readers
"already a leaf: nothing reasons across it, so extracting it removes no coupling". That was
measured on identifier references and is true of them; it is not true of the rules. The
guards are one rule set applied at several sites, and twice a rule reached some readers and
not others while they sat four thousand lines apart in one file — the descriptor
classification (#400: an `lseek` happened to refuse a FIFO and nothing refused `/dev/zero`)
and the symlink refusal (#469: given to one of the two readers of `<work>/oracle.txt`). The
next change to a reader rule opens one file whose header states the rule, instead of three
sites found by grep. That is edit coupling in #572's sense, measured on two incidents rather
than on reference counts, and it corrects the sentence above.

**What the header may claim, corrected in review.** The first draft of `capture.zig`'s
module map said every reader is bounded in bytes, classifies its descriptor and refuses a
link at a name the operator did not choose. The file's own bodies falsify each:
`readFileAlloc` reads the strace oracle's capture with `maxInt(usize)` as its cap (its
fs_usage sibling is capped at 2 GiB by the caller — an asymmetry older than this change and
left as it is, since a cap is a behaviour change and this is a move); `readFileAllocCapped`
classifies only when asked (`require_regular`), and `--config` deliberately does not ask,
because `/dev/stdin` and a process substitution are legitimate spellings; and
`/etc/ld.so.preload` is neither the operator's name nor the engine's, and is followed —
`ReadMode`'s doc draws that line in three parts, not two. The header now states the one
rule every reader keeps — "could not be read" is never answered as "was empty" — and says
that the other guards are the caller's to choose through `ReadMode`, link refusal alone
following from who named the path (the second review caught the first fix saying all three
did: `/etc/ld.so.preload` is the system's name and is classified, `--config` is the
operator's and is not, and a byte ceiling is a caller's budget). It also names the capture
rule that is not a reading rule: the work-directory captures refuse a FIFO at the name
because they are created with `Capture.exclusive`, which adds `O_EXCL` to
`posix.captureFlags`' `O_CREAT|O_TRUNC|O_NOFOLLOW` (the same review corrected a draft that
credited `captureFlags` itself with the `O_EXCL` — `exclusive` defaults to false, and a
capture added without it would meet the hang `posix.zig`'s doc warns of), so a change to how
a capture is made opens `src/posix.zig`.

**The CLI stays, and the order changes for it.** The Decision made the CLI's move
conditional on its parse loop returning refusals as values. Measured: the loop (`main.zig`
2075–2225 at `dbcfe7a`) exits through sixteen `setupError` calls and between them writes
state fifteen times — six of it report state (`noteOracle` three times, `checker_note`,
`l1_note`, `settleDeclared`), the rest run configuration (`stop_when_orphaned`,
`expected_status_val`, `json_path` with the `removeFile` beside it, the apparatus and
scratch flag buffers), the allocator `json_arena`, `SIGCHLD`'s disposition, and
`boundary_ev.witness` twice — and the order of the six relative to the exits is product
behaviour that #352's tests pin: an oracle named by a flag is reported as named by a refusal
later in the same argv, and `--json` removes the previous report before any later refusal
can write a new one. A parser that returned a refusal instead of exiting would have to return
the ordered effects to replay first, which is glue larger than the coupling removed, or call
report state that has an owner — and that owner is seam 3. So the CLI moves with seam 3 or
after it, which is the stop condition written above. Moving `Args`, `splitArgs` and the
`resolve*` family alone, with the loop left behind, would split one family across two files;
not done. The freeze-audit rung-1 list is unchanged for the same reason: `splitArgs` and
`resolvePathAgainst` are still in `main.zig`.

**Ratchet**: 95 → 89 functions; 32 variables unchanged — nothing here is state. **Test
roots**: one more `run test` step (12 → 13 on macOS, 13 → 14 on Linux); the main root stayed
at 311 (its #483 renderer test calls `readSetupCapture`, so collection reaches `capture.zig`
from that root and the six run there as well), the boundary root at 253 (`boundary.zig` never
references `capture.zig`), and the capture root runs 31 — its own six plus `posix.zig`'s 25;
`contract` is a module, across which tests do not travel. The total went 1,033 → 1,064. Every
number in this paragraph was written in BUILDLOG before the move and matched after it.

**What measures this seam next**: the next reader rule — a new descriptor kind to refuse, a
new bound, a new link policy — should open `src/capture.zig` and its header, `src/main.zig`
only where a call site chooses a `ReadMode`, and `src/posix.zig` only if the rule is about
how a capture is created rather than read. If it needs a change to a body in `main.zig`, the
seam was drawn wrong.

### Seam 3, first half — what a run says and how it stops (2026-09-13)

The seam the Decision called the region every change converges on, cut after a design
review of its own: two fresh reviewers, the second falsifying the first's fix (the plan
records both rounds). Re-measured at `39da3cf`: the declarations of `main.zig` in seven
groups, edges between groups counted on code with comments and strings stripped. The
report's state (36 declarations, 343 lines) references nothing but imports. The renderers
(54, 1,275 lines) reference the state and no refusal — the Alternatives above say rendering
calls `setupError`; measured, it does not, and the cycle this ADR feared is not there. The
refusals (24, 810 lines) reference the state, six renderers, and the live-observer registry
(`stopLiveSidecar`, `dropCapture`), while `startFsUsage` references the refusals back: the
one cycle in the graph. It is broken by keeping the registry with the refusals — its own doc
comment says it exists so the two exits cannot forget to stop the sidecar — and the
observer's start in `main.zig`.

**Three files.** `src/report.zig` (1,603 lines) owns what a run says: the account's facts
(`oracle_note`, `checker_note`, `l1_note`, `l0_note`, `case_note`, `explored`, `violations`,
`setup_status`, `scratch_declared`, …), the helpers that set them from what the parser has
established (`noteOracle`, `settleDeclared`), and both renderings — `say` for the text,
`buildJson` and `writeJsonReport` for the document — with thirteen tests. `src/refuse.zig`
(957 lines) owns how a run stops: `unknown`, `setupError`, `setupErrorFmt`, `spawnFailure`,
the classifiers and `*OrRefuse` helpers, `json_path`, `json_arena`, `run_phase`,
`SpawnPhase`, `trace_budget`, and the observer registry, with four tests. `src/files.zig`
(44 lines) is a leaf for `removeFile` and `writeWholeFile`, which the orchestrator, the
renderers and the refusals all call: the second leaf a seam has forced (`defang.zig` was the
first), forty-four lines against two thousand five hundred moved. `posix.zig` was the
obvious owner and was not chosen because both bodies spell their calls with the `posix.`
qualifier and size their buffers with `contract.max_path`, and that file imports `std` and
`builtin` only. Edges are one-way: `report.zig` imports neither `refuse.zig` nor anything
that will move later; `refuse.zig` imports `report.zig`; `main.zig` imports all three.

**What the move changed, declared.** Bodies moved byte for byte, with `pub` on 44 names of
`report.zig`, 21 of `refuse.zig` and both of `files.zig` — the counts the design reviewer
had computed independently. Two edit classes beyond `pub`, both listed line by line in the
pull request: a refusal body that reaches a fact of `report.zig` spells it `report.<name>`
(16 lines), because a module-level variable cannot be aliased — a container-level `const x =
report.x;` would copy its initial value — where functions can; and the aliases `main.zig`
already carried for `defang.zig`'s primitives are re-declared in `report.zig` and
`refuse.zig` beside new ones for `say`, `removeFile` and `writeWholeFile`, so that the moved
call sites read as they did. `main.zig` keeps `say`, `setupError`, `setupErrorFmt`,
`unknown`, `spawnFailure`, `removeFile` and `writeWholeFile` as aliases for the same reason,
and spells the report's facts `report.<name>` at 88 lines and the other refusal helpers
`refuse.<name>` at 36. One `say` call's hand-aligned argument columns were re-aligned by
`zig fmt` after the prefixes lengthened its tokens — whitespace only. A first generation of
the tree had the extractor rewrite the word `explored` inside seventeen string literals of
refusal sentences; the unit tests stayed green, the acceptance suite in the container went
red on one leg, and the tree was regenerated with string literals masked (BUILDLOG
2026-09-13). The container run is a criterion of this series for that reason.

**What stays in `main.zig` by decision.** `splitArgs`, `commandArgv`, `resolvePathAgainst`,
`resolveCommandAgainst`, `resolveCommand`: the freeze audit's rung 1 reads surface 1 out of
`src/main.zig` because they live there (see the Alternatives above), its list requires each
path to exist at both ends of a window, and the two moves that would have taken them out
both fail — into a new `cli.zig`, the list cannot follow (a path absent at the window's base
is a `FAIL`); into `config.zig`, the graph closes a cycle, because `resolve*` call
`setupError` and the renderers call `config.apparatusUnchecked`. Their callers are `main()`
and the apparatus check only — never the CLI group or the parse loop — so leaving them
splits no family. The ratchet stops at 31 functions rather than 26 for it. Also staying:
the CLI parse loop and the saved-case code (the second half of this seam), the apparatus
check, the observer's start, the demo, `preflightReport`.

One edge is recorded as a candidate rather than moved: `report.zig`'s `setupOutputDetail`
clamps a setup's output line with `mcp.cutOnBoundary`, so the report imports `mcp.zig` for
one UTF-8 helper; the first real change to that renderer can move the helper to
`defang.zig`, where the other clamping primitives live.

**Ratchet**: 89 → 31 functions, 32 → 4 variables (`apparatus_flag_buf`, `scratch_flag_buf`,
`stop_when_orphaned`, `startup_ppid`), and its predicate widened once more: the review of
this seam appended a `const phases = struct { fn a() … fn b() … fn c() … }` to a copy of
`main.zig` and the check read green — it counted a container's `var` but not its `fn`, and
its own selftest decoy held a method that pinned the hole. A `fn` directly inside a
top-level container now counts (the tree has none today, so the ceiling is unchanged), the
selftest tries it in both spellings, and the check's label follows the file it was pointed
at. Three reviews have now falsified the guard against its own predicate; each time the
accident's shape had been closed and the predicate's had not. **Exits**: twelve `std.process.exit` lines stay in
`main.zig` (ten in `main()`, two in `preflightReport`), two are in `refuse.zig`. **Test
roots**: 13 → 15 on macOS; the main root stayed at 311, boundary 253, capture 31; the report
root runs 295 — its thirteen, the boundary chain of 253 that `buildJson` reaches through
`boundaryAccount`, `capture.zig`'s 6, `config.zig`'s 15 and `mcp.zig`'s own 8 — and the
refuse root 299 — its four plus the report chain; total 1,064 → 1,658. Every number in this
paragraph was written in BUILDLOG before the move and matched after it. `files.zig` holds
no tests and is not named in `test_sources`.

**What measures this seam next**: the first new report field. It should open
`src/report.zig` (a fact, a line in `buildJson`, a line in the text renderer) and
`docs/report-schema.md`, and `src/main.zig` only where the phase that knows the value sets
it. If it needs a new module-level variable in `main.zig`, the ratchet refuses it, and that
is the seam working rather than a reason for an exception.
