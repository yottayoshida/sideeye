# Buildlog

Development journal, newest first. Decisions are recorded when they are made — including the ones that turn out wrong. This file is allowed to be embarrassing in hindsight; that is what it is for.

## 2026-08-27 — the snapshot gets a memory ceiling, and the verification moves from "did it refuse" to "how much had it read" (#323)

`max_state_file_bytes` bounds one read. The tree's total was unbounded, and the constant's own comment says so — "a tree's TOTAL stays unbounded, and this constant must not be read as a memory ceiling for the run". So 60 MiB × 1000 files passes every per-file check and ends in an OOM kill with no report, which is the failure shape the per-file cap was built to remove. This entry is being written as the work happens; the paragraphs below arrived in this order.

**The plan's first metric was a hand-rolled sum, and first-look review broke it with a measurement.** The proposal was to accumulate `content.len + rel.len + @sizeOf(Entry)` per entry — the `rel` and `Entry` terms specifically so that a tree of a million empty files could not pass with zero content bytes. The reviewer built a Zig probe reproducing `walk`'s allocation pattern and compared that sum against `ArenaAllocator.queryCapacity()`: **1.70× on one 64 MiB file, 2.43× on three ~42 MB files, 7.07× on 200,000 empty files** — the worst ratio on exactly the shape the extra terms were invented for. `std.ArrayList` grows by realloc-and-copy inside an arena that never frees, and the `rel`/content interleaving keeps breaking `ArenaAllocator.resize`'s last-allocation fast path, so every growth strands the previous buffer. The plan had hedged this as "a small constant factor" and then computed the whole memory budget as if the constant were 1 — a contradiction inside one section. **The metric is now `queryCapacity()` itself**: it is the quantity being bounded, it covers stranding, `rel`, `Entry`, symlink targets and the `.missing` branch's dropped `rel` without naming any of them, and it cannot drift from allocator behaviour the way a written-down proxy can.

**The refusal stops at the break instead of walking on to learn more.** The filing asked for "the total, the cap, and the largest contributors". Naming contributors means continuing past the break in an accounting-only mode, and four things measured against that: the continuation still runs `TooDeep`, `PathTooLong`, `ClassifyFailed` and `readLinkTarget`'s `ReadFailed`, and `opendir(...) orelse return` silently treats an unopenable directory as empty — so either a later failure replaces the size refusal, or the reported total quietly excludes a subtree; the breadth of one directory is unbounded and `max_depth` does not touch it (200,000 empty entries measured at 13.88 s); and ties in file size leave the top-3 order-dependent anyway, which the planned fixture — N sparse files of identical size — is precisely the case for. **The decisive one is that the continuation inverts the precedent it cited.** `FileTooLargeDiag.size` is `?u64` because "a size nobody measured must not appear in the message"; the answer that rule gives is to say less, not to walk further. The refusal names the arena's reach, the cap, the content bytes and the entry count it actually read, says those describe what was read rather than the tree, and points at `du -sb` and `find | wc -l`. Naming contributors is filed separately.

**The unit tests were green and the first thing running it for real said was that a shipped sentence was false.** The doc claimed the arena could exceed the ceiling "by the single allocation that crossed it". Against four 40 MiB files it reported reaching **305,446,540 bytes against a 134,217,728 ceiling** — 2.3x over, after two entries. `ArenaAllocator` does not add the allocation, it adds a *node* sized 1.5x *(current node + request)*, so the overshoot scales with what the arena already holds. Small-cap unit tests never enter the region where that rule matters; nothing but the real binary on a real tree was going to say it.

**Measuring what the ceiling actually accepts then found something worse: it was not monotonic in the tree.** Two 32 MiB files (64 MiB of content) were refused at 291 MiB of arena while two 64 MiB files (128 MiB of content) passed. The cause is the same rule — whether a growing buffer outgrows its node decides whether the old copy is stranded — and the consequence is a contract nobody can predict: a tree refused and a strictly larger tree accepted. **That is a fair objection to capping the arena at all**, and the response was to attack the term rather than document around it — though "remove" is what the first version of this paragraph claimed and review measured it false. What went away is the *stranding* term and the inversion that motivated it; the node-growth term inverts a different pair at the shipped ceiling, two 50 MiB files (100 MiB of content, refused at 262 MiB) against four 32 MiB files (128 MiB, accepted at 168 MiB). The property is reduced and stated, not gone.

**So `readWhole` reserves from the file's own length.** The size is a hint and nothing trusts it — the loop still reads to EOF, and past the cap it reserves only `cap + one chunk`, so a sparse terabyte cannot turn the reservation into the OOM this change exists to prevent. Reserved exactly, never `cap + chunk` on a small file, because over-reserving 64 KiB per entry is the shape a tree of many small files is made of. The cost becomes a flat **1.50x** — 100,663,448 bytes for a 64 MiB file, 50,331,800 for 32 MiB, 1,573,016 for 1 MiB — which is the node growth factor and nothing else. Trees of many mid-sized files that were refused before now pass — 4x16, 8x8 and 16x4 MiB, but **at the 128 MiB value this work was carrying at the time**; 64x1 MiB fit even then, and at the 256 MiB it ships with all four fit without the reservation. Stated because the first version of this sentence read as a result at the shipped ceiling, which it is not. **Whether this belongs in a PR about a ceiling is a fair question**; the answer is that without it the ceiling has no predictable meaning, so the two are one decision.

**The ceiling moved from 128 MiB to 256 MiB, after measuring what each accepts rather than reasoning about a budget.** At 128 MiB, two 32 MiB files — 64 MiB of content, 168 MiB of arena — are refused, which is less content than the per-file cap allows in a single file; the two ceilings would contradict each other. At 256 MiB every 128 MiB-of-content shape tried passes, the exception being two files at exactly the per-file cap (336 MiB), and 256 MiB of content is refused in every shape tried. The first value came from an arithmetic that used the wrong ratio in the first place.

**The reservation broke a rule written four lines above the code it was added to, and the review that would have found it died mid-run.** `readWhole` has a second caller: `readTraceCapped`, whose catch collapses every error except `FileTooLarge` into an empty `TraceInfo` — which the engine reads as `no_shim_marker`. So a reservation returning `OutOfMemory` turns "the trace is larger than this engine will read" into "the shim never initialised", and that exact relabelling is what `max_trace_bytes`' own comment calls worse than having no cap at all. The reservation is a hint, so its failure is now dropped and the read loop grows as it did before. **The test is aimed at the call site rather than the function**, because the function returning an error is not the defect — the defect is what the caller does with it; restoring the `catch return` reddens that one test and nothing else. Writing it needed a twenty-line allocator: `std.testing.FailingAllocator` advances its index only on success, so a `fail_index` catching the first request catches every request after it, which measures "nothing can be allocated" rather than "this one large reservation could not be met". The first version of the test used it and failed for that reason, which is a fair description of the guard it was trying to pin.

**Three times in one sitting a check reported nothing because the filter was narrower than the thing being measured.** A mutation that deleted the ceiling entirely reported zero failing tests — it had not compiled, and the grep looked only for test names. A corpus measurement reported nothing four times — the compile error was invisible for the same reason, and once fixed, the output was on the same line as the test-progress text and `grep "^MEASURE"` anchored past it. Each was found by looking at the raw exit code or the whole output instead. This file already carries the general form of that lesson; what is new is that it happened three times inside the work that was applying it.

**Four numbers in the plan were wrong, and one of them is the plan's own subject.** The shipped comment beside the cap says the crashed sequence "holds three at once"; four are live wherever `crashed_again` is — `initial` and `final` are function-scoped and `judgeL1` takes both inside the world loop — and `crashed_again` predates that comment by two weeks, so it was wrong when written rather than gone stale. The plan set out to correct that — and then said two snapshot sites precede the world loop when there are three (`final_again` at `:1510`), while citing the very comment block that states the split correctly. It also read 13 committed reports and called that the corpus when 154 carry a verdict, and quoted a judged-path range of 1–3 from cohort 3 when the range across all of them is 0–95. None of these changed a decision; all four are the same failure, which is writing a count from the sample in front of me.

## 2026-08-27 — `after-1.0` is a disposition, and class A cannot take it

Three issues closed as scheduled out of v1.0 (`#201`, `#202`, `#217`, owner ruling recorded in each close comment) put a question to the manifest that it had no word for. The enum offered `defer`, and `defer` is defined on the page as deferral **to 1.x** — these are deferred *past* the frozen contract's life, which is a different fact. `tracked` means held open deliberately, the opposite of closing. `declined` had a precedent in the repo (`#94`'s exit-code split, "declined permanently") but carries a permanence the closes explicitly disclaim: "not as resolved".

**Owner ruling: `after-1.0`, unified with the label vocabulary.** That also settled an inconsistency nobody had named: four issues carrying the `after-1.0` label and still open (`#123`, `#262`, `#279`, `#286`) had rows saying `defer`. Seven issues, one adjudication, two words. They now say `after-1.0` and differ only in `state`, which is where the difference actually lives.

**The asymmetry is the substance: class A cannot take it.** Scheduling a PASS-overclaim gap out of the release is precisely the outcome class A forbids, so an enum accepting `after-1.0` there would let the one clause with teeth be satisfied by a calendar instead of by a fix, a demotion or a narrowing. The gate withholds it from A and the mutation set has the negative for it.

**This is the third enum gap this sweep has surfaced**, all the same shape: `class` had no home for the five threat-model issues (D was added), the disposition sets had no room for the seventeen migrated historical rows (`document` on a C row, `measured-already-fixed` outside A, `duplicate`), and now no word for scheduled-out. Each appeared only when real rows were pushed through the enumeration. **An enumeration designed before its population meets it will be wrong, and the way it is wrong is invisible until something has to be classified.**

**One consequence of shipping while the gate reports drift, which cost a real weakening before it was noticed.** `#323` landed `state_tree_too_large` after this sweep measured the closed set, so the offline gate now exits 3 by design — the drift leg doing its job. The mutation harness had been written to count a mutation as killed when the gate returned **non-zero**, and with a baseline of 3 that criterion no longer discriminates: a mutation that changed nothing would have scored as killed. The kill criterion is now **exit 1** specifically, and the baseline is asserted as 3 rather than 0. Twenty-one mutations, all dying with exit 1 and the message that names their predicate. The lesson generalises past this harness: **a pass/fail test whose environment starts failing for a legitimate reason stops testing anything, and nothing announces it.**

## 2026-08-27 — the re-sweep: what the audit can measure, and what it has only ever read (#281, part two)

Part one built the mechanism. This is the sweep it was built for: the snapshot moves to 2026-08-27, the table grows from thirteen rows to a hundred and thirteen, and `#281` and `#353` close. Two things found before writing a single row changed what this PR is.

**The audit's method cannot answer its own question.** For nine days the audit has decided "does this issue touch a frozen surface" by reading the issue. `#324` is the counterexample: its body never says `unknown_reason`, never says "closed set", and its resolution added `trace_too_large` to that set. What moved the surface was the *resolution*, not the issue text, and no amount of careful reading recovers it. So the surface column stops being a reading and becomes a measurement — the surfaces are code artifacts, and code can be diffed.

**Then the yardstick turned out to be moving too.** `docs/contract-freeze.md` — the normative declaration every reading is taken "strictly against" — was amended three times inside this window. `0e035eb` added surface 2's additive allowance and its closed-set exemption; `9f04932` rewrote surface 3 from "0 PASS" into a one-way verdict-to-code promise, legalising `#273`'s `--help` exit change; `975e2fd` corrected surface 4, whose previous text had split one refusal across two reason names and was *measured to be wrong*. The additive allowance that most of this sweep's readings lean on **did not exist when the snapshot being replaced was taken**. Nothing anywhere records which revision of the declaration a sweep was read against, so this one pins the sha beside the snapshot.

**The first draft of the measurement claimed more than it measured, and an adversarial review rejected the plan for it.** The draft said it "diffed the five surfaces". It diffed narrow syntactic proxies. The clearest refutation is in this window: `#273` moved the exit-code surface while the `ExitCode` enum stayed identical, so an enum diff reports "unmoved" about a surface that moved. One stated figure — "toml keys 15 → 15" — was not reproducible at all; the accepted key set is the six names surface 1 lists, and the extractor had been counting quoted strings. The measurement is now a three-rung ladder that says what each rung can support: **blob identity** (if the defining file is byte-identical the surface did not move, behavioural clauses included — which settles surface 1 outright, `src/config.zig` is unchanged), **an enumerated diff with its extraction defined in the script**, and **a named residue that is read, not measured** — split rules, presence rules, field meanings, which call site returns which exit code, input schemas, `isError`. The residue is written on the page as unmeasured rather than quietly folded into the claim.

**A predicate shipped yesterday was never satisfiable.** `--live` compared the snapshot against the tracker's open set. A sweep closes its own obligation issue, so the equality breaks the moment the sweep lands — measurably: `#86` closed at `04:06:58Z`, one second after the snapshot commit at `04:06:57Z`. It has been false ever since, and part one's close condition ("`--live` green before closing") could only have held for an instant. The predicate becomes: every tracker-open issue has an active row, and every snapshot issue that is now closed has a resolved row. That is what "the page has caught up with the tracker" actually means, and it survives a sweep closing its own issues — which also fixes the older inconsistency that `#86` sat in the *active* table while closed.

**Two ledgers, because one column cannot hold the shape.** A change is (surface, item, kind, before, after, commit, issues, legality), issues and changes are many-to-many, and `disposition` is already a class-dependent enum the gate checks — folding legality into it collides with a live predicate. So `surface-changes.tsv` holds changes and `audit.tsv` holds issues, linked by id. An active row's surface entry is a forecast; a resolved row's is a measurement. Keeping them in one column would have hidden that they are different predicates.

**Measured before writing any of it**, and re-derived from a raw capture committed in this PR rather than from the numbers above: the window opens at the snapshot commit `8feae88` (`2026-08-18T04:06:57Z`); the `unknown_reason` closed set went 24 → 29 with nothing removed; `contract_version` went 10 → 11 → 12; the MCP tool names and the exit-code values did not move. A peer session independently reproduced the closed-set figure after reporting three of the five from memory — the two neither of us had counted are `child_wait_failed` and `parent_exited`.

**A peer's correction turned a filed gap into an implemented one.** The plan was to file "a surface can move after a sweep and `--live` will not notice", since `--live` asks the tracker about issues and a surface moves in code. The peer session working `#323` then reported that `spike/check-report-schema.py`'s third claim already holds the documented closed set against the enum — traced and confirmed here: `spike/acceptance.sh:2476` calls it and `ci.yml:104` runs acceptance, so CI does hold that pair. That narrowed the gap to the audit's own record going stale, and narrowing it made it cheap enough to close: the gate now pins the `src/contract.zig` revision the sweep measured and reports any later movement of the closed set as **drift, exit 3**, after every other leg has passed so a stale audit never masks a malformed one. The first draft of that leg compared the window's base against `HEAD` and would have exited **1** the moment the next member landed — a stale audit reported as a broken one. Both directions were seen red before shipping; the addition side was driven by writing a synthetic blob into the object database carrying the exact member (`state_tree_too_large`) the peer's unmerged work adds, so this leg's first real firing is already rehearsed against its real cause.

**The first-look review returned nine P1s and no P0, and every one of them was mine.** Six were the same defect in different places — a guard whose covered set was smaller than the claim standing on it — which is the defect this whole PR is about, reproduced inside the thing that was supposed to fix it.

*The claim that was widest.* The page said the gate "holds the enumerated half of each frozen surface"; the drift leg diffed `unknown_reason` and nothing else, so renumbering `ExitCode` passed. The leg now pins one blob per defining file and compares all six enumerated sets.

*The claim that named the wrong file.* Rung 1 declared surface 1 **settled outright** on `src/config.zig` being byte-identical — including, by name, the split-on-spaces rule, the argv form's verbatim passing and relative-path resolution. Those three live in `src/main.zig`, which **changed in this window**. So the one surface the ladder claimed to settle was not settled, and the ladder's own headline result is now "it settles none of the five on this window". That correction costs the page its best sentence and is the most important thing review found.

*The guard that read "unmeasured" as "unchanged".* The resolved table rendered `surface_change_ids=none` as "measured: no frozen surface moved", on rows (`#326`, `#336`) whose subject is the MCP input schemas and the `isError` rule — which the measurement itself prints as **not measured**. It now renders as "no attributed enumerated change".

*Three guards with an empty or unchecked covered set.* An empty classification axis passed, because a split of an empty string yields zero elements and the enum loop never ran — so a snapshot issue could sit in the table with no forecast at all. The change ledger's `legality` column, the axis this sweep introduced to say whether a movement was permitted, accepted any string or none. And the head side of every set comparison was never asserted non-empty, so breaking an extractor there reported every element as removed and still exited 0 — the mirror image of the base-side assert added the same day, which is the shape I had already been bitten by once.

*The check that trusted a claim instead of recomputing it.* The window accounting read the capture's own `returned_below_limit` boolean. Truncation is this audit's originating defect, and a capture asserting `limit=100, returned=152, returned_below_limit=true` passed. All three facts are recomputed now, plus that the recorded command carries the recorded limit.

*The falsification that proved the wrong thing.* Each run deletes a row from a copy of the page and requires the copy to fail — but it checked the copy with a **different predicate** (row count and number set) than the real leg (`render-audit.sh --check`). A mutation making the render check always succeed left the falsification green. `--check` now takes a page path and is run against the tampered copy; that mutation is in the set and dies.

*And the evidence that was not committed.* ADR 0028 rests on a negative claim — `#324`'s body names neither `unknown_reason` nor the closed set — while the sweep's capture deliberately excludes bodies, so a reader could not check the one counterexample the design change stands on. `capture-2026-08-27-issue-324-body.json` commits it, with the term counts taken on both the raw text and a whitespace-normalised copy.

Two P2s were stale numbers in places the same correction had already been applied elsewhere: `PRD.md` still said class A was "eleven rows, all resolved" after the page had been fixed to "ten resolved and one active", and `surface-drift.sh`'s header still said "three of the six commits" after the page and the ADR had moved to nine. Both are the cost of writing a figure in more than one place, which is what generating the tables from a manifest exists to prevent for rows and does not do for prose.

The mutation set is nineteen after the fixes, each negating one named predicate, all nineteen dying with the message that names it. Three of the six new mutations were harness bugs on their first run — an ambiguous anchor, and two mutations caught by an earlier leg than the one they targeted — and the harness reported all three as failures rather than passes, which is the property it was given after anchors drifted silently in an earlier PR.

**Two more things found after the review, by tools pointed at something else.** A `/simplify` pass found that the six enumerated-set extractions now existed **twice** — once in the drift script, once in the gate, identical logic under different names, hand-synced with nothing pinning them together. That is the shape `#65` tracks, and here it would have failed in the worst available way: the gate and the drift report would have disagreed about what a surface *is*, each internally consistent while doing it. They now live in one sourced file, and the drift transcript is byte-identical across the refactor, which is what makes it a refactor.

And the **secret scan**, reading the diff for credentials, printed a line containing `**narrow**: **narrow**:`. Four of the seventeen migrated rows opened their rationale with their own disposition, which the renderer prepends — so the page rendered it twice. Byte-equality between page and render could not see it, because both sides were doubled. The prefix is stripped in the migration and the gate now refuses a rationale that restates its disposition, with a mutation for it. Twenty mutations now, all dying with the message that names their predicate.

**R2 confirmed all eleven as ADDRESSED with no new P0**, and judged the PR mergeable on its own.

**Three ways the instruments lied during this work, all in the direction of "everything changed".** `git show "$REV:path"` under zsh silently drops the path — `:s` is a history modifier — and prints the commit's diff instead, where every line of the file carries a `+`; the first closed-set measurement therefore read "29 added" against a base that had extracted to nothing. `git log -S` counts occurrences, so editing a constant's value on a line whose text is otherwise unchanged is invisible to it, which is why the `contract_version` bumps came back as zero commits. And a grep for a clause of the declaration reported it deleted when it had only re-wrapped across a line break. Each is now a rule in the drift script: brace the revision, assert the base extraction is non-empty before reporting any difference, use `-G` for value edits, and normalise before counting prose.

## 2026-08-27 — the freeze audit gets a trust root, and the gate finally says what it guarantees (#281, part one)

`#281` asked for a re-sweep. Measuring the sweep before starting it turned it into two pieces, and this is the first: the audit's trust root moves from a hand-written Markdown table to a manifest the table is generated from, the gate gains semantic predicates, and it gains the one thing it never had — the ability to notice drift on its own.

**Three things measured before any of that was decided, all of which changed the plan.**

*The acquisition command truncates silently.* `gh issue list --json ...` without `--limit` returns **30**; with `--limit 1000` it returns the real count. Thirty is exactly the page size, so a truncated count looks like a count — no gap, no ellipsis, no warning. **The two numbers move differently and that is the tell**: the default reads 30 whatever the tracker does, while the limited form read 56 during this PR's planning and 55 after a peer closed #351, so the count dropped was 26 then and 25 now. Both queries are captured at one instant in `spike/freeze-audit/capture-2026-08-27-limit-truncation.json`, because the first version of this entry asserted the claim in prose and committed a capture of a different query — which is the same defect the claim is about. The first plan's acquisition step had no `--limit`, and **the snapshot and the table would have agreed perfectly on the truncated set**: green, complete-looking, wrong. For a gate whose whole subject is completeness that is the worst available failure. Every query in this PR carries `--limit 1000` and asserts the returned count is strictly below the limit, because reaching the limit is indistinguishable from being cut off. (A peer had already reported "30 open issues" to the owner from the unlimited form; the real number that day was 55.)

*The existing thirteen rows do not follow the page's own rule.* The page says classes are "for touchers". Counted: three touchers carry classes (`#39` A, `#123` C, `#156` C), **six non-touchers carry class C** (`#62`, `#63`, `#64`, `#65`, `#160`, `#161`), three non-touchers carry none, and `#86` — the issue that introduced the rule — carries neither. Four patterns for one rule, on thirteen rows. Multiplying that by four and calling it a gate is not something a reviewer could check, and it is why the trust root moves.

*The gate's guarantee was never written down.* `#353` states it as "no open frozen-surface issue at the freeze", and that is measurably not it: `#39`, `#123` and `#156` are open touchers and criterion 5 is met. `PRD.md`'s actual wording is "none left as a documented hole under an intact PASS claim". Nobody had turned that into a sentence the page states and the gate checks.

**The invariant, and one place where the question was posed more loosely than the page already puts it.** The owner ruled that an executed adjudication clears the gate whether or not the issue is open. Writing it up against `docs/freeze-audit.md`'s own class-A definition — "prose alone cannot retire one; resolution is fix, demote to a refusal, or narrow the stated promise" — showed the option had been offered as "a narrowing written in prose still counts as execution", which flattens the distinction the page draws. **Narrowing counts because it changes the promise, not because prose suffices; explaining a gap without narrowing anything is exactly the "prose alone" the page refuses.** The recorded invariant uses the page's framing rather than the option's. This is the shape a peer had warned about hours earlier from the other direction: a ruling written without checking what the existing rule already said.

**What is deliberately not here, and the one thing that is.** The sweep itself is part two, and it closes `#281` and `#353`. The thirteen existing rows are migrated into the strict form, which is what proves the form before the rest arrive — **and that migration is itself a classification change on four rows**: `#86`, `#118`, `#140` and `#147` carried no class and now carry C, because the two-axis ruling makes class apply to every row. Saying "no issue is classified here" would have been false, and it was in the first draft of this entry. The row count part two faces is whatever the tracker says when it runs; it read 56 during planning and 55 after `#351` closed, which is why `--live` reports it rather than this entry fixing it. `PRD.md` is untouched: this PR does not replace the snapshot, so criterion 5's evidence still stands as written.

**`--live` reports a red result on purpose.** The check sits outside CI because it needs the network — which is precisely why it can reach the tracker, a fact the first plan missed while arguing that detection could not be added. Its first run here legitimately reports the drift the audit has been carrying: thirteen in the snapshot against fifty-six open. That output is part two's input, and it is the substance of what `#353` asked for. The default mode is unchanged and stays green.
## 2026-08-27 — the predicate that deletes stops accepting what the predicate that names refuses (#358)

#329 gave the naming vet an outward read of the denied lists — refuse a root that is an *ancestor* of a denied entry, not only one inside it — and left `assertSafeRoot`, the predicate behind every delete, byte-identical. #358 is that gap, and this closes it by moving the outward read into the helper both predicates share, so the state where only one has it cannot be built.

**The gap is one path, and saying only that would be the wrong measurement.** Enumerating every proper ancestor of both lists through both predicates: destructive accepts and naming refuses exactly `/private/var`. But production realpaths before it vets (`--state` is resolved, then checked), so **on macOS a typed `/var` arrives as `/private/var` and lands in the hole** — from the input side it is two spellings, not one. A first draft of this entry used the lexical count to call the filing an overstatement. The count is right; it is about a domain the harm does not live in.

**The harm's conditions, stated because the filing overstated them.** `/private/var` is `drwxr-xr-x root:wheel`, so an ordinary user's delete fails on permissions — and `/private/var` exists only on macOS, while the container the README recommends is Linux. **So the realised harm is macOS, running as root or otherwise able to write there.** The filing said "empties it once per explored world" and a first correction reached for "containers run as root", which contradicts the Linux half of the same paragraph. Permissions stopping it is not a defence this engine provides; it is also not the same as the engine stopping it.

**The verification changed shape after review, and that is the finding worth keeping.** The draft's two checks were both `expectError` on a pure function. This PR changes what the engine refuses to *delete*, and nothing in the plan deleted anything — the shape this file already records the #266 security review catching ("the four undo calls could all be deleted under a green suite"). The reason given for having no acceptance leg was also wrong twice over: it claimed a non-existent `--state` dies at realpath, when `posix.mkdir` runs first and creates it; and the real vacuity risk was different — a leg aimed at `/var` would be green before the change too, because the depth rule already refuses it, so the green would attribute to the wrong thing.

**So the leg builds its own ancestor.** `-Dtest-ancestor-probe` produces a separate binary whose denied list carries a synthetic entry under `/tmp`, making its parent a depth-2 ancestor that no privilege is needed to create. The leg plants a sentinel there and runs a real replay with `--fresh-state` — explore would not do, for the reason two paragraphs above: today the sentinel is destroyed, after this change the run refuses and it survives. **The shape is #266's leg A, but not its defining property** — that one still runs the destruction for real on every suite run, because the unconfined path survived its own fix. Here the red is a one-time recorded observation plus the mutation, and borrowing the shape without saying that would be borrowing its falsification too.

**The CI guard is a direct observation, not the sha comparison it was modelled on** — but the reason written here first was wrong, and review measured it. The claim was that flipping this option's default would ship the entry while the trace cap's default cannot, because the denied list is one shared const. Both are false in the same way: each option's shipped value is a separate literal in build.zig, so **neither default reaches a released binary** — measured by flipping this one, which left the shipped binary clean. What a sha comparison actually cannot see is an **edit to the shipped literal**, which lands in both arms and leaves them matching; that edit does put the entry in the shipped binary, also measured. The grep is right, for that mutation.

**And the trace cap has the same hole, still open.** Editing its shipped literal from `0` to `64` changes the released binary while its own step's shas match, so an engine with a 64-byte trace ceiling would ship green. That is #324's step, not this change, and it is filed as #365 rather than widened into here — but it is the same lesson twice: a differential check cannot see what lands on both sides of the difference.

**The first version of this apparatus broke a sibling build, and every check that was run stayed green.** `engine.zig` reads the new option unconditionally, so every options module handed to a build of `main.zig` has to carry the field. Three of the four got it by hand; `-Dtest-trace-cap`'s two did not, and that build stopped compiling — upstream in CI of everything this change adds, so the branch would have died before acceptance ran at all. What was measured was `zig build`, `zig build test`, and the new option: three variants out of four, and the fourth was the one edited around. The modules are built by a helper now, which makes a module short a field unconstructible rather than detectable. Review found it; no check here would have.

**And `grep -a` is in the step for a reason that is not the one first written either.** The comment said plain `grep -q` exits 1 on a binary match and called it measured. GNU grep and BSD grep both exit 0 — what exited 1 was this session's shell replacing `grep` with ugrep, which skips binaries. The measurement had been taken through a tool CI does not run. `-a` stays, because it also makes the check correct under such a replacement; the justification is now what it actually buys.

## 2026-08-27 — the snapshot's other failures stop claiming the define never ran, and say what happened (#351)

#330 gave the per-file cap an honest verdict at the four post-recording snapshot sites. It gave it to the cap alone: one line, `if (e != error.FileTooLarge) setupError(what)`, still sent the other six `SnapshotError` values to exit 3 — "the define did not run" — after the define had run to completion. `TooDeep` fires at depth 33 and a target reaches it by making directories during its own operation.

**Everything measured here ran on macOS, through a host build, without an oracle — the production refusal path, not the shipped legs**, which run only in the Linux container with `--oracle /usr/bin/strace`. Nothing in this repository has yet executed either new leg on Linux; CI is the first thing that will.

Measured before changing anything: an operation of `mkdir -p <state>/d0/…/d39` returns exit 3 with `could not snapshot the final state` and nothing else, and `preflight` does the same because its cut is past the final snapshot. **That the failure is `TooDeep` was not observable** — the message carries only the call site's `what`, so the defect being fixed here is what prevented measuring the defect. What could be measured is the boundary: 32 nested directories snapshot fine and 33 refuse, which is where `depth > max_depth` with `max_depth = 32` and a strict `>` puts it. (The first version of this paragraph cited 31 and 33 — two points that are consistent with a boundary at 32 *or* at 33, and so do not reach the sentence they were offered for. Review asked for the point in between; it is the one that decides it.) After this change the reason is in the text, so the leg asserts it directly; the ordering — verifiable only once fixed — is the point worth recording.

**Two decisions came from adversarial review, and both are corrections to how this side measures rather than to what gets built.**

*The reason is computed once, not passed per site.* The draft threaded `reason` through `snapshotRefusal(reason, detail)`, arguing that a mistake was pinned in both directions by the existing cap leg and the new one. Review counted the call sites: **four, not two** — the cap's measured-size branch, its no-measured-size branch, its no-arena fallback, and the non-cap path — and two of those are reachable by nothing, as the source says about the no-arena one in its own comment. Two sites could have named the wrong reason with every check green, which is verbatim what #330 rejected a parameter to avoid. A single ternary at the top of the `catch` makes the mistake unrepresentable. The mutation changed with it: inverting the ternary reddens the cap leg **and** the new leg together, and that simultaneity is the evidence, because one expression cannot be half-broken. **That is not the pair-mutation error #329 hit** — there the pair was two independent loops either of which survived alone. Worth separating here so the two are not confused later.

**Four mutations, with attribution, plus two the second review asked for.** Routing the non-cap path back to `setupError` reddens both new legs and leaves the cap legs alone. Inverting the ternary reddens the cap leg and the post-recording leg together, as above. Sending the `.before_exploration` arm to `unknown` reddens **both** initial legs, cap and non-cap — the arm is shared, and the plan's first draft had claimed the new one alone would move. Deleting the `TooDeep` arm of the message switch reddens both non-cap legs' text while leaving their exit codes right — **measured before the switch was typed; in the shipped code the same deletion is a build failure**, which is the improvement the paragraph below is about.

The two added after review: changing the final site's `what` reddens the post-recording leg alone, which answers whether that leg's `final state` assertion is a piece that survives on its own — it is not, it is falsified by itself. And **deleting the `OutOfMemory` carve-out leaves all four legs green**, which is the finding that mattered: the deviation this entry argues for is the one line no check covers.

*A check that passes before the change checks nothing.* The draft's initial-snapshot leg asserted exit 3 and the existing message — both already true on main, and none of the three planned mutations reddened it. The justification given was "the same paired structure as #330's 2fc", which is a false analogy: **2fc was born with #265 and saw its own red; #330 borrowed a leg that had already been falsified.** Borrowed falsification is not falsification. The leg now asserts the new detail text, which main does not produce, so it is red at birth.

**`OutOfMemory` is left where it was, against the ruling's own list.** The ruling named six errors; `main.zig`'s `spawnFailure` already states the rule that "fork and allocation failures are environment problems in either phase". Routing snapshot-OOM to UNKNOWN would put a seam one statement wide into the file — the snapshot's OOM exiting 2, and `classify`'s OOM on that very snapshot, the next statement, exiting 3. The ruling did not address that rule, so the deviation was written into the plan for the owner to see before approving, and approved there.

**And the deviation is the one line nothing can falsify.** Review deleted it and all four legs stayed green: a real allocation failure is not something a fixture produces, so no check reaches the guard. What review's suggestion did buy is narrower and worth having anyway — typing the message switch to `SnapshotError` and dropping its `else` means a member added to that error set now fails to compile instead of quietly emitting the bare call-site wording, which is the pre-#351 behaviour. Measured both ways: deleting the `TooDeep` arm no longer builds, and deleting the OOM guard still does. The second is the honest limit of the first.

**The same lie has eight more sites, none of them snapshots** — the recording run's and the worlds' stdout captures, the oracle's empty output, `corruptState`, and two `engine.restore` calls that reach `setupError` through the `restoreFailure` wrapper. The first scan of this class found six and missed the wrapper, because it grepped for `setupError(` and the wrapper does not spell it at the call site. Filed as #363 rather than fixed: the thesis here is the snapshot, and a thesis that claimed all of exit 3 would have been false on landing.

## 2026-08-27 — the two reopened rows are adjudicated, and the review's own record survives the ruling (#240)

Yesterday's part one entered three cohorts' evidence into the kill-criteria review, found rows 4 and 6 on a trigger side, and left the re-score pending. The owner ruled both today: **neither is triggered, criterion 3 stays met.** This entry is about how the rulings were arrived at and recorded, because two of the four questions put to the owner were the wrong questions and review is what showed that.

**The first framing was wrong, and the record said so all along.** Row 4 was put to the owner as "is this the same class as the known one, a second class, or triggered", and the middle option was chosen. Adversarial review then opened `spike/cohort2/borg-r3/RUNLOG.md` and found the sentence this project had already written there: *"The multi-write shape, #35's class, tinted further by our own apparatus."* The class exists, it is "tools with non-durable scratch files" in `docs/target-classes.md`, and `docs/checker-cookbook.md` already carries its recipe — **so "a new second class with no recipe" was wrong twice over, and the "same class" option had silently meant buku's journaled-store class rather than the one that actually fits.** The question went back to the owner with the record in front of it and was re-ruled: Borg is the **second example of #35's class**, adding one property the class did not have — a target-created scratch path can be relocated into the judged root by the measurement setup rather than sitting there from the start. (The first wording of that property said the apparatus *created* the path, which review corrected below: Borg creates the cache, r2 repointed `BORG_BASE_DIR`.) The re-review section written yesterday says "a second class" and is left saying it; the adjudication section corrects it in its own words rather than editing yesterday's.

**The second wrong question was one that had not been asked at all.** Row 6 was put to the owner as "does declared apparatus count as setup", and the answer was no. Review pointed out that the answer does not finish the row: excluding apparatus still leaves Mercurial's four define revisions and Borg's three, so a ruling that stops there has adjudicated a premise and called it a conclusion. That went back too, and the owner ruled it separately — **define-revision cost is excluded from row 6**, which is the cost of getting ordinary software into a measurable state. Two independent rejected readings now stand under row 6 instead of a premise and its consequence. (The ruling was recorded at first as "row 2's subject, the cost of declaring invariants"; the implementation review showed the record does not support that either, and the cost is now recorded as unallocated — see below.)

**Review also refused the reason the not-triggered reading was leaning on.** The draft's case for row 4 led with "nothing was claimed" — which, as the review put it, proves campaign discipline and not product-side protection. The recorded order is now inverted: the violating file is a client cache outside the durable repository state Borg's transactional claim covers (a property of the product), a checker carrying that claim ran in all 119 worlds and held (a check, not a judgement made afterwards), and only then the claim rule. Both halves of that sentence were narrower by the time the implementation review finished with them — see below. Each ruling also records what it gives up, in the shape #305's adjudication used.

**Where things are written moved, for a reason worth keeping.** The plan had `PRD.md` carrying the full ruling and `DESIGN.md` a pointer, copying #305. Review checked the premise instead of the pattern: criterion 1 is *defined* in `PRD.md`, which is why its ruling belongs there, while criterion 3's line in PRD points at DESIGN §18 for its conditions. So the binding definition — declared apparatus is instrument cost, narrowly bounded so that nothing touching the target's own installation, configuration or state can be relabelled into the exclusion — lives in §18, and PRD carries a status line and a pointer. Copying the shape of a precedent without checking why it had that shape would have put a definition three documents away from the condition it defines.

**Nothing dated was overwritten, and the check is what says so.** Four separate statements said "pending" on the review page and two more in this file and the changelog. The first plan replaced two of them, which review showed would leave the page asserting both "this section does not re-score anything" and a re-score. What landed instead: one sentence appended to the 2026-08-26 section's opening paragraph marking it superseded, the same device §17 uses, and everything else — the cells, the closing list, the two contradicted sentences — left verbatim as the record of that day. `PRD.md` gained a third dated status line beside the first two, which is what criterion 1 already does with its own 2026-08-14 and 2026-08-25 lines. The historical `pending` in this file and in `CHANGELOG.md` stays: a guard that required it gone could only be satisfied by rewriting history, which the first draft's check would have done.

**Re-read at PR-open, and the implementation review took five more claims off the draft — three of them about evidence this project had already committed.** The pattern is the one this file has been recording all week: a claim written from the shape of the record rather than from the record.

- **"The checker's leg R0 exercises Borg's documented deletion-and-rebuild in every world" was not measured.** The `rm -rf` in `spike/cohort2/borg-r3/ops/check.sh` is unchecked, and `spike/cohort2/borg-r3/checker-drills.txt` records it failing with `Permission denied` while execution continued. What the transcript proves is that the whole checker ran 119 times and its legs held — not that that leg's deletion succeeded. The support was rewritten to stand on the contract legs, which the transcript does measure, and the gap is now stated in the ruling and in what it gives up. **This was the strongest-sounding of the three supports and the only one with no measurement behind it.**
- **"Outside Borg's own contract" was wider than the record.** The RUNLOG claims that Borg's *transactional* contract held; the cache is not uncovered by every Borg contract — deletion is its documented handling. The corrected phrasing is that the file lies outside the durable repository state the transactional claim covers, in the review page, DESIGN, this file and the changelog together.
- **The class extension misstated who creates the path.** Borg creates `ambient/.cache/borg/<repo-id>/chunks`; what r2 changed is where `BORG_BASE_DIR` points, which brought the target's own cache inside the state root. "Created by the apparatus" would have taught the #35 class something false. It now reads as a target-created scratch path relocated into the judged set by the measurement setup, which is the property actually worth adding.
- **The narrow definition was not yet narrow.** Requiring only advance declaration and an environmental constraint still admits a target-specific shim that emulates a service the target needs, or a pre-provisioned database selected by an environment variable — substantial ordinary setup wearing apparatus clothes. §18 now adds two semantic bounds: the control must be measurement-only and behaviour-preserving, and provisioning anything the target depends on is setup however it is injected.
- **Sending the define-revision cost to row 2 was tidy and wrong.** `spike/cohort2/borg-r3/proposals.md` says the question bytes were unchanged; r2 changed state placement and a checker leg, r3 added a `sendfile` workaround. Those are measurement and define-packaging costs, so they are not evidence for row 2's invariant-authoring comparison any more than for row 6's setup weight. The owner's ruling — excluded from row 6 — stands as given; **the attribution this project added on top of it did not survive the record, and the cost is now recorded as unallocated.**
- One more, smaller: the adjudication section opened by claiming nothing above it was edited, which is false — a superseded note was appended. The invariant is that no dated text was *overwritten*, and it now says that.

**And the local checks caught two of their own defects before the review saw them.** The ordering predicate compared the *first* ruling against the *last* pending text, which is not the question; and "history is kept" was implemented as "some pending phrase survives", which a mutant scrubbing one occurrence passed until the predicate became byte-identity against `b195eb2`. Seven mutants now each die on their intended assertion. **The checks caught structure and preservation; every one of the five claim errors came from review.** That split is now four sittings old.
## 2026-08-27 — the naming root's gate stops measuring depth and starts measuring distance from danger (#329)

`engine.assertSafeRoot` was written to guard the directory `restore` empties and rebuilds. Its depth rule — fewer than two slashes and refuse — came along when `mcp.zig` reused the predicate to vet `SIDEEYE_MCP_ROOT`, and it refuses every single-component mount: `/work`, `/opt`, `/repo`, the ordinary shape of the container this project's own README recommends. #329 asked whether the naming root should be subject to it at all.

**The ruling was made twice.** The first, on 2026-08-26, was a conditional exemption: drop the depth rule only when `SIDEEYE_MCP_STATE_ROOT` is set, on the reasoning that the root doubles as the destruction range when it is unset. Adversarial review of the plan then measured three things that moved the decision, and the owner changed it on 2026-08-27 to an unconditional exemption plus an ancestor check.

*What the review measured.* First, the condition is nearly always true in practice: `README.md`, `docs/ci-quickstart.md` and this repository's own sweep apparatus all set `SIDEEYE_MCP_STATE_ROOT`, and nothing requires it to differ from the root, so `SIDEEYE_MCP_STATE_ROOT=$SIDEEYE_MCP_ROOT` buys the exemption while leaving the root as the destruction range — the exact configuration the condition existed to gate. Second, a conditional couples two knobs ADR 0022 exists to separate; that ADR's rejected alternative is recorded as "the wall teaches operators to widen the wrong variable", and "set the destruction range and the naming vet relaxes" is the same shape. Third, and decisively, **the depth rule is an approximation that is already broken**: `SIDEEYE_MCP_ROOT=/var` starts today, rc=0, because realpath turns it into `/private/var` and two components pass. What is dangerous was never the component count.

**So the gate now measures what it meant to measure.** `assertSafeNamingRoot` keeps every non-depth check and adds one the destructive predicate never had: the denylists are consulted in *both* directions, so a root that is an ancestor of a denied entry is refused as well as a root inside one. `assertSafeRoot` and its four destructive call sites are byte-identical — an enum parameter was rejected because a per-site argument is a shape that gets misread, and here misreading it means a destructive path losing the depth rule.

**This is not a narrowing, and the first draft of this entry said it was.** The reviewer enumerated both denylists mechanically and computed the ancestor check's covered set: it closes exactly `/var`, `/private` and `/private/var`, and it opens every depth-1 path in neither list — `/opt`, `/cores`, `/nix`, `/srv`, whatever a given host has at `/`. A depth heuristic is being traded for an ancestor rule and the boundary moves both ways. For the same reason the original ruling's "additive relaxation; nothing that used to start changes behaviour" is false: `/var` starts today and refuses after this change.

**"The consumer that cannot delete anything" was this entry's own sentence, and review measured it false.** With `SIDEEYE_MCP_STATE_ROOT` unset the server passes the root itself as the destruction range, so relaxing the naming vet relaxes the default destruction range by one level. The reviewer demonstrated it through the real functions: `/opt` passes the new vet, `/opt/homebrew` is strictly inside it, and it passes `assertSafeRoot` — so a replayed case naming that state empties it once per world. **The README rewrite in this same batch had made it worse**, offering `/opt` as an example of a fine single-component mount on a page whose next sentence says the root is the destruction range. `/work` and `/repo` are container mounts; `/opt` is where installed software lives. Corrected in the README, the ADR amendment, the changelog and the two doc comments that said it. **This is the inversion ADR 0024 exists to correct, written by the same batch that cites ADR 0024 for it.**

**What this closes on the naming vet it leaves open on the destructive one.** `assertSafeRoot` is untouched, so `sideeye --state /var` still passes the destructive vet. (This sentence said "and empties `/private/var` once per explored world". #358's own implementation measured that wrong: `restore` puts the initial snapshot **back**, so an explore leaves the root's contents where they were — measured on one regular file's bytes surviving one explore, which is what the harm story turns on; `restore` rebuilds with fixed modes and does not preserve ownership, timestamps or inode identity — `freshDir`, reached only through replay's `--fresh-state`, is what empties. Corrected there.) Keeping that out of one PR is a scope decision, filed as #358.

**A new guard shipped implemented twice, each copy inert.** The outward read was written as two loops, one per list. Review mutated each half alone: both survived. The proper ancestors of `denied_exact` and of `denied_trees` are the *same three paths* — every entry in one list has a sibling in the other under the same parent — so each loop's marginal covered set is empty and only deleting both is caught. Collapsed to one loop over the concatenation, which cannot be half-deleted. The measurement that missed it was this side's: the mutation was run on the pair, and the pair is not the predicate.

**Two more the review found and this PR does not do.** The lists and the shared checks arguably belong in `contract.zig`, where `isInsideDir` already lives and where the naming/destruction split would stop being decided by proximity — filed as #359, and the plan's first rejection reason for it ("it would touch the destructive call sites") was false, which the review demonstrated by pointing out that `assertSafeRoot` keeps its name and signature. And four ADRs still say `Status: Proposed` after their implementing PRs merged (#360); flipping only 0022 while amending it here would have made the other three read as deliberate.

## 2026-08-26 — three cohorts reach the kill-criteria review, and two rows land on a trigger side (#240)

`docs/kill-criteria-review.md` is the evidence for v1.0 entry criterion 3 and was written on 2026-08-16. Twelve targets have been measured since, across three selection cohorts, and none of them appears anywhere on the page — twenty-two search terms, the cohort names, the issue numbers and every target name among them, return nothing. This entry is opened before anything is written to the page.

**What #240 asked for, and what this does instead.** The issue proposed re-running the review row by row with the old verdict quoted beside the new one. The first plan did exactly that and was rejected in review for a reason worth keeping: *"re-score all eight rows but move no verdict"* is not falsifiable. No observation distinguishes it from having re-scored nothing, and the page itself says the review reopens on trigger-side measurements — so a re-score that cannot reopen anything is a re-score in name only. The scope is now narrower and says what it is: the eight row bodies are not edited at all, a dated table is appended, and the re-score is **raised as pending** rather than performed. The page gains material; it does not gain a verdict.

**The page's own closing rule is what makes "just add the evidence" impossible.** Its last paragraph reads *"None of the rows closes permanently. A future measurement landing on a row's trigger side … reopens this page, and per the PRD's own rule the analysis ships instead of the release,"* and the same rule is written into `PRD.md`'s criterion-3 status and `DESIGN.md` §18. Two of the cohort measurements land on a trigger side. So recording them fires the reopen in three documents at once, and there is no way to write the evidence down that leaves the release gate untouched. That consequence belongs to the owner, which is the reason the re-score is pending here rather than decided.

**Four things this project had wrong before the review opened the sources.** All four are the plan's own numbers, all four corrected against the files:

- **The population.** The draft said ten targets, four walls, six verdicts. `DESIGN.md` says twelve targets and thirteen outcomes: five walls still standing (KeePassXC, Jujutsu, Bun, cargo, unison), one wall lifted by declared apparatus (Borg, #200), and seven verdicts. Borg is counted twice because it produced both — which is why `spike/cohort2/RESULTS.md` writes "five targets, six recorded outcomes" rather than a single number.
- **"None of them produced a false positive."** Written into the draft as a strengthening of row 4, and contradicted by the record it cites: `spike/cohort2/borg-r3/RUNLOG.md` says the three violating worlds are "all three in the relocated client cache's in-place rewrite." The apparatus is part of the measurement environment and row 4 is the environment-artifact row. The draft had read that record and taken the verdict out of it without the location.
- **A ratio that pooled two cohorts.** "Two of ten" for the apparatus-dependent verdicts mixed cohort 2 with cohort 3; cohort 2 has five targets.
- **"The cohorts are the first genuinely independent data."** This came from the issue and the draft repeated it. It is false in the direction that matters: `spike/cohort3/PROTOCOL.md` says "The probe gate of cohort 2 applies … with one substitution," and `spike/cohort4/PROTOCOL.md` sources `spike/cohort2/probes/lib.sh` — "no fork, no copy." The cohorts share engine, observer, probe-gate predicates and the same owner and scout, so they are **not three independent apparatuses** — a systematic error in the shared gate or the engine would appear in all three alike. The page's "one instrument read eight ways" note therefore gains support on that axis rather than weakening, which is the opposite of what the issue predicted. **The first draft of this correction over-corrected**, writing that the cohorts "widen coverage, not independence" — review pointed out that the quotations establish shared instrumentation and nothing about the evidence, and twelve distinct targets with their own checkers and verdicts are new information whatever instrument read them. Narrowed in the page, DESIGN, this entry and the changelog together.

**What the corpus ledgers settle about row 8, which the draft had also missed.** The eight defines that entered the A-group at g2 are not an arbitrary addition — they are the cohort verdict targets themselves (hg, borg, black, papis, poetry twice, rustfmt, himalaya). So g2's 2/36 is not "another sweep": it is the rate after the cohort verdicts entered the denominator. The walls did not enter. jj, Bun and cargo sit in `class-exclusions.tsv` because their target class has no recorded verdict at all, and KeePassXC and unison appear in neither ledger because they never produced a committed define. Row 8's condition is about "runs on supported targets" — a wall is not a run — so the direction the issue expected, more targets meaning a higher rate, does not follow. The draft asserted that it did.

**What the local checks caught in the prose, before any reviewer saw it.** Three of these are the same failure shape — a claim written from a scan whose form did not match what it claimed to count.

- **A line-oriented grep counted four reproduction phrases in cohort 3 where a normalised count finds five.** The fifth is worded "reproduced identically across three runs" and spans a hard line break, so `grep -n` cannot see it. The breakdown was wrong — the draft credited the three-run figure to poetry's second define instead of its primary — **and so was the conclusion, which the local checks did not catch and review did.** The scan covered the cohort RESULTS pages and not the per-target rulings, and `spike/cohort2/hg-r4/RUNLOG.md` says in as many words that "a second run reproduced the identical verdict and counts". Re-scanned across every ruling: **all seven** verdicts record an identical re-execution and there is no Mercurial gap. This is the third instance in one sitting of the same shape — a claim written from a scan whose scope or form did not match what the claim covered — and the only one of the three that a reviewer had to find.
- **papis was offered as counter-evidence for row 6 while its own record cuts the other way.** Its define is a single revision, which is the light side of that row — but its *plan* was amended before its accepted probe, because the original `--set` form made a purely local `papis add` reach out to arxiv.org over HTTPS. Counting define revisions puts papis on the light side; counting arrival cost as the record describes it does not. Using it one-sidedly was arguing the row with the half of the record that suits it, so the section says which unit each reading needs and leaves papis on neither side. **This correction was then silently reverted and had to be made twice.** Proving a check red requires mutating the tree, and one restore copied a backup taken before this fix, so the page went back to the one-sided wording while this entry still claimed it was fixed — a reviewer found the contradiction between the two files. The lesson is not "be careful with backups": a mutation-and-restore loop over the artifact under review will silently undo work unless the restore is verified against the state it is meant to return to, and the local checks asserted nothing about this sentence, so nothing failed.
- **"The uniform three-file shape" is not a fact about cohort defines.** Measured, they carry four files and himalaya five; "three small files" is row 6's phrase about the #84 sweep. The measurable contrast row 1 actually wants is the operation count: every cohort verdict define carries exactly one `.toml`, against the thirteen in the corpus's own topydo define. That is now counted by the check rather than described, and the check was falsified two ways — the section-side predicate by putting the three-file phrase back, the counting predicate by a synthetic define with a second operation file.

**And what the checks caught about themselves.** Four construction defects, each found by running them rather than by reading them:

- The verdict-quotation check failed on six of eight rows on its first run — not because the quotes were wrong, but because the body writes `**Verdict: not triggered**` and the quoted cell carries no asterisks. A check that fails for its own formatting reasons teaches nothing; it now strips emphasis from both sides.
- "The eight row bodies are unedited" was implemented as a removed-line budget over the whole file. Mutant D — a figure swapped inside the *appended* section — killed it, which proved it fires on edits it does not describe. It now compares the rows region against `git show HEAD:` byte for byte.
- The figure check verified that each figure exists in a named source, which a swap between two sourced figures passes. Mutant D survived it for exactly that reason, so the two rate/fraction pairs are now bound as pairs. **What is still not covered is stated rather than implied**: nothing mechanically checks that a figure was used for the right quantity in the right sentence.
- The host-side reproduction of acceptance check 11 was itself wrong on its first run: written as `for r in $refs`, it iterated **once** over the whole blob, because this shell does not word-split an unquoted variable expansion. It reported "missing count: 1" — the right answer for the wrong reason, since the blob it tested contained the bad reference. Re-run line by line, the real finding stood: the upstream commit reference `pimalaya/io-maildir@b4e9080` was written in backticks, and check 11 treats every backticked token containing a slash as a repository path, so **CI would have gone red**. Every other upstream reference on the page survives only because it carries a `#`, which the extraction drops.
**Re-read at PR-open, per this file's own rule, and three more things had moved.** Review round one raised five findings above the two already recorded here, and two of them changed the shape of the change rather than a sentence in it.

- **The section was in the wrong place, and the mistake was structural rather than editorial.** It was first inserted before `## Calibration`, which put it *inside* the 2026-08-16 review: a reader met "reopened, re-score pending" and then walked into the unchanged closing verdict, "All eight rows reviewed against the collected data: **none triggered**", as the page's last word. Appending after the historical conclusion instead costs nothing and removes the contradiction — the old verdict finishes as a verdict, and the new state opens the section that follows it. The first line of that section is now the current state of the gate, so the answer is above the evidence rather than after it. **What this project got wrong was assuming placement was presentation.** The page has a closing rule and a closing verdict; anything inserted before them inherits their conclusion.
- **poetry was said to have needed a second define, and it did not.** Its first define produced a FAIL reproduced across three explores with identical verdicts, and `spike/cohort3/poetry-r2/RUNLOG.md` says on its face that "poetry reached its FAIL verdict before this revision existed" — the revision is a sealed manifest-only shape under the FAIL-freeze ruling. Written into row 2 as authoring cost, it read as a target that took two attempts to measure. This is the same error as the Mercurial one, in the other direction: a revision counted as a cost without opening the ruling that says what the revision was for.
- **The release gate could be misread by anyone scanning headings.** `PRD.md` carries one standard `Criterion 3 status` line and it says `met`; the reopen was appended as an adjacent paragraph. A reader skimming for the status heading would take `met` and stop. The current state is now labelled as its own dated status line, with the older one explicitly named as the 2026-08-16 record. Preserving a dated statement and making it findable are different problems, and only the first had been solved.

Two follow-ups are filed rather than built here: the three documents that carry the reopen rule can drift apart with nothing to notice (#356), and a quoted figure is checked for existing in a source but not for being the right figure for its sentence (#357, where a mutant swapping one sourced figure for another survived until the rate pairs were bound together).

**The detection split, since this entry is where such things get counted.** The local checks — 104 assertions, eight mutants each killed by their intended predicate — caught the figures, the structure, the verdict transcription and a backticked path that would have turned CI red. They caught none of the five claims that were wider than their sources. Review caught all five, and found the reverted correction only because the page and this file disagreed about it. That is the same split this repository has been measuring all month, reproduced on a change with no code in it.

## 2026-08-26 — the per-file cap learns what time it is (#330)

The 64 MiB per-file snapshot cap (#265) refuses at five call sites, and four of them are at or past the recording run. All five said `SETUP_ERROR` — exit 3, "the define did not run" — which at the four late sites is a lie the target can trigger legitimately by writing a big file during the operation (#322's review filed it as #330). The ruling (recorded on issue #330): add `state_file_too_large` to the `unknown_reason` closed set, send the four post-recording sites to UNKNOWN, keep the initial snapshot as SETUP_ERROR — there the define really has not run. The closed set is excluded from the additive rule (#320), so the tag makes this now-or-never; `child_wait_failed` (#264) and `trace_too_large` (#324) already draw the same line.

**The first design lost to review before it ran.** The draft passed the phase as a parameter to `snapshotOrRefuse`, mirroring #264's `spawnFailure`. The reviewer counted what verifies it: the new acceptance leg reaches the final-snapshot site only, so three of the five call sites could pass the wrong phase and every check would stay green. Replaced with a file-scope `SpawnPhase` variable assigned once, immediately before the recording run — a per-site mistake is now unrepresentable, and what is left to get wrong is where that one assignment sits.

**Three mutations, and the third corrected the claim the first two were taken to support.** Deleting `run_phase = .exploring;` returns the late path to exit 3 with 2fc still green; moving it above the initial snapshot turns 2fc red with the late path still green. Both were measured on macOS against the shipped binary, *without* an oracle — the acceptance legs themselves run only in the Linux container, with `--oracle /usr/bin/strace`, so those two runs exercised the production refusal path but not the shipped legs. The draft of this paragraph wrote that pair up as pinning the assignment's **position**. Review measured a third mutant — the assignment moved *down* to just above the final snapshot — and **both paths keep the verdicts the legs assert**, because nothing between the two points reads the variable. The legs bound an interval, not a point, and the entry now says so. The same review ran the new leg verbatim in `debian:bookworm` against an aarch64 cross-build (`rc=2`, `"unknown_reason": "state_file_too_large"`), which is the only execution of the shipped leg that has happened anywhere so far; CI is what will run it on every push.

**Two claims in the ruling comment were false, and both came from the same habit.** It said #324 merged "three days ago"; `0e035eb` merged the same day — authored 11:31:55, committed 11:35:08, and a paragraph about numbers transcribed without opening the source should name which clock it means, so: commit date, 11:35:08 +0900. It also named "the ci.yml value assert" as part of the implementation; `ci.yml:168` pins `no_shim_marker` for the platform-binary refusal and neither enumerates the closed set nor moves with a new member, so `ci.yml` is untouched here. Both were transcribed from review prose without opening the source — the failure mode the rule about numbers exists for — and both are corrected on the issue.

**The sibling was ruled in the same sitting.** The same phase lie exists for every post-recording snapshot failure that is *not* the cap: `SnapshotError` also carries `TooDeep`, `ReadFailed`, `PathTooLong`, `ClassifyFailed`, `EntriesNotSortedUnique` and `OutOfMemory`, and depth > 32 is reachable by a target creating directories during its own operation. A dedicated token is equally now-or-never. Ruled: `state_unsnapshotable` joins the closed set in its own PR, after #329 — one closed-set member per PR so each addition's mutation attribution stays clean. Filed as #351; this PR does nothing else about it.

## 2026-08-26 — the sweep that the rulebook was frozen for (#239, part two)

Part one froze the corpus and built the apparatus without measuring anything. This is the measurement. **The entry is committed on its own, before the sweep runs, and that ordering is not stylistic**: `sweep.sh` refuses a dirty worktree, because the define digests it records would then match no commit. The repository's own rule says to write the buildlog entry when work starts. Both are right and only one order satisfies them — write, commit, then measure. **The plan's first draft had it the other way and would have been rejected by the tool on its first command**, which is the kind of defect that only appears when two rules written at different times are put in the same procedure.

**What the plan learned before any of it ran.** Two adversarial rounds moved it fourteen times; four are worth recording because they were about the shape of the evidence rather than the shape of the code.

*"Thirty-six rows" is not "thirty-six measured".* The sweep writes a manifest row whenever a report file exists, whatever the launcher's exit code, and `count.py` publishes a `SETUP_ERROR` as an excluded row rather than refusing it. So a sweep with one apparatus failure produces thirty-six rows, a green `check`, and a rate computed from thirty-five. The gate before marking a generation complete therefore counts **the rated denominator**, not the manifest — and if a `SETUP_ERROR` appears, the apparatus fix lands separately and the measurement is re-run, per this page's own rule.

*The mutant that was supposed to catch a swapped report does not.* The first review said the draft's check (g1's block byte-identical) would pass an implementation that read g1's artifacts for g2. The replacement check — swap a g2 report for a g1 one — was reviewed in turn and **measured passing**: a virtual mutant with all twenty-eight shared reports copied byte-for-byte from g1 still produced `check: OK — 85 measured`. Reports carry no generation, no HEAD, no run identity; `load_reports` reads a verdict and a reason and nothing that says where the file came from. **The eight new trials are detectable** (their ids do not exist in g1's directory at all) and **the twenty-eight shared ones are not**. What was wrong in this project's own reasoning is narrower and worth naming: the reply to the review assumed the swap would target the *new* rows, because those are what changed. The shared rows are the ones that can be swapped precisely because they did not change.

*The difference between g1 and g2 has more than two causes.* The draft called it corpus plus engine. The page's own Method section says the base images are pinned by build rather than by manifest and that environmental identity with past runs is recorded, never claimed — so a re-build sits in the difference too, along with run-to-run variation. Two of the four can be separated with the data the sweep already produces (the shared twenty-eight across generations, and the shared twenty-eight against all thirty-six within g2), and that separation is a one-shot calculation recorded here rather than a third number added to the published block.

*A guard that has only ever been red in a fixture.* Part one's partial-execution check has never fired on real data. It fires only for a generation marked complete, and a sweep that dies leaves the generation `unstarted` — so the failure path reaches a different message than the plan first claimed. Both are measured here on a scratch copy, whether or not the sweep completes, because the completing case is the ordinary one and would otherwise leave both unverified forever.

**The first sweep was interrupted, and the interruption did that verification for real.** Contract v12 merged a few minutes into the run. Its Linux side is unchanged — `git diff 892276d..main -- shim/src/linux.zig src/oracle.zig` is empty, checked here rather than taken on report — so the numbers would have been identical either way. What is not identical is the record: `apparatus.txt` writes `head:` with the commit the sweep ran on, and rebasing afterwards leaves that sha pointing at a commit no longer in the history. **The run was stopped and restarted on the new base for provenance, not for arithmetic.** The sixteen trials it left behind became the real material for the check above, which had been planned as a synthetic one:

- g2 still `unstarted`: `generation g2 is marked unstarted but artifacts-a2/manifest.tsv exists`
- g2 flipped to `complete` on a symlink farm, production tree untouched: `manifest covers 16 trials against its expected 36 — a partially measured generation is not publishable`

Part one's guard had only ever been red in fixtures. It is red on real data now.

*The first attempt at that check was a hollow red.* The scratch tree was built by copying files instead of linking, so it lacked defines the corpus names, and `count.py` died on `define path missing from checkout: spike/dogfood-todoman.sh` — before reaching the predicate under test. Red, and about nothing. Precisely the shape check 12's message matching exists for, met while relying on it.

**The sweep: 36 trials, 4 minutes 21 seconds** (17:03:14 to 17:07:35, base `6533681`, engine 0.13.0 on trace contract v12). Recorded because part one could not find the previous sweep's duration anywhere — not in the buildlog, not in a runlog — and the artifacts' mtimes are checkout times, so reading them naively says "36 reports in one second".

**Gate before marking the generation complete**: 36 manifest rows, **zero SETUP_ERROR**, **rated denominator 36**, every verdict inside the closed set — FAIL 23, PASS 11, UNKNOWN 2. The row count alone would have passed with a `SETUP_ERROR` among them and a rate computed from thirty-five, which is why the denominator is what the gate counts.

**What in this entry is re-derivable from the tree, and what is not.** The verdict counts, the rated denominator and the shared-subset comparison recompute from `artifacts-a2/` and `artifacts/` alone. The ledger arithmetic (eighteen defines as eight, six and four) needs more than the artifacts — it needs `corpus.tsv`, `supersession.tsv`, `class-exclusions.tsv` and the cohort directories on disk — so it is re-derivable from the **committed tree**, which is a wider claim than "from the artifacts" and was written as the narrower one until review separated them. **The rest is operator-observed and leaves no artifact**: the elapsed 4m21s (a wall clock read outside the tool, which records no timing), the sixteen-trial interrupted run and the two predicates measured on it (that tree was deleted before the real sweep, because `sweep.sh` refuses an existing artifacts directory), the scratch symlink farm, and the report-swap mutant, which was constructed in memory during review and never written. Those are claims about operations, not about committed evidence, and they are marked as such rather than left to read like the recomputable ones.

**One review finding is deferred rather than fixed, and that is a waiver, not a repair.** The raw oracle logs this sweep commits carry absolute paths from the machine that ran it, operator username included — four files, 264 occurrences, the same shape and the same count as g1's committed logs. Normalising them means either rewriting evidence or changing what `sweep.sh` writes, and a measurement PR is the wrong place for either. **This PR adds new instances knowingly** and files the decision; it does not claim to have addressed it.

**The difference between g1 and g2, separated once rather than left to a reading:**

```
=== A-group, shared trials (the 28 both generations measured) ===
  g1: 1/28
  g2: 1/28
  trials whose verdict or reason changed: 0

=== A-group, within g2 (same engine, same images, same run) ===
  shared 28: 1/28
  all 36:    2/36

=== published ===
  g1 (28 trials, 2026-08-16): 1/28
  g2 (36 trials, 2026-08-26): 2/36
```

The plan called the difference multi-causal and warned against reducing it to two effects. **The first draft of this entry then reduced it to one**, writing that the other causes contributed nothing because the shared twenty-eight did not move. Review caught it, and the correction matters because the counter-example was three paragraphs away in the same entry. What the arithmetic supports is narrower: the same twenty-eight trials produced identical verdicts and identical reasons across an engine change and a rebuild, so **the movement is located in the eight that entered at g2** — and locating it there is not attributing it to their novelty. No run exists in which those eight faced g1's engine, so their being new and the engine having changed cannot be separated from each other the way the shared twenty-eight separate from both.

**And the added UNKNOWN is, in fact, an engine effect.** #239 argued the rate would rise because several added defines reach named refusals, naming jj, Bun and cargo; all three sit outside the corpus by class and never entered the denominator. The one that did was himalaya — the single define carrying `apparatus_superseded`, whose `no-accel-copy.so` answers the copy primitives **the shim now interposes itself**, the two colliding into `oracle_saw_phantom`. It refused because the engine changed, on a define that happened to be new. Writing "the movement is the corpus addition" while also writing "the shim now interposes what the apparatus was answering" is a contradiction inside one entry, and it survived until someone read both sentences together.

**A second pass at that sentence was still wrong, in a subtler way**: it called himalaya "the one trial that moved the rate", which confuses the numerator with the rate. Eight trials entered; one added an UNKNOWN and **seven added only to the denominator**. The shared twenty-eight plus himalaya alone read **2/29 (6.9%)**; the other seven bring it down to **2/36 (5.6%)**. So the added set pushed in both directions and the published rise is *smaller* than the new refusal alone would have produced. Two rounds of review to get from "the corpus did it" to "one of the eight refused for an engine reason and the other seven diluted it" — each correction sounded like a rewording and was a different claim.

## 2026-08-26 — the clone nobody saw, and the issue that named the wrong function (#333, #336)

The issue was written by this project, at the end of the previous batch, from a scratchpad note — and its premise was never measured. It says macOS copies go through `fcopyfile`, which the shim does not interpose. Measured: `fcopyfile` and `copyfile` were **already visible** — libcopyfile binds plain `_open`/`_write`, which cross the interpose boundary — and what was invisible was selected by a *flag*: `COPYFILE_CLONE` routes to `clonefileat`, and the clone family (`clonefile`, `clonefileat`, `fclonefileat`) was interposed nowhere. A clone into the state directory recorded zero operations while a real file appeared with real content, and with one `unlink` beside it the run **PASSed** — `state_changed_without_ops` fires only at zero recorded mutations, a guard whose covered set is "targets that do nothing". Rust std's `fs::copy` reaches `fclonefileat` first, so the silent route was the common one. Same shape as `copy_file_range` one batch earlier: the abstraction "this function is visible" broke on an argument, and the real judgment lives one level down.

**The review widened the object from a function to a family, and measurement confirmed the family.** `dyld_info -exports` against the interpose table: `renamex_np`/`renameatx_np` — which the table's own comment NAMES as `renameat2`'s macOS spelling, named and not taken — `exchangedata`, the `setattrlist` family (`ATTR_CMN_NAME` renames), `mkfifo`/`mknod` (measured: caught downstream by the snapshot's `.other` demotion), `msync`/`aio_write` (the store is invisible to any wrapper; filed), `open_dprotected_np` (libcopyfile imports it). Contract v12 counts the clones and the rename extensions, refuses the swaps — and the refusal had to move observers: on Linux the oracle refuses `RENAME_EXCHANGE`, scope-gated; macOS has no oracle, so the shim writes a new `.unsupported` marker the engine answers with the same reason and the same spelling shape. **Moving the refusal moved the check and silently dropped the order around it** — the first design did not scope-gate, which would have refused runs for swaps outside the state directory, an over-refusal Linux does not have. The oracle checks `scope == .outside` *before* its flag branch; that order is part of the specification and it does not travel with the function.

**The failed-clone question got a theorem instead of a workaround.** `clonefile` fails when its destination exists; `copyfile(COPYFILE_CLONE)` and Rust both fall back to plain writes, so every overwrite-shaped copy records one attempt that changed nothing. Records are attempts by contract (the kill must land before the effect), and a failed attempt's crash point is a **state-twin of its successor** — identical state, identical judgment, so v12's worlds map one-to-one onto v11's and only indices shift. Measured: failed-clone-then-fallback PASSes with 7 crash points where v11 had 6. Two earlier phrasings of this argument were wrong (the twin named as the predecessor; "cannot be the earliest") and were corrected by the review's confirmation round — the wrong versions read plausibly, which is exactly why they are recorded. The named cost: an attempt record disarms the zero-ops guard, so "failed clone + msync-class write and nothing else" was refused under v11 and can false-PASS under v12 — the one change moving in the false-PASS direction on the witness-less platform, written down beside the msync filing rather than left to be discovered.

**The ratchet, and what its falsification found.** `spike/check-macos-coverage.py` compares the runner's own `libsystem_kernel` exports against the interpose table and a reason table — the macOS twin of the Linux check whose own doc declared this exact blind spot ("this check cannot see it") one batch before the blind spot became this issue. Declaring is not covering. Falsifying the new check found its own limit: deleting a row from its watched set stays green, because the set is its own universe — recorded in the check's doc, partially anchored by a darwin_libc.zig cross-check (retiring an interposition without a reason is red; deleting a name from every list at once is review's job, and no in-file check can own it). The six misnamed documents fixed alongside (`case_no_longer_applies`, not `contract_version_mismatch`, for saved-case version refusals) included one the confirmation round's own sweep missed — found by re-running the sweep here rather than transcribing its count. (This journal's own earlier entries keep the misnaming they were written with — the journal records what was believed at the time, and correcting it would forge the record; the six fixes are all in living documents.)

**#336, folded in by owner decision over the review's split recommendation, and done as a reversal.** Three days ago #326 argued the provenance advisory belongs in `tools/list` only, on three grounds, recorded in two comments. Two grounds (FAILs carry no target bytes; a standing advisory is noise) are answered by gating the advisory on the region's presence. The third — `tools/list` is read once per session — is not answered; it was the problem: a caveat read once loses to fresh tool output arriving later, and salience at consumption is what a warning is for. Both comments now carry the reversal's accounting, per this file's own contract that the reversals are the point.

**fsevents.** The #293 sensitivity apparatus deliberately planted `clonefile` as a mutation the shim provably misses; v12 records it, so the apparatus's own precondition now refuses ("pick another mutation" — its message was self-describing from the day it was written). The 15/15 result stands as a v11 measurement, annotated in three files; the re-point to an msync-class mutation is filed with #293. Cohort 4's `no-accel-copy.so`, one contract version ago: an apparatus built on a wall outlives the wall, and this is the second time in two batches.


## 2026-08-26 — the corpus rules, frozen before the numbers that will move them (#239, part one)

`docs/unknown-rate.md` defines the A-group as "every committed, runnable define in the repository" and publishes a rate measured on 2026-08-16. Eighteen further defines have landed since, under `spike/cohort2/`, `spike/cohort3/` and `spike/cohort4/`. The page and `PRD.md` both carry an as-of note saying so and defer to this work. **This entry is written at the start of it, and it records what the plan got wrong before any of it was implemented.**

**Two merges, not one — and the page said so where the plan did not look.** The rulebook's own opening states that it lands in two merges, apparatus first and results after, "so the first-parent history proves the corpus predates the numbers". The first draft of this work put the rules and the sweep in one PR, with the rules written first inside the branch. That is not evidence: a corpus adjusted after seeing its effect on the rate is indistinguishable from one frozen before, once the branch is squashed to a diff. The paragraph had been read during planning and not applied to the plan's own shape. **This PR therefore publishes no rate at all**, not even a counterfactual one — the constraint is what makes the merge order mean anything.

**The ledger had to split three ways, not two.** The plan's first shape was "corpus plus a supersession list, summing to eighteen". Measured, the eighteen split into three kinds: eight defines to measure, six superseded by a later revision of the same target, and **four whose class is not supported at all** — jj, Bun and cargo's two revisions sit in `docs/target-classes.md`'s refusal tables, and that page states outright that only the first table's rows are supported classes. A two-ledger scheme forces those four into the supersession list, which would have recorded "replaced by a later revision" about targets nothing replaced. `class-exclusions.tsv` exists because the alternative was a lie in a file whose whole purpose is to be checked.

**What the supersession rule costs, recorded here rather than in the rule.** Collapsing revisions to their last is a choice against the alternative of counting all eighteen, and `spike/cohort3/PROTOCOL.md` says plainly that "a define revision is a new target directory" — so the alternative is the one with textual support. It was rejected because hg would occupy four corpus rows and Borg three, letting one target contribute to the rate four times over, with the intermediate rows recording where an apparatus fell short rather than where the engine did. **That choice moves the published rate downward**, and saying so belongs in a development journal, not in the rulebook: a rule file that argues about which direction it moves the number is evidence that the number was in view when the rule was written. The rule states the criterion; this entry states what it costs.

**An earlier draft's justification was an accident.** It argued that collapsing to the last revision was already the repository's practice because the count matched the number of directories carrying a `RUNLOG.md`. It does not: himalaya's RUNLOG sits in the r1 directory, whose verdict was UNKNOWN, while the FAIL it is known for lives in r2 under `RESULTS.md`. Eleven equalled eleven by coincidence, and a coincidence had been doing the work of an argument.

**Some of the defines cannot run on the current engine, and that is a result rather than an obstacle.** `PRD.md`'s instrument note of the same day records that himalaya's `no-accel-copy.so` is superseded — v11 interposes `copy_file_range` and `sendfile` directly (#244), so the apparatus now collides with the engine it was built to route around. The hg and Borg sendfile workarounds are the same family. These defines are neither rebuilt (that is a cohort re-run, not a re-sweep) nor dropped (dropping deletes the finding that the engine's own inputs include some it can no longer measure). They carry a flag, and the flag has to reach the arithmetic, not just the table — a mark that only decorates a row can be skipped by the aggregation underneath it.

**Adding corpus rows without measuring them turns the gate red, which is the third thing the plan had not noticed.** `count.py check` requires the manifest to match the corpus row for row, so a rulebook PR that adds eight unmeasured rows fails its own check. The fix is to make generations first-class: each sweep is a generation with its own artifacts directory, corpus rows carry the generation they enter from, and a generation is `complete` or `unstarted`. There is deliberately no third value for the state between them — it closes the door on measuring some rows and publishing anyway, which nothing in the current shape forbids because the current shape cannot express it. Writing it down as a status was the first design and it is worse: a half-finished sweep with a name is a half-finished sweep that can be published from.

**Four things went wrong during the implementation itself, and all four were found by running something rather than reading it.**

*The plan's `FETCH.md` was a re-invention.* Each cohort's Dockerfile says, in its own header, that its inputs are "fetched on the HOST by ./fetch-artifacts.sh into ./artifacts/ (gitignored)" — and all three scripts exist, with the sha256 pins already in them and re-verified in the Dockerfile. The plan had decided to write the fetch procedure down without opening the directory it was writing about. Nothing was written; `sweep.sh`'s failure message points at the existing script. One real defect surfaced there: **`spike/cohort4/fetch-artifacts.sh` was not executable** while its Dockerfile documents invoking it as `./fetch-artifacts.sh`, so the documented invocation did not work. Fixed here.

*A new fixture was red for the wrong reason.* `gen-unstarted-with-manifest` exists to catch a generation recorded as unstarted that has in fact been measured. It died on `report missing ... in artifacts-a2` — true, and about the wrong thing, because `count.py` read the generation's reports before checking its status. Reports are now read only for a generation claiming to be complete. This is the exact failure mode check 12's `bad:want` matching was built for, and its comment already records the suite reaching a state where all five fixtures were red for unrelated reasons; an rc-only loop would have counted six greens.

*Measuring the download sizes returned four zeros.* The `awk` filter used `BEGIN{IGNORECASE=1}`, which is gawk-only — macOS's awk ignores it, the lowercase pattern never matched `Content-Length:`, and an unset variable became 0 through `v+0`. The artifacts are ~950 MB in total (rust's toolchain twice, himalaya's vendored tree once), not zero. A zero that means "the check did not run" is the shape this repository keeps re-encountering, and it appeared here in a throwaway one-liner rather than in shipped code, which is where it is cheapest and least visible.

*Adding two columns broke a reader that had been correct for a month.* `sweep.sh` reads corpus rows with a ten-variable `while read`, so a twelve-column corpus would have folded `since` and `flags` into `defines` — silently, since `read` assigns the remainder to the last name. Caught before it ran, but only because the loop was being edited anyway for the generation filter. The executable-bit defect above is the same class read through the repository's own rule: CLAUDE.md already requires declaration scripts the engine execs to be committed 755 and spawned through their own exec bit, with campaign 2's abook recorded as the case that went green under `sh` and died with Permission denied on the sealed run. `fetch-artifacts.sh` is not a script the *engine* execs, so it fell outside how that rule is worded while being inside what it is about.

**Verification.** Check 12's fixture loop grows from five to eleven, each new one matched on its own message rather than its exit code. Two things had to be built before the flag check could mean anything. **The check was inspecting an empty set**: `apparatus_superseded` and `apparatus_declared` appear only on rows entering at g2, which has not run, so the loop over completed generations walked past zero flagged trials and reported green. `fixtures/good` now carries a flagged row, which is what makes the predicate reachable at all. Then the mutation: a `tabulate` that renders a flagged trial and skips it when counting is red with `carries flags 'apparatus_declared' and appears 0 times in the rated set`, and red on nothing else. **The other mutation answers a review point the first plan could not**: a rate emitted as a literal instead of a recomputation. Hard-coding one is red on `good` — the published block no longer matches — but that only proves the block is compared, not that the artifacts are read. Hiding `fixtures/good`'s artifacts directory and running the check is the direct measurement: red with `marked complete but has no manifest`, green again when it is restored, with the before-and-after both recorded rather than the failure alone.

**First-look review found one blocker and four holes, and the worst of them was a claim in the ADR that the code did not implement.**

*The generation sweep could never complete.* `sweep.sh` built its manifest from the generation's filtered set and then compared the row count against every row in `corpus.tsv`. g2 selects 36 of 57, so a fully successful run of it would have failed at the last line with all 36 trials present and correct. The comparison was right while one sweep covered everything and became wrong the moment a generation covered a subset — the same shape as the ten-variable `read` above, an assumption that survived because nothing had violated it yet.

*The supersession ledger did not check its own criterion.* ADR 0025 states the file's claim is narrow — "a later revision of the same target, and it is in the corpus" — and the check verified only that the successor was *some* corpus define. Measured: rewriting hg's successor to `borg-r3` left the check green. So the file could park any define at all behind a sentence saying it could not, which is worse than having no ledger, because the sentence is what a reader would rely on. The predicate now holds all three parts (same cohort, same base target, later revision), a fixture falsifies the "different target" half specifically, and the rewrite that used to pass is red.

*Three fail-open readers.* `outcome-map.tsv` accepted two-or-more columns after being published as three, allowed a duplicate tool to win silently, and took any string as a disposition — a typo like `kept-unreportd` is not `new-this-sweep`, so it passed the untriaged check while matching none of the four printed rows, and that tool's FAILs would leave the ratio without a trace. Shape, uniqueness and enum are checked now, and a conservation assert requires every A-group FAIL to land in one of the four printed rows. `generations.tsv` took any string as a group name, and an unrecognised one covers nothing — narrowing g2's groups to `control` removes all eight new rows from every expected set at once, after which a shrunken manifest reads as complete. The group names are a closed set, and every corpus row must be covered by the generation it enters at.

*The rulebook's corpus section still described g1 alone.* It said "28 trials, 10 tools" unqualified while the frozen corpus this PR is about carries 36 across 18 tools. Split into two tables by entering generation, with the g2 one saying outright that it has not been measured.

*And the ADR's own status was wrong by this repository's rule*, which says an ADR stays `Proposed` until its implementing PR merges. The workspace-level command that drives this flow says to promote it at plan approval; the repository's rule is the narrower one and wins.

## 2026-08-26 — two neighbouring defences, written as if either replaced the other (#326, #327, #328)

Both halves of this batch turned out to be the same mistake in different places: a new mechanism that looks like a superset of an old one, and is not.

**The destructive walk (#327).** Holding the root by descriptor closes the swap window — every delete is relative to the inode opened once, so replacing the pathname afterwards redirects nothing. The plan said that made `assertRootResolvesToItself` redundant and retired it. The first-look review killed that: `O_NOFOLLOW` is about the **final component**. With root `/a/b/state`, replacing `/a/b` with a link opens the other tree, and the new walk would then empty it race-free and thoroughly. The guard's own doc says it covers a parent component; the descriptor does not. Both ship. The same shape a second time, three lines up in the same file: the denylist's sunset note says to delete the list once the root is held by descriptor — but that list stops a **mistyped** root, and holding `/etc` open deletes `/etc` just as completely. Pinning identity and picking the right target are different properties. The note was wrong when it was written, and #327 is what made that visible, so it is corrected rather than obeyed. A second consumer settles it structurally: `mcp.zig` runs `assertSafeRoot` on `SIDEEYE_MCP_ROOT` at startup, where there is no delete at all — a sunset phrased around deletion would have authorised removing a guard that a naming boundary still depends on. The replacement condition names both consumers and the two ways a destructive root actually arrives — the MCP knobs constrain where one may resolve and never supply one, and putting them on that list would have repeated the conflation being corrected.

**The marked region (#326).** First design was a per-process marker from `/dev/urandom`: unforgeable, and it would have forced `mcp-acceptance.sh`'s summary-equality check — the strongest thing pointed at this surface — to read the marker out of the very string it is checking, which passes for an empty marker. Second design was a fixed delimiter with both tokens escaped. What shipped is neither: **the region states its byte count, and the count is the extent.** Counting removes the scan, so there is nothing to forge and no escape rule, and the quoted diagnostic survives byte-for-byte — which matters, because the region *is* the diagnostic. Reframing "how do we make the marker unforgeable" as "how is the extent decided" is what dissolved it, and that took two review rounds to reach.

**Measured rather than asserted, after getting it wrong three times.** The cap on the text block was "under 10 KiB" in the draft, "~50 KiB" after review, "~50 KiB" again in the revision — all three written without opening anything. `readFileAlloc` reads the oracle output with `maxInt(usize)` and no line-length bound, so `message` has no upper bound anywhere in this codebase. Measured in a container (strace 6.13, a 4,021-byte path holding 248 control bytes): longest line **8,919 bytes**, and strace prints filenames in full — `-s` bounds write buffers, not paths. The adversarial maximum is arithmetic: four bytes per byte on the oracle side through strace's own escaping and four on the shim side through `sanitizeForReport`, on different bytes — the two do not compose — so ≈33 KiB each and ≈66 KiB together. 128 KiB, and the doc says outright that this does not bound what reaches the agent — `structuredContent` still carries up to 4 MiB.

**The issue's premise was wrong, the correction was wrong, and the correction of the correction was right.** #326 says the report carries "bytes the explored operation wrote to stdout" via `l1`/`message`, and `readFile`'s own doc said the same. `l1` is engine prose at all five of the places it is set, one of which interpolates counts. The revision then claimed stdout could never be in scope, because `--work` is forbidden inside the state directory — true of the engine's redirection and false in general: scope is decided by the `-y` descriptor annotation alone, so a target that points its own fd 1 at a file in the state directory is in scope, and what it writes is quoted into `message` through the raw oracle line. Three passes to land on what the code actually does.

**Also fixed here because it is the same class:** `snapshotOrRefuse` splices the offending entry name into a `SETUP_ERROR` with no defang, four lines of reasoning away from `refuseUnsupportedEntry`, which defangs. That code was added in the previous batch, by the same author, in a batch about exactly this.

**Verification.** Each new check seen red once, with attribution. Handing the directory stream `dirfd` itself, so `closedir` closes the descriptor the rebuild writes through, reddens the existing `restore` and `corruptState` tests — the call sites caught it, not a new test. Collapsing `freshDir`'s absent-root reading into `deleteTree`'s reddens only the new test that separates them. Replacing the region's count with a scan for the closing banner reddens only the new banner leg: the mutant changes output solely when the message spells the banner, so no other fixture can see it. The macOS baseline for `mcp-acceptance.sh` is 8 failures out of the 13 legs this batch leaves behind (12 before it added one) — it is a Linux-container suite — and the batch was checked against that number rather than against zero: 8 before, 9 with the format change, 8 after the checker was taught the new shape.

## 2026-08-26 — the writes the shim could not see, and the copy whose destination is not its first argument (#244, #256)

Two observers, and a list on one side that the other never compared itself against. The oracle has classified `pwritev`, `pwritev2` and `renameat2` since v0.1; the shim never exported them. On Linux that is an honest `oracle_missed_operation` — measured before touching anything, and the refusal names the exact line the shim had no record of. On macOS, where SIP leaves no usable oracle, the same write is invisible to **everything**, which is the difference between an ergonomic gap and a PASS hole (the phrasing v7's `remove(3)` entry earned). Trace contract **v11**: the countable operation set widens, so saved v10 cases refuse with the mismatch named, which surface 4 of the freeze calls promised behaviour rather than breakage.

**The interesting half was `copy_file_range`.** ADR 0006 decides fd-syscall scope from "the descriptor", implemented as argument 0 and documented as a fact about the category — true of every fd syscall the contract had. `copy_file_range(fd_in, off_in, fd_out, …)` puts the SOURCE first. Classifying it without noticing would have been wrong in **both directions at once**: a copy out of the state directory counted as a mutation (a fabricated operation, and a fabricated crash point with it), a copy in from elsewhere scoped out and missed. The evidence was sitting in the test that pinned the syscall as unsupported — its fixture line carries annotations on arguments 0 and 2 — and nobody had read it that way. What ships is a declared table (`fd_write_args`) whose default is argument 0, so every existing fd syscall behaves exactly as before; `sendfile`'s destination is already first and it deliberately gets no entry, pinned by a test so a later simplification cannot drop the default quietly. ADR 0023.

**The first-look review found two things the plan had wrong, and both were about this repository's own history.** First, the symbol list was short: `no-accel-copy.c` — cohort 4's own apparatus — potholes *three* names including `sendfile64`, and this repo already exports `open64`/`pwrite64`/`fopen64` and keeps a `toy-lfs` specifically to walk the LFS alias path. Shipping five symbols would have re-opened a class the project had already paid to close; the batch ships eight. Second, and worse: **that apparatus collides with the new exports.** `no-accel-copy.so` answers the copy primitives in userspace through `/etc/ld.so.preload`, and the engine owns `LD_PRELOAD` for the shim. Measured with a two-library probe rather than reasoned about — **LD_PRELOAD wins** — so the shim's wrapper records the copy, calls through to the stub, and the stub returns ENOSYS without issuing a syscall: an operation on one side of the account and nothing on the other, which is a phantom and refuses. The define it belongs to is a criterion-1 exhibit.

The review's follow-up pass then caught that closing that was only half the problem: `upstream-fix/run-replay.sh` is both the collision's owner **and** a replay of a committed v10 case, so from v11 on it stops at `contract_version_mismatch` before reaching the collision at all — and `spike/check-sealed-campaigns.sh` walks only `blind-hunt*/`, so cohort 4 can break with CI green. Owner ruling: keep it as history and annotate. Deleting the stub was refused for a reason worth recording — run2's committed oracle transcript contains its preload lines, so removing the source would leave a transcript nobody could account for. The PRD's criterion-1 paragraph gets the same instrument note: those measurements stand as taken, on their date, with the engine of that date.

**The structural half deliberately is not a set-equality check.** The obvious form — compare the oracle's `known` with the shim's exports — was measured before being written — and the first draft of this entry got the numbers wrong by taking them from the review that suggested the shape rather than counting: **28 exports have no `known` entry** (stdio, the process family, the LFS aliases) and **4 `known` entries had no export** (`openat2` plus the three that were the real gap). Equality would have started red on 32 differences, 29 of them legitimate — only the three were real — and the cheapest route to green would have been an exclusion list — where adding one line is also the cheapest way to hide the next real gap. `spike/check-shim-coverage.py` asks instead: for each classified syscall, is it interposed, or is there a recorded reason it is not? The exclusion list **is** the check. Both sides are parsed from source, never transcribed, so a table claiming an export the shim lacks cannot pass. It runs in CI — the existing `class-drift-check.py` is reachable only from `spike/cohort4/preflight.sh`, which is precisely why it could not have caught this.

Seen red, all of it: `pwritev` refusing before the export existed (with the bytes asserted too — the toy hands two iovecs, so a wrapper with its arguments transposed records correctly and writes wrong); the copy refusing in both directions; and three mutations against the coverage check — drop an export, drop a reason, add a classification without an export — each red, each naming what was missing. Removing the `fd_write_args` entry fails the copy legs in **both** directions, which is the point of having both. Also taken from the review: `renameat2`'s flags decide what it means, so `RENAME_EXCHANGE` and `RENAME_WHITEOUT` refuse by flag name the way `linkat(AT_EMPTY_PATH)` does rather than being counted as renames; the optional symbols set `errno = ENOSYS` when their lookup fails, because Rust std's kernel_copy reads errno to decide whether to fall back and a bare -1 would turn "this shim cannot see the call" into "your copy failed"; and `spike/Dockerfile` pins rustc (1.97.1) so a rolling tag cannot change which primitive the Rust toy exercises under a leg that asserts which one it saw.

**The first-look review of the implementation found the batch doing the thing it is about.** Its top finding was that the set-difference numbers written into five places — the script's docstring, the acceptance comment, this entry, the CHANGELOG and the ADR — did not match the tree. They came from the review that suggested the check's shape, and were transcribed instead of counted: the real figures are 28 exports with no `known` entry and, before this batch, 4 `known` entries with no export. Worse, thirteen of the fourteen rows in the exclusion table named syscalls that are not in `known` at all — the #121/#190 metadata families live in separate oracle tables — so the table looked like it carried thirteen standing decisions and covered one. The script's own runtime line printed `len(NOT_INTERPOSED)` and inherited the same lie. Fixed by counting: the table holds one row, the output reports the intersection, and a new `stale` branch fails on any row naming a syscall the oracle does not classify (seen red by adding `chmod` back).

The same review found a second `#256` still open, on the side where it costs more: **`fdatasync` is classified by the oracle, exported by the Linux shim, and was absent from the macOS interpose table.** No public header on macOS declares it, which is why `callFdatasync` carried the comment "Darwin has no fdatasync; fsync is the honest equivalent" and forwarded there. Measured against libSystem: the symbol exists. So the shim was substituting a stronger, slower call for the one the target made — different contracts, and a shim that swaps them changes the target rather than observing it. Both fixed here. Note what did **not** find this: the check this batch added reads `shim/src/linux.zig` only, and its docstring now says so, because otherwise the next person to look would read a green run as covering both platforms.

Also from that review: `renameat2`'s flag branch shipped with no test at all, while both of the siblings it was modelled on (`linkat(AT_EMPTY_PATH)`, `unlinkat(AT_REMOVEDIR)`) have them — five cases now, including the two that matter, a filename spelling `RENAME_EXCHANGE.bak` and the numeric `0x2` that `strace -X raw` prints (reading only the symbol failed OPEN there). The acceptance legs asserted `rc != 2`, which passes on SETUP ERROR; they now require a verdict, and the copy leg requires the crash point to have been counted. The LFS aliases were exported on the strength of `toy-lfs`'s precedent and then exercised by nothing — there is a `-D_FILE_OFFSET_BITS=64` build and a leg for `pwritev64` now. And the Dockerfile pin's stated reason was false: no leg asserts which primitive Rust std picks, because the Rust toy does not copy. The pin stays, with the honest reason.

**The procedure both of those failures point at.** P1-1 (numbers transcribed rather than counted) and the review's follow-up finding — three places still saying macOS gained "`pwritev` alone" after `fdatasync` had been added to that same table — are one shape, not two: a quantifier written before the implementation settled, and never re-read once it moved. The word is the entry point (`alone`, `one`, `every`, `all`, a bare count), and it hardens into prose while the code around it keeps changing. Grepping the diff for quantifiers just before opening the PR, and checking each against the code rather than against memory, catches both of these on the day they were written. That is worth more here than either individual correction.

**#257 is deferred, with the measurement returned to it.** The apparatus survey found nine devices, not the six the issue lists — and two of them cannot become config keys at all: `seccomp-enosys.json` applies at the container boundary, and `pin-getpid.c` is used by no define (it is probe-only, and the reason is recorded in the define that cannot use it). The report side depends on #320, since surface 2 is the one frozen surface with no additive rule. The three-tier apparatus policy #257 asks for already exists in the cohort protocols; what is missing is promotion to the product surface, which DESIGN's own budget sentence ("a sixth key — or a third shape — should face it again") makes an owner call. One thing this batch does change for it: with the copy primitives interposed, "kernel-copy acceleration" drops out of the kit #257 would need to carry.

## 2026-08-26 — the trace read's cap, and the two places it had to say so (#320, #324)

`readTrace` was the engine's second unbounded read, and #265 left it that way on purpose: every failure of that read collapses into an empty `TraceInfo`, which the caller reports as `no_shim_marker`, so a naive cap would relabel an oversized trace as a shim that never started — a refusal with the wrong reason, worse than none. That reasoning stands; what changed is that the cap now has a way to say what it is. `error.FileTooLarge` is caught apart from every other failure and raises `too_large` with the size `lseek` measured; everything else still collapses, because for those the empty TraceInfo is the honest observation. The new `unknown_reason` is `trace_too_large`, the reader's side of the pair whose writer's side is `trace_truncated` — the shim stopped mid-record there, the engine declined to hold a complete account here. UNKNOWN, not SETUP_ERROR: both read sites sit at or past the recording run, where exit 3's "the define did not run" is the lie `child_wait_failed` already refused to tell.

**The draft I wrote had one read site. There are two, and the second one fails worse.** `main.zig` reads a trace after the recording run and again inside the world loop, once per world. The loop's site has no shim-marker branch at all, so a collapsed read there leaves `kill_landed_seq` null and the run refuses with `kill_did_not_land` — a claim about the engine's own kill, drawn from a trace the engine declined to read. The plan's adversarial review found it before any code existed. Both sites now check `too_large` ahead of their existing branches, and the position is the design: `unknown` does not return, so a check placed after the branch that would otherwise fire is unreachable.

**The unit tests could not see the wiring, and saying so is what bought the apparatus.** The branches live in `main.zig`, whose refusals exit the process, so the first draft tested a mirror of their order in `engine.zig` instead. Measured: deleting either real branch from `main.zig` left the whole suite green — the mirror only ever tested itself, the same shape #267 recorded when a guard's call was removed from `restore` and nothing went red. The mirror is gone now, deleted in the simplification pass rather than kept as a second, hand-synced definition of an order that lives elsewhere (#280's complaint, made against this repository's own code). What replaced it is `-Dtest-trace-cap`: engines with a 64-byte ceiling, built the way `-Dtest-seq-gap` builds its shim — generation-gated, separately named, the shipped value a literal rather than the flag's default, with CI asserting byte-identity of the shipped binary (measured locally too: same sha256 with the flag on and off). **Two** such engines, because the recording read exits before the world read is reached, so one lowered cap can only ever demonstrate the first site. Acceptance drives one run through each plus a control on the shipped engine; reverting either call site turns that site's leg red on the REASON rather than the exit code — both collapses still exit 2, which is why the leg greps for `trace_too_large` and not merely for a refusal.

**The simplification pass broke something the file says six lines below, and review caught it.** Folding the read and the cap check into one helper moved the recording site's refusal ahead of `engine.classify` — while the comment above that call promises every UNKNOWN beneath it reports the classification that existed rather than the placeholder. L0 comes from the snapshots and an oversized trace does not touch it, so the classification was available and was being thrown away: `trace_too_large` would have been the one structural UNKNOWN reporting "not classified". The read and the answer are two calls again, paired by name, with the recording site classifying in between. Measured after the fix, on the lowered-cap engine: the refusal now carries `atomicity 1 path(s) judged pre-or-post`.

**Running it found what the tests did not.** The first real firing printed "against a 67108864-byte cap" on a run capped at 64: the message reported the shipped constant instead of the cap that actually fired. Invisible in production, where the two are equal, and it would have been pinned as correct by an acceptance leg written from the unit tests. The refusal takes the cap in force as an argument now, and the leg asserts the number.

Sized from measurement rather than taste: the largest recording in this repository is 119 explored worlds (Borg, cohort 2), which at the contract's worst-case record — `max_record_len`, 8210 bytes for two `max_path` components — encodes to under 1 MB. 64 MiB leaves that more than sixty times over. **What this does not claim** is anything about the published UNKNOWN rate: trace size scales with operation count, not with state size, so the corpus behind that number says nothing about this cap. #239's re-sweep is where that gets measured.

**#320, decided rather than discovered.** Surface 2 of the freeze forbade removing an account field and silently changing a machine field's meaning, and said nothing at all about adding one — while surfaces 1 and 5 both carve out additive extension in as many words. Two readings were defensible and the owner picked additive: a new optional field may appear in 1.x, and a consumer must tolerate fields it does not know. The `unknown_reason` closed set is explicitly outside that allowance, which is why `trace_too_large` had to land before the tag rather than after it.

## 2026-08-25 — the clock's binary moves with the README it measures (#160 follow-up, run 2 prep)

Run 2's last apparatus gap was going to be an easy one: the Dockerfile still pinned the v0.10.0 tarball while the README the clock measures documents the current release, so — the reasoning went — a driver reading today's front page against a three-releases-old binary would hit flags the binary does not have. **Measured before writing it down, and the justification did not survive.** The two examples first written here, `--stop-when-orphaned` and per-mode `--help`, are in *neither* release — both merged after v0.13.0 was cut, so moving the pin does not deliver them. Worse for the premise: v0.10.0 and v0.13.0 print **identical usage text apart from the version string**, the five README-documented flags I exercised (`--oracle`, `--allow-unverified`, `--check`, `--marker`, `--fresh-state`) parse on both, and `demo` produces the same report on both including the one report concept the README names (`not tested`). The README names thirteen long flags in all; the other eight were never tried, and review caught the first draft of that sentence calling the five it measured "all". There is no observable README-to-binary mismatch between the two releases today. A changelog-first-mention proxy said otherwise for `--oracle` and `--allow-unverified` ("added in 0.11.0") and was wrong — run 1's own transcript shows the v0.10.0 binary taking `--oracle` — which is the reminder that a changelog entry records when something was *written about*, not when it started working.

The pin still moves, on the argument that survives measurement: **criterion 6 asks what a fresh machine does from the README, and a fresh machine today downloads the current release.** Pinning a three-releases-old artifact measures a pairing no real user has, and the gap only widens with each release; that is a validity argument about the instrument, not a defect claim about v0.10.0. Written that way in the amendment rather than as the mismatch story that measurement killed. Rehearsal-boundary verification only, as the protocol permits: the image builds, the pinned sha check passes (recomputed from the downloaded asset, not copied from a page), the binary prints its banner in the box (`sideeye 0.13.0 (trace contract v10)`, raw rc 0), and jrnl accepts a non-interactive entry and reads it back — nothing ran sideeye against jrnl. Two documentation repairs ride along, both the stale-referent class this apparatus keeps producing: the launcher's usage comment and its `${1:?}` usage string both offered `run1` as the example name, and run 1's RESULTS.md says the clock ran against "the repaired artifact, sha-pinned in the Dockerfile" — a live referent this very PR repoints, now dated in place. **Review then killed the reason I gave for the first repair and exposed a worse problem underneath it.** I wrote that the "one run per name" guard would refuse `run1` anyway, so the stale example merely could not work. Measured: the guard keys on `transcript.jsonl`, which is **gitignored** — on any fresh clone that file is absent while run 1's committed `meta.json` and `timeline.tsv` sit right there, so the guard passes and the `mkdir -p` above it sends the new run into run 1's directory to overwrite its evidence. The interlock could not hold on any machine except the one that ran run 1. It keys on the directory being non-empty now — what survives a clone — measured refusing `run1` in this worktree, where the old predicate passes, and passing an unused name.

## 2026-08-25 — the case names what gets destroyed, the snapshot has no ceiling, and the numbering net has no reacher (#265, #266, #270)

Three v1-tightening holes in one batch, all of the same family: a safety property everyone believed was held by something that was not holding it.

**#266.** The MCP server vets the *case path* against `SIDEEYE_MCP_ROOT` and then hands the engine `replay <case> --fresh-state` — and the engine takes the state directory from inside the case file. Nothing connected the two: a case inside the root could name any directory the destructive-root denylist does not (the denylist stops `/var/lib`, not `/Users/alice/projects` — #267's own text calls it "a denylist, not a safety boundary"). Two premises died during design. First, `--fresh-state` is not the destructive trigger — `engine.restore` deletes and rebuilds the state directory once per world, so a flagless replay destroys just as thoroughly; the issue and the first plan draft both carried the mistake. Second, "replay's path is vetted" reads as safety and is the opposite: the replay tool's description said nothing about execution while explore's said "the operation is executed; the config is a trust boundary" — two tools side by side, the one that also empties directories reading as the safer one. What ships: a replay-only `--state-under <dir>` flag enforced in the engine at the point the value is read (same bytes checked and used, no second parse, no check-to-use window — the mcp-side pre-parse alternative was rejected for exactly the drift-and-TOCTOU pair this repo keeps refiling), **strict** inside (`SIDEEYE_MCP_ROOT=$HOME` plus a case naming `$HOME` itself would otherwise make the home directory the sacrificial one), and a second environment variable, `SIDEEYE_MCP_STATE_ROOT`, because "which files may be named" and "which directories may be emptied" are different properties: the operator who wants CLI-made cases (state under `/tmp`, the documented convention — every committed define) replayable through the server widens the destruction range explicitly and the naming root stays narrow. Unset falls back to the root. The owner ruled on four points: replay-only (a root-writing attacker runs the case's own setup/operation — ACE by design, ADR 0010 — so confining explore's vetted configs buys nothing in the domain where the flag works at all and breaks every documented config); strict inside; the separate variable; close #266 and split the residue. What the flag does NOT do is written where it can be seen: the effective domain is "a received case, in a workspace the agent cannot write" — supply-chain and accident, not a hostile agent; the check-to-opendir window `assertRootUnchanged` narrows stays open (hostile setups retry it once per world); ADR 0022 records the split and the scope. Measured: acceptance leg A **runs the destruction for real every suite run** (flagless replay of a crafted case empties the victim — the red side stays demonstrated, not remembered); legs B–F pin refusal-with-untouched-directory (sentinel survives), equal-refused, inside-passes, explore-refuses-by-name, duplicate-refused. The mkdir undo is measured by its own leg, not by those: B–F hand the engine an EXISTING victim, so their refusals never have a directory of their own to undo — the security review caught that the four undo calls could all be deleted under a green suite, the exact "tests aim at functions, mutants survive at call sites" shape, and a first draft of this entry claimed "both mkdirs undone" on legs that never measured it. Leg G replays a case naming a not-yet-existing outside state, so the refused invocation's own mkdir succeeds and the leg asserts neither it nor the work dir survives; leg H pins `--state-under /` refusing as a range that confines nothing (the one branch whose deletion makes the feature fail OPEN — `isStrictlyInsideDir(x, "/")` answers true for everything else, and only that branch stands in front); the server refuses `STATE_ROOT=/` at startup for the same reason, and preflight's by-name refusal got its own leg instead of riding explore's shared predicate. Deleting the check is KILLED by exactly those legs — the failure message is "sentinel GONE", the harm itself. On the server side mcp 10 (fallback refuses outside), mcp 11 (STATE_ROOT=/tmp lets the same case replay — the env branch's live coverage, without which half the new code ships unmeasured), mcp 12 (root `/` and `/tmp` refuse at startup; unresolvable STATE_ROOT refuses rather than running unconfined). mcp 11's first run failed for check 8's reasons, not its own — the borrowed case's setup is deliberately non-idempotent (`mkdir state/once`), and the leg now clears that marker. One near-miss the plan review caught before it shipped: `spike/loop-closure-timew`'s MCP variant stages cases with state at `/tmp/loop-state` and a root elsewhere — the README's "measured, not aspirations" evidence would have refused under the fallback; its mcp.json now sets `SIDEEYE_MCP_STATE_ROOT=/tmp`. And one inversion that had to ship atomically: `resolveInsideRoot`'s hand-rolled prefix check and `contract.isInsideDir` disagree on root `/` in **opposite directions** (reject-everything vs accept-everything), so unifying them without the startup `assertSafeRoot(server_root)` vet would have flipped fail-closed to fail-open; they are one commit, and mcp 12 pins the refusal so neither can be removed alone quietly.

**#265.** `readWhole` had no cap while every other read in the pipeline has one (case 1 MiB, MCP report 4 MiB) — and snapshots call it for every file, hundreds of times per explore, so one multi-gigabyte state file was an OOM kill with no report. Now: 64 MiB **per file**, refused as a SETUP ERROR naming the file, its size (from `lseek(SEEK_END)` at the moment the cap breaks — the read loop stopped before it could know, and a size nobody measured must not appear in the message) and the cap. The cap is a parameter for the reason `readLinkTarget`'s buffer is one: against the shipped constant the boundary is a claim nobody falsifies; the unit test drives it at 8 bytes, the acceptance leg drives the shipped constant end to end with a sparse 64 MiB+1 file. Two deliberate boundaries. The claim is per-file, not a memory ceiling — the tree's total stays unbounded (60 MiB × 1000 files still dies; review caught the thesis overclaiming "no OOM" and the wording shrank to what the mechanism holds; the total is filed separately). And `readTrace`'s `readWhole` call is **deliberately uncapped**: every failure of that read collapses into "the shim never initialised" (`no_shim_marker`), so a cap there would relabel an oversized trace as a shim that never ran — a refusal with the wrong reason is worse than no cap, and the trace's unbounded read is filed on its own. Removing the constant is KILLED by the acceptance leg alone (exit 1 — the run proceeds to a verdict over the huge file, which is precisely the pre-fix behaviour); the strictness mutant of the new `isStrictlyInsideDir` (`>` to `>=`) is KILLED by its unit test.

**#270.** The 2026-08-16 entry recorded, so a stale mutant result would never be cited as current: the numbering-assert wiring lost live acceptance coverage when the structural double-announcement rule took the execl shape, and R2 measured the both-asserts-off mutant SURVIVING. The recorded argument — "a live shape that reaches it would need a shim that renumbers without re-announcing, which no interposed path produces" — was exactly what had to be pinned or retired. Pinned: retiring would leave the shim's own future numbering bugs structurally invisible (one announcement, wrong numbers — the double-announcement rule never looks). The apparatus makes the hypothesised reacher exist: the same shim source with a compile-time gap (`-Dtest-seq-gap` builds `libsideeye_shim_testgap`, numbering skips 2 so any target with two in-scope operations fires it deterministically), generation-gated so a plain `zig build` — which is what brew runs — cannot produce it, hardcoded `false` in the shipped shim's own options module so no invocation of the build can make the shipped artifact skip. The option leaking into the shipped shim would have been a new guard blinding every older one (all other legs would measure the gap shim), so that is asserted, not trusted: CI hashes `libsideeye_shim.so` before and after the flagged build and requires byte-identity (measured locally first: `802709da…` both sides, gap artifact `dfb45308…`). The both-asserts-off mutant is now KILLED by the new leg **and only by it** — the suite's one FAIL under the mutant is the gap-shim check, which is the attribution the 2026-08-16 entry's standing note needed; that note is superseded by this one. The run under the mutant still exited 2 by a later net, which is the two-witness design degrading exactly as designed — but with the wrong reason named, which the leg's message anchor catches.

Process notes for this batch: the plan's adversarial first-look ran as a Codex proxy (fresh context, no conversation state) because the Codex workspace is out of credits; it confirmed every cited line number against origin/main and found the four conditions above (loop-closure breakage, thesis overclaim, the root-`/` inversion, the artifact-contamination assert). A security threat model ran before it and drew the strict-inside and startup-vet lines. On the implementation, the first-look code review's P1 was the startup vet refusing more than any document said — `assertSafeRoot`'s depth rule silently bars every single-component root (`/work`, the ordinary container mount), which none of the message, CHANGELOG, ADR or README mentioned; the docs now state it and whether the naming root should be exempt from the depth rule is filed for the owner. Its P2 stands as filed: a target that legitimately writes a >64 MiB state file mid-operation now hits the cap AFTER exploration began, and `setupError` reports exit 3 — honest about the failure, wrong about the phase (the same shape `#264` refused for wait failures); moving the four post-recording call sites to UNKNOWN needs a new `unknown_reason` member and is an issue, not this PR. The security re-review's two Majors were both "a new guard unfalsified against its own predicate" — the undo calls and the `/`-range refusal — closed by legs G/H above; its smaller catches (the strictness predicate trusting `path` to carry no trailing slash, a message claiming a directory check the code does not make, the one-buffer `resolveDir` wrapper surviving as a named footgun) are each fixed in place. Both reviews' full adjudication is in the PR.

## 2026-08-25 — the onboarding clock's escape paths close at the permission layer, and the audit learns to read quotes (#160)

Run 1's review named six instrument gaps and #160 held them; this closes all six before run 2, which the criterion-6 standing note already owes. The headline change moves the box confinement toward refusal: the launcher's allowlist becomes `Bash(docker exec onboarding-box *)` — which the CLI's docs say refuses a non-box command before it runs, an expectation the plain-terminal probe at run 2's preflight will test (the one environment measured today is not that one; see below). The host-side transfer idiom run 1's driver used (`docker cp`, base64 pipelines) falls outside the declared scope either way. The audit stays as the independent second layer and stops being a string prefix — `startswith("docker exec onboarding-box")` accepted a same-prefix container name (`onboarding-boxx`) and any compound tail (`… true && anything`).

**The plan's first audit design died in its own adversarial review, twice, before any code.** A shlex token-stream predicate ("leading triple exactly `docker exec onboarding-box`, zero top-level punctuation tokens") was measured to pass two escape shapes clean: an **unquoted newline** — a command separator to bash, but whitespace to shlex, so it can never appear as a token — and a **backtick substitution**, which shlex treats as neither quote nor punctuation, so it rides along inside an ordinary word. The shipped predicate is four conditions: the leading triple, zero top-level operator tokens, raw-vs-in-token newline counts equal (a quoted newline survives inside its token; an unquoted one is consumed — the counts differ exactly when one was unquoted), and no `` ` `` or `$(` anywhere (an unquoted `$(` splits at the `(` and is already an operator token; a quoted one survives in its word — legitimate in-box substitution included, surfaced anyway because the audit cannot tell the two apart and prefers a flag over silence). shlex `ValueError` is a finding ("unparseable"), not a crash: the committed run-1 quotes themselves prove truncated commands with broken quoting occur, and an extractor that dies mid-run-2 is worse than one that flags.

**The committed evidence could not be the selftest's fixtures.** The natural move — feed the audit the three flagged commands quoted in `runs/run1/meta.json` — fails structurally: those strings are `head()`-truncated at 160 characters with their quoting broken mid-string, and 2 of 3 raise `ValueError` (measured in review, re-measured before adoption). The selftest says so in its docstring and carries hand-authored full-length representatives instead, including run 1's real in-box heredoc author shape as a must-stay-clean fixture. The selftest runs at the top of every `run-clock.sh` launch, so a predicate regression stops the launch rather than surfacing at adjudication.

The rest of the six: stop candidates now require `\bexplore\b` as a word (a `grep worlds_explored` result leading with PASS was a candidate under the substring test); the violation list splits into `audit_void` (denied tool, repo read — the protocol's outright voids) and `audit_adjudicate` (everything the box predicate surfaces, **including shapes the permission layer legitimately allows** — a redirect into the driver's own scratch passes the CLI as "the command", so "flagged" cannot be read as "escaped"; run 1's transfer adjudication stays the precedent); `meta.json` gains `target_version` (read from the box before the clock starts — deviation 2 promised it recorded, and run 1 carried it only in a truncated timeline head) and `protocol_version` (which amendment a run ran under, since the amendment restarts the run count per the protocol's own rule); the scratch cleanup replaces `rmdir || true`, which failed silently the moment the driver wrote a file — run 1 left its scratch on the host — with a name-echo plus real removal; and `.gitignore` drops the `canary-out.txt` entry for a file the canary never writes (its stdout goes to a variable).

**The permission-layer probe measured the wrong regime, and saying so reshaped the design.** The falsification plan was two headless drivers against a live box — the old open allowlist executing all five probe commands (it did: the `-boxx` name, the `;` tail and the newline tail all ran — today's red), then the scoped allowlist refusing the escapes. What the scoped run measured instead: **none of the escape shapes was refused, and the one command blocked was the legitimate in-box heredoc author — by "the Claude Code auto mode classifier", which is not the allowlist at all.** The probe was launched from inside a Claude session; under that launch nothing refused the escapes, and the one denial that did occur names the classifier — so the declared pattern demonstrably did not gate, and whether it was consulted at all is not observable in the transcript. Re-measuring with the session markers stripped from the environment was **blocked by omamori — an AI-detection env var is not something this workspace unsets, measurement purpose or not — and the block was honoured, not worked around.** So the claim is written at the strength the measurement allows: the docs' gating behaviour (word-boundary ` *`, per-subcommand matching, newline as separator) is recorded as expectation, not fact; a plain-terminal probe rides with run 2's preflight as a named precondition; and the launcher gained a structural guard that **refuses to start when `CLAUDECODE` is in the environment** — a nested launch measures the wrong regime entirely, and would hand run 2 an apparatus DNF (the classifier blocking the driver's only authoring idiom). The guard's firing branch is measured (refuses, rc 1, creates nothing); its pass-through branch cannot be measured from inside a session by construction, and is one `[ -n ]` test read by eye.

**First-contact review of the diff caught the audit lying one more way — the same class as the plan review's two.** shlex's default `commenters='#'` discards everything after a `#` even mid-word, where bash reads a literal: `docker exec onboarding-box echo a#b; rm -rf /host` tokenized to five words and passed all four conditions clean while bash would run the `rm`. One line (`lx.commenters = ""`) closes it; the cost — a leading-`#` bash comment now flags — is the flag-over-silence direction the amendment already chose. The selftest carries the shape as its eighteenth check, and six mutations — the `startswith` revert, the substring stop-candidate, the merged vocabulary, each dropped meta field, and the commenters default restored — were each seen red on the committed checks, each missing only its intended assertions. The same review tightened four sentences the probe paragraph had left claiming more than the transcript shows (the allow-direction attribution to the classifier is inference — only the one denial names it), the protocol's own preamble (which promised itself unchanged while this PR amends it: the stale-present-tense class RESULTS.md's note exists to fix), the re-projection sentence in that very note (unmeasurable here — the raw stream is outside the repository), and the selftest's timestamp substrings (`"T1" in …` aliases against future `T10+` fixtures; the asserts now match `" at T1:"`).

The protocol body now says the audit surfaces rather than voids the box-predicate class (the old sentence voided any non-docker command; run 1's own adjudication already read it more carefully), and an Amendments section carries the restart, the run2-continues-numbering rule, the CLI's parse/10,000-character prompt bounds as run-2 DNF suspects, and one attribution note: a driver reaching for run 1's transfer idiom will be refused until it re-derives in-box authoring, and that detour is apparatus, not documentation — a slow run 2 gets its timeline checked for refused transfers before the number is read as a README verdict. RESULTS.md gains a dated instrument note because three of its present-tense sentences ("stays byte-identical", "keeps its strict prefix check", "re-runnable + the extractor is committed") became true-of-run-1's-date rather than true-today — the same stale-bold class a review caught in DESIGN §17 earlier the same day.

## 2026-08-25 — criterion 1 adjudicated met: a fix that changes the operation sequence gets a second regression shape (#305)

#305 put the question and deliberately carried no recommendation: the himalaya case refuses against the fixed build (`case_no_longer_applies` — the freeze's promised behaviour), so the timewarrior-shaped "PASS patched" leg is unreachable for it, and whether that disqualifies the finding was the owner's to rule. The ruling is option A. "Kept as a replayed regression case" accepts, for a finding whose fix changes the recorded operation sequence, the shape the upstream-fix record already measured: the exhibit replays against the pinned buggy build (run 1 — empty diff against the committed transcript after normalising the minted filename, the per-run work path and the driver's own header lines), and the defect's absence on the fixed build is demonstrated by a fresh explore under controls — run 4's PASS 4/4 through the single-guard relaxation with the checker still falsified before the run, run 5's negative control keeping the original defect caught on the stock build, run 6's functional control pinning that a copy happens at all. What the shape gives up is written into the ruling rather than hidden: it answers "did the defect go away", not "did this exact exhibit stop firing" — the exhibit cannot, by construction.

Option B was rejected on the issue's own observation: it would make the criterion select partly on what upstream chose to do rather than on what the search found — this fix restructured the write into staging-then-rename, and a bar that fails the finding *because* the repair restructured the write is measuring the repair, not the discovery. Option C (re-record on the fixed build) is not required and stays available as hygiene. Nothing in code or CI changes: the frozen checker keeps its assertions, and `spike/dogfood-timew-replay.sh` keeps its stricter leg C, which its own case can meet — the timewarrior patch left the sequence intact, so the stricter shape remains the right one where it is reachable. With the ruling, criterion 1 is met on the himalaya finding and #140 closes. What v1.0 still waits on is unchanged by this entry and listed where it lives: criterion 6's owed re-run behind #160, and the freeze audit's standing re-sweep (#281).

**Review of this entry's own PR caught the entry's own class before commit.** Three new sentences said "empty diff" while the script that claim rests on normalises three things first — the minted filename, the per-run work path, and the driver's own header lines — and its guard refuses byte-identical inputs, so the unqualified form overstated exactly the way this repository's review axis warns about. Fixed in all three places, plus a bold-status collision in DESIGN §17 (the paragraph's head said "stays open" in present tense above the appended "is met") and an understated description of the relaxed instrument (it also carries a non-judging evidence recorder). The committed record holds the same class twice more — its README counts "two things" where its script normalises three, and the pre-existing PRD trail sentence carries the unqualified "empty diff" — which makes three instances and trips the full-sweep threshold: #318.

## 2026-08-25 — an orphaned exploration stops itself: the channel was the bug, and the test staging was the other bug

#269 recorded that a killed MCP server leaves the target's process group running, and proposed `PR_SET_PDEATHSIG` plus a liveness pipe. What shipped is neither, and it is also not the design this branch tried first. The first design passed the server's pid to the child in an environment variable and compared it against `getppid()` at each world boundary. It worked, and then it was measured: **the variable reaches the target too** — the engine hands the target its own environment on the non-minimal path (seven inheritances counted in one run) — and **a stale exported copy stopped an unrelated direct-CLI explore at its first world**. The fix for that, "trust the value only if it already matches `getppid()` at startup", closed the leak and quietly destroyed the check: a nonexistent pid — the deterministic test input — now classifies as stale and is ignored, so the only remaining way to verify the feature was to actually kill a parent mid-run, and three stagings of that had already failed. The channel's two properties — inherited, and outliving its sender — were the whole disease. Every fix was a symptom fix.

**Zero-basing on the channel**: argv is per-invocation and is not inherited. `--stop-when-orphaned` is a documented flag; the engine records `getppid()` at the top of `main` — captured any later, a launcher that died during setup or the recording would be indistinguishable from the baseline — and refuses to start another world once it changes. No pid travels anywhere, nothing can go stale, nothing leaks, and the synopsis check that would have flagged a hidden switch is satisfied by not hiding it. The nohup pattern (orphan a run on purpose) keeps working because the default is off; the MCP adapter passes the flag on every self-exec. `PR_SET_PDEATHSIG` stays rejected (Linux-only, and mid-world immediacy is the wrong shape); the pipe stays rejected (the write end is inherited by the child, which would hold the channel open against itself, before counting the descriptor-number convention, `FD_CLOEXEC`, non-blocking reads, and an exemption from the minimal env's fd sweep). `unknown_reason` gains `parent_exited`; the doc-versus-enum gate holds `docs/report-schema.md` to the contract, the same three-place edit #264 documented.

**The staging that finally measured it kills the launcher from inside the run.** Three earlier attempts each failed before measuring anything: a launcher that `exec`'d the engine keeps its pid, so the recorded pid *was* the engine and killing it proved nothing (caught by an alive-before-the-kill assertion); a forked launcher raced the sub-second exploration; and slowing the operation with a `sleep` wrapper created a process boundary that ended the run as UNKNOWN before any world. The shipped staging has no timing at all: the define's own `--setup` reads the launcher's pid from a file and SIGKILLs it, so the launcher is alive when the engine captures its baseline (it forked the engine a moment earlier) and dead before the first world boundary (setup precedes the recording). The same trick tests the full MCP path in `mcp-acceptance.sh` check 9 — the config's setup assassinates the *server*, and the orphaned engine's report is read off disk since nobody is left on the transport.

**Review round two found the staging leaning on unspecified shell behaviour, and the claimed reproduction did not reproduce — the fix went in anyway.** The launcher writes `$$` and then runs the engine as the last command of `sh -c`; POSIX permits a shell to exec that tail, and an exec'd engine *is* the recorded pid, so the assassin would shoot the engine instead of the launcher. The reviewer reported verifying the pid reuse on dash; measured here, both dashes at hand fork the tail in every shape tried (bookworm and ubuntu, list and single-command, tail's own pid compared against the recorded `$$`). That disagreement does not rescue the staging: the behaviour is unspecified, so the green run was resting on a shell implementation detail either way. The launcher now ends with an explicit `exit` so the engine can never be the tail, and both assassin legs assert the launcher's own exit status is 137 — the same staging precondition mcp 9 carries — so a kill that lands anywhere else is loud instead of quietly measuring nothing. The three engine-side mutations were re-run red under the hardened staging.

**Two assertions in a row were structurally unable to fail, and the reviewer caught the second.** "No world ran" was first asserted as the absence of `path(s) judged` — printed on the UNKNOWN path too — and then as the absence of `explored N worlds`, which is also only printed on the PASS/FAIL paths, so moving the guard after the first world satisfied both spellings. The report JSON's `explored` field is written on every path; the acceptance leg asserts `explored == 0`, and the mutation that moves the guard after world one now fails it with `explored=1`. Four mutations were each seen red on the committed checks: deleting the comparison (leg 1), ignoring the flag gate (leg 3, the nohup pin), firing only after a world (leg 1's explored assert), and dropping the flag from the MCP argv (mcp 9, the shipped-path pin).

## 2026-08-25 — the symlink guard was carrying the x86_64 number for all of Linux

`O_NOFOLLOW` in `src/posix.zig` was `if (os.tag == .linux) 0o400000 else 0x100`. The value differs **within** Linux by architecture: 0o400000 on x86_64, 0o100000 on aarch64. Measured three ways in three places — a C probe in an arm64 container, the same probe on x86_64, and `/usr/bin/cc` on this machine — and confirmed against `std.posix.O` for each target, which agrees with the C header everywhere. So the one caller of this constant, the MCP capture's symlink guard, was **inert on arm64 Linux**: a symlink planted at the capture path was opened straight through.

The block this line sits in already opens with "Three defects in this project so far were a platform constant that was right on one side and quietly plausible on the other, so the differing one is branched and the agreeing ones say so." The lesson was written down and the shape of the declaration is what let it happen a fourth time — a two-way branch cannot express a value that varies along a second axis. The fix is not a different number. It is `std.posix.O` with the field set and the struct bit-cast, so the architecture question is answered by the standard library that already answers it per target. The four neighbours were checked the same way and are correct on all three targets; they keep their literals rather than churning.

**The test asks the kernel.** Asserting the number would be satisfied by whatever the constant says, which is exactly how this survived. It opens a real symlink twice, once without the flag (must succeed, or "the open failed" would also be true of a missing path) and once with it (must fail). With the old constant restored the test reports `NofollowDidNotRefuse` in an arm64 container and **passes on macOS**, because 0x100 happens to be the right value there. That asymmetry is why nobody saw it: the development machine agrees with the bug.

Found while trying to ship #268's flag changes, and it is filed and fixed on its own rather than as part of them, because two of that ticket's premises did not survive measurement. `O_EXCL` on the capture does **not** make two runs sharing a `--work` refuse: every call site unlinks the capture path immediately before opening, so the second run's unlink removes the first's file and its exclusive create then succeeds. Measured with two overlapping runs — both completed, neither child exited 126, and both reported `boundary_without_oracle`, which is the interference showing up as a verdict rather than as a refusal. The plan for #268 said otherwise and so did the review that proposed doing `O_EXCL` first; both were reasoning from the flag rather than from the call sites. What that ticket needs is per-run paths, which is a larger change than a flag.

## 2026-08-25 — the destructive-root guard was inert on the platform it is developed on, and the fix's own test did not prove it was wired in

#267 asked for a stronger predicate in front of `deleteTree` and proposed three ways to get one. Two do not survive contact with this repository. **A marker file inside the state root cannot work**: `restore` empties the root and then recreates only `snap.entries`, and the comment at that loop already treats any leftover as a delete failure and refuses with `CreateFailed` — so a marker is removed by the delete it is supposed to authorise, and putting it in the snapshot would make it part of what gets judged. **A minimum-depth rule ranks danger backwards**, measured over the 61 absolute state paths this repository has committed: it refuses `/tmp/quickstart-state` (two components, and the shipped `docs/ci-quickstart/sideeye.toml` uses it) along with four spike harnesses, while accepting `/var/lib/myapp` (three components) — which is what `docs/ci-quickstart.md` told readers to use. A fourth predicate, tried after those two: "refuse a non-empty root the engine did not create" refuses every re-run of all 27 cohort defines, because `spike/acceptance.sh` and the defines' own `setup` scripts both `mkdir -p` the state directory and `setup` runs *after* the resolution; and "refuse a non-empty root with no declared setup" accepts the quickstart's dangerous example, which declares one.

**The real hole is not the predicate.** External review of the plan pointed at the ordering and it is right: `assertSafeRoot` and the `realpath` behind it run before `--setup`, and between that moment and the first delete the root can be replaced. `deleteTree` refuses to recurse into a symlinked *entry* — there is a comment about exactly that — but it reaches the root through `opendir`, which follows one. A setup command, or the recorded operation running hundreds of times, that leaves a link where the state directory was sends the delete somewhere else. The plan draft asserted the opposite ("deleteTree does not follow symlinks, so the root is safe"), generalising the entry-level guard to the root; reading the two `opendir` call sites in that function is what settled it. So the fix is `assertRootUnchanged`, one `realpath` immediately before each delete, requiring the root to still resolve to itself — which covers the root replaced by a link, any parent component replaced by one, and the root moved, in a single call. **It narrows the window and does not close it**: the check and the `opendir` are two syscalls. Closing it needs the root held open by descriptor for the whole delete, which is filed rather than done.

**The prefix denylist that came out of this is a denylist, and the guard was inert on macOS before it.** Both destructive call sites hand over the realpath'd spelling, and on macOS `/tmp` arrives as `/private/tmp` — two components, deep enough to pass. The guard's own comment says it rejects `/tmp`, and the test asserting that passes, on an input production never evaluates. The two lists are split for the same reason: subtree denial for `/usr`, `/etc`, `/var/lib` and their `/private` spellings, exact denial for `/tmp`, `/private/tmp`, `/Users`, `/home` and the other scratch parents, because `/tmp/x/state` is the ordinary case and a subtree rule would refuse all 58 of the committed paths that live there. `/var` is deliberately absent from both: `$TMPDIR` resolves to `/private/var/folders/...`, and denying that tree would refuse the platform's own scratch space. Matching uses `contract.isInsideDir` rather than `startsWith`, which would refuse `/var/library` for naming `/var/lib`. The vet also runs at first contact in `main.zig`, not only inside `restore`/`freshDir`: the first world is downstream of `--setup`, and refusing a system path only after running the target's setup command against it is not a refusal. The `mkdir` that precedes the resolution is undone on that refusal, for the reason the `--work` containment vet beside it already states for itself.

**Two existing tests were handing `restore` a spelling production never uses**, and the new check found them: they build roots as literal `/tmp/...`, which resolves to itself on Linux and does not on macOS. They would have been green in CI and red on the development machine. Both now take the resolved parent through `realpath` first, which is also what makes them exercise the precondition the destructive path actually has.

**The embarrassing half.** The first version of the falsification suite drove `assertRootUnchanged` directly, and deleting `try assertRootUnchanged(root);` from `restore` left the whole suite **green** — a guard that exists and never executes, which is the shape this project's own review axis asks for. A call-site test replaced it: snapshot a real root, plant a sentinel outside it, swap the root for a symlink, and require both `restore` and `freshDir` to refuse with the sentinel still there. Removing the call from either entry point now goes red. One earlier sabotage was worse than useless: replacing the comparison with `if (false)` made `resolved` an unused local and the build failed with a compile error, so no test ran at all — and the run still reported a non-zero exit, which reads exactly like a test going red. The mutation that means something deletes the call, not the comparison.

**The acceptance check took three tries, and the first two were green for reasons unrelated to what they claimed.** Version one planted a sentinel inside the link's target and required it to survive: the snapshot is taken after `--setup`, so it follows the link too, and `restore` deletes the sentinel and writes it back from the snapshot — the assertion was structurally unable to fail, measured by deleting the re-vet and watching the leg stay green. Version two asserted the re-vet's own refusal but used `/bin/true` as the operation, which records nothing, so no world ran and `restore` was never reached; on macOS that leg passed anyway, for a reason having nothing to do with the swap. What the container actually reports for a setup-time swap is `state_changed_without_ops` — **a structural detector that runs before any world, so the swap this leg stages is already refused today and nothing is deleted either way.** The leg pins that as the pre-existing protection it is. The re-vet covers a later timing — the recorded operation replacing the root between one world's resolution and the next world's delete — and no acceptance define can stage it, because the structural detectors see the first swap first. That case is pinned at the call sites instead. Two mutations turn the check red in the container: removing the tree denylist, which lets an explore of `/var/lib` proceed to a verdict as root, and removing the first-contact vet in `main.zig`, which matters because the denied-root leg's operation records nothing and therefore never reaches `restore` — the guard inside `restore` cannot answer for it.

**Where these numbers come from, and what is not committed.** The unit and acceptance figures are reproducible from this tree: `zig build test --summary all` reports 193/193, and the acceptance suite's 49 checks pass under `docker run -v <repo>:/work -e SIDEEYE_ROOT=/work <linux image> sh -c 'sh /work/spike/build-toys.sh && sh /work/spike/acceptance.sh'`. The mutation results are reproducible the same way, by making the named edit and re-running. **The 61-path corpus figure is not**: it came from an ad-hoc extraction of absolute `state` paths out of the tree, applied to a transcription of the predicate rather than to the shipped binary, and neither the extraction nor its output is committed. It is the reason `/opt` and `/srv` were dropped from the list and the reason the doc example was the only committed path denied, so it carries weight — and it was measured on a copy of the predicate, not on the thing that ships. Turning it into a committed check that walks the tree and calls the real binary is filed, not done. Review found this: the claim was written as if it were reproducible.

**One line came back out.** The re-vet asked `isSymlink` before the comparison, justified in a comment as keeping two failures distinguishable. Deleting it left every test green: the comparison already refuses a linked root by the only property that matters, that it resolves somewhere else. The case the extra call could have added — a dangling link at the root — cannot reach the function, because `main.zig` fails to resolve such a `--state` in the first place (measured: `SETUP ERROR --state could not be resolved`). The comment was doing the work the code was not, which is the shape worth deleting.

## 2026-08-25 — the entry recording the accidental close caused a second one

The entry below records an issue closed by a negated closing keyword in a commit
message. The PR that shipped that entry closed the same issue again, by the same
mechanism, because its commit message **quoted the offending clause**.

The quote wrapped. The keyword ended one line and the number began the next.
GitHub's parser treats a newline as whitespace and matched across it; the guard
written for this an hour earlier used a regex whose space class matches within a
line. So the check was line-oriented and the thing it checks is not.

The clause was removed from the PR body and that was verified. The commit body
was not re-checked with a pattern that can span lines. Which is the same defect
this repository wrote down yesterday, in the entry about a same-class scan
reaching one of three ways a checker fails: **flatten whitespace before searching
prose for a multi-word phrase.** It was applied to somebody else's scan and not
to this one.

Reopened a second time, with the mechanism recorded on the issue.

**The rule, now in three parts:**

- Never put a closing keyword beside an issue number unless closing is the intent.
- **Do not quote such a clause at all** — not to explain it, not in a commit
  message, not in a PR body. Describe its shape instead. Reproducing it is how
  it works.
- When checking for one, flatten whitespace first. A line-oriented grep cannot
  see a wrapped occurrence, and the wrap is invisible in a rendered view.

**What was NOT changed.** Earlier entries in this file contain the same
construction in ordinary prose (five of them, describing PRs that really did
close what they name). They are inert: this file is history, and its text is not
re-parsed by future merges. Rewriting them to satisfy a pattern would damage the
record to protect against a mechanism that cannot reach them.

## 2026-08-25 — the sentence saying an issue would stay open is what closed it

#312 merged and closed #297, which the PR body said in three places should stay
open. The commit message contains:

    This does not close #297: forget an eighth report

GitHub's closing-keyword parser matches `close #297` and does not read the
negation in front of it. One clause of prose overrode three explicit statements
of intent, plus a `Closes #296` that was deliberately the only closing line.

Reopened with the reason recorded on the issue. Nothing about the ticket
changed: #312 implements its option 3 (name the denominator), and the gap the
issue is named for — a report filed without editing the literal is invisible —
is untouched.

**Scanned the last 30 commits** for the same shape, with a positive control to
prove the pattern fires:

    git log -30 --format='%b' | grep -icE '(not|never|without)[^.]{0,40}(close[sd]?|fixe[sd]?|resolve[sd]?) +#[0-9]+'
    -> 1   (this one)

**What that scan cannot answer, said here rather than left implied**: it only
finds closing keywords preceded by a negation. An unintended `Closes #N` with no
negation looks exactly like an intended one, so no scan over commit text can
separate them — that distinction lives in whether the author meant it, which is
not in the data.

The practical rule this leaves: **do not write a closing keyword next to an
issue number unless the intent is to close it, even inside a negation.** Say
"#297 stays open" instead of "this does not close #297".

## 2026-08-25 — the veto's first measurement was clean because it only had one path to be clean about

`#293` asked whether FSEvents can veto a mutation the shim never reported.
H1 died in #291 because a capture cannot be rebuilt into the OpClass
sequence `compare()` wants, so H2 gets a weaker relation: **path set
containment**, every reported path being one the account already names.
Containment passes through coalescing and reordering by construction,
which is what killed H1.

**The planted mutation was verified rather than assumed.** A sensitivity
leg needs a mutation the shim provably misses, and "provably" is where it
would have gone wrong: a planted operation the shim happens to record
makes a silent capture unreadable in both directions. `clonefile(2)` is
absent from the 40 symbols `shim/src/macos.zig` interposes, but the table
is read, not trusted — the probe runs under the shim and the trace is
checked. It names `seen-by-shim.txt` and `clone-src.txt` and never names
`clone-dst.txt`. The control half matters as much: a trace missing
everything would prove the bypass for the wrong reason. That check came
from the session working on `#310`, which asked how the bypass was going
to be established; the plan had only said "a mutation that bypasses the
shim", with nothing saying who guaranteed it.

`clonefile` creating an unreported file in the state directory is a
finding about sideeye rather than about FSEvents. It is the macOS
instance of the class `#244` named on Linux.

**The first containment number was 5/5 and meant nothing.** It ran one
probe mode, `write`, and each run was 2 operations over **1 path**. Five
repetitions of one path are five observations of one path; the repetition
was not buying width. That became visible while writing the result and
looking for the subject of "containment held" — the sentence wanted a set
of operations and the measurement had a file.

Widened to 11 modes x 5 runs. Three transcripts, all from the committed
code and all committed beside it:

| run | held | `link` | other 10 modes |
|---|---|---|---|
| 1 | 49/55 | 5/5 | 1/50 |
| 2 | 47/55 | 5/5 | 3/50 |
| 3 | 49/55 | 5/5 | 1/50 |

Every outside path is the state directory, an ancestor of an account
path. `link` was outside on all 15 runs it had; the other ten modes on 5
of 150. Which modes is not readable — the three runs disagree, and so do
two earlier sets.

**The reading was rewritten four times, and the rewrites are the
evidence.** After the first widened run: "`link` is a systematic
counterexample, the rest are clean". After the second: "and `create` is
intermittent". After the third: neither, because `write` — the mode
whose thin 5/5 started all this — failed three times in five. Then the
pooled count moved twice more: three sets of 150 runs gave 6, then 23,
then 5. A low rate spread across modes is
exactly what produces a different mode each time five more samples
arrive; a property of one mode would keep selecting that mode. `link`
at 15/15 never moved, and that contrast is the whole reading.

Five runs per mode answers "does this reproduce", not "how often": a
1-in-5 behaviour is missed entirely by five runs about a third of the
time. No per-mode rate is claimed.

**Three `unrelated` entries were nearly recorded as a finding.** They
were the judge's own selftest fixture, printed once per run before any
measurement starts, and a transcript-wide grep for "unrelated" returns
them beside real ones. Telling them apart needed a reader who remembered
which was which, which is the kind of guard that works exactly until
somebody reads the file three days later. The fixture path is
`/selftest-only/stranger` now, so the prefix does the work. The measured
runs saw zero, which is what the neighbour control exists to make
readable.

**And the pooled figure is a count, not a rate.** A draft of this entry
called 23 of 150 about 15%, after an earlier draft called 6 of 150 about
4%, and reasoned that the first set had been a quiet stretch and the
larger number was the real one. A third set gave 5. Three sets of 150
runs on the same machine and the same code: 5, 6, 23. Two samples were
enough to notice the number moves and not enough to say which way, and
picking the newer one over the older was the same error as quoting
either as a percentage. `link` at 15/15 in every set is what survives;
the rest is "it happens, and how often is not measured".

**The two buckets name shapes, and an earlier comment named causes.** An
outside path is reported as an ancestor of an account path or as
unrelated to it. Both are facts about strings. The comment beside them
said ancestor means the relation is too tight and unrelated means a
neighbour wrote here, which does not follow: a real neighbour touching
the parent directory lands in the ancestor bucket and would be excused by
a label that had already decided the cause. Attributing an event to an
actor is what #291 measured FSEvents cannot do. The labels stayed; the
comment now says so, and the reading moved to RESULTS where it can be
argued with.

**The `unrelated` bucket had never been red.** Zero over 165 runs is what
a working classifier gives in a directory only the probe uses, and also
what a classifier that never reaches that branch gives; nothing in the
leg told them apart. A second actor now runs with the watcher live —
`/usr/bin/touch` on a path the account will never name — and it lands in
`unrelated` while the state directory lands in `ancestor`, in one
capture. Three outcomes are distinguished, including "the neighbour
produced no outside path at all", because a silent control reads exactly
like a passing one.

**The outside review found four more, and the largest was about where
the evidence lives.** A draft of this entry and of RESULTS reported three
transcripts and committed one. The 50/55 and 49/55 sat in prose with
nothing behind them, so the pooled figures could not be recomputed by a
reader, and this file repeating the same numbers is transcription rather
than a second source. The runs above replace them: three transcripts,
one code version, all committed. The other three:

- `L7a` ran `strings` twice — once for the control, once for the
  absence. A failed second read is a non-zero grep, indistinguishable
  from a real absence, and the leg would have called that a proven
  bypass. It reads once, checks that the read worked, and tests all
  three conditions against the saved output. The success line also
  claimed `clone-src.txt` had been checked when only the control had.
- A `planted` record without a `syscall` field raised `KeyError`, which
  exits 1 — and rc 1 is this survey's code for "the hypothesis failed",
  not for a broken apparatus. A malformed transcript could have ended
  `BROKEN checks: 0` with the veto recorded as blind.
- **The new verdicts' guards had never run.** Deleting `require_liveness`
  from either, or the `disowned` check from sensitivity, left all 33
  selftest cases green: every fixture carried a sentinel and none of the
  sensitivity fixtures disowned itself. The guards existed and were
  never exercised — the same shape as the `unrelated` bucket above, in
  two more places in the same judge. Four cases added, each shown red by
  removing its own guard.

The last one generalises the reviewer's point rather than just fixing
it: finding one branch that has never been red is a reason to count
every branch of that judge, not to fix the one that was named.

**An apparatus bug worth its own line.** The first version of the leg
looped on `i`, and `wait_ready()` uses `i` as its own counter and resets
it. The loop never terminated; 17234 lines came out before it was
stopped. That is the collision fixed in #308 four hours earlier, where
every block-local name took a prefix and the reason went into this file.
The class was known, written down, and reproduced in the next file.
Worth noting that the two instances differ in severity for reasons that
have nothing to do with the class: #308's `line` was harmless because
nothing after it read the variable, and this one was fatal because it was
a loop bound. `mkfifo: File exists` was printed on every iteration and
nobody read it — the signal existed and had no consumer, which is worse
than no signal, because the output looks like observability. It is fatal
now.

## 2026-08-25 — per-mode help, and a design that would have deleted the caller's report

Opened when the work started, per the contract above. Grows as decisions land.

**The two tickets.** `#296`: `sideeye --help` works since #273 but
`sideeye explore --help` exits 3 — help is answered before the mode word and
never reaches past it. `#297`: `spike/upstream-report-status.sh` cannot see a
report that was never added to its hand-written list, and its output does not
say whether "6" is all filings or all it knows about.

**What planning turned up before any code.**

The first design put help in the shared parse loop as a no-value flag. Review
called it Critical and was right: `--json` calls `removeFile(v)` while parsing
(`src/main.zig`), so `sideeye explore --state X --json existing.json --help`
would have deleted an existing report to answer a question about usage. The
comment beside that `removeFile` records the project already dodging this trap
once — "rejected before the removeFile below: a rejection that had already
deleted the caller's previous report would be a refusal with a side effect".
The first design was building the second one.

The shape that ships instead is an exact match on `argv == [sideeye, <mode>,
--help|-h]`, handled before the mode dispatch. It never enters the parse loop,
so it cannot reach `removeFile`; it fixes `replay` in the same place (the
positional check rejects a leading `-` before the loop is reached); it leaves
`--marker --help` alone because four elements do not match the shape; and it
needs no change to the arg matrix #295 added, because `--help` never becomes a
parse-loop literal.

**A claim retracted during planning.** The draft said a report was missing from
`REPORTS` — `alecthomas/devtodo#9`, which exists, is authored by this account,
and is not in the list. It is not missing. `spike/assisted/NOVELTY.md` records
it as filed and **withdrawn the same day** on the owner's judgement, and
`outcome-map.tsv` and `docs/target-classes.md` agree. The measurement was
right and the reading was wrong, and the step it produced would have added a
withdrawn report to a list of standing ones.

That is also what kills the ticket's option 1 (derive the list from the
tracker): a withdrawn report and an unlisted one have the same shape in the
tracker. What separates them is a judgement recorded in prose. Not "one more
failure mode" — the distinction is not in the data the derivation reads.

**The table of current behaviour was a reading, and it measured true.** Nine
invocations, built and run before any edit:

    --help / -h / help                 rc=0  usage banner
    explore --help                     rc=3  SETUP ERROR  an option is missing its value
    explore --help --state /tmp        rc=3  SETUP ERROR  unknown option
    preflight --help                   rc=3  SETUP ERROR  an option is missing its value
    replay --help                      rc=3  usage banner
    demo --help                        rc=3  SETUP ERROR  demo takes only --shim <lib>...
    mcp --help                         rc=3  sideeye mcp takes no arguments...

Four distinct behaviours across the modes. **The ticket's own transcript is
wrong**: it shows `sideeye explore --help` producing "unknown option", and the
message is `an option is missing its value` — the arity guard, because `--help`
is last and the loop treats every unrecognised flag as one that takes a value.
"unknown option" is what the four-element form produces. The failure the ticket
names is real; the transcript beside it is not what the binary prints.

**The check went red before the branch existed, and two of its own assertions were
wrong.** 15 failures across the four modes on the first run, which is the point of
writing it first. Then:

- The control for `--marker --help` expected "an option is missing its value". Wrong
  message: `--marker` swallows `--help`, the loop ends, and the run dies on the
  missing `--state`. Pinning that message would have tied this check to the ordering
  of unrelated guards. It compares `--marker --help` against `--marker ZZZ` instead —
  whatever `--marker` does with its value, it must do to both.
- That comparison then passed **vacuously**: both files were empty, because
  `setupError` writes to STDOUT in this program and the check captured only stderr.
  The "both sides non-empty" guard written beside it is what caught that, on the same
  day it was written. Fixed by capturing both streams.

The stderr assertion on the help paths is weak for the same reason and says so in
place: a failing help path also leaves stderr empty. The `cmp` against the canonical
help text is what actually catches a broken help path.

**Four mutations, each on a fresh copy, each red — and the attribution is the
interesting part.**

    1  delete the help branch          FAIL per-mode help: 14
    2  keep --help, drop -h            FAIL per-mode help: 7
    3  move help into the parse loop   FAIL per-mode help: 3
    4  freeze the denominator to 6     selftest rc=2, short leg caught it

Mutation 3 is the one worth keeping. Moving help into the loop makes the
behaviour look FIXED — all eight invocations still exit 0 with the right text —
and three assertions still go red: the source-shape one, and the two halves of
the `--marker --help` control, because a loop-resident help swallows the value
`--marker` was supposed to take. **The Critical design passes a behaviour-only
test.** That is why the source-shape assertion is in there, and it is now
measured rather than argued.

The first mutation run had to be discarded: `rm -rf` on the scratch copy was
refused by a local guard, so `cp -R` layered each mutation on the previous one.
The verdicts happened to be identical when re-run with the copies actually
cleared, but the first run could not have told the difference — a monotonically
falling count is exactly what stacking would produce too. Re-run with
`/usr/bin/trash` and an existence check that aborts rather than stacking.

**Review broke the assertion that was supposed to protect the design, and the
counterexample destroys a file.** The first version of the source-shape check
grepped for `eql(u8, argv[i], "--help")` and the comment beside it claimed that
moving help into the loop "in any form" would go red. It would not:
`eql(u8, "--help", argv[i])` means the same thing and has a different shape.

Measured rather than argued. A fifth mutation writes exactly that:

    grep hits:                     0        (invisible to the old assertion)
    explore --json X --help:       exit 0, sentinel DELETED
    acceptance:                    FAIL per-mode help: 3 problem(s)

So the evasion is real, it costs the caller their report, and the runtime probe
added after review is what catches it. The probe uses a --json path under a
parent that does not exist, so it cannot destroy anything itself whether or not
the regression is present; a non-zero exit is the whole assertion. The grep is
kept beside it as a cheap second opinion and now says in place that it knows one
spelling and is not load-bearing.

**Three more from the same review.** The `--marker` control compared output but
not exit status, so a regression printing the same refusal and then exiting 0
would have passed — both rc are compared now, and both must be non-zero. The
top-level help comment in `src/main.zig` still said `explore --help` reaches
"unknown option", which this change makes false and which was never the right
message anyway. The script's own comment attributed the list-completeness gap to
#271; it is #297, and the paragraph now carries the measured reason the
derivation cannot work.

**One review finding did not reproduce — and the defence written for it broke a
form that worked.** `self=$0` was said to break the new short leg under a PATH
invocation, because `sed "$self"` does no PATH search. Measured: a PATH
invocation gives $0 as an absolute path (the shell resolves before exec), and the
only slashless form is `sh script.sh` from the directory holding it, where sed
opens it anyway. So the reported failure is not reachable through documented
usage.

The guard added anyway resolved through `command -v` **first**, which turned that
working slashless form into a refusal whenever the script's own directory is not
on PATH — `cd spike; PATH=/usr/bin:/bin sh upstream-report-status.sh --selftest`
went from working to `could not resolve $0`. Round 2 caught it; reproduced before
believing it, and the comment beside the guard still asserted the PATH scenario
this entry had already retracted. Readability is checked first now and PATH is
only a fallback. Four invocation forms measured after the fix — slashless with
the directory off PATH, relative-with-slash, absolute, and PATH-from-elsewhere —
all rc=0.

The first attempt to reproduce the original failure also did not create the
condition it needed (the copy sat in the directory that was on PATH), which is
why it "passed" both before and after.

**Same-class scan for the broken assertion.** The class is "a check reads the
source and knows one spelling of the construct it looks for".

    grep -nE 'grep.*($ROOT/src|src/main\.zig)' spike/acceptance.sh   ->  3 hits

The scan itself had to be run twice. The first pattern carried a `[^|]*` between
`grep` and the path — added for no reason beyond caution — and that excluded any
line containing a pipe character, which is exactly the line under investigation
(`(argv|rest)`). **The scan for this class missed its own instance of it.**

The other two hits are `parser_literals()` and the `rest[i]` scan feeding
`acc_flags`, both from #295. They share the fragility and **fail in the opposite
direction**: a flag written with the operands swapped drops out of the candidate
set, stays on its synopsis line, and the "every advertised flag has a parser
branch" assertion goes red. Missing a spelling makes those checks loud, not
quiet. The one removed here was the only fail-open member. Left as they are.

**What this PR does not do**, stated here so the PR body is not the only place:
`#297`'s output will name the denominator it knows, and nothing more. Forget to
add an eighth report and the script will still say so honestly and exit 0. The
claim shrinks; the ability does not grow. `#297` stays open.

## 2026-08-25 — the same-class scan reached one of three ways a checker fails, and said it had covered them all

The scan published in #303 and again in #307 opens with "scanned across every
committed cohort checker" and reports 18 hits in 6 files. Both numbers are right
about what they measured. What they measured is `fail "…"` calls in shell.

Counting how a checker can fail turns up three idioms:

| how | reached by the scan |
|---|---|
| `fail "…"` in shell | yes |
| a bare `echo …; exit` | no — the four hg revisions, one message between them |
| a message inside an embedded Python block | no — five checkers embed Python, three messages: two in black, one in papis |

**The classification does not move,** and that is measured rather than assumed:
the four unreached messages were read. hg's states a premise about its own setup
script; black's two assert a parse and program identity; papis's asserts a
document's shape. None is a premise an external system can falsify, so the two
falsified premises are still the himalaya staging guard and nothing else.

**The first draft of that table had the same defect it describes.** It said two
Python messages, both in black. papis fails through `raise SystemExit(…)`, which
`print(` does not match, and the pattern reaching for it also matched shell
`printf` — so the counts were wrong in both directions at once. Re-derived before
publishing rather than after, which is the only reason this paragraph is right.

**What moves is the claim about reach**, and that is worth correcting because
the paragraph publishes its own command — it is an entry point for reuse, and a
reader who takes the scanner and the sentence together inherits a blind spot
that the sentence denies having.

**Measuring before writing would not have caught this.** The numbers were
measured, and they were correct. The scanner was built around the first idiom
found and that idiom was taken for the set, so the range was fixed before the
first measurement ran. The cheap check is to **derive the denominator twice and
look for disagreement**: `grep -c 'fail "'` beside `grep -cE '\bexit [1-9]'` per
file puts black at `fail=1, exit=2`, an outlier that says the scanner is not
finished yet. The parallel case on the other side of this repo the same day was
an ADR status scan whose `^Status:` pattern reached 4 of 21 files, the rest
using a bold-bullet form; there the two-way count would have shown 4 against 21.


## 2026-08-25 — the synopsis check's third direction was not blocked, and the first draft of it compared a world the help text chose

`#295` filed the missing direction — a flag a mode accepts whose synopsis
line omits it — rather than faking it, and named two blockers. grep
cannot tell `if (mode == .preflight) setupError(...)` from acceptance.
Driving it by execution needs to know which flags take a value, since a
dummy argument after a no-value flag comes back as "unknown option" and
reads as a refusal; that list would be the hand-synced second copy `#65`
is about.

**The second blocker was not one.** Put the flag last and a value-taking
one reaches the parse loop's own `i + 1 >= argv.len` guard while a
no-value one is handled before that guard and fails elsewhere. Measured
across all thirteen: eleven take a value, two do not, which is the split
the source shows. No list, so nothing to go stale.

Acceptance is then a differential — a base invocation that parses and
then fails on the first thing after parsing, with an accepted flag
leaving that failure untouched. Two things had to be measured before
that worked.

*The unit is the line, not the mode.* `--config` is mutually exclusive
with the define-surface flags, which is why `explore` has two synopsis
lines. A per-mode union would claim `--config` and `--state` are usable
together. `#294` split that line for a display reason, and the split
turns out to be the semantic one.

*The residue is a value-shape table, not an arity table.* Nine of the
eleven value-taking flags accept a path that cannot exist.
`--expect-status` validates its value first, so a path there reads as a
refusal of the flag; `--json` needs a writable path for the same reason.
Three entries, and the direction they fail in is the useful part: an
acceptance copy that goes stale makes the check quieter, while a
value-shape entry that goes stale makes it report a drift that is not
there. There is an assertion that every parser flag is accepted by at
least one line, which is what turns a stale entry into a failure rather
than a silent widening.

**The first draft was green under the mutation that should have killed
it.** Candidate flags were taken from the synopsis. Removing `--marker`
from the explore line dropped the candidates from 13 to 12, so the flag
was never probed and the two sides agreed about a smaller world:
`cli_fails=0`. Not a tautology — a tautology dies under mutation — but a
check whose population is chosen by the thing under test. The candidates
come from `parser_literals` now, the same reader checks 4 and 5 use.

That failure was discussed with the session working on `#303` about an
hour before it was written, under the name "one side determines the
population". Naming the shape did not prevent writing it.

Five mutations, each red, each naming the right thing, and the block
green before and after every one:

- the explore line loses `--marker` → names `--marker`
- the parser makes `preflight` refuse `--oracle`, which its line
  advertises → names `--oracle`. **This is the direction that decides
  the check.** A one-way "every accepted flag is advertised" stays green
  here, because the refused flag leaves the accepted set too
- the `demo` line loses `--shim` → names it. `demo` is parsed by
  `runDemo` before the mode enum and drifts on its own; probing it with
  the flag last never starts the demo
- `help` stops refusing extras → names all thirteen flags it now accepts
- the value-shape table is broken → three failures, including the
  accepted-nowhere assertion

The outside review found three more places where the check was weaker
than its own description, and one of them is the same shape a third
time.

*A flag in the base was never acceptance-tested.* Flags in the base
invocation were marked accepted because the base parsed. Make the parser
refuse `--operation` in preflight and the base's own failure becomes
that refusal — measured, and the result is not the pass the review
predicted but something almost as bad: the check goes red naming the
wrong thing, reporting that preflight "accepts" nine flags including
`--allow-unverified` and `--config`, because every probe now compares
equal to the refusal. The expected failure of each base is pinned now,
so that mutation reports the base rather than the synopsis.

*The candidates came from one parser.* `runDemo` compares against
`rest[i]`, not `argv[i]`, so a demo-only flag contributes nothing to the
candidate set and the claim that this check covers demo held only
because `--shim` happens to appear in the shared loop as well. Adding a
demo-only `--quiet` takes the candidates from 13 to 14 and is caught.

*One key could match two lines.* Splitting the replay line in two makes
the grep return both, and the advertised set becomes their union: each
line could be missing half its flags and the union would still match.
Exactly one line per key now.

The same shape was also found one level up, in the same check, while
writing this. The four bases are written in the check, so a synopsis
line **added** to the usage text would not be tested at all: the check
would be choosing which lines exist rather than the text. Counted from
the text now and compared against what ran — adding a ninth line goes
red naming the count, and the sixth mutation is that.

Scan volume is in the output: 8 of 8 synopsis lines against 13 parser
flags, 99 probes. That number counts acceptance probes only — the 47
arity determinations and the 4 base runs are on top of it, for about 150
invocations in total. A loop that silently covered nothing reports the
same zero failures as one that covered everything.

## 2026-08-25 — the guard's reason is corrected in both copies, and the scan said the cheap change was not cheap

#306 offered three ways to handle a guard whose failure message states a premise
upstream falsified: leave it, correct the reason text, or relax the assertion.
The owner picked the middle one. This is that, and what implementing it turned
up is worth more than the edit.

**What changed.** In both `spike/cohort4/himalaya/ops/check.sh` and
`spike/cohort4/himalaya-r2/ops/check.sh` — byte-identical files, which is why
this had to happen twice — the staging guard used to fail with:

    new/ or tmp/ is not empty: this operation stages nothing, so N entry/entries
    there is damage or a shape the define did not declare

and now names the entries it found, scopes the premise to the version the define
was measured against, and says which single state under a fixed build is the fix
working rather than damage. **The assertion is untouched.**

**The first version of that wording repeated the mistake it was fixing, in the
other direction.** It said that against a build carrying the fix "this fires on
correct behaviour rather than on damage" — unconditionally. The guard covers four
directories and only one of them, the target's tmp, is where 0.3.1 legitimately
stages. An entry in `new/`, in the store's own `tmp/`, or in `Archive/new/` is
damage under either version, and so is a second entry anywhere; the new message
would have called all of them correct. Review caught it. Replacing an
over-general premise with an over-general exemption is the same failure with the
sign flipped, and it took the same shape as everything else this entry is about:
a sentence that is true of the case in front of you, written as though it were
true of the category.

**What the scan found before the edit, which contradicted the issue.** The issue
called this "the cheapest thing that stops the misreading". Grepping for who
quotes the string turned up seven files, and two of them are mechanical:

- `spike/cohort4/himalaya/checker-drills.sh` and its r2 twin assert the substring
  `new/ or tmp/ is not empty` — the first clause only. Keeping that clause is
  what makes the drills survive, and it was a constraint on the new wording
  rather than a happy accident.
- `spike/cohort4/himalaya-r2/upstream-fix/check-relaxed.diff` **stops applying**,
  because the lines it removes are the lines being edited. That is a reproduction
  path verified to work yesterday and broken by today's change if nobody looks.

The rest are records of runs — transcripts, drill output, this file — and they
keep the old wording because they record what happened.

**The diff was regenerated and the instrument was not, and that distinction is
checked rather than claimed.** The relaxed checker was reconstructed by applying
the *previous* diff to the *previous* `check.sh`; the new diff is taken against
the corrected `check.sh`; applying it produces a file byte-identical to that
reconstruction. The patch base moved and the measurement's instrument did not.

**No verdict moves, and that is measured too.** The define was re-run against the
stock target through the corrected checker and diffed against the committed r2
transcript: every judgement-carrying field is identical — verdict, world counts,
both crash-point classes and their paths, leg D's byte counts, the oracle's
operation and syscall-line counts, atomicity, metadata, the checker line. The
only differences are the per-run work paths, which is the property `RESULTS.md`
already names. Against the fixed build the run still FAILs 2 of 4, with a message
that no longer asserts what the fix removed. Both drill suites: 0 failures.

**The mini-seal is unaffected, and that was read rather than assumed.**
`spike/assisted/verify-assisted.sh` D2 compares `$def_commit:$p` against
`$art_commit:$p` — two fixed historical commits. Editing the file today cannot
change either blob. Checking that before editing was the difference between a
safe change and finding out from CI. Run afterwards as well:
`ALL ORDER CHECKS PASSED`.

**One more, small and worth writing down.** Checking that the discarded first
wording had not survived anywhere, `grep -rn` returned 0 for this file too — and
this file is where it deliberately survives, quoted above. The phrase is wrapped
across a line break here, and grep is line-based. A count of zero from a
line-oriented search over hard-wrapped prose does not distinguish "absent" from
"wrapped". Re-measured by flattening whitespace first: exactly one occurrence,
in this file, which is the intended answer arrived at for the right reason.


## 2026-08-25 — the himalaya case refuses against the fixed build: a case pins an operation sequence, and this fix changed it

Yesterday's entry closed with a question left to the owner: does "kept as a
replayed regression case" mean the committed transcript, or a CI leg in the
timewarrior sense. That was framed as turning on wording rather than on
evidence, because the fixed build had never been measured against the case.
It has now.

**The measurement.** himalaya built against `io-maildir` 0.3.1 — the release
carrying `pimalaya/io-maildir@b4e9080` — installed into the cohort-4 image
with nothing else changed. Six runs, in
`spike/cohort4/himalaya-r2/upstream-fix/`:

1. replay, stock target, frozen checker → FAIL, leg D, "the case reproduced"
2. replay, **fixed** target, frozen checker → **`UNKNOWN case_no_longer_applies`**,
   exit 2: "the recording now counts 3 state-changing operation(s); the case
   was recorded over 2"
3. explore, fixed target, frozen checker → FAIL 2 of 4, through the **guard**
4. explore, fixed target, guard relaxed → **PASS 4/4**
5. explore, stock target, guard relaxed → FAIL 1 of 3, leg D

Run 1 is the positive control and its diff against the committed transcript is
empty once the minted filename and the per-run work path are normalised. Run 5
is the negative control and exists because a relaxation written by whoever
wants the PASS can only confirm the breakage that person imagined; it shows the
relaxed checker still catches the original defect.

**Finding 1, and it is decidable rather than arguable.** The third operation is
the rename the fix introduces. A case names a crash point inside a recorded
sequence, so the sequence it addresses stopped existing. The refusal is the
promised behaviour, not a defect — `docs/contract-freeze.md` §4 says so in
those words. What makes it decidable is that this repository already wrote the
bar down: `spike/dogfood-timew-replay.sh` leg C says "a `case_no_longer_applies`
here is honest but does NOT meet the v0.4 acceptance". Legs A and B hold for
himalaya; leg C is not reachable.

The general shape is worth more than the instance, but only the structural half
of it is measured. timewarrior's patch left the operation sequence intact and
its case survived its own fix; himalaya's adds an operation and its case did
not. **A case pins a crash point inside a recorded operation sequence, so any
fix that changes that sequence orphans the case** — that needs no survey. The
version I first wrote here went further, saying the fixes most likely to be made
are the ones most likely to orphan their case, and review was right that n is
two and nothing here samples repairs across targets. It stands as a hypothesis
worth testing, not as a finding. Whether leg C needs a different shape for such
fixes, or whether an unreachable leg C disqualifies a finding, is filed rather
than decided here. The criterion is not re-scored in a measurement record.

**Finding 2, which was not being looked for.** The frozen checker's guard
asserts every staging directory is empty, and prints its reason in the failure:
"this operation stages nothing". That was true of 0.3.0, where `messages copy`
was the one arm that filled the destination in place — the cohort's own
RESULTS.md says exactly that. The fix falsified it. So run 3 FAILs against a
fixed target while asserting the premise the fix removed, and reads at a glance
like the bug is still there and worse (2 of 4 rather than 1 of 3). It is not:
the property asks for the old set or the old set plus a **complete** copy, and a
stray file in the target's staging directory is not a message. Run 4 measures
that — PASS 4/4, with the two non-empty worlds holding a 0-byte and a 307-byte
staged file, the target folder empty in both. The frozen checker is not changed
here; the relaxation is committed as a diff so it cannot be read as a second
checker.

Scanning the class across every committed cohort checker — 18 files, 14 hits in
6 — turned up one thing the record would otherwise have missed: **the falsified
guard is committed twice.** `spike/cohort4/himalaya/ops/check.sh` carries it
identically, because r2's checker is r1's byte for byte. r1 never reached a
verdict, so nothing was ever judged through it, but a premise stated twice is a
premise that has to be corrected twice. papis's library-shape guard has the same
construction with nothing upstream to falsify it, and the remaining hits assert
the property or a parse rather than an implementation premise.

**What went wrong, in order.**

- The guard problem was spotted from the upstream diff before any build, and
  then predicted for the wrong path. The prediction was that replay would
  produce a misleading FAIL. Replay never reaches the checker — the engine
  refuses first. The concern was real and the path was wrong, which is the
  same shape as measuring something other than what changed.
- `grep -c AwaitRename` against the vendored 0.3.1 source returned 0. Stopping
  there would have concluded the fix is not in the release. The state variants
  were renamed between the fix commit and the release (`AwaitCopy`/`AwaitRename`
  became `Copy`/`Rename`); the semantics are identical. Identifiers taken from
  a diff carry an unstated assumption that names do not move. The image build
  now asserts on the semantics instead.
- The first `cargo update -p io-maildir --precise 0.3.1` re-resolved the whole
  lock and moved `windows-sys` in five places as a side effect. Irrelevant to a
  Linux build, but it makes the delta larger than the fix. Discarded; the two
  lines were edited by hand and `cargo vendor --locked` accepted the result,
  which is the machine-checked statement that the dependency closure is
  unchanged.
- The first `Cargo.lock.diff` came out **0 bytes**, because `artifacts/` is
  gitignored and absent from a fresh worktree, so the left-hand side did not
  exist. A zero-byte diff reads as "no delta". Re-taken against the shared
  checkout with a non-empty assertion in front of it.

**What review found, and what fixing it turned up.** Eight findings, five of
them P1, and none of them cosmetic. Four are worth carrying:

- **There was no functional control, and the record did not know it.** Neither
  the frozen checker nor the relaxed instrument pins the copy's *presence*: an
  empty target folder is one of the two states the property allows. A build that
  returned 0 while copying nothing would have produced PASS 4/4 and this record
  would have called it a working fix. The falsification gate does not close that
  gap either — it goes red through source conservation, which fires whether or
  not a copy would ever be made. `functional-control.sh` closes it and was shown
  red by replacing `himalaya` with a script that exits 0 and does nothing.
- **The check I wrote to make the positive control reproducible was tautological.**
  `norm "$original" | diff -u - /dev/stdin <<EOF …` redirects the same stdin the
  pipe is writing to, so both operands read the here-document and diff compared
  it with itself. It returned ok against a transcript whose verdict line had been
  rewritten. **Found by running the red proof, not by reading the code** — and it
  is the exact class this entry spends its length on, written fresh, by me, today.
- **The fixed binary is not reproducible, so its hash was never a pin.** Two
  builds from byte-identical inputs produced two different binaries. The pin
  moved to the input side — a tree digest over everything except `Cargo.lock`,
  matching the frozen tree, plus the lock's own sha256 — and every transcript
  here was re-measured against the second build so the committed `Dockerfile` and
  the committed evidence describe the same image.
- **Writing the reproduction instructions was itself a check.** Both committed
  diffs had been produced with the file headers stripped, so the `patch -p0` the
  instructions call for could not have applied them. Regenerated with labels and
  verified by applying each to a copy and comparing bytes.

Two more, recorded without ceremony: the same-class regex missed `should not`
and therefore missed leg C's conservation premise in both himalaya checkers
(widened, 14 hits became 18); and the entry's headline generalisation was an
n-of-2 claim about which fixes are common, which nothing here measures.

**And the miss that stings.** Yesterday's entry named the class "a page states
an external system's status as a fact, and the external system moved", and fixed
`PRD.md` §17. Review found the same stale sentence three paragraphs further down
in the same file — "what remains is an author's judgement, a fix, and a
regression case that runs" — and again in `DESIGN.md` §17. Two of those three
were closed by upstream on 2026-08-23. I scanned for the class and scoped the
scan to checker failure messages; the class lives in the prose too. Scanning the
prose afterwards turned up one more page to qualify (`docs/target-classes.md`)
and one that is still accurate: `DESIGN.md` says timewarrior's report is not yet
confirmed by its maintainers, and `GothenburgBitFactory/timewarrior#778` is
still open with no comments, last touched 2026-08-12.

**On the classification this directory lands in**, since the entry below it
inverted the default the same day. `spike/cohort4/himalaya-r2/upstream-fix/`
carries three executable scripts and falls to documentation without anyone
naming it, which is the exact shape ADR 0021 says the check cannot catch: a
live directory omitted from both `.gitattributes` and `exempt_dirs` is green
because both sides agree on the wrong answer. Green was therefore not treated
as the decision. `git check-attr` says these scripts sit where
`spike/cohort4/himalaya-r2/ops/check.sh` sits — the cohort's own frozen define —
and not where `spike/acceptance.sh` sits, which is the maintained harness. They
are the apparatus of a frozen measurement, so documentation is the right side
and no exemption is asked for.

## 2026-08-25 — the classification rule was missed on every closure it faced, so the closure moment was removed

`#292` reported that `spike/macos-oracle/` never got its
`linguist-documentation` line and called it the second miss after cohort
4. Measuring the tree found a third it had not noticed:
`spike/scout-model-comparison/` is unregistered too. Three closures,
three misses. That is not a memory problem.

Predictions were fixed in the plan before any of this was written, and
they are quoted here with what happened.

*A content predicate can replace the rule.* Wrong, and the way it failed
is the useful part. Three candidates over all 20 directories under
`spike/`: "has a committed transcript" disagreed with the current
registration on 6, "is not referenced by live code" on 6, their
conjunction on 10. The second fails because four registered records
*are* read by live code, for four unrelated reasons —
`check-sealed-campaigns.sh` checks one, `rehearse-campaign.sh` drives
another, `acceptance.sh` consumes a third, `spike-fsusage.yml` re-runs a
fourth. There is no predicate separating "a record something still
reads" from "an apparatus still maintained", and those four reasons are
why one is unlikely to be found.

*The first design.* Every directory must appear in either the
registration list or an explicit exemption list, and CI fails on one
that appears in neither. The outside review killed it in a sentence: a
directory created as live and later closed never changes either list, so
the check is green forever. It verified that somebody classified a
directory **when it was created**, which is not the predicate `#292` is
about. Written into ADR 0021 rather than quietly dropped, because the
draft was an instance of exactly the failure the ticket describes.

*What shipped.* The default is inverted — `spike/**` is documentation,
`spike/*` and `spike/toys/**` are code — so a record is documentation
from the day its directory exists and there is no closing moment to
notice. The trade is stated in the ADR: the one misclassification this
direction can produce is a new **live directory** left as documentation,
which understates Shell rather than counting a frozen transcript as
code, and which happens while somebody is working in that directory.

*Exactly 35 files change meaning and 27 change only their label.*
Predicted from the file counts, then measured: `macos-oracle` (9) and
`scout-model-comparison` (26) move to documentation; the 27 that were
`unspecified` and correct — 22 top-level scripts and `spike/toys/` —
become an explicit `unset`. Measured over the 1239 files tracked before
this change: 1212 documentation, 27 code, 0 unspecified. Adding the
checker itself makes it 1240 / 1212 / 28 / 0, and that it landed as code
without a line of its own is the inversion working.

Those two states are not the same thing, which the first draft of this
entry and of the ADR both said they were. `unspecified` leaves
linguist's own documentation heuristics in charge; `unset` overrides
them to false. Of the 27, the one those heuristics do claim is
`spike/README.md`, which moves from documentation to
explicitly-not-documentation — and still leaves the bar unchanged, for a
different reason: Markdown's type is `prose` and the bar counts
`programming` and `markup`. The `.patch` is unchanged for that same
reason (Diff is `data`), not because the heuristics claimed it; the
second draft said they did, and they do not. Both steps are read from
linguist's documented behaviour rather than measured here. The first
draft said "linguist reads them identically", which is a claim about a
tool nobody in this repository has run.

The third number is still the point. Before the inversion 62 files came
back `unspecified`, 35 of them the bug and 27 of them correct. A
decision and an omission produced the same attribute value, which is why
three misses in a row were invisible. `unspecified` is a failure now,
and that is only assertable because there are none left.

*The check reads the attribute, not the text.* Measured rather than
argued. A minimal text-comparison checker — the shape the first draft
implied — was run beside the real one against a mutation appending
`spike/macos-oracle/** -linguist-documentation` to the end of the file.
The text checker returns 0: the general registration line is still
there, spelled correctly. The attribute checker returns 1 on nine files.
A positive control confirms the text checker is not simply broken —
delete the `spike/**` line outright and it goes red.

*The apparatus lied first, in the usual direction.* The fold from
`check-attr -z` was written as `awk 'BEGIN { RS = "\0" }'`. BSD awk,
which is what macOS ships, does not accept a NUL record separator and
read the whole 3717-record stream as one record, so the checker saw
nothing. GNU awk on the Linux runner would have accepted it. That is a
check which is green in CI and structurally blind on the machine you are
standing at, and the only reason it did not ship that way is the
empty-set guard borrowed from `check-sealed-campaigns.sh` — "finding no
file at all is a failure, not a pass". The fold is `tr | paste` now,
with a column-alignment assert on the attribute name and a scanned-count
assert against `git ls-files`.

Five mutations, each red, each with its count reconciling against a
separately measured number, all against the final tree: the override
above (9 files plus the summary, 10), a revert to the old direction (63
unspecified, the stale exemption that revert also produces, and the
summary, 65), dropping the `spike/*` line (23 top-level files plus the
summary, 24), a typo in the live-directory pattern (5 toys files plus
the summary, 6), and a stale literal in `exempt_dirs` (2). Unmutated is
green before and after.

**One of those counts was wrong, and refusing it found a real bug.** The
stale-literal mutation reported 8 failures where 2 were expected, and
the extra 6 said every file in `spike/toys/` was a record that came back
`unset` — the exemption had stopped matching. The membership test was
`for e in $exempt_dirs` inside the file loop, and that loop runs under
`IFS=newline`, so a space-separated list is one word. With the single
entry the repository has today that is indistinguishable from working.
It breaks the first time a **second** live directory is added, which is
the only occasion this list is ever edited: the check would have gone
red on the toys files, pointing at the wrong thing entirely. Membership
is a `case` match on a space-padded string now, which does not consult
IFS, and the loop reads through `while IFS= read -r` off a here-document
so there is no shell-wide IFS to save and restore at all — the form the
other eleven IFS sites in this repository already use. A here-document
rather than a pipe, because a pipe would put the counters in a subshell
and report zero. Verified with two entries in both orders, and with two
entries that both exist; that last one is the positive case, and it is
green. Three shells (`sh`, `dash`, `bash`) give identical output.

**The guard added for the review's second point was wrong in both
directions on its first try.** Tab and newline in a path break the fold,
so a guard was put in front of it that rejected any path `git ls-files`
quotes. Measuring it: a Japanese filename is quoted under the default
`core.quotePath`, so the guard rejected a perfectly legal path — and a
repository with `core.quotePath=false` set quotes no non-ASCII at all,
so the guard would have been reading the user's config to decide what to
check. Forcing `-c core.quotePath=false` in the command separates the
two: that setting governs non-ASCII and never control characters, so a
tab stays quoted under both and a non-ASCII path is bare under the
forced one. Verified three ways — non-ASCII alone is green, a tab is
red, and a tab is still red with `core.quotePath=false` set in the
repository config.

## 2026-08-24 — upstream fixed himalaya#738 within hours, and the pages that score criterion 1 did not know

The cohort-4 record says the report is "open with no response as of
2026-08-23" and scores two of §17's six conditions open on that basis:
*the author judges it a real bug* and *fixed*. Both were closed by the
maintainer the same day the sentence was written. `pimalaya/himalaya#738`
is CLOSED as completed, with one comment — "Bug fixed on `master`."

Finding the fix took longer than it should have, and the wrong turn is
worth recording. The issue timeline lists three referenced commits;
asking `pimalaya/himalaya` about each returns 422, and the obvious
reading — "no fix commit upstream" — is wrong twice over. Those three are
this repository's own commits, which GitHub cross-references onto the
issue, and himalaya's master carries only two commits in the window,
neither a copy fix. The fix is not in himalaya at all: the maildir
implementation lives in `io-maildir`, a separate crate, and the fix is
`pimalaya/io-maildir@b4e9080`, "fix: clean tmp after copy", carrying
`Refs: .../himalaya/issues/738`. himalaya's own history shows it only as
`d507387c`, "build: bump deps", where `io-maildir` moves 0.3.0 -> 0.3.1
in `Cargo.lock`. A repository is not the boundary of a project's code,
and 422 from one repository is not absence.

The fix is the staging the report named as missing: `copy` now lands in
the target `tmp/` and renames into place, "as `MaildirEntryStore` writes
them", so an interrupted copy leaves at worst a stray file in `tmp/`
rather than a truncated message enumerated under its final name.
Upstream's own CHANGELOG describes the failure in the same terms the
report used — an entry every Maildir reader lists as an ordinary message,
empty and unparsable, that copying again does not replace — and the
commit adds a test.

So criterion 1's remaining gap is one condition, not three, and it is a
question of wording: *kept as a replayed regression case*. The exhibit
replays today, against the version that has the bug. Nothing has replayed
it against a build carrying the fix, and nothing in CI runs either leg —
which is exactly the gap this page called "closed as hygiene" for
timewarrior once `timew-regression` existed. A case that reproduces a bug
is not yet a case that detects its return.

**This change does not re-score the criterion.** Re-scoring inside a
documentation change is the move this repository refuses, and it refused
it once already when criterion 6's measured README moved underneath it.
What this change does is remove the false premises: the pages no longer
say a fixed bug is unfixed. The adjudication — whether "replayed
regression case" means the committed transcript or a CI leg — is the
owner's, and it is now the only thing between this finding and the
criterion. Note also that the pinned v2.1.0 does not carry the fix, so
any such leg means building against `io-maildir` 0.3.1, not against a
newer himalaya tag.

**Then acceptance check 11 went red on this very change, which is the
part worth keeping.** The check extracts every backticked token
containing a slash from the evidence-first pages and requires it to exist
in the repository — its own comment warns that a backticked ratio like
"3/7" is read as a path, filed as #85. Two of the tokens added here were
neither paths nor ratios: an upstream commit reference, owner/repo@sha,
and a directory named in prose. Both were extracted, neither exists here,
and the page went red. The fix is to drop the backticks; the reference
reads the same without them.

The PR body claimed this change "adds nothing that needs verifying beyond
what is quoted above" before CI said otherwise. It did: a documentation
change has a machine-checked surface, and prose that names an external
repository in the local path syntax lands on it. Corrected in the body
rather than quietly.

Reproducing the failure locally took one wrong turn first. Running the
check's own loop under zsh reported one missing entry per page, including
pages this change never touched — `for r in $refs` does not word-split in
zsh, so the whole newline-joined blob arrived as a single item and every
page looked broken in the same way. Under `sh`, which is what CI runs, the
count is 2 before the fix and 0 after, and restoring one backtick puts it
back to 1. A gate reproduced in the wrong shell measures the shell.

## 2026-08-24 — the sorted order `find` wants was never a property of the type

`Snapshot.find` is a linear scan, called from inside loops in `classify` and
both judges, so lookup is quadratic in the entry count for every world
explored. The entries are already sorted by `rel`, so a binary search needs
no new structure — that is what #262 lists first among the steps that touch
no frozen surface.

The sort is real, but it belongs to one producer rather than to the type.
`takeSnapshot` sorts; `testSnapshot`, the helper the unit tests build
snapshots with, does not. Ten of its forty-four call sites are not in
lexicographic order. Swapping the search without fixing that would not have
failed those tests — it would have returned wrong answers that happened to
satisfy them, which is the worse outcome of the two.

So the order is: both producers sort, a validator runs once at each producer
boundary, and only then does the search change. The validator is not in
`find`. Putting it there was the first draft, and review killed it: `find`
is called n times per judge, so an O(n) check inside it restores the
quadratic cost this issue exists to remove. The accompanying belief that a
debug-only assert would not matter was also wrong — `std.debug.assert` is
generated in Debug **and ReleaseSafe**, the release artifacts are
ReleaseSafe, and ordinary CI runs Debug. It is optimised out under
ReleaseFast and ReleaseSmall, neither of which this project ships or tests
in, so the check would have been free in exactly the configurations nobody
runs.

Sorting `testSnapshot` can move an answer, and the path is worth recording
because it is not obvious: `classify` walks `pre.entries` in order and
appends to `plan.files`, and both judges return on the *first* violation
they find in that list. Order therefore decides which violation is
reported. It does not break the ten fixtures — each one arranges exactly one
violation at a time — but "does not break today" is not "does not depend on
it", and a future fixture with two violations would be decided by the sort.

Scope: #262 stays open. Parallel exploration, differential restore and
partial crash-point selection are the rest of it, and each needs a decision
this PR is not making. The batch it arrived in (#263 timeout, #265 snapshot
cap) is also not in here — review pointed out that with #265 landing as an
opt-in flag, the only bound that would actually apply by default was the
lookup cost, which does not match a thesis about the engine refusing at its
limits. Three tickets, three PRs.
## 2026-08-24 — the laptop leg: two output shapes the runner never produced, and a judge that called them findings

The fs_usage survey (#298) concluded on one machine, a GitHub runner, and
said so. Running the same apparatus on the owner's laptop (15.3.1, SIP
enabled, not a VM) reproduced every capability finding and turned up two
things about the format instead.

The first pass reported BROKEN 1 and DEAD 3, one more DEAD than the runner.
Both were the judge.

`Google Chrome He.64625821`: a process name with spaces in it. The grammar
read that field as `\S+`, so those lines went to `unparsed` and the census
refused the capture. The census was right and the grammar was wrong. The
runner had no process with a space in its name, so nothing there exercised
it.

`.../missing-d>>>>>>>>>>>>>>>>`: macOS 15.x pads a truncated pathname with
`>` to a fixed width. The failed `open` was in the capture, with its errno,
and exact-path matching missed it, so P4 read DEAD on this machine only. The
`>` are the truncation marker; what remains is a real prefix. `same_path`
accepts a stump against the path it was cut from now, and rejects a stump of
a different path.

Neither is a version capability difference, which is the part worth keeping.
Both are properties the format always had and 26.5.2 never happened to
produce. Had the adapter been designed from the CI measurement alone, both
would have arrived on the first laptop run, as a parser that reports nothing
and a verdict that says a visible line is missing.

After the fix, re-judging both machines' committed captures: the laptop's
seven P4 modes pass, its census is clean, and the runner's numbers are
unchanged in every leg. The second run on the laptop is BROKEN 0, DEAD 2,
the same two walls, with the display cap at 156 against 144 and 153 there.

## 2026-08-24 — #286 route F1 opens: does fs_usage have the oracle's shape, measured before anything is built on it

Entry opened at the start of the work, per the contract. Today's zero-base
review killed three unprivileged routes three different ways (FSEvents by
measurement, calibration by tense, the state-closure check by information
content), which leaves two families: secure an observer, or build a recorder
that needs none. This spike is the first family: fs_usage, measured at the
four points the fsusage plan names, before any adapter or grant-once design
is written on top of it.

One reframing changes who runs the privileged leg. The verified PASS matters
most as a CI gate, and GitHub's macOS runners are documented to allow
passwordless sudo, so the leg that needed a human yesterday may need none.
That claim is itself unmeasured here, so it is the first thing the apparatus
checks, as a workflow that does nothing but try.

### Predictions, written before any run

Confidence is a guess, not a measurement.

1. On the GitHub macOS runner, `sudo -n true` exits 0 and `sudo fs_usage`
   produces a non-empty capture (confidence 90%).
2. Write syscalls do NOT appear as their own lines under `-f filesys`: the
   #181 capture shows `open`, `WrData[A]`, `rename`, `unlink`, `mkdir` for a
   toy that called write() three times, and no `write` line. If that holds,
   P2 kills the strict drop-in on its own (confidence 70%).
3. A failed unlink/rename/mkdir appears with the errno in brackets and the
   attempted path; a failed open is less certain to carry its path
   (confidence 55%).
4. fs_usage accepts a pid argument and restricts output to it (70%); a
   forked child is not followed under the parent's pid (60%); two same-named
   processes under a name filter are merged and separable only by thread id,
   which nothing in the output maps to a pid (70%).
5. `-w` lifts the 28-byte pathname limit to full paths (85%).
6. At least one of P1-P4 fails hard enough that fs_usage is not a drop-in
   oracle without lowering the contract's ambition (60%). The prior is
   honest: prediction 2 alone would do it.

The ground truth for the comparison legs is the shim's own binary trace
(SIDEEYE1 header, little-endian records), read directly by the judge, not
the probe's self-account. The probe knows what it asked for; the shim's
record is the account the oracle would actually be compared against.

### What round 1 said (run 32687071111, macOS 26.5.2 on the runner, SIP disabled there)

The premise held: `sudo -n` exits 0, `fs_usage` runs, and two unfiltered
seconds are 27,994 lines. Then all 25 legs ran and ten came back BROKEN,
every one of them the apparatus, and the platform findings sat underneath.

Apparatus, two holes. fs_usage prints `write F=3 B=0x7` with no pathname,
so the judge scoped every write as off-state noise; the `open F=3 <path>`
that preceded it on the same thread is the address, and resolving through
the descriptor is what the strace oracle already does with its own
annotations. And the shim recorded only opens, because the harness passed
the state dir spelled `/tmp/...` while the shim resolves descriptors with
`F_GETPATH`, which answers `/private/tmp/...`; without the alt spelling the
engine sets, every descriptor-addressed op fell out of scope. That is not a
shim bug (the engine passes both spellings, `contract.zig` says why) but it
is a sharp edge for any adapter: the observer's spelling, the shim's
spelling and the engine's spelling are three things, not one. fs_usage adds
a fourth: a path the target named through the /tmp symlink comes back as
`private/tmp/...` with no leading slash, while the same path named
canonically prints as `/private/tmp/...` intact (round 2 measured both).

Platform, what stood after the holes were accounted for:

- P4: all seven failed attempts left a line, each with the errno in
  brackets and the attempted path: `open [ 2]`, `mkdir [ 17]`, and so on.
  The counterexample that killed FSEvents does not touch fs_usage.
- P1: the pid filter kept one of two same-named processes and leaked
  nothing (5 lines kept, 0 leaked). Under a name filter covering both, the
  trailing number on every state-dir line was one of the two tids the probes
  had reported through `pthread_threadid_np` (15741 and 15743, nothing
  else). Prediction 4 said that mapping would not exist; it does. A forked
  child is not followed under the parent's pid filter, as predicted.
- P3: a rename line carries the old path only; the destination never
  appears. Wide mode keeps the LAST ~153 characters of a pathname and cuts
  the front, so a state dir deeper than that cannot be scoped by its own
  path. Narrow mode prints full paths too (58 characters intact, so the man
  page's 28-byte figure is not what this build does) but carries no thread
  id at all, so nothing in narrow mode attributes a line. A directory name holding a space and
  Japanese survived wide mode byte for byte.
- The shim's own resolution shows through: every op is bracketed by
  `fstat64 F=n` and `fcntl F=n <GETPATH>` on the target's thread, and the
  shim's trace writes appear as `write F=900`. An adapter has to know those
  are the observer's shadow, not the target's work.

### What rounds 2 and 3 said (runs 32687503436 and 32687827616)

Round 2 fixed the two harness holes and came back BROKEN 0, DEAD 11. Nine
of the eleven were the judge again: "1 recorded write arrived as 3 lines",
every time by exactly two. The two were the sentinels. Their write lines
carry no pathname in the raw text, and the exclusion that keeps the
apparatus's own mutations out of the count only looked at the raw text.
Beneath that sat a normaliser that stripped `/private` only after a leading
slash, so round 1's `private/tmp/...` and round 2's `/private/tmp/...`
never met. Round 3 carries both fixes; re-judged over round 2's own
captures first, all nine P2 modes were 1:1 with the shim's count.

One more near-miss, recorded because the shape is the one this workspace
keeps meeting. Looking for fsync, a grep for the word returned 18 hits, all
of them the leg's own name inside a pathname; a listing of the probe's
thread cut at fourteen lines stopped just before the fsync line; and a
`uniq -c | head -8` of CALL names dropped the one-count entry. Three
truncated reads agreed that fsync was invisible. The verdict, judged by
CALL name over the whole thread, found it at once: `fsync F=3`, one of one,
beside the `WrData[ST1]` it caused. The number that nearly went into
RESULTS was manufactured by the reads, not by the platform.

Scoring the predictions written before any run:

1. Runner sudo works, capture non-empty. **Right.**
2. Write syscalls do not appear as their own lines. **Wrong.** They do,
   as `write F=n B=k` with no pathname, and once placed through the
   descriptor they are 1:1 with the shim's records in all nine modes:
   three consecutive small writes are three lines, two interleaved fds are
   four, a 4 MiB write is one, a zero-byte write is one, pwrite and writev
   print under their own names, stdio's flush is one. The #181 capture that seeded the
   prediction had been read through a path filter, which is exactly what
   hides them.
3. Failed attempts carry errno and path; failed open less certain.
   **Right, and the uncertain half held too**: seven of seven, `open [ 2]`
   with its path included.
4. pid filter honoured (right); forked child not followed (right); tids
   unmappable to a process (**wrong**: the trailing number IS the value
   `pthread_threadid_np` reports, and two same-named processes on one file
   separated cleanly by it).
5. `-w` lifts the 28-byte limit. **Half right.** Narrow mode already prints
   58-character paths intact; what wide mode changes is a cap of about 144
   displayed characters, cut from the left, which narrow mode was not
   pushed against.
6. At least one point fails hard enough to deny the strict drop-in.
   **Right, but not where expected.** P4 and P1 and P2 all hold. What
   fails is P3: a rename line names only its old path, and a state
   directory deeper than the display cap cannot be scoped by its own path.

What this leaves. Three of the four points are clean on this machine.
The fourth has two measured walls, neither of them the kind that killed
FSEvents: the rename destination is a per-class gap (ADR 0006 counts
either endpoint), and the depth cap is a constraint sideeye can enforce on
the work directory it hands the target. Whether those are cheap enough to
build an adapter behind is the next decision, and it is the owner's.

### What round 4 said (run 32689458393), after the diff's first-look review

The review of round 3 reproduced four verdicts that returned green on an
adversarial capture: p4 on a path hit with the errno stripped, p2-order on a
capture with the write syscall line deleted (its WrData carried it),
p1-partition with one process missing, and a census of an empty capture
reporting all zeroes. Three more were found by reading: containment was a
substring test where the engine's rule is component-boundary, the trace's
contract version was read and discarded, and the child-follow leg had no
positive control. Each is a selftest case now that failed before the fix.

Round 4 with the tightened judge: BROKEN 0, DEAD the same 2 (rename's
destination, the depth cap), census on 27 of 28 captures (the deep-path leg
is the one where state scoping fails by construction) with `other_state`
and `unparsed` at 0 in every one, and the child write visible under a name
filter (4 lines) while invisible under the parent's pid filter (0), so the
"not followed" is the filter's and not the child's. The depth cap printed
153 this run against 144 in round 3; the number moves, the left-cut does
not.

Round 5 (run 32690217527) carried the confirmation review's three fixes
(exact call names in p4, sabotage at every indentation, the census said as
27 of 28) and returned the same shape: BROKEN 0, DEAD 2, census 27 with
both counts at 0, depth 153, always-accept sabotage 15. It is the transcript
committed beside the code that produced it.

Two of the document's own claims were also wrong against the captures:
pwrite and writev print under their own names (a `uniq -c | head -8` had
dropped them, the same truncation that nearly hid fsync), and the
attribution finding said more than a single-threaded probe reporting its
own thread id can say. Both narrowed to what was measured.

## 2026-08-24 — three places where a failed measurement ends up shaped like a success

#264, #271 and #273 arrived as unrelated tickets and turned out to be one
class: a measurement that did not happen, reported in the form of one that
did. The direct child's `waitpid` can exhaust its retries and leave `status`
at the zero it was initialised with, so `decodeStatus` reads a killed world
as a clean exit and the run is reported `kill_did_not_land` — a confident
wrong reason, in a design where every explored world is expected to die by
signal. `upstream-report-status.sh` increments `broken` inside a pipeline
subshell, so nothing outside can read it and the script ends `exit 0` even
when every row is BROKEN. And `--help` is not a word the CLI knows, while
the usage text has drifted from the parser it is supposed to describe.

Two of the three fixes are not the ones the tickets proposed, and the
reasons are worth recording because both were wrong in the same direction —
the proposed fix would have left the defect in place while looking done.

For #271 the plan initially kept `exit 0` when rows are BROKEN, reasoning
that the script's own header says it reports rather than judges. That was a
misreading. The header assigns exit 2 to "could not measure", and a row that
BROKE is precisely a report that could not be read; the same file already
exits 2 when `gh` is missing. Printing "N of M could not be read" changes
nothing for the machine reading the exit code. The check that went with the
first design was worse than useless: it compared emitted row count against
the list length, and six BROKEN rows still emit six lines, so a fully
failed run would have passed it. The predicate is `broken > 0`, not a count.

For #273 the ticket proposes pinning that every flag the parser reads
appears in the usage text. Measured, the parser accepts 13 unique flags and
the usage text names the same 13 — the pin is satisfied the day it is
written. What has actually drifted is per-mode: `explore` omits six flags it
accepts, `replay` omits one, `mcp` has no synopsis line at all, and
`preflight` is already correct because the parser explicitly refuses the
five flags its line leaves out. A pin that fills in `preflight` would
advertise invocations the program rejects.

The intended replacement was the full mode-by-flag acceptance matrix. That
is **not** what shipped, and the reversal belongs here rather than only in
the CHANGELOG. Driving the matrix by execution needs to know which flags
take a value — a dummy argument after a no-value flag comes back as
"unknown option", which is indistinguishable from a refusal — and that list
would be the same hand-synced second copy the check exists to avoid. What
shipped is the help paths by execution, plus two directions that need no
such list: every mode the parser dispatches on has a synopsis line, and
every flag the synopsis advertises has a parser branch. The reverse
direction per mode is filed.

Review moved the extractions after that, twice. They were `[a-z]+` and
`[a-z-]+`, which cover today's seven modes and thirteen flags and would
silently miss a `show-report` or an `mcp2` — a narrow pattern turns "every
mode" into a claim the check cannot support. The first pass widened the two
patterns that read `src/main.zig` and left a third: the *line selection* on
the synopsis side, still `^  sideeye [a-z]+ `, which meant a `show-report`
line's flags were never scanned at all. A synthesised
`sideeye show-report --not-a-parser-flag` passed both checks. Three places
had to move, not two — worth recording because the first fix was reported as
complete and the claim in this file had to be walked back with it.

The same round caught the banner assertion reading `--help`'s output instead
of the bare invocation's, so `usage()` could have disappeared from the bare
branch with the check still green: the defect the check was written to
prevent, inside the check.

One more from verifying the fix rather than the code. The `unknown_reason`
addition was declared safe because `check-report-schema.py` reported no
drift — except it had not checked. Run without report arguments the script
exits at its verdict-coverage assertion, forty lines before the drift
comparison, so deleting `child_wait_failed` from the doc produced the same
output as leaving it in. Reaching the comparison needs four reports covering
all four verdicts: three are committed fixtures, and SETUP_ERROR generates
on macOS from `--setup /bin/false`. With those it prints "schema page, 4
reports (all four verdicts), and the contract enum agree" — a success message
that states what it covered — and the doc-minus-one-entry control fails with
`enum-only: ['child_wait_failed']`. A bare exit code could not tell the two
runs apart.

Also recorded because the comment is load-bearing and wrong: `posix.zig`
says the retry bound exists "because there is no errno binding here to tell
a retryable interruption from a permanent failure". There is. `EINTR` is
declared forty lines above it and `std.c._errno()` is already used in this
same file. The retry can distinguish EINTR from a permanent failure instead
of spending nine attempts on both.

Review moved two more things. The first draft returned the wait failure with
`try`, which would have skipped the process-group drain that follows and
left the direct child unreaped — a new defect introduced by the fix, caught
before it was written. And the seam was going to be a comptime default
argument, which Zig has no syntax for; it is a wrapper function instead.

The larger correction came from review of the finished code: every wait
failure was being turned into a SETUP ERROR. Honest about the failure, wrong
about when it happened. Exit 3 means the define did not run — DESIGN's
exit-code table says "before exploration began", and `ci-quickstart.md`
tells CI authors that exit 3 means the define itself did not run — so a wait
that fails while worlds are being explored would have published
`verdict: "SETUP_ERROR"` for something that happened well after the define
started. A silent change to the serialized shape, in the same PR whose whole
subject is failures that misreport themselves. The fix carries the phase:
`--setup` and the demo's compiler probe stay SETUP ERROR, everything from
the recording run onward is UNKNOWN with a new `child_wait_failed` reason.
The distinction was already in the tree — `recording_run_failed` and
`baseline_run_failed` are UNKNOWN for exactly this reason — and reading the
existing classification first would have shown it. Adding to the
`unknown_reason` set is a change to a frozen-at-1.0 surface, allowed
pre-1.0; the doc-versus-enum gate in `check-report-schema.py` is what keeps
the two lists from drifting, and it was run.

The same-class scan for #271 was rebuilt three times and was wrong twice.
`| while read` on one line found 8 sites, `while[[:space:]]+read` found 10,
and both missed `while IFS= read -r`. Scanning for `read -r` finds 22 across
13 files. The conclusion did not move — one counter defect, in the script the
ticket names — but two of the three phrasings would have justified the same
sentence with a smaller denominator. Worth noting that the correct shape is
already in the tree twice: `blind-hunt2/verify-seals.sh` runs its loop with
`done < "$voidfile"` so an in-loop `exit 2` survives, and `unknown-rate/
sweep.sh` carries a comment calling pipes-hide-failures a measured class in
this workspace.
## 2026-08-24 — #286 route B opens: what FSEvents can verify, and the predictions made before measuring

Entry opened at the start of the work, per the contract. The owner picked
route B over route C today and scoped it to v1.0 (#286, comment of
2026-08-24). The reason recorded there: every route in that issue buys a
claim weaker than `oracle_verified`, and B is the only one whose failure
modes are disjoint from the shim's, because a witness interposer and the
shim ride the same injection.

The plan's first draft was wrong in a way worth writing down. It treated
"can FSEvents feed `oracle.compare`" as the whole question, so a negative
answer would have been recorded as "route B is dead". The issue text asks
something weaker: whether the mutations the shim reported are consistent
with what the kernel says changed. Those are two hypotheses, and the
first failing does not settle the second.

- H1: a full OpClass sequence, good enough to drop into `oracle.compare`.
- H2: an independent veto, catching a change the shim failed to report.

This spike hunts counterexamples to H1 and builds the apparatus H2 would
need. It does not judge H2.

The asymmetry is the reason the work is cheap. One counterexample kills
H1. No counterexample proves nothing, because `FSEvents.h` describes its
flags as a hint, and a handful of agreeing runs is not a guarantee about
future runs. False PASS is this project's worst failure, so the survival
side of RESULTS is capped at "worth further study", never "it works".

Two readings from the source shaped the measurement list. `shim/src/ops.zig`
records each attempt *before* it runs, and says why: a failed attempt has
to count on both sides or the two accounts desync. FSEvents reports
changes to the filesystem, so an attempt that changed nothing has no
event to report. That is the cheapest counterexample available and it is
measured first. Separately, `src/oracle.zig` drops write-incapable opens
from the comparison entirely, so the read-only open this plan originally
listed as a measurement target was never relevant.

The #181 toy is not reused. It performs `open, write, rename, open,
write, unlink, mkdir, open, write`: nine operations across five classes,
with no `fsync`, no `truncate`, no `rmdir`, no `link`, no `symlink` and
no failing call. It was built to test token presence and first-appearance
order, not class mapping. A mode-driven `probe.c` replaces it.

### Predictions, written before any measurement

Recorded so the misses are legible afterwards. Confidence is a guess, not
a measurement.

1. A failed attempt produces no event at all, in every configuration
   tried (confidence 90%). This alone kills H1.
2. `fsync` produces no event (confidence 85%).
3. A truncate to the file's existing size produces no event, or one
   indistinguishable from a write (confidence 70%).
4. Even at latency 0 with `NoDefer`, a create immediately followed by a
   write arrives as one entry with both bits set (confidence 65%).
5. The probe and a neighbour performing the same operation on the same
   path are indistinguishable in the output (confidence 90%).
6. The watcher soundness control passes: a single file created after
   READY yields at least one event for that path (confidence 95%). If
   this one fails, nothing else in the run means anything.

Prediction 4 is the one most likely to be wrong in an interesting
direction, because the header's `NoDefer` description is about when a
group is delivered rather than about whether same-path events within a
group are merged.

### What the measurement said

H1 is dead, and the cheapest leg did it. Seven modes issue a call that fails
and changes nothing; in each one the sentinel's event arrived and the
operation's own path produced none. Delivery worked and there was nothing to
deliver. The shim records those attempts, so `compare()` diverges there.
`RESULTS.md` carries the detail and two corroborating findings.

Scoring the predictions written above, before any of this ran:

1. A failed attempt produces no event. **Right**, 7 modes out of 7.
2. `fsync` produces no event. **Not decidable as stated.** No entry was
   attributable to it in 32 runs, so the transcript cannot say whether it
   produced one. The prediction assumed the answer would be visible.
3. A same-size truncate produces no event, or one indistinguishable from a
   write. **Wrong on the first half.** It produced an event carrying
   `ItemInodeMetaMod` on top of `ItemModified`. The second half stands
   unjudged; a create over an existing file carried the same extra flag.
4. Create then write arrive as one entry even at latency 0 with `NoDefer`.
   **Right in effect, wrong as written.** The L2 mode does not create: the
   setup creates the file before the watcher starts and the run opens the
   existing file `O_WRONLY` and writes. What collapsed was `open`+`write`
   +`fsync`, not create-then-write. The prediction described an experiment
   that is not the one that ran, which is its own small lesson about writing
   predictions against a harness rather than against the code.
5. The probe and a neighbour on the same path are indistinguishable.
   **Right**, after two harness corrections.
6. The soundness control passes. **Right.**

And one finding no prediction covered: `link` reports on the new name only.
The source path produced no event, while `src/contract.zig` treats `link` as
one operation. `rename` likewise arrived as two entries for one call, so the
entry count diverges from the operation count in both directions.

That one was invisible until the judge was rewritten. The first version scored
mapping as "any of this operation's paths was seen", which counted `link` as
fully observed. An external review of the diff called the per-operation claim
unsupportable; fixing the claim is what surfaced the finding.

Five things went wrong in the apparatus. All five were caught, and the pattern
across them is the point.

The attribution leg was built wrong twice. First each side got its own parent
directory, so the absolute paths differed and the judge said "distinguishable"
for a reason with nothing to do with who acted. That is precisely the failure
the plan review had named, reintroduced through the parent directory rather
than the file name. Then, after the sentinel was added, clearing only `target`
between runs left the first run's sentinel in place, so the second run's
create became a truncate and picked up `ItemInodeMetaMod`. Both versions
produced a confident wrong verdict.

The first sweep reported 0 entries for `latency=1.0`, five times out of five,
with a fixed 0.4s settle. That was the wait, not the platform: at 2.5s the
same configuration delivered one entry in all five runs. A negative result
from the harness reads exactly like a negative result from the subject, and
this is the failure the sentinel now exists to make impossible.

`SETTLE_OVERRIDE=$st capture ...` does not scope to the call. On this `/bin/sh`
the assignment survives the function, so L3 onwards silently ran with the last
L2 settle while the transcript stated the default. Measured with a three-line
script rather than assumed from the standard.

The always-reject control spliced from `v_mapping` to `j_mapping` and deleted
the four functions in between, so the sabotaged judge died with a NameError
and reported zero failures. Zero from a crash and zero from an ineffective
control are the same string. The control now replaces one function body and
the driver requires the sabotaged run to have completed, not merely to have
exited.

Counting `mapping: DEAD` across the whole transcript gives more than the
measured count, because the judge's own selftest fixtures demonstrate DEAD
verdicts and `v_coalescing` prints from inside the selftest too. Both the mode
census and the entry distribution had to be counted inside section boundaries.
Harvesting a gate's own red output as a finding is a known shape here and it
presented itself twice in one afternoon.

The coalescing distribution is not stable between sweeps: 29/1, 30/0, 28/3,
26/5 and finally the committed 25/5, over the same 30 configurations. None of
those is the property. The write-up says so rather than quoting whichever
sweep is on disk.

Beyond H1, two findings bear on H2 without settling it. The output cannot
attribute: `MarkSelf` and `IgnoreSelf` separate exactly one process, the
watcher itself, from an undifferentiated everyone-else, and `src/oracle.zig`
needs `child_touched` to mean "some other process". And the flag word
describes the path rather than the delivery window: in one measured run, a
file created 3 seconds before the watcher started still contributed
`ItemCreated` to the event for a later write.

Route C keeps its measured foundation from #181 and is the one route in #286
that is both measured and still standing.

## 2026-08-23 — the README still described a one-exhibit report

v0.13.0 gave the FAIL report a second exhibit (#231, ADR 0020): when the
earliest failing world trips only the built-in comparison, the earliest
world that falsified the declared checker is carried alongside it, with
its own case file. The CHANGELOG says so. The README — which is the
entry point, and the thing the onboarding clock hands its driver as the
only documentation — still described the single-exhibit shape: "brings
back the earliest failing crash point, saved as a replayable case", and
"a FAIL saves its counterexample to `<work>/cases/NNNNNN.json`",
singular. Both are now qualified, and `--fresh-state` — a shipped
replay flag that appeared in `usage()` and nowhere in the README —
joins the flag list.

This is the release checklist's own lesson recurring. Step 3.5 asks for
a README pass at every bump, and v0.13.0's pass looked at
version-relative strings; a report gaining a field is not one of those.
The rule the checklist states — hold it as "what changed that means the
README should be reopened", not as "what to fix" — would have caught it:
the report shape changed.

**Review caught an overclaim in the fix itself.** The first draft said
the second exhibit appears whenever the earliest world is built-in-only.
It does not: `first_checker` is set only when some world actually
falsifies the checker (`src/main.zig:1415`), so a run with no checker,
or a checker green in every world, has no second exhibit at all. The
sentence now requires a world that failed the checker, in both places
that mention it.

What the change is checked against, since prose can claim anything:
acceptance already pins the shape — `000001.json` for the earliest and
`000002.json` for the checker world, the text section
`checker red crash point 4 of 4 (built-in atomicity, and the checker)`,
and the second case replaying on its own. Nothing in the repository
reads the README as a test fixture, so there was no anchor to move.

## 2026-08-23 — the empty message travels, and one reader refuses it

`external-recovery.txt` closed with three things written down as not
measured, and the himalaya report's severity ceiling rests on them
(`#272`). The first is the one the freeze calls the strongest form:
whether an external syncer managing the maildir would carry the empty
message outward to a server. Measured today, and it does.

**The apparatus, and why it is two images.** The damage is produced by
`sideeye-cohort4:latest` untouched — the stock reproduction's shape, one
`strace` injection on `copy_file_range`, no shim, no engine, no seccomp,
no interposer — writing into a bind mount. The syncer and the readers run
in a separate `debian:trixie-slim` image that never contains the target.
The reason is not tidiness: the pinned himalaya is a glibc-dynamic
self-build, and installing a mail stack on top of that image would pull
dependencies able to replace the shared libraries the measured binary
resolves against. The target runs in the pinned image unmodified — the
generation step checks `/etc/ld.so.preload` is absent and prints
`LD_PRELOAD` the way the stock reproduction does — and the tools live
somewhere else.

**leg S, stage 1: mbsync carries it.** isync 1.5.1, Maildir on both
sides, `Sync All`, `Create Both`. The near side is the damaged Archive
folder holding two entries produced by real operations — the 0-byte one
from the killed copy, and a 307-byte one from letting the same copy run
to completion. mbsync loads the box as **two messages**, not one, and the
sync reports `Far: +2 *0 #0 -0`. Both arrive. The 307-byte message lands
as 328 bytes; the empty one lands as **21 bytes whose entire content is
mbsync's own `X-TUID` bookkeeping header** — the value is minted per run,
so the transcript holds it and this entry does not. Synced alone from a
clean near side, so the far side's count is about that entry and nothing
else, the empty one still produces exactly one far-side message.

So the external recovery path does not merely fail to restore the folder;
it propagates the damage in the direction the report had said the entry
never travels. That sentence in `#738` was about the entry never being
sent **during the copy**, which is still true and was measured with a
positive control. What was not measured, and is now, is what happens
afterwards when something else syncs the folder.

**leg R, and it cuts the other way: notmuch refuses the file.**
`notmuch new` (0.39) over a copy of the damaged Archive itself — not the
far side; the readers are asked about the store himalaya left behind —
prints `Note: Ignoring non-mail file:` naming the empty entry, and adds
one message to its database of three files. That is a detection path the
record did not have, and it narrows the report's "why it is easy to miss"
section: the claim there is scoped to the one reader tried, python's,
which does enumerate the entry as ordinary and still does. What the
refusal is *not* is emptiness-specific: a planted control in the same run,
malformed but not empty, draws the same `Ignoring non-mail file`. So
notmuch distinguishes parseable from unparseable, and this entry falls on
the unparseable side — which is a detection path without being a
diagnosis. Recording both directions rather than the convenient one.

**leg S, stage 2: a real server keeps it.** Stage 2 was asked only
because stage 1 answered yes — if the syncer had declined to carry the
entry, no server would have been needed to know that. dovecot 2.4.1 on
loopback, the folder pushed over IMAP, and the far side read back with an
independent IMAP client rather than by looking in the server's backing
directory: `SELECT INBOX` reports **2 messages**, one of them
`RFC822.SIZE=22` with an empty subject.

That identification rests on subject and size, so the leg then removes it:
the empty entry alone is pushed into a mailbox of its own (`Far: +1`), the
server reports **one** message there with `RFC822.SIZE 22`, and a clean
second store pulling that mailbox receives **one file of 21 bytes**
(`Near: +1`). The chain is measured end to end with nothing inferred — a
crash inside a local copy produces a message that a real server keeps and
another device downloads. The first attempt at that isolation pushed
nothing and the server answered `NONEXISTENT`: pointing the store's Inbox
at the isolated maildir while matching it with `Patterns "ISO"` makes
mbsync match nothing and create nothing. The store needs an Inbox of its
own and the isolated folder as a subfolder.

**leg T, and it goes the other way: the tool can finish the cleanup.**
`external-recovery.txt` measured the delete relocating the entry into
Trash and left "whether emptying the trash removes it" open in the same
sentence. It does: a second `message delete` against the Trash copy
answers `Successfully deleted 1 message(s) from the trash`, and the folder
is empty afterwards. The route is the same command twice, on an account
whose trash mailbox the user configures and creates first. That narrows
what the report may say about the user being stuck. The scan for a
purge-shaped name covers the three blocks it prints — top level, the
shared `mailbox` API, the maildir-specific API — and not the whole
surface: the IMAP-specific API does carry an `expunge`, irrelevant to a
maildir account and named in the transcript anyway, because the first
draft of that sentence said "no name in the surface" and review caught it.

**leg H, narrowed until it was checkable.** Regexing clap's derive
expansion would have produced a set that agrees with the help output
while both missed a cfg-gated construction, and an extractor returning
nothing agrees with everything — the review of the plan said so and was
right. What is checkable without rebuilding: the pinned source, digest
verified against `freeze-build.txt`, declares no `hide`,
`hide_long_help` or `external_subcommand` across 314 `.rs` files, with
the same expression shown matching a planted attribute. R1's enumeration
is not undercut by a hidden command. Everything else about clap's
faithfulness stays unmeasured and is written down as such.

**Three instrument notes, all the documented kinds.** `mbsync --dry-run`
cannot be used for this: against a Maildir near store it aborts on
`maildir_find_new_msgs: Assertion 'DFlags & FAKEDUMBSTORE' failed`, so
stage 1 is a real sync into a scratch far side rather than a dry run. The
first time I ran it I read `rc=$?` through a `head` pipe and printed
`dry-run rc=0` for a run that had aborted — the exact trap this
repository has recorded nine times; the rc is taken from the command now.
And the guard that mattered most **failed on its first real run, for the
right reason**: the plan required the syncer's own output to name the
damaged file, and mbsync names no individual file at any verbosity tried.
The combined run identified the two arrivals by size, which is an
inference — precisely the "a mis-mapped empty file plus a correctly
mapped healthy one would pass" hole the plan's review had named. Rather
than soften the sentence, the leg now syncs each entry **alone** from a
clean near side, so the far side's count is about one entry and nothing
else. The empty one, by itself, produces one far-side message.

**The review round: six P1s, and four of them were guards that could pass
without measuring.** That is the failure class this repository names most
often, and it was in the very harness written to avoid it.

- `trash.sh` always exited 0 and the driver asserted only on that, so a
  failed delete, a skipped second delete or a non-empty Trash would have
  produced a green cleanup measurement. The markers now come from each
  command's own rc and the folder's own counts.
- The reader guard searched the transcript for the damaged filename — which
  the leg prints in its own preamble before notmuch runs. It would have
  passed with notmuch flagging nothing. Replaced by four markers emitted
  from measured outcomes.
- S2 called any empty-subject message the damaged one and any two-message
  mailbox proof of the control, an identification S1 had earned and S2 had
  not. It now pushes the entry alone and pulls it back into a clean store.
  A server that fails to start is also no longer a soft outcome: the run
  goes red, because the record's sentence about servers is written from
  this transcript.
- The help audit compared the source tree's own `.digest` sidecar with the
  pin instead of hashing the tree, so a modified tree carrying its old
  sidecar would have passed. It now recomputes with `fetch-artifacts.sh`'s
  own expression. And a non-zero count of hiding attributes only printed a
  note; it fails the run now.

Two more, both real: an unchecked `mktemp` would have made every path a
root-level one (`/c4`, `/gen.txt`) — the reviewer watched the selftest
try to create `/present.txt` in its own sandbox — and four sentences in
the prose were outside the transcript, including a quoted `X-TUID` value
from an earlier run. That value is minted per run, so the fix is not to
update it but to stop quoting it: the transcript holds it and the prose
describes it.
## 2026-08-23 — posix.zig said the shim cannot use std at all; the shim uses std

Found by a peer session quoting the comment as a primary source for an
outward-facing draft, where the owner caught it disagreeing with the
implementation. `src/posix.zig`'s header said the shim "cannot use a
standard library at all inside somebody else's process". Measured, with
test blocks separated from runtime code: the shim's runtime paths use
`std.mem` (span, eql, sliceTo, startsWith, endsWith), `std.fmt`
(bufPrint, bufPrintZ), `std.math.maxInt`, `std.c` (Stat, fstat, _errno)
and `std.os.linux` (statx, errno). The peer's census also listed
`std.c.fopen`/`fclose`; those are test-only, which is why the
runtime/test split was worth running before rewording.

What the shim actually forbids was already written correctly one
directory over — `shim/src/common.zig`: no heap, no standard-library
I/O, no locks, no assumptions about what the target has initialised.
posix.zig's paraphrase was stronger than the accurate rule its own
neighbour states. The reword says the rule, names common.zig as its
home, and says plainly that the shim still uses std's allocation-free
slices.

Same-class scan: one site. And the scan itself needed its control — the
first pattern matched nothing because the phrase breaks across two
comment lines, and it took the known-hit control going red to notice
the scan was blind ("cannot use a" ends line 9, "standard library"
opens line 10). The "no std" pattern's hits are all "no stdin",
unrelated.

## 2026-08-23 — #181: the macOS no-oracle claim gets its measurement

The claim decides what a verdict means on half the supported platforms,
lives in four claim sites plus CI and two docs, names one tool, and ADR
0001 has said "to be measured" since 2026-08-10. The 08-10 entry's
objection — a sudo-only oracle is not a CI tool — is an argument about
the product default, not about whether an observer exists, and it was
written without running anything as root.

The survey splits on the privilege line. The unprivileged half ran first
(`spike/macos-oracle/survey.txt`): every candidate refuses without root,
each refusal captured verbatim — including the distinction the issue
called out, that unprivileged `dtrace`'s hard stop is PRIVILEGES while
SIP only limits "some features". OpenBSM is dismissed there without a
sudo leg: auditd(8) on this machine says the subsystem is deprecated
since 11.0, **disabled since 14.0**, and will be removed. The ktrace
invocation for the privileged half is designed from this machine's man
page (filter class `C3`, `-c command`), not from memory, because
unprivileged ktrace refuses before printing usage.

**Predictions, written before the privileged half runs**, so the run can
contradict them:

- `sudo dtruss` on the self-built, ad-hoc-signed toy: genuinely unknown —
  this is the promised measurement. If it traces, four claim sites
  overstate ("SIP refuses dtruss" is then true only of unprivileged
  invocations); if it refuses even as root, the claim survives with the
  privilege nuance corrected.
- `fs_usage` as root: expect visibility with pathnames (kdebug substrate);
  open questions are path truncation in non-tty output and event drops.
- `ktrace -f C3`: same substrate as fs_usage; expect the same visibility
  or a usage error that is itself the measurement.
- `eslogger`: expect either JSON events or a TCC refusal naming Full Disk
  Access; either answers whether ES is reachable without our own
  entitlement.
- A first-party ES client stays out of reach for a survey (the
  entitlement is Apple-granted); eslogger is its measurable proxy.

What the answer changes either way: the four claim sites say "macOS has
no usable oracle" where the measured statement so far is "no unprivileged
oracle, and the privileged candidates were never asked".

**Round 1 (2026-08-23T08:31Z) answered two legs decisively and caught my
harness lying on a third.**

The decisive pair. L2: even as root, DTrace's syscall provider matches
no probes — "probe description syscall:::entry does not match any
probes. System Integrity Protection is on". So sudo does not rescue
DTrace; the 08-10 claim survives at root, though its stated reason
("requires additional privileges") was the unprivileged symptom, not the
cause. L3: **fs_usage is oracle-shaped.** Full paths, operation names
(open / WrData / rename / unlink / mkdir), attribution to `toy.<pid>`,
timestamps, order intact — all three markers in first-appearance order,
nine event lines, zero contamination, no truncation at these path
lengths. The kdebug substrate saw everything this survey's
six-operation toy asked of the oracle role.

The lie. L1 reported dtruss "ok - all 3 tokens present", and every one
of its marker lines began with `op ` — the toy's OWN stdout. dtruss runs
the child itself, the child's output landed in the capture, and the
check judged the target's self-account as the observer's testimony. A
confident false pass on the exact machine where L2 proves the provider
is gone. L4 (ktrace) has the same contamination, and its verdict line
shows only 6 marker lines = the toy's own, which suggests raw kdebug
events carry no resolved path strings — but round 1 cannot prove that,
because the capture was cleaned up and only marker lines were excerpted.
L5 (eslogger) failed with a 1-line capture whose content the transcript
never showed, for the same excerpting reason.

Fixes, each the shape of a lesson already paid for elsewhere: runner
legs now route the toy through a wrapper so captures hold only what the
observer emitted; check-capture rejects a capture whose every marker
line is the toy's own words (seen red on a synthetic copy of round 1's
dtruss capture; the ground-truth control passes `--allow-self-account`
explicitly); verdicts print the capture head verbatim so a refusal
survives into the transcript after the raw file is cleaned up.

**Predictions for round 2, before it runs:** dtruss becomes a measured
refusal (capture = DTrace's own error lines, check FAIL "saw nothing",
toy account showing toy-rc=0 separately); ktrace's clean capture shows
**0** observer lines carrying a marker path, because raw kdebug does not
resolve paths — fs_usage is the front-end that does; eslogger's one line
becomes readable and is expected to name Full Disk Access.

**Round 2 (08:36Z): one prediction confirmed, one measurement settled a
second time, and a guard of the owner's broke three legs while my BROKEN
counter said 0.**

What held: eslogger's one line, now readable thanks to the verbatim
head, names exactly what was predicted — "responsible process needs TCC
Full Disk Access authorization (ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED)".
Root changes the refusal from NOT_PRIVILEGED to NOT_PERMITTED: ES is
reachable only behind root AND an FDA grant to the invoking terminal.
fs_usage passed a second time, this round with the contamination guard
attesting all 9 marker lines came from the observer.

What broke: the transcript's line 14 reads "omamori blocked this command
because it was invoked via sudo/elevated privileges" — the wrapper's
`chmod 755`. The wrapper stayed 0644, dtruss and dtrace died on "failed
to execute run-toy.sh: Permission denied", ktrace on "could not start
process", and none of that reached the BROKEN counter because the chmod
carried no guard: the exact targets-added-after-the-check shape, one day
after writing it down elsewhere. The owner's guard blocking the
measurement is itself the own-guard-blocks-the-next-measurement shape.
Round 2's L1/L4 therefore measure nothing about SIP; round 1's L2
remains the only probe-provider evidence (preserved as
sudo-survey-round1.txt; round 2 as sudo-survey-round2.txt).

Fix: no mode change anywhere. The wrapper is invoked as `/bin/sh
wrapper`, which needs no exec bit — routing around the guard with an
absolute /bin/chmod would be circumvention, needing no chmod is not.
dtruss and dtrace keep the toy as their DIRECT child, because /bin/sh in
front would make the traced root a platform binary, the one case the
SIP question must not be measured on; their contamination fix is stream
separation instead (trace on stderr, toy account on stdout).

**Predictions for round 3:** dtruss, clean streams — capture holds
DTrace's own refusal lines and zero syscall lines, check FAIL "saw
nothing", toy account 7 lines with toy-rc=0; dtrace aggregate rows 0
with the round-1 probe refusal back; ktrace starts this time, and its
observer lines carrying a marker path number **0** (151 non-op event
lines in round 1 held none); eslogger identical FDA refusal; fs_usage
passes a third time.

**Round 3 (08:41Z): complete. Four predictions held; the one that
missed, missed in a direction worth the whole survey.**

dtruss did not refuse. It printed its trace header and **zero syscall
lines**, ran the toy to completion, and **exited 0** — a silent empty
trace, which for an oracle is worse than a refusal, because the exit
code alone reads as success. The prediction said "refusal lines"; the
reality is quieter and more dangerous. The stream separation also failed
— dtruss remixes its child's stdout onto stderr, so the toy's account
landed in the capture after all — and the contamination guard built
after round 1 **fired in production**, turning what round 1 had scored
as "ok" into the correct FAIL. The guard's first real catch is the same
false pass it was built from.

Everything else landed as predicted. dtrace reproduced the round-1
probe refusal verbatim in a clean transcript. ktrace started under the
/bin/sh wrapper (a 337-line capture — a launch line, a column header
and a blank, then events — toy-rc=0 in its separated account) and
carried **0** marker paths in its own event lines — kdebug packs path
bytes into hex args; fs_usage is the shipped resolver. eslogger repeated
its FDA refusal, and fs_usage passed a third time, 9 of 9 marker lines
from the observer.

**The verdicts, and what moved.** The claim "macOS has no usable
oracle" was false as universally stated and is now corrected in seven
places (four claim sites the issue named, plus ci.yml, unknown-rate.md
and an acceptance.sh comment the issue's census missed): no
*unprivileged* oracle exists; SIP leaves DTrace's syscall provider
with no probes even as root, and dtruss fails silently on top of it;
`fs_usage` as root gave an ordered, attributed, full-path account of
the survey's six-operation toy, three runs out of three; Endpoint
Security's shipped CLI refuses without root plus a Full Disk Access
grant (a first-party ES client is unmeasured); OpenBSM is disabled by
Apple since 14.0. The 08-10
product stance — no root demand in a distributable default — survives
untouched, now standing on measurement instead of one sentence about
one tool. Left explicitly unmeasured: fs_usage's drop behaviour under
load, ktrace's --json output, and eslogger with FDA actually granted.

**R1 found eight claims wider than their transcript lines, all
accepted.** The heaviest: "DTrace is dead under SIP even as root" was
measured only for the syscall provider the probes named — every claim
site now says the provider — and "dtruss traced nothing" rested on a
capture the transcript showed only excerpts of. The arithmetic that
makes it checkable from committed data: the 283-byte capture holds the
SIP notice (80 bytes), the trace header (~36) and the toy's seven
`op` lines plus `done` (166) — those sum to the byte count within a
couple of bytes, and a dtruss syscall line runs tens of bytes, so
there is no room for even one. "Endpoint Security sits behind root plus
FDA" is now scoped to its shipped CLI, the thing actually measured.
"337 events" was numerically false (three preamble lines). The man-page
provenance the sudo script's comment cited was never committed —
survey.txt now carries the ktrace filter grammar, the eslogger TCC
paragraph and the fs_usage synopsis it designs from. And two guards no
transcript had shown red — wrapper readability and the residue check —
now fail on their own predicates in `sudo-survey.sh --selftest`, the
residue one against a live process really named fs_usage. observe()
additionally bounds the toy (R1: the 45s watchdog bounded only the
observer) and records whether the observer survived the settle;
rounds 1-3 ran before those two fixes, and no conclusion rests on the
paths they change — fs_usage's passes and eslogger's refusal are
outcome-proven in their transcripts.

The residue selftest's first version produced its own measurement: it
staged the fake observer by copying /bin/sleep to a file named
fs_usage, and the copy died on exec. R2 refused the claim because no
committed line carried it, so the selftest now reproduces it as a
recorded control: the copy exits 137 (SIGKILL) — and codesign still
VERIFIES the copy, which narrows the cause. The signature is not
broken; copying does not change it, exactly as this repository's
platform-binary refusal text says, and what kills the copy is the
execution policy on a platform-signed binary at a foreign path. The
staged observer is therefore compiled — ad-hoc signed by the linker,
it runs — and the guard passes in both directions.

## 2026-08-23 — the record catches up with cohort 4, and the denominators get a route

Cohort 4 closed this morning; the top-level record did not move with it.
`PRD.md`'s criterion-1 trail stops at cohort 3, `DESIGN.md`'s status line
still reads "design finalized, pre-implementation" thirteen tags in,
`docs/target-classes.md` carries neither the himalaya verdict nor the
unison probe wall, and its git row cites `#35` as open although that
issue closed 2026-08-17. That page was backfilled for cohorts 2 and 3
yesterday and drifted again within a day, which says the fix is a habit
at cohort close, not a bigger backfill.

Two measurements shaped this change. Both were made while planning it,
before this entry existed — the entry opened with the working tree, which
is the first moment there was a tree to open it in.

**The mini-seal transcript is missing for the one target that needs it
most.** Cohort 2 commits four `verify-transcript.txt` files and cohort 3
commits six — ten, and not one per target: the probe walls never spent a
define and poetry carries two. Cohort 4 commits none:
`git log --oneline --all --diff-filter=A -- 'spike/cohort4/**/verify*'`
returns nothing, so the file was never added there. The check itself
passes — `verify-assisted.sh spike/cohort4/himalaya-r2` returns ALL ORDER
CHECKS PASSED, the define complete at `e445686` strictly preceding the
first artifact at `1949c62`, all four define blobs byte-identical at both
points. What is missing is the evidence, not the property, and it is
missing on the first criterion-1 candidate in four cohorts — the target
whose provenance leg the mini-seal exists to machine-check.

**A hypothesis about severity died in the source, in the useful
direction.** Planning this, I expected `maildir messages move` to be
copy-then-delete, which would make the same crash window destroy mail
outright rather than leave clutter behind. It is not:
`io-maildir/src/entry/move.rs` runs
`Locate → AwaitTime → AwaitPid → AwaitHostname → AwaitRename` and
completes on the rename reply. One rename, no interior to crash inside.
`copy` is the outlier among the crate's arms, which is the opposite of
what I went looking for.

**One correction to my own prose, caught before review.** Both this entry
and the PRD paragraph first said the mini-seal ran on *every* target of
cohorts 2 and 3 — ten transcripts, ten targets, which reads true and is
not. KeePassXC spent no define and has none; poetry carries two. The
count was right and the universal was wrong, and it only became visible
when cohort 4 made the two numbers disagree: twelve targets, eleven
transcripts. Both sentences now state the count and name the exceptions
instead of quantifying over targets.

**The review round, and what moved.** Five P1s, no P0. The reviewer
re-derived every count here independently — eleven transcripts, twelve
targets, thirteen outcomes, five standing walls, seven verdicts, eighteen
post-sweep defines, thirteen release tags — and all of them held. Four
sentences did not:

- The criterion-6 note said the README had changed **twice** since run 1.
  `git log --since=2026-08-17 -- README.md` says **seven** commits, and
  this change is the eighth. Written from memory of what I had touched
  rather than from the log, which is the failure the rule about writing
  numbers from open sources exists to catch, committed inside a paragraph
  whose whole subject is a stale document.
- The same note said run 1 was "no longer the last run before the
  freeze". It is: it is still the only run, and by the criterion's own
  rule it is still the evidence. What moved is the document it measured,
  not its standing, and the note now says that and declines to re-score.
- The load-bearing sentence credited the mini-seal with showing that the
  define "preceded any observed failure". `verify-assisted.sh`'s own
  header says it audits the history as pushed and proves nothing about
  what happened on a private disk first. The claim is now split: the
  pushed ordering is machine-checked, and the protocol statement rests on
  it with the public order as its witness.
- The new README paragraph called the tool "safe to leave running
  unattended", which collides with the MCP section three paragraphs
  above, where this repository says plainly that the root confines which
  config may be named and not what that config's operation does. Narrowed
  to the exit-status distinction, with the boundary named rather than
  implied.

Also scoped, at the reviewer's prompting: criterion 4's status described
the A-group as "every runnable committed define", which stopped being
true when the eighteen later defines landed. It now carries its sweep
date and a pointer to `#239`.

**And the local check lied, in the documented way.** Rather than run the
full acceptance suite outside its container, I re-implemented check 11's
reference sweep to pre-check my own edits — and it reported
`/bin/true` missing from the cookbook, a reference that has been there
untouched all along. The real check skips absolute paths
(`case "$r" in -*|/*) continue`); my copy did not. Nothing was wrong with
the page and nothing needed fixing, which is the point: a check written
by copying production instead of calling it produces findings that belong
to the copy. The pre-check kept its value only as an existence test on
the four references this change adds; the sweep itself is CI's.

**The simplify pass changed the shape of the fix.** Two things came out of
it. One was ordinary trimming: the same conclusion — that what criterion 1
still lacks is no longer the search half — had been written three times in
three consecutive PRD paragraphs, and now appears once where the argument
is. The other is the reason this entry exists at all. Fixing the pages by
hand is the same move that was made yesterday for cohorts 2 and 3, and it
will be the same move again at cohort 5 unless something opens these files
at the moment a cohort ends. `CLAUDE.md` already carries exactly that rule
for `.gitattributes`, bought by exactly this failure; the record and the
verify transcript now sit beside it. That is a scope addition to this
change, deliberate and named here rather than slipped in.

**Then the same class bit a third time, in the rule itself.** Running the
diff through the universal-quantifier scan the claims rule asks for —
before opening the PR, after the commits were already pushed — turned up
the new `CLAUDE.md` sentence saying each define that reached an explore
leaves a verify transcript. Cohort 2 holds nine define directories and
four transcripts: hg's first three revisions and borg's first two all
reached explores and left none, because the transcript belongs to the
revision that produced the recorded outcome. Fixed forward rather than
amended, since the branch was pushed. Three instances in one change —
prose, then prose, then a rule written to prevent the first two — is the
argument for running that scan before review rather than after.

## 2026-08-23 — the formula shipped and the README still said "download the tarball"

`#180`'s whole thesis was that installing takes four steps and one thing
to remember where the ecosystem's answer is one line. The formula landed,
`brew install yottayoshida/tap/sideeye` works, the issue was closed
quoting that line — and the README, which is where anyone would actually
look, still opened with `tar xzf`. Half the issue, shipped as if it were
all of it.

The mechanism is worth naming because it is not "forgot". The release
checklist has a README step and it ran, at bump time, and its conclusion
was correct **then**: the only version-relative string was the tarball
name. The formula merged afterwards. Nothing brought the README back into
view once the thing it described had changed, because the checklist
attaches that step to a version bump and this change was not one.

Fixed here: the install section leads with brew, the tarball path stays
for everyone it still serves and now says *why* it wants you in that
directory (the shim sits beside the binary), and the three usage examples
drop their `./` since the primary path puts sideeye on `PATH`.

Checked before editing, because prose edits have moved test anchors here
before: nothing reads the README's install block. `quickstart.yml` builds
from source and `acceptance.sh` only mentions the README in a comment.
Checked after: `sideeye demo` from `PATH` exits 1 with the shim resolved
out of the Cellar, and `sideeye preflight` on a real state directory
refuses with `no_shim_marker` — which is SIP declining to inject into
`/bin/sh`, a platform binary, and not a shim it failed to find. Zero
complaints about a missing `--shim` in either.

## 2026-08-23 — v0.13.0: a second exhibit, a wider metadata exclusion, a relocatable shim

Minor rather than patch, and the reason is the second of those three: the
oracle's metadata exclusion widens to the timestamp family (#190), so a
run that previously refused with `unsupported_syscall_observed` on a
timestamp write now reaches a verdict. That changes what existing targets
answer, which is not a patch-level change. `checker_earliest` (#231) also
adds a field to the report.

The version lives in three places and all three moved: `build.zig.zon`,
`src/main.zig`, and the tarball name in the README's install block. Found
by grepping for the old version rather than from memory, which also
turned up a dozen mentions that must NOT move, because they name v0.12.0
as a past artifact: the headerpad measurement in `build.zig` and
`release.yml`, this file's own history, and the `sideeye_version` stamped
into every committed case file.

README reconciliation, the step that exists because two releases in a row
forgot it: the install block's tarball name is the only change it needs.
The FAIL report sample stays byte-accurate because its earliest world is
itself checker-red, which is exactly the case #231 leaves untouched, and
its `metadata` line was already about restore rather than about the
oracle's exclusion. `docs/scouting.md`'s table row had already moved with
#221.

The reconciliation also found the README's list of tools with
replay-confirmed counterexamples — timewarrior, topydo, GNU Stow,
calcurse, devtodo — running behind. That is a claim about the project's
record rather than a version-relative string, so it went to the owner
rather than being quietly edited; the ruling was to add himalaya, whose
counterexample replays and whose report is filed as
`pimalaya/himalaya#738`. poetry stays out for now: its report is closed
and its outcome is a separate question from whether the counterexample
stands.

168 tests, and the binary answers `sideeye 0.13.0`, which is the exact
form the release workflow checks against the tag.

## 2026-08-23 — the shim was not relocatable, and only a package manager noticed

`#180` had already measured that a Homebrew formula needs no code change:
the shim search is the binary's own directory then `../lib`, resolved
through realpath, which is exactly a keg's layout. That held. The formula
installs, `sideeye version` answers, and `sideeye demo` finds the planted
bug with the shim resolved out of `../lib`.

**And `brew install` still exits 1.** Homebrew rewrote the shim's install
name to an absolute path under its prefix, and v0.12.0's shim has no
padding in its Mach-O header for a longer name, so the rewrite failed and
the install reported "Failed to fix install linkage". Moving the dylib to
`libexec` does not help; the whole keg is scanned. sideeye's own lookup
does not notice, because it resolves the shim by real path and injects
that path, so the name it carries never enters the search. That is why
this survived to here: nothing that uses sideeye the way sideeye is used
had a reason to read it.

R1 caught two places where I had written that more widely than I had
measured: "the install name is never consulted" is false in general, since
dyld uses `LC_ID_DYLIB` as the library's identity, and "Homebrew rewrites
every dylib in a keg" is false too, since it has exceptions this library
happens not to qualify for. Both narrowed. The causal claim about this
library was never in doubt; the sentences around it were.

The fix is one build flag, `headerpad_max_install_names`, macOS only.
Measured as a pair on the two real artifacts rather than argued: give
both the same long install name, and v0.12.0's dylib keeps
`@rpath/libsideeye_shim.dylib` while the rebuilt one takes the new path.

**The tool lies in a way worth writing down.** `install_name_tool` prints
"larger updated load commands do not fit" on stderr and **exits 0**. Both
halves of the pair returned 0. The only thing that separated them was
reading the install name back with `otool -D` afterwards. So the new
release-workflow check asserts the resulting name, never a status, and
says so in a comment next to itself. It was seen red on v0.12.0's
released dylib, which is a real artifact rather than a synthetic one.

Ordering consequence, recorded because it reverses a decision made an
hour earlier: the formula cannot point at a release that predates this
flag, so Homebrew now lands after v0.13.0 rather than before it. The
formula itself is written and `brew audit --new` clean; only its URLs
and checksums are waiting.

## 2026-08-23 — cohort 4 closes, and stops counting as Shell

The slate is exhausted: himalaya reached a criterion-1 candidate and the
finding is filed upstream as `pimalaya/himalaya#738`, and unison is a
recorded named wall on determinism. `.gitattributes` says a closed cohort
belongs in its list, so `spike/cohort4/**` joins it.

That is 173,168 bytes of shell out of the 425,400 GitHub was still
counting, about two fifths of the visible Shell in a Zig repository. The
live harness stays out of the list on purpose, and the check that it did
was a negative control rather than an assumption: `acceptance.sh`,
`merge-gate.sh` and `campaign-driver.sh` all still report the attribute
unspecified, while all 112 tracked files under `spike/cohort4` report it
set.

**Filing the report left a second thing owed, and it was nearly missed.**
`upstream-report-status.sh` opens by saying it measures rather than
remembers, but the list of reports it measures is hardcoded in the
script. A new report that is not added there does not appear as missing:
the table simply prints five rows and looks complete, which is the exact
failure the file was written to prevent one level down. `#738` is
registered now, and the table prints six.

## 2026-08-23 — the recovery paths outside the tool

The last precondition the freeze's Reporting section puts in front of a
report: measure the recovery paths that exist outside the tool, and the
conditions under which they do not apply. Seven legs. R2, R4, R5, R6 and
R7 each produce the damage for themselves with a real crash rather than
assembling a store by hand; R3 is the deliberate exception and runs the
operation to completion, because what it counts is what the whole
operation does.

**The first thing measured was my own scan.** A three-level walk of the
command tree reported 208 commands; measuring the depth instead of
assuming it found a fourth level with 29 more. (Those two numbers are
this entry's own history, not artifacts: the committed script measures
depth 4 and 216/237.) The loose parse then turned out to be reading
wrapped alias lines as commands, so the enumeration is
indentation-strict and validated in both directions: every node it keeps
answers `--help` (216 of 216), and every node the fix dropped is not a
command (21 tried, 0 real). The dropped-node check printed a reassuring
`0` the first time it ran with its input file missing, which is why it
now refuses on an empty list.

**The answer.** Two recovery paths work and both need the user to notice
first. Repeating the copy restores the message but leaves the empty one
beside it, listed as a message. The empty one can be moved out by the
tool's own delete once the account names a trash mailbox, where it sits
in Trash still at 0 bytes. Meanwhile nothing offers to notice: no
command *name* in the surface is about checking stored mail, and
`account check` reports `maildir: OK` over the damaged store. The one
independent reader tried, python's `mailbox.Maildir`, enumerates the
empty file as an ordinary message as well.

Re-fetching from a server cannot restore the target-folder entry,
because the operation makes no call of the traced `%network` class while
creating it and no name in the surface is a sync. That is about the
entry and not the content: the content still exists in the source
folder, which is the honest limit of this finding's severity.

**Three things went against what I had already written, which is the
entire reason the controls are there.**

`message delete` refused on the empty message with `Cannot determine the
trash mailbox`, and I had written that up as the tool being unable to
remove it. The control refuses in the same words on a healthy message in
the same folder under the same config, so it is a property of an account
with no trash mailbox. The first version of that control was not a
control at all: it targeted the source message without `-m` and failed
with a different error entirely.

The review then found that the network leg counted a hand-written list
of syscall names, which measures "none of the names I thought of" rather
than none. It now counts every syscall line in a log strace was already
told to fill with the `%network` class, and the positive control
promptly caught `getsockname` and `getpeername`, neither of which was in
the old list.

The same review found the walk's `--help` status was being lost through
a pipe, so a failed invocation would have looked like a childless leaf.
Capturing it turned up 21 failures, and the new guard stopped the run.
They are all in the *loose* walk, which descends into the alias
fragments it mis-parses, so the guard's predicate was too wide and now
counts the strict walk. The number is a gift: 21 loose failures against
21 dropped nodes is a second, independent confirmation that the dropped
ones are not commands.

R2 then found the one fix that had not actually landed. I had added a
non-empty assertion to the store snapshot and treated the point as
closed; the reviewer pointed out that `find`'s status was still going
through a pipeline, so a **partial** read would give a short list rather
than an empty one, two short lists would compare equal, and "store
unchanged" would be a statement about an unknown subset. Recording the
status per call fixes it, and drilling it is what turned the point from
an argument into a measurement: with one subdirectory unreadable under a
dropped uid, `find` returns rc 1 **with one file still listed**, which
is exactly the shape the non-empty check cannot see.

That drill is now a `--selftest` mode, because the same rule that says a
define's checker legs must each be watched failing applies to the guards
a measurement script carries. Five cases, all green, and the first
attempt at the drill was written inline in nested shell and printed
`drill ok` from a comparison against an empty string, which is the
failure it exists to prevent.

Left explicitly unmeasured, written into the transcript rather than kept
in my head: whether an external syncer would carry the empty message
outward to a server, whether any reader other than the one tried would
flag it, and whether clap's help is a faithful index of the binary.

## 2026-08-23 — the stock reproduction, and what it corrected about my own argument

The freeze wants a finding to reproduce against the stock tool with
nothing beyond strace fault injection before it is claimed or reported.
Done, with the apparatus checks in the script rather than in a sentence:
no `/etc/ld.so.preload`, `LD_PRELOAD` unset, no shim, no engine, no
seccomp profile.

**And it corrected something I had argued rather than measured.** The r2
toml said the kill window does not depend on the apparatus, because the
destination is created and filled afterwards whichever primitive does
the filling. Stock turns out not to take the path the define measured at
all: it copies the whole 307-byte message in a single `copy_file_range`,
where the apparatus had removed that primitive and forced a read/write
loop. The window is there anyway. Killing at the copy leaves a 0-byte
message at its final path, himalaya lists it as an ordinary envelope
with blank subject, sender and date, and `message read` on it fails.

So the argument held, and it is now a measurement, which is the whole
reason the rule asks for one. The apparatus decided what the engine
could see; it did not make the finding.

Also caught by a gate rather than by me: the first push of this work
changed `spike/` without touching BUILDLOG, and CI's buildlog job failed
the PR. That is the contract this file opens with, enforced.

## 2026-08-23 — himalaya-r2: a FAIL through the declared checker, reproduced twice

The revision ran and the declaration held on every point it made.
**FAIL, 1 of 3 worlds, `oracle_verified: true`, single process**, the
violated invariant being the checker rather than the engine's built-in
atomicity invariant, and the report carrying `checker_earliest` — which
is exactly what this cohort's frozen claim rule asks a criterion-1
candidate to be. Two runs agree on every field that carries a judgement;
the eight that differ are the minted filename, which the checker is
name-agnostic about by design, and the per-run work paths. The exhibit
replays.

The crash lands after the destination is opened and before anything is
written to it, and leaves a message file at its final path in the target
folder with **0 bytes against the source's 307**. `proposals.md` named
that window, that leg and that world count before the engine ran, and
nothing in it was adjusted afterwards.

What is deliberately not claimed yet, and is written into RESULTS rather
than left to be discovered later: the stock reproduction is still owed
(the freeze wants a measurement, and the kill window being
apparatus-independent is so far an argument), the outside-the-tool
recovery paths the Reporting section demands are unmeasured, and novelty
was cleared at selection time rather than here.

One correction to my own procedure, recorded before the good news
because it is the part worth remembering: the first pair of r2 runs
happened with the r2 define on a local branch only. The mini-seal wants
a revision's directory first-parent on main before the engine touches
it, and `verify-assisted.sh` refuses on exactly that. The checker had
been on main since #247, so criterion 1's own text held, but the
mechanical discipline is the part that makes a claim publishable. Those
runs were discarded and repeated after the merge. They cost four
minutes.

## 2026-08-23 — himalaya explores, refuses, and the refusal is a gap between two predicates

The first explore of the merged define came back UNKNOWN:
`unsupported_syscall_observed: copy_file_range`, exit 2. The seccomp
profile was working exactly as the probe measured it — copy_file_range
and sendfile both ENOSYS, the copy falling back to the libc read/write
loop, 307 bytes landing correctly. The refusal was not about the target.

**Two predicates that looked like one.** The probe's condition asked
whether any accelerated copy SUCCEEDED and answered no. The oracle asks
whether the syscall was OBSERVED, and its predicate reads the syscall's
name and never its return value (`changesPersistentState`, oracle.zig).
An ENOSYS from the kernel is still an observation. A profile that makes
a call fail cannot satisfy a rule about calls being made, and the probe
gate could be green on its own terms while the next stage refused.

The owner ruled a revision, the cargo-r2 precedent: a refusal is not a
FAIL, so nothing about the define is frozen by it, and the define
surface — property, checker, setup, fixtures, argv — moves to
`himalaya-r2` byte for byte. Only the apparatus changes.
`no-accel-copy.so` answers the three accelerated primitives in userspace
so the syscall is never made and the tracer has nothing to see, which is
reachable because Rust std resolves them as weak symbols precisely so
`LD_PRELOAD` can interpose them (#244). Measured before the revision was
written: zero copy_file_range/sendfile lines in the trace, strace itself
healthy, the copy still 307 bytes. It rides /etc/ld.so.preload because
the engine owns LD_PRELOAD for its shim, and unlike the pid pin it
defines only those three functions.

What the apparatus does **not** change, since the stock-reproduction rule
turns on it: the destination is created with O_CREAT|O_TRUNC and filled
afterwards on both paths, so the kill window exists whether the fill is
one copy_file_range or a read/write loop. The apparatus decides what the
engine can see, not whether the window is there.

**And a procedural error of mine, recorded because the contract asks for
the reversals.** I explored r2 with its define only on a local branch.
The mini-seal requires a revision's target directory to be first-parent
on main before the engine touches it, and `verify-assisted.sh` refuses
(exit 2) precisely on that. The invariant itself had been on main since
#247 — the checker in r2 is byte-identical to the one that merged — so
criterion 1's own text was satisfied, but the mechanical discipline was
not, and the discipline is the part that makes a claim publishable. Both
runs were discarded rather than kept with a disclosure. They cost four
minutes and had already proved themselves reproducible; provenance costs
more than that.

## 2026-08-23 — himalaya's define: what the checker may use, measured before it is written

Entry opened before the define exists, per the contract. The probe (#246)
established the operation is measurable; the define now has to state the
property, and the mini-seal says nothing may explore until the complete
define — toml, setup, checker, launcher — is first-parent on main.

Two things get measured before a line of the checker is written, because
cohort 3 paid for both. papis's checker rejected `papis doctor` as the
documented recovery on a reading that had never actually run the command
(no selection flag, so it fell to an interactive picker), and papis's own
reader turned out to WRITE — `papis list` minted and persisted a random
papis_id into a document that had lost one, which would have made a byte
assertion after the reader a judgement of the checker's own side effect.
So for himalaya: does the reader this checker wants to use mutate the
store, and does himalaya carry anything that could be called a documented
recovery? Both answered by trials in `pre-define-trials.txt`, before the
property is committed.

**Both answers came back useful, and one of them shapes the property.**
The reader does not write: five states, healthy through zero-length,
with every path, size and checksum snapshotted around each invocation,
and nothing moved. So the ordering papis needed does not bind here, and
the checker says which of the two reasons it is following. There is no
documented recovery either: the enumerated command surface has no
doctor, repair, check, verify or fsck, and the maildir subtree offers
create, rename, delete, list, messages, flags. Nothing is run before the
assert because nothing claims to repair a store.

The measurement that shapes the property is trial G. **A zero-length
message lists as an ordinary envelope** — one row, `0 B`, blank subject,
from and date, rc 0 — and so does one cut mid-headers. Only `message
read` refuses the empty one. That settles the checker's architecture:
the byte assertion is what catches a torn copy, and the tool's own
reader runs beside it rather than instead of it. It also says something
about what a finding here would mean, which `proposals.md` states before
the engine has run: a crash in this arm leaves a message the tool
presents as real and whose content is gone.

Two design decisions recorded with their reasons. The checker is
**name-agnostic**: io-maildir mints the copy's filename from clock,
counter, pid and hostname, and the pins the probe used cannot come along
— the engine owns `LD_PRELOAD` for its shim, and `/etc/ld.so.preload`
was measured to break strace, which the engine uses as its oracle. The
engine does not need cross-run byte identity (it refuses on threads and
on a baseline that violates the invariant), so the checker asserts
content and flag suffix and never the minted name. The **seccomp profile
stays**, and is not optional: without it `fs::copy` reaches
`copy_file_range`, which the shim does not export and the oracle reports
as unsupported. It applies at the container boundary, so the launcher
cannot carry it and the RUNLOG records the invocation that does.

Drills: every leg red once, on its own, with the expected leg named.
**Re-read after two review rounds, per the contract, and two sentences
of this paragraph did not survive them.**

The first draft said "both states the operation can actually leave are
green", and R1 pointed out that both had been measured on stores built
by hand: the operation itself appeared in no transcript in the PR. It
does now, first case in the drills, through the define's own setup and
the toml's own argv, and it is the case that matters most, because a red
checker on the un-killed state is what `baseline_violates_invariant`
costs the target its slot for. The run also demonstrated the
name-agnostic design rather than arguing it: with the probe's clock and
pid pins absent the copy landed as
`1787451722.#0M840838050P17.<host>:2,S`, 307 bytes, and the checker
passed.

The same draft said leg R's predicate was "exercised directly" and left
it there. R1 counted the leg's fail sites: five, with two drilled. All
five are drilled now. Leg C is two drills rather than one, a changed
config and a missing one, because the first version reported a config
that had been deleted as one that had "changed".

R1's first finding was the sharper one, and it was mine: the drills
spawned check.sh as `sh file`, the form CLAUDE.md forbids and campaign 2
bought with a Permission denied at the first sealed exploration, and
they had copied setup.sh's config-writing inline, so the define's own
setup had no green run anywhere and a drift between it and the checker's
leg C would have stayed green in the drills. R2 then proved the fix by
its own predicate rather than by inspection: with check.sh at 644 every
drill fails with Permission denied, so the exec bit is load-bearing and
there is no silent `sh` fallback.

## 2026-08-23 — cohort 4 probes: the plans are frozen, so the scripts are transcription

Entry opened at the start of the probes work, an hour after the freeze
(#245) merged. The probe plans, fixtures, argv and apparatus are all
frozen in PROTOCOL.md, so what this PR adds is their mechanical form: the
positive control (cohort 3's synthetic wall-clock writer, verbatim in
predicate path), one run script per target with the fixture bytes
transcribed exactly, and the transcripts. The one design decision the
scripts do make, recorded now: each target's script takes a mode argument
(the borg precedent), because the falsification order is part of the
frozen plan. himalaya runs `bare` first (no apparatus; the determinism
split on the minted pid and the strace showing `copy_file_range` are the
falsifications that JUSTIFY the apparatus) and `apparatus` second
(ld.so.preload carrying libfaketime and pin-getpid.so, the container
under seccomp-enosys.json, where the accepted verdict lives). unison runs
the same two modes with its own argv. Apparatus plumbing corrections, if
any, land in the transcript per the freeze's own rule.

**himalaya passed every judged condition, and the bare mode earned its keep.**
Without apparatus the two runs split on the minted entry name and the
copy *succeeded* through `copy_file_range` — the shim-invisible path — so
the seccomp profile was justified by measurement before it was used once.
With it: byte-identical roots, the minted name reading
`1767225600.#0M0P4242.<host>` in both (the apparatus visible in the
artifact), condition 8 clean, condition 9 counting two kill points, and 0
of 3 kernel-copy attempts succeeding.

**unison cost four wrong hypotheses and ended as a named wall — which is
the probe gate working.** The first apparatus run hung after "Looking for
changes". Four things were blamed and each was eliminated by measurement
before the next was tried: the equal-second guard in `Fileinfo.unchanged`
(reachable only if libfaketime faked stat, which a direct check said it
did not — and that check was itself wrong, having read the mtimes with
`env -u FAKETIME`, i.e. with the apparatus switched off); pin-getpid; the
seccomp profile; and the frozen clock as such. A bisection down to the
one structural difference found it: **the harness was creating its
fixtures and pristine restores under the frozen clock**, which made their
mtimes equal the frozen instant as the target reads them, arming unison's
own guard — and libfaketime then scaled its one-second sleep by the
frozen speed. strace named it exactly:
`clock_nanosleep(CLOCK_REALTIME, {tv_sec=9223372036})`. libfaketime is
inert without FAKETIME in the environment, so applying the apparatus to
the target invocations only is the whole fix, and it is recorded as a
plumbing correction inside the probe rather than quietly applied.

Then the wall itself. Two runs of the frozen operation on one restored
pre-state leave archives differing by a handful of bytes, the counts printed by
the diagnosis rather than quoted from memory. The freeze forecast
the directory inode inside `freshDirStamp` as the un-coverable residue;
measurement eliminated it: the directory inodes and the propagated file's
inode come back identical, and so does its mtime once `-times=true` is
added — a qualifier worth keeping, since the shipped argv carries no
`-times` and its propagated mtime does differ. **The residue is recorded
as unattributed**, with the four eliminated hypotheses named, because a
fifth would be a guess and the verdict does not depend on it. `-times=true` was measured purely
to answer whether amending the frozen argv would buy determinism: it does
not, so no amendment is proposed. Cost: one transcript, zero defines.
Condition 8 meanwhile passed cleanly for unison too — with the profile
landing the copy stub on its read/write fallback, every in-root mutation
is interposable — and condition 9 counted 62 kill points, a rich interior
the cohort will not get to use.

Three harness defects surfaced along the way, all of the same family:
- An interrupted edit truncated `run-unison.sh` mid-block, deleting the
  whole round-trip check and leaving only comment lines. **The result was
  still valid shell**: it would have run, judged one condition fewer, and
  printed "conditions failed: 0". That bought `check-transcript.sh`,
  which compares the verdict names emitted against the names the plan
  requires and now closes every transcript. It is falsified four ways
  (deleted verdict, renamed verdict, and an extractor control) and its
  own first cut used sed's `\|`, a GNU extension that matched nothing on
  the macOS host — caught by that same extractor control.
- The round-trip check compared the whole state root and went red while
  the tool printed "Nothing to do"; unison rewrites its archives and
  appends to `unison.log` on every invocation, which the freeze's own
  expected-artifacts line already said. It also compared against run A's
  snapshot when the re-run starts from run B's. Both fixed; the scan for
  the same class across both probe scripts found no other comparison
  whose unit was wrong.
- Condition 8 first reported a wall for unison whose own numbers refused
  to add up — `interposed=9` against `unmatched=21`. The harness was
  passing `LD_PRELOAD=pin-getpid.so` into the preflight invocation, which
  **replaces** the visibility logger preflight had just installed, so
  unison ran with no interposer at all. A FAIL can be the harness, and
  the way to tell is that its own numbers disagree with each other.

## 2026-08-23 — cohort 4 begins: the freeze is a fill-in, and one of its citations turned out not to exist

Entry opened at the start of the work, per the contract. The slate has
been signed off since 2026-08-22 (himalaya and vdirsyncer, two slots, the
remaining primaries and the whole bench deliberately empty), and
`PROTOCOL-DRAFT.md` says the freeze should be a fill-in rather than a
write. Two of its three blocked sections unblock with the target list
(per-target probe plans, versions and image); the third (claim reading)
unblocked when #231 merged. So the work here is: scout rows for the two
targets, the image with its freeze-build transcript, the probe plans with
fixture bytes inlined, and the freeze itself.

Division of labour, set today by the owner: this session owns the freeze
and everything downstream (probes, defines, explores); a peer session
supplies the measured scout rows (rules 1-3 and 11-17 receipts, the
novelty pre-scans, write-path readings from public source, checker
sketches), all target-non-contact, delivered on a local branch, with
BUILDLOG left to this session so the head cannot collide (the #238/#231
lesson).

First finding of the day, before any new measurement: **the himalaya
write-path determination this cohort has been leaning on is not on
main.** The 2026-08-22 reading (io-maildir's std driver,
`fs::rename`/`fs::write`, no fsync, the tmp-then-new two-stage window,
static distribution) was made in a session and recorded in workspace
memory, but a grep for its terms across every committed .md and .txt
returns zero lines. A freeze cannot cite a chat. The row was re-derived
from public source and committed like vdirsyncer's: the E4 register row
again, in a new costume. A determination that never became a diff was
never checked as one.

Image plan, decided in the morning: trixie-slim with the apt layer pinned
by build, artifacts fetched host-side against the TLS-intercepting proxy
(the cohort-2 measurement, unchanged); rust 1.98.0 from the same
channel-manifest pin cohort 3 used (the tarball is still in the local
cache and re-verifies against the published sha256); **himalaya built
from the v2.1.0 source tag inside the image**, because the distributed
binaries are static cross-builds the shim cannot enter, so the measured
binary is a self-build and the freeze says so in the versions section,
with the crate closure vendored host-side by `cargo vendor --locked`
against himalaya's own committed Cargo.lock; vdirsyncer at its current
stable with a uv-generated hash lock, the cohort-3 pattern verbatim.

**Same day, and the paragraph above is already stale on one word: the
slate lost vdirsyncer to its own measured row.** The scout rows this
cohort demanded (rules measured, not recalled) came back from the peer
session and failed vdirsyncer on rule 2 (three commits in the six-month
window, all typo/docs/CI), rule 3 (one author in that window), and rules
11/17 (one of its six recent bug reports answered within a week, the
committed row's figure; the peer's first chat message carried a different
count from an earlier cut of the same measurement, this entry briefly
copied it, and the committed transcript outranks the chat, the E4 failure
in miniature, caught by the digits check run early). The checker anchor
the slate had assumed, `repair`, sits behind an interactive
`click.confirm` (re-verified here from the fetched wheel before gating on
it). The 2026-08-22 sign-off was made on rows that had not been measured
to the brief's standard; the measurement outranks the sign-off. Owner
ruling (2026-08-23, AskUserQuestion, both halves): **vdirsyncer is
dropped, and the second slot is re-scouted before the freeze lands**; no
single-target cohort, no promotion clause in the freeze. The FAIL row
stays committed with its transcripts; the rejection table is the audit.

The himalaya half of the freeze filled in meanwhile, and picking the
operation settled on the arm the write-path reading singled out:
**`maildir messages copy` is the one io-maildir arm without a tmp stage**.
The destination is created at its final path and filled in place
(`entry/copy.rs`, the I/O at `client.rs:227` `fs::copy`), so every
intermediate state is a visible message in the target folder. save and
move rename; copy exposes. Two rule-16 forecasts came out of reading the
same sources, each with committed apparatus the probe must first show red
without: minted entry names embed the pid
(`{secs}.#{counter:x}M{nanos}P{pid}.{hostname}`, entry.rs:48-56, via libc
getpid at client.rs:239), answered by `pin-getpid.c` loaded the
libfaketime way; and `fs::copy` prefers `copy_file_range`/`sendfile`,
both of which the oracle reports as unsupported (the hg-r2 precedent,
oracle.zig's own test), answered by `seccomp-enosys.json`, which lands
std on the libc read/write loop the shim exports. The kill window needs
neither: the destination exists empty before any bytes move, so strace
fault injection reproduces the torn state against the stock tool under
every copy mechanism.

**The re-scout came back one-for-five, and the owner closed both open
questions in one gate (2026-08-23, AskUserQuestion).** Homebrew fell on
rule 5, trash-cli and pipx on rules 11/17, CocoaPods on rule 3; **unison
survived rules 1-15**, entering on a strong rule-3 row (two contributors
at comparable weight) and a writer that leaves a commit log for exactly
the window this engine crashes into. Rulings: **unison takes slot 2**,
and **himalaya stays on `messages copy` with the seccomp profile as the
ruled lift**. The peer's correction had meanwhile shown the copy arm
invisible to the shim's 52 exports (`fs::copy` reaching
`copy_file_range`/`sendfile`), and the profile turned out to be the one
apparatus that lifts *both* targets' copy walls, because seccomp filters
at the kernel boundary and cannot be dodged by the `syscall(3)` spelling
unison uses (copy_stubs.c:199) or by the weak-symbol route std uses. That
taxonomy (inline instruction / `syscall(3)` / weak lookup, three
mechanisms the old wall table read as one) is now a row in
`docs/target-classes.md` and roadmap #244: the shim-side lift, an export
plus the oracle op class it would also need.

The unison determinism reading (peer, from source, line-numbered in
`SCOUT-ROWS-SLOT2.md`) found the preference that actually removes inodes
from the archive is `ignoreinodenumbers`, *not* `fastcheck`, and found
the hazard the preference does not reach: **`freshDirStamp` folds
`(gettimeofday + √2·getpid)·1000 + the directory's inode` into one
archived number** (props.ml:1575-1585). faketime and `pin-getpid.c`
cover two of the three terms; the directory inode has no apparatus, so
the freeze names it honestly as the residue the probe's two-run
comparison measures, a possible nondeterministic-writer wall, priced at
one transcript. The same reading flagged that a frozen clock can flip
`Fileinfo.unchanged`'s equal-second branch (a one-second sleep and a
forced "changed" per file, fileinfo.ml:246-249): the apparatus changing
the target's behaviour, to be measured at the probe rather than assumed
away. `seccomp-enosys.json` gained an arg-filtered ioctl rule (ENOTTY for
FICLONE, value 0x40049409, everything else untouched) so the reflink arm
fails by construction instead of by trusting the container filesystem.
The image now builds both targets from commit-pinned trees (unison
because upstream ships no aarch64-linux binary at all; nine release
assets read, macOS arm64 only) and the freeze-build transcript comes from
a single --no-cache build so every quoted line is from one clean build
rather than from cache hits of the vdirsyncer-era layers.

**The first-sight review came back BLOCK, and its P0 was real: the
unison sign-off rested on a misreading of the recovery path.** The rows
and this entry had said the `DANGER.README` commit log is "replayed
mechanically by the next startup". The pinned source says otherwise,
verified here by direct read before gating: `processCommitLog`
(files.ml:70) detects the file and raises Fatal, instructing the user to
inspect the named files, delete the notice, and run again; the notice
itself (files.ml:30-46) says the same. No replay exists. Owner re-ruling
(2026-08-23, AskUserQuestion, on the corrected facts): **unison stays**,
with the checker's recovery defined as following the tool's own written
instruction (the one deletion, the single non-tool action) and then
re-running the tool for the assert, and with the Fatal refusal itself
used as a tool-command assert leg. Third pre-define catch of the same
shape: papis `doctor`, vdirsyncer `repair`, unison replay. The reviewer's
sweep also caught the peer's files.ml call-site line numbers coming from
a newer revision (a 21-line insertion upstream of renameLocal shifted
the citations below it by +21 while the rest sat unchanged, so each was
re-pinned individually by grep against the v2.54.0 tree; a bulk offset
would have broken the unchanged ones), a four-not-three count in the
vdirsyncer rule-11 prose
(#1207 also drew no non-author comment; the committed transcript already
said so), and a bug-set "fastest" figure that belonged to a non-bug
issue. Four of the reviewer's own line numbers were themselves off by
one (:27/:69/:83 and a NEWS.md:169) and were rejected against grep -n
output before any edit: the reviewer's numbers get the same verification
as anyone's.

The review's remaining structural point was that the image gates had
only ever been seen green. Every pin and assert in the Dockerfile and
fetch-artifacts.sh is now shown red once against a synthetic mutation
(`guard-reds.txt`): both tree-digest checks (one flipped hex character
each), the ldd dynamic-linkage assertion (a static hello), the commit
pin (flipped hex in the pinned SHA), and the download sha pin (an
uncached name pointed at a small real file). Two misfires during that
work are kept in the transcript because they are the register working:
the first mutation targeted a variable the rewritten script no longer
has and came back green (a green falsification is a broken falsification
until proven otherwise), and one raw rc was first read through a pipe
and said 0 while FAIL printed, the C1 row stepped in again. LC_ALL=C now
pins the digest sort collation on both sides (host and image digests
re-verified unchanged), and the digest's scope is stated where it is
computed: file contents and names, not symlinks or modes (zero symlinks
in both trees, measured).

Also today, relayed by the session that owns upstream reporting:
**poetry #11019 drew its first comments and was closed not-planned**, so
rule 11 has now been tested on a report of ours exactly once, negatively.
`spike/upstream-report-status.sh` gains the fifth row so the measuring
device stops being blind to it, and the freeze's Reporting section gains
the lesson as a requirement: measure the recovery paths outside the tool,
and when they fail, before reporting (for himalaya, what is lost before
it reaches the synchronized side; for unison, whether damage propagates
to the healthy replica, which would break the external recovery path
itself). A note for cohort-5 selection, not this slate: poetry's manifest
survives corruption because users keep it in version control, a
recoverability class rule 5's current wording does not capture. And the
owner's punctuation ruling (relayed and scope-confirmed today) applied
to everything written today: em dashes are gone from this cohort's new
files; older entries and the verbatim ADR 0020 quotation stay as
written.

## 2026-08-22 — the rejections were thinner than the funnel implied, and six were re-judged

The cohort-4 candidate funnel went out with two numbers I had not counted
and one stage that was not a stage. Recounted from the file the enumeration
actually wrote: 159 unique repositories, not 163 rows; the language wall
forecast removed **128**, not the 64 I reported (that figure was Go plus
TypeScript plus JavaScript and omitted Shell, PHP, Java, Swift, Kotlin, C#,
Nix and six more); and the "~50 left" was never computed — it was written to
keep the column continuous. The owner's audit derived ~89 rejections at the
rules-4/5/7 stage from those numbers, which was correct arithmetic on a
wrong table: the real figure is 31 in, 22 rejected, 2 set aside, 3 unread,
4 already measured.

Worse than the counts: **no project was read at that stage.** Every one of
the 31 was judged from the search result's own one-line description plus
recollection. The brief this cohort runs under says a candidate row missing
a measurement is an incomplete row; by its own standard the whole column
was incomplete, and I had written the word "read" over it.

**Owner rulings that close the selection (2026-08-22, recorded at the moment
they were made rather than when the freeze is written — the contract in
CLAUDE.md).**

- **Rule 9 is pinned to reading (b): a checker must go through the target's
  own commands.** The alternative — reading a plain-text store directly —
  was declined. The precedent held: every cohort-2 and cohort-3 checker went
  through its target's commands. **No exception clause for neomutt**, which
  was offered and refused.
- **The slate freezes at two: himalaya (Rust) and vdirsyncer (Python).** The
  remaining three primary slots and the bench are deliberately not filled.
- **neomutt therefore drops on rule 9**, and it is the only candidate in
  four cohorts to fall to an interpretation rather than to a measurable
  wall: its write path was measured visible (libc `open` + `rename`, no
  mkstemp) and its batch mode measured to write into the judged maildir, and
  neither fact saved it, because it has no non-interactive read-back for a
  checker to use. himalaya has `envelope list` / `message read` and
  vdirsyncer has `repair`, so neither needs the reading that was refused.
  The freeze will carry that record rather than only the outcome.

Worth keeping beside those three: the candidate that moved three times today
moved on my reasoning each time, never on the target. neomutt was rejected
on rule 8 (wrong — batch mode is a first-class mode in its own man page),
returned to the pool with both open questions answered favourably from
source, and then dropped on rule 9. The target never changed.

**Third pass, same day: the two rows left on a judgment were read from
source, and one of them changed the slate.** neomutt returns to the pool
with both of its open questions answered favourably — send/send.c has an
Fcc branch guarded by SEND_BATCH ("Printed when an Fcc in batch mode
fails"), so a non-interactive invocation with a local `record` writes into
the judged maildir; and maildir/message.c opens the temp file with plain
`open(path, O_WRONLY | O_EXCL | O_CREAT, 0666)` and moves it with
`rename()` — libc, no mkstemp, which is the question today's #39
measurement made cheap to ask of any C candidate. What holds it back is
rule 4 (the primary interface is a TUI — a judgment reading cannot settle)
and rule 9 (no non-interactive read-back, so a checker would read the
maildir rather than use the tool). It brings the language the slate lacks.

calcure's rule 8 was simply wrong, not merely unproven: `--task` and
`--event` both add and exit. But calcure/savers.py then argues against the
slot better than my rejection did — every row is written to `<file>.bak`
and moved with `Path.replace()`, so **no window loses the user's tasks**,
and the forecast is PASS with `.bak` noise in the judged root. Overturning
a rejection and finding the target uninteresting are different results, and
this pass produced the second.

The three unread rows closed too: yadm is a `#!/bin/sh` script whose writes
run in git children (the pass wall, #123 — GitHub's "Python" is its test
suite), and bob and proto keep re-downloadable toolchains, which is not
primary data. proto's user-authored `.prototools` is the only part worth
revisiting if slots stay empty.

Slate after three passes: himalaya (Rust), vdirsyncer (Python), neomutt
(C) — three languages, all multi-file coherence, **two primary slots and
the whole bench still empty**. The population argument is unchanged: 128 of
159 enumerated repositories fell to language wall forecasts, and both walls
doing that work are scheduled after v1.0.

The owner's instruction was to re-judge the thin rejections against primary
sources, reading only. Six rows, and the results split:

- **pnpm** — upheld, and now on the project's own sentence: the README
  calls the Rust port experimental, so the shipped CLI is still the Node one
  and the thread forecast applies to what rule 12 says to measure. The doubt
  was real (Rust is the majority language by bytes, with a genuine
  workspace); the answer happened to be the one I had guessed.
- **neomutt** — my rule was **wrong**. "Batch mode" is a first-class mode in
  neomutt's own man page, -e/--command runs commands after config, and draft
  files on stdin are documented as processed identically in batch and
  interactive mode. Rule 8 does not fail. The rejection now rests on rule 4
  — the primary interface is a TUI — which is a judgment about the word
  "primary", recorded as one.
- **ArchiveBox** — my rule was **wrong** in the other direction. The primary
  data is files under the archive directory; the project itself calls its
  SQLite file "your index", so rule 7 passes. It is still rejected, on rule
  4 (five interfaces, browser extension listed first) and more strongly on
  rule 16: the archiving is done by Chrome, wget and yt-dlp — child
  processes writing the state, which is the pass wall (#123).
- **TrendRadar**, **ffsubsync** — upheld, bases upgraded from a search
  summary to the projects' own READMEs.
- **calcure** — **weakened to uncertain.** Its README documents
  argument-driven task and event adding, so rule 8 is unproven; rule 4 is
  the likelier objection. One wiki page would settle it and this pass did
  not open it.

Zero rejections were fully overturned, which is the least interesting part
of the result. The interesting part is that two of them now stand on a
judgment rather than on a rule a measurement can settle, and the owner can
see which.

Two process notes. The register's E4 check — grep the diff for digits and
open the primary source for each — is bound to *diffs*, and the wrong funnel
went out in a chat message, which is not a diff. The check never fired. And
this log's first draft backticked upstream repository names, which is
exactly what acceptance check 11 extracts as repository paths; the
convention `docs/target-classes.md` already follows is now followed here
too, with a note saying why.

## 2026-08-22 — #231: the overall earliest and the claim exhibit are two different things

Entry started before the first line of code, per the contract. The
poetry pair proved that "the run's saved case = the earliest violating
world" promotes an engine implementation detail — one case per run —
into a scoring rule: poetry's lock-first write shape puts an L0-only
precision-limit world structurally ahead of the real checker-red
manifest destruction, and the exhibit slot was already taken. The fix
is to separate the two roles the single case has been playing.
**Overall earliest stays exactly what it is** — the first physical
counterexample, `earliest` in the report, `cases/000001.json` on
disk, every existing consumer untouched. **The claim exhibit becomes
its own thing**: the earliest world whose violation includes the
declared checker, tracked by the invariant bits at world-judgment
time (never by parsing the invariant string), saved as its own case
when it is a different world, and reported as `checker_earliest` —
the `earliest` shape plus its own `case` and `replay` inside, absent
when no checker-red world exists. The write order is fixed (earliest
first), so 000001's owner never changes; if the earliest case cannot
be written, the checker case is not written either, keeping "000001,
when present, belongs to the earliest" as an invariant. Plan R1
measured one assumption dead before it shipped: acceptance's check-4
FAIL fixture runs without `--check`, so a checker-red world is
structurally impossible there and the fixture change is definite
work, not a contingency — with the `--oracle` kept, because the same
fixture feeds the `ov_pin`. (Decisions recorded as they land; the
mutation drill's result is appended below when it runs.)

Two decisions from the implementation itself. The regression toy's
first draft used the existing `write_file` helper, whose `fsync` is
itself a kill point — six crash points instead of the declared four,
with the exhibits at k=2/k=5 instead of the declared k=2/k=4; the toy
now does raw open/write/close so the committed check asserts the
numbers the design named. And the replay leg of the new acceptance
check initially invoked `sideeye replay` bare: a case carries the
define but not the environment, so the fresh recording would have run
the toy's ordinary rotate instead of the split rewrite and refused
with `case_no_longer_applies` — the env rides the invocation, as it
does in every other env-driven toy check.

The three falsification drills, run and measured (all 2026-08-22).
**Pre-change binary** (origin/main in a worktree) against the new toy
and checker: FAIL 2 of 5, earliest k=2 L0-only, **no
`checker_earliest` field, one case file**. Red on that binary, named
rather than totalled (this PR's R1 caught the first draft's "every
new assertion" — six of check 4c's assertions are about the old
behavior and stay green on the old binary): the two
`checker_earliest` field pins, both case-ownership pins on the
second file, the `checker red` text grep, five of the replay leg's
six assertions (the sixth — the replayed-path equality — compares
two empty reads against the old binary and is vacuously green
there), and the same-world control reads as they stood at drill time. **The schema pin, both directions, raw rc**: the new
doc against the old binary's four-report corpus exits 1 with
"documented but never generated" naming all nine `checker_earliest`
rows; the old doc against the new binary's corpus exits 1 with
"generated but not documented" naming the same nine. (The first
measurement of side (a) read the rc through a `head` pipe and printed
0 beside the red message — the exact pipe trap this workspace has on
record; re-measured bare.) **The write-order mutation**: a scratch
mutant writing a checker-world case before the earliest's was built
and run against the committed check 4c; exactly the two ownership
assertions broke — `case: .../000002.json, wanted .../000001.json`
and `checker_earliest.case: .../000003.json, wanted .../000002.json`
— so the 000001-owner invariant is measured by assertions that die
when it does, and the mutant was reverted from the committed base.
## 2026-08-22 — the register was ten measurements behind the measurements

`docs/target-classes.md` says what "supported" means — "supported classes
are exactly the rows of the first table below" — and PRD's UNKNOWN-rate
criterion takes the word from there. It listed thirteen tools, all of them
from the blind campaigns and the assisted cohort. **None of cohort 2's
five and none of cohort 3's five were on it.** Two cohorts of measurement,
closed and recorded in their own RESULTS and RUNLOG files, never reached
the page that summarises what has been measured.

Backfilled here, in the shape the page already uses. Six verdict rows —
Mercurial (FAIL 73/107, all L0-only, contract held 107/107), Borg (FAIL
3/119, same shape, under declared pins), black and rustfmt (FAIL 1/3 each,
the same in-place tear in two languages, both already on their trackers),
poetry (FAIL 2/5, not a candidate because the earliest world is L0-only,
with the checker-red world behind it reported as python-poetry/poetry#11019),
papis (PASS 2/2, the contrast case). Three refusal rows — jj on static
linkage, Bun on threads, cargo on the raw-syscall rename. And one new
section for a distinction the page could not previously express: KeePassXC
never reached a define, because the engine-free probe refused first on
determinism and on 7 unattributable calls. Calling that an engine refusal
would have been a claim about a judgement that never happened.

Two consequences worth stating rather than leaving to be noticed. The
supported set grew by six rows today, so any sentence elsewhere that
counts supported classes is now stale. And `docs/unknown-rate.md`'s
A-group is defined as *every committed, runnable define in the repository*
while its sweep ran on 2026-08-16 — before both cohorts, which have since
committed **16** further defines, several of which reach named refusals
rather than verdicts. That page now carries an as-of note saying so. The
threshold is unaffected: it is set from B-group only, and no cohort-2 or
cohort-3 target is in B-group. Re-running the A-group sweep is filed
separately rather than done here, because doing it inside a documentation
change would bury a measurement in a backfill.

One row on that page was not stale but empty, and it is filled here by
measuring rather than by moving text. `#39` — libc functions that mutate
state through internal calls — carried "no recorded run for any of these
members" since it was filed. Two members are now measured
(`spike/cohort4/mkstemp-class.txt`, on a new toy written for it), and both
are invisible in the way the mechanism predicted. The canonical C
atomic-replace idiom, `mkstemp` + write + fsync + rename, has its
**creation** performed inside libc: the kernel issues
`openat(..., O_RDWR|O_CREAT|O_EXCL, 0600)` in the state root and the
interposer records no `open` for that path. The control is in the same
run and needed no arranging — the write and the fsync on that same temp
file *are* visible, because the program issues those itself. `dprintf`
behaves identically (its `open` is visible, its write is not) and
`tmpfile` left nothing inside the root.

This one matters for cohort 4 before selection rather than after: a C or
C++ target whose atomic write goes through `mkstemp` hits the same wall as
cargo's raw rename, and the idiom is the one a careful C program is
*supposed* to use. `preflight.sh visibility` names it at probe time, which
is the whole point of having built the thing before the cohort rather than
during it — and this is its third falsification shape, distinct from the
raw-syscall toy and the libc-routed one.

Then the same-class scan asked which *other* documents summarise
measurements, and the answer was worse than the two being fixed. Searched
for any mention of cohorts 2 or 3 — by name, by issue number, or by target
— **`PRD.md`, `DESIGN.md`, `docs/kill-criteria-review.md`, `README.md` and
`docs/scouting.md` returned zero each.** PRD's criterion-1 status trail
stops on 2026-08-15 and closes with "what remains is the
novelty/confirmation/fix/replay work on the assisted findings", written
before the two campaigns that were run specifically to close that
criterion. The document that defines the v1.0 gate had no record of ten
targets measured against it.

PRD and DESIGN §17 gain those outcomes here — facts only, no criterion
re-scored — and the closing sentence is corrected to say what remains:
one finding that is novel, automatically discovered and provenance-clean
at once. `docs/kill-criteria-review.md` is deliberately **not** touched:
criterion 3 is scored there against collected data, the data has since
grown by ten targets, and its Row 8 names its own margin as one trial.
Re-scoring a met criterion inside a documentation backfill is exactly the
move this repository refuses; it is filed instead. README needed nothing —
it points at `docs/target-classes.md` rather than restating it, which is
why fixing the register fixed the README too.

**CI caught what the local checks did not: the as-of note broke a machine
check.** `docs/unknown-rate.md` carries a generated results block between
`<!-- unknown-rate:results:begin/end -->` markers whose own first line says
"do not edit between the markers", and acceptance check 12 compares it
byte for byte against `count.py`'s recomputation. The note landed directly
under the `#### A-group` heading — which `count.py` *generates* — so the
block stopped matching and the linux job went red on the drift gate. The
diff was one blank line.

This is the recorded class, happening to the person who wrote the register:
a prose edit moving an anchor that code reads. The fix is not to reword the
note but to move it out of the block entirely — it now hangs off the
A-group *definition* bullet, which is prose the generator does not own, and
says so in its last sentence. The generated block was then restored from
`count.py emit` rather than hand-repaired, and the diff against main is 11
added lines and zero deletions: no published number moved.

Two smaller things worth the ink. The local reproduction was available all
along — `python3 spike/unknown-rate/count.py check` prints exactly what CI
prints — and I did not run it before pushing, which is why a one-blank-line
error cost a CI round. And the first fix attempt was not enough: removing
the note left the extra blank line behind, and the check stayed red until
the block was replaced with the generator's own bytes. A gate that compares
byte for byte does not care which of two edits caused the mismatch.

Two claims of my own were caught by the pre-review check on numbers and
universals before this was committed. "On tools with millions of users"
was not measured anywhere — replaced with the star counts #209 actually
recorded. And DESIGN's arithmetic counted Borg twice, once as a probe wall
and once as the verdict that wall became when #200 lifted it: eleven
outcomes for ten targets. Now four walls that stood, one lifted, six
verdicts.

One measurement error of my own, caught by its own denominator: the local
replication of acceptance check 11 printed "1 slashed refs checked" for a
page with 46 of them. `for r in $refs` does not split on newlines in zsh,
so the whole list arrived as one string. The real check runs under `sh` in
the container and was never affected — but had the output not carried its
denominator, "0 missing" would have read as a pass. Re-run properly: 46
checked, 0 missing, with a planted bad path as the control.

## 2026-08-22 — cohort 4's preconditions, and the gate that caught its own author

This entry is late, and says so first: the contract in CLAUDE.md is to open
the entry when the work starts, and four commits of `spike/` landed before
a word of it existed. Written now, before the pull request, with the
reversal it would otherwise have hidden left in.

**What the work is.** Not a cohort — its preconditions. Every mistake
cohorts 1–3 paid for, mapped to the thing that makes it impossible rather
than merely noticed, plus the four gates that make some of those rows
mechanical. No target is named anywhere in it, deliberately: selection is
the owner's, and it comes after the engine change (#231) and the PROTOCOL
freeze that cites it.

**The reversal, which changed the plan.** The first draft read criterion
1's *author-confirmed* leg as the target's maintainer, counted four
upstream reports sitting at zero comments for 7–10 days, and concluded the
gate was blocked on other people. It is not. PRD glosses the phrase —
"this project's author judges the bug real, upstream confirmation is
sought, not required" — and DESIGN scored timewarrior exactly that way,
clean, with this project's own patch at PASS 25/25. `#140` never
contradicted that; its *Live candidates* paragraph just reads as though
the replies were the path. One clarifying line there settles it, and no
criterion changes. What is actually missing, counted from the record: no
single finding has yet been novel, automatically discovered, and
provenance-clean at once — timewarrior lacks the first, topydo and cohorts
2–3 the second, the assisted cohort the third. That combination is what a
fourth cohort is for, and nothing external stands between here and it.

**The exit rule, decided before the cohort rather than after it.** PRD's
default stands: no criterion-1 find, no v1.0, the kill analysis ships
instead. What the analysis should *conclude* on a null is deliberately
left open — with two facts recorded now so they cannot be discovered
conveniently later. A null fires none of §18's eight conditions (its
antecedent, "finds nothing beyond existing hand-written adversarial
tests", is contradicted by the record and `docs/kill-criteria-review.md`
says so), so the document will not produce a mechanical verdict. And the
two fallbacks considered and declined — pre-authorising an assisted-cohort
finding despite its red provenance, and re-measuring an assisted target
under the mini-seal (barred by the criterion's own text) — are written
down, so that choosing one later reads as a change.

**The gates, each falsified before being believed.**

- `spike/merge-gate.sh`. Three merges went out wrong in two cohorts — #184
  with the review fix unstaged, #194 with a red gate, #216 on "no checks
  reported" read as no failures — and they are one predicate now: at least
  one success, no failure, nothing pending, clean tree, local head equal to
  the PR's. Zero checks refuses; a zero denominator is absence of evidence.
  Self-test 7 of 7 against those three shapes and four more, plus a live
  run against a merged PR, which it refused for two independent reasons.
  It deliberately does not merge: chaining the wait to the merge is how
  #194 happened.
- `spike/cohort4/preflight.sh` + `visibility-logger.c` +
  `preflight-analyse.py`. Probe conditions 8 and 9, engine-free. Condition
  8 asks, before any define exists, whether every state-root mutation
  passed through a function an LD_PRELOAD shim can interpose — the
  question cargo answered only after two defines and two explores. On this
  repository's own toys: `toy.c` PASS, `toy_raw.c` WALL naming the
  unmatched `openat`, `renameat` and `unlinkat`. Condition 9 counts kill
  points; the libc toy reports 4. Stated in the header, because a green
  must be read correctly: the path-bearing classes carry the precision,
  and `write`/`fsync`/`ftruncate` are compared by count, catching a total
  bypass but not a partial one.
- `spike/cohort4/novelty-prescan.sh`. Cohort 3 spent black's slot learning
  that the novelty question belongs at selection, not after the verdict.
  Writing the script surfaced a trap worth the exercise: a space-separated
  query returns **zero** through this API — `disk` gives 30 hits against
  psf/black at `--limit 100`, `disk full` gives 0 — so the natural phrasing
  would have called every known defect novel. Multi-word terms are refused.
- `spike/upstream-report-status.sh`, because a table of dates nobody
  re-measures is indistinguishable from a table nobody re-read.

**The gate that caught its own author.** Running the pre-scan against the
two targets cohort 3 actually burned was meant to confirm it and found a
hole instead. psf/black's issues answer eight or more terms; but
`rust-lang/rustfmt#6041` answers exactly two, `disk` and `disk+full`.
Remove `disk` and rustfmt reads as novel — the one verdict the script
exists to prevent, missed by a margin of one word. So the term list is no
longer a matter of taste: it is derived from the titles of issues this
project has already had to find, and `--validate` holds it to them
(black#2479, black#5207, rustfmt#6041, 3 of 3), shown red by stripping
`disk`. Two smaller measurements from the same run: narrowing with
`in:title` is actively harmful — `truncate in:title` returns 0 against a
repository whose known issue plain `truncate` finds — and a broad term
saturates the page limit, four terms returning exactly 100, a floor rather
than a count, with only the top 20 by relevance listed. Saturation now
prints as SATURATED, counts are no longer summed, and the header says the
scan cannot prove absence. The exploratory full scans are not committed:
they were produced by the term list this run replaced, and a transcript
that does not match its script is worse than none.

**Re-read at PR-open, as the contract asks — and the same-class scan
found three defects in this change's own gate.** The scan's question was
which other lists here were chosen by taste rather than derived. The
interposer's function list was one: it omitted the shim's stdio flush
family (`fclose`, `fflush`, `fseek`, `rewind` and variants), which the
shim exports precisely because buffered bytes reach the kernel from inside
libc, past any PLT — #39's class. Any target writing through stdio would
have been called a false wall. The list now comes from `nm -D` on the
built shim, restricted to the mutating set.

Fixing that hid the second one. Descriptor classes were compared by count,
and once the logger emitted stdio flushes, its own 47 writes to stdout
swallowed the raw in-root write the positive control exists to catch — the
row went quiet while the verdict still read WALL from the path classes, so
nothing looked wrong. Descriptors are resolved through `/proc/self/fd`
now, and every class is compared path to path. That exposed the third:
path extraction keyed on the *class* read `write`'s payload as its path
and dropped every write, which showed up as a missing row and a kill-point
count falling from 4 to 3. Extraction is keyed on the syscall name.

After the three, the raw toy is flagged on all five classes with their
exact paths, the libc toy stays green, and the interior count is 4 again.
Worth stating plainly: two of the three were introduced by the fix to the
first, and only the self-test's own numbers showed it — the verdicts never
stopped being correct.

**Order, recorded so it cannot drift** (the owner's, 2026-08-22): the
BUILDLOG entry for #231 opens before its code; the engine separates the
overall earliest from the claim exhibit, tracking the checker-red class
from the invariant bits at world-judgement time rather than by parsing an
invariant's name; acceptance miniaturises poetry (k=2 L0-only, k=4
checker-red, overall earliest stays 2, checker exhibit is 4, the case for 4
replays) with the new assertion shown red once; that merges; **then** the
cohort-4 PROTOCOL freeze writes the new reading down; then targets. The
engine work is another session's, and this file waits on it.

## 2026-08-22 — cohort 3 leaves the language bar

The `.gitattributes` rule written when cohort 2 closed says "a closed
cohort belongs here; add its directory when it closes", and cohort 3
closed this morning, so `spike/cohort3/** linguist-documentation`
goes in. Measured rather than predicted: the cohort contributes
**123,757 bytes of shell across 38 scripts**, and GitHub currently
counts Shell at 359,264 bytes (37.1%) against Zig's 550,992 (56.9%);
excluding the sealed cohort leaves **235,507 bytes of shell — the
live harness, and only the live harness** (acceptance, the MCP
suite, the campaign driver, the rehearsal, the toy builders), which
is what the rule is for: hide the evidence, keep the maintained code
visible. The effect is display-only — checkout, diff, merge,
`verify-assisted.sh`, CI and code search are all indifferent, and
`linguist-documentation` does not collapse diffs the way
`linguist-generated` would.

## 2026-08-22 — the papis verify transcript: the sixth seal, and the ledger is shut

verify-assisted green on papis (define at 22cec73 strictly before
artifacts at 410def6, all four define files byte-identical). Six
sealed records across the cohort — black, rustfmt, poetry, poetry-r2,
papis, and the poetry pair's shared reading — every one of them a
question frozen on main before the worlds that answered it existed.
Cohort 3 is closed: five primaries measured, no bench promotion,
criterion 1 unmet, and the comparison the cohort was built for on the
record. What moves next is not another target in this cohort but the
three things it filed: the poetry manifest prospect behind the
upstream gate, #217's ptrace-grade observer, and #231's claim reading
for the next campaign's freeze.

## 2026-08-22 — papis passes, and cohort 3 closes

PASS, 2 of 2 worlds, crash points 1 + 1 baseline, single process,
reproduced identically twice — and the report matched the declaration
line for line, including the two things a PASS most needs to prove
about itself: it carried the **non-vacuous headline** (`2/2 explored
worlds satisfied the built-in atomicity invariant`, not "the operation
performed nothing that can change the judged state", which would have
meant the shim never saw the rename), and the metadata line disclosed
`fchmodat x1` as observed-and-excluded, exactly where the declaration
said the unjudgeable seam was. The falsification gate fired through
leg E before any world ran. `papis add` stages the whole document
outside the library and moves it in with one `renameat`; the only
crash world the engine can build is the library before the move.

So the cohort closes 5 for 5 measured, criterion 1 unmet, and the
record is the comparison it was designed to be: four tools that
rewrite files in place — black, rustfmt, poetry, poetry's revision —
and one that stages and renames, all under the same engine, the same
discipline, the same seal. What it leaves behind is worth more than
the verdict count: a live upstream prospect (poetry's manifest
destruction, sealed as a minimal reproduction), a named engine wall
with its after-1.0 issue (#217), a claim-reading design gap the poetry
pair exposed and #231 carries into the next campaign, and — from this
last target — a checker whose every leg came out of measurement that
contradicted intuition, plus the reminder that a rejection is only as
good as the invocation it was measured with.

## 2026-08-22 — the papis define: the target that has no interior to crash inside

The cohort's last define, and the first whose declaration expects a
PASS. Papis builds the whole document in a temp directory outside the
library and moves it in with one `renameat`, then `fchmodat`s it to
0755 — and chmod is not a kill point (`OpClass` in `src/contract.zig`
lists open/write/rename/unlink/fsync/truncate/mkdir/rmdir/link/symlink;
`src/oracle.zig` records chmod as *metadata observed*, disclosed and
not judged). So the engine-reachable crash set is a single world: the
library before the rename. An operation with one atomic mutation has
no interior. Declared as such, with the mode seam written down and
deliberately not asserted — restore flattens permission state, so a
mode leg would fail its own baseline (mercurial's `checkisexec`,
cohort 2, applied before the fact this time).

The checker came out of measurement, and measurement contradicted
every intuition I would have coded. Seven library states through
papis's own reader (`pre-define-trials.txt`): **`papis list` exits 0
in all seven** — an rc assertion would be a check that cannot fail; a
document directory with no `info.yaml` is **silently ignored**, so an
orphaned attachment is invisible to the tool; a document whose
attachment is **gone** is listed happily; and a torn `info.yaml` is
loaded with a **freshly generated random `papis_id` persisted back
into the damaged file** — the reader writes. That last one fixes the
checker's shape: every structural and byte assertion runs before the
reader, or the checker judges its own side effect. And `papis doctor`,
the obvious candidate for "documented recovery first", is measured
unusable as one: in a two-document library it falls to the interactive
picker and returns rc 0 having examined nothing, and where it does run
it reports three type errors **on the untouched baseline** and
auto-fixes zero of them. The rule is satisfied by having looked and
recorded that there is none — not by assuming one exists because the
command does. Drills eleven for eleven, attributed; most reds are
surgery-only shapes, rehearsed anyway because an unseen branch is not
a trusted branch.

**Corrected before merge, on R1's findings and one of my own.** The
paragraph above was right that doctor is not the recovery and wrong
about how I had shown it: the trials ran `papis doctor` with **no
selection flag**, so in every two-document library it fell to the
interactive picker and examined nothing — including state E, the
missing-attachment shape built *for* doctor's `files` check, which
therefore never ran once. The measurement was designed around a check
it then prevented from executing. Re-run with `-a`, doctor is worse
than impotent and the rejection is stronger for being fair: it is red
on the **untouched baseline** (six type errors over two healthy
documents, rc 0 while saying so); its one applicable fix prints
"[FIX] Removing file from document" and leaves `files: []` — the
library made consistent by **forgetting the lost data**, which the
cargo and poetry rulings already refused to call recovery; and on a
torn `info.yaml` **doctor itself dies**, rc 1 with an uncaught
AttributeError, which is precisely the damage a repair would exist
for. Four more corrections landed in the same round. **The
"reader writes" claim was unattributable** — the trials ran list, then
doctor, then doctor --fix, then list, and dumped the file once at the
end — so three states were added: no command run (no `papis_id`),
`papis list` alone (a `papis_id` appears — the reader is the writer),
and a second byte-identical torn state whose id came out **different**,
so "random" is now measured rather than asserted. **The mode-seam
argument had the right conclusion and the wrong mechanism**: restore
creates 0755 directories and 0644 files and never chmods, which are
exactly papis's post-chmod modes, so a mode leg is *vacuous* at this
umask and a *false-candidate generator* under a stricter one — not
"fails its own baseline", the shorthand I had carried over from
mercurial's `checkisexec` and was about to propagate to the next
define. **The checker had dropped the probe's entry enumeration**, so
a stray entry, a `probe-doc` that is a plain file, or a dangling
symlink named `probe-doc` (listed by `ls`, denied by `-e`) walked past
every leg; the guard now enumerates and the two legs that branch on
presence read that one answer instead of testing independently. And
the leg-R drill had to change with it: a third top-level document now
trips the guard first, so the drill became a document **nested inside**
`probe-doc` — measured: papis indexes the library recursively, so that
is a document no filesystem-level leg can see and only the reader
reveals. Drills went from eleven to thirteen. Two claims were also
walked back to what the record supports: the trials arrive *with* this
define rather than ahead of it on main (the scout is the part that
predates it), and "every branch rehearsed" is now stated as what a
count says it is — ten of the checker's twenty failure messages seen
red, per-leg red met, "every branch" not claimed. I wrote "nine"
there first, from the shape of the drill list rather than from a
count; the count is what shipped.

## 2026-08-22 — the poetry-r2 verify transcript: the fifth seal, and the papis off switch

verify-assisted green on poetry-r2 (define at 88447be strictly before
artifacts at 89e8ae2, all four define files byte-identical). Both
poetry records — the primary and its revision — now carry the
complete seal, and the pair is what #231 cites.

Scouted papis in the same window, at the slot RESULTS reserved for it
("3 in-process threads; no off switch measured yet"). Papis documents
one: `PAPIS_NP`, whose own docstring says setting it to 0 disables
multiprocessing on all platforms — an env pin, the free apparatus
tier. Measured with the probe's fixtures and the probe's predicates
(`papis/thread-offswitch-scout.txt`): default = 3 threads, 14 clone
lines, 14 pids; **`PAPIS_NP=0` = 0 threads, 0 clones, one pid**, rc 0,
document landed, read-back exact with the wrong-id drill at zero,
determinism green, closure clean. Both forecast legs assert rc and
landing, so a zero cannot mean "died at startup" — the
zero-without-a-denominator trap, closed in the harness this time
rather than in the prose. The write shape it exposes is the opposite
of the cohort's other four: papis builds the whole document in a
temp directory outside the library and moves it in with **one
`renameat`**, then `fchmodat`s the result to 0755. Two state-root
calls, the first atomic — so the expected verdict is a PASS, and the
one seam worth declaring carefully is the mode, which the engine's
restore flattens by design (the cohort-2 hg `checkisexec` lesson: a
checker that asserts a mode fails its own baseline).

## 2026-08-22 — the poetry-r2 verdict: the wound, sealed, and a rule for the next campaign

FAIL, 1 of 3 worlds, reproduced identically twice — the declared
shape to the letter: the empty manifest at crash point 2, combined
invariant, the whole documented recovery chain failing on a config
whose name and version died with the file, and **no noise world in
front** — the evidentiary contrast with the primary that this
revision existed to buy. Recorded and never claimed, per the
FAIL-freeze ruling the define carries on its face. Two additions
beyond the verdict. First, an outside reading of the poetry pair
(relayed by the owner) named the design gap precisely: the cohort
rule promoted the engine's save-one-case behavior into claim
eligibility, so L0 precision noise can mask a real checker red —
correct as cherry-picking prevention, odd as semantics, and
demonstrated cleanly by these two records. Filed as #231 for the
next campaign's protocol (earliest checker-red world as the
mechanical exhibit, or first violation per invariant class —
engine-side case saving plus a contract-freeze check as
preconditions), freezing before that campaign's first contact and
changing nothing in cohorts 1–3: applying it "before papis" was
considered and declined on the record — papis's rename-shaped write
has no maskable world, r2's disqualifier is the FAIL-freeze rule
(its earliest world *was* checker-red), and the only run it would
help, the primary's, is read-frozen. Second, the run-0 lesson from
the primary held: `--work` was mounted from the first run and the
case survived.

## 2026-08-22 — poetry revision 2: the operation that writes only the manifest

Owner ruling (same day as the poetry verdict, order explicit:
poetry-r2 before papis): take up the deferred revision question. The
revision changes the operation — `version patch` instead of
`add --lock` — which is not cargo-r2's apparatus-swap kind, and the
proposals say so up front: the primary's outcome was a claim-reading
structure (lock-first write order puts an L0-only world ahead of the
checker-red manifest world in every run), so the only way the
manifest wound can become an earliest case is an operation whose only
in-root write is the manifest. Measured before writing anything:
`version patch` works under package-mode=false, bumps 0.1.0 → 0.1.1
byte-deterministically, **leaves poetry.lock byte-identical** (no
lock syscalls; version does not participate in the lock's
content-hash — `check --lock` green after the bump), and mutates the
state root in exactly one truncate-plus-104-byte-write. The full
seven-condition probe harness was re-run for the new operation
(committed in the revision dir): conditions 1–6 machine-green, **0
threads, 0 clones** under venv-off — this operation spawns nothing,
cleaner than the primary. Drills nine for nine with the chain's every
branch re-rehearsed in this define's own state (branch rehearsal is
per-define, not per-copied-code — the heal branches are
engine-unreachable here and rehearsed anyway). Version-shaped novelty
round recorded (four terms, nothing named); the destruction round and
control carry over from the primary. If this define FAILs at the
empty-manifest point, the earliest case is checker-red by
construction — the first candidate-shaped prospect of the cohort
where the claim reading and the write shape point the same way.

**Reversed by R1 before merge — the candidacy was never available.**
The frozen charter's own bullet, the one sentence the first draft's
citation skipped: "a FAIL freezes the define — later revisions cannot
produce a criterion-1 claim for that target" (cohort 2's original
adds the reason: the question would no longer precede the answer;
only refusal and UNKNOWN iteration stay free). Poetry reached its
FAIL verdict before this revision existed, so nothing r2 measures can
be a candidate, and the paragraph above was written by an author who
had read the revision mechanics around that sentence and not the
sentence itself — the same selective-citation shape the novelty scan
lesson warned about, one layer up. Owner ruling, on the record in
proposals.md before the freeze: measure r2 to the end as a **sealed
minimal reproduction for the upstream conversation** (one crash
point, one world, checker-red through the whole documented chain —
no noise world in front), recorded and never claimed; criterion 1
moves to a cohort designed with both poetry lessons — write order
and the FAIL-freeze — in front of the first contact. R1's three P2s
also landed before the freeze: the toml's probe-configuration
sentence had inverted the primary's careful disclosure (main legs
ran venv-ON; venv-off is a third delta, promoted from the forecast
leg), the static "124/137 = timeout" legend in the chain-fail red
collided with the frozen apparatus reading (the candidate-shaped
message would have carried the apparatus trigger tokens on every
ordinary red — now the annotation is conditional on the step's
actual rc), and the pass drills printed only their fragment line,
leaving the healing step unattributable from committed evidence (now
full output).

## 2026-08-22 — The scouting guide stops legislating target selection

docs/scouting.md is the public method page, and its "must never" list was
carrying this repository's own governance dressed as method: the ≥500-star
liveness bar, the human sign-off before measured contact, and the flat "a
dormant project is not a legitimate target at all". Those rules decide
which third parties *this project's experiments* touch and who signs off —
they are recorded, with their history, as the owner rule in
`spike/assisted/PROTOCOL.md` — but a reader pointing Sideeye at their own
dormant tool, or a fork they maintain, is squarely inside the tool's
purpose, and no guide sentence should say otherwise. The page also broke
its own opening rule: the intro says numbers on a guide page go stale and
belong in the records, and the one number on the page was the star bar.
The dormant-target bullet is deleted; the upstream-filing bullet keeps the
part that is genuinely method — reporting is decided at selection, not at
discovery — and now says plainly that the bar and the sign-off bind this
repository's experiments, not the reader. Prompted by the owner asking
whose rules those were.

## 2026-08-22 — the poetry verify transcript: the fourth seal

verify-assisted green on poetry (define at 75b3d19 strictly before
artifacts at f35bf72, all four define files byte-identical;
`verify-transcript.txt` committed beside the ruling). The seal
matters more than usual here: this is the target where the frozen
claim rule refused a claimable-looking number, and the sealed order
proves the rule predates the worlds it refused — the chain ruling,
the moved prospect and the claim reading were all on main before the
engine ran. One target remains: papis.

## 2026-08-22 — the poetry verdict: the rule refuses the number I wanted

FAIL, 2 of 5 worlds, reproduced identically across three runs — and
**no candidate**, because the run's earliest violating world is the
empty lock: L0 red, checker healed (chain step 2 brought it back
green, with poetry's self-prescribing step-1 failure observed in a
real crash world for the first time). The checker-red world is real —
crash point 4 empties user-authored `pyproject.toml` and the whole
documented chain fails on the result — but the write shape puts the
lock first, so the L0-only lock world owns "earliest" in every run of
this operation, and the frozen claim rule (earliest saved case must
have the declared checker as its violated invariant) reads the run as
recorded-not-claimed. This is the hg 73/107 shape again, one cohort
later, refused by machinery instead of willpower. The declaration's
miss, on the record: proposals.md predicted every world's behavior
correctly (A heals at step 1, empty lock at step 2, empty manifest
chain-fails — all confirmed by the engine) and still called the
manifest world "the candidate shape", reading only the checker column
and forgetting that L0 fires independently at an earlier crash point.
Candidacy is a property of the run, not of a world. Two smaller
things: run 0's cases were lost to `--work` defaulting inside the
discarded container (transcript and report retained and matching;
runs 1-2 re-measured with the work dir mounted — operator error,
recorded), and the deferred revision question (a manifest-only
operation like `poetry version patch` would put the checker-red world
earliest; new target dir, owner's call) plus the upstream-report
material (the stale prescription; the manifest wound) sit in
`poetry/RUNLOG.md` behind the standing gates. The cohort closes with
papis.

## 2026-08-22 — scout model sensitivity: the metadata gate checks presence, not truth (#221)

Measured whether the scouting method survives a weaker scout: the assisted
five re-scouted, paper-only, by four fresh agents under identical
conditions (Fable 5 control, Opus 5, Sonnet 5, Haiku 4.5 — protocol frozen
as #221 before the arms ran; record in `spike/scout-model-comparison/`).
Outcome: Opus ≥ the control ≈ the committed baseline (and it re-found
calcurse's measured FAIL shape as its P1, independently); Sonnet usable
with gate-catchable misses; Haiku below the bar — wrong determinism calls
on three of five targets, six of fifteen argvs undrivable as written, every
metadata field present throughout. Owner ruling: scouts run on Opus 5 or
better, Sonnet 5 is the measured floor; now stated in `docs/scouting.md`.

Two things this run paid for. First, the contamination probe before the
arms: the workspace memory index turns out to be injected into fresh
subagents, so the cohort-2/3 targets (walls named in the index) were
unusable for comparison and the assisted five carried a disclosed
existence-of-filing leak for calcurse and stow — disclosure was mandatory,
and all four arms located and quoted the same sentence verbatim. Second,
the grader-bias caveat is recorded rather
than solved: the grader is the orchestrating session, same model family as
the control arm, unblinded; the mitigation is that every judgement in
RESULTS.md anchors to committed text, and six load-bearing citations were
opened against the checkouts (six of six matched) before the tables were
written. The wrong-in-hindsight candidate to watch: opus's four
beyond-record findings are static claims — if one of them fails to
reproduce under a probe, the "exceeded the baseline" line above overstates
it by exactly that much.

## 2026-08-22 — the poetry define: the recovery that prescribes itself

Target 4, the first live criterion-1 prospect. The committed probe
strace pinned the write shape: `poetry add --lock` touches the state
root in four syscalls — **lock first, manifest second, both in-place
truncate-and-write** — so the reachable crash states are empty-lock,
new-lock-plus-old-manifest (the lock knowing a dependency the manifest
does not), and empty-manifest. Five engine-free trials fed each state
to poetry's own reader and its prescribed recovery, and they split the
world exactly where a property should sit: the between-writes state
**heals** — `poetry check --lock` names the fix ("Run `poetry lock`"),
and it works; the empty and torn lock states get the same or a worse
answer and **the prescription itself fails** (rc 1), leaving the
project stuck until a human deletes the lockfile — a step no error and
no document names. The drills then measured the punchline: the failing
`poetry lock` on an empty lock **prints "Regenerate the lock file with
the `poetry lock` command"** — the recovery prescribing itself while
failing. The pre-define novelty scan (recorded in proposals.md) found
no issue naming this recovery failure.

The checker follows the cohort rule to the letter: documented recovery
first — poetry prints its own, so leg R runs it exactly once when
check is red, and the prescription failing IS the red. The
green-heal-A drill pins the other side (state A must heal and end
green, with the transcript carrying the recovery line, so a checker
that never ran the recovery cannot fake the green). One wrong-leg
declaration was caught before commit this time, by applying the black
and rustfmt R1 lessons up front: an empty pyproject parses as an empty
TOML document, so it lands in leg R (invalid configuration, failed
prescription), not leg V — the declaration says so, with the trial
table beside it. Drills ten for ten, attributed.

**Reversed the same day, before merge.** R1's novelty-scan finding
(the recorded terms were corruption-shaped while the claimed-absent
finding was recovery-shaped) forced a re-scan with poetry's own error
text as the query — and "Regenerate the lock file" surfaced #1196 and
PR #6753: **the self-prescribing recovery failure was reported in
2019, fixed upstream (in 1.2.2 via backport #6759; main's fix shipped
in 1.3.0), and the fix's own test fixture is the unparseable "This
lock file is broken!"**. Poetry 2.0 then split the
command on purpose — bare `poetry lock` preserves (and so must read)
the existing lock, `--regenerate` carries the #6753 behavior — and
`test_lock_with_invalid_lockfile` pins both halves as intended.
Re-measured in-container: `--regenerate` heals the empty and torn
lock, rc 0, re-check green; on the empty manifest **everything fails**
— the name the rebuild needs was in the file the crash destroyed. Two
consequences, both frozen by an owner ruling before any engine
contact: leg R became a chain (prescription, then the documented
regenerate — a prescription-only red would be a manufactured
candidate that upstream answers with "intended"), and the live
prospect moved from the lock to the manifest: `poetry add` rewrites
user-authored `pyproject.toml` through the same in-place
truncate-and-write the formatter half died of, and no scan term
(destruction-shaped round recorded in proposals.md, control "cache"
2479) finds it reported. The stale prescriptions (`check.py:184`,
`locker.py:358,365` — while `installer.py:270` already routes through
a dynamic `_lock_fix_command()`) are upstream-report material behind
the owner gate, not a candidate. The near-miss to remember: the
original entry's "leaving the project stuck until a human deletes the
lockfile — a step no error and no document names" was **false** — 
`poetry lock --help` documents the way out, and only the second,
recovery-shaped scan was pointed well enough to break the story. The
drills went from ten to eleven — the two lock-red drills became
heal-through-regenerate greens, the empty-manifest red became the
whole-chain red, and one drill is genuinely new: the persistent-red
branch R1 caught as never-rehearsed, fabricated with a missing-README
state measured before the drill was written — every leg-R branch now
attributed by a branch-specific fragment instead of a shared "leg R"
tail. (R2 caught both of this paragraph's original numbers: "fixed in
1.2.2" without the backport attribution, and "ten to twelve" for what
is a count of eleven — the claims-from-open-sources rule, violated in
the very entry that records a narrative reversed by a better-pointed
measurement.)

## 2026-08-22 — the rustfmt verify transcript: the formatter half sealed

verify-assisted green on rustfmt (define at 9faf204 strictly before
artifacts at 8f33bdb, all four define files byte-identical;
`verify-transcript.txt` committed beside the ruling). Both formatter
verdicts — black and rustfmt, two languages, one wound — now carry the
complete seal: questions frozen on main before the worlds that
answered them existed.

## 2026-08-22 — rustfmt's verdict: the second language, the same wound

FAIL, 1 of 3 worlds, crash point 2 — the empty file, the declared tear
— combined invariant with leg V carrying rustc's own E0601, reproduced
identically twice, replayable case committed. Exactly black's verdict
in a second language, which was the point: the owner sent this target
through with its novelty gate already closed (#6041 has named the
surface since 2024) to buy the cross-language proof, and the engine
delivered it in three worlds. The formatter half of the matrix is
done: two languages, one non-atomic in-place write, both current
stables destroyed by a kill between the truncating open and the
write. Nothing filed upstream; the criterion-1 search moves to poetry
and papis, whose trackers name no crash-destruction surface in the
pre-scans.

## 2026-08-22 — the rustfmt define: measured with the answer's fame declared up front

Target 3 proceeds by owner decision (2026-08-22) with its novelty gate
already known closed — rust-lang/rustfmt#6041 has named the in-place
erasure surface since before this cohort existed, and the recorded
pre-define search sits in proposals.md. The define exists for the
ledger's completeness and as black's cross-language companion: same
class, same discipline, a Rust target. The checker differs from
black's where the language differs: leg V is rustc's own front end
(--crate-type bin, so the empty file — the engine-reachable tear, the
same one-truncating-open-one-write shape as black, probe strace lines
51-52 — fails V with "main function not found" rather than parsing as
an empty module), and leg E is a two-anchor byte comparison against
the frozen source and the probe-measured formatted output (Rust has no
stdlib AST to compare cheaply; both anchors are committed
measurements). Drills six for six, message-attributed; green-new
byte-matches the probe's anchor live.

## 2026-08-22 — the black verify transcript: the cohort's first FAIL under the full seal

verify-assisted green on black (define at 413cdb2 strictly before
artifacts at 32ae2fc, all four define files byte-identical;
`verify-transcript.txt` committed beside the ruling). The first
crash-world FAIL of the cohort carries the complete discipline: the
question — including the R1-corrected torn-file reading and the
empty-file drill — stood frozen on main before the world that answered
it existed.

## 2026-08-22 — black's verdict: the engine finds the right thing; the thing was known

The cohort's first full crash-world FAIL: 1 of 3 worlds, crash point 2
of 2 — after the truncating open, before the single write — the empty
file, exactly the tear the define's R1 forced into the frozen reading
and the `E-red-empty-file` drill rehearsed. Combined invariant
("built-in atomicity, and the checker"), oracle-verified, reproduced
identically three times, replayable case committed. A candidate shape
under the frozen reading.

Then the novelty gate did its job: the recorded tracker search
(positive control included) surfaced psf/black#2479 — open since
2021, "black in-place reformat wipes or corrupts target when disk is
full" — the same non-atomic write surface under a different trigger,
with the maintainer-endorsed temp-file fix now pending as
psf/black#5207 (opened 2026-07-01, after the measured stable shipped).
The candidate closes as not novel; nothing is filed upstream. What
stands: the sweet-spot thesis measured — define to checker-red verdict
in three worlds and minutes on the most-used Python formatter, finding
the defect class its own tracker needed five years to converge on. And
one inherited fact for target 3: that same thread names rustfmt as a
direct in-place writer, so rustfmt's novelty gate gets checked before
its define is written.

## 2026-08-22 — the black define: a formatter's in-place rewrite, the textbook shape

Cohort 3's second define (spike/cohort3/black), pushed before any engine
contact. The shape is what this tool was designed around: black rewrites
the user's source **in place** — no temp file, no rename (the probe's
root holds exactly probe.py before and after), and the write reaches the
file through libc (an interposing logger fired on `open64`, the same
2026-08-22 trial in which cargo stayed silent — named trial, the
explore's own recording re-verifies). The property borrows black's own
`--safe` contract and stretches it across a crash: the source must
survive as a program — it parses (leg V) and its AST equals the frozen
pre-operation program's (leg E). Both the unformatted old bytes and the
formatted output are green on both legs; the green-new drill proves the
AST equality live (black's quote normalization does not touch the AST).
The torn-file reading is declared ahead of any world — and the define's
R1 corrected its first draft before the freeze: the probe strace shows
the rewrite is ONE truncating open plus ONE write, so the
engine-reachable tear is the **empty file**, which *parses* (an empty
module) and fails **leg E**, not leg V as first written; a mid-token
tear (a partial write) fails leg V; either way checker-red, a candidate
shape — with no recovery leg, because black documents no crash recovery
and the source is the primary data (the cargo ruling's principle,
applied where no self-heal exists at all; no open decision fork, so
declared rather than gated). Drills six for six after R1 (the empty
file drilled as its own leg-E red), message-attributed.

Recorded here as promised: the previous batch's verify PR (#216) was
**merged while its CI reported "no checks reported"** — the watch
returned before the checks had started, and a chained
watch-count-merge command read pass=0 fail=0 pending=0 as "no
failures" instead of "no evidence". The post-merge CI came back all
green (transcript-and-BUILDLOG diff), so no harm — but this is the
#194 lesson in a new coat: zero is not a verdict without a
denominator, and merge stays a separate command from the poll that
justifies it. This batch's merges are issued only after a non-empty
check list shows failed=0.

## 2026-08-22 — the cargo verify transcript: a wall measured under the full seal

verify-assisted green on cargo-r2 (define at 24e773f strictly before
artifacts at 0fb9a73, all four define files byte-identical;
`verify-transcript.txt` committed beside the ruling) — the cohort's
first engine outcome, a two-layer wall, carries the same mini-seal
discipline the cohort-2 walls did: the question preceded the answer
even when the answer was a refusal.

## 2026-08-22 — cargo r2: the stand-in lifts one wall and finds another — the manifest rename never touches libc

The r2 explore got past the child-thread boundary (`single process` in
its report — the stand-in doing its job) and refused one layer deeper:
`oracle_missed_operation`. The oracle saw the manifest's atomic rename
(`Cargo.tomlI2K6rq` → `Cargo.toml`); the shim — loaded, recording the
operations on either side of it — had nothing. Diagnosis with a
committed transcript: cargo *imports* libc `rename@GLIBC_2.17`, so the
import table decides nothing (an earlier check that concluded "no
imports" had actually measured a missing `nm` binary — the
zero-without-a-denominator trap, caught before it was written anywhere
that matters); a minimal LD_PRELOAD logger interposing rename and
renameat, with python's libc-routed `os.rename` as the positive
control (fires), stays silent through `cargo add` while strace watches
the renameat reach the kernel. **The rename is a raw syscall.** The
two-witness design earned its keep: one witness saw what the other
could not, and the engine refused rather than judging blind.

Ruling (cargo-r2/RUNLOG.md): a named wall, terminal for the cohort —
the operation under study is invisible to a libc interposer, and a
ptrace-grade observer is engine architecture (the after-1.0 family of
#201/#202). cargo's slot closes with its torn-lock question asked and
not answered: the in-place lock rewrite, the parse-failure brick, and
the silent regeneration of an absent lock are all measured and
committed at the edges (drills, diagnosis, probe strace), but no crash
world could be explored to test them. The cohort order continues with
black — whose probe showed zero threads and zero children.

## 2026-08-22 — cargo r1 refuses on the forecast thread; r2 lifts it with a RUSTC stand-in

The first cargo explore refused as the define disclosed it might:
`UNKNOWN child_process_detected (clone3)`, reproduced on a second run
(`spike/cohort3/cargo/explore-r1-transcript.txt`; the reproduction's
machine-readable form beside it as `explore-r1-repro-transcript.txt`). The boundary is the
probe's forecast wearing a different name: the `rustc -vV` child's
internal thread arrives through a raw `clone3` carrying `CLONE_THREAD`,
which the oracle refuses (a thread past the pthread wrapper). A refusal
is not a FAIL — the define is not frozen — so the disclosed, owner-gated
option came due. **Owner approval (2026-08-22): a RUSTC stand-in**,
cargo's own documented configuration, in a new directory
(spike/cohort3/cargo-r2) per the mini-seal.

Measured before writing r2: with the stand-in, `cargo add` completes
rc 0, records the identical manifest entry, and the strace carries
**zero CLONE_THREAD lines** — the boundary gone, the remaining child a
thread-free /bin/sh. `cargo add` and `generate-lockfile` ask the
stand-in for `-vV` and nothing else; **`cargo metadata` asks for a full
target-info probe** (`--print=file-names ... --print=cfg`) and dies at
the stand-in — measured, and the reason the r2 checker carries `unset
RUSTC`: the apparatus reaches exactly the recorded operation, and the
checker's job is stock cargo's reader. Setup's cache-warm metadata call
went for the same reason (generate-lockfile alone creates both caches —
measured). The r2 drills run with RUSTC exported at the stand-in, the
way the engine's environment will carry it, so the green controls
double as the falsification of the unset line. Seven for seven,
attribution unchanged. Stock reproduction stays mandatory for any
finding: real rustc, no stand-in, strace fault injection.

## 2026-08-22 — the cargo define: manifest survival, asked before any crash exists

Cohort 3's first define (spike/cohort3/cargo), pushed before any engine
contact per the mini-seal. The property is **manifest survival**: kill
`cargo add --offline --path` anywhere and the project must still open to
cargo's own reader — leg V (`cargo metadata --offline` parses and
resolves), leg T (the dependency set is old-or-new: depcrate named zero
times or exactly once, metadata agreeing), leg C (source bytes
conserved). The deliberate omission: **no manifest+lock simultaneity
assertion** — the cargo book says the lockfile "is maintained by Cargo
and should not be manually edited", so lock re-sync is cargo's own job,
exercised by running its reader rather than legislated by the checker;
L0 still judges the lock's bytes. The rejected alternative (asserting
simultaneity) would manufacture FAILs out of cargo's documented
maintenance model.

Checker drills: six for six, each red **attributed to its intended
leg** — the drill asserts the checker's message names the leg it was
aimed at (a red from the wrong leg is a drill failure), which is the
mutation-killed-by-the-wrong-test lesson applied to checker
falsification. The torn-manifest drill red carries cargo's own parse
error; the leg-T red is depcrate named twice in *valid* TOML
(dependencies + dev-dependencies) — the one wrong-set shape metadata
happily resolves, so only T can catch it.

Ambient: CARGO_HOME outside the state root, warmed once by setup so
every world *finds* a warmed CARGO_HOME — shared and mutable across
worlds, deliberately outside the snapshot (borg-r3 put its ambient
inside the root; here the caches would be L0 noise), so cross-world
cache drift can only surface as an engine refusal, and that would be
the recorded outcome. The probe's forecast (the per-add `rustc -vV`
child and its internal thread) rides into this define as a disclosed
possible refusal too; the documented RUSTC override stays an
owner-gated option for a revision, not an assumption.

The define's R1 (fresh subagent) found the thing worth finding before
the irreversible step: **the likeliest FAIL shape — a torn Cargo.lock —
had no decided reading and no measurement.** Measuring settled it hard:
cargo writes `Cargo.toml` through temp+rename but rewrites `Cargo.lock`
**in place** (the probe strace had the evidence all along); a lock torn
mid-entry fails `cargo metadata --offline` with "failed to parse lock
file", rc 101, no recovery hint — while an *absent* lock is silently
regenerated, rc 0. My first tear measurement lied briefly: a 60-byte
truncation lands inside the lock's comment header and parses as valid
empty TOML, which cargo happily re-locks — the tear has to cut into an
entry to measure anything. **Owner ruling (2026-08-22): no recovery
leg.** Cargo's automatic maintenance already gets its turn by running
the reader (it heals an absent lock unprompted); a torn lock is the
state where that maintenance refuses to engage, so it is checker-red —
a criterion-1 candidate shape, with claim and report still behind the
standing gates. The `V-red-torn-lock` drill pins the measured behavior
in the committed transcript. Also from R1: the toml's "determinism and
closure for exactly this shape" overstated the probe (the probed
spelling differs from the define's — now named in the comment), and the
recorded dependency entry is now measured and printed by the drills
rather than forecast in a comment.

## 2026-08-22 — cohort 3 probes: five for five, and the bench stays seated

Drills re-proven on the new image, the synthetic positive control split
as required, then the five primaries: **all five hold probes with all
six machine-judged conditions green** — four on their first probe under
the frozen plan, papis under a plan amended after its first probe
failed (kept as papis-v1). First contact proceeded in cohort order, but
the committed transcripts are final-harness re-runs whose timestamps
are not (each header carries its own; all postdate the freeze merge) —
the first draft of this entry said "in frozen order" and the R1 review
caught the claim outrunning the committed evidence. The refill bench is
not activated either way: even reading papis's first probe as its
outcome, four primaries passed, and the rule promotes only below four.
Engine order stands: cargo → black → rustfmt → poetry → papis.

The probe phase earned its keep twice. First, **papis**: the original
plan's probe failed with a network traceback — `papis add` of a local
text file runs importer auto-matching, and the arxiv importer validates
the local PATH against arxiv.org over HTTPS, so a failed fetch fails a
purely local add (measured here as TLS verification dying under the
intercepting proxy — the network was reached; R2 caught this sentence
still saying "unreachable" after the reword landed everywhere else). No config filters the importer set (measured
in the source); `--from` skips matching structurally. One measured
amendment (metadata via a frozen YAML fixture and `--from yaml`),
recorded in the PROTOCOL with `papis-v1.txt` as evidence — the jj
pattern from cohort 2, again. Under the amended plan the determinism
condition also answered the open question: **the fixture's `papis_id`
pins it** — byte-identical libraries across runs.

Second, **cargo**, where a hypothesis died properly: an ad-hoc
measurement said a warm CARGO_HOME removes the `rustc -vV` child (zero
clones on the second run). Wrong — that second run was a **no-op add on
an already-edited manifest**, short-circuiting before the resolver ever
ran; the measurement did not reach the thing it claimed to measure. The
transcript's forecast loop uses a fresh pre-state per configuration and
shows the child (and its internal thread) in both states. So cargo's
define faces one vfork child per add whose thread the shim will observe;
the documented `RUSTC` override is recorded as gated apparatus, not
assumed.

Also measured: poetry's `add --lock` builds a virtualenv (threads) even
though it installs nothing — `POETRY_VIRTUALENVS_CREATE=false` takes the
thread count to zero with only oracle-accountable discovery forks left.
black and rustfmt run thread-free and child-free. papis carries 3
in-process threads, off switch unscouted. One harness anchor was
corrected mid-probe: bare `papis list` prints folder paths, so the
round-trip check now reads the document back through `papis list
--format` — papis's own reading — instead of grepping for a title in
output that never contains one.

The batch's R1 (a fresh context-free subagent again — Codex still out of
credits) returned three P1s, all adopted: the "in cohort order" claim
above (reworded to what the transcripts show); "unreachable network" in
the papis story, when what v1 measured was a *reached* network dying on
TLS verification under the intercepting proxy (reworded — any fetch
failure propagates the same way, but the claim now names the measured
one); and the cargo/poetry `thread_counts` lines printing `inconsistent`
without RESULTS saying so — the pairing assertion assumes only
CLONE_THREAD clones split into unfinished/resumed pairs, vfork splits
too, the machine judge refused fail-closed, and the thread facts came
from the raw logs and the clone-only forecasts (now disclosed, with the
lib.sh limitation named). Its P2s too: the positive control's gate was
fail-open (any red printed "control ok" — now gated on the determinism
verdict specifically, diff rc = 1, everything else green) and the
corrected papis anchor had never been red in its final form (it now
drills itself against a wrong id in the transcript). The affected four
probes were re-run under the fixed harness; black and rustfmt stand.

## 2026-08-22 — cohort 3 opens: the sweet-spot five frozen, with a bench that refills

Selection frozen in #209 before any contact: **cargo → black → rustfmt →
poetry → papis** under the owner's thirteen-condition ruleset (≥1k stars,
6-month activity, sustained contributors, CLI-primary, precious local
plain-file state, no transaction engine, non-interactive mutations,
self-checkable, probe-verifiable observability — plus the sharpened three:
≤1-week maintainer responsiveness measured on real issues, currently used
rather than legacy-only, language diversity). New over cohort 2: **the
refill rule** — a probe wall promotes the bench head (taplo → unison →
sc-im, re-qualified at promotion) until four targets have passed probes,
so a wall costs a transcript, not the cohort.

The plan's adversarial review ran into something new: Codex completed its
investigation (five interim reports, real repo cross-checks) and then the
provider's content filter blocked the final consolidated findings list.
The interim findings were recovered and each re-verified here before
adoption: the verifier lives at `spike/assisted/verify-assisted.sh` (the
plan had the path wrong); `PYTHON_KEYRING_BACKEND` needs the
fully-qualified `keyring.backends.null.Keyring`; black has an official
`--no-cache` (so the cache class is removed, not relocated); papis
auto-generates `papis_id`, so pinning time alone would not make its add
deterministic — the probe plan pins it via `--set` and lets the
determinism condition judge. The truncation is disclosed in the plan as
an honesty note: the findings list may be incomplete.

One defect in the cohort-2 record surfaced during that review and is
recorded here rather than retro-edited there: all five cohort-2 probe run
scripts call `mutating_paths` — a name the fail-closed closure rebuild
renamed to `closure_paths` — in their informational path listing, and the
committed transcripts carry the `not found` line. Display only; condition
6 was judged by `closure_check` throughout, so the verdicts stand. The
cohort-3 run scripts call the defined name.

Freeze-day measurements that moved the plan: the cargo-add manual
promises **manifest editing only**, so "Cargo.lock also updates" was
demoted from a frozen expectation to a measured observation; the Rust
combined tarball carries rustc/std/cargo but **not rustfmt** (channel
manifest, 2026-08-22) — rustfmt rides its own component tarball, both
hash-pinned from the manifest. The Python closure is a uv cross-platform
lock (74 packages, PyPI-published hashes, `--require-hashes` at both
download and install); exactly two packages ship no wheel at their locked
versions and enter as pure-Python sdists: bibtexparser 1.4.4 and
python-doi 0.2.0 — measured by the wheels-only download refusing them,
one at a time.

Two build mistakes, recorded: the first image build failed at the pip
layer — Debian's apt python ships a `typing_extensions` with no RECORD
file, which pip cannot uninstall; fixed with `--ignore-installed` (the
locked versions land in /usr/local, which precedes dist-packages, and
Debian's copies are left untouched). And the failure was initially
invisible because the build command was piped into `tail`, which
swallowed the exit code — the repo's own pipe-hides-rc lesson, re-enacted
and caught only because the versions were measured afterward against the
image that was supposed to exist.

The freeze PR's own R1 (six P1s, all adopted) reversed one of this
entry's paragraphs within hours: the combined rust tarball **does**
bundle rustfmt-preview — the reviewer listed the shipped artifact's own
`components` file, which the earlier "measured in the manifest" claim
never opened (it had read rustup's network component model instead of
the artifact). The separate rustfmt tarball is gone; `install.sh` now
selects its four components explicitly, and the committed evidence is
the artifact's `components` file plus the in-image `rustfmt --version`,
both in `freeze-build.txt` (R2 flagged the first draft of this sentence
for citing an uncommitted build log).
The same review falsified the pins cover guard against its own
predicate — a deleted `--hash` continuation line sailed through the
name==version comparison — so the guard now compares every line, and
`freeze-build.txt` carries the red drill (rc=1 on the mutated copy) next
to the green run. The other adoptions: the refill algorithm is now
deterministic (all five primaries probed unconditionally, in order;
bench refills toward four passes only after the fifth verdict — no
outcome can shrink or reorder the measured set), the probe fixtures are
inlined in the PROTOCOL byte for byte (a "pre-computed formatted form"
for the formatter targets would itself have been pre-freeze contact, so
the formatter oracle is the tool's own `--check` plus the determinism
condition), the positive-control substitution is scoped explicitly
instead of hiding inside an "applies verbatim", and the freeze build's
evidence is a committed transcript (`freeze-build.txt`) instead of
prose.

## 2026-08-21 — the borg verify transcript closes #200: four mini-seals, four greens, still zero claims

verify-assisted green on borg-r3 (define at f508312 strictly before
artifacts at 79bb7bc, all four files byte-identical), the fourth
verify-green mini-seal of the day after hg-r4, jj and bun. #200 closes
with its outcome: the wall was lifted by declared apparatus, the
strongest documented promise in the cohort was asked 118 ways, and it
held every time. The search stays empty-handed and the record stays
honest — which is the only way an empty hand is worth anything.

## 2026-08-21 — Borg's verdict: FAIL 3/119, all three in the cache we relocated, and the contract held everywhere

The r3 explore ran 118 crash worlds plus baseline and reproduced its
verdict identically on a second run: FAIL 3/119, oracle_verified true,
single process, the #190 exclusion visible (fchmodat x3). The reading
writes itself: **Borg's documented transactional contract held in all
119 worlds** — break-lock fired in 14 and succeeded in 14, borg check
passed everywhere, the base archive extracted byte-identically in every
world, the listing was never a third thing. The three L0 violations sit
in `ambient/.cache/borg/<repo-id>/chunks` — the client cache's in-place
rewrite, a file borg documents as deletable-and-rebuildable, judged at
all only because r2 moved it inside the state root so worlds could run.
The all-5a repo id in the flagged path is the pinned urandom looking back
at us — the apparatus working, visibly.

Under the claim rule frozen before the cohort's first explore: a
precision-limit observation, no criterion-1 candidate. That is the
second null-with-verdict of the day, and the stronger one: the strongest
documented crash promise in the cohort, asked 118 ways under pinned
clocks and entropy, and kept 118 times.

## 2026-08-21 — borg-r3: the sendfile rerun, paid for in one line this time

The r2 explore cleared the cache refusal and stopped one syscall later on
`unsupported_syscall_observed: sendfile` — CPython's shutil fast-copy,
the exact refusal hg-r3 met this morning. The lesson was already paid
for: the sitecustomize gains the same one line
(`shutil._USE_CP_SENDFILE = False`), question bytes unchanged, seven
drills green again. hg needed a fork in the road and an owner ruling to
cross this; borg needed a copy of the receipt.

## 2026-08-21 — borg-r2: the client cache is state, and the engine's restore semantics said so twice today

The r1 explore refused `kill_did_not_land`: the engine restores only the
state root, Borg's client cache lived outside it, and after the recording
every world's `borg create` met a cache newer than its rolled-back
repository and refused (rc 2) before reaching any operation the standing
kill could land on. The same class as hg's wcache this morning — state
that decides the target's behavior must live where restore can carry it.
r2 moves `BORG_BASE_DIR` inside the state root, and the checker gains leg
R0: the crashed world's cache is derived state that can legitimately sit
ahead of the rolled-back repository, Borg's documented handling of a
suspect cache is deletion-and-rebuild, so the checker discards it before
reading and answers the two first-contact prompts with the documented env
overrides. Question bytes unchanged; seven drills green again.

## 2026-08-21 — the borg define: the strongest documented promise in the cohort, asked under the declared pins

The define (`spike/cohort2/borg/`, P1 of three proposals): kill
`borg create` over a repository holding a prior archive, and the
documented transactional contract must hold — stale-lock removal
(`break-lock`, exactly when a lock exists), `borg check`, the
pre-existing `base` archive conserved byte-identically, the listing
old-or-new, a new-side content assertion. The launcher installs the
three-piece apparatus (ld.so.preload + FAKETIME x0 + PYTHONPATH); setup
generates the sitecustomize so its bytes are D2-held (the hg-r3 reason).
Seven drills green on the first run — greens as controls, five reds one
leg each, including the leg V/leg C split (a corrupted segment vs a
VALID repo with different base bytes — the case `borg check` cannot see)
and the as-nobody unremovable-lock red. No explore has run.

## 2026-08-21 — #200: the Borg wall falls to a three-piece apparatus, and the issue's premise was wrong twice

The issue predicted one leak (time_end's monotonic duration). Running
found three, each by measurement rather than reading: the monotonic
duration; the manifest's utcnow; and — after both clocks were provably
frozen — the TAM authentication tag's random salt, present even at
encryption=none (found by diffing `borg debug dump-archive` between two
frozen runs: `salt`/`hmac`/`id` were the only moving fields). The
apparatus that pins all three: libfaketime via `/etc/ld.so.preload` with
FAKETIME `@...x0` (realtime frozen; monotonic deliberately left real so
sleeps and timeouts outside borg stay alive — the first frozen round
proved why by hanging in the harness's own gap sleep while borg itself
had finished fine), plus a sitecustomize pinning `time.monotonic` and
`os.urandom` (Python-scoped via PYTHONPATH; the C world untouched). The
urandom pin crossed a line drawn earlier the same day ("crypto randomness
is where we give up") and went to the owner instead of under the rug:
approved, with the distinction recorded — this is an integrity tag's
salt on an unencrypted repository, not encryption, and the
reproduce-against-stock condition already covers any finding.

The harness paid a tuition too: the first frozen round still split, and
the culprit was the probe itself — borg stores the full command line in
the archive metadata, and a harness that runs A and B in different
directories manufactures a split no real exploration would see. The
probe now runs A and B in place at one canonical path, restored from a
pristine snapshot between runs — which is the engine's own restore
semantics, so the probe got more faithful by being corrected. Final
record: control splits (the check can fail), pinned splits (the wall
stands without the apparatus), frozen is six-for-six green.

## 2026-08-21 — the closing verify transcripts: the mini-seal held on all three engine targets

verify-assisted runs green on jj and bun (define strictly before
artifacts, all files byte-identical at both points), joining hg-r4's
transcript from earlier today. Every engine target in cohort 2 now
carries a machine-checked provenance record — including the two that
ended in walls, where the record's value is exactly that the wall was
measured through the same discipline a find would have been.

## 2026-08-21 — both forecasts land verbatim, and cohort 2 closes with five recorded outcomes

The jj explore refused `no_shim_marker` (static binary — the shim never
initialised) and the bun explore refused `multiple_threads_detected`
("Saved lockfile" printed first: bun's own run was fine, the engine's
single-thread contract was not). Both are the exact refusals the probe
phase forecast, both measured binaries are the latest upstream stable so
the wall rechecks are inherent, and both are terminal for this cohort —
the dynamic-jj build stays an open apparatus decision, not a debt.

Cohort 2 is closed: five frozen targets, five recorded outcomes, zero
criterion-1 candidates, every step from selection to walls under the
committed discipline. The honest sentence for #183 is that the search
came up empty and the record proves the search was real. Criterion 1
continues on the standing upstream reports and any future cohort.

## 2026-08-21 — the jj and bun defines land together: two questions written down under standing wall forecasts

The cohort's last two defines ship in one PR, both with their expected
outcomes declared up front from the probe phase: jj's release binary is
static (`LD_PRELOAD` cannot load — a `no_shim_marker`-class refusal at
recording is the forecast), and bun spawns six threads during `bun add`
(`multiple_threads_detected` is the forecast). The defines exist so those
walls are *measured through the mini-seal*, not assumed — and so that if
either forecast is wrong, the question is already committed and the
verdict counts.

jj's checker asks the op-log contract (readable repo, initial bytes
conserved, description list old-or-new, `jj workspace update-stale`
exactly when jj reports staleness), reads with `--ignore-working-copy` so
observation does not trigger the auto-snapshot, and paid two small
tuitions in its drills: the description-list literals forgot the root
commit's empty row (the exact lesson hg-r4's probe already taught — pin
literals, then let the first contact correct them), and
`description("initial")` resolves nothing because jj matches the full
description including its trailing newline — `subject()` is the right
revset, confirmed in-container before trusting it. bun's checker holds
the triple (package.json/lockfile/node_modules) to
old-or-new-or-repairable with re-run-the-install as the documented
recovery, and its poisoned-cache drill (same tarball name, different
bytes) proves the byte-comparison leg is load-bearing. All nine drills
green across the two targets, greens as controls.

## 2026-08-21 — the verify transcript merged through a red gate, because the merge command never looked at the gate

The hg-r4 verify transcript (verify-assisted green end to end: define
strictly before artifacts, all four files byte-identical, the PROTOCOL
provenance attached in oneline form) went to main in #194 — and #194's
buildlog gate was RED, because the PR touched `spike/` without touching
this file. The gate did its job; the operator did not: the CI-polling
loop broke on "nothing pending" and the merge ran unconditionally in the
same command, so a failed=1 that was printed on every poll line was
scrolled past. Two mistakes stacked — the forgotten entry, and a
poll-then-merge pipeline that never gated on failures. This entry is the
missing BUILDLOG paragraph and the record of the bypass; the operational
fix is the obvious one (a merge command must test the failure count it
just printed), and it goes to the session's learning pass, not to another
layer of harness.

## 2026-08-21 — the first cohort-2 verdict: FAIL 73/107, and the frozen claim rule refuses it on schedule

hg-r4 reached the cohort's first verdict, twice identically: FAIL, 73 of
107 worlds, earliest at crash point 16, `oracle_verified: true`, single
process, the #190 exclusion visibly working in the metadata line
(fchmodat x10, utimensat x2). And the reading is the whole point of the
freeze: **every violation is L0-only, and Mercurial's documented contract
held in all 107 worlds** — recover succeeded in all 62 worlds that had an
abandoned transaction, verify passed everywhere, the checker's transcript
carries zero leg failures (the single red leg V line wears the falsify:
prefix, the #134 labeling doing its job). The torn file behind the
earliest case is `dirstate` holding a valid intermediate between its
pre-transaction rewrite and its final one — the multi-write shape, #35's
class, exactly what the protocol pre-declared as "recorded as a
precision-limit observation and never claimed."

73/107 is a seductive number. It would headline. The claim rule was
frozen before the first explore precisely so that nobody — including the
author on a long day — gets to decide after seeing it whether it counts.
It does not count. Mercurial's outcome is a null-with-verdict: the
contract held, the instrument's byte-atomicity form over-fires on files
written more than once per operation, and both facts are now committed
records. Criterion 1 stays open on the upstream watch and the remaining
targets.

## 2026-08-21 — hg-r4: 101 worlds green, and the baseline check earned its keep on a mode that carries meaning

With #190 merged, the r3 explore finally ran the whole campaign: 101
crash worlds, the checker green in every one — the documented `hg
recover` fired in 62 worlds and succeeded in all of them, verify held,
conservation held, the working copy agreed with the store on every line.
Then the un-killed baseline world died to the standing kill and the run
refused with `baseline_run_failed`.

The trace diff told it straight: the baseline ran a longer operation
stream than the recording, because the engine's restore flattens modes
(documented behavior since #121's note) and hg caches the filesystem's
exec-bit answer AS a mode — an executable `.hg/wcache/checkisexec`. Every
restored world silently re-ran the exec probe the recording had skipped,
shifting every operation index; the baseline was simply the world where
the shifted stream reached the kill that is never supposed to land. The
baseline check exists to say "the restored state is not the recorded
state", and it said exactly that about a state whose bytes matched and
whose *meaning* did not.

The r4 fix is define-side and one line: setup removes `wcache` from the
pre-state, so the recording and every world probe from the same blank
slate. Measured outside the engine before committing: with no wcache, a
mode-flattened copy of the pre-state produces a syscall-name sequence
identical to a mode-preserving copy (167 calls, diff clean); the probe's
temp names still differ per run, which the engine already tolerates by
design (classes gate, paths warn).

## 2026-08-21 — #190: the timestamp family joins the metadata exclusion, the decision the code reserved for itself

The r3 explore cleared sendfile and refused one syscall later:
`unsupported_syscall_observed: utimensat` — CPython's copy machinery
touches timestamps once per transaction-backup copy. The full syscall
inventory of the operation against the oracle's sets showed utimensat as
the *only* remaining blocker (ioctl and the stat family already sit in
the read-only list), and the oracle's own comment had reserved exactly
this call: "#121's ruling covered ownership/permission only; widening the
excluded list is its own decision, not a side effect."

The decision came due and the owner ruled (issue #190): the whole family
— `utimensat`, `futimesat`, `utimes`, `utime`, not just the spelling this
cohort hit — joins the exclusion, same shape as #121 option b. Test
first: the new unit test went red on the pre-change engine with the right
attribution (`unsupported = utimensat`, 167/168), then green after the
list change. Two prose consumers were updated with the mechanism, not
found by luck: the same-class scan for the old wording caught acceptance
check 2w-b's grep anchor (which would have gone red in CI against the
widened note) and README's sample report line — the exact
prose-edit-moves-a-test-anchor shape this workspace has paid for before.

The r2 explore ran deep — recording contained, 23 paths under the
pre-or-post form, 6 under history preservation — and refused:
`unsupported_syscall_observed: sendfile`. The strace hunt pinned it to the
transaction's backup copies (`branch`/`dirstate` → `journal.backup.*`,
then → `undo.backup.*`): hg's `util.copyfile` calls `shutil.copyfile`,
and CPython 3.13 fast-copies through `os.sendfile` with no environment
switch (`_USE_CP_SENDFILE` is a bare module global). Adding sendfile to
the shim is a contract change and the contract is frozen.

The fork was real: record the wall and almost certainly end the cohort
empty (jj's release binary is static, bun runs six threads — both
forecast walls), or bend the target's runtime one documented notch
further than the hgrc configs. The owner chose the workaround, r3: a
setup-generated `sitecustomize.py` sets `shutil._USE_CP_SENDFILE = False`
— identical bytes through supported syscalls, verified by a normal run
with zero sendfile calls — declared in the define, the proposals and here,
with the standing condition that any finding reproduces against stock hg
(strace fault injection, the four filings' method) before it is claimed.
This is a private CPython attribute, not a documented interface, and the
declaration says so plainly rather than dressing it up as configuration.

## 2026-08-21 — hg-r2: the first explore died at hello, and the revision rule got its first customer

The first engine run against the merged hg define stopped at a SETUP
ERROR before touching the target: the engine resolves `--state` to an
absolute path before setup runs, and the launcher had not pre-created the
state root — the exact lesson docs/scouting.md already carries ("create
the state root and the report's directory before exploring") and the
calcurse launcher already embodies. The transcript is committed beside
the r1 define (`explore-r1-transcript.txt`, two lines, rc 3).

The fix is one mkdir in the launcher, and it still gets a new directory
(`hg-r2/`): the launcher is D2-held from the define's anchor, an in-place
edit would read as a tuned question at claim time, and the protocol's
revision rule exists precisely so that nobody has to argue about whether
a given in-place edit was innocent. No test explore ran against the
uncommitted fix — an unpushed define that reaches worlds and FAILs would
burn the target's provenance — so the fix leans on the calcurse
precedent and ships to main before the engine sees it again.

## 2026-08-21 — the Mercurial define: the question is written down before the engine is allowed to ask it

Cohort 2's first define (`spike/cohort2/hg/`, P1 of three proposals): kill
`hg commit` anywhere, and the repository is already valid or returns to
valid through the documented `hg recover` — with the pre-existing
changeset conserved and the tip old-or-new at the contract level, never a
third thing. The shape is exactly the probe's (whole-`.hg` root, working
files outside as unwritten inputs, argv-form operation because the date
argument carries spaces), and the launcher pins `HGRCPATH` because the
operation child inherits the engine's environment, not the setup script's.

Two decisions worth their ink. First, the pinned hgrc is **generated by
setup.sh** rather than committed as a loose file: the provenance verifier
holds toml/check/setup/launcher to byte identity and nothing else, so a
loose config would be editable after the fact without D2 noticing — the
same hole R1 found for the launcher at the freeze, closed the same way
(bytes that live inside a D2-held file are bytes D2 defends). Second, the
checker's recover leg has deliberately **never seen a real interrupted
transaction**: manufacturing one by killing `hg commit` before the define
is pushed would observe exactly the failure class the provenance gate
requires the committed define to precede. Its red drill is synthetic (a
garbage journal in a store made unwritable — as nobody, because to root
every permission is a suggestion), and its first live exercise belongs to
the explore's worlds. Every other leg went red separately in
`checker-drills.txt` — including leg C via a *valid* repository with
different rev-0 bytes, the case `hg verify` structurally cannot catch —
with both greens (rolled-back shape, completed shape) as controls.

## 2026-08-21 — the probes ran, two walls fell where predicted, and the frozen jj plan was wrong twice in instructive ways

All five cohort-2 probes ran (engine-free, positive control first — the
unpinned `borg create` split, so the harness demonstrably flags
nondeterminism). Outcomes, transcripts committed under
`spike/cohort2/probes/`: Borg and KeePassXC record the pre-declared
determinism walls (both re-checked against latest stable in committed
transcripts: the fetched Borg 1.4.5 source carries the same `time_end`
code; KeePassXC 2.7.12 is current and its CLI help carries no determinism
option — the randomness is the format's own guarantee). Mercurial, Jujutsu
and Bun pass all six machine-judged conditions, with the ambient evidence
(condition 7) printed in each transcript — Bun's byte-determinism over a
local-tarball `bun add` was the surprise of the day, and it survives
`--network=none`, so the DNS/443 contact its strace showed is optional.

The jj plan needed amending twice, both times by measurement and both
before any explore (the amendment window the protocol allows): the frozen
`.jj` state root failed the closure condition because jj 0.44 colocates
the git store at `./.git` by default (jj-v1 transcript), and the corrected
repo-wide root then split on a single byte run — the reflog line jj's git
export stamps with wall-clock time (jj-v2). `core.logAllRefUpdates=false`
in the pre-state settles it (jj final transcript). The closure condition
caught a wrong frozen assumption on its first outing, which is the best
argument it will ever make for itself.

Three shim-visibility forecasts go into the define phase, each now
measured inside its own transcript: Mercurial's commit path spawns one
thread by default and the forecast table pins the off switch exclusively
(`storage.revbranchcache.mmap=no` → 0; both `worker.*` switches → still
1). The jj release binary answers `ldd` with "not a dynamic executable" —
`LD_PRELOAD` cannot load into it at all, so jj's slot will open on a
`no_shim_marker`-class wall unless a dynamic build is worth the
apparatus. Bun makes six successful `CLONE_THREAD` creations during
`bun add`, and the shim notes every `pthread_create`. Engine order, fixed
before any define: Mercurial → Jujutsu → Bun.

The probe PR's own R1 returned seven P1 and was right seven times: the
"all seven pass" wording claimed machine judgement the harness only gave
conditions 1–5 (closure is now condition 6 in the FAILS counter, seen red
and green in drills.txt with the other predicates); the mutating-path
listing missed most mutating syscalls and the raw strace logs were not
committed (they are now); KeePassXC's runs shared one HOME (per-run
ambient copies now); the transcripts' timestamps contradicted the "cohort
order" claim (the final transcripts are one clean in-order sweep); the
latest-stable rechecks and the linkage/thread forecasts existed only as
prose (committed transcripts now). Two of my own exactness literals were
wrong on first contact — jj's root-commit row and bun's tarball-path
version display — which is what exact assertions are for.

R2 then caught the closure check itself fail-open — a P0, and the exact
class the predicate exists to forbid: strace shows bare pointers where a
target locks its memory, and the extraction silently dropped those calls,
so an empty allowlist still passed. The rebuilt accounting is fail-closed
(every successful mutating call must be attributed or the condition
fails), drilled red both ways (an undeclared write, an unattributable
pointer call) with a green control, and its first honest sweep produced
three corrections at once: KeePassXC gains a second, independent wall
(7 unattributable calls — the memory locking that makes it a password
manager also makes it unauditable to ptrace); the `/var/lib/libuuid`
"finding" dissolved (the raw log shows ENOENT — the old extraction was
counting failed calls); and hg's lock symlinks taught the parser that a
symlink's first argument is content, not a path. Two sweeps of transcript
numbers also disagreed (bun's thread count, 6 vs 4) because the counter
ignored unfinished/resumed pairs — it now counts them with a consistency
assertion, and every number in RESULTS was re-read from the final
transcripts, not from the terminal scrollback of an earlier sweep.

## 2026-08-21 — cohort 2 opens: the claim discipline is frozen before any measurement, and the plan's first draft was wrong three ways

Criterion 1 is the last v1.0 item and its four upstream reports sit
unanswered (calcurse #529 and stow #139 re-measured today: zero comments),
so a second cohort opens rather than waiting. Selection cleared the owner
hard gate today — BorgBackup, Mercurial, Jujutsu, KeePassXC, Bun, evidence
and sign-off on #183 — and `spike/cohort2/PROTOCOL.md` freezes the rules
before any probe or measurement (pre-freeze target contact was install
plus `--version` in the image build, the cohort-1 pre-window allowance;
measured there: borg 1.4.0, hg 7.2.4, jj 0.44.0, keepassxc-cli 2.7.10,
bun 1.4.0, strace 6.13, Python 3.13.5): probe gate first (engine-free, seven pinned
conditions per transcript, all seven or no pass, positive control before
the first verdict counts, and the five probe plans themselves frozen in
the protocol), claim reading fixed in advance (only a saved
case whose violated invariant is the declared checker is a criterion-1
candidate; an L0-only FAIL is a precision-limit observation, the #35
ruling applied cohort-wide), and the mini-seal sharpened to #140's gate
(no explore before the define is on main; a define revision is a new
target directory; a FAIL freezes the define).

The plan's first draft did not survive review, and the reversals are worth
their lines:

- **The checker was designed to judge a scratch copy** on the belief that
  the quiescence double-sample brackets the checker's state access. It
  does not — `main.zig` takes the crashed snapshot and judges L0 *before*
  the checker runs (the stdout capture is what brackets the checker), and
  buku's committed checker already recovery-opens the crashed db directly.
  A scratch copy would also have handed Borg a relocated-repository prompt
  for free. Reversed: checkers run on the crashed state.
- **Borg was slotted as engine target 1** on the assumption `--timestamp`
  pins the archive clock. It pins the start only; `time_end` is start plus
  a `time.monotonic()` duration and lands in the archive metadata (read in
  both `1.4-maint` and `1.4.5` `archive.py`). Byte determinism is expected
  to fail, and the probe gate now exists to buy that answer for the price
  of two normal runs instead of a define and an explore.
- **The noise model overclaimed**: the draft assumed L0 would flag every
  transactional target's uncommitted partials. DESIGN §12 says otherwise —
  one-sided files are unconstrained, append-extended files are judged by
  history preservation — so the claim rule is framed as "how an L0-only
  FAIL is read if it appears", not as a prediction that it will.

Also reversed in review: an in-place define fix can never satisfy D2 (the
verifier anchors the define at its introduction and demands blob identity),
and a delete-and-re-add inside one merge collapses to `M` on the
first-parent line — so define revisions are new target directories, the
only shape that is an `A` event under every merge style. And the
verification transcript cannot ride the artifacts' own PR: the verifier
reads main, so verification is a follow-up PR after the artifacts merge.

KeePassXC moved from slot 1 to slot 4 (owner decision, recorded on #183
before any measured contact): its save is encrypted with fresh randomness
per write, a determinism wall is the likely outcome, and the binding
constraint on v1.0 is the upstream-response clock on a find — walls can
wait, finds cannot.

The first image build failed and taught the build its shape: the
development machine sits behind a TLS-intercepting proxy whose CA the host
trusts but a stock Debian container does not — in-container pip died on
"self-signed certificate in certificate chain" against PyPI, and the curl
steps for jj/bun would have died the same way one layer later — an
inference from the shared trust store, not a measurement: curl was
dropped from the image instead of tested (apt survived because Debian's
default mirror transport is plain HTTP).
Downloads moved host-side into `fetch-artifacts.sh` with committed sha256
pins (PyPI's published digest for the Mercurial 7.2.4 sdist, upstream's
SHASUMS256.txt for Bun 1.4.0, a stated first-download pin for jj v0.44.0),
and the Dockerfile re-verifies every copy so the build never has to trust
the context. The corporate CA stays out of the image and the repository.

The freeze PR's own review (R1, fresh session) returned six P1 and caught
this entry overclaiming in its first form: "frozen before anything is
installed" was false — the image build had already installed and
version-checked all five targets — so the claim narrowed to what the
cohort-1 rule actually allows (install + `--version` pre-window) and the
measured versions moved into the record. Same round: the Mercurial
eligibility ruling now cites its primary source instead of asserting a
sprint from memory; the five probe plans were frozen into the protocol
(pass conditions chosen before any probe can run, all seven or no pass);
pip gained `--no-index --no-deps` so the no-network claim is enforced
rather than hoped; and the launcher's precedence was demoted from "the
verifier proves it" to "read off D3's listing" — the verifier holds
toml/checker/setup only. R2 then showed the D3 reading still cannot catch
a launcher edited between explore and artifacts, so the rule moved once
more: the launcher ships with the define, present at the anchor, held
byte-identical by D2 like everything else.

And straight into the embarrassing column again: the freeze PR (#184)
merged **without** R2's three residual fixes. The commit was cut from the
staged snapshot taken before the R2 round, while the fixes sat unstaged in
the working tree — so the PR body claimed "R2 confirmed closure" about
content that did not contain the closures. The failed branch switch after
the merge is what surfaced it. The fixes land in the immediate follow-up
that carries this paragraph; the lesson is the usual one wearing new
clothes: a claim about the shipped thing must be measured on the shipped
thing — `git diff --cached` after the last edit, not before it.


Straight into the embarrassing column. The freeze-audit page carried a
standing sentence: *"Before tagging, the sweep is re-run and this page
updated for any issue opened or closed since the snapshot — the audit is a
gate, not a ceremony performed once and aged."* PR #178 replaced it with a
report that the re-sweep **had run**, which converts a standing obligation
into a completed one — the exact transformation the deleted clause names and
forbids. Two external reviews of that PR (R1: one P1, two P2, one P3; R2:
CLOSED) did not catch it; they were looking at the snapshot's arithmetic,
the class narrative, PRD's surface count and the CHANGELOG header.

It took hours to matter: filing `#180` (Homebrew install) and `#181` (the
macOS oracle claim resting on `dtruss` alone) left the page reading "nothing
remains" while two unclassified issues sat outside it. Neither touches a
frozen surface on this author's reading — `#180` is release engineering like
`#161`; `#181` adds capability through `--oracle` and `oracle_verified`,
both already frozen and both already shaped to carry it — so criterion 5's
substance is intact and only the bookkeeping drifted. Restored the sentence,
recorded the two filings with that reading marked as the author's rather
than the sweep's, and reconciled "What remains" so that "criterion 5 is met"
reads as a statement about the audit that ran, not a promise that the
tracker stopped moving.

The general shape, worth more than this instance: **when an edit replaces a
rule with a record of having followed it, the rule is gone.** Both readings
of the paragraph look correct in review, because the record is true. What
distinguishes them is tense, and tense is exactly what a diff review reads
past.

## 2026-08-18 — v0.12.0: the re-sweep ships as a minor

Owner decision: minor, not patch — #169 changes verdict behaviour (a
world-only-forking target that previously reached PASS/FAIL now refuses,
exit 2), the same shape that made v0.11.0 a minor. The version moves in
the usual three places (build.zig.zon, src/main.zig, README's quickstart
tarball name — grepped, no residuals). README cross-check against the
release content (checklist step 3.5): the boundary paragraph's two
sentences both stay true under #169 — a world-only boundary is a boundary
the oracle did not confirm, so it lands on the already-documented UNKNOWN
side; the quickstart name is bumped; adding contract-freeze.md to the
docs table is *declined* under the README's cut-only order (adding a row
would need its own owner call, and the PRD link already carries it).
CHANGELOG promoted with one release-time truth edit ("#86 closes with
this change" → "closed with it").

## 2026-08-18 — the pre-tag re-sweep closes the audit: snapshot replaced, resolved rows struck, the freeze declaration moves to its permanent home

Entry opened at the start of the work, per this file's contract. This is the
third and last PR of the re-sweep batch (#169 and #167+#159 landed first —
their entries below); it executes freeze-audit's What-remains item 3 and
closes #86, meeting v1.0 criterion 5.

Decisions, as adjudicated through plan review:

- **The snapshot and the gate's name move in one commit** — the gate's own
  header calls them one trust root. 13 open issues at the re-sweep capture,
  down from 26; the delta is all accounted: thirteen of the original
  snapshot's rows closed (that count includes #159), and four issues were
  filed *and* resolved inside the inter-sweep window — #164 (fixed with
  #27's measurement), #165 (its accidental duplicate), #167 and #169 —
  enumerated by a closed-issue query over the window, because a final-state
  capture is structurally blind to an issue that opened and closed inside
  it (the implementation review caught #164 missing; the query then also
  surfaced #165, which the review had not named).
- **Resolved rows are struck, not deleted.** A struck row (`| ~~#N~~ …`)
  keeps its adjudication history on the page but no longer matches the
  gate's `^| #` anchor — the gate counts active rows only. Review was right
  that the gate cannot prove a struck row is *genuinely* closed (it proves
  set equality of active rows against the snapshot, nothing more); that is
  commit review's job and the page says so, the same way it already says
  the snapshot itself is trusted by review, not machine.
- **The declaration moves to `docs/contract-freeze.md`.** #86's third ask —
  "the freeze itself lands in the docs" — was unmet in the letter: the five
  surfaces lived only on the audit page, which retires at the tag. Review
  (M-8) also caught PRD's normative list still naming four surfaces; it
  names five now and points at the new page as the single normative source.
- **Criterion 6 and #159 are deliberately separated**: the README change
  does not re-run the onboarding clock — the criterion's evidence is the
  pre-change README's measured run, and the audit row says so.

## 2026-08-18 — the text defang learns UTF-8 (#167), and the README says --shim and --work out loud (#159)

Entry opened at the start of the work, per this file's contract. Both are
pre-tag re-sweep adjudications (owner, 2026-08-18): #167 fixes now rather
than deferring, #159's held call resolves as a minimal Usage addition.

Decisions for #167:

- **One classifier, two spellings.** Plan review found the second predicate
  the issue never named: `sanitizeForReport` (the oracle-divergence detail
  route) has the same C0/DEL-only blindness as `appendSanitized` (the
  l0-note/FAIL route). What is shared is the *classification* — which unit
  of bytes gets defanged — not the replacement: the l0 route keeps its
  1:1-or-shrinking `?` (a hostile name must never bloat the report past its
  buffer), the divergence route keeps its visible `\xNN` spelling.
- **C1 is defanged in both encodings.** A raw 0x80–0x9F byte is invalid
  UTF-8 and defangs as such; the *valid* two-byte encoding (C2 80–C2 9F,
  the codepoints U+0080–U+009F themselves) defangs too — an 8-bit-CSI
  terminal interprets either arrival as an escape introducer. This is one
  class wider than the issue's own suggestion (which stopped at invalid
  bytes), and the reason is on the classifier.
- **Real UTF-8 is the guarded regression, and é cannot guard it.** Plan
  review caught the first draft's control: é is C3 A9, whose continuation
  byte lies *outside* 0x80–0x9F, so a lazy byte-wise widening would pass
  it. The controls are À (C3 80) and € (E2 82 AC) — continuation bytes
  inside the C1 range — plus 0xFF as the invalid-but-not-C1 independent
  pin. Any other invalid byte defangs one byte at a time (resync).

Measured: unit 167/167 native (one new test covering both routes and both
spellings). Seen red by mutation: `defangUnit` replaced with exactly the
lazy byte-wise widening the test exists to kill — 166/167, the only
failure is the new test itself ("the defang classifier covers raw C1,
encoded C1 and invalid bytes, and spares real UTF-8"), on the À/€/0xFF
controls. Reverted, green again.

## 2026-08-18 — a world-only boundary refuses (#169): the recording's clearance cannot cover a boundary the recording never crossed

Entry opened at the start of the work, per this file's contract. The pre-tag
re-sweep classified two issues filed since the 2026-08-17 snapshot; owner
adjudication (2026-08-18): #169 fix, #167 fix, #159's held call resolved as
a minimal README addition — all three land before the tag, then the snapshot
is replaced and #86 closes.

Decisions for #169, as adjudicated through plan review:

- **No new `unknown_reason`.** The refusal reuses `boundary_without_oracle`
  — the issue itself calls the missing refusal "the per-world analog of
  `boundary_without_oracle`", and the token's meaning (a boundary nobody's
  oracle accounts for) applies verbatim: worlds run with no oracle at all.
  The recording-time and world-time refusals differ in `message`, not in
  token, so the schema's closed set does not move — which also dissolves
  the "extend the schema before the freeze" pressure the first draft had.
- **The account is written before the refusal.** Replacing the
  processes-note update with a bare `unknown()` would have shipped a JSON
  whose `processes` field still said "single process" under a refusal
  naming a world boundary (review catch). Order: note first, refuse second.
- **The existing world-only checks: one inverts, one is deleted.** The
  quiet-checker check (exit 1, tolerated-with-observation) inverts to the
  refusal — that inversion *is* the fix's red/green pair. The arming check
  (capture contamination observed) would die silently, because the refusal
  now fires before the capture observation. The first draft migrated it to
  `TOY_FORK`; implementation review caught that the migrated copy was a
  byte-identical re-run of the check directly above it (same toy variable,
  same contaminating checker, same predicates) — the #46 machinery is
  already pinned on the tolerated side, so the world-only arming check is
  deleted with a note, not migrated.
- **The `crossed_boundary=true` window stays, documented.** Review pressed
  to refuse every world boundary; declined as adjudicated scope — ADR 0002
  already accepts the world-divergence window with its cost written down
  (closing it means an oracle on all N+1 worlds), and refusing every
  boundary would unmeasure legitimately-forking targets. ADR 0002 gains
  the clarification instead.

Measured (container, aarch64-linux cross build): full acceptance 150 ok on
the fix — the inverted world-only check green (exit 2,
`boundary_without_oracle`, the world-story `processes` account in the
JSON, the pre-#169 tolerate wording absent from text and JSON both). Seen
red by mutation, twice: first pass removed only the `unknown()` call (note
kept) — the suite failed on exactly one check, "world-only boundary
refusal: exit 1", the full-verdict FAIL headline in its output. Review
correctly objected that this is not the *exact* pre-#169 behaviour (the
note differs) and that the first draft's old-wording negation grepped for
the old *check's* echo text, not the old report wording — both fixed: the
negation now targets the report's own pre-#169 wording ("observed for
quiescence only", text and JSON), and the mutation was re-run with note
AND refusal both restored to their pre-#169 forms — the suite fails the
same single check, on the exit code (1, the full verdict; the old-wording
negations sit later in the predicate chain and guard the narrower
regression where the refusal stays but the tolerate wording returns).
Reverted; unit 166/166 native.

## 2026-08-18 — the last pre-tag narrowing: macOS says its widest limit out loud (#10), and two old issues turn out to be already answered (#6, #12)

Entry opened at the start of the work, per this file's contract; decisions
recorded as they land.

The batch picked #6, #10 and #12 together. Measuring before implementing
reclassified two of the three:

- **#6 (the oracle reads any quoted string as a path) is already fixed** —
  ADR 0006's Context names the issue's false-positive verbatim ("a
  `write(1, "/tmp/s/x")` whose buffer merely contains a state-directory
  string is read as touching the state directory") and the typed resolver
  closed it: `write` is classified, therefore an fd syscall, therefore
  scoped from its descriptor annotation only. The named unit pin exists
  ("a state-directory string inside a write buffer is not scope"). What
  remains of `touchesStateDir` is the conservative whole-line net for
  *unclassified* syscalls, and that route only ever refuses (`unsupported`)
  — fail-closed residue, deliberately kept. Plan: mutation-check the pin
  once (attribution fixed with `zig test --test-filter`, not the build
  graph — build.zig does not forward `b.args` to the test artifact), close
  as measured already-fixed, scoped to the named classified-write case.
- **#12 (the omamori dogfood cannot be agent-driven) is already recorded**
  — PRD's v0.4 status carries the full account (guards fire for a human at
  a terminal exactly as for an agent; measuring one would need break-glass,
  which removes the defence under test; out of scope on discipline), and
  DESIGN says "not measured either way". The close is the documented
  by-design decision, not a fix — the plan review (R1 M-4) caught the draft
  calling it "measured covered", which claimed a measurement nobody made.
  One sentence generalising the audience assumption goes on scouting.md.
- **#10 executes as adjudicated** (class A-adjacent narrow), wider than the
  audit's docs-only wording by owner decision: the `no_shim_marker` detail
  line gains a macOS-only clause naming an Apple-shipped platform binary as
  *one possible cause* — not the first suspect; the review (R1 M-1) killed
  the attributing form, since `no_shim_marker` proves only that `shim_ready`
  never appeared — and the macOS CI job gains a permanent pin (R1 M-2:
  a one-off local measurement is evidence it printed today, not a
  regression pin): exit 2, `unknown_reason` == `no_shim_marker`, the macOS
  clause present, the JSON `message` contained verbatim in the text (a
  containment check, not an extracted-line equality). The Linux wording
  stays byte-identical (comptime branch), so no existing pin moves.

Measurements, as they ran (all on the dev Mac, aarch64-macos):

- **#6 pin mutation**: `zig test --dep contract -Mmain=src/oracle.zig
  -Mcontract=src/contract.zig --test-filter "a state-directory string inside
  a write buffer is not scope"` — green on HEAD (1/1, raw rc 0). Mutating
  `isFdSyscall` to `return false` (dropping every classified fd syscall into
  the whole-line net): the *same filtered invocation* fails 0/1, raw rc 1,
  and the failing assert is the pin's own `classes.items.len == 0` — the
  issue's exact defect shape, attributed to the named test, not to some
  other member of the suite. Reverted; green again; `git status` clean on
  `src/oracle.zig`. First attempt at the single-file invocation failed with
  "no module named 'contract'" — `@import("contract")` is a build-graph
  module, so the direct form needs `--dep`/`-M`, which is also why the
  attribution cannot ride on `zig build test` (build.zig does not forward
  `b.args`).
- **#10 diagnostic, measured on the real binary**: `sideeye explore --state
  <scratch>/state --operation /usr/bin/true --check /usr/bin/true --work
  <scratch>/work --json <scratch>/report.json` against `/usr/bin/true`
  (an Apple platform binary): exit 2, `unknown_reason` `no_shim_marker`,
  the macOS clause on the detail line, and the JSON `message` contained
  verbatim in the text output (checked by substring, one detail line).
  `preflight` was the first attempt and refused `--json` by design
  ("preflight has no machine-readable form"), so the CI pin uses `explore`.
- **Seen red once — per predicate, not per script** (the implementation
  review caught the first pass claiming the guard falsified when only one of
  its four predicates had been): *clause* — the same script against a build
  with the branch stashed fails "the macOS clause is missing from the JSON
  message", raw rc 1; *exit code* — the same script pointed at a self-built
  toy-bug (which FAILs, exit 1) fails "expected exit 2 from an Apple
  platform binary, got 1", raw rc 1; *reason token* — pointed at a run whose
  checker never falsifies (a real UNKNOWN, not a doctored file) it fails
  "unknown_reason is 'checker_not_falsified', wanted no_shim_marker", raw
  rc 1; *containment* — the one synthetic input: a green run's report.json
  with a doctored text.out fails "the text report does not carry the JSON
  message verbatim", raw rc 1. Each failure is the named predicate's own
  message. The step also re-ran extracted from the workflow YAML (what the
  runner will actually execute after dedent): green, raw rc 0.

**The pin's first CI run refuted its single-path assumption.** Local green,
runner red: on the `macos-26-arm64` runner the same `/usr/bin/true`
invocation answered `recording_run_failed`, not `no_shim_marker` — dyld
*terminated the target* ("inserted dylib ... incompatible architecture
(have 'arm64', need 'arm64e')") instead of stripping the insertion
silently the way this dev machine's macOS 15 does. "An Apple platform
binary cannot be observed" is true on both; *how* it refuses is
OS-dependent, and the macOS clause never prints on the terminate path
(it lives on the `no_shim_marker` detail line). The step is now two
measurements: the platform binary pins only the refusal fact (exit 2,
never a verdict), and the clause's four predicates moved to a self-built
hardened-runtime binary — `zig cc` noop, `codesign -s - -o runtime`,
flags `0x10002(adhoc,runtime)` — where the insertion is ignored silently
and the run answers `no_shim_marker` with the clause (measured locally;
the same predicates, so the per-predicate reds above still hold — the
new second `[ "$rc" = "2" ]` is the same predicate form whose red the
toy-bug run produced). target-classes now records the two measured
refusal paths by OS instead of implying one.

**And the replacement was refuted the same way one push later.** The
hardened-runtime carrier claimed "ignored silently on every measured OS" —
technically true with one OS measured, exactly the claim-exceeds-
measurement shape — and the runner promptly measured the second OS the
other way: on `macos-26-arm64` the ad-hoc `runtime`-flagged noop *accepted*
the insertion (the shim loaded, ran, and the refusal came one detector
later as `completeness_not_verified`). Both dyld behaviours are
OS-dependent, in opposite directions. The clause carrier is now the
deterministic synthesis of the marker's absence, dyld's mood not invited:
a decoy dylib that never writes `shim_ready`, handed to `--shim` — whether
it loads or not, the marker cannot appear, so `no_shim_marker` and the
clause follow on any OS. Measured locally through the extracted-YAML form
(exit 2, token, clause, containment — same four predicates, reds standing);
this is the same synthesis philosophy as the MCP doctored-response red.

Entry opened at the start of the work, per this file's contract; decisions
recorded as they land.

#150 as adjudicated (relabel to explored worlds, sweep the greps first) —
and the plan review found the same mislabel on the PASS headline, which the
issue never named: `PASS {explored}/{explored} crash worlds satisfied...`
counts the baseline too, and the public records quote it (taskwarrior's
12/12 against an 11-operation oracle account, the onboarding clock's 4 of
4). Owner decision: both verdicts in this PR — fixing the FAIL line while
knowingly leaving its twin would be the same defect with a paper trail.

Three more review-driven decisions, taken before code: the headline tests
compare the printed numerator/denominator against the same run's JSON
`violations`/`explored` (a wording-only pin passes an implementation that
"fixes" the denominator to crash points); the MCP transport-contamination
check drops its prose anchors — which would have needed to chase this very
relabel — for an exact match of `content[0].text` against a reconstruction
from `structuredContent`, self-falsified by feeding the same predicate a
doctored response; and #157 is pulled forward by owner decision (the same
overtake shape as #58) as one typed `pin()` used by both the seven real
oracle_verified pins and a synthetic string-"True" rejection, so the red
cannot drift from the predicate it falsifies. #156 stays deferred — the
audit accepted the permanence trade explicitly, and nothing new argues
against it; the issue gets an out-of-band note, not code.

The sweep taught two lessons on its first container run. First, a
classification error of mine: dogfood-todoman.sh looked like current
apparatus, but its define bytes are hashed by the frozen unknown-rate
sweep — relabeling one word in a comment broke the corpus digest
(check 12 caught it immediately; the file is reverted and reclassified
as frozen evidence, stale wording being the price of the freeze).
Second, the reverse collision the grep-for-old-text sweep cannot see:
`grep -o 'explored [0-9]*'` matches ZERO digits, so the relabeled PASS
headline's "explored worlds" started matching an extraction that had
only ever seen the "explored N worlds" line, feeding it an empty value.
Sweeping for consumers of the old wording finds half the problem; the
other half is old patterns that newly match the NEW wording. The
extraction is anchored to the unit word now, and the only other
output-parsing pattern in the suite anchors on l1's unchanged phrasing.

## 2026-08-17 — v0.11.0: the day's four batches ship as one minor

Owner-selected minor over patch: the release carries a required new report
field (`oracle_verified`), a new refusal (`unsupported_state_entry`), and an
expansion of what L0 judges (dir-to-dir pairs) — surface additions, not
repairs only. Three version spots moved together (build.zig.zon, main.zig's
banner constant, the README quickstart tarball name); the v0.10.0 strings
that remain are the SIGILL incident's historical records and stay. The
first push of this bump forgot this very file and the buildlog gate caught
it — the gate doing for the journal exactly what it was installed to do.

## 2026-08-17 — the demotion was the easy half; the review found the classifier that would never produce the entry to demote

#5, the audit's last tag-gating fix, measured before written as usual: the
issue's symlink half was stale (#122 restores links, dangling included), and
the live half was `restore`'s catch-all silently dropping `.other`. The
plan-stage adversarial review then found the hole under the hole, a Critical
worth the name: `.other` only exists when `d_type` says so. On a filesystem
that answers `DT_UNKNOWN`, the fallback probed by `open(O_RDONLY)` — which
*hangs forever* on a FIFO with no writer, reads a socket's failed open back
as `.missing` (silently absent from the snapshot), and slurps a readable
device as a regular file. A demotion wired downstream of that classifier
closes #5 in a shape that quietly does not exist on exactly the filesystems
most likely to carry special files. The entrance got repaired first:
`statx(AT_SYMLINK_NOFOLLOW)` on Linux (std binds no libc stat symbol there —
glibc's are versioned aliases; the syscall layout is std.os.linux's to keep),
`std.c.fstatat` on Darwin (where std resolves `$INODE64`), no open, no
follow, and posix.zig's old "stat is unusable here" comment carries the
dated correction: true of hand-rolling, not of what std ships. A real-FIFO
unit test pins all five kinds; a regression to probing would surface as a
test timeout, which the test says out loud.

Two process notes, both cheap and both mine. The first cross-build failure
hid behind a pipe: `zig build ... | tail -1` reports tail's exit code, and
the "success" I read was the pipe's — the stale binary then sailed through a
whole rehearsal answering exit 1 with the demotion nowhere in it. The known
gotcha, performed anyway; raw `rc=$?` on the bare command found `std.c.fstatat`
being `void` on linux-gnu in one look. Second, `E.init` was remembered, not
read — the 0.16 idiom is `linux.errno(rc)`, and the compiler said so on the
first try, which is what the discipline is for.

The three reds are one per detection site because one red proves one call
site: setup-created FIFO (initial), TOY_MKNOD on the no-oracle path (final —
under an oracle the defined-list refusal keeps precedence, pinned by the
untouched 2w-b control), and TOY_MKNOD_TRANSIENT (crashed: mknod invisible,
the remove's unlink a kill point, the world killed between them holding the
FIFO). The symlink discriminator doubles as the green control through the
same apparatus; a newline-named FIFO pins the defang with the forged-line
predicate self-falsified each run against a synthetic raw-shaped line.

The diff review sharpened three edges of the first cut. The classifier
collapsed every syscall failure into "absent" — ENOSYS under an old kernel
or EPERM under seccomp would have deleted a real entry from the snapshot and
routed it around the very refusal being added; only a genuinely-gone path
answers `.missing` now, everything else fails the snapshot loudly, and the
`statx` type mask gets the check std's own doc demands. The crashed-site
refusal sat between the capture's two quiescence samples, so a
still-writing world with a stable FIFO would have refused as the FIFO
rather than as itself — moved below the second sample, restoring the stated
order. And the world loop's last iteration is the un-killed baseline: an
entry only IT leaves (pinned with a flag-file toy whose mkfifo is rotate's
last act, reached by no killed world) now reads "left by the baseline
re-run", not a fictitious crash. The both-platforms unit claim was also
trimmed to what was actually run where.

## 2026-08-17 — the checks that could stop looking, and the class that gets named instead of judged

#58, fixed ahead of the audit's "defer" with the owner's approval (the same
overtake shape as #26, and the audit row carries the same dated correction):
`assert` in a judgment is a check that can be turned off from the outside —
`PYTHONOPTIMIZE=1` strips it and the suite keeps answering green with only
exit codes examined. The counts were re-measured before touching anything
(the issue's 18+3 was stale): five live asserts in the explore suite,
twenty-two in the MCP suite, and one more in the quickstart workflow the
issue never named — the same-class sweep over every committed `*.sh`/`*.py`
found nothing else (the replay suite was converted back when the defect was
first caught there). The conversion is the replay suite's shape verbatim;
the hole was demonstrated once on falsified input before converting, and
the completion bar was raised from "a representative red" to running both
suites end to end under `PYTHONOPTIMIZE=1` — 142 ok and all-passed, so the
judgments demonstrably still look when the switch that silenced them is on.

#39 executes the audit's narrowing, and the writing job turned out to be
about measurement tiers, not platforms: the class's two demonstrated
members carry different evidence (stdio probed on macOS too — ADR 0005's
dyld line; remove(3) measured on Linux only), and the first draft's flat
"measured precedent" would have promoted an inference to a measurement.
The committed sentence separates probed / measured-on-Linux / unmeasured,
and states the macOS consequence for the unmeasured members as mechanism
inference. The issue stays open on purpose: its body is the family's
lookout post, and closing it would orphan the fix pattern it carries.

## 2026-08-17 — the capture joins the quiescence observation, and the straggler that motivated it cannot be built

#46, measured live before implementing (twice bitten by stale issues this
week): the world loop's quiescence double-sample covered the state directory
only, and `stdout-world.txt` — L1 evidence — was read exactly once, by the
marker scan. Then the plan-stage measurement closed the door on the issue's
own reproduction idea: a real straggler cannot be manufactured. The oracle
flags any non-primary `setsid`/`setpgid` as a boundary (oracle.zig, the
"visible nowhere else" comment) and refuses before the quiescence code runs,
and a child that stays in the group cannot outlive `kill(-pgid)` by more
than scheduling noise. The committed red apparatus is therefore the
checker: `--check` runs between the two capture samples, so a checker that
appends to the capture lands its bytes exactly where a surviving writer's
would — deterministic, and it exercises the guard's own predicate (fp1/fp2
disagreement), not a lucky race. Measured pre-fix in the container: the
append sat unread in the capture while the run reached exit 1.

The external plan review found the hole beside the hole: arming was
recording-global. A toy that forks only when `SIDEEYE_KILL_AT` is set (so:
in every world, never in the recording) reached a full verdict pre-fix with
the report's processes line reading `single process` — the recording's story
spoken over worlds that each crossed a boundary. Arming now includes the
world's own trace evidence; whether such a world should refuse outright
(nothing oracle-shaped ever accounts for it) is deliberately not decided
here — filed as #169, because it changes verdicts.

Shape decisions, each with its reason: one `observeCapture` read produces
both the marker verdict and the fingerprint, so the two claims cannot come
from different bytes; the read is bounded by the size measured at open,
because a live writer must never be able to keep the observer chasing EOF
(the hang would replace the refusal); the digest is Blake3, because the
bytes are target-chosen and a same-length rewrite must not be able to keep
a cheap checksum; the refusal reuses `state_not_quiescent` (the closed set
is a frozen surface) with a capture-naming message, which is also what lets
the acceptance red attribute its kill to this check and not the state-dir
one. `fileContains` lost both call sites and is gone — its straddling-marker
test carried over to the new observation, on pid-unique paths this time.

The diff review (R1) then found two real holes in the first cut and one
overclaim. First, the bounded read could be blinded by a truncate: measure
size B, read b < B after a concurrent shrink, and the stored fingerprint
says b — so a later honest size-b sample with the same bytes compares
*equal*, and the change observed mid-read evaporates. The observation now
records both the measured size and the bytes actually read, equality
compares both, and reaching EOF below the measured size is its own refusal
predicate (`sawTruncation`) at every armed comparison — on a regular file
that shape cannot happen without a concurrent writer. Second, the processes
line kept telling the recording's story: a world-only boundary armed the
observation while text and JSON still said `single process`. The note now
corrects itself before any refusal can fire, and a fourth acceptance case
pins the corrected account on the quiet world-only run. Third, the
CHANGELOG draft claimed "a still-live writer surfaces as a refusal" — more
than two samples can promise (a writer that pauses between them passes);
narrowed to what is measured. R1 also named the honest limit of the
committed reds: they all write `stdout-world.txt`, so the recording-side
comparison has no end-to-end pin — nothing external executes between its
two samples, the same structural exclusion as the straggler itself. Its
seen-red is a mutation, run once and reverted: inverting the recording
comparison flips the green control to `state_not_quiescent` with the
recording-specific message, which is the wiring-and-attribution proof the
suite cannot carry.

## 2026-08-17 — a hostile file name forged a report line on demand, and the fix defangs the text while the JSON stays as it was

#26, measured before fixed: a state file named with an embedded newline
(`log`, newline, `not tested  nothing`) drove a real exploration to FAIL
under the strace oracle, and the pre-fix text report printed the second half
as its own line — a forged `not tested  nothing` sitting where a verdict
line sits. The apparatus taught its own lesson first: the obvious shell
script driving rm/mv is refused as `child_touched_state_dir` (children have
no crash-point address — the refusal doing its job), so the committed check
drives the unlink/rename in-process from python. The fix is three operands
wide and display-only: `after_path`, `before_path` and `path_shown` reach
the text through the l0 note's existing defang predicate (one predicate, not
two that drift), while the JSON block keeps reading the raw variables —
`jsonString` behaves as it always did (controls escaped, invalid UTF-8 to
U+FFFD, so a valid name round-trips exactly), and the acceptance check pins
both sides plus the round-trip, with the forged-line predicate falsifying
itself against a synthetic forgery on every run. `?` and not a hex spelling on
purpose: one byte in, one byte out, so a hostile name can never bloat the
report past its buffer and erase the counterexample it names. This overtakes
the audit's same-day "document" adjudication for #26 with the owner's
approval, and the audit row carries the dated correction. #35 rides along
as adjudicated: the scratch-file pattern (git's COMMIT_EDITMSG, measured
2026-08-11, thirty-four worlds, fsck accepting every crash world) joins the
checker cookbook's failure-patterns list, and the issue closes as
documented.

## 2026-08-17 — the audit adjudicated a fix for a hole that was already closed, and the measurement found the real one next door

The freeze audit classified #27 as class A, "fix before the tag" — and the
audit's own sweep had just caught #13 being stale, so the lesson was on the
table and still didn't transfer: the sweep checked open/closed, not whether
an open issue's defect still existed at HEAD. It didn't. #122's pair rule
(kind and content compared together) closed #27's named window two days and
twenty-eight commits before this branch's HEAD (38e1186, 2026-08-15); the
plan-stage measurement — write the issue's own scenario as pins through the
real classify+judge path, run them against HEAD — came back green on the
first run. The pins stay, one test fn per pin so a mutation reports each red
individually (the first round used one shared fn and its single failure
masked the rest — that round's numbers were unobservable and are not
claimed). Measured on the split tests: a kind-blind mutation (both kind
checks removed from the standard arm) reds five tests — the three empty-side
#27 pins, #164's file-replacement pin, and the #122 symlink test — and
spares the non-empty control, which keeps rejecting on content alone. The
audit row, PRD and the unreleased CHANGELOG entry carry dated corrections
rather than silent rewrites; the tag gate shrinks to #46 and #5.

The measurement's real find is the adjacent gap the issue never named:
`classify` skipped every dir-to-dir pair as "nothing to compare", so an
empty directory present in both clean runs had no witness at all — a crash
world could replace it with a file or delete it and PASS stood. Filed as
#164 (the class-A shape, joining the audit table at the pre-tag re-sweep)
and fixed in the same change: the skip is gone, the pair enters under the
standard two-sided rule, and reintroducing the skip as a mutation reds four
tests (the three #164 pins and the #122 kind-change control). The restore
prerequisite went loud with it — the directory mkdir was the only creation
whose failure was ignored, harmless exactly while empty directories were
unjudged and a tool-manufactured `missing` the moment they are judged. Review
then killed the EEXIST tolerance the first version carried: the root never
appears in restore's entries (walk records children only), so an existing
directory there has no legitimate source — tolerating it would let world k
judge world k-1's residue through deleteTree's one silent path. Strict now,
and the guard has its own falsification: a parentless dir entry must refuse,
and silencing the mkdir as a mutation reds exactly that one pin. Same-day
process notes, recorded because they cost redos: the first mutation round
was reverted with `git checkout` on a tree whose base was not yet committed,
which threw away the implementation along with the mutation — the second
round committed the base first. And the batch's own filing tripped GitHub's
closing-keyword parsing twice in one day (#27 accidentally closed the same
day by the merge-commit prose `fix #27` — reopened within fifteen minutes
with the accident named; then a shell precedence slip filed #164's text
twice, #165 closed as the duplicate) — keyword-shaped issue references now
travel in code spans, the one spelling GitHub's autolinker is measured to
skip (entities and backslashes are not — the workspace learned that on the
org migration).

## 2026-08-17 — the freeze audit: twenty-six issues against five surfaces, and nothing deferred under an intact PASS claim

Criterion 5's audit ran as #86 wrote it: sweep first (committed snapshot,
2026-08-17T00:33:15Z — the set includes issues filed the same day, three of
them under half an hour before the capture, and excludes #87, closed
seventeen seconds before it; recalled, the table would have missed both
edges), classify every row, decide every toucher.
The completeness gate is check-12-shaped — a script, run at each sweep
rather than wired into CI, checks the table against the snapshot and judges
a one-row-deleted copy of the page on every run, demanding red there. Ten of twenty-six touch a frozen surface. The class-A
adjudications are the owner's, taken 2026-08-17 with recommendations visible:
fix #27 (the L0 kind hole is a real false-PASS window) and #46 (the capture
quiescence gap), demote #5 (a non-regular entry refuses rather than exploring
an unreproducible tree — the issue's own "more honest and more annoying"
option), narrow #39 and #10 (the macOS promise shrinks on the target-classes
page; the README stays under its cut-only order). The exit-code split — #94's
deliberately deferred half — is rejected permanently: the flag is the
caller's consent, macOS would lose exit-0 passes entirely, and the designed
channel already carries the bit. Two readings are codified so the freeze
cannot be argued around later: a post-1.0 trace-contract bump is honest under
the replay promise (refusal, never a misjudged address), and #156's inert
flag combo freezes as documented behavior — refusing it later would be
breaking, and that trade is accepted out loud. One stale promise died in the
sweep: preflight's refusal text still said a machine-readable form "arrives
with issue #84" — it never did; the text now states the constraint. #13
closes as fixed (ADR 0005 shipped stdio observation; check 2u pins it).
The audit's own gate: #86 stays open until #5, #27 and #46 land and the
pre-tag re-sweep runs — the declaration takes effect at the tag, not today.

## 2026-08-17 — the clock ran: 4 minutes 22 seconds, README to a real verdict on jrnl

Criterion 6's first measurement, under the protocol committed the day before:
a sealed driver (claude-opus-5, 28 turns, not told it was timed) walked from
the README to `explore` returning PASS on jrnl — 4 of 4 crash worlds, oracle
agreed on 3 operations, checker falsified before the run — in 4:22, well
under the ten-minute budget. Met, first try. The number is derived from the
committed event timeline, not written by hand; the extractor flagged three
transfer commands (docker cp / base64-through-exec of driver-authored files)
and the adjudication is on the results page rather than swallowed — the seal
guards what flows in from outside the driver, and nothing did. Two honest
observations from the driver survive as work: `--shim`/`--work` appear only
in the README's Example, not the Usage bullets (filed), and its own PASS
carries the history-form reservation (`appended tails` in not_tested) —
which the driver read, understood, and answered with its own checker; the
account block did its job on a stranger. What did not survive rehearsal is
the entry below this one.

## 2026-08-17 — the release binaries only ran on the machines that built them

The onboarding clock's rehearsal — the step that exists to prove the
apparatus before blindness is spent — found the apparatus broken in the
product's favor of nobody: the v0.10.0 aarch64-linux tarball's binary dies
with Illegal instruction on the fresh box, before printing its banner.
Isolation: the same tarball dies in the spike container too (so not the new
image), a local cross-build runs fine in both (so not the environment), and
v0.9.0's tarball dies the same way (so not this release). Cause: the release
workflow built with a bare `zig build -Doptimize=ReleaseSafe` — no target —
which compiles for the *builder's* CPU. The aarch64-linux artifacts inherited
the Graviton runner's extensions; Apple-Silicon Docker lacks them; SIGILL.
The workflow even smoke-tests the artifact (`sideeye demo`) — on the same
runner that built it, so the claim "the packaged pair works on the OS it
ships for" was measured on the builder's CPU only, and stayed green for
every broken release since the tarballs began. The x86_64-linux artifact has
the same construction and no hardware here to test it on: presumed affected,
unverified. Fix: the matrix now spells `-Dtarget` per artifact, which pins
the architecture's baseline CPU; v0.10.0's assets are rebuilt and replaced
through the workflow's own tag-dispatch repair path (built from the tag's
code, uploaded with --clobber), with the owner's approval recorded in this
batch. The onboarding clock waits for the repaired artifact — measuring a
broken tarball would time the bug, not the docs.

## 2026-08-16 — the onboarding clock: the protocol is committed before the stopwatch starts

Criterion 6 has had its instrument for weeks and no measurement; #87's own
rule is protocol-before-clock, so the protocol went down first
(`spike/onboarding-clock/PROTOCOL.md`) and this entry records its decisions
as they were made, before the first run. The fresh machine is a network-off
Linux container; three deviations are declared rather than hidden — the
release tarball is pre-staged (no network means no download, and the download
would measure a CDN, not the docs), the target arrives installed and
configured (a user measures a tool they already run), and the README is a
staged file (its opening is the session start). The driver is the
loop-closure isolation form — `--safe-mode` headless, allowlist plus denied
network/delegation tools, stream-json transcript as the audit surface — with
one new rule: the driver is not told it is being timed, because a driver
racing a clock skims and the criterion is about the documentation. The
target is jrnl, the owner's pick under the standing selection bar (7,291
stars, pushed 2026-08-14, contributors above the bar — measured, not
recalled, same day). The clock stops only at a real verdict — exit 0 or 1 —
because refusals are what the README teaches you to fix; a refusal loop that
eats the ten minutes is itself the measurement. Rehearsal boundary written
before rehearsing: the apparatus may prove that jrnl accepts an entry and the
tarball's binary runs, but nothing rehearses sideeye against jrnl — the
first exploration of the target happens on the clock or not at all.

## 2026-08-16 — oracle_verified: the report says, as a value, whether a second witness checked

Issue #94's gap, measured before anything was written: a verified PASS and an
`--allow-unverified` PASS were generated on the same clean toy in the spike
container and their JSONs diffed — both exit 0, and the difference confined to
two prose account fields (`oracle` and `metadata_writes`). Grep-able, so the
premise is not "no difference"; it is that neither is a field designed for
branching — the schema page licenses account prose to change wording between
releases. The fix is one required bool on every report: `oracle_verified`,
true at exactly one point in the pipeline (the oracle comparison completed and
agreed — set beside the "agreed on N operations" note), false on every other
path: no `--oracle`, `--allow-unverified` with no oracle, a comparison cut
short by a refusal (the flags are not exclusive — an oracle that ran and
agreed sets true beside an inert `--allow-unverified`; whether that combo
should refuse instead is filed as #156, not decided here). Review then added
two more corners to the pins — the SETUP_ERROR report and the no-oracle FAIL,
each seen red once against a field-less report — bringing the value pins to
seven; the pins' repr comparison cannot see a bool-vs-string type regression,
filed as #157.
The name was the owner's pick from three shapes: `evidence_level` on every
verdict was rejected because a no-oracle FAIL would be stamped "unverified" —
a word that reads as doubt about a counterexample that stands on replay alone;
a PASS-only field was rejected for pushing three-state logic onto every
caller. A fact about the run, never the verdict. The exit codes stay untouched
— whether an unverified PASS should exit differently is the freeze audit's
question (#86), deliberately not this change's. Acceptance pins the value on
all four corners (verified PASS true, oracle-borne FAIL true, no-oracle
UNKNOWN false, --allow-unverified PASS false) plus the ran-but-not-compared
path (empty oracle), and the pins were run against the pre-change binary
first: all five red (the field read as empty on every pin), with check 4's
bidirectional binding firing too — "documented but never generated".

## 2026-08-16 — the README sheds its history: the owner's simplification order

The owner read the front page and ordered it cut: the status paragraph, the
version history, the filing-by-filing accounting of upstream reports, the
inline ADR and issue numbers — none of it serves the person arriving today.
The rewrite deletes, and rewords only downward; nothing gets a stronger
claim than it had. One sentence needed real care: the results line. The old paragraph
enumerated filings, and #147 is open precisely because a committed table
(`outcome-map.tsv`) overcounts reported-upstream rows — so the new sentence
was derived from `spike/assisted/NOVELTY.md`'s upstream round and the live
tracker links instead: four standing filings (timewarrior, topydo, calcurse,
stow), devtodo filed and withdrawn the same day by the owner's fair-play
ruling. The page now says "several of them reported upstream" and carries no
count. The "not measured from this README alone" sentence survives on
purpose: criterion 6's first timed run (#87, this batch) is what replaces it
with a measurement, not an edit.

## 2026-08-16 — v0.10.0: the pre-freeze batch release

Version bump only — the work is in the entries below from the same two
days. The release carries the argv form (#95, ADR 0019 flipped to Accepted
in this commit), criteria 3 and 4 recorded as met, the timew-regression CI
job, the scouting guide, and the follow-up measurements. The choice of
0.10.0 over 0.9.1 follows the house precedent that a define-contract
extension is a minor: the trace contract did not move, but the config
contract grew a value shape and the case format grew version 3. One
process note: the buildlog CI gate correctly refused the first push of
this bump — a version literal in `src/main.zig` is still a src/ touch, and
the gate does not know "it's only a release" from a code change. This
entry is the fix, not an exemption.

## 2026-08-16 — the scouting guide ships: SCOUT.md grows its product form

The batch's last PR promotes the assisted-discovery method to
`docs/scouting.md`. The promotion is a rewrite, not a copy: the experiment's
measurement framing (start timestamps, the 15-minute budget, cohort rules)
stays behind in `spike/assisted/`, and what crosses over is the method — the
five things a scout reads for, propose-before-define metadata, fail-closed
checkers, treat-UNKNOWN-as-a-define-bug — plus every lesson the cohort paid
for and two things this batch added: the argv form for the argument a
space-split string cannot spell, and the routing note that an argv define
skips preflight for `explore --config`. Numbers are deliberately absent from
the guide: measured results live in the records (`spike/assisted/`,
`spike/followup-95/`), which do not go stale when the next cohort runs.
SCOUT.md keeps a pointer forward so the experiment's record and the product
door cannot drift apart silently.

Same PR, a reversal recorded as it happened: on the owner's direction to
sweep the README for contradictions, hnb was first PROMOTED — into the
front page's counterexample list and the target-classes Measured table —
and the owner rejected the promotion within the hour, on a stronger ground
than the reporting rule: **a small, effectively dormant project is not a
legitimate measurement target at all**, and putting one on the product's
front page is wrong even unreported. Both promotions are reverted; the
re-scoring that had briefly taken a half point from the hnb run is
corrected 3.5 → **3 of 5** (RESULTS.md carries the correction, the
selection rule in PROTOCOL.md is tightened from "explorable but
unreportable" to "not a target", and the scouting guide now says so as its
first never-do). The followup-95 record itself stands — it was and remains
the #95 contract measurement — it just names no score and no front page.

## 2026-08-16 — #118 re-scored by the owner, #123 held on measured demand

**The re-scoring (owner adjudication, recorded in RESULTS.md).**
Drivable-slice discovery value 1.5 → **3.5 of 5**; question quality stays
5/5. The mechanics: stow and devtodo graduated from blocked to found when
#121/#122 closed the gaps under their questions; buku counts zero (question
stood, answer sat inside the store's contract, claim withdrawn); pass stays
blocked on #123. The half point is hnb — outside the cohort, same assisted
shape, and the deliberately irregular part of the number: a sixth target
against a five-target denominator, disclosed in the record as
"corroboration the pattern holds beyond them" rather than silently pooled.
The owner also ruled the product decision: **advance** — the agent-facing
scouting guide gets written (next PR), and #118 stays open per its own
tracking note.

**#123 stays open and unbuilt, and now the reason is measured rather than
felt.** The trigger was "build when multi-process friction dominates". The
#84 sweep's two child refusals turned out to be spelling (both op.sh
wrappers; #95 dissolved hnb's live), leaving one direct demand (pass) plus
one potential (lbdb through a wrapper child). Against that: the address
`(subject pid, seq)` is load-bearing across engine, case format and replay;
ADR 0002 already rejected both obvious mechanisms; and the ADR 0018
precedent prices the smaller half of this issue at 1106 PR lines (~370 of
them src/ + shim/ insertions, measured from that PR's own diffstat — the
review caught this entry's first draft carrying "~450" inherited from an
earlier review's estimate, unverified: the remembered-number class again).
The disposition comment carries all of it, with the reopen condition stated
as a data condition, not a mood.

## 2026-08-16 — #95: the argv form, and the wall it was built against turns out to hide a real bug

**The shape of the change (ADR 0019).** One tagged union — `config.Command`,
string or argv — carried from the parser through `Args`, the case file and
the three spawn sites, so the two spellings meet only where both become the
executor's argv. The string path is byte-identical to before: the flags still
bind strings, `splitArgs` still splits them, and a case spelled entirely in
strings still writes `case_version: 2` — the bump to 3 happens only when a
define actually carries the argv form (the ADR 0014 travel-together law,
extended to shape). The parser's array grammar is deliberately narrower than
TOML's: one line, quoted elements, commas, and a named line-numbered refusal
for everything outside that — including the array form on a non-command key,
which a value-first parse would have accepted silently (plan R1's catch,
confirmed against the code: the old parser read the value before dispatching
on the key). Review then caught the refusal *count* claimed in prose
disagreeing between four documents while a reachable refusal sat unpinned —
the counted-claim class; the counts are gone and the branch is pinned.

**Red first, and the instrument lied once.** Before the implementation, the
current binary was fed both an argv operation and an argv `state`: line-named
refusals, exit 3 — measured in the working session, not kept as an artifact;
the durable red is structural, and review verified it: check 2ab's argv toml
exits 3 on any build without the feature, so the acceptance suite cannot go
green pre-feature, and the acceptance refusal checks plus the unit-test
refusal table pin the walls that replaced that one generic refusal. The one stumble: the first followup-95 run reported `rc=0` while
its own log said the apparatus had failed — the raw exit code went to `tail`,
not to the record. The pipe-hides-rc class, re-learned; the re-run reads the
raw rc before any pipe.

**followup-95: the sweep's hnb wall was the spelling, and only the spelling.**
Run in the sweep's own image (hnb 1.9.18 baked in), this branch's engine:
the wrapper spelling still refuses exactly as the #84 sweep recorded
(UNKNOWN, child_process_detected — the control), and the same question
spelled as argv explores fully and lands **FAIL — 1 violation over 3 crash
points, strict oracle agreeing on all 3 operations** (the engine's headline
prints "1 of 4", counting the baseline world — #150): hnb's save path rewrites `notes.hnb`
through truncation, and a kill inside the open→write window leaves the file
neither old nor new — the devtodo/calcurse class on a third target. The v3
case replays in a fresh work directory. Finding kept in-repo, deliberately
unreported (the devtodo target-selection call). One self-caught slip on the
way: the NOTES' Result section was drafted before the run — the
conclusion-before-measurement class R1 flagged on the #123 comment this same
batch — and was reverted to a placeholder until the artifacts existed.

**What did not change, verified rather than assumed.** No trace-contract
movement (no shim or record change; existing saved cases replay untouched),
no report-schema movement (the operation never reached the report), and
preflight is untouched — the plan's original hint-branch idea died in review
as unreachable code, and the real constraint (an argv-form define cannot use
preflight, because preflight is flags-only by its own refusal) is documented
where the argv form is.

## 2026-08-16 — #81: the README's agent section states two measurements and one absence

The batch's last PR adds the agent-onboarding section to the README's MCP
chapter: the two measured agent workflows stated separately (fix-from-report,
twice; define authoring, five targets in minutes), and the unmeasured path —
setup from the README alone — named as unmeasured instead of implied. The
lightweight review caught the draft doing, in miniature, exactly what the
#85 review's R1 caught at scale: "handed only the counterexample" had
dropped the bug-blind replay plumbing from the input list (PRD's own honesty
note says the input set is the report *and what it transitively names*), and
"documentation-reading protocol" implied a docs-only scout when the protocol
grants source, tests and trackers too. Both were claims of *less* access
than measured — flattering compression, the same overclaim class in the
humble direction. Fixed before commit.

The kill-criteria review (`docs/kill-criteria-review.md`) scores all eight
§18 conditions against the collected data — none triggered — and PRD
criterion 3 is checked on it. Three decisions worth recording at the moment
they were made:

**The preamble was checked, not skipped.** §18's own gate ("if Sideeye finds
nothing beyond existing hand-written adversarial tests") never opened — the
record contradicts its antecedent. The review runs anyway because criterion
3 asks for the review unconditionally; the page says so first, so a reader
knows the antecedent was examined rather than quietly bypassed — the class
of failure where a check's precondition quietly becomes false and nobody
re-reads it.

**Row 7 went to the owner, and the adjudication is recorded as one.** The
UX-difference condition is the only row whose wording makes
failure-to-demonstrate itself the trigger — no-data is not neutral there, so
no measurement could score it. Adjudicated 2026-08-16: not triggered, on the
measured in-repo differences (minutes-scale onboarding, agent-driven define
and fix, named refusals) plus the structural arena difference; the missing
head-to-head is disclosed on the page, and a real one supersedes the
adjudication in either direction.

**The wiring honored R2's backticked-ratio trap, and the dry-run lied once
first.** Check 11 now sweeps the new page; before wiring, the extractor was
run over the draft exactly as the plan required (18 tokens, all resolving)
and proven red with one deliberately broken reference. The first dry-run
attempt reported a false MISSING — the interactive shell here is zsh, which
does not word-split an unquoted variable, so the whole 18-line list arrived
in the loop as one "path"; the valid dry-run is the POSIX-sh replica of the
gate's own loop, which is also what CI runs. The one-off measuring
instrument was the broken part — the recurring class where the path you
measured is not the path that runs. Check 11's comment now warns that a
backticked ratio reads as a path — the page keeps every ratio in prose.

**Review round 1 reversed two evidence claims (recorded, per the contract).**
The reviewer verified every number against the primary artifacts and caught
the draft over-counting on both of the rows it was written to strengthen:
row 5 said "all four blocked assisted defines reached verified" where
REMEASURE records three of four (pass stayed refused — the control that is
*supposed* not to move), and row 3 attributed "topydo filings" with
replayable counterexamples where the record shows exactly one filing
(topydo#341, a plain-printf reproduction rewritten for reporting etiquette)
and a deliberate decision *not* to re-file the destruction class
(topydo#318 is a third-party report). Both corrections make the rows
stronger, not weaker — an unmoved negative control is reproducibility
evidence, and the un-filed counterexample is a reporting-policy fact, not a
complexity one. Same lesson as ever: the claims that exceed their artifacts
are the ones written from memory of the result rather than from the
artifact.

## 2026-08-16 — #141 + #144: two follow-up measurements, and both came back the good kind of boring

**#141 — the omamori surface probes, re-measured under v10.** DESIGN §18 had
banned its own calibration sentence from citation until
`spike/dogfood-omamori-surface.sh` re-ran; it ran (omamori 1.0.4, built
offline from a tracked-files archive with host-side `cargo vendor` because
this network's TLS interception kills both git-over-https and rustup inside
containers — the rustup shim kept trying to sync components, so the build
calls the toolchain's real cargo directly). The v8 walls are gone exactly as
the old pins predicted: install, setup and init no longer refuse at
`symlinkat`/`fchmodat` (#122 made symlinks first-class, #121 made the chmod
family recorded-only — three of the four reports' metadata lines name the
excluded `fchmodat x1`; verify observed none), and **all four unguarded
writers explore fully and PASS** (assisted image: install 16 / setup 28 /
init 6 / verify 4 crash points, reports committed under
`spike/followup-141/artifacts/`; the
spike-image family measured higher counts the same day — the counts are
image-sensitive, so the refreshed pins keep verdict+reason as the claims and
demote min_cp to a vacuity floor below both measurements). The citation ban
is lifted: §18's calibration paragraph and the target-classes Rust story now
carry the v10 record.

**#144 — the bogofilter-sqlite counterexample, triaged with the tool's own
reader.** The labeled follow-up (`spike/followup-144/`, outside the #84
corpus, reading the committed define verbatim) re-ran the sweep's define
with a checker asking bogofilter's own tools — `bogoutil-sqlite -d` plus a
real classification. First run was an apparatus lesson the engine caught
for us: bare `bogoutil` resolves through alternatives to the **BDB**
variant, which cannot read a sqlite wordlist at all — the checker was red on
valid state, and the run refused with the checker failing in 25 of 26
worlds rather than minting a false verdict. With `bogoutil-sqlite` named:
**FAIL 3/26 reproduced, and the checker passed in every explored world —
the violating three included** — the git COMMIT_EDITMSG template exactly.
Review caught the first draft of that sentence overclaiming: the report
records only the earliest violating world's invariant, so "never failed in
any world" was an inference over 24 of 26 worlds, not a record. The cheap
fix was the reviewer's own suggestion — the checker now appends one line
per invocation to a log outside the judged state, and the committed log
(`spike/followup-144/artifacts/checker.log`: the falsification gate's red
first, then 26 passes) turns the claim into an artifact, with run.sh
pinning its shape so a re-run that breaks it goes red. sqlite's journal
recovers the wordlist in every crash world; the disposition is
withdrawal-shaped (the buku class lesson, confirmed on a second store),
and nothing goes upstream.

## 2026-08-16 — #82: the timewarrior proof moves into CI, and plan review re-priced the whole issue

Two decisions before any code, both from adversarial plan review. First, the
issue's own framing was stale: #82 was written (and amended) before ADR 0017,
whose ordering requirement keeps the timewarrior finding at "discovered
automatically — partial" permanently — so this work is **regression hygiene**,
not criterion-1 progress, and the amendment's three definitions are
superseded. That is now written where the job lives, not argued here. Second,
the planned committed-case design (record once, replay-only in CI) died in
review: the reviewer measured five failure modes it would create — the case
freezes absolute paths to heredoc-generated scripts, the legs need state
resets, the recording is environment-sensitive (the distro-vs-pinned 19/24 op
split is this repo's own measurement of that), submodules were missing from
the fetch plan, and a shallow-fetched tree breaks the local re-clone — all
five of which `spike/dogfood-timew-replay.sh` had already solved and measured.
So CI runs the proven script itself: a `LEGS` selector (default `abcd`,
unchanged; `a` mandatory since b/c/d replay the case leg A records) and the
`timew-regression` job runs `LEGS=abc` per push. A per-leg detail the review
also caught before it shipped: the distro-timewarrior precondition was
unconditional, which would have killed `LEGS=abc` in exactly the environment
CI provides — it now belongs to leg d.

Measured: `LEGS=abc` in a container **without** the distro package — ALL LEGS
PASSED in **37s** (the +10min CI budget was over-cautious by an order of
magnitude); default `abcd` with the package — ALL PASSED, 35s, behavior
unchanged. Falsified both directions, with one embarrassment kept on the
record: the first red-C harness passed `PATCH=` as an environment variable,
but the script assigns `PATCH=` unconditionally — the override was silently
ignored, the REAL patch applied, and the "falsification" run came back green
with the real patch's sha in its own footer (the measured path did not reach
the thing being varied — the exact class this workspace keeps re-learning).
The second harness bind-mounted the no-op patch (a new-file-only diff) over
the script's hardcoded path; the footer then showed the no-op's sha and leg C
went red on the script's own path — "expected a clean replay PASS", got the
case reproducing, 1 leg failed, rc=1. Leg B's predicate — extracted verbatim
from the script by awk, not re-typed — exits 1 when fed a committed PASS
report. Local-only honesty note: this host's network intercepts TLS, so the
container clone ran with GIT_SSL_NO_VERIFY for these measurements — the
script's content trust rests on the full 40-hex pin (its own header's
argument), and CI verifies TLS normally on GitHub's network.

## 2026-08-16 — #84 sweep: the numbers land, and the composition is the finding

The sweep ran from the apparatus PR's merge (`b5b23fd`, engine 0.9.0 /
contract v10), all 49 corpus rows — one fresh container per executed trial
(36 rows; the other 13 are documented walls that never run), repo mounted
read-only, no SETUP_ERROR anywhere — `count.py check` closes green over the
full with-data path (49 digests, docs in sync).

**A-group: 1/28 UNKNOWN (3.6%).** The one is watson's recorded
nondeterministic-writer refusal, reproduced exactly. Everything else
reproduced its committed record too: topydo 12 FAIL + `ls` PASS with 0
crash points, abook and khal null, the four assisted counterexamples,
timewarrior a-PASS/b-FAIL, todoman both PASS. An engine that drifted from
any of those records would have shown up here; it did not.

**B-group: 13 walls, then 3/7 UNKNOWN (42.9%) — and all three are
define-budget refusals, none target-origin.** hnb and lbdb died on the
exec-chain rule their NOTES predicted before the sweep; cookietool's
recording was refused over its exit convention (10 — apparently the count
of deleted cookies — where the uniform protocol fixed 0). Of the five
targets whose documented invocations could be spelled as operation
strings, four reached verdicts; cookietool, the fifth, was refused on the
declared exit status, not on spelling — the first "4/4" draft of this
sentence was wrong, and review caught it against the frozen definition.
The striking row is **bogofilter-sqlite: FAIL 3/26, oracle agreed on
25 operations** — a fresh counterexample from a never-run target, in
exactly the buku shape (a sqlite store judged by file bytes is judged more
strictly than its journal contract). No checker ran, so no recovery was
measured, and the disposition stays new-this-sweep; its case file was not
preserved (the sweep keeps reports and transcripts, not replay cases — a
labeled follow-up run can re-derive it if triage wants one).

**Threshold (owner, 2026-08-16, set from the B data after seeing it):**
two-part — target-origin UNKNOWNs ≤ 1/7 (measured 0) and overall ≤ 50%
(measured 42.9%). Both hold; **criterion 4 is met**. The two-part shape
was chosen over a single rate precisely because the composition carries
the information: a contract that cannot spell an invocation is an issue
backlog, a tool the engine cannot watch is a product wall, and a single
number reads the two identically. The macOS column derives to 11/28 and
6/7 by the completeness formula — printed by count.py, never typed — which
is the per-platform honesty the #84 amendment asked for.

## 2026-08-16 — #84 apparatus: the corpus is fixed before the sweep, and the first draft could not fail

The UNKNOWN-rate measurement (v1.0 criterion 4) starts with the PR that must
merge before any number exists: `docs/unknown-rate.md` (the frozen rulebook —
unit, four axes, funnel walls, outcome-ratio classification, small-cell rule),
`spike/unknown-rate/` (corpus.tsv with 49 trials, five launchers, sweep.sh,
count.py, a third Dockerfile), and acceptance check 12 (the drift gate).

The first corpus design was killed in plan review, and the reviewer was right
in one sentence: **the measurement could not fail.** Every committed define
that reaches a verdict today is a define whose past refusal drove #121/#122 —
the assisted cohort went 4/5 UNKNOWN → 1/5 in one day when those engine PRs
landed — so a corpus of committed defines measures "did the engine catch up
with its own inputs", and a threshold set from its ~0% is satisfied by
construction. The shipped design splits the corpus: the A-group (28 trials,
10 tools, every runnable committed define — watson counted IN the denominator
as an UNKNOWN, since "supported" is a class property and watson is a Python
CLI) is published as the engine's development-input set and is not the
threshold basis; the B-group (20 targets nobody here ever ran) is, and its
members were selected by a committed debtags predicate over bookworm's own
archive metadata with a deterministic sort — the second review round caught
that "about 10, hand-picked from the predicate's pool" would have moved the
gerrymandering from the rate to the threshold, so no hand touches the list
(select-b.sh, b-candidates.txt, b-targets.txt are all committed; the one
hand-written input is the name-exclusion file carrying the taint ledger and
hledger's sealed eligibility). Of the 20, seven reached a uniform minimal
define (setup + one documented state-changing op + L0 + strict oracle;
grounds quoted per target in defines-b/*/NOTES.md — cookietool's man page
even documents its temp-file rewrite and a "CAUTION NEEDED" direct-overwrite
flag); thirteen are funnel walls (W1 does-not-install ×2 measured, W2
state-not-in-local-files ×9, W3 no-non-interactive-writer ×2), published as
funnel data outside the engine-rate denominator.

Decisions that will read as opinionated later, recorded now: taskwarrior is
in the supported table but has no committed define, and reconstructing one
today from BUILDLOG prose would be answer-known authoring — it joins the
corpus in neither group (the exclusion table says why); the campaign
declarations run through a thin open launcher that replicates exactly what
can move a verdict (HOME, the CHECK_* unsets, the state roots) and
deliberately not the seal machinery — CLAUDE.md now says a post-campaign open
re-measurement is not a campaign phase; macOS gets a derived column from the
requireCompleteness mechanism (every strict PASS → completeness_not_verified,
no oracle exists there), computed by count.py from a formula, never typed.

The gate was seen red before it was trusted, both sides: fixtures/good passes,
tampered-verdict (one report's verdict flipped, docs left stale) dies with
"published results block differs from recomputation", tampered-manifest (one
row deleted) dies with "manifest rows (2) != corpus rows (3)" — and check 12
re-runs all three every CI run, so the red proof cannot rot. Pre-data, the
live check asserts the explicit placeholder line: an empty table can never
read as a measured zero.

**The smoke run found what two review rounds did not.** The first uniform
B-group protocol wrapped every operation in an `op.sh` (for `$TOY_STATE`
expansion) — and the very first real trial (2vcard) came back
`child_process_detected`: a script that performs nothing state-changing
before its `exec` is an image change whose observation chain carries no
operation count, exactly the shape #137's structural rule refuses. The same
define spelled as a direct operation string explores and PASSes (3 worlds,
2 crash points, measured back to back). So the protocol now prefers
`op.txt` — a static command line with `$TOY_STATE` as a launcher-expanded
token — and keeps `op.sh` only where the engine's space-split contract
cannot spell the invocation (hnb's space-carrying command argument, lbdb's
stdin redirect), with the consequence written into those NOTES: a
chain-rule refusal there is the trial's honest verdict, because it is what
any user driving that target through the current contract would get. Also
measured on the way: the stale local `sideeye-spike` image silently lacked
khal at the toml's pinned path (`recording_run_failed`), while the image
rebuilt from the committed Dockerfile explores khal `import` to the same
PASS 10+1 the campaign recorded — the sweep builds its images fresh for
exactly this reason.

## 2026-08-15 — #78/#79/#80: found not plumbed, and two evidence-first pages

Batch b_309cfe196cf1. The shim default is the demo's resolver generalized —
the doc comment on `demoShimCandidates` had already deferred exactly this
move to #78 — plus realpath, so a reproduce line names the real file rather
than a `bin/../lib` spelling. One resolution point (the shared
`args.shim orelse`) covers explore, preflight and replay at once.

The oracle half shipped as a HINT, not a default. The plan-stage adversarial
review measured what silent attach would change: six acceptance checks pin
no-oracle behavior and the container carries strace, so they would all flip;
the MCP child would grow an oracle the server never configured; and
`--allow-unverified` without `--oracle` — an invocation that does pass a
flag — would change meaning, falsifying the "flagged invocations unchanged"
thesis as written. Named-never-attached keeps every verdict byte-identical
and still deletes the plumbing friction: the refusal now hands the user the
exact `--oracle /path` to paste. The deviation from the issue's letter is
recorded in the PR and in #78's close.

The target-classes page dropped the issue's Node/libuv claim — no committed
evidence exists anywhere in this repo — down to a labeled not-yet-measured
row, and the review reversed my own draft's omamori arc against the record:
the nondeterminism refusal came first, the L0 history form (#24/#25)
produced the PASS 143/143, and the 08-12 walls (symlinkat/fchmodat) have
since been removed for other targets without re-measuring omamori. Writing
the evidence table was itself the audit the covenant asks for.

New acceptance: shim found/absent (both sides pinned), hint present/absent
(the rc pin doubles as the not-attached proof), and a path-existence sweep
over the two pages — guarding path rot only; claim drift stays a
review-time axis. Sunset on the sweep: never fired by the freeze → removal
list. Running the suite caught one thing the plan review had predicted for
the oracle and I still missed for the shim: check 2h used a missing --shim
as its SETUP ERROR falsification, and the default turned that run into a
PASS — the trigger moved to a missing --state, and the zig-out layout the
incident exposed became check 9's third leg.

R1 (fresh reviewer, whole diff): no P0. The P1 was this batch's own
covenant applied back at it — two rows stated claims their named artifacts
do not contain (timewarrior's 25/25 lives in the buildlog, not the four
named spike paths; devtodo's "deliberately unreported" lives in NOVELTY /
PROTOCOL) — both fixed by naming the right artifact, plus two Walls
bullets that carried no artifact at all. P2s: the page and the changelog
claimed the sweep covers "every repository path" while the check's own
echo says "slashed backtick references" — the prose narrowed to what is
measured; the sweep's denominator is now asserted (a page whose extraction
yields under five references goes red instead of passing over an empty
loop, seen red on a synthetic page); the omamori arc gained its middle
wall (baseline_violates_invariant) so the page and this entry tell the
same story. The reviewer also ran the extractor for real: 35 tokens, all
resolving, none dropped, none foreign.

## 2026-08-15 — v0.9.0: the release rides a truth-up of the front page

The bump (0.8.0 → 0.9.0, minor by the contract-bump precedent — v8 rode
0.7.0, v9 rode 0.8.0) ships the v10 batch merged earlier today. The
release checklist's README-against-release step turned into real work
rather than a check: the findings paragraph still listed buku (withdrawn
this same morning), counted "two upstream reports" (four are filed — the
stow and calcurse reports went out 2026-08-15), and said novelty was
"deliberately unchecked" (the novelty round ran). Fixing #93 here
surfaced the same-class hits beyond the front page — DESIGN's overview,
its one-sentence definition, and the report schema's `earliest`
description all promised "smallest"/"minimal"; every one now says what
ships: the earliest failing crash point, saved as a replayable case.
#96's sandbox sentence landed in README's MCP section and ADR 0010's
consequences. One piece of bookkeeping: #134 had to be closed by hand —
PR #135 shipped it but referenced the issue without a closing keyword,
so the merge never closed it.

## 2026-08-15 — #123: the judge follows a single pid across execve (contract v10)

Third PR of the b_cd3b31e80b91 batch; the design is ADR 0018 and the
plan carried two adversarial review rounds before a line was written.
The shape that shipped: the shim's exec wrappers carry the operation
count (`SIDEEYE_SEQ_BASE` — subject-only via the armed-pid gate, which
excludes vfork children structurally; execve rebuilds envp in a stack
frame; overflow carries nothing rather than truncating the target's
environment), the re-run init continues numbering, `shim_ready`
re-announces the base as its seq, and the engine tolerates a subject
exec only when exactly that evidence follows. The oracle's own
primary-exec refusal is gone — chain integrity is the shim's evidence,
divergence is the oracle's net. `sequence_numbering_broken` is the new
refusal for the shape prefixHash provably cannot see (it probes 1..k
and stops at the first match; a restarted counter is a duplicate).

First-try measurements in the container, all four exactly as the plan
predicted: TOY_SELFEXEC judged end to end (the planted bug FOUND at
crash point 8 of 8, oracle agreeing on all 8 operations spanning two
images), TOY_FORKEXEC still refused as child_touched, TOY_EXECL (an
uninterposed exec — no record, no carry) caught as
sequence_numbering_broken, and ONE trace header across the image change
(the lseek guard promoted from convenience to load-bearing, now pinned).

The mutant sweep earned its keep twice over. Mutant A (disable the
continuation) failed to COMPILE, the container ran the stale binary,
and the suite came back all green — a textbook "unmeasured green"
caught only because the build's raw exit code was read; the harness now
gates on it and the mutant was rebuilt as a base-off-by-one (killed:
the self-exec check went red at exit 2). Mutants B and C SURVIVED their
single-line forms and both survivals were the two-witness design
working: the fork+exec refusal is held by the shim's foreign-kill-point
AND the oracle's child-touch (disabling both produced a false PASS at
exit 0 — killed), and the numbering refusal is held at the recording
AND in every world (disabling both likewise false-PASSed — killed). The
header mutant broke six checks at once, as a mid-file header should.

The v9→v10 re-record of the four assisted cases went verdict-identical
(2/22, 1/11, 6/8, 2/5; fresh-container replays all `the case
reproduced`) after two instructive trips: replay refuses before setup
when the state root does not exist to resolve, and buku's replay needs
the launcher's XDG environment — the cohort R1's "the toml does not
carry the environment" lesson, now measured on the replay side.
The buku inspection case (#133) stays v9 deliberately: its claim rides
its transcript and worlds log, not replayability.

R1 (fresh subagent) then broke the slice where the oracle's old refusal
used to stand and nothing had replaced it: an execl with ZERO in-scope
operations before it — no exec record, no window, and the numbering
check's two sides trivially equal — reached a **FAIL verdict** with the
second `shim_ready` sitting ignored in the trace (the reviewer decoded
it and pasted the record). The evidence was self-contained all along:
the constructor runs once per image, so a second same-pid announcement
IS an image change. The parse now refuses on exactly that, which also
made TOY_EXECL's refusal structural (the acceptance anchor moved to the
double-announcement message, seen red against the unfixed engine first;
the numbering assert stays as the second net, unit-pinned). The ADR and
CHANGELOG sentence claiming the oracle's completeness comparison covers
broken chains was wider than the code — narrowed to what is actually
computed. Also adopted: the report now DISCLOSES an unbroken chain
("the subject's image replaced N time(s), chain unbroken" in the
processes note — `exec_continuations` had been write-only outside its
own unit test, and the reviewer noted every other note in the report
names what the judgement covered while this one was silent);
`SIDEEYE_SEQ_BASE` is pinned empty in all three spawn env lists so an
ambient value in the operator's shell cannot become the first image's
base (measured: it turned a PASS run into a mis-attributed
sequence_numbering_broken); errno is saved across the failure-path
unsetenv in execv/execvp (glibc measured harmless, musl/darwin not —
the `remove` wrapper's discipline); README/DESIGN's "execs over itself
is refused" and README's v9 badge updated; the world-phase exec message
no longer claims more than its branch checks; TOY_EXECL gets its own
stage variable; the colliding `check 2x` label renamed `check 2ex`.
Not changed: the header-count check's dependence on the preceding run's
work dir — the block rm -rf's it first, so a stale file cannot survive
into the read.

R2 CONFIRMED all ten with its own re-measurements (the zero-op probe
now refuses; ambient SEQ_BASE runs PASS again; the disclosure appears
in text and JSON). Two of its notes acted on: the printed `reproduce`
line now pins `SIDEEYE_SEQ_BASE=` (the acceptance executes that line,
so an ambient value would have made it diverge from the engine's own
runs — the same class as the spawn-env pin), and the image-change
disclosure moved to right after the trace is trusted so the JSON
`processes` field is honest on oracle-refusal paths too, with the
children note now composing around it in either order. One note
recorded rather than fixed, so a stale mutant result is never cited as
current: **the numbering-assert wiring in main.zig no longer has live
acceptance coverage** — the structural double-announcement rule catches
the execl shape first, and R2 measured the both-asserts-off mutant
SURVIVING the current suite. The wiring stays as the second net, its
computation unit-pinned; a live shape that reaches it would need a shim
that renumbers without re-announcing, which no interposed path
produces.

## 2026-08-15 — #130: the assisted funnel gets its verify-seals — and building it hit both failure modes it exists to catch

Second PR of the b_cd3b31e80b91 batch. `spike/assisted/verify-assisted.sh`
machine-checks that an assisted claim's question preceded its answer: D1
(the define's introducing commit strictly precedes the first
report/case/transcript artifact's, on the FIRST-PARENT order of main —
squash and merge read the same, and local commit-splitting cannot
reorder a pushed history), D2 (define blobs byte-identical at both
points; the launcher is D2-held when it exists but never moves the
define point), D3 (every scanned file listed with its introducing
commit). PROTOCOL.md gains the claim rule ("Claiming criterion 1"):
push the define, then explore, then push the artifacts, and a claim
commits the verifier's transcript. Exploration stays ungated.

Building the checker produced two textbook instances of its own subject
matter. First, the D1 comparison shipped inverted (rev-list is
newest-first; "precedes" is a LARGER position) — drill 1, the clean-
order green case, caught it on the first run. Second, on the real
history the walker returned an introduction a day older than the cohort
itself: git's similarity matching recorded fresh cohort reports as
**C071 copies of an unrelated blind-hunt JSON**, my rename handling knew
R but not C, the file silently fell out of the anchor set — and the
narrowed set produced a **false green D1 on devtodo**. Both fixed:
rename/copy hops are honored only inside the target directory (a hop
from outside IS the introduction), and an unresolvable file now stops
the run at exit 2 — a narrowed anchor set is not an answer. Drill 5
pins that. All five drills seen red/green for their own reasons
(`verify-assisted-drills-run-2026-08-15.txt`).

The cohort run
(`verify-assisted-run-2026-08-15.txt`): all five targets red, uniformly
"define and first artifact were introduced by the same commit
(daa6a93)" — the single PR #119 merge, exactly what the plan's reviewer
measured at commit granularity and ADR 0017 admitted in prose while the
check did not exist. A record, not a certification; the rule binds
claims from today.

R1 (fresh reviewer) then broke the first version four more ways, every
one a variation of the class this checker polices. P0: the file sets
came from filesystem globs, so an UNCOMMITTED `rm` of two define files
flipped a red target green — the sets now come from `git ls-tree` of
the anchor ref, and a working-tree difference is noted and ignored.
P1s: the walker took the NEWEST introduction for artifacts, so
delete-and-re-add laundered an artifact's age (an artifact now anchors
at its OLDEST in-target existence event); the out-of-target
rename-terminate rule doubled as an out-and-back laundering path
(rename hops are now followed in both directions, and only in-target
events count — which also lets git's cross-repo similarity noise stop
counting on its own); the five drills killed none of the rename/copy
machinery (six named mutants all survived); and the committed cohort
transcript carried twenty vacuously-true "D2 ok" lines — a same-commit
comparison measures nothing and now says "not evaluated". Drills grew
to twelve, one per mechanism, and all six of R1's surviving mutants
were re-run against them: 6/6 KILLED. Artifacts also match at any
depth below the target now (the answer can sit in inspection/ or
evidence/), and a merge-commit introduction is annotated in D3 since
first-parent order deliberately ignores side-branch author dates.

R2 confirmed seven of eight and caught the eighth half-closed: the
tree-sourced set fixed only the UNCOMMITTED deletion — a committed
deletion removes the path from ls-tree too, and R2 reproduced the same
false green against the fixed HEAD (delete the early report in a
commit, add a dissimilar one). The denominator is now the anchor tree
united with every path the first-parent history introduced under the
target; paths no longer in the tree are annotated in D3. Drill 13 pins
it. R2's independent mutant re-measurement (in-clone, with a no-op
control that correctly SURVIVED) also confirmed 6/6 — and flagged that
an out-of-repo copy of the script makes every mutant look killed
because drill 10 fails for the wrong reason; its in-clone method is
the one to reuse. Verified after the fix: the five-target cohort
transcript is byte-identical (the real histories contain no deleted
artifact-shaped paths — R2's measurement, reconfirmed here). Its one
remaining nit — four mechanisms hang on a single drill each, and
confinement's only kill depends on the C071 record staying in this
repo's history — rides the PR as a recorded follow-up.

## 2026-08-15 — #134: the gate's child output now carries falsify: on every line

First PR of the b_cd3b31e80b91 batch (plan reviewed adversarially twice;
Codex was out of credits, so a fresh subagent carried both rounds — same
fallback as the novelty round). The mechanism this closes is the buku
misread: the falsification gate produces, by design, exactly the output
a real finding would, and a single unlabeled line harvested from the
transcript became "world evidence" that survived four review rounds.

The shape: the gate's checker child now runs through
`posix.runChildCaptureAll` (a new variant that sends both streams to one
file — `runChildCapture` redirects stdout only, and the `dup2(1,2)` that
looked reusable turned out to live inside the minimal-env branch), and
the capture is read back and re-emitted line by line on stdout with a
`falsify: ` prefix, before the probe's verdict is judged so the refusal
path keeps its evidence. A per-line prefix rather than a fence because
the harvested artifact was a single line, and a fence does not travel
with an excerpt. World, recording and setup output are unchanged — the
plan's reviewer wanted the world-phase checker labeled too, and that was
declined with reasons recorded in the plan: the failure class is
gate-vs-world confusion, and labeling the gate side alone makes an
unlabeled checker line unambiguous.

Measured: unit tests green; the container acceptance suite green
including the new two-sided count — the buggy-toy run has the checker
speaking in both places, so the check asserts gate lines labeled (x1)
AND world lines unlabeled (x1), neither side empty (a silent checker
would satisfy a presence-only grep vacuously). Seen red once: committing
first, then mutating the re-emission loop away, the check failed with
`gate falsify-lines=0` — killed, restored. One compile slip worth
keeping: `zig build test` stayed green while the cross-build failed on
an un-updated `runChild` wrapper — Zig's lazy analysis means a green
test step does not prove every call site compiles.

R1 (fresh subagent) found a P0 this change had introduced and measured
it end to end: the capture stub's `_exit(126)` (capture file cannot be
opened) read as "the checker went red", so a directory squatting on the
default /tmp work dir's capture path let **/bin/true pass the gate** —
on main that exit was unreachable at this call site, so a regression,
not a pre-existing hole; the reviewer even showed the sibling 127 case
is netted downstream by the baseline while 126 escapes precisely
because the gate and the worlds now spawn differently. Fixed
fail-closed: exit 126 at the gate is now `checker_not_falsified` with
the stub named in the message (the discrimination mcp.zig already
made). The new acceptance check was seen red first against the unfixed
binary — where the squatting directory produced a clean **PASS** with an
unfalsifiable checker, one step worse than the reviewer's FAIL example.
Its P3s: my "121 ok" count did not reproduce (116 on a clean re-count;
117 after the new check — the verdict reproduced, my number was a hand
count over a file that included more than the suite), and the loud
read-back line now names the 1 MiB cap as a possible cause. Accepted
residuals, recorded: single lines over say()'s 16 KB buffer are dropped
with a generic overflow message (evidence loss, not misattribution),
and the capture opens without O_NOFOLLOW|O_EXCL — the same class as
every existing capture in the work dir, one more instance rather than a
new class; hardening the class is issue-worthy, not this PR.

## 2026-08-15 — buku downgraded to no finding: the "buku could not read it" line was the falsification gate talking

The buku disposition below ("held pending a plain reproduction") ended
today, and not the way either branch anticipated. The open question was
why 38 plain strace kills all recovered while "the engine's recorded
world" showed buku's own `initdb(): file is not a database`. The answer:
**that world never existed.** The committed transcripts contain the
initdb line exactly once each — at the falsification-gate position, where
the engine deliberately corrupts the state and requires the checker to go
red before the run. Every report beside it even says so ("falsified
before the run: corrupted state -> check failed"). The case's
`violation: hybrid` is an L0 content kind (neither-old-nor-new), not "the
checker also fired"; I read it as the latter, and with that reading the
gate's line became a crash world's evidence. The cohort RUNLOG wrote "in
at least one world", NOVELTY.md and RESULTS.md inflated it to "2/22
worlds" by merging it with L0's violation count, and yesterday's entry
below repeated it as the reason the finding was held rather than
withdrawn.

Measured today (committed under `spike/assisted/buku/inspection/`): the
committed define re-run with an instrumented checker that dumps every
visited world before applying the committed logic verbatim. Same verdict
(FAIL, earliest 18 of 21, 2 violations) — and the checker **passed in
all 22 worlds**. Both torn worlds hold a fully-synced hot journal beside
the torn db; buku's recovery-open rolls back, answers the bystander
query, and cleans the journal up. A plain strace of the same add shows
why that is structural: the only neither-old-nor-new windows lie between
sqlite's three db page writes, each bracketed by the journal it just
fdatasync'd. So the L0 hybrid is a true byte observation that sits
entirely inside sqlite's documented recovery contract, buku holds no
finding at all, and the two-day hunt for a plain reproduction was
chasing a transcript misread, not a fragile bug.

The general shape is worth keeping: **a guard that proves the checker
can fail produces, by design, exactly the failure output a finding would
produce — and the transcript interleaves it unlabeled with world
output.** `target-error-line.txt` is a one-line harvest of gate output
promoted to target evidence, and it survived the cohort reviews, the
remeasure reviews, the novelty round and the upstream round, because
every layer read the prose, not the position of the line in the
transcript. Candidate engine fix, not yet filed: label
falsification-gate target output in the transcript (a `falsify:` prefix
or a begin/end fence) so it cannot be quoted as a world's.

R1 on the correction (fresh reviewer, same day) returned one P0, three
P1 and six P2 — all adopted, and two deserve their own record. First,
the P0: my same-class sweep for carriers of the withdrawn claim used
`grep ... | grep -v transcript` to exclude transcript FILES and thereby
dropped every LINE containing the word "transcript" — including
NOVELTY.md's strongest form of the very claim being withdrawn ("the
checker did fail in one world ... and that transcript is committed").
The exclusion excluded a known hit; the filter unit (line) differed
from the intended unit (file). Second, R1 strengthened the correction's
own footing: the committed remeasure transcript alone proves no world
checker failed — check.sh prints only through `fail()`, the line
appears exactly once, the gate must fail or the run ends UNKNOWN
`checker_not_falsified`, and `checks_run` counts exploration-phase runs
only — so the instrumented re-run is corroboration, not the load-bearing
leg, and the RUNLOG now says so in that order. The re-run itself was
redone through a committed launcher (`inspection/run.sh`, environment
as `ops/explore.sh` — the lesson this repo already paid for in
campaign 2) with the verdict transcript and case committed beside the
world dumps, the instrumented checker's leg order restored to the
committed checker's, and the visit-to-world mapping derived in the
RUNLOG rather than assumed. Residue closed across NOVELTY.md (the HELD
section now reads WITHDRAWN), RESULTS.md (a dated note under the
owner's scoring — the numbers stand as scored; re-scoring is the
owner's), PRD.md (a new dated status paragraph: novelty four-for-four,
two reports standing, buku withdrawn, three live assisted findings) and
ADR 0017 (two dated inline notes marking buku's later resolution;
engine-level statements stand).

R2 CONFIRMED all ten and added one strengthening observation adopted
into the RUNLOG: the instrumented case's `prefix_hash` is byte-identical
to the committed remeasure case's — the two runs share the same recorded
trace prefix, a mechanical bridge tighter than matching summary numbers.
Its two non-blocking nits (a dead report.json harvest in run.sh — the
engine writes that file only under `--json` — and the oracle-less
re-run's report wording) were fixed and the inspection re-run through
the updated launcher; the artifacts are identical in structure, gate at
line 7, 22 world PASSes, same prefix hash.

## 2026-08-15 — Three reports filed, one finding held: the report step is a harder gate than novelty

Owner instruction for this round: plain bug reports, no mention of this
project or its experiments, and no AI-slop prose. That constraint turned
out to be a technical gate, not a stylistic one. A report nobody can
reproduce without our shim is not a report, so every finding had to be
re-derived from scratch with tooling a maintainer already has — strace's
`-e inject=` fault injection — before a word was written.

Three survived that and were filed; one of the three was then withdrawn
on a fairness call the owner made and I should have raised before filing
(below). calcurse #529 (interrupted `-P` leaves apts at zero bytes; the
syscall log shows `open(O_TRUNC)` then the kill), devtodo #9 (same shape
on .todo, and the next run says "database corrupt" in the target's own
words — withdrawn), stow #139 (the unfold sequence
`unlinkat(sub)` → `mkdirat(sub)` → `symlinkat` ×2, killed anywhere inside
it, leaves the already-stowed package unreachable). Each carries a
measured reproduction rate — 5/5 with injection, 2/2 clean without — and
each names what was not checked. The stow report says outright that no
atomic symlink-to-directory swap exists and asks whether documenting or
detecting the window is preferable, because pretending not to know that
would waste the maintainer's time.

**buku did not survive, and that is the entry worth keeping.** Thirty
eight plain kill points — eight on db writes, ten on journal writes,
twenty on the two interleaved — all end with sqlite rolling back and buku
reading its store normally. Zero reproductions. The engine's recorded
world is not withdrawn (the checker failure with buku's own `initdb():
file is not a database` is committed), but two things follow. A finding
that only our harness can produce cannot be reported, full stop. And the
earliest violation in that run was L0, a BYTE comparison — for a
journaled database, a mid-transaction byte state is precisely what the
journal recovers from, so L0 is stricter there than sqlite's own
contract. That is a limitation of judging a journaled store by file
bytes, not a defect in buku, and it means the finding rests on the single
checker failure alone until someone reproduces that world plainly.

**And a third question, which the owner asked after the filing and which
belonged before it: should this project be on the receiving end at all?**
devtodo is a legacy project its author calls stable, star count in single
digits, chosen for the cohort because apt had it — not because anyone
here uses it, and not because its users needed the news (Debian's tracker
already carries adjacent reports on the same code path). A data-loss
report from a stranger who does not use your software is work you did not
ask for, and the evidence value of filing it accrued here, not there.
The issue was withdrawn with two sentences (a long apology is more of the
same imposition), the finding stays in this repository, and the rule now
sits in `spike/assisted/PROTOCOL.md` at TARGET SELECTION, where the cost
is actually incurred: explore anything, but decide before running whether
a finding would be reportable, and record that decision with the target.

The general lesson, recorded because it will apply to every future
finding: novelty asks "has anyone reported this", the report step asks
"can anyone else see it", and the step before both asks "is it fair to
send this here". Today the second question killed one of four findings
and the third question killed another — both after they had passed the
first.
## 2026-08-15 — The novelty round: four searches, four not-founds, and the boundaries say so

The step the criterion-1 redesign designated ran the same day: recorded
tracker searches with positive controls, the campaign-1 shape, for all
four assisted findings. Verdict on every one: **not found — novel as far
as each search sees** (`spike/assisted/NOVELTY.md`, terms and hit counts
recorded for re-running). The controls did their job in three different
shapes: buku's proved the vocabulary reaches issue BODIES (a body-only
"corrupt" match), calcurse's found a real existing apts-corruption issue
by the same word that would have found ours, and stow's used the domain's
own vocabulary (twelve fold/unfold threads, ten open) while every
crash/interrupt/atomic term returned zero — the failure class is absent
from that tracker's language entirely.

**The review round earned its keep on the denominator.** The first pass
enumerated devtodo's Debian BTS from the OPEN view — 4 bugs — and called
it the tracker; the combined open+archived view holds ~70, including
grave #511342 among 72 bugs, which sits on the exact code path our finding kills:
`open(".todo", O_TRUNC)` on the in-place rewrite — reported for IGNORED
ERROR RETURNS (EACCES, exit 0, nothing written, no crash anywhere in it;
fixed in 0.1.20-4). Same path, other side of the syscall boundary; the
not-found verdict survives, and the disposal is now written down instead
of lucky. The same round corrected the counterparty claim (the
"unmaintained since 2010" line was the Debian QA opener's — the upstream
maintainer replied "It is maintained, it's just stable" in the same
thread), caught a `--limit 20` ceiling transcribed as a hit count
(calcurse's apts term: 34, and the 14 hits beyond the window contained
two plausible titles, both read, both disposed), and left ~25 extra
probes across the four trackers with no verdict changed. A results
document whose defining property is re-runnable coverage got exactly the
review such a document deserves: the reviewer re-ran it.

Standing notes: stow's GNU mailing-list archives were not searched (the
one adjacent thread, #29, ARRIVED from the list — suggestive of
funneling, not proof), and buku's mechanism attribution (buku's sqlite
usage vs an unavoidable tear) is deliberately left for the upstream
conversation — novelty asked whether the finding was already reported,
not whose fault it is. Upstream contact is the next step and needs
per-report owner approval.

## 2026-08-15 — Criterion 1 is redesigned around provenance (ADR 0017), on the owner's ruling

The §18-class decision #118 reserved for the owner is made: option A of
three presented (redesign / add an OR-route / keep and re-arm blind).
The criterion's gate moves from "the question was posed blind" to "the
question's provenance is recorded and labeled"; novel, author-confirmed,
fixed and replayed stay exactly as they were, and an assisted finding
still may never wear the blind label. The full argument for why this is
a redesign and not a moved goalpost — the order of evidence, the
pre-committed rule in #118, the falsified hypothesis — is ADR 0017; the
PRD's criterion text and status trail now carry it.

Alongside, three bookkeeping debts flagged by review: ADR 0012, 0015 and
0016 still said Proposed after their Seal A PRs merged (the repo's own
convention flips them at merge); flipped now with the flip's lateness
recorded in the status line itself. What this unlocks next is mechanical
and deliberate: tracker searches with positive controls for the four
assisted findings — stow's unfold, devtodo's in-place rewrite, buku's
torn db, calcurse's purge — then upstream contact for whichever survive.

**The adversarial R1 reshaped the ADR more than any review today reshaped
code.** Its charge was to refute the redesign-not-goalpost argument, and
it could — against the draft as written, not against the decision. Three
sentences claimed more than the record: "run to exhaustion" (only the
sealed pool is spent; ADR 0012 leaves the fresh-seals door open),
"before any of the evidence existed" (the nulls WERE known when #118
pre-committed the redesign path — the true margin is eighteen minutes
before the first assisted run, found in the issue's public edit history,
now disclosed rather than discoverable), and "falsified the hypothesis"
(the experiment measured where the constraint was; topydo reached
verified counterexamples blind and still failed on novelty, so reaching
a verdict was never the value claim). Each was rewritten to the measured
statement, which is stronger, not weaker. The review also found the two
structural misses: DESIGN §17 still carried the old criterion (ADR 0012
names PRD/DESIGN as its joint home — the same-class sweep stopped at
PRD), and the new text had a hole the old one covered implicitly — no
requirement that the question precede the answer, through which
timewarrior's "partial" would have silently become a pass. The criterion
now requires the invariant committed before any observed failure, and
the ADR re-scores all three past findings explicitly. The owner's ruling
(option A of three) is posted to #118 with this merge — the review
rightly noted a decision whose defence rests on pre-commitment cannot
live only in a session transcript.

R2 confirmed all sixteen R1 findings closed and then found the guard's
own hole, in this workspace's most familiar shape: the sentence added to
close H5 was itself unlimited — "before any failure of the target was
observed" names no observer and no mode, so read literally it
contradicted the ADR's own re-scorings (topydo's failure surface was on
a public tracker since 2023; every mature assisted target likely has
failure reports somewhere). The wording now says whose observation
counts: "before THIS PROJECT observed any failure of the target IN
EXECUTION (reading a report of a failure while scouting is not observing
one)" — timewarrior still blocked (its strace triage WAS this project
executing and observing), scouting still legal by text rather than by
charity. R2 also caught the ADR naming the wrong proof mechanism for
assisted ordering: the proposal-artifact-first rule it cited was broken
on three of five first-cohort targets (RESULTS.md's own record), and no
verify-seals equivalent exists for the assisted funnel — the ADR now
says the honest weaker thing (committed define + measured windows +
review, not a seal) and names the machine-check as open work. One digit
rounded the wrong way (eighteen → seventeen minutes) — in the sentence
that says "it is the true one", of all places.

## 2026-08-15 — v0.8.0, and the README stops being a changelog

The bump rides the owner's earlier ruling (next engine change ships a
release; contract v9 is that and more). With it, an owner instruction:
the README had gone stale — its Status headline still said "v0.5 — the
loop closes" two minor versions later — and it should be SIMPLE, per the
Utrecht reproducibility workshop's README guidance (title/description →
installation → usage → example → license; plain language; copy-paste
commands; short scannable sections; link out for depth).

The rewrite's structural decision: **the per-version milestone list is
gone.** It was the README's main rot engine — a hand-maintained shadow
changelog that had to be extended every release and wasn't (the v0.5
headline), on top of the sample-report block that missed new report
lines two PRs running. Version-relative narrative now lives where it is
already maintained (CHANGELOG, PRD); the README keeps one Status line.
The sample FAIL report is now REAL regenerated output from this release
(toy-bug cross-compiled, explored in the container with checker +
oracle) — which immediately caught a third drift instance: the old
hand-patched sample was missing the `expected  exit 0` line that reports
have carried since #98. Real output wins arguments that careful editing
keeps losing. The real-tools sentence names the six targets with
replay-confirmed counterexamples and says plainly that only two are
upstream-reported and the rest are novelty-unchecked — the same honesty
budget the reports themselves spend.

The judge-first ruling paid out the same day. The committed defines from
the #118 cohort, re-run unmodified against main `647acbf` (v9 engine +
option b) in the cohort's own container: **stow FAIL 2/5** at the unfold
window (`unlink(target/sub)` → `mkdir(target/sub)` — the fold symlink is
destroyed before the real directory exists, exactly the L0 `missing` R2
forecast, with the L2 checker agreeing), **devtodo FAIL 6/8** (the XML
database rewritten in place through truncation — crashed content neither
old nor new), **buku strict FAIL 2/22 with the oracle agreeing on all 21
operations** (the #120 suspension resolved the way R1's analysis said it
would: the question re-posed fresh, the torn-db answer came back
verified, `fchown x1` observed-and-excluded in the report), and
**calcurse FAIL 1/11 re-recorded under v9** (its cohort case was v8,
dead by contract mismatch — the cost the CHANGELOG named, paid). pass
stayed UNKNOWN on exec detection — the control confirming #123 is real
remaining work, not noise. All four cases replay from committed files in
a fresh container (rc=1, reproduced). One slip recorded: the first stow
run's `--rm` container discarded the saved case; repeated in one session,
identical verdict both times. Full record: `spike/assisted/REMEASURE.md`.
Novelty of all four findings deliberately unchecked (separate step).

## 2026-08-15 — Ownership and permission writes become recorded-only (#121, option b)

The second half of the owner's judge-first ruling. Option b was chosen in
the issue's own terms: the cheap unblocking that declares, in the
contract's terms, that ownership/permission bits are outside the judged
state. The oracle gains a metadata table (chown/lchown/chmod path forms,
fchownat/fchmodat *at forms, fchown/fchmod fd forms — the last scoped from
the descriptor annotation like every fd syscall), and an occurrence on the
state directory is appended to a per-run list instead of routing anywhere
that refuses. Three exclusions travel together, deliberately: not
`unsupported` (the subject's branch), not a touch (the child branch — a
child's chmod changes nothing the verdict judges either), never a kill
point. An UNRESOLVABLE metadata write is counted too: over-reporting an
exclusion is the honest direction, because the report says "excluded",
never "did not happen".

The report grows a constant `metadata_writes` field (text + JSON, §13).
Its no-oracle default is the point of the design: "not observable (no
oracle ran; the shim does not interpose ownership/permission calls)" —
the buku scoring suspended a finding precisely because nothing could see
the fchowns behind an --allow-unverified run, and a field that read "none
observed" there would repeat that lie structurally.

No contract bump: the trace format and every class's meaning are
untouched — the shim records exactly what it recorded before. What
changed is what the ORACLE does with syscalls the shim never saw, and
the report schema (documented, schema-checked in CI by check 4's
field-parity claims).

CI carries the end-to-end pin: acceptance 2w-b drives a toy chmod on
state under strace — PASS with the note in both report forms, where the
pre-#121 binary answered UNKNOWN unsupported_syscall_observed (the
seen-red inversion, same argument as 2v) — plus the control that keeps
the net honest: a toy mknod must still refuse, because the exclusion is
a defined list, not a loosened net.

Mutation record, against the committed code (commit first, then mutate):
chmod removed from the path table, the path form gated to the primary
only, fchown removed from the fd table, and the unresolvable arm demoted
to inside-only — each killed by the #121 unit test's corresponding
assertion. The report-note aggregation in main.zig is deliberately not
mutation-tested at unit level; 2w-b is its proof, against real strace
output on CI.

**R1 (same day) found the same pattern #122's review found — removing a
refusal exposes what the refusal was hiding — three more times.** (1) A
chmod-only operation lands in the zero-op PASS branch, whose headline
("performed nothing that can change the state directory") R1 measured to
be plainly false over a changed mode, and which printed no metadata line;
the headline now says "the judged state" and the branch prints the note.
(2) restore() flattens ownership/permission to the engine's defaults —
crash worlds do not run under the recorded modes, which is both the
likeliest way the cohort re-runs could stumble and, correctly read, just
option b's declaration showing up at world level; the metadata note now
says so per run rather than leaving the next investigator to rediscover
it. (3) deleteTree accepted a PARTIAL failure — an unreadable 0000-mode
directory is skipped silently by opendir, its rmdir fails, and a
deletable sibling made the pass count as success, leaving residue for
the next world to be judged against (the function's own history entry,
survived by its own fix). The pass now requires every collected entry
removed; a non-root test pins it with a locked directory beside a
deletable file. R1 also demanded the exclusion's own predicate be pinned
rather than inferred: a new engine test asserts a chmod leaves the
snapshot byte-identical — if Entry ever grows a mode field, that test
goes red and the report wording has to change with it. Table hygiene from
the same round: fchmodat2 (glibc 2.39 spells flags!=0 fchmodat with it)
joins the table — built from the syscall family, not from what the
cohort happened to hit — and the timestamp family is documented as
deliberately absent (widening the exclusion is its own ruling, not a
side effect). Fix-round mutation: the deleteTree guard reverted to
`removed == 0` is killed by the partial-failure test.

R2 caught the fix under-covering its own finding: the restore-flattening
sentence rode only the writes-observed branch, while flattening is a
property of RESTORE, not of the target's syscalls — a setup-created 0600
file runs its worlds at 0644 whether or not the target ever chmods,
which is precisely the buku shape (sqlite fchowns only as root). The
sentence now rides both branches. R2 also measured that the zero-op
disclosure works end to end, verified the deleteTree strictness has no
false-fail path (an unreadable-but-EMPTY directory still rmdirs on the
parent's permission alone), and noted one behavioural edge worth naming:
a name vanishing between readdir and unlink — a still-writing straggler —
used to pass silently and is now a loud SETUP ERROR, consistent with the
quiescence refusals. And the README's sample report block missed the new
report lines for the SECOND consecutive PR (the string sweeps keep
stopping at acceptance pins); fixed again, and the recurrence is flagged
to the owner as a structure question, not another instance fix.

## 2026-08-15 — Symlinks become a first-class operation; the real gap was restore, not the oracle (#122, contract v9)

The owner's ruling on #118's product decision: close the judge's measured
gaps first (#122, then #121 option b), re-run the blocked committed
defines, and only then decide §18 with a re-measured number. This entry is
the first half.

The oracle table was the visible absence, but the engine was the real
work: snapshot recorded a symlink as "present but opaque" (kind `.other`,
no target) and **restore did not recreate it at all** — a state directory
with links would have started every crash world with the links missing.
That was tolerable only because the oracle refused symlink-touching
targets before any world ran; making the class supported without fixing
restore would have shipped fabricated worlds. So: snapshot content is now
the readlink target (fail-closed on a result that fills the buffer —
truncation cannot be told from an exact fit), restore recreates links
verbatim (a dangling link is restored dangling), and judgeL0 checks kind
before content — a regular file holding the pre-target as *bytes* would
otherwise satisfy the content comparison while being a different thing.
That kind check also closes part of the standard arm's documented
empty-content blind spot (an empty pre file replaced by a directory used
to compare equal).

Decisions made here, with their reasons:

- **Contract v8 → v9.** The v6 precedent (link/linkat) decides it: adding
  a class changes what a trace means, and a v8 shim beside a v9 engine
  must refuse loudly, not diverge positionally. Cost accepted: every
  saved v8 case replays as `case_no_longer_applies` — the assisted
  cohort's two committed cases need re-recording, and #82's pending
  re-record stays pending.
- **`aux` stays empty for symlink.** The target string is content the
  subject chose, not a path this run touches — the oracle already
  excludes it from scoping (its path table lists only the link-path
  argument), and recording it would hand every later consumer a
  plausible-looking "path" that must never be resolved. Symmetry beats
  convenience: nothing that needs the target exists today (restore reads
  it from snapshots, not traces).
- **corruptState retargets links** at a probe name that exists nowhere,
  and the falsification gate counts corruptible entries (files + links)
  instead of files — a stow-shaped state (directories and links, zero
  regular files) used to read as "nothing to corrupt", which would have
  refused exactly the target class this change exists to reach.

Mutation record: four guards, each killed by the test written for it —
judgeL0's kind check, restore's symlink arm, corruptState's retarget, the
oracle's class entries. The first corruptState mutation was invalid (it
left an unused local and died as a compile error — a red for the wrong
reason); re-shot as a compiling no-op branch and killed by the fs test.
The shim wrappers have no unit-test harness (nothing loads the .so in
`zig build test`); their end-to-end proof is the container re-run of the
stow define, which is the next step's acceptance criterion.

**R1 (same day) reshaped the change in two ways worth recording.** First,
the certain CI red: acceptance check 2v still demanded the refusal this
change removes — R1 also measured, on macOS, that the TOY_SYMLINK run now
PASSes with the symlink counted (crash points 4 → 5), which is the first
live evidence of the macOS interposer working. The check is flipped to
assert the v9 contract (PASS + exactly one class-10 record) and becomes
the Linux end-to-end pin. Second, and central: removing the oracle's
refusal EXPOSED a pre-existing silent skip — a shared path whose kind
changes between the clean runs (stow's unfold: fold symlink → real
directory) was outside both built-in invariants and outside the report's
disclosure. The owner ruled to judge it in full rather than disclose-only
or refuse: the identity on each side is the (kind, content) pair, killed
mid-swap the path matches neither, and the file world's delete-then-
recreate window was already judged `missing` — the kind change was an
escape hatch, not a policy. L1's standard arm now promises the post
(kind, content) pair from the plan, and a post-only symlink is judged by
target (the existence-only rationale — content may differ between runs —
does not transfer to a link, whose target is its whole identity).

R1 also caught this entry over- and under-claiming. Over: the readlink
fill-the-buffer guard could never fire on a real platform (`max_path` ==
PATH_MAX), so "fail-closed" was a claim nobody could falsify — the guard
moved into `readLinkTarget(buf)` and the boundary is now hit for real by
a test with an 8-byte buffer. Under: two silent-wrongness fixes this
change makes were never claimed — `snapshotsEqual` now distinguishes two
links with different targets (both read as `.other` + empty content
before), and `kindOfPath` no longer reports a symlink-to-file as a
regular file on DT_UNKNOWN filesystems (it used to read the POINTED-AT
bytes into the snapshot). Both are real fail-open closures that came
along with making the kind first-class. The judgeL0 kind strengthening
also reaches beyond symlinks: an empty pre file replaced by a directory
used to compare equal and no longer does.

Fix-round mutation record: the classify skip-revert, judgeL0's pre-kind
half, L1's post-only target check, and the readLinkTarget `>=`→`>`
boundary — each killed by exactly its own test. One process slip during
the round, recorded because it will happen again if unrecorded:
`git checkout -- src/engine.zig` after a mutation run reverted the file
to the last COMMIT, which silently discarded the not-yet-committed R1
fixes and made the next mutation a no-op against old code (rc=1 for the
wrong reason — a compile error in a neighbouring file). The fixes were
re-applied and committed BEFORE re-running the mutations; the rule is
"commit first, then mutate", and the redo killed all four legitimately.
Left alone on purpose: `spike/assisted/RESULTS.md` still says stow is
blocked — it is the first cohort's sealed record, and the re-measurement
writes its own.

## 2026-08-15 — spike/ gets a map; the cleanup that was NOT done is the point

Three campaigns plus the assisted cohort left spike/ dense enough that the
owner asked for a tidy-up. The honest finding: most of what looks like
mess is sealed design. The per-campaign tool copies are the forward-carry
rule (check-sealed-campaigns.sh fails a campaign that dropped its
checker); sealed directories take no new files (ADR 0012 would mark
campaign 1's checkers sighted); and the assisted `ops/explore.sh` paths
are named by #121–#123 as acceptance tests. So the tidy-up is a README
that says which rules protect what — plus ~37MB of gitignored local run
outputs (`spike/out`, `spike/runs`, `assisted/runs`) sent to the trash,
every committed report and transcript being on the tracked side already.
The dogfood-era scripts stay in place: BUILDLOG and ADR prose cite them by
path, and a stale citation costs more than the directory listing it
saves.

## 2026-08-15 — The #118 scoring lands, on two axes; the gate was aimed at the wrong failure mode (#118)

The owner scored the cohort — and rejected the one-axis form as too kind
before signing. Question quality: 5/5 meaningful (no vacuous-checker trap
appeared anywhere in the funnel). Drivable-slice discovery value, the
harsher axis the product decision actually needs: **1.5 of 5** — calcurse
found (verified), buku *suspended* rather than pending (the strict run's
fchown refusal means the shim's record may be incomplete in exactly the
way that could fabricate the torn-db world — after fchown support the
question gets re-posed, the unverified FAIL is not "a finding awaiting
confirmation"), stow high-but-blocked, devtodo real-but-light (a target-
selection critique, not a question critique), and pass low — its
meaningful contract's engine-drivable slice is the near-trivially-atomic
rename, which the first self-assessment glossed.

The inversion is the finding about the experiment itself: the metadata
gate was built against an agent posing vacuous questions, and that failure
mode never appeared; the binding constraint was the judge's reach. Scoring
recorded in each RUNLOG and RESULTS; next is the engine-gap issues and
then #118's product decision on 1.5/5-today plus minutes-not-hours.

## 2026-08-14 — The assisted-discovery cohort: five targets, five verdicts, the human half still owed (#118)

The #118 experiment's measured half ran end to end (the human
meaningful-question scoring — part of the success signal by the protocol's
own definition — is still owed to yotta, so the signal is NOT claimed
cleared): five fresh apt-installable targets
(buku, pass, calcurse, stow, devtodo — todo-txt verified installable and
excluded because the scout already knows the todo.txt format's crash shapes
from campaign 1), one measured window each, the SCOUT.md loop as the only
instructions. Full record: `spike/assisted/RESULTS.md`.

The headline: **calcurse gave a VERIFIED, replay-confirmed counterexample
109 seconds after first contact** — `-P --purge` ("Read items and write
them back", the help text naming its own window) truncates `apts` in place,
and the crash between open and write destroys the bystander event the purge
never named. The topydo class, strict oracle agreeing 10/10. buku added an
unverified-oracle FAIL (mid-write crash leaves the db unreadable to buku
itself), replay-confirmed but resting on --allow-unverified.

The equally important half: three of five funnels stopped at the ENGINE,
not at the scout. fchown (buku/sqlite), symlinkat (stow/perl), fchmodat
(devtodo) — three measured absences from the trace contract, no common
family claimed (the first draft's "*at family" was technically false and
R1 said so); and pass's measured refusal is exec image replacement —
that shell-script CLIs hit it as a class is inference, labeled as such. Every one of those questions was
posed, with why/what-property/where-from metadata, in under two minutes —
the judge just could not execute them. Against #118's success signal: T0→define landed in 1m25s–5m02s on all
five. The blind-arc comparison sits in RESULTS as context, not a ratio —
the scopes differ in almost every dimension (this branch's own
apparatus-to-results arc was ~25 minutes for five targets; campaign 3's
sealed arc ~1.5h for one). What remains standing after the scout is engine
coverage — issueable, buildable work rather than a skill wall — plus the
human meaningfulness verdict.

Also on the record: DeepWiki was wrong once about the pinned build (buku's
env var — re-measured, corrected); the proposal-artifact-first rule was
broken on THREE of five targets (calcurse, stow, devtodo — the first
summary admitted only calcurse; R1 caught the other two by file birth
times); a grep pipe ate one exit code before the raw-rc habit caught it;
and SCOUT.md gained a measured-lessons section.

R1 of this branch: sixteen findings, all adopted. The load-bearing ones
beyond the above: the committed saved cases embedded gitignored paths and
could not replay from a fresh checkout — every target was RE-RUN from the
committed ops dirs (identical verdicts), committed launcher scripts now
carry the exact environment (the buku/pass defines were irreproducible
without it), and the buku claim chain gained its committed artifacts
(strict report, replay transcript, the target's own error line). The
calcurse "verified" is scoped: the oracle's account covers the declared
data subtree, with the config dir deliberately ambient. The devtodo
checker counted lines, not occurrences; stow's dangling-link scan piped
find into head (fail-open); both hardened, both still unexercised by any
exploration. The Dockerfile's "pinned" claim is corrected to pinned-by-
build with the actually-run versions recorded.

## 2026-08-14 — Campaign 3 explored: khal, three ops, zero violations (#83)

Exploration from Seal B `9028b04b` completed: import 10 crash points +
baseline, update 21 + baseline, new 10 + baseline — **every world PASS,
violations 0** across 41 crash worlds (10+21+10) and 3 baselines. The full verifier
over Seal A, Seal B, the run manifest and the sealed sweep reports says ALL
SEAL CHECKS PASSED (R1 audited) — transcript committed as
`spike/blind-hunt3/analysis/verify-seals.txt`. The engine's falsification
gate fired in all three runs (corrupted state → the checker's I-C leg
failed), closing post-seal the red side the declaration deferred.

The surprise is what did NOT happen: both pre-registered refusal
expectations (update's random-suffixed leftovers, new's random
UID-as-filename) did not fire — the recordings were accepted and explored
in full, wider coverage than the declaration promised itself. The findings
record the acceptance and deliberately not a mechanism: the mechanism was
not measured, and asserting one would be the claim-exceeds-measurement
shape this campaign kept meeting. Update's oracle numbers (170
state-directory syscall lines vs import's 81) are quoted as consistent
with the normal-run temp-file observation, nothing stronger.

A null result, recorded at counterexample precision
(`spike/blind-hunt3/analysis/findings.md`). Campaign accounting: khal
consumed; hledger is the only name left in the order and is unselectable
while its sweep refusal stands (understanding it means unsealing the
refusal reason — deliberately not done). PRD criterion 1: **two
designated-path campaigns have now returned null**; the remaining path —
more campaigns, a different target class, or §18's kill analysis — is
recorded in PRD as an open decision.

## 2026-08-14 — The khal declaration: one live search, two pre-registered refusals (#83)

Campaign 3's declaration phase, from permitted sources only: the full help
set, the version-pinned usage page (the image ships no khal man page —
probed, 0 hits under the man trees, recorded in sources-provenance), and
one normal run per candidate form. Three operations declared, all
reaching the vdir through documented non-interactive argv: **import of a
fixed-UID .ics** — the live search, byte-deterministic in observation, the
event file named `<UID>.ics`; **import-update of the same UID** — declared
with a pre-registered refusal expectation, because the NORMAL update was
measured leaving random-suffixed leftover files in the vdir (names differ
across runs: baseline-irreproducible, the khard/watson shape — and the
observation is quoted in the declaration so nobody later mistakes it for a
crash finding); **new** — pre-registered refusal, random UID-as-filename
plus DTSTAMP=now, measured. `edit` is excluded on the documentation's own
word ("an interactive command"), `configure` and the TUI on observed
prompts, the ask-first and stdin import forms on channel. The recovery-path
rule discharges vacuously over the widest readable base (help set + usage
page: zero recovery-vocabulary hits). The todoman storage-class disclosure
duty is discharged in the declaration itself.

Two khal-specific checker decisions, both measured before being relied on:
khal's search exits 0 even on no match, so I-Q anchors the exact observed
output line (`grep -Fx`) instead of the exit code — and the red suite's
impostor probe measured khal's search as substring-matching, exactly the
tolerance the exact-line anchor exists to reject; and khal's `list` CREATES
a missing configured vdir (measured, filesystem-verified; no other query
was measured doing this), so the checker only ever
queries a vdir its file legs proved populated, with a fresh scratch HOME
per query so the ambient cache is rebuilt cold every time. I-W (queries
write nothing into an existing vdir) is promoted to a declared invariant —
a crash-world query that "cleans" what it reads would violate it. Red: 15
cases, message-pinned, green first try, real khal touching only
khal-written/empty/absent stores, misbehavior through the CHECK_KHAL stub
seam, plus the golden drift-gate. Green: exec-bit spawns throughout (ADR
0016 requirement 3 — the exec bits were set before anything ran), verbatim
toml operations matching expected_status, effects asserted, parse probes
stopping at state resolution with probed paths untouched. Engine and shim
SHA-256 equal the sweep manifest's: R3 pre-verified.

R1 of this declaration: nine findings, all adopted. The claim-exceeds-
measurement class again (the sixth and seventh instances today): the `new`
paragraph asserted byte-difference, UID-as-filename and DTSTAMP=now when §3
had shown two filenames and one file — §3 now prints both files, cmp's
their bytes with names aside, checks UID==stem for both, and brackets the
run with a reference clock, so the claims stand as measurements; the
create-missing-vdir observation is now filesystem-verified and scoped to
`list`; "ships no man pages" became a recorded probe; the transcript line
count is corrected (588). The apparatus-accounting error — the ledger said
the red suite runs real khal "only as search" while the drift-gate runs
real import three times — is corrected in an appended ledger entry. The
red suite gained the branches R1 found unexercised (update/new dispatch,
update's I-T, the missing-sealed-conf environment branch, a parameterized
scribble target): 19 cases, still all message-pinned and green. The green
run now GATES its stages (a failed prerequisite aborts that op's remaining
stages) and its parse-probe claim matches its predicate ($HOME/.cache is
asserted, not just named). The unexercised-variant column is explicitly
inventory disclosure with per-variant reasons — --random-uid is undriven
for the same determinism reason `new` carries a refusal, not silently.

## 2026-08-14 — Campaign 3 swept: khal accepted, hledger refused again (#83)

One sweep, through the driver, from Seal A `2239fba`, displayed per the
harness contract as exit codes only: **khal 0 / hledger 2** — the same
public values as both prior sweeps, hledger's refusal reason still sealed
and unread. Full reports sealed locally; their hashes travel in the
committed manifest, whose engine and shim SHA-256 are byte-equal to
campaign 2's sweep (same pinned image, same binaries). The sealed selector
over this manifest picks **khal**, which triggers the pre-registered
disclosure duty: khal shares the vdir/iCalendar storage class with todoman,
which this project has explored — the campaign report must say so. Process
note, disclosed in the PR too: the sweep-record commit was first created on
the local main by mistake, caught before any push, and moved to its branch;
origin/main was never touched.

## 2026-08-14 — Campaign 3 opens: khal then hledger, the lessons as requirements (#83)

The apparatus for the third campaign (ADR 0016): `spike/blind-hunt3/` is
campaign 2's sealed tooling copied with paths adapted, plus the content that
changes per campaign — the order is khal → hledger (khard burned, abook
consumed), the khal random-`.ics` refusal risk and the todoman storage-class
disclosure duty carry restated, and campaign 2's six paid-for lessons ride as
declaration requirements rather than advice (file-first checker, no
out-of-contract store ever shown to the target, 755 + engine-path green,
audit-order commits, refusal as an `expected_status` operation, fail-closed
runner with engine identity). The adaptation was swept for leftover
`blind2`/`blind-hunt2` strings — zero hits **in the operational apparatus**
(tools, configs, invocations; the ledger's own narrative names campaign 2
legitimately, so a whole-tree grep does hit and the claim is scoped to what
the sweep actually covered) — and `check-config-paths.sh` is green, because
a config still naming another campaign's state root is exactly the class
that voided campaign 2's first seal.

The rehearsal caught the first real defect before the seal, as designed —
and it was in the rehearsal itself: two walker drills fabricate a "new
campaign" to test the checker walk, and they had fabricated it under the
name `blind-hunt3`. With the live campaign now bearing that name, walker3
copied its planted defect onto the real campaign copy (which HAS an
executable checker) and walker4's "pre-sweep" dir already had invocations —
both drills went green-for-the-wrong-reason and the suite failed 2/42. The
fabricated name is now `blind-hunt9`, and "never live" is a run-time guard
rather than a hope: the rehearsal refuses to start if the fabricated name
exists in the real repo or equals CAMP (R1 of this seal pointed out that a
bare rename repeats the same collision one campaign later). A harness note
on the way: the first rehearsal run was piped through `tail -15`, which both
truncated the failures out of view and replaced the suite's exit 1 with the
pipe's exit 0 — the raw-rc re-run is what surfaced the red. 42/42 green
before the Seal A PR opened.

R1 of this seal: five findings, all adopted. The P1 was in the void-class
gate itself — `check-config-paths.sh` resolved config references by
BASENAME, so a stale `/work/spike/blind-hunt2/configs/khal.conf` in a row
would have been checked against campaign 3's file and passed while the sweep
read campaign 2's config: the exact contradiction the gate exists to refuse,
reachable through the gate. The discovery rule now requires the reference to
name THIS campaign's mounted configs dir and the file to exist — refuse
loudly, never remap — and the new predicate was falsified both ways before
this entry was written (stale cross-campaign reference → refused with the
pinned message; missing config → refused; the real rows → green). The P2s:
the mechanical `s/campaign 2/campaign 3/` comment adaptation had rewritten
history (this campaign's tool copies claimed campaign 3 "already voided a
seal" and re-attributed campaign-2 R1/R2 findings — eleven comment sites
restored to honest attribution, "carried" where inherited); the fabricated
rehearsal campaign gained the run-time guard above; the zero-hit scan claim
is scoped; and the verifier's header summary contradicted its own B1 leg
(invocations are sealed at A, only the manifest first appears at B — the
summary now says what the code checks).

## 2026-08-14 — Campaign 2 explored: abook, three ops, zero violations (#83)

The exploration from the re-sealed Seal B `eb51c483` completed: import 2
crash points + baseline, export 2 + baseline, refused 1 + baseline —
**every world PASS, violations 0**. The refusal path ran as a declared
`expected_status = "1"` operation and never damaged the store it refused to
replace. The full verifier over Seal A, Seal B, the run manifest and the
sealed sweep reports says ALL SEAL CHECKS PASSED (R1 audited) — the
invocation transcript is committed as
`spike/blind-hunt2/analysis/verify-seals.txt`, so the
claim is checkable from the repo, not prose — declaration before
exploration, clean tree at the seal, sweep and exploration on
byte-identical engine and shim. The engine's falsification gate fired in
all three runs (corrupted state → the checker's I-C leg failed), closing
post-seal the red side the declaration deliberately deferred.

A null result, recorded at counterexample precision
(`spike/blind-hunt2/analysis/findings.md`): what PASS bounds (the declared
invariants, single process, the engine's crash model — its own not-tested
list rides in every report) and what it does not (abook's crash safety in
general; the TUI and stdin surfaces are undriven). Campaign accounting:
khard burned, abook consumed by exploration, khal the only unconsumed
candidate, hledger's sweep refusal still sealed unread. PRD criterion 1
stays open; a third campaign is a resourcing decision.

## 2026-08-14 — Seal B's first exploration attempt: Permission denied before anything ran (#83)

Exploration from Seal B `84d0f2e1` returned SETUP ERROR for all three abook
ops. Root cause: the engine execs `./setup.sh` and `./check.sh` directly —
no shell — and both were committed mode 100644 (the Write path that created
them does not set exec bits; campaign 1's scripts were 100755). Permission
denied, exit 126, before a single instruction of setup ran. The green run
had proven setup through `sh ./setup.sh` — a shell spawn the engine never
performs. The measured path did not reach what the seal shipped: the same
lesson as the hook-run-by-hand class, now in the one place the campaign
cannot simply patch, because the declaration is sealed.

What makes this recoverable with blindness intact: the run observed nothing.
All three `.out` files hold exactly the engine's SETUP ERROR line; all three
reports parse with `verdict: SETUP_ERROR, crash_points: 0`; abook never
executed. The fix commit changes the two files' git modes and nothing else —
0 insertions, 0 deletions, every blob SHA unchanged, which the PR diff
proves mechanically. The fix PR's merge is the Seal B the exploration
actually runs from. Rule extracted (CLAUDE.md): declaration scripts the
engine execs are committed 755, and a green run must spawn them the way the
engine does — through the exec bit, not through `sh`.

## 2026-08-14 — The abook declaration: refusal as an operation, and a red suite the burn can no longer reach (#83)

Campaign 2's second declaration, written after the khard burn and carrying its
structural fixes as design, not as review patches. Three things decided here:

**The commit order is the audit trail.** Sources (help/formats/man pages from
the pinned deb, normal runs) were committed before a word of declaration
existed; the declaration before the apparatus. The khard round's single batch
commit made "observed then declared" unprovable; this branch makes the
ordering readable from history — local reordering remains possible (ADR
0012's honesty bounds), but the default story is now in the commits.

**Refusal is an operation.** abook's only non-interactive writer is
`--convert`; converting onto an existing outfile refuses ("cannot write
file", exit 1, store byte-identical — normal-runs §4). That observation
became a declared operation with `expected_status = "1"` (the v8 field
shipped for exactly this): an interrupted refusal is where a "harmless" path
could still damage the store it refused to replace. The other two ops are
import (fresh outfile; bystander store conserved byte-for-byte) and export
(the cross-file window: a reader must not scribble what it reads). No
refusal pre-registered — both writers observed byte-deterministic, twice.

**The red suite cannot re-create the burn.** The checker runs file legs
first and the target last, so a red fixture that fails a file leg provably
never reaches an abook invocation (each failure message names its leg — the
pin doubles as the no-execution proof). Real abook touches only
abook-written, empty, or absent NATIVE stores (queries over goldens — the
impostor anchoring probe: `Grace Hopperson`'s real match line is rejected
because the anchor demands the full name bounded by both tabs — and the
provenance case's converts, whose vCard inputs are the committed
hand-authored well-formed files, the documented-normal input class). Every
branch that needs an ill-behaved binary — wrong exit codes, duplicate match
lines, byte-writing queries, hangs, outfile creation — runs through a stub
via the checker's documented CHECK_ABOOK seam: those branches are exercised
and the target never runs. 17 red cases, message-pinned; the khard R1's
other gaps (green-run without setup/parse/binary evidence, missing engine
version in the run manifest) are answered in green-run.txt and run.sh.
Engine and shim SHA-256 already equal the committed sweep manifest's values,
so the R3 leg's comparison is pre-verified at declaration time.

**R1 of this declaration: ten findings, all adopted.** The two fixed review
axes cut into the new work exactly as they did last round. The ones that
mattered: normal-runs §4 had *printed* the store before and after the
refusal but never ran `cmp` — "store byte-identical" exceeded its
measurement (the same claim-vs-measurement shape, caught a third time
today; §4 now measures, and the probe was re-run). The "every store the
target meets is abook-written" rule as first written was false — green
feeds hand-authored vCard *inputs* to `--convert`; the rule now
distinguishes native stores from documented-normal input files. The
committed goldens had no drift gate (make-goldens silently re-baselines; a
red provenance case now regenerates into scratch and byte-compares on every
run). The green harness could pass without its operations doing anything
(setup rc ungated, effects unasserted, an empty extracted command exits 0
via `sh -c ""`) — setup is gated, extraction asserted non-empty, and each
op's documented effect is asserted. run.sh swallowed exploration failures —
it now requires each op's report to exist and parse, records per-op
exit/report state in the manifest, and exits nonzero on a missing report.
Sources provenance (deb version assert + sha256, bare-`abook` resolution)
now lands in a committed transcript instead of a terminal. `--add-email-
quiet` is kept excluded but for the honest reason — a documented stateful
form whose only input channel (stdin) the engine never supplies — and the
inventory says so instead of calling it a prompt. The mutt/muttq
outformat-name discrepancy between abook(1) and --formats is recorded.

R2 confirmed eight of ten and returned two as incomplete: the `interactive`
verdict still contradicted its own evidence text (resolved by stating the
label's sense once — ADR 0012 seals the four words without defining them —
and rewording the row under it), and the parse-probe section heading still
said "no side effects" while the probe inspects three paths (heading now
says "probed paths untouched"; transcript regenerated). R2 also verified
the ledger's append-only property byte-for-byte against the parent commit
and ran `sh -n` over the eight touched scripts.

## 2026-08-14 — khard is burned: the red suite let the checker query a malformed store (#83)

The declaration below shipped with a red suite whose header argued its own
safety: "khard itself only ever runs `list` over these stores." R1 read the
transcripts instead of the header: `checker-red.txt` line 13 ends with khard's
own error message for an unparsable .vcf ("Use --debug for more information or
--skip-unparsable to proceed"). The checker's first step is the `khard list`
liveness query, so the I-F red fixtures — vCards deliberately written
mis-shaped — put khard's failure behavior on record before Seal B. ADR 0012
has no cure for that: blind is once per target. The safety claim named what
the script runs, not what the run touches: the recurring shape where a
verification is trusted without asking what it does not look at.

Corrected after this burn PR's own R1 (the first version of this entry said
campaign 1 was safe "by structure"): campaign 1 ran the same design risk.
Its checker was also query-first — `check.sh` runs the I-Q `ls` before the
I-F file checks — and its red suite also fabricated stores violating its own
I-F predicate (`not-a-completed-task`, `x other-task` in done.txt). The
committed transcript shows the I-F messages firing, which means the I-Q leg
had already passed: topydo's query returned documented-normal output over
those out-of-contract stores, and no failure behavior was committed. Campaign
1 escaped by outcome, not by structure; campaign 2 collected the consequence
of the same red-suite design. (The uncorrected version of this entry was
itself the recurring shape — it asserted a mechanism, "only well-formed
stores, query-first was new", that no committed artifact supports.)

Burn handling per ADR 0012, before Seal B, so the campaign survives:
`burned.txt` now carries khard, the ledger records what leaked, the khard
declaration leaves the tree (history keeps it at a459995), and selection
re-runs with the burned name skipped — abook by the sealed order, if the
selector agrees. The structural fix rides the next declaration, not a review
round: file inspection first, the target query last, and red fixtures that
are well-formed only (an empty store — documented-normal — is the one
permitted refusal shape). The next declaration also inherits R1's independent
P0/P1s: pin every red case to the message of the guard that fired, exercise
the counting branches, complete the unexercised-form inventory, and keep
every claim inside what its transcript actually shows.

## 2026-08-14 — The khard declaration, written blind, with two refusals pre-registered (#83)

Campaign 2's declaration phase, from permitted sources only: the sixteen-command
help, three man pages, two docs pages, RFC 6350 through the carve-out, and one
normal run per declared form. Four operations declared — `new`, `remove
--force`, `move`, `copy` — with `move` as the cross-file window (one contact,
two addressbooks: after a crash it must be in exactly one place). Three
subcommands excluded as interactive on hard evidence: `edit` waits for
confirmation even with `-i` and no stdin; `add-email`'s prompt loops unbounded
on EOF (~200MB of `Select?` in five seconds); `merge` is documented as needing
an interactive merge editor and errors without one.

The two honesty-first moves:

- **The recovery-path rule discharges vacuously, and the enumeration proves
  it**: no recovery, undo, restore or repair command form exists anywhere in
  the sealed documentation transcripts. The consequence is stated in the
  declaration instead of implied — a crash-damaged khard store has no
  documented in-tool recovery at all, which cuts both ways and the report will
  have to weigh it.
- **Two of the four declared operations carry pre-registered refusal
  expectations.** Measured in normal runs: `new` mints a random UID (filename
  and content) plus a second-precision REV, `copy` re-mints both, and
  khard.conf(5) offers no setting to fix either. The byte-reproducible
  baseline should refuse them — the watson shape — and that refusal is #84
  data the campaign wants, not a failure. `remove` and `move` measured
  deterministic (identical stores end byte-identical; move preserves filename
  and bytes), so they are the live searches.

Verification stayed inside the blind rules: the checker's red side is twelve
committed cases over hand-fabricated vCard files (khard only ever ran `list`,
and an empty book exiting 1 is documented-normal — it is also why every
declared state keeps a conserved bystander); the green side runs
setup → verbatim toml operation → checker for all four; the tomls parse on
the binary built from this very tree, inside the pinned container — not on a
host binary, which is the exact mistake campaign 1's declaration phase had to
correct after review. No preflight touched any declared define.

## 2026-08-14 — Campaign 2 between the seals: khard, by the sealed predicate (#83)

The sweep ran once against the re-sealed apparatus (Seal A = the #107 merge,
`8878df82`), through the phase driver, and displayed what the harness contract
allows: **khard 0 / abook 0 / khal 0 / hledger 2** — the refusal reason sealed
and unread, as it has been since campaign 1. `select.sh` over the committed
manifest recomputed **khard**: first in the sealed order, accepted, in-image.
With the config/invocation contradiction fixed, khard's verdict returned to
campaign 1's public value — consistent with the voided sweep's refusal having
been our apparatus, and nothing stronger than consistency is claimed.

The attempt also bought one more driver fix, live: with the docker daemon
stopped, `image_id`'s die was swallowed by the command substitution and an
**empty image name reached `docker run`**. Both call sites now stop the driver
(`|| exit 2`), red-measured against an unreachable DOCKER_HOST — the driver
dies naming the image, runs no container, creates no outdir. The rehearsal
cannot unplug docker, so this red lives in the PR record, not a drill; said
here rather than implied. (And this entry itself exists because the buildlog
CI check went red on the sweep PR — the same check that PR #103 was merged
over; this time it was read before the merge.)

Next, deliberately in its own session: the khard declaration — inventory,
invariants with provenance, the recovery-path rule's full form enumeration,
and Seal B. The pre-registered risk stands: per-entry random filenames may
refuse the byte-reproducible baseline, and a full-refusal exploration is a
recorded result, not a failure of the campaign.

## 2026-08-14 — #28: the version-mismatch test stops sharing its path, measured at 82% (#28)

The contract-version unit test wrote to a fixed `/tmp/sideeye-version-test/` and
`zig build test` runs the engine's tests in more than one concurrent binary. It
cost three CI round trips today alone — different assert lines each time, which
is what losing a race at different points looks like. The fix is the issue's own
prescription: a pid-suffixed directory (`posix.getpid()`, one new extern).

The measurement is the part worth recording. The first reproduction harness — an
external loop deleting the shared path — never landed in the microsecond windows:
its positive control stayed green at 0/15, which means it measured nothing, and
a "0 failures" from the fixed binary under that harness would have been the
day's fourth verified-nothing claim. The real adversary is another copy of the
same test binary, in phase over the same sequence (its `rmdir` is also the only
thing that can make `open(O_CREAT)` fail, explaining the `fd2 >= 0` variant).
Two old binaries racing: **66 of 80 runs failed**. Two fixed binaries racing:
0 of 80. The flake was never rare — CI was just rolling one die per push.
## 2026-08-14 — The campaign becomes a program: rehearsal, driver, R3, and a ledger pen (#83)

The re-verification question was blunt: what would let a blind hunt run without
the mistakes this session kept making? The answer that survived scrutiny is not
another checking layer — it is moving every apparatus error to before the seal,
where errors cost nothing, and removing the hand-typed procedure where the
sequencing errors lived. Four pieces, shipped together on the re-seal branch:

- **`spike/rehearse-campaign.sh`** — the whole pipeline against synthetic
  targets in a scratch git repository that mimics the real layout, so the REAL
  sealed tooling runs byte-for-byte unmodified. Defects planted one at a time
  (a sealed path edited between seals, a rewritten ledger, a tampered manifest
  hash, a wrong declaration, a wrong-head run manifest, a wrong-engine run
  manifest, a voided anchor, a cross-row config, a dropped checker, a vandalized
  ledger under the append tool, three driver refusals), each required to turn
  its guard red — with the guard identified by its MESSAGE, not just the exit
  code — then the real pipeline through the driver: container sweep, selection,
  a Seal B carrying a real runner, a real exploration, and the full battery's
  ALL SEAL CHECKS PASSED (R1 audited) over artifacts the shipped code produced.
  Forty-one drills. The first two versions each failed honestly: run one caught
  real behavior (this host's docker answers `image inspect <name>` flakily —
  both resolvers now accepted — and bookworm's /bin/cp is *correctly* refused
  by preflight because it copies via copy_file_range; the toy now writes
  through dd); the delta review then caught the rehearsal itself lying twice —
  two driver drills passing on the dirty-tree guard while claiming to test two
  other guards, and an "entire pipeline" whose exploration was a fabricated
  manifest. Both are the same shape as everything else today, inside the tool
  built to stop it. The current suite pins every red to its guard's message
  and runs the exploration for real.
- **`spike/campaign-driver.sh`** — every phase behind preconditions that refuse:
  dirty tree, uncommitted inputs, existing output directories, a manifest that
  already exists, a HEAD that is not the seal being explored. Unsealed by
  design: it carries no verdict logic, only the sequencing that was previously
  typed by hand — which is exactly where the fused-chain failures lived. It
  never merges and never commits.
- **verify-seals R3** (sealed, amended pre-merge on this branch): the run
  manifest's engine/shim SHA-256 must equal the committed sweep manifest's.
  The machine half of "measure the thing you ship" — the class that started
  today's chain.
- **`spike/ledger-append.sh`** — appends and proves the prefix against HEAD,
  restoring on refusal. The append-only discipline has now been broken twice by
  well-meant edits; the pen replaces the discipline.

CLAUDE.md gained the operating rules, including the two review axes external
review has repeatedly out-detected self-checks on (claims vs. what the
measurement looked at; guards falsified against their own predicate). What
stays honest: the rehearsal covers the apparatus, not the declaration's
completeness, and prose outside Verified sections still depends on review.

## 2026-08-14 — The same mistake three times in one session, and where the stop now lives (#83)

Three failures today share one shape, and naming it matters more than any of them
individually:

1. "All thirteen tomls parse" — measured with the host binary, not the revision
   being sealed.
2. "The configs carry no campaign-1 dependency" — measured by resolving
   references and checking files exist, never by opening the files, where
   `/tmp/blind` sat in two of them the whole time.
3. "The new guard is falsified" — measured against the defect that produced it,
   never against its own predicate. External review then found seven holes in it.

The common shape: **when I say "verified", I do not check what the verification
did not look at.** Each time the net was finer than the thing I claimed to have
caught, and nothing came up, so I reported safety. A rule against this already
existed ("measure before trusting a check"), and existing prose did not stop the
third repeat — which is the measurement that decides where the fix belongs.

So the stop moved out of prose in two places:

- **CI**: `spike/check-sealed-campaigns.sh` walks *every* campaign directory
  present, requires each one that seals invocations to carry an executable
  consistency checker, runs it, and **fails when no campaign is found at all**
  (a path typo would otherwise pass over an empty set). Campaign 1 is exempt by
  literal name — its seals are closed and adding files there would mark its
  checkers sighted — and the exemption cannot be inherited, which is one of the
  cases the suite proves. Falsified across seven cases, and deliberately not
  only against the accident that motivated it: a campaign that drops the
  checker, one whose checker is not executable, an empty tree, a *new* campaign
  trying to inherit the exemption, and a pre-sweep campaign that must be skipped
  rather than failed.
- **The PR template** (`git-delivery` skill): the Verified section now asks for
  the claim, the command that measured it, and what that command did not look
  at. All three failures above were written into a Verified section; that is
  where the discrepancy would have had to be spelled out.

What this does not fix, stated because the honest scope is the point: CI covers
the config/invocation class only. Classes 1 and 3 are caught by the template, or
not at all — the template is a prompt to notice, not a machine check, and its
effect is unmeasured until the next time I claim something.

## 2026-08-14 — Campaign 2's first seal was void within the hour, by its own sweep (#83)

The between-seals sweep ran once against the sealed rows and displayed its four
exit codes: khard 2, abook 0, khal 0, hledger 2. khard's flip against campaign 1's
public verdict (0 there) sent me to our own committed artifacts — the sealed
reports stayed unread — and the contradiction was inside the seal:
`configs/khard.conf` and `configs/khal.conf` still hardcoded campaign 1's
`/tmp/blind/...` state roots while the sealed invocations watch `/tmp/blind2/...`.
That does not prove the mismatch produced the refusal — the reports stayed unread
and no controlled re-run was made — but it does mean the verdict is
uninterpretable, which is the only property the decision needed.

Voided, not proceeded with. The machine had selected abook, and following it
would have been indefensible: the khard refusal risk was pre-registered, so an
apparatus bug that knocks khard out is — to any skeptical reader —
indistinguishable from steering. And the seal design itself forbids the quiet
fix: configs ride the A2 no-touch set. So the exit is the loud one — void before
any declaration exists (blindness cost: four displayable exit codes), fix the
two paths, re-seal, and give khard its fair shot.

The part worth keeping: **my own R1 fix created this trap and certified it
safe.** Sealing the invocations at Seal A was finding 5's remedy; I "verified"
the rows resolvable and wrote that the freeze "does not risk a spelling-error
dead end"; R2 confirmed the configs "contain no campaign-1 workspace
dependency". `/tmp/blind` sat in two of them the whole time. The verification
checked command resolution and file existence — not the paths inside the
configs, the one place a path could still disagree. Falsified within the hour
by the first real run. The re-seal adds the mechanical consistency check
(config `/tmp` paths ⊆ invocation state roots, green on the fixed tree), and
the ADR now says what a frozen apparatus actually guarantees: not that it
cannot dead-end, but that its dead end is public and the exit is a recorded
re-seal rather than a quiet tune.

Two more things the void surfaced, both about checks that could not see what they
claimed to cover. `check-config-paths.sh` is the new Seal A artifact — every
absolute `/tmp` path in every sealed config must sit under a state root named in
the sealed invocations — and it was falsified before being trusted: red on the
voiding defect itself, red on a sibling-but-wrong root, and **exit 2 rather than
success when it cannot look** (no roots, or no configs), with a green control on
the fixed tree. And `.gitignore` was campaign-1-specific, so campaign 2's sealed
sweep reports and hledger's import sidecar both walked into the staging area; the
patterns are now `spike/blind-hunt*/`, verified with `git check-ignore` to cover
campaigns 1, 2 and a hypothetical 3 while leaving sealed configs and manifests
tracked. A guard written against one instance of a hazard does not cover the
hazard.

One more, from asking what actually invalidates a voided seal. Measured before
writing anything: passing the voided anchor to `verify-seals.sh` already failed,
because the re-seal edits sealed paths and A2 walks the whole range — the lock
was there, it just said the wrong thing. So the re-seal adds `voided-seals.txt`
plus a verifier preamble that refuses a listed anchor by name, and both
directions were falsified: voided anchor exits 2 with the reason, a live anchor
still runs the full battery (a new guard that swallowed the old checks would be
the exact ADR-0012-era failure this repo has already paid for once).

R1 on the re-seal then found eight more, seven of them in the guard I had just
written and falsified — a guard tested against the defect it was born from, and
not against its own predicate. It compared each config path against *any*
invocation root (so a config could agree with a different row's state and pass);
its containment accepted any *ancestor* of a state root and never considered
`..`; and its cannot-look contract leaked four ways (extra args ignored,
unreadable files and malformed rows exiting 1 through Python, the bare path
`/tmp` unmatched by the regex). Rewritten per-row with strict normalized
containment, and re-falsified across twelve cases — one red per hole, a green for
a deeper path inside the row's own root, four cannot-look refusals.

Two findings were about the void rather than the guard, and both mattered more.
The sweep harness accepted an existing output directory and truncated it, so
re-sweeping would have destroyed the voided run's evidence — the very artifacts
the ledger promises are retained. It now refuses, as it already refused existing
state roots, and the voided run was moved aside and re-verified against the
superseded manifest (four hashes, still matching, still unread). And my account
overclaimed: with the reports unread and no controlled re-run, the path mismatch
does not prove it produced the refusal. What it proves is that the apparatus
contradicted itself, so the verdict is uninterpretable — which is all the void
decision ever needed, and the weaker claim is the one now in the ADR, the ledger
and this entry.

The last one is small and my favourite. Fixing the ledger's stale "none yet"
placeholder into a self-aware annotation *broke the append-only prefix* — the
exact property the annotation was bragging about. The pre-commit self-check
caught it, the sealed bytes went back verbatim, and the explanation moved into an
appended entry where it belongs. A rule you are describing is still a rule you
can break in the sentence describing it.

## 2026-08-14 — Campaign 2's Seal A: an inherited selection, and the recovery-path rule (#83)

The strict ruling made the second campaign the designated criterion-1 path, so it
starts now. ADR 0015 records the two ways it differs from a naive re-run of
ADR 0012, both forced by honesty rather than convenience:

- **The selection seal is inherited, not re-performed.** The four remaining
  candidates have been installed, normally run, and swept once — publicly, under
  campaign 1's rules. Claiming a fresh "nothing has run yet" seal would be theater.
  Instead the candidate list, order, and predicate come byte-inherited from
  campaign 1's Seal A (merged before anything ran), minus the consumed target; the
  only knowledge gained since is ledger-recorded permitted-source contact and the
  public sweep exit codes. The khard random-filename observation is deliberately
  NOT allowed to touch the predicate — dodging a known refusal shape with observed
  behavior is the leak the seals exist to close. The risk is pre-registered
  instead: a full-refusal exploration is a recorded result, and campaign 3
  inherits the same way.
- **The recovery-path rule.** Campaign 1's sharpest behavior lived in the path its
  declaration scoped out. Campaign 2's declaration MUST declare, where the docs
  name a recovery/undo/repair command, that running it once after a crash
  preserves the tasks the crash left intact — declarable from docs alone, so the
  misfire class moves inside the blind checker's reach.

Mechanics: `spike/blind-hunt2/` is self-contained (fresh candidates/priority/
ledger/configs, tooling copied and re-sealed — each campaign freezes its own
verdict logic; campaign 1's directory stays untouched so its checkers stay
unsighted). The adapted tooling was falsified before being trusted: select.sh
green (picks khard from a 4-candidate manifest) and red twice (all-refused exits
3, missing-candidate exits 2); verify-seals2 pointed at campaign 1's seals fails
on every blind-hunt2 path — the proof it audits the new namespace, with the FAIL
lines as the evidence (the pipeline's displayed rc was head's, worthless, the
same trap as ever).

R1 (external, covenant-instructed; no breach) found eight holes — seven P1, one
P2 — and every one was the inherited apparatus trusted a step too far:

- The recovery-path rule allowed choosing the convenient command form; campaign 1
  itself proved two documented forms behave differently. Now: enumerate every
  documented form with citations, freeze exact argv per checker, per-form
  invariants, fixed-vocabulary exclusions, and an honest note that coverage is
  review-enforced, not machine-checked.
- Nothing consumed a selected target after a null/refusal campaign — the
  inherited selector could pick the same name twice. Consumption is now a
  normative rule, distinct from burns.
- ADR 0012 governed the campaign but sat outside the A2 no-touch set; the
  inventory now lists it — and itself (the P2).
- The environment that decides selection was unpinned prose. The sweep manifest
  now records the engine version and binary/shim SHA-256 (stub-tested: valid
  JSON, fields present), the run manifest must mirror them, the ledger records
  the image ID at sweep time, and the ADR states exactly what that does and does
  not prove.
- The inherited invocation rows were prose-bound. They are now sealed at Seal A
  itself (public since campaign 1; resolution-verified in the image with no
  target executed — the freeze cannot dead-end on a typo), and select.sh rejects
  manifest names outside the sealed order (red-tested, exit 2).
- sweep.sh's header still instructed copying the manifest into campaign 1's
  directory — following it would have touched the closed campaign — and claimed
  a freshness ("before any candidate has been installed") that ADR 0015 exists
  to deny. Both rewritten.
- "Knows ... exhaustively" overclaimed a self-reported ledger; now "the
  repository records", with the ADR 0012 bounds restated beside it.

## 2026-08-14 — Ruled: the misfire does not count as "found by Sideeye" (#83)

The open fork in the PRD's criterion-1 status was closed today, on the strict
side. The recovery misfire (novel, upstream as topydo#341) was reached by a
human following the automated FAILs into the recovery path; counting that as
"discovered automatically" would read the same scale two ways — timewarrior's
find was scored *partial* because a human formed the specific hypothesis, and
the arrows being reversed here (tool search first, human hypothesis second)
does not change who formed it. The sealed declaration also pre-committed to
calling recovery measurements analysis; promoting them to findings after the
fact is the goalpost-shaped move this campaign built two seals to prevent.

Consequence: criterion 1 stays open. The designated path is a second blind
campaign under fresh seals, whose declaration includes recovery-path
invariants — declarable from documentation alone, and exactly the coverage
this campaign's declaration listed under "what this does not check". The
remaining candidates (khard, abook, khal, hledger) are still blind-eligible:
permitted-source contact only, hledger's refusal reason still sealed unread,
no bug tracker opened for any of them. Keeping them that way is a standing
discipline until the next campaign picks one up. Timing deliberately not
fixed.

## 2026-08-14 — The misfire went upstream (topydo#341), and a red check got merged over (#83)

Two things to record, one good and one not.

The recovery misfire was filed upstream as `topydo/topydo#341`, with the text
approved verbatim beforehand: observation, a plain-printf reproduction (verified
in the container before the text was shown for approval), conditions, risk, a
confirmation request. No fix proposal, no tooling named, #318 referenced as
related context. The crash-window destruction itself was deliberately not
re-reported — #318 already covers that phenomenon, and a duplicate adds noise,
not information.

The process slip: the ledger entry recording that filing went in as PR #103,
and PR #103's `buildlog` check **failed — correctly** (it changes `spike/`
without touching this file; that is exactly the contract in CLAUDE.md) — yet
the PR got merged anyway. The merge command was chained after the check
*display* in one invocation, and a display exits 0 whether the checks passed
or not. This is the third occurrence of the same fused-chain class (#51: watch
exits 0 before checks register; #61: rollup query and merge in one command;
now #103: an until-loop that waited for "not pending" but gated nothing on
pass/fail). The structural fix this repo's discipline demands: **merge is its
own invocation, issued only after reading the pass/fail column** — never
appended to the command that prints it. This entry is also the BUILDLOG entry
PR #103 should have carried.

## 2026-08-14 — The novelty check: the phenomenon was known, the recovery misfire was not (#83)

The bug-tracker restriction was lifted as its own recorded step (ledger: fourteen
search terms over title+body, comments-inclusive passes for the revert terms, a
positive control proving the instrument can see what it looks for, full bodies
read for the three candidates). The answer split the campaign's result in half:

- `topydo/topydo#318` — open since 2023-10, zero comments — already reports the
  active list being destroyed by an interrupted write (disk full there, SIGKILL
  here; same failure surface). The reporter had not read the code; there is no
  mechanism and no reproducer. So the blind search's headline finding is real but
  **not novel as a phenomenon** — what this campaign adds is the deterministic
  window and a case that replays in a pinned container.
- The recovery misfire — plain `revert` after a crash undoing an *older* command
  and deleting data the crash left intact, on documentation that contradicts
  itself about the matching rule — appears **nowhere in the tracker**. Novel as
  far as the recorded search sees; also the one finding that came from post-seal
  human analysis rather than the blind search.

The uncomfortable consequence, written into the PRD status rather than smoothed
over: **no single finding currently holds "found by Sideeye" and "novel" at
once.** The automated find is known upstream; the novel find is human analysis.
Whether the recovery misfire still counts as "found by Sideeye" (its FAILs are
what pointed the analysis there) is the author's judgement, not this file's.

## 2026-08-14 — The blind hunt ran: twelve of thirteen operations produced a counterexample (#83)

Seal B merged as `5a034aff`, and the exploration ran from that commit in a clean
tree, in the pinned container. `verify-seals a21b0933 5a034aff <run-manifest>
<sealed-reports>` prints **ALL SEAL CHECKS PASSED (R1 audited)** — the first time
the verdict line has come back without PARTIAL, because the run manifest finally
exists to audit. The declaration order is now a checked fact rather than a claim.

**Result: twelve FAIL, one PASS.** The ten single-file operations each violated
the declared conservation invariant in the window between opening the active list
and writing it; `do` and `revert` failed across the file pair (2 of 5 and **5 of
8** worlds). `ls`, declared read-only, recorded zero state-changing operations and
passed — the one declared operation whose expected result was "nothing to explore"
delivered exactly that, which is the honest control this run needed.

**The saved cases replay in a fresh container with nothing else installed** —
exit 1, `the case reproduced`, for every case tried. That is the property the
timewarrior finding never had (`#82`: a recipe bound to a built binary). The
in-image resolution leg of the sealed predicate was a structural proxy for this,
and the proxy held.

Then the part that matters more than the truncation window, and the part that is
**analysis, not automated discovery** — I followed the FAILs into the documented
recovery path, after the seal, and `analysis/findings.md` keeps the two halves
apart on purpose:

- The data is recoverable, but through the *numbered* form: `revert 1` restored
  the intact pre-crash state every time, including worlds where the active list
  had been emptied. My first reading of the measurements was "unrecoverable" —
  the forced form is documented one sentence below the one I had leaned on, and
  measuring it before writing is the only reason this entry does not contain a
  false claim.
- The no-argument form — the one the docs lead with — does something else. For
  `add`, in **3 of its 5 crash worlds**, the crash left the pre-existing task
  intact and plain `revert` then deleted it, exiting 0 with `Reverted to state
  before: add seed-task`: a command the user never pointed at. In 2 worlds it
  refused. The cause is legible from the outside: after the interrupted write
  the file is byte-identical to an *older* snapshot, so the search for "a backup
  corresponding to the current state" matches the older entry and rolls past
  work the crash never touched.
- The target's own two documentation sources disagree about this case — the help
  text promises refusal when the latest backup does not match; the documentation
  tiddler describes searching for any backup that corresponds to the current
  state. The behavior follows the second; under the first it should have refused.
  Whether upstream knows is **not checked** — the reference rules forbade the bug
  tracker, and lifting that is a deliberate step before any report, not a thing
  to do while writing up.

**What the campaign may and may not claim.** Declared-before-known: yes, and
machine-checked. Found by the search: yes for the crash windows. Novel: unknown,
and the file says so. Real bug: yotta's judgement, not asserted here. And ten of
the twelve ran with `backup_count = 0` — our own declared config, safety net off
by our choice — so their weight is bounded by exactly the thing the declaration
said it would not check. `do` and `revert` ran at the default and did not need
that caveat.

## 2026-08-14 — The topydo declaration, written blind (#83, toward Seal B)

The declaration phase ADR 0012 authorizes: everything the exploration will be
judged by — invariants, operation inventory, checkers, setups, tomls, the
runner — written from permitted sources only and frozen in
`spike/blind-hunt/declaration/topydo/`. The consultations are itemized in the
ledger; the raw material (help output, doc tiddlers, the todo.txt spec, one
normal run per subcommand) is committed under `transcripts/` so every
`source:` line points at something a reader can open.

Shape of the declaration (after R1, below): thirteen operation forms across
twelve of the fifteen help-listed subcommands are declared (excluded whole:
`edit` interactive; `listcon`/`listprojects` not-stateful — and every
unexercised form of a declared subcommand is listed, not silently dropped).
Six invariants — query survives (I-Q), conservation across the
file pair (I-C), no duplication for the two cross-file operations (I-D2),
archive holds only `x `-marked lines (I-F), the backup listing answers after a
crash (I-B, revert only), and claimed durability via L1 markers where the
operation prints a past-tense success line (I-M). Severity is pre-registered
(loss over duplication) so a finding cannot be inflated afterwards.

Decisions worth recording, made while still blind:

- **Backups off for ten operations, on for revert.** The docs say the backup
  store is rewritten on every modification, and `revert ls` shows its times at
  second precision — that alone would make the un-killed baseline world
  irreproducible and refuse every run (`baseline_violates_invariant`, the
  watson shape) before topydo's behavior was ever measured. The documented
  `backup_count = 0` switch is the declared config for the ten; revert keeps
  backups because they are its input. The cost — the backup subsystem's crash
  surface rides on revert alone — is stated in the declaration instead of
  being discovered in the report.
- **Conservation greps the files, not the listing.** A normal run showed
  `ls -x` omitting a task that had just acquired a dependency; the todo.txt
  carve-out (the format is normative public documentation) makes the files
  the honest inventory.
- **No preflight on the declared defines.** The temptation was real — eleven
  tomls, why not check they will be accepted? Because acceptance-checking is
  observation, and tuning the declared set against it is the exact leak Seal B
  exists to close. The sweep stays the only sideeye↔topydo contact; a refusal
  at exploration time is #84 data, not a defect. What did get verified without
  touching the target: all eleven tomls parse (host binary, nonexistent shim,
  stops at state resolution), and the green side — setup, the verbatim
  operation string, checker — exits 0 on normal state for all thirteen.
  (An earlier draft of this entry said the checker had never been seen to
  fail; that was superseded the same session: its red side is now proven on
  hand-fabricated, user-authored states — `checker-red-test.sh`, committed
  with its fixtures — while the red side against real *crash* states still
  belongs to sideeye's falsification gate, after the seal.)

R1 (external review, covenant-instructed; it complied — no burn) then bent
the declaration in four places, all recorded in the ledger:

- **The parse validation had measured the wrong binary.** "All tomls parse"
  was run against the host's v0.7.0 sideeye — but this branch based on the
  Seal A merge, which predates `expected_status`. The sealed revision would
  reject every toml. The green run that was supposed to protect the seal was
  itself the measured-a-different-path shape this workspace keeps meeting.
  **Resolved, with the decision on record**: the branch was rebased onto the
  v0.7.0 merge (`a21b093`) — every Seal A artifact is byte-identical between
  the two anchors and the criterion wording did not move (PRD untouched;
  DESIGN's two new lines are the §12 define-key note), so verify-seals runs
  with A=`a21b093` and every leg stays mechanical. The alternative — keeping
  the old base and dropping the key — would have sent the exploration out on
  an engine whose PASS-side soundness bugs v8 had just fixed, and recorded a
  case the current contract refuses (#82's hole, re-dug). Because the engine
  moved, the sweep was re-run once, recorded (ledger): identical invocations
  by hash, identical verdicts, topydo again — and the superseded manifest
  stays committed beside the new one.
- **The backup-refusal certainty was an overclaim.** Normal runs only show
  that `revert ls` prints second-precision times; whether backups-on would
  actually refuse the baseline is deliberately unmeasured. Downgraded to a
  pre-registered risk everywhere it was stated.
- **The inventory was neither complete nor honestly granular** — `ls` was
  excluded as not-stateful while a documented form writes, and `dep rm`/
  `dep clean` were unmentioned. Now: `ls` and `dep rm` are declared (the
  former with its zero-op expectation stated), `dep clean` and every other
  unexercised form is named per subcommand, and the lscon/lsprj tiddlers
  were pulled so the two remaining not-stateful verdicts are doc-backed.
- **The checker was hardened without unsealing anything**: padded list
  numbers accepted (the docs' own example pads), conservation demands a
  whitespace-delimited token (an embedded substring is not survival), and
  I-F now enforces the completion date the spec's rule 2 requires. Red
  cases for each new tooth ran before they were trusted.

## 2026-08-13 — v0.7.0: minor, because the number must predict the case refusals

Version 0.6.0 → 0.7.0, both hand-written strings at once (the unit test holds
the pair). 0.6.1 was proposed and rejected: a patch number reads as a safe
drop-in, and this release changes what saved cases do — every v7 case now
refuses as a contract mismatch and must be re-recorded, and the countable
operation set itself moved (contract v8). A new user-facing define key
(`--expect-status`, case schema v2) rides along; the 0.6.0 precedent already
chose minor for less. README reconciliation (checklist step 3.5): the tar
example moved to v0.7.0 and the Status list gained the release's claim; the
two other v0.6.0 mentions are historical ("entrance paved at", "releases from
v0.6.0 on ship binaries") and stay.

## 2026-08-13 — expected_status: the fifth define key, spent against §12's budget sentence (#3)

The recording run and the baseline world both demanded exit 0, which made every
git-convention target unjudgeable — refused on sight, no opt-out
(`--allow-unverified` weakens completeness, not the success convention). The fix
is one declared value with two spellings (`--expect-status 3` /
`expected_status = "3"`), one shared digit parser so the spellings cannot drift,
and one meaning: *un-killed runs of the operation must exit N.* That sentence is
the answer to #3's own worry ("one flag governing two checks with different
meanings") — the recording run and the baseline are the same command over the
same state, so they were always one check wearing two names.

The wiring is the work, not the comparison: the flag, the toml key, the
`--config` exclusivity list, replay's define-surface rejection list, the saved
case (schema v2 — the declaration is written even at the default, because a case
must replay identically years later without consulting anything outside the
file; v1 cases read as "0 was the contract"), preflight (accepts it, and the
graduation hint carries it — a hint without it would hand explore a define that
refuses the recording preflight just blessed, the known hint-drops-the-define
class), MCP (rides for free: the server self-execs through `--config` and the
case file), and the report (`expected_status`, always present, so a PASS over a
non-zero convention is machine-distinguishable from one that required 0).

Measured on macOS first, then pinned in the container as acceptance check 8
(nine legs): undeclared exit-3 refuses naming both statuses; declared-3 explores
5 worlds with the baseline held to 3; declared-2 refuses naming 3 and 2; the
toml spelling explores and the JSON report carries the field; 256/-1/abc refuse
in both spellings; preflight accepts, carries, and refuses without; the case
round-trips at v2 with the field frozen; a real case stripped to v1 replays
(absent means 0); and `_exit(137)` under `--expect-status 137` explores in full
— an exit status is not a SIGKILL, and every killed world still dies by the
signal. The baseline-forgot-the-declaration mutant (comparing against 0 again)
died loudly in three legs at once, with a diagnostic that read "exited 137 where
137 was expected" — the mutant's own fingerprint, since the message printed the
declared value while the comparison ignored it.

DESIGN §12's sentence — "If Define ever needs more than this, that is movement
toward the kill criteria in §18, and we should notice" — is quoted and answered
in ADR 0014 rather than silently outgrown: `expected_status` is a fact about the
operation, not a new verb, and the sentence now records that it has been faced
twice (marker, ADR 0008; this, ADR 0014).

The blind review round returned three real holes and four loose claims, all
taken. The version and the field did not travel together — a v1 case carrying
`expected_status` and a v2 case missing it were both read under a guessed
contract; both now refuse as malformed. The report mirror was set too late: a
refusal *after* the declaration was read (a status-3 case dying at the contract
gate) said `expected_status: 0` — the mirror now sets at each source the moment
it resolves, and reordering the replay block also fixed a pre-existing wart
where a contract-mismatch refusal did not name its case. And the field lived in
the JSON only, against DESIGN §13's text/JSON parity — the three verdict text
forms now carry it (`expected status: 3` / `expected    exit 3`), pinned by
grep in three legs. The loose claims: the help tail still demanded exit 0 two
paragraphs under the flag that says otherwise; the README's "exactly this
shape" toml omitted the new key and the exclusivity list omitted the new flag;
"diagnostics always name both statuses" overclaimed what a signal death can
name; and the mismatch message blamed `--expect-status` even when the value
came from the toml or the default.

R2 held five of the seven closed and sent two back for a second pass, both
finished here: the zero-operation PASS — a fourth verdict emitter the parity
fix had missed — now carries the status line (and its acceptance leg greps for
it), and the shape gates' claim was honest only for numbers, because a JSON
`null` is indistinguishable from an absent field after parsing. A v2 `null`
refuses like an absence (pinned in the leg); a v1 `"expected_status": null`
passes deliberately — null is not a declaration and the meaning is the same —
and the gate's message now says "declaration", not "field". One R2 remark is
left as-is on purpose: SETUP_ERROR's text form is a single line by original
design and carries none of the classification fields the JSON does; adding
this one there would be inventing a parity the form never had.

## 2026-08-13 — Contract v8: no descriptor number is exempt, and "could not tell" stops passing as "not ours" (#4)

Measured first, on the pre-fix binary, with the new `TOY_DUP2` toy (state writes
through fd 1, fd 2, fd 0, and a stdio leg on rebound stdout):

    no oracle, --allow-unverified:  PASS 9/9   ← the false PASS, real
    with oracle:                    UNKNOWN oracle_missed_operation
                                    (divergence at operation 2: the oracle saw
                                    write(1</tmp/.../dup-fd1.txt>); the shim
                                    recorded open of the *next* file)

Both halves of the hypothesis held: on Linux with the oracle the second witness
already refuses — fail-closed doing its job — and the genuinely wrong verdict
lives on the oracle-less side (macOS, `--allow-unverified`), where four state
files were written through standard descriptors and the report said PASS.

The fix that review shaped (two Criticals deep, past the original one-line
plan): `noteFd`'s early returns shrink to `fd < 0` only — both the `fd <= 2`
skip and the `trace_fd` comparison go, because each was a *number*-based
exemption and a target can rebind any number (the shim's own trace writes never
pass through the wrappers, so the trace_fd check defended nothing). And fd
resolution becomes three-valued: a descriptor **proven** to be a socket, pipe
or character device is evidence the operation is elsewhere; a regular file or
directory whose path cannot be read is **unresolvable** and gets recorded, so
the engine refuses instead of passing; and `st_nlink == 0` now marks unlinked
files on both platforms — closing the macOS gap F_GETPATH left, which this
file previously documented as known-but-open. The harness also refuses
`--work` inside the state directory before running: with the exemptions gone,
the engine's own stdout captures would otherwise become countable state
operations. Trace contract v7 → v8 — the countable set changed, the same
class as v5 (stdio) and v7 (remove) — and saved v7 cases refuse honestly.

Post-fix, same toy, first run: the four descriptor-borne writes are counted
(crash points 8 → 12), and **the oracle agrees on all 12 operations** — the
worry that the shim's own per-operation `statx` would trip the oracle's
unknown-syscall net was measured away, absorbed like the readlink calls before
it. The plain toys' sequences are unchanged (toy-bug still FAILs at crash
point 5 of 5), and `--work` inside state refuses before anything runs.

One toolchain find worth its line: Zig 0.16's std.c deliberately exports **no
libc fstat on Linux** (`.linux => {}` in std/c.zig — the __fxstat legacy), so
the shim asks via the raw `statx` syscall there and libc `fstat` only on
Darwin, where std.c handles the $INODE64 decoration. The local std source
answered in one grep what the compile error alone did not.

The blind review round then broke this entry's own sentence "the trace_fd
check defended nothing" — true for protecting the trace, false as a conclusion.
The *number* is the channel's identity, and with the check gone nothing
defended the channel at all. Measured with a daemonize-style `close(3..255)`
sweep: the shim's trace fd sat at 3, the sweep closed it, the toy's next open
took the number, and `key.json` came back with the shim's binary trace records
spliced between its own bytes — the harness corrupting the data it judges,
refused only by the accident of `state_changed_without_ops`. The channel now
defends its identity itself: relocated at init (`F_DUPFD` ≥ 900, fallback
≥ 200 under macOS's 256 rlimit), and every descriptor-retiring wrapper (close,
fclose, freopen) treats closing it as the channel dying — one final
`unresolved` record while the fd still works, then trace_fd = -1 and silence.
Sweep below the floor: verdict untouched, 5 worlds. Sweep at 1023: refused
`unresolvable_path` with `key.json` byte-identical to what the toy wrote.

The same round found three more, all measured red first: `fdKind` sent
anon-inode descriptors (type bits zero — eventfd, epoll; the kernel's own
spelling, while macOS kqueue stats as a FIFO and never hurt) to
`unresolvable_path`, so one eventfd close refused an innocent run — every
epoll-based target was unjudgeable until type 0 and `S_IFLNK` joined the
proven-non-path class. The `--work` vet destroyed evidence before refusing:
`replay --fresh-state` emptied the state directory and *then* noticed --work
sat inside it (sentinel file: gone), and plain explore planted `<state>/work`
before refusing — the vet now runs before the deletion and removes the one
directory its own resolution creates. And the vet's hand-rolled prefix test
answered "outside" for a state directory of `/` (the byte after `/` in `/tmp`
is `t`); it now uses `isInsideDir`, whose root case the acceptance leg runs
for real — the mutant with the old expression sailed past the containment
message and died on a snapshot error instead, which is exactly why the leg
asserts the message and not the exit code. The same-class scan for the
null-conflation found a second instance in `resolveAt`'s dirfd base — the
`*at()` family answered "not ours" where it could not measure — fixed with the
same three-way split, though no toy can drive that branch (a live directory
whose path query fails is not constructible on demand; recorded as the one
unmeasured edge). The first version of that fix shared one `deleted` flag
between `fdKind` and `fdPath` — and `fdPath` resets its out-param on entry, so
fdKind's nlink==0 finding (the macOS deleted-directory carrier) was erased on
the successful-path branch; caught in the simplify pass by reading `noteFd`,
which had kept the two flags separate all along. The schema page said "v7 today" over a v8 binary; claims 1-3
stayed green because none of them read the version prose, so check 4 now pins
the doc's version words to `contract_version` — seen red against the v7
wording, red again with the anchor prose deleted, green on the real page.

## 2026-08-13 — A sweep dropping walked into the release commit

Caught right after merging the 0.6.0 bump, before the tag: the bump commit
carried `spike/blind-hunt/configs/.latest.hledger-in.journal` — one line, a
date. It is hledger's import-dedup sidecar, written **next to its input
file**, and during the sweep the input file lives inside this repository; the
sidecar sat untracked in the working tree across a branch switch and a
`git add -A` swept it into a commit about something else entirely. Content
harmless (the date of our own committed test transaction), no sealed path
touched — but a release tag should not carry runtime droppings, so it is
removed here and the pattern is ignored before the tag lands. The general
shape is worth the entry: **a target that writes beside its inputs turns the
repo into its scratch space the moment the inputs are committed files**, and
`git add -A` does not ask whose file that is.

## 2026-08-13 — v0.6.0: the first release that ships binaries

Version 0.5.0 → 0.6.0, both hand-written strings at once (the unit test holds
the pair). Minor, not patch: the release carries four new user-facing pieces —
`sideeye demo`, `sideeye preflight`, `sideeye version`, and the release
workflow itself. The version number was an explicit decision, not an
assumption (the owner flagged it for consideration; minor won because the
content is features, and a patch number would under-report it).

This is the release where `release.yml`'s upload leg runs for the first time:
until tonight, the prebuilt tarballs existed only as CI artifacts on a pull
request. The ceremony therefore grows its recorded new step — after
publishing, verify the workflow went green and `gh release view` actually
lists the assets, because the failure mode this trigger design accepts is a
published release standing empty. Also new to this ceremony: the shipped
artifact itself gets exercised — download a tarball, unpack, run the demo,
expect exit 1 — because "the workflow uploaded something" and "a visitor can
run what was uploaded" are different claims.
## 2026-08-13 — Between the seals: five invocations from permitted sources, committed before the sweep (#83)

Seal A merged this evening (PR #89); this entry is the between-seals phase it
authorizes. All five candidates installed pinned (`spike/Dockerfile`), their
invocations assembled from `--help`, two official-docs pages, and normal-run
observation only — the ledger itemizes every consultation — and committed
*before* the sweep runs, so the manifest's invocations hash has something to
bind to (ADR 0012).

What the permitted sources decided, without touching a trace:

- **topydo** drives its two files (`-t` todo, `-d` archive) into one state
  directory; `do 1` completes-and-archives — assembled exactly as hoped.
- **khard** and **khal** both name their state through a config file (formats
  from their readthedocs pages) and mint randomly named files per entry —
  observed from the filenames alone, which normal runs are allowed to show.
- **abook**'s only stdin-free writer is `--convert`; the interactive book
  editor and `--add-email` both need what the exploration engine does not
  provide (a terminal, stdin).
- **hledger** appends via `import`; its journal is seeded by `/bin/cp` in
  setup, where any tool is allowed.

The sweep ran once, with the oracle, and this is everything the experimenter
has seen of it:

    topydo exit=0 resolved=yes
    khard exit=0 resolved=yes
    abook exit=0 resolved=yes
    khal exit=0 resolved=yes
    hledger exit=2 resolved=yes

Four recordings accepted; hledger refused — **why is sealed**. The refusal
detail sits unread in the hashed artifact until Seal B, exactly because a
refusal reason is knowledge about how a target behaves under observation.

`select.sh` applied the sealed predicate to the committed manifest:
**topydo** — first in the sealed priority order with exit 0 and in-image
resolution. Nobody chose it; the choice was merged five hours before the
sweep existed. Next (a fresh phase, deliberately not tonight): the
declaration — invariants with per-line provenance, the operation inventory,
the concrete checkers — then Seal B, and only then the first crash world.

## 2026-08-13 — Seal A: everything about the blind hunt is decided before a target runs (#83)

§17's first condition — "Sideeye discovered it automatically" — is the one part of
the primary criterion the timewarrior finding could not honestly claim, and the one
piece of remaining v1.0 work with no guaranteed outcome. This entry seals the
procedure for measuring it (ADR 0012): the campaign that will try to find a real bug
from an invariant declared before anyone knew the bug existed.

**The design died twice in review before it was right, and both deaths are worth
recording.** Draft one swept candidates with preflight and picked the promising one —
but preflight's operation counts and refusal reasons correlate with how breakable a
target looks, so choosing after seeing them is choosing informed; the same direction
of leak as reading traces, only politer. Draft two sealed the *information sources* —
and the reviewer pointed out that source rules alone let the declarer run the tool,
watch what happens, and then pick, from those same permitted sources, exactly the
invariants that fit. Hence two seals: the procedure (candidates, priority, a
discretion-free selection predicate, reference rules, wrapper template, audit
tooling) frozen before any candidate is installed; the declaration (invariants with
per-line provenance, operation inventory with a fixed exclusion vocabulary, concrete
checkers) frozen after the permitted contract reading and before the first crash
measurement. Exploration runs only at the second seal's commit, from a clean tree.

Choices made here, and the shape of their honesty:

- **The selection predicate takes the first exactly-one candidate** (preflight exit 0
  ∧ commands resolve to absolute paths inside the image). Not "one or two" — a count
  with slack is a stopping decision made after seeing how the first target went. The
  in-image leg is the structural proxy for "a saved case will replay here without
  external builds" (the timewarrior regression case is still recipe-bound; #82 —
  that hole does not get re-dug on a new target).
- **The sweep shows exit codes only.** Full reports go unread into a hashed local
  artifact. Unread is a working rule, not a proof; the hash makes a later swap
  detectable while the reports are retained, nothing more. Said so in the ADR,
  said so in §17.
- **The criterion was widened before the campaign, not after.** PRD criterion 1
  named "omamori or the calibration target"; a blind-protocol target now counts,
  and the sentence itself records the date and the reason. Author-confirmed is
  fixed to the timewarrior reading (project author judges; upstream sought, not
  required) — the same answer #82 needs, decided once.
- **These are high-risk blind targets, not average ones.** topydo, khard, abook,
  khal, hledger — file-backed state chosen on purpose from web docs alone, several
  spanning multiple files, two single-file counterweights. The §18 average-target
  calibration already stands on timewarrior; this campaign does not claim it twice.
- **The taint ledger names what cannot be blind anymore** (timewarrior, taskwarrior,
  git, todoman, watson, jrnl, omamori) and admits what carries over anyway: class
  knowledge, and a language model's training data. The seals make the *recorded*
  consultations and the commit order auditable — the ledger is self-reported, and
  an unrecorded consultation is exactly what it cannot detect. They cannot make
  the experimenter forget. §17 carries the claim at exactly that strength.
- **Reviewer covenant with breach handling**: a reviewer who names target internals
  or known issues burns that target; so does an experimenter who touches a
  forbidden source. The ledger records it and the campaign moves down the sealed
  order. No cure — blind is once per target.

Also recorded, from the review mechanics themselves: the first adversarial-review
call on this plan came back as a 258 KB transcript that quoted engine source at
length and then died on the reviewer platform's safety filter — zero findings,
reported as success. A long response is not evidence a review happened; the verdict
was at the tail, and the tail was an error. The re-run, phrased neutrally and told
not to quote source in its reply, went through on the same model.

Code review on the seal itself found eight P1s — all protocol holes or
document-vs-tooling gaps, all fixed before the seal merged, which is the one
moment they were still fixable:

- The sweep's *inputs* were the unguarded loop: nothing stopped tuning
  invocations against exit codes and committing only the final spelling. Now
  the manifest embeds the SHA-256 of the invocations it ran against, the
  committed file must match (verifier B3), the sweep runs once, and a re-run
  after a broken invocation keeps both manifests committed with a ledger entry.
- The verifier audited endpoints, not history: it never checked that Seal A is
  an ancestor of Seal B (A0, new), compared only the two trees so a
  change-and-revert inside the range hid (A2 now walks `git log A..B` over the
  sealed paths), accepted a declaration for *any* candidate (B4 now recomputes
  the selection from the committed manifest + priority + burned list, using the
  committed selector, and requires the single declaration directory to match),
  and could print an unqualified pass with the run manifest simply not supplied
  (the verdict line now says PARTIAL unless R1 was audited).
- The seal was narrower than the ADR said: PRD/DESIGN — the criterion wording
  the campaign is scored against — now ride the A2 no-touch set, and the ledger
  gets an append-only check (A3: Seal A's ledger must be a byte prefix of
  Seal B's; entries cannot be deleted en route).
- The implemented predicate was weaker than the declared one: the oracle is now
  mandatory in the harness, and resolution covers the binary, the setup's and
  operation's first words, and the shim (loaded, not executed — checked as
  absolute-and-readable, since `command -v` would demand an execute bit a
  shared object need not carry).
- Breach handling contradicted the one-target rule. Resolved by phase: a
  pre-Seal-B burn appends to a committed `burned.txt` and selection re-runs
  with it as an explicit selector input; a post-Seal-B burn ends the campaign.
- Two claims were stronger than their machinery: the report hash "proves"
  became "makes later substitution detectable while the reports are retained"
  (with an R2 verifier leg that actually recomputes when they are supplied),
  and "what was consulted is checkable" became "recorded consultations and
  commit order are auditable; the ledger is self-reported". The criterion's
  "no hand-written adversarial crash tests" became "documentation does not
  advertise crash-injection testing" — verifying the stronger phrasing would
  require reading the target's test suite, which the source rule forbids.

Next: merge = Seal A. Then install the candidates into the container, read only what
the rules allow, assemble invocations, sweep, and let the predicate pick.

## 2026-08-13 — The entrance gets paved by shrinking a claim, not growing the tool (#75 #76 #77)

Three entrance features in one branch — release tarballs, `sideeye demo`,
`sideeye preflight` — because v1.0's criterion 6 (a fresh machine reaches its
first exploration in under ten minutes from the README) currently dies at the
first cliff: install a pre-1.0 compiler to see anything at all.

**The plan-review reversal worth recording: preflight's claim was wrong before a
line was written.** The draft said preflight answers "explorable, or refused for
reason X". The adversarial plan review pointed at what the cut point cannot see:
`kill_did_not_land`, world-side boundary refusals, `baseline_run_failed`,
`baseline_violates_invariant` and checker falsification all live in or after the
exploration loop, which preflight never enters. "Explorable" was therefore a
claim the command does not earn — the same overclaim shape §17's scoring polices.
The fix was to shrink the claim: preflight says **"recording accepted"**, and a
fixed-vocabulary `not checked` block names the four exploration-only classes
every time. Acceptance check 6 pins the wording both ways: a target that is
recording-clean but exploration-refused (`TOY_NONDET_REWRITE` on the fixed toy —
recording gates all pass, the baseline world refuses) must be *accepted* by
preflight with baseline behavior named as unchecked, while `explore` on the same
define exits 2 with `baseline_violates_invariant`. A preflight that mirrored
explore's verdict fails the first half; one that claims everything fails the
second. Measured: the vocabulary mutation (dropping "baseline behavior" from the
block) went red in the container before the wording was trusted.

**Preflight's mechanics**: a third mode sharing the explore pipeline, cut at one
place — after `n = kill_point_count` is known, before the zero-op PASS branch —
with an unconditional exit. No detector is duplicated; a refusal exits through
the same `unknown()` with the same name a real run prints. The define-shaped
flags (`--check`, `--marker`, `--config`, `--json`, `--allow-unverified`) are
refused by name, not ignored — an accepted-but-inert flag would be a declared
intention that silently never fires, the shape the toml parser already refuses.
`--json`'s rejection sits *before* the `removeFile` in its parse branch: a
refusal that had already deleted the caller's previous report would be a refusal
with a side effect.

**The demo compiles its toy on the visitor's machine and self-execs explore.**
The embedded assets are `spike/toys/toy.c` and `spike/check.sh` — the same files
the acceptance suite drives, so the demo cannot drift from what CI proves (both
now listed in build.zig.zon's `.paths`, or a fetched package would not build).
Choices that review corrected before they became bugs: the checker is invoked as
`/bin/sh <path>` (a Written file has no execute bit and posix.zig has no chmod),
and `TOY` is baked into the script's first line rather than passed through the
environment (the checker runs a fresh process several layers down; a baked value
cannot be lost to an exec-model change). The self-exec is plain `execvp` with
the inherited environment — the MCP minimal-env helper exists to withhold
credentials from an untrusted config's operation, and the demo's operation is
our own toy. Compile ladder: cc → gcc → clang, each with `-lpthread` then
without; no compiler at all refuses by name with the install hint. Measured on
this Mac first try: exit 1, crash point 5 of 5, same numbers as the README
showcase — and the first run's output opened with a screenful of clang's vfork
deprecation warnings, so the compile now carries `-w` (the toy's warnings are
addressed to this repo's developers, not a demo viewer's terminal). The
checker's own stderr ("doctor says 'healthy' but the key is unloadable") stays:
that is the instrument speaking, twice — once at falsification, once in the
violating world.

**The release workflow builds on three native runners** (`ubuntu-latest`,
`ubuntu-24.04-arm`, `macos-latest`) rather than cross-compiling from one: a
cross-built artifact cannot be *run* where it was built, and the per-artifact
smoke test is the demo itself — exit 1 on the runner, through the shim the
binary just found beside itself, exercising the ReleaseSafe build the acceptance
suite (Debug) never touches. Trigger is `release: published` so the manual
ceremony stays the origin; the failure mode that leaves a published release
without assets gets two answers: `workflow_dispatch` with a tag re-uploads, and
the ceremony gains a step — after publishing, verify this workflow went green
and `gh release view` shows the assets, before announcing anything. The upload
job carries `permissions: contents: write` explicitly. `sideeye version` (one
line, exit 0) exists because the workflow must hold each artifact's binary
against its tag, and the usage banner — the only place the version appeared —
exits 3. The tarball inventory is diffed against an expected list before upload:
a tarball without the shim is half the product, silently. The
`ubuntu-24.04-arm` runner is an assumption until the PR's build-only trigger
runs; if it is unavailable, the fallback recorded in the plan is a cross-build
with the smoke honestly marked absent, not a silent drop of the architecture.

Container measurements for the whole batch: acceptance checks 5 and 6 (six legs)
green; both source mutations KILLED (`-DBUGGY` removed → demo exits 2 with no
window named; vocabulary dropped → wording assert red); four synthetic reds
(refuse leg fed an in-bounds toy → 0, compiler-absent leg with a normal PATH →
1, fallback leg with cc and gcc both failing → 3, honesty pair's explore side
without the rewrite → 0). mcp-acceptance untouched and green — the only mcp.zig
change is `canonicalSelf` going pub for the demo's self-exec.

Code review (R1) found three real ones, all fixed and confirmed in R2:

- The release workflow's repair path (`workflow_dispatch` with a tag) checked
  out the default branch, so a "repair" would have rebuilt current main and
  uploaded it under the old tag's name — an artifact whose content is not the
  tag's, with `--clobber`. The checkout now takes the dispatch tag as its ref,
  and the version-against-tag assert runs on tag-named dispatches too, not
  only on release events.
- The preflight graduation hint dropped `--setup`: the define it suggested was
  silently different from the define it had just accepted. The hint now
  carries it, and acceptance check 6 greps for it — seen red against the
  unfixed binary before the fix was written.
- The demo baked `TOY=<path>` into the checker unquoted; a `$TMPDIR` carrying
  shell metacharacters would have handed them to `/bin/sh`. Now single-quoted
  through a complete POSIX escape (`'` → `'\''`), unit-tested, and the space
  guard on `$TMPDIR` stays for the separate splitArgs constraint. Same-class
  scans for all three classes found no further instances (the FAIL report's
  replay line is structurally immune — the define travels inside the case).

## 2026-08-13 — v0.5.0: the README stops introducing the tool as v0.1

Version 0.4.0 → 0.5.0, both hand-written strings at once (the unit test holds
the pair). The release carries the docs catch-up (#67), on the discipline the
repo already owes its examples to: the README's showcase FAIL was regenerated
with the 0.5.0 binary rather than trusted — and the regeneration itself proved
the point, because the stale example was missing five lines the report has
grown since v0.1 (atomicity, l1, case, replay, processes) and showed old
prose in two it rewrote (oracle now records a real agreement where
`--allow-unverified` used to apologize; checker now counts its worlds). The Status
section now tells the five-milestone story instead of the feasibility spike's;
the target-constraints section drops "for v0.1" and folds in what the
observation surface learned since (stdio at flush granularity, the hard-link
family, rustix-class raw syscalls as the canonical refusal example); the toml
gains equal billing with `--state`. The CHANGELOG's `[Unreleased]` became
`[0.5.0]` with the milestone summary; the PRD's v0.5 heading carries
"delivered". Everything else in this release rode earlier PRs the same day —
this one is the ceremony.

## 2026-08-13 — v0.5's last two items: the report as a schema, the quickstart as a workflow

The milestone's remaining scope line — "the report JSON documented as a
schema; a quickstart for CI (GitHub Actions example)" — closed with the same
discipline the README learned in v0.1: a document nothing executes is a claim
nobody measured.

**`docs/report-schema.md`** documents every field the report carries, per
verdict, plus the closed `unknown_reason` set — and acceptance check 4 holds
the page to reality in both directions: four fresh reports covering all four
verdicts (their union of fields must all be documented, every documented field
must appear in one of them), and the doc's `unknown_reason` list must equal
the contract's enum exactly. The comparison lives in
`spike/check-report-schema.py` taking paths, so the doc side falsifies in
isolation; three mutations seen red (a deleted field row, a deleted enum
value, a phantom field nothing generates) and green on the real page.

**The check caught two real drifts before it was even trusted.** First, its
own field regex `[a-z_.]` silently dropped `l0` and `l1` — a digit in a field
name — and reported them undocumented while they sat in the table (the
checker's first red was against itself). Second, the doc's `unknown_reason`
list was **seven values short**: the sed extraction used to WRITE the page
(`sed -n 'X,+40p'`) truncated the enum at forty lines and the page inherited
the truncation — the doc-writing pipeline was fail-open, and only the check
comparing against the enum itself exposed it. Also learned en route:
"toy-bug without an oracle" is NOT an UNKNOWN recipe — a FAIL stands on its
own evidence without completeness; the oracle gates only the would-be PASS
(the check's verdict-coverage guard fired on this, correctly, before the
comparison could go vacuous).

**`docs/ci-quickstart.md`** documents `.github/workflows/quickstart.yml` — a
REAL workflow that runs on every push to main and every pull request, against
a committed `docs/ci-quickstart/sideeye.toml` and this repo's planted-bug toy,
so the quickstart example is executed by CI rather than trusted. The demo job passes
iff sideeye finds the counterexample (exit 1, the gate a reader inverts for a
clean target); measured in the container before the workflow existed: FAIL at
crash point 5, the unlink→rename window — re-measured with no extra
environment after review showed the workflow's `TOY_STATE` was dead weight
(sideeye itself exports it to its children, pointed at the resolved state).
The doc carries the exit-code table and the honest default for UNKNOWN in CI:
fail the job — treating a refusal as green is how a target quietly leaves the
tested set.

**Review corrected the corrector.** The first-look pass found the digit bug
this entry brags about catching still alive in the enum regex fourteen lines
below the field-regex fix — a `[a-z_]` that would let a future digit-bearing
refusal (`l2_*`) slip out of the closed-set claim, and whose failure message
pointed the wrong way ("doc-only" reads as "delete it from the doc"). Fixed by
scoping the extraction to the whole enum block (values declared after a
`pub fn` count now) with strict member indentation, and falsified against a
mutated contract carrying `l9_added_after_fn` after the fn — red, in the
right direction. Smaller corrections in the same round: `explored ==
crash_points + 1` does not hold for a zero-operation PASS (both counters 0 —
now stated); `earliest.invariant` has five values, not three (the two
combined-layer forms are now listed, literals verified against main.zig); the
quickstart's short replay command was missing the required `--shim`; and
"every push" was the kind of rounding-up this repo dislikes — it runs on
pushes to main and pull requests.

## 2026-08-13 — The MCP-mediated run: two product gaps first, then the loop closed through the surface

The optional follow-up to the loop-closure measurement — drive the same sealed
experiment through `sideeye mcp` instead of the replay.sh plumbing — was
attempted the same day. It did not reach an agent. Probing the wiring against
the recorded loop-1 stage (read-only) surfaced two product gaps, which is the
kind of result the confirmation run exists to produce:

- **#68 — the minimal-env child cannot serve env-located-state targets.** The
  server hands its child PATH only (deliberate, ADR 0010: a config's operation
  must not read the server's credentials). But timewarrior finds its state
  through `TIMEWARRIORDB`; the sealed case replayed as `UNKNOWN
  (case_no_longer_applies): the recording now counts 0 state-changing
  operation(s)` — setup and operation ran against timew's env-free fallback,
  not the case's state dir. The 08-12 over-the-wire measurement used the toy
  scenario, whose operation takes its path as an argument; the gap was
  invisible from there.
- **#69 — no per-call state freshness.** `sideeye replay` re-runs setup onto
  whatever the state dir holds; every CLI caller so far provided a pristine
  dir (fresh container per replay), so the precondition was never written
  down. An MCP server is started once per client session: the second replay in
  the same session died in setup (`timew: You cannot overlap intervals`) —
  measured over the CLI with correct env, so it is not a symptom of #68. An
  agent's edit → rebuild → re-check loop through this surface dies on its
  second check.

**Decision (approved): fix the product before running the experiment**, rather
than scaffolding around the gaps (an env-free state location plus an
out-of-band state reset would have carried the run, but three more moving
parts to prove, and the honest conclusion would still have been "the surface
alone is not ready"). The fix directions, fixed before implementation:
`SIDEEYE_MCP_CHILD_ENV` — a comma-separated allowlist of variable NAMES,
values resolved from the server's own environment, so the operator who already
owns the trust boundary decides what the target needs and the agent never
touches it; a name listed but absent from the server environment is a loud
tool error, not a silent skip (a typo must not reproduce the silent 0-ops
failure). And `sideeye replay --fresh-state` — the state dir is already
sacrificial by contract (exploration kills processes mid-write into it), so
the flag empties and recreates it through the engine's existing guarded
deletion (`assertSafeRoot` + the same deleteTree the restore path uses); the
MCP server always passes it for replay children, the CLI default is unchanged.
Both changes get their acceptance checks red first.

**Harness facts measured on the way, for whoever wires an agent to MCP next:**
`--safe-mode` never starts `--mcp-config` servers (zero traffic on the snoop —
the config is not even read). The working seal replacement, measured:
`--disable-slash-commands` + `--settings '{"disableAllHooks":true,
"enabledPlugins":{...off}}'` + `--strict-mcp-config` from a foreign cwd gives
plugins [], skills 0, zero hook events across a real Write, OAuth intact, MCP
connected — residue: user agent names stay visible in the init event, inert
once Task is denied. Claude Code 2.1.229 speaks the 2026-07-28 stateless
protocol natively (first client frame is `tools/list` with `_meta`, snooped
verbatim — the missing-`initialize` worry was empirically unfounded). `--bare`
is not usable here: it skips keychain reads, so OAuth dies — same wall as the
scratch config dir. And a `:ro` DIRECTORY bind mount silently mounted nothing
on this docker/virtiofs stack — the container saw an empty path where the
stage should be; the same run's plain rw mount of the same directory worked,
and judge.sh's `:ro` FILE mount (the pos control's patch) demonstrably works,
so the failure is narrower than ":ro is broken" — measured for the directory
case only, cause not isolated. The stage mounts stay rw.

**Implemented and measured the same day (ADR 0011).** Three new acceptance
asserts were seen red against the pre-fix binary first: the allowlisted var
did not reach the child (check 7), a listed-but-absent name was not refused
(check 7), and the replay triple came back FAIL / SETUP_ERROR / SETUP_ERROR —
the toy's deliberately non-idempotent setup (mkdir of a fixed name) reproduced
the timew overlap shape exactly (check 8). After the fix: all 8 mcp-acceptance
checks green in the container, including check 4's isolation claim unchanged —
the unlisted secret still does not reach the child, now asserted in the same
run as the pass-through. Unit side: `freshDir` sits behind `assertSafeRoot`
(pinned with I/O-free guard tests; the behavioral half is pinned at the call
site by check 8, which is where the workspace discipline wants it). The
real-target contrast then held through the MCP channel against the recorded
loop-1 stage with `SIDEEYE_MCP_CHILD_ENV=TIMEWARRIORDB`: the reverted
(unpatched) tree replays **FAIL, crash point 19, twice in one server
session**; the agent's fixed tree replays **PASS, explored 2, twice** — same
code path, opposite answers, repeatable. One reading trap for whoever repeats
this: the loop-1 stage's `repo/` is the agent's FIXED tree, so PASS there is
the expected answer, not a broken probe.

**The confirmation run's protocol, fixed before the run (VARIANT=mcp).** Same
judgement, same seal discipline, same primary three-condition AND as the first
run — nothing about how the verdict is reached changes. What changes is the
agent's re-check button and its wiring, declared here before any agent runs:

- **Input set**: report JSON + the case it names + the define's setup/check +
  the pinned repo + `build.sh` (bug-blind rebuild-and-install plumbing) + the
  `sideeye_replay_case` tool served by `sideeye mcp` — started by the client
  from `mcp.json` at the root (outside the stage; the agent never reads it),
  with `SIDEEYE_MCP_CHILD_ENV=TIMEWARRIORDB` and PATH carrying `$STAGE/bin`,
  where build.sh installs the rebuilt binary. The seal stays seven files;
  replay.sh is simply replaced by build.sh.
- **Controls**: the judge's neg/pos pair as before, plus a third — the MCP
  channel itself must give opposite answers on this stage (unpatched: FAIL at
  the case's k, twice in one server session, because per-call freshness is
  part of what is proven; patched: PASS) before any agent runs. `finalize`
  refuses an mcp-variant record without it.
- **Seal recipe**: `--safe-mode` never starts `--mcp-config` servers, so the
  measured replacement is `--strict-mcp-config` + `--disable-slash-commands` +
  settings (hooks off, plugins off by name) + foreign-cwd project namespace.
  Residue stated: user agent names remain visible in the init event, inert
  with Task/Agent denied. Canary 1 asserts the measurable parts from the init
  event; canary 2 observes the enforcement once before the stage is burned
  (half of #63). **Canary 2 fired on its first form and was recalibrated** —
  the "nothing may fetch the page" assertion conflated two channels with
  different owners. What the probe actually showed: **in this configuration**
  the disallowed tools are ABSENT from the presented set (init carries no
  WebFetch — stronger than the allowlist, which leaves tools visible). Scoped
  deliberately: run 1's init, same CLI and the same five `--disallowedTools`
  but under `--safe-mode`, still presented all five — the removal was not
  isolated to the flag alone. The page arrived through allowed Bash + host
  network instead (`curl`), which is the declared soft-seal residual the
  AUDIT owns in the sealed run. The
  canary now asserts absence-from-init for the launcher's whole deny list plus
  no WebFetch attempt, and records the Bash residual instead of failing on it.
  The miscalibrated form did its one job correctly — it refused to burn the
  stage until the failure was understood. After the run, review widened the
  deny list to eleven names (the outbound/delegation surface: SendMessage,
  PushNotification, RemoteTrigger, ScheduleWakeup, CronCreate, CronDelete
  join the five) — and because removal is the configuration's behaviour, not
  the flag's, the widened list was MEASURED in a throwaway session before
  being trusted: all eleven absent from init, core tools intact. The recorded
  run itself used the five-name list; its six new names were merely
  void-by-audit then, denied-at-launch now.

**The run (same day): the loop closed through the MCP surface.**
`spike/runs/sideeye-loop-2/manifest.json`; numbers below are from the
manifest or the transcript's result event (the launcher now records
num_turns / duration / cost into agent-meta so the next run's headline is in
an artifact, not hand-read). Fresh stage at the pin reproduced the finding
(FAIL, k=19 of 24); all three controls held (judge neg with the crash-point
pin, judge pos, and the MCP channel contrast: unpatched FAIL@19 twice in one
server session, patched PASS). The agent: **claude-fable-5** (CLI 2.1.229) —
a different model than run 1's claude-opus-5, both Claude 5 family;
`models_billed` also carries a $0.0009 haiku sliver (CLI internals). **38
turns, 8.9 minutes, $4.43** (run 1, same num_turns metric: 75 turns, 16.6
min, $5.97). Tool ledger: Bash 19 / Edit 10 / Read 5 / Grep 1 /
**`sideeye_replay_case` 1** / ToolSearch 1 — the ToolSearch loaded the MCP
tool's schema (recorded `off_allowlist`, a local tool, not a void; it sits on
the path to the surface, so it is named here). Audit: clean — zero network
reaches, zero context reads, `server_tool_use` 0/0. The stage's only extra
file was `bin/timew` — present since the channel contrast installed the
agent's starting world, rewritten by the agent's one `build.sh` run; the diff
cannot and need not distinguish the two, the judge builds from `repo/` alone.
Judgement: replay gate **pass**, non-degeneracy gate **pass**, **loop_closed:
true**. **What the ledger actually shows — no iteration happened**: calls
1–33 read the tree and made 11 edits, call 34 was the first and only build,
call 36 the first and only replay — **PASS on the first attempt**; the MCP
call was the agent's only verification (plus one normal-world sanity check
after). The honest limit riding that: the edit→rebuild→re-check loop that
`--fresh-state` (#69) exists to support was exercised by the channel contrast
(two calls, one session), not by this agent. The fix is the third independent
derivation of the same three targets as the human patch, each part
implemented differently — journal-before-data via a `finalize_first` mark
and a two-pass `finalize_all` (vs opus's `commit_first` + `stable_partition`,
vs the human patch's reversed rename order); a stale-`tags.data` tolerance in
`Database::deleteInterval` (a tag absent from the index already has a zero
count — the human patch and opus both reordered instead, opus via
`commitTagDatabase`); and a no-op undo for an intent
that never landed (a `hasInterval` probe like opus's, arrived at
independently). Its final message names the rename-order root cause and both
violation windows precisely. The same cosmetic leak as run 1: the agent
answered in Japanese to an English prompt (path still not identified).
- **Audit**: `--allow-mcp sideeye` admits exactly the one trusted server's
  tools; every other `mcp__*` stays a void by name; all other void conditions
  unchanged (seen red/green against synthetic transcripts and re-run green on
  the recorded loop-1 transcript).
- **Acknowledged wrinkle**: `$STAGE/bin/timew` is executed from the virtiofs
  mount. The syscall-fidelity invariant covers the OBSERVED state dir, which
  stays container-local (`/tmp/loop-state`); executing a binary from the mount
  is not observation, and the channel contrast measures this wiring end to end
  before the agent does.

**The first-look review reversed one piece of the design; recorded here per
the contract.** The first implementation handed `freshDir` the case's raw
`define.state`. Review showed `assertSafeRoot` is lexical — "/tmp/../etc"
counts three slashes and passes, then the kernel resolves it to /etc; a
symlinked root walks past the same way — while every other destructive engine
call receives the realpath'd `state_abs`. The call moved to sit after the
existing mkdir-then-resolve and now receives `state_abs`, which also put every
setup validation ahead of the one destructive step and closed the symlinked
root that `deleteTree`'s child-level symlink refusal could not see. In the
same round `freshDir` stopped returning success when it could not do its job:
a regular file or a missing parent at the state path is a loud
`DeleteFailed` now — the silent no-op was the exact shape this flag exists to
remove. ADR 0011 Decision 2 carries the resolved-path requirement as part of
the decision, and the unit test pins the fact that makes it load-bearing
(`assertSafeRoot("/tmp/../tmp")` passes — the guard alone is not the
protection). The mutual contrast and the acceptance suite were re-measured
after the relocation: identical results.

## 2026-08-13 — Loop closure: the protocol is fixed before the run

The v0.5 milestone's remaining item is the loop-closure test itself (DESIGN §17,
second criterion; PRD v0.5). The protocol is written down here BEFORE any agent
runs, so that no gate moves after the measurement starts.

**The input set, declared.** §17 says "the counterexample report (JSON + replay
command) and the repository". As run, the set is: the report JSON, the case file
the report names, the define's `setup.sh` / `check.sh` (the declared invariant —
the case points at them and the replay cannot run without them), the timewarrior
checkout at the pinned commit `db7751cb`, and `replay.sh` — bug-blind plumbing
that rebuilds `./repo` and replays the sealed case in a `--network none`
container. The result will be reported with this set as its subject, not as
"the report alone". The stage carries the sideeye binary and shim as `.harness/`
(the plumbing has to run something); they contain no knowledge of the finding.

**Primary judgement, three conditions AND, fixed now:** (1) *originality* — the
judge trusts only `repo/` as the agent's work; every other staged file is
verified against a seal (sha256 manifest + pristine copies taken at stage time)
and restored from the seal before judging, so doctoring the checker or the
plumbing cannot reach the verdict; (2) *replay* — the judge's own fresh replay of
the sealed case must satisfy the leg-C predicate (PASS, explored 2, no
unknown_reason, crash_points == the case's ops_total); (3) *non-degeneracy* — in
a normal crash-free world, seed → track → undo must remove exactly the newest
interval. The checker's non-destruction form deliberately admits an undo that
always no-ops (2026-08-12 entry); a "fix" that silences the checker by
lobotomizing the feature fails gate 3 and is declared a failure up front. The
agent's prompt warns about this in general words only ("a change that disables
or degrades a feature does not count") — the checker already shows the agent
that undo is being exercised, so nothing about the finding leaks.

**Controls before the agent.** The judge must produce opposite answers on the
same code path before any agent runs: the unpatched tree must reproduce the
failure (gate 2 red, gate 3 green), the known patch must pass all three gates.
A constant-answer apparatus cannot satisfy both; the mutual contrast is the red
for these checks.

**Seal is soft, void is hard.** The agent host is a fresh headless Claude Code
session: `--safe-mode` (no user memory, no MCP, no hooks — the plan said scratch
config dir; that reversed, the dead-ends below carry the measurement), cwd = the
stage, a six-tool allowlist (Bash/Read/Edit/Write/Glob/Grep). An allowlist is
not a menu: the harness still presents its full tool set, web tools included, so
what a clean run proves is recorded non-use, not inability — all tool calls land
in a stream-json transcript and the audit reads every one of them. This is not a network namespace — Bash could reach the network — so
the invalidation condition is declared instead: the audit enumerates every call,
and one network reach or one read into this workspace voids the run. If a void
actually happens, the next run moves into a container with an egress allowlist;
building that fortress first was rejected as cost without a demonstrated need.
The upstream issue (timewarrior#778, filed 2026-08-12) postdates the model
cutoffs, so with the web closed it is unreachable; the model id is recorded in
the manifest either way.

**One deviation from the plan as approved:** the plan put the explore's work dir
container-local; as built, `work/` lives in the stage (mounted at the identical
absolute path in host and container) so that the report's `case` and `replay`
fields name paths that are real in the agent's world — the report telling the
truth about where things are IS the thing under test. The state dir stays
container-local (`/tmp/loop-state`): it is the directory under observation and
its syscall semantics must not ride a virtiofs mount. After the explore, the
work dir's traces and captures are moved out to `spike/runs/` — the input set is
the report, not the trace — and only the case file survives in place.

**The run (same day): the loop closed.** `manifest.json` in
`spike/runs/sideeye-loop-1/`; every number below is from the judge's own
measurements, not the agent's claims.

- **Stage**: fresh explore at the pin reproduced the finding exactly as in v0.4
  — FAIL, case k=19 of 24, two violating worlds. Seven files sealed.
- **Controls held**: unpatched tree → replay `fail_reproduced` + functional gate
  pass; known patch → all three gates pass. Opposite answers from one code path.
- **The agent**: claude-opus-5[1m] (CLI 2.1.229), headless `--safe-mode`, cwd =
  the stage, a six-tool allowlist (Bash/Read/Edit/Write/Glob/Grep), no MCP, no
  memory. The transcript's init event shows the full tool set was still
  presented — web tools included, no denial ever recorded — so the claim is
  non-use, with two independent witnesses: every one of the 74 tool calls is on
  the six (Bash 37 / Read 17 / Edit 19 / Grep 1), and the server-side counters
  read `web_search_requests: 0, web_fetch_requests: 0`. 75 turns, 16.6 minutes,
  $5.97. Audit: clean — zero network reaches, zero reads into this workspace,
  zero edits outside `repo/` within the stage (the only extra file was its own
  `replay-latest.json`; it did write two scratch logs under the host's `/tmp`,
  against the prompt's letter, and read them back itself only).
- **Judgement**: replay gate **pass** (PASS, explored 2, crash_points 24 ==
  ops_total, fresh state, rebuilt from the agent's tree with everything else
  restored from the seal); non-degeneracy gate **pass** (normal-world undo still
  removes exactly the newest interval). **loop_closed: true.**
- **Secondary observations**: judge-side full explore of the agent's tree —
  **PASS 25/25 worlds** (24 crash + 1 baseline; both violating worlds gone).
  Upstream suites on the agent's tree: AtomicFileTest 18 pass / 0 fail /
  6 skipped — the six are the fault-injection cases (`FIU_ENABLE` is compiled
  out without libfiu, which the image lacks), and they cover exactly the error
  paths the agent's change touches, so that 0-fail is lighter than it reads —
  data.t 96/96, Datafile.t 2/2, TagInfoDatabase.t 8/8 (`test/AtomicFile.t`, a
  bash launcher for the same binary, errored on a path it hardcodes; ignored as
  a duplicate of the directly-run binary, not counted as a pass). The agent's own broader
  before/after comparison (undo.t 29/29, track.t 15/15, config.t 22/22, ~1055
  C++ asserts, pre-existing chart.t/help.t failures identical on both sides) is
  recorded in the transcript but is its claim, not the judge's.
- **The fix itself**: the agent independently re-derived the same three-part
  mechanism as `spike/timew-undo-ordering.patch` — journal renamed before the
  data it describes (write-ahead), tags.data ordered ahead too, and an undo of
  an intent that never landed becomes a no-op — implemented differently
  (a `commit_first` flag + `stable_partition` in `finalize_all`, and a
  `hasInterval` probe in CmdUndo). Its final message names the root cause
  precisely: the rename order was first-touch order, so data files (touched by
  load) renamed before the journal. Nothing in its world named undo except the
  declared invariant (`check.sh`), the report's crash-window paths — and,
  because the stage carries a full clone, the upstream branch name
  `issue/772-undo-command-documentation`, which its `git branch -a` did print
  (a documentation issue, different mechanism; harmless here, but a full clone
  also means an older pin would ship upstream's own later fixes inside the
  stage — a shallow-fetch stage is filed as follow-up).
- **Apparatus checks that had not fired were fired deliberately** (on a copy of
  the root, so the real run's records stay untouched): a doctored all-pass
  `check.sh` was detected, restored from the seal, and re-verified by hash. The
  copy's replay then refused with SETUP_ERROR — a case pins absolute paths and a
  relocated root is not the recorded world (the identical-path mount invariant,
  demonstrated rather than argued) — which also means the end-to-end
  proposition "a doctored checker still cannot reach a *completed* replay
  verdict" was not carried through on the copy: what is measured is detect →
  restore → re-verify, plus the refusal. `finalize` on a results dir missing
  the controls exits nonzero — the record's completeness rides the exit code.
- **Two apparatus dead-ends, measured**: a scratch `CLAUDE_CONFIG_DIR` cannot
  authenticate (the keychain credential is keyed to the config dir; seeding the
  account keys from `~/.claude.json` does not help), and running under the
  default config would have loaded this workspace's own SessionStart hooks into
  the agent — `--safe-mode` disables every customization while auth works. The
  isolation evidence is the transcript's init event, an artifact: `mcp_servers:
  []`, default output style, built-in agents only. The committed canary proves
  auth and nothing more (its one-word reply was not kept; the next staging
  saves it). One leak, path not identified: the agent answered in Japanese to
  an English prompt — some user-level preference survives safe mode; nothing
  about the finding rides on it.

What this does and does not claim: the loop closed once, on this finding, for
this input set (report + case + declared invariant + repo + bug-blind plumbing
— not "the report alone"), under a soft seal with a declared void condition
that did not fire. v1.0 entry criterion 2 is met by this measurement; the
remaining v0.5 scope (report schema doc, CI quickstart) is untouched by it.

**The first-sight review corrected this entry** (a fresh-context proxy — Codex
was out of credits). The one finding that mattered: "tools limited to" was
false — `--allowedTools` is an allowlist, not a menu, and the transcript's init
event shows the full tool set presented, web tools included — and the audit
that should have caught a web call only examined Bash commands. The reviewer
proved the fail-open with a synthetic transcript (WebFetch, WebSearch, a Task
delegation, a home-dir bind mount: `audit: clean`), and proved the real run
clean by independent means (server-side web counters 0/0, every one of the 74
calls on the six allowed tools). The audit now judges every call, per escape
channel: network/delegation tools void by name, Bash text by the network
markers, any tool input by the repo and user-config paths, docker by absolute
mount sources outside the stage — while variable mount sources ("$PWD") are
recorded as unresolved rather than voided, because a transcript holds shell
text, not resolved paths, and the real clean run mounts "$PWD:$PWD" from inside
the stage. An empty transcript is now unauditable, not clean. Seen red on the
synthetic transcript and green (verdict unchanged, 74 calls) on the real one.
The negative control now also pins the reproduced crash point to the case's k
(crash_point 19 == case_k: green; mutated k: red) — a checker broken for an
unrelated reason no longer opens the agent gate. The recorded run's artifacts
in `spike/runs/sideeye-loop-1/` are NOT rewritten: `audit.json` there is the
pre-review auditor's output (old field names), kept as the record of what
judged the run at the time; the rewritten auditor applied to the same
transcript returns the same verdict — clean, 74 calls — measured independently
twice (this session and the R2 reviewer). Smaller corrections riding the
same round: the stale scratch-config-dir sentence in the protocol paragraph,
the canary's quoted evidence (no artifact existed — the isolation evidence is
the init event; the canary now saves its reply), the full clone printing
`issue/772-undo-command-documentation` under `git branch -a`, "25/25 crash
worlds" (24 crash + 1 baseline), the unexplained AtomicFileTest skips, and the
host-/tmp scratch logs the prompt's letter forbade. Apparatus work that needs a
fresh staging to verify honestly — shallow-fetch stage (#62), a canary that
probes the seal red (#63), a committed generator for the secondary
observations (#64) — is filed as issues rather than silently absorbed.

A cleanup pass after the review tightened three things (each seen red against
the recorded artifacts, none touching a judgement): the define's operation is
written once and rides `protocol.json` to the functional gate instead of a
second hand-written copy; the seal now pins the exact expected inventory, not
its size (a one-in-one-out swap passed the count check and fails the list
check); and the judge's usage text is derived from the header structurally
instead of a line-number constant. The class it declined to fix in this PR —
the declared invariant existing as three byte-identical copies across the
dogfood scripts and this experiment, and the leg-C predicate implemented twice
— is #65, because the fix direction runs through shipped measurement scripts
this plan pledged not to touch.

## 2026-08-12 — v0.4.0: the milestone is the measurements; the tag carries a passenger

Version 0.3.0 → 0.4.0, both hand-written strings at once (the unit test holds the
manifest and the CLI banner together — that is why the bump cannot be forgotten in
one place). What the release claims is the v0.4 milestone: §17 evaluated honestly
across omamori's full surface (the enumeration entry above) and regression-case
stability measured across the real timewarrior fix (the four-legs entry). What the
tag *carries* besides that claim is the MCP adapter and its post-merge fixes — v0.5's
surface landed on main before v0.4 was cut, and a tag cannot pick its passengers, so
the CHANGELOG and PRD both say so rather than letting the numbering imply v0.5
happened. The 0.5.0 tag waits for the loop-closure test, which is v0.5's own
acceptance. Repaired in passing, because the release links now exist to be checked:
the CHANGELOG's bottom link references had never gained `[0.3.0]` — the release that
introduced the section forgot the pointer to itself.

## 2026-08-12 — Every omamori surface, counted twice: the enumeration closes, three probes hit the same named wall

PRD v0.4's status has carried an honest parenthesis since this morning — "other
state-changing surfaces beyond `exec` were not enumerated exhaustively". Closed now,
by counting from two directions and requiring the counts to meet.

**From the command side** — every dispatch arm in `run()`, nested subcommands
included, plus the two non-command entrypoints: test, exec, install, uninstall, init
(plain and `--force`), config list/validate/add/disable/enable, override
disable/enable, audit verify/show/key-rotate/hash-cwd/unknown, break-glass
activate/`--status`/`--clear`, doctor (and its fix arms), setup, explain, report,
status (and `--refresh`), cursor-hook, hook-check, version/help — and the argv0 shim
mode plus the shim-routed hook-check.

**From the write side** — a sweep for write primitives (fs::write / OpenOptions /
rename / remove_file / create_dir / atomic_write / set_permissions / append) over the
non-test sources hits 12 files, and every hit maps to a command above: quarantine
moves (actions.rs ← exec/shim), the audit-chain append and the hwm
temp-create_new-rename (audit/mod.rs ← the whole append family), the retention prune
(below), key rotation (audit/secret.rs ← guarded), the warn-throttle and hook-verify
markers (← shim/hook), installer writes and the integrity baseline (← install,
doctor's fix arms, status `--refresh`), config writes (← the guarded config family),
break-glass state (← activate / guarded clear) and its denial-path audit append, the
shell-profile append (← setup), and doctor's transient writability probe. The
util.rs / context.rs hits are `#[cfg(test)]` code.

**Classification.** Read-only: test, explain, report, audit show/hash-cwd/unknown,
config list/validate, break-glass `--status`, version/help. Guarded — and the guard
refuses a human at a terminal exactly as it refuses an agent (#12), so driving one
would remove the defence under test: uninstall, init `--force`, config
add/disable/enable, override, audit key rotate, break-glass `--clear`. One asymmetry
worth naming: break-glass activation's *denial* path appends an audit event with no
guard in the way — but it exits non-zero, which is #3's wall, so it is recorded
rather than driven. Unguarded writers: **install, setup, plain init, and audit
verify** (plain init because creating a config where none exists is deliberately not
"modification"; audit verify because a missing or unusable high-water mark makes it
re-create the mark — a bootstrap write the first draft of this enumeration missed,
caught in review: the write site was mapped to "the append family" by file, and the
same `write_hwm` serves a second caller. Mapping files to commands is not mapping
call graphs to commands).

**The probes** (`spike/dogfood-omamori-surface.sh`: container, L0 + strace oracle,
disposable HOME inside the state directory, each expected outcome pinned):

- **install** and **setup**: UNKNOWN `unsupported_syscall_observed` — `symlinkat`.
  The installer creates the PATH shims as symlinks, which is outside the trace
  contract; the oracle sees an operation the shim cannot record and the account
  refuses (the #39/#5 wall family, named).
- **init**: the same refusal one step earlier, on `fchmodat` (the config directory
  and file permissions).
- **audit verify**: **PASS — 6 crash points, 7 worlds explored, 0 violations.** The
  bootstrap re-write of the mark is a single atomic publish (temp, `create_new`,
  rename), and every crash world keeps a database that is pre or post, never torn.
  This is the first omamori surface sideeye has fully explored to a verdict rather
  than met at a wall — a real §17-side data point, and it holds.

The probes' first version measured something else entirely, and the correction is
the part worth keeping: every probe initially answered `child_process_detected`
("the target replaced its own image") — which was about to be documented as
omamori's structure, until the pinned PASS prediction for audit verify failed and
forced a second look. The image being replaced was the harness's own: the operation
was wrapped in a shell script whose `exec "$OMAMORI"` is exactly an execve inside
the recorded process. The wrapper is gone (HOME/SHELL reach the child by inheritance,
the same wiring the timewarrior recipe uses for TIMEWARRIORDB), and the outcomes
above are the target's, not the recipe's. A measurement harness lies quietly; a
pinned expectation is what made this one speak up. One recipe detail that survives:
setup's own safety guard refuses a cargo build artifact as the hook source, so the
probe passes `--source` explicitly — without it the recording run exits non-zero
before hooks are touched, which is that install-time defence doing its job (measured
both ways).

**The one non-atomic write the sweep surfaced — recorded, not driven.**
`audit/retention.rs`'s `try_prune` rewrites the audit log **in place** (seek(0),
write_all, set_len, flush; no temp file, no fsync), and it sits on the append path,
firing every PRUNE_CHECK_INTERVAL appends once retention is configured. Everything
else in omamori goes through `atomic_file`; this is the exception. A crash inside
that rewrite leaves a mixed old/new log, which `verify_chain` would read as
tampering-shaped corruption — a false alarm on an honest log. Driving it under
sideeye needs entries older than the retention cutoff, and entries are hash-chained
with real timestamps, so it takes clock control this measurement does not have.
Recorded as the enumeration's one open finding, for the author to take to the
omamori side.

## 2026-08-12 — The saved case works across the real fix: replay-across-fix, four legs, measured

PRD v0.4's second scope item — regression-case stability *in practice* — had never
actually been exercised: the replay context gates were pinned by synthetic changes
(v0.3 acceptance), and the timewarrior fix was verified by a full re-explore, never by
replaying the saved case across the patch. `spike/dogfood-timew-replay.sh` closes that,
in the container, one saved case through four legs:

- **A** — timewarrior built at the pinned upstream HEAD `db7751cb` (still upstream HEAD
  at run time; `git ls-remote` returned the same hash), explored with the undo-contract
  checker: FAIL at crash point 19 of 24, case saved.
- **B** — replay against the same build: FAIL, "the case reproduced".
- **C** — `spike/timew-undo-ordering.patch` applied in a SEPARATE checkout, rebuilt,
  installed over the same PATH name, same case replayed: **PASS, explored 2, no
  unknown_reason, crash_points still 24.** The paths-only-warn rule (ADR 0009) did
  exactly what it was written for: the fix reorders same-class renames, the class
  prefix hash held, and the case stayed addressable across the real code change.
- **D** — negative control: the distro 1.4.3 package at the same PATH name: UNKNOWN
  `case_no_longer_applies`, exit 2. A recording with a different operation count gets
  a refusal, never a verdict.

The four legs demand three different outcomes from one code path (FAIL / FAIL / PASS /
refuse), so no constant-answer replay satisfies them — that mutual contrast is the red
for these checks. Leg C's PASS rests on the checker's contract as written (the
non-destruction form: undo must not remove an older committed interval; removing
nothing is allowed, because a crash may have beaten the intent's commit). That form
deliberately admits a hypothetical "undo that always no-ops" — sound for measuring the
crash windows, but it means leg C alone does not prove the fix *restores* undo, only
that the counterexample stops reproducing. The fix's positive behaviour is what leg
A's FAIL-then-PASS pair and the 25/25 patch measurement (this morning's entry) carry;
this script measures case portability across the change, not undo's full semantics. Wiring facts the recipe depends on, learned while writing it: the
case stores the operation as the PATH name `timew`, so a directory at the head of PATH
is the lever that swaps builds; TIMEWARRIORDB is not part of the case's identity (env
is not captured) and the recipe must re-export it; the setup is additive, so the state
directory is MOVED aside between legs, never deleted. For the record: aarch64
container, g++ 12.2.0, timew 1.10.0-dev vs 1.4.3, patch sha256
`586040127c56bac45a49595573837438e61e852583bb987e5814cfa32912ec96`. One environment
wall worth writing down: the corporate network intercepts TLS (Netskope), so the
container has to trust that CA before the clone can run — the measurement's integrity
does not rest on the transport, because the pin is the full 40-hex commit hash and the
recipe enforces it with `git rev-parse HEAD` after checkout (an abbreviated hash would
be a lookup convenience, not a content address — review caught the first version using
one while making this exact claim).

What this clears and what it does not: v0.4's regression-stability scope item is now
measured, not argued. It does **not** make the counterexample CI-resident (the case
still needs a built timewarrior), so v1.0 entry criterion 1's "kept as a replayed
regression case" stays open — the same two §17 gaps as this morning, with the replay
half now demonstrated.

## 2026-08-12 — The MCP green was partly vacuous: a reused work dir served a stale verdict

A post-merge adversarial re-review of PR #55 (its own PR, re-read cold) found the worst
defect a truth-telling tool can have: the wrong answer delivered confidently. Two
`sideeye mcp` processes sharing `SIDEEYE_MCP_WORK` collide on `report-N.json` /
`child-N.out` — the artifact counter is per-process — so the second server's `O_EXCL`
capture aborts its child at 126, and the parent then reads the *previous* server's
report back as *this* call's verdict, `isError:false`. Measured twice: natively (run 2
answered while neither work-dir file was rewritten — mtimes identical to the
nanosecond) and in the container (a call for `env.toml` answered with toy-bug's FAIL
report, a stale verdict about a different target).

Worse, the acceptance suite itself reused `/tmp/mcp-work` across checks, so its own
green was carrying two checks that could not look — a correction to the entry below,
which claims "env isolation, canonical self-exec" among the green: check 4's child
never ran (its "file absent → ok" soft branch is exactly what fired) and check 5's
"real report proves self-exec" assert was satisfied by check 1's leftover file. The
suite also ran in no CI job at all.

Fixes, each seen red first against the pre-fix binary: stale artifact names are
unlinked before the child runs (whatever exists there afterwards was written by this
call's child or by nobody — the work dir is operator-owned by ADR 0010's precondition),
the fork stub's own exits (126 capture / 127 exec) become tool errors instead of a
report read, check 4 fails when the env file is absent, and a new check 6 pins the
cross-server reuse case (server A explores toy-bug → FAIL; server B, same work dir,
explores toy-fixed and must answer PASS — the pre-fix binary answers A's stale FAIL).
The suite now runs in CI.

Same review, same class — the check and the code sharing an assumption: `isError` was
decided by substring-matching six `unknown_reason` strings, while the acceptance
asserts `isError ⟺ verdict ∉ {PASS, FAIL}`; the two agreed only on the one path the
suite exercised. `UnknownReason` has ~20 values, and the first from outside the list to
show up live (`no_shim_marker`, a macOS hardened binary) returned `isError:false` —
which an agent reads as a settled verdict. Replaced with the structural property (the
report's `verdict` field), fail-closed for unparseable reports, unit test seen killing
a mutation. And the spec half, verified against schema.ts raw rather than any summary:
`DiscoverResult` and `ListToolsResult` both extend `CacheableResult`, whose `ttlMs` and
`cacheScope` are *required* — both responses omitted them (and discover omitted
`resultType`), so a schema-validating client would have rejected the handshake before
anything worked. Smaller tightenings while in there: the `jsonrpc` tag is validated,
`clientCapabilities` must be an object, a transport write failure exits instead of
leaving a half line on fd 1, and `sideeye mcp` refuses extra argv.

## 2026-08-12 — `sideeye mcp`: a stateless MCP server, over paths not commands (ADR 0010, v0.5)

The agent-facing surface DESIGN §3 promised, and the first half of §17's second
criterion. `sideeye mcp` is a single-binary subcommand — a stateless loop over
`server/discover` / `tools/list` / `tools/call` (MCP 2026-07-28 dropped the
`initialize` handshake and exempts stdio from OAuth, which made a hand-written Zig
server small and killed the case for an SDK wrapper).

The plan's adversarial review (three Criticals) reshaped it before a line was written,
and building it caught two more failures that only a real run surfaces:

- **Design (review):** raw `operation`/`shim` as tool input is confused-deputy RCE, so
  the tools take *paths* (`config_path`/`case_path`), confined inside
  `SIDEEYE_MCP_ROOT`; the operation lives in the config, a human-inspectable file. The
  child is self-exec'd through the canonical binary (`/proc/self/exe`, not argv[0] —
  PATH hijack), with its stdout captured to a file (fd 1 stays the pure MCP transport)
  and a minimal environment (execve, PATH only — the server's credentials do not reach
  a config's operation). Acceptance pins all three: a PATH-planted fake `sideeye` is
  ignored, a secret env var does not reach the child, a path outside the root is
  refused before any exec.
- **Build (measured):** the PoC's first real `explore` call returned no response.
  Cause: the report is pretty-printed (newlines), and embedding it raw in
  `structuredContent` split the single-line JSON-RPC frame — the transport invariant
  the PoC exists to prove, broken by my own serializer. Fix: minify the report before
  embedding. Then a second real-run bug: the stdin loop dropped a final message not
  terminated by a newline (many writers omit the trailing `\n`), so a single unframed
  request produced silence. Fix: flush the buffer at EOF. Both are the class that
  passes unit tests and dies on first contact — which is why the plan raised the PoC's
  bar to "a real explore, self-exec'd, with fd 1 uncontaminated".

Measured end-to-end (Linux container): MCP `explore` with an oracle returns FAIL and
saves a case under the server root; MCP `replay` of that case reproduces the FAIL —
the loop-closes surface (§17 second criterion) works over the wire. Full MCP
acceptance green (transport framing, `_meta` validation on every method, version
negotiation, path confinement, env isolation, canonical self-exec). isError separates
a real verdict (PASS/FAIL) from an actionable one (SETUP ERROR / retryable UNKNOWN) so
the model can self-correct. Cancellation of a long explore is deferred (the sync loop
blocks; **parent-death cleanup of the self-exec'd group is not implemented** — a server
killed mid-explore can leave the target group behind, tracked honestly as a limitation,
not claimed as done) — the Tasks extension is future work.

Review R1 (Codex) then caught what the design draft got wrong about the *spec itself*,
which is the part I had read only in summary: `_meta` lives under `params`, not at the
top level, and `server/discover` returns `supportedVersions` + `capabilities`, not a
bare `supported` — as written, the server would have refused every spec-compliant
client (P0×2, fixed against schema.ts). And it found real hardening gaps: the child
still inherited fd 0/2 (a config's operation could read the MCP transport) and other
fds — now stdin→/dev/null, stderr→capture, higher fds closed, capture opened
`O_NOFOLLOW|O_EXCL` in a 0700 work dir; the report read is capped (4 MiB) and an
oversized stdin line is drained rather than mis-parsed. One review point (a
copy-into-work-dir TOCTOU defence) was tried and reverted: it breaks a config's own
relative resolution, and the residual window needs an attacker-writable root, which
SIDEEYE_MCP_ROOT is not by contract — stated in ADR 0010 rather than papered over with
a fix that breaks the common case.

## 2026-08-12 — §17 substantially met on the calibration target (two gaps), and why omamori was the wrong place to demand it

A wrong turn corrected first. The plan had "omamori §17 evaluation, human-driven at a
raw terminal" as remaining work. That is not real work — it cannot be done. omamori's
guard on config-modify / `init --force` / key rotate (#12) fires for a human at a
terminal exactly as it does for an agent; the guard is not a session check, it is
omamori refusing to modify its own defence, whoever asks. Making one of those a
Sideeye `operation` means the operation exits non-zero when not killed, which Sideeye
refuses to explore. Break-glass would "work" and would mean disabling the defence to
measure the defended operation's crash-consistency — self-defeating, and against the
discipline. So omamori's guarded surface is not evaluable by this tool at all, and the
plan item was struck.

That reframes what "§17 on omamori" could ever have been. The state mutation this
session actually drove is `exec`'s audit append, and yesterday's recon showed it
crash-safe by construction; the guarded self-modification commands are walled off by
design, and other state-changing surfaces beyond `exec` were not enumerated
exhaustively. Zero findings on the path we drove is exactly what §18 calls survivable
— and now with a mechanism, not a shrug.

Where §17 is *substantially but not fully* met is the calibration target §18 required
all along: timewarrior, a stateful CLI with no hand-written adversarial tests. Scored
honestly rather than generously, four conditions hold and two have real gaps — not
cosmetic qualifications — and the DESIGN/PRD text now says so instead of leading with
"met". **Reproducible / small / judged real by this project's author / stops-after-fix**:
clean (reproduce line + `cp`; one op, two-file window; filed as timewarrior#778, not
yet maintainer-confirmed; PASS 25/25 on the patch). **"Discovered automatically" —
partial**: this is the honest one. A human read the plain strace, confirmed by hand
with `cp` file surgery that `undo` destroys committed data, and *then* wrote the
checker; Sideeye automated the crash-world search, not the hypothesis (§4.1). Writing
this as "met" would have been the over-claim the first draft made and review caught.
**"Kept as a regression" — a recipe, not a replayed case**: the recipe and patch are
in the repo and reproduce it, but it needs a built timewarrior, so it is not a
CI-resident `sideeye replay` case — which means v1.0 entry criterion 1 is not yet
satisfied by it either.

§18's calibration test — does "no findings" mean the tool is weak or the target strong
— resolves to strong-target: hardened where we can drive omamori, a real find on the
deliberately-average target. That clears the calibration *kill* condition and lets the
project continue; it is not the same as clearing the v1.0 entry criterion, and the two
gaps above are what stand between them.

## 2026-08-12 — Why omamori's audit survives every crash window: hwm is confirmed *after* the body

Reconnaissance for v0.4, done the timewarrior way: read the write pattern with plain
strace before pointing sideeye at it, looking for a window before hunting a bug. The
question is whether omamori's `exec` audit append has a multi-file window like the one
that broke timewarrior this morning. It does not, and the reason is the exact inverse
of timewarrior's bug.

Measured (omamori 1.0.2 Linux, one `exec -- /bin/true`, isolated HOME): the audit
record is written to `audit.jsonl` first — 134 one-byte writes, no O_APPEND, no fsync
on the body — and only *then* is `audit.jsonl.hwm` (a high-water mark, contents "3"
for the third entry) advanced through the durable temp+fsync+rename+dir-fsync dance.
Body at trace lines 102–235, hwm confirmation at 245–249: the confirmation strictly
follows the content it confirms.

That ordering is what makes every crash window safe, and it is precisely the ordering
timewarrior got backwards. timewarrior renamed its journal (its hwm equivalent) *before*
the data, and `undo` trusted the journal — so a crash between the two renames left the
journal ahead of the data and undo destroyed committed work. omamori confirms after, so
whatever the crash leaves, verify stays conservative:

- body torn, hwm at the old value → verify trusts up to the hwm and drops the torn tail
- body complete, hwm still old → the last entry is treated as unconfirmed and dropped
  (data lost, but never inconsistent — the conservative direction)
- body complete, hwm advanced → all confirmed

This is why the run has been PASS 143/143 since #25 and stays there through contract
v5/v6/v7. **On the `exec` operation, no §17-class window exists — not for want of
looking, but by construction.** It is a clean instance of DESIGN §18's kill criterion 4
(the target may be too hardened to yield a novel bug): the same discipline sideeye
exists to check, applied correctly by the target.

The §17 primary criterion is not thereby closed. `exec` is the one state-mutating
omamori subcommand an agent can invoke (#12: config-modify / init --force / key rotate
are all guarded, and the guard is intended); pointing sideeye at those needs a human at
a raw terminal. What this session *can* conclude is the "written analysis of why none
was found" that v0.4's acceptance explicitly allows for — for the append path, and with
the mechanism named. And it strengthens the standing note that timewarrior — a
calibration target with no hand-written adversarial tests (DESIGN §18, PRD v0.5) — is
the live §17-class find, now with a mechanical contrast to omamori: confirm-after-body
holds, confirm-before-body breaks.

## 2026-08-12 — v0.3.0 ships

Version bump to 0.3.0 in both hand-written places (the drift test held them
together, as designed), `[Unreleased]` confirmed into `[0.3.0]`, tag and GitHub
Release (`v0.3.0 — The full Define contract`) to follow on the merge commit. No
workflow fires on tags here and nothing publishes to an external registry; the
release is the record.

## 2026-08-12 — v0.3 closes: the worked example runs from the toml, and the budget holds on a fresh target

Fifth and last PR of the plan. Two acceptance runs carry the milestone's claims.
The DESIGN §12 worked example — doctor cross-examined against reality — now runs end
to end with the define coming entirely from a `sideeye.toml` (check 2aa: FAIL, the
checker falsified first, the case saved). Seen red by synthetic input: the same check
aimed at the fixed toy exits 0 and the check demands 1.

The define budget (PRD kill criteria 3) got its measurement on a fresh target.
Watson (td-watson, a Python time tracker sideeye had never touched) is driven by
`spike/dogfood-watson/sideeye.toml`, one checker script and one environment variable
(`WATSON_DIR`) — and is refused honestly: every frame carries a fresh uuid4 and an
updated-at stamp, so the operation is not byte-reproducible and the un-crashed
baseline cannot match the recorded final (`baseline_violates_invariant`, the class
the first omamori run surfaced). The falsification probe fired loudly on the way in
("Invalid JSON file … frames"), which is watson's own reader earning the checker
seat. A refusal that names the right reason is the budget working, not failing — the
define fit the file, and nothing needed a recipe script's worth of glue.

PRD's v0.3 section flips to delivered with one deliberate narrowing recorded:
shrinking means the earliest failing crash point; "simplest" and measured
reproducibility counts stay future work and the report claims neither.

## 2026-08-12 — Replay: the same pipeline, one world, and a case that knows when it no longer applies (ADR 0009)

Fourth PR of v0.3, the last functional piece. A FAIL now saves its counterexample —
schema/versions, the resolved define, k, and a landing context of three parts: the
operation count, an FNV-1a hash over the class sequence 1..k, and the classes+paths
adjacent to k. `sideeye replay <case.json>` is `explore` with the kill set restricted
to {k, baseline}; the restriction is a `continue` in the world loop and nothing else,
so the oracle comparison, structural detectors, checker falsification, landing
evidence and quiescence all run — the acceptance pins that with a case whose stored
checker is `/bin/true`, which must die at falsification inside the replay exactly as
it would in an explore.

The plan's two review Criticals shaped the context design: adjacent-only matching is
aliased by one same-class insertion earlier in the sequence (every later index shifts
by one), so the prefix hash gates; and paths only warn, because pid-embedded temp
names differ between runs while naming the same operation — and because a fix that
*reorders* same-class operations (the timewarrior patch, measured this morning) keeps
classes while moving paths, which is precisely the replay-after-fix this exists for.
A case from a different trace contract refuses outright: v4 and v5 both changed what
`SIDEEYE_KILL_AT` counts, and a hash cannot vouch for a counting rule it was not
computed under. The context check sits before the zero-crash-points early PASS, so a
case whose operations all vanished cannot be answered with a green.

Measured: toy-bug's FAIL saves `cases/000001.json` and prints the replay line;
replaying unchanged reproduces (FAIL, "the case reproduced"); `TOY_EXTRA_FIRST=1` —
one extra write at the head of the sequence — answers `case_no_longer_applies` with
no verdict; the gated-checker case refuses `checker_not_falsified` inside the replay.

## 2026-08-12 — L1: the program is held to its own words, across the whole post snapshot (ADR 0008)

Third PR of v0.3. A success marker (`marker` in the toml, `--marker` as a flag) makes
the post-success invariant real: in worlds where the marker's bytes reached stdout
before the kill, the *new* state must survive — shared files on post content, history
files longer than their pre, created files present, deleted files gone (`not_durable`).
Judging the whole post snapshot is the point: the plan's own adversarial review
(Critical 1) caught that a strengthened L0 over shared files would miss a created file
vanishing — exactly what a success claim covers.

Two honesty edges did the design work. **"Not applicable" and "not observable" are
different absences**: a crash world killed before the marker is the normal shape of a
conditional invariant (L0 and the checker judged it anyway), but a marker the clean
recording run cannot produce refuses as `marker_never_observed` — a misspelled marker
must not make every L1 obligation silently vacuous behind a PASS. **The plan was wrong
about one case and the measurement fixed it**: the no-flush variant was slated to be
`marker_never_observed`, but a recording run completes normally, so libc's exit-time
flush delivers even an unflushed buffer to the capture — the honest verdict is a PASS
with `marker observed in 0 of N crash worlds`, and that is what ships (the buffer dies
with the process in every killed world, which is true of the real program too).

Mechanics: every operation run — recording, worlds, baseline — writes stdout to the
work directory through the same redirection (`runChildCapture`), so an isatty branch
cannot make the recording describe a different execution than the worlds; stdout
writes consume no crash-point address, so addressing is untouched. A rolling-window
`fileContains` scans the capture without holding a chatty target's output in memory
(the boundary-straddling marker is pinned by a unit test). The toy grew four L1
shapes; measured: the correct shape passes with the marker observed in 4 of 8 crash
worlds (the anti-vacuity bounds hold on both sides), claim-before-commit and
claim-before-create both FAIL as `not_durable`, and the misconfigured marker refuses.
Target stdout no longer leaks into the engine's console — the dogfood noise is gone.

## 2026-08-12 — sideeye.toml: the parser's width is the contract's width (ADR 0007)

Second PR of v0.3. The define surface gets its file form: `[world] state`,
`[define] setup / operation / check`, parsed by a hand-written strict subset
(~100 lines, `src/config.zig`) that refuses everything else with the offending line
named — unknown sections, unknown keys, bare values, duplicates, empty values,
escape sequences, trailing junk. The refusals are the design: a full TOML dependency
would accept arrays and dotted keys whether the contract wants them or not, and an
ignored key is a declared invariant that silently never fires, which is this tool's
worst shape wearing config clothes.

Three decisions worth their ink. **Keys exist only once they are enforced** —
`marker` is deliberately not in the schema until the PR that makes L1 judge
something; today it refuses as an unknown key, and the acceptance suite pins exactly
that, so the L1 PR will have to flip a red check rather than un-forget a parser.
**The file owns the define surface only** — `--shim`/`--oracle`/`--work`/`--json`/
`--allow-unverified` stay flags and combine with `--config`; the define-surface
flags are mutually exclusive with it, because a precedence merge would make the file
unreadable on its own (which line is in effect becomes invisible). **Relative paths
resolve against the toml's directory**, and command argv[0] resolves only when it
names a place (`./check.sh`), never a program (`mytool` stays a PATH lookup) — the
same file has to mean the same thing from anywhere, or a replayed define points at a
different state.

Measured: red first (the pre-change binary answers `--config` with "unknown
option"), then the DESIGN §12 example parses inline comments and all, a toml-driven
toy-fixed run reaches the byte-identical PASS verdict line the flags reach, and the
three refusal classes name their lines. Full acceptance green.

## 2026-08-12 — v0.3 begins: a refusal names the operation it refused on (#41)

First PR of the v0.3 plan. The account comparison already computed the divergence
index (`oracle.compare` returns it); everything after that index was thrown away on
the way to a one-line refusal, and the reader — twice now a whole dogfood session —
had to decode `trace-record.bin` with a copy of the acceptance suite's struct reader
and grep `oracle.txt` to learn which operation split the accounts. Now the oracle's
`parse` keeps the raw strace line behind each class entry (index-aligned), the shim
side keeps its records alongside the filtered class list, and both refusals
(`oracle_missed_operation`, `oracle_saw_phantom`) say: the 1-based divergence index,
the raw line the oracle holds there, and what the shim's account holds at the same
position — or that either account simply ends. The detail travels through the
existing `message` plumbing, so text and JSON carry it identically (DESIGN §13) with
no schema change and no trace-contract change (v7 stays).

One deliberate asymmetry: on allocation failure the naming is dropped and the bare
lead sentence survives — the refusal is the point, the naming is the courtesy, and
the courtesy must never cost the refusal.

Measured on toy-mixed (the mixed-visibility target): red first on the pre-change
binary (generic message in both forms), then
`divergence at operation 3: the oracle saw: openat(… "/tmp/acc/state/key.json",
O_WRONLY|O_CREAT|O_TRUNC …); the shim's account ends after 2 operation(s)` in text
and JSON alike. The timewarrior wall would have named its four ENOENT unlinkats on
the first run. Full acceptance green; the parse test now pins line/class alignment.

## 2026-08-12 — The fix experiment closes: reorder the renames, tolerate the unlanded intent, and the counterexample stops reproducing

The author's verdicts on the morning's finding, recorded before the experiment they
triggered: the timewarrior counterexample is judged a real bug (an undo that reports
success while deleting an interval committed the day before is genuinely incorrect
failure semantics), and §17 keeps omamori as its subject — this finding is recorded as
proof of the class, and the primary criterion is evaluated for real at the v0.4
dogfood, not retrofitted onto a different target. Upstream reporting waits until the
fix leg is measured, which is this entry.

Upstream HEAD reproduces it. timewarrior 1.10.0-dev (db7751cb), built from source in
the container: FAIL 2 of 25 worlds, earliest at crash point 19 of 24 — the same
window, after the month-data rename and before the undo rename. HEAD's `finalize_all`
wraps the rename loop in `sigprocmask` (PR #316, "Mask signals while updating
database"), which is evidence upstream knows this window must be atomic — and measures
as no defence here, because SIGKILL cannot be masked. Neither can OOM or power loss.

The checker's contract had to be refined first, and the refinement is a reversal worth
recording: the first checker demanded that undo always remove the newest *visible*
interval, but a correct recovery may find that the newest intent never landed (the
crash beat its data-file rename) and discard the intent without touching visible data
— the strict form would condemn that correct behaviour along with the bug. The
non-destruction form — undo runs, adds nothing, removes either nothing or exactly the
interval timew's own export names most recent — still fails the unpatched build 2/25
(both faces named: alpha deleted at point 19, the decrement abort at point 20), so the
red is preserved, and it passes a correct recovery.

The patch (kept as `spike/timew-undo-ordering.patch`, three small changes): finalize
in reverse registration order, so the undo journal reaches its final name before the
data files it describes — a crash may now leave the journal *ahead* of the data, never
behind; `Database::deleteInterval` deletes from the datafile before decrementing tag
counts, so the not-found check runs before anything mutates; `undoIntervalAction`
treats "failed to find" as the change never having landed — popping the intent is the
whole undo. Measured on the patched build: PASS 25/25 in both explorations (the same
counterexample stops reproducing), and upstream's own suite holds — 37 bash behaviour
tests, AtomicFileTest 24, data.t 96, Datafile.t 2, TagInfoDatabase.t 8, all green.

Known-issue check before any report, as directed: #772 (open, 2026-08-03) is the
nearest neighbour and a different mechanism — a missing fsync lets an unclean
*shutdown* zero-fill undo.data (content durability, power loss, filesystem-dependent);
this finding is rename *ordering* under process crash (filesystem-independent, and
untouched by adding fsync). #182 wants a consistency doctor and names mismatched tag
counts as a symptom without the crash-window cause; #480/#292 are disk-full and an old
truncation. Nothing covers the ordering mechanism or undo aiming at the wrong
transaction. The maintainer engaged constructively with #772's explicitly AI-generated
analysis five days after filing.

Reported upstream as GothenburgBitFactory/timewarrior#778, in the shape the author
directed: what was found, the two `cp`-only reproductions, the risk, and a request to
confirm — no fix proposal in the opening post; the tested patch stays here until the
maintainer engages.

## 2026-08-12 — A fifth target picked by reading commit tails: timewarrior's undo desyncs from its data across a crash

Four targets in, §17 is still open, so the fifth is chosen for bug likelihood rather
than coverage: strace the candidates' write patterns bare, before sideeye enters the
picture, and only aim at a commit shape that actually has a window. Two candidates,
one survivor:

- **jrnl 4.6 (Python): rejected.** Guessed to rewrite its journal in place; measured
  otherwise — whole journal into a random-named temp (`O_EXCL`), one write, rename.
  No fsync anywhere, which is invisible under a process-crash model. Predicted PASS,
  so not a §17 candidate.
- **timewarrior 1.4.3 (C++): selected.** One `timew track` rewrites three files —
  month data, `undo.data`, `tags.data` — each atomically via pid-named temp + rename,
  but the three renames run in sequence at the very tail: data, undo, tags. Every
  crash between them leaves files that are individually pre-or-post (L0 passes by
  construction) and mutually inconsistent.

The window that matters was then measured by hand, with file surgery and no sideeye:
restore the state to "month data has the new interval, undo.data still ends at the
previous transaction" and run `timew undo`. It deletes the OLD interval — committed
long before the crash — and keeps the one whose commit crashed. The documented
contract is "The undo command will undo the most recent change"; after this crash it
destroys data it was never asked to touch. The other window is stale `tags.data`, and
it is deliberately not part of the checker: `timew tags` recomputes from the interval
database (measured — hand-staling `tags.data` changed nothing), so that staleness has
no reader to lie to.

The checker (`spike/dogfood-timew.sh`) states the undo contract and nothing else:
undo must remove exactly the interval timew's own export names as most recent. Two
measured facts make it workable: `timew export` dies loudly on garbage (exit 255,
"Unrecognizable line …"), so falsification passes with no strict wrapper — the
opposite of todoman's `todo list`; and the engine snapshots the crashed state before
the checker runs, so a checker that mutates state (undo rewrites the database) cannot
contaminate the L0 judgement (main.zig takes the snapshot at the top of the world
loop, judges that snapshot after the checker).

For the record, since §17 asks what was discovered *automatically*: the window was
first spotted by reading a plain strace and confirmed by hand; sideeye's part is to
find it blind from the declared contract and hand back a minimal reproducible
counterexample. The claim under test is "point the declared invariant at the tool and
the exploration lands on the bug", not "nobody looked at a trace first".

The first run refused — and surfaced a sixth-through-tenth cousin of #30. Both
explorations came back `oracle_missed_operation`: timewarrior's AtomicFile cleanup
removes every registered temp name at exit through `remove(3)` — including
`timewarrior.cfg.<pid>-1.tmp`, which this run never created — and libc implements
remove as unlink-then-rmdir *internally*, behind the PLT. Four failed unlinkat
attempts (all ENOENT, the renames had already consumed the temps) were visible to
strace and invisible to the shim. The account conventions are symmetric on purpose —
the shim records before the call, outcome-blind, and `syscallSucceeded` in the oracle
only gates cwd tracking — so the honest fix is to interpose remove and reimplement
its documented two-step through the shim's own unlink/rmdir wrappers: every attempt
recorded pre-call, matching strace attempt for attempt, EISDIR probe included (glibc
falls through on EISDIR; Apple's BSD libc on EPERM — each platform's wart kept). On
macOS this is not ergonomics but soundness: there is no oracle there, and a
mixed-visibility target (some ops seen, removals not) keeps `mutation_count != 0`, so
`state_changed_without_ops` stays silent — the same mixed-case PASS hole R1 closed
for raw syscalls in v0.1. TOY_REMOVE pins it (check 2w): refused as
`oracle_missed_operation` before the interpose (seen red), PASS 12/12 with the exact
kill sequence — the never-created path's failed attempt an address on both accounts —
after.

The re-run landed where the hand measurement said it would, and one window deeper.
(a) L0 alone: PASS 20/20, oracle agreed on 19 operations — no single file is ever
torn; the bug is not in any file, it is between them. (b) undo contract: **FAIL, 2 of
20 worlds**, earliest at crash point 14 of 19 — after `rename(2020-01.data.tmp)`,
before `rename(undo.data.tmp)` — where `timew undo` prints "Undo", exits 0, and
deletes the alpha interval committed the day before, keeping beta whose commit
crashed. Replayed end-to-end from the reproduce line: kill 137 at point 14, export
shows both intervals, undo, alpha is gone. Crash point 15 (before the tags rename) is
the reversal this file exists to record: the claim two paragraphs up that stale
`tags.data` "has no reader to lie to" was measured against `timew tags` and was wrong
by one command — `timew undo` reads it to decrement the cached counts, errors with
"Trying to decrement non-existent tag 'beta'", exits 255 and undoes nothing. It
undoes nothing *atomically* (both intervals and the txn survive — the good half), but
undo stays unusable until tags.data is repaired by hand. One declared contract, two
distinct failure semantics: an undo that succeeds and removes the wrong thing, and an
undo that cannot run at all. Falsification passed bare — `timew export` on garbage
exits 255 — the opposite of todoman's lenient reader.

## 2026-08-11 — todoman reaches a verdict: a fourth target, and falsification rejects a lenient reader

Re-ran todoman 4.1 (Python) after #34; the calibration sweep had ended in an honest
refusal (`unsupported_syscall_observed: linkat`, filed as #31). The wall is gone. The
operation (`todo new` against a seeded list) confirms its entry the atomicwrites way —
temp created `O_EXCL`, reopened, written (302 bytes), fsynced, link(2)ed to the final
name, temp unlinked, directory fsynced — seven state-directory operations, and the
linkat that used to stop the whole run is now a kill point like any other. PASS 8/8
crash worlds, oracle agreed on 7 operations (6273 syscall lines examined, 38 in scope).
Fourth real target with a full verdict, the first in Python, and the field confirmation
that #34 closed the wall it named. No new bug: atomicwrites holds under every crash
point, so the §17 primary criterion is still open.

The checker leg measured something better. `todo list` as `--check` is rejected by
falsification: with every state file overwritten with junk it prints a traceback —
"Failed to read entry …" — and exits 0, answering "nothing wrong" precisely when it
could not look. Sideeye refuses the checker (`checker_not_falsified`, UNKNOWN) rather
than let eight crash worlds pass vacuously against a reader that skips what it cannot
parse. A wrapper that fails on the skip message restores the contract: falsified before
the run, then PASS 8/8. That is DESIGN §14-13 doing its job against a real target's own
diagnostic — the first real checker the gate has rejected, as opposed to a synthetic
`/bin/true`.

The recipe lives in `spike/dogfood-todoman.sh` now; this session had to reconstruct it
from scratch because the sweep ran it ad hoc. Two environment walls worth keeping: pip
inside the container needs `--trusted-host` for pypi.org and files.pythonhosted.org
(the host network intercepts TLS with a self-signed chain — the same wall rustup hit),
and todoman 4.1 with the current icalendar imports `pytz` at runtime, which neither
package declares. `TODOMAN_CONFIG` must end in `.py`; todoman loads it with importlib.

## 2026-08-11 — The oracle resolves paths instead of scanning lines (#31, in progress)

With stdio observed (#32), git's account stopped splitting on `COMMIT_EDITMSG` and split
one wall later, on `mkdirat(AT_FDCWD</g1/repo>, ".git/objects/cc", …) = 0`: a relative
path with no absolute state-directory spelling anywhere in the line, and a return value
of 0, so no result-fd annotation either. The oracle's `touchesStateDir` scans the whole
line for a `"…"` or `<…>` string starting with the state directory, finds none, and
declares the mkdir out of scope. The shim records it (it resolves against the cwd); the
accounts diverge; the run refuses. Same mechanism as the `linkat` that todoman surfaced
(#31), and the more dangerous direction — the tool's whole premise is *refuse what you
cannot see*, and this silently didn't.

The measurement that shaped the fix: on aarch64 every relative call comes through an
`*at` syscall and strace's `-y` annotates `AT_FDCWD</current/dir>` per line, following
relative `chdir` and `fchdir` both (measured). On x86-64 it does not — glibc 2.36's
`mkdir`/`link`/`unlink`/`rmdir`/`symlink`/`chdir` are generic and issue the legacy
syscalls (confirmed in the source, since qemu-user can't be ptraced to measure it), so
the line is `mkdir("state/sub", …)` with no annotation at all and the cwd has to be
tracked. CI runs on x86-64, which makes CI the measurement: a relative-spelling toy that
must reach the same verdict as its absolute twin can only pass there if the tracking is
right.

Adversarial review of the plan (three Critical, five Major) turned "add relative
resolution" into "replace the scope test". The first Critical is the reason: leaving
`touchesStateDir`'s whole-line scan in place as `scope = old ∨ resolved` re-lets every
hole the typed table was meant to close — a `write(1, "/state/path")` buffer string, a
`symlinkat` whose *link content* names the state dir — because the old scan still says
yes. The typed table is only authoritative if it is the *only* authority: path syscalls
resolve their real path arguments, fd syscalls read only their `<fd>` annotation, and
the whole-line scan survives solely as the conservative net for syscalls in neither
table (a net that only ever routes to `unsupported`, so a false hit refuses rather than
passes). Two more Criticals: two-path operations (`rename`, and the new `link`) had no
scope rule and the shim's `observe` judged only the first path — an `outside → state`
rename is a real mutation the first-path test drops — so "in scope iff either path is
inside" goes into both observers, closing a rename blind spot as a side effect. And
`link`'s record order (`path`=new, `aux`=old) invited a natural-order implementation
that would silently miss `outside → state`; making scope independent of argument order
removed the hazard structurally rather than with a careful comment. Adopted too:
`AT_EMPTY_PATH` refuses, `CLONE_FS` joins the boundary refusals (a child sharing the fs
context can move the subject's cwd), the oracle finally sees `state_alt`, and the ADR
states plainly what hard links cost — restore splits them into independent files, and
inode identity, `nlink` and hardlink topology are outside the model.

**Implemented, and git reached a verdict for the first time.** The mutation pair split
along the architecture line the design predicted: unclassifying `link` reddened the link
checks on aarch64 directly, but *disabling the typed resolver* (forcing `pathSpec` to
miss, so path syscalls fall to the whole-line scan) left every acceptance case green on
aarch64 — because there strace annotates an absolute path on every relative line, and the
scan still finds it. Its four unit tests went red, because the legacy-form half of
"relative paths resolve by annotation and by tracked cwd" has no annotation to lean on —
it is x86-64 in miniature. So the resolver's scoping value is genuinely CI's to prove;
what aarch64 pins locally is the direction the scan got *wrong*, the false positives, and
those are unit-tested (a state path inside a write buffer, a symlink whose content spells
the state dir). One measured surprise: `TOY_RELATIVE` refused at first with
`unsupported: getcwd`, because after the toy chdir'd into the state directory `getcwd`
returned a state-directory string and the conservative net scoped it in — it is a read,
now listed as one.

git commit, pinned dates, no oracle wall left: **the two accounts agree on 33 operations,
34 worlds explore, and the verdict is FAIL — one world, at `COMMIT_EDITMSG`, "holding
neither the old nor the new content".** It is not a git bug. `COMMIT_EDITMSG` is git's
editor scratch file, opened `O_TRUNC` and then written, so a kill in that window leaves
it empty; git rewrites it on the next commit and never reads a torn one. Run again with
`git fsck --connectivity-only` as the L2 checker: the falsification probe rejects a
corrupted object store, and then fsck passes *every* crash world — the report's invariant
stays "built-in atomicity (L0)", never "and the checker". So git's real integrity holds
across all 34 worlds; the loose objects (write-tmp, link-into-place, unlink-tmp), the
refs (lock + rename), the index and the reflogs (history form) are all crash-consistent,
and L0's one complaint is about a file whose atomicity does not matter. That is an L0
precision limitation on scratch files — the thing an ignore-list or an L1 marker is for —
not a defect, and worth filing as its own note rather than dressing up as a find. Every
regression held: taskwarrior PASS 12/12 with its own reader as the checker, omamori PASS
143/143, macOS parity exact (`link` in the same six kill-point addresses for the link
toy, relative and absolute spellings identical). 83 unit tests, 69 acceptance assertions.

## 2026-08-11 — The shim learns stdio, at flush granularity (#30, in progress)

The calibration sweep put a number on the wall: taskwarrior's writes are invisible above
its `fdatasync` (the shim recorded 4 of ~20 in-scope operations), and git — which writes
almost everything through raw syscall wrappers — lost its whole run to the **two** stdio
operations behind `COMMIT_EDITMSG`. Libc-internal calls never cross the PLT, so
interposing `write` says nothing about `fprintf`. One stdio call anywhere is enough to
split the two accounts, and most C programs have at least one.

The design was measured before it was written, and one measurement chose it. glibc's
buffer cannot hold more than its own size, so **the flush of pending data is normally
exactly one `write(2)`** — flushes are the one place where stdio granularity and syscall
granularity coincide. So the shim records `.open` at a write-capable `fopen`, `.write`
at `fflush`/`fclose` **when and only when the stream has pending bytes** (recording an
empty flush would invent an operation the oracle never sees), and `.close` at `fclose`.
Recording happens before the call, so the kill lands *before* the flush — what dies with
the process is the unflushed buffer, which is exactly what a real crash loses. What
bypasses the buffer (a large `fwrite` going direct, an overflow flush inside `fprintf`,
the exit-time cleanup of never-closed streams) is deliberately not modelled: on Linux
the oracle sees the extra writes and the run refuses, same as today, just from a much
smaller class. The alternative that would have made everything 1:1 — forcing streams
unbuffered — was rejected for the best reason this project has: it would explore crash
states the natural execution cannot produce.

Plan review (two Critical, eight Major) fixed a real bug before any code existed:
`freopen` with pending data issues **[write, close, open]**, and the draft recorded only
the last two — an instant `oracle_missed_operation`. It also forced the macOS caveat
into the open (no oracle there, so the not-modelled classes fall inside
`--allow-unverified`'s already-weaker claim rather than being caught), added the
missing glibc symbols (`fopen64`, `freopen64`, `fflush_unlocked`), and demoted
"one flush = one write" from an assumption to an expectation whose violation is
detected. Declined once, with reasons recorded: shipping this Linux-only. macOS goes
from zero stdio visibility to everything inside the boundary, under a claim whose
wording does not change.

**Implemented — and the first dogfood run found the flush point the plan did not
know about.** The toys all passed on the first full suite (six new acceptance cases,
kill-point sequences asserted with the decoder against exact predictions, the fopen64
alias exercised through an LFS build), the mutations landed red in both directions —
removing the pending check turned out to be caught by *three* checks, because it also
records a phantom write for the read-control stream's fclose — and then taskwarrior
refused again. The diff of the two accounts showed its `pending.data` write reaching
the disk inside an **fseek**: the file is updated through an `"r+"` stream, and libc
flushes a dirty stream as a side effect of repositioning it. `fseek`/`fseeko`/
`rewind`/`fsetpos` are flush points too, now wrapped with the same pending rule and
pinned by a toy in the taskwarrior shape ("r+", dirty, seek) whose check was shown its
own red once. The macOS pending fallback earned its keep immediately: the `__sFILE`
arithmetic passed the two-byte pin test on the first run, and parity came back exact —
the same six kill-point addresses for the stdio toy on both platforms.

**Review round, re-read as the contract demands.** Four findings, all adopted, one of
them the best catch of the day: recording freopen's whole [write, close, open] triple
before its one real call meant a kill aimed at the new `.open` died before *any* of the
syscalls — a world whose address claims the flush already happened, over a file that is
still empty. The wrapper now flushes explicitly first (record `.write`, real `fflush`,
then `.close`/`.open`, then the real freopen, whose own flush is empty), which keeps
the oracle's sequence identical and makes every address honest — the remaining gap
between the recorded close and the real one is disk-neutral, which is what ADR 0003's
close rule is for. The new acceptance pin kills at the open's address and asserts the
flushed line is durable; mutating the wrapper back to record-all-then-call went red on
the new pin while the sequence check stayed green — a measured demonstration of the
reviewer's point that recording order alone cannot see this. Also adopted: inactive/
re-entered shims no longer touch stream internals before refusing; `freopen(NULL)`
joined the documented not-modelled list; and the mode-predicate comment stopped
claiming the two predicates agree on inputs libc rejects before any syscall. taskwarrior: **PASS 12/12 worlds**,
oracle agreed on 11 operations, all three data files under the history form — and with
`--check "task list"` the falsification probe rejected the corrupted state
("Unrecognized Taskwarrior file format") and taskwarrior's own reader judged every
crash world. The second real target, judged end to end. git: `COMMIT_EDITMSG` no
longer splits the accounts — the shim now records all 31 in-scope operations — and the
run refuses one wall later, on #31's class: `mkdirat(AT_FDCWD</g1/repo>,
".git/objects/cc", …)` has no absolute state-directory spelling anywhere in the line,
so the oracle cannot see it (the result-fd annotation that saves relative `openat` does
not exist for calls returning 0). The wall moved from #30 to #31, exactly as scoped.
omamori: PASS 143/143 twice over, numbers unchanged — a Rust target never enters the
new wrappers.

## 2026-08-11 — L0 learns a second per-file form: history preservation (#24, in progress)

The plan was measured before it was written, and the measurement deleted two of the
issue's three directions. Re-running `omamori exec -- /bin/true` twice from the same
restored state, plus one straced run: the only non-reproducible file in the state
directory is `audit.jsonl`, and its shape is a strict extension — pre is a byte prefix
of post. The HWM sidecar is rewritten, but through temp+`rename` and with deterministic
content (`0` → `1`); the secret never changes; the lock and the `.hwm.tmp` exist in only
one snapshot and are outside L0 anyway. So the class "non-reproducible rewrite" — the
one that would need a per-world fresh baseline (direction 1) or L2 delegation
(direction 3) — has no representative in the first real target. Direction 2 alone
closes #24.

Two more measurements sharpened what the change means. The 142 operations are real: one
audit line is written through **134 separate `write(2)` calls**, so a kill lands inside
the line and leaves a torn tail — the "crashed content still begins with the pre
content" invariant holds there too, and whether a torn tail is acceptable becomes the
checker's question, not L0's. And `omamori audit verify` already answers it: fed an
audit log with a half-written last line, it reports "chain intact. (1 torn lines
skipped)" and exits 0. The dogfood prediction is therefore PASS, and a deviation from
that prediction would itself be a finding.

Adversarial review of the plan (two Critical, seven Major) forced one rename and one
reversal before any code. The form is **not** called "append-only": a snapshot proves a
shape, never a write mechanism, so the name now claims exactly what is checked —
**history-preservation form**. (The reviewer's "soundness regression" framing was
declined with a reason worth keeping: to a snapshot judge, the intermediate states of a
sequential rewrite are byte-identical to those of a true append — mechanism is not
observable in principle, and rename-rewrites, unlink-recreates and truncate-rewrites
all still land in violations.) The reversal: a file that is **empty in pre** does not
enter the form. `startsWith(anything, "")` is vacuously true, so the "history" of an
empty file constrains nothing; such files keep the standard pre-or-post rule, and a
non-deterministic fresh log stays an honest UNKNOWN instead of a silent no-check. Also
adopted: classification happens once (`classify → L0Plan`) and both the judgement and
the report read from it, so the two cannot drift; the report's `not tested` line grows
"appended tails" dynamically whenever the form is in play.

**Implemented; the mutation pair landed where the plan said it would.** The engine
change is `classify(pre, post) → L0Plan` plus a `judgeL0(plan, crashed)` that reads it,
a third violation (`rewritten`), and a report that carries the classification in text
and JSON alike. The shim is untouched and the contract stays v4. Disabling
classification alone sent the append toy back to `baseline_violates_invariant` — the
measured pre-fix class — and turned the rewrite toy's verdict into a *hybrid*-worded
FAIL, red on wording. Disabling the violation check alone let the rewrite toy PASS
with its truncate window open (red), while the non-deterministic rewrite toy **stayed
refused** — the boundary of the relaxation is held by the classification, not by the
arm that was just mutated, which is exactly the separation the L0Plan design bought.
While fixing the baseline gate's surroundings, its comment turned out to already be
wrong before this change: it claimed the gate is "only reachable through a checker",
and the first real target reached it with no checker at all — the baseline is a fresh
execution, not the recorded snapshot. The comment now says what was measured. 60 unit
tests, 57 acceptance assertions, all green on Linux.

**The wall is down, measured end to end.** The dogfood script now lives in the repo
(`spike/dogfood-omamori.sh`) and runs two explorations. Without a checker: **PASS
143/143**, the report naming `audit.jsonl` as the one history-form file and the oracle
agreeing on 142 operations — the same run that was structurally UNKNOWN yesterday. With
`--check "omamori audit verify"`: the falsification probe fails loudly on the corrupted
state ("audit secret must be exactly 64 hex characters"), and then the target's own
verifier judges all 143 worlds — visibly, one line per world: the early worlds hold one
entry, roughly 130 hold one entry plus a torn line it skips by design, the last few
hold two. PASS, as the torn-tail probe predicted. This is the first time a real
target's own invariant has been cross-examined in every crash world sideeye can
construct — and the first exploration where the question "is a half-written audit line
acceptable after a crash?" was actually asked 130 times and answered. One stumble on
the way: the first dogfood run ended in SETUP ERROR because a fresh HOME has no
`.local/share` and the engine creates only the final component of `--state` — the
script now makes the parents, and the error's JSON incidentally showed the `l0` note's
"not classified" state doing its job in the wild.

**Review round, re-read as the contract demands.** Two findings, both adopted. The
UNKNOWN text report carried no `atomicity` line while the UNKNOWN JSON did — the exact
"two forms, one content" rule this codebase keeps citing, broken by the surface that
was added to honour it; both lines now appear in `unknown()`, the acceptance pins the
text, and the pin was shown red once via a spelling mutation. And the l0 note embedded
target-chosen file names into the text report unescaped — a Unix file name may contain
newlines, enough to forge report lines. The note now defangs control bytes
(`evil\nname` prints as `evil?name`), with a unit test. The same-class scan found the
FAIL block's own path fields (`after`/`before`/`path`) have carried that exposure
since v0.1 — pre-existing, off this change's thesis, filed as its own issue rather
than widened into this diff. macOS parity: the append toy passes under the history
form and the rewrite toy fails at **the same logical address as Linux** (crash point 3
of 8, after truncate, before write). One environmental find that cost an hour of
suspicion: on this development machine, `DYLD_INSERT_LIBRARIES` is silently ignored
for binaries produced by `zig cc` (dyld prints nothing, no shim, no trace) while the
same source compiled by the system `cc` interposes fine — CI's zig-cc path stays
green, so it is pinned to this host's policy, not to the toolchain in general.

The plan, before the code: crash-point addressing and the completeness comparison move to
cover **state-changing operations only**. A write-incapable open — accmode is `O_RDONLY`
and neither `O_CREAT` nor `O_TRUNC` is set — mutates nothing, so the world killed
immediately before it is byte-identical to the world killed at the next address; it stops
being a crash point and stops being compared, on both sides, under one predicate. `close`
leaves the comparison too (it stays recorded): the simulation over omamori's accounts
showed read-only-open exclusion alone leaves the close of a raw-opened descriptor
stranded on the oracle's side, and fd-provenance tracking dies on `dup` and inheritance.
Simulated result to beat: **142 vs 142, aligned**. Contract bumps to v4 — the recorded
set changes meaning, and a v3 shim under a v4 engine should refuse loudly, not drift.

Adversarial review of the plan (one Critical, eight Major) reshaped two things before any
code: the oracle-side predicate is **fail-closed** — a symbolic `O_` token must be
present before anything is excluded; numeric-only flags (`0x241`), missing arguments and
unknown shapes are counted as before, so a parse failure ends in UNKNOWN, not a pass. And
the predicate moved from a flag-list to accmode, which keeps `O_RDONLY|O_CREAT` (creates
but cannot write) addressable and drops `O_APPEND` from the set (append without write
access cannot write). Rejected with reasons: recording flags in `aux` and projecting
later (a type pun that makes `aux` mean different things per op, and a third place the
predicate must agree), and fd→flags tracking (leaks on dup/inheritance).

**Implemented, with one prediction corrected.** The mutation pair went red in both
directions, but the plan mislabelled one: disabling the shim-side exclusion was predicted
to surface as `oracle_saw_phantom`, and it surfaces as `oracle_missed_operation`, because
`compare()` reports any mid-sequence divergence as "missed" and reserves "phantom" for a
shim account that is a pure suffix-extension. The discrimination is intact — the
read-first toy flips from FAIL at 5-of-5 to UNKNOWN under either one-sided mutation — the
label prediction was just wrong, and the acceptance comments say what actually appears.
Two count anchors moved exactly as the run-first sweep found them: "agreed on 6
operations" is 5 (close left the comparison), and the zero-op PASS wording is now "no
state-changing operations". 55 unit tests, 52 acceptance assertions.

**Review round, re-read as the contract now demands.** Three findings, all adopted. The
ADR overclaimed `O_RDONLY|O_CREAT` as "a mutation": it keeps its crash-point address, but
`OpClass.open` has never counted toward `isMutation()` (deliberately — it makes
`state_changed_without_ops` stricter), so a target whose only state change is creating
files via open is refused by that detector, before and after this change; the ADR now
says addressable, not credited. strace spells an *invalid* access mode as `O_ACCMODE`
(its own xlat says so), which the fail-closed token set did not contain — the one input
on which the two predicates would have split, now in the write set with a test. And
"state-changing operations" oversold the set — a write-capable open may change nothing —
so the public wording is "operations that can change state". The confirmation round then
caught the ADR still listing the old token set two paragraphs below the sentence that
described the new one — fixed; a document can contradict itself as easily as two
documents can.

**The measurement this PR exists for, and the wall behind the wall.** omamori again,
under the new rules: the oracle **agreed on 142 operations** (615 syscall lines examined,
183 in scope — the exact number the simulation predicted), one tolerated child, and the
engine explored **all 143 worlds with every kill landing, in about one second**. The
verdict is `UNKNOWN baseline_violates_invariant`, with 138 of 142 crash worlds reading as
violations — and that is the *correct* answer, not a defect: omamori's audit line carries
a timestamp and an HMAC chain, so re-running the operation writes different bytes, every
crash world's partial line matches neither the pre nor the post content, and the baseline
world differs from the recorded final for the same reason. The baseline gate built during
v0.1 release prep is precisely what stood between this target and a monstrous false
"FAIL 138 of 142". The next wall is therefore not observation but **operation
non-determinism versus L0's byte comparison** — filed as its own issue; candidate
directions include a per-world fresh baseline and an L0 form for append-only files.

## 2026-08-11 — The guard's own contract had the hole it was built against

Hours after the guard below merged, review of the practice caught its wording: "write the
entry before opening the PR" *permits batch-writing at delivery* — which is not a lesser
form of compliance but the documented failure mode itself. The containment entry was
written exactly that way, once, at PR-open; its central argument was reversed in review
two hours later; and the reversal never made it back in, because the entry was already
"done". A delivery-time log loses precisely the things that happen after delivery-time.

The contract now says what the journal's own header always said: append at the moment of
the decision, in the same working tree as the change it describes, and **re-read the
entry at PR-open and after every review round** — the reversal window is after writing,
so the re-read is the load-bearing clause. CI cannot see when a line was written, only
whether the file changed; the timing half of the contract lives in `CLAUDE.md` and in the
habit, and this entry is the first one written under it.

## 2026-08-11 — This log stopped being written, and a guard now keeps it written

The last entry written at the time it happened is six entries down, four pull requests ago.
Between it and now: the containment fix merged with its most instructive reversal
unrecorded, a defect that killed observed targets was found and fixed, boundary tolerance
shipped with a contract bump, and v0.2.0 went out — none of it logged. The catch-up entries
below were reconstructed from the session transcripts, the PR bodies, and the git history,
and each states only what was measured at the time.

Why it happened is worth a line: the delivery routine that produced those PRs carried the
CHANGELOG, the ADRs and the PR bodies — artifacts every repository has — and this log is an
artifact only this repository has. Nothing in the routine asked for it, so nothing wrote it.
The fix is structural, not resolutional: CI now fails any pull request that changes
`src/`, `shim/`, `spike/` or the build files without touching `BUILDLOG.md`, and the
repository carries a `CLAUDE.md` stating the contract — the entry is written before the PR
is opened, failures and reversals included. The guard was shown its red once, against a
synthetic diff with no log entry, before being trusted.

## 2026-08-11 — The opened boundary reveals the next wall: a dependency that bypasses libc

With #18 merged, omamori was pointed at again. It travelled: `child_process_detected`
(v0.1.0, nothing explored) → `unsupported_syscall_observed: flock` → after classifying
`flock` as read-only (advisory locks live in the kernel and die with the process, so no
crash world can be told apart by one) → `oracle_missed_operation`. The oracle saw a
state-directory operation the shim did not record.

The missed line is an `openat` of the state directory itself —
`O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY` — issued between taking the audit lock and
reading the secret. omamori's dependency tree includes **rustix**, whose Linux backend
issues raw syscalls; there is no libc entry point for `LD_PRELOAD` to reach. The shim
recorded the libc-reached operations around it faithfully, the oracle compared the two
accounts, and the refusal is exactly what the design promises for a target that bypasses
libc. But it is also categorical in the way the boundary refusal used to be: rustix sits
under a growing slice of the Rust ecosystem, so "a Rust program whose state handling is
partly rustix-backed" is a class, and the whole class is UNKNOWN. Filed as #19.

**The way through was measured before being planned.** The operation the shim missed
cannot change state: a read-only open mutates nothing, so the world killed immediately
before it is byte-identical to the world killed at the next address — a redundant world.
Simulating "read-only opens leave the numbering, on both sides" over the recorded accounts
brought them from divergence at index 3 to within one operation; the residue was the
**close of the raw-opened descriptor**, which the shim never saw born. Tracking fd
provenance dies on `dup` and inheritance, so the simulation instead dropped `close` from
the comparison on both sides — close is neither a kill point nor a mutation, and its only
role was positional corroboration. Result: **142 vs 142, aligned**.

The plan that came out of this — make addressing and the completeness comparison cover
state-changing operations only — went through an adversarial review that caught the
predicate being fail-open: the oracle-side read-only test would have accepted numeric
flags (`0x241`) as read-only. It now requires a symbolic token before excluding anything;
what it cannot parse, it counts, and a miscount is an UNKNOWN, not a pass.

## 2026-08-11 — v0.2.0: the version number was already promised to something else

Releasing the boundary work hit a problem no test catches: **the v0.1.0 release notes had
already promised v0.2 to the Define contract** — `sideeye.toml`, L1 markers, case storage
and `replay`. Published release notes are history and do not get rewritten. The options
were to ship as v0.2.0 anyway and say so, to mislabel it a patch, or to sit on a merged
defect fix (#17 — sideeye was killing the targets it observed) until the promised scope
existed. Holding a shipped fix hostage to milestone naming lost.

v0.2.0 went out with its own notes opening on the change of plan; the PRD now records the
queue-jump and the reason ("roadmaps yield to measurements; that is what they are for"),
moves the Define contract to v0.3 with its scope unchanged, and marks the macOS milestone
absorbed into v0.1 — its one remaining item is #10, the report's silence about *why* an
Apple platform binary shows `no_shim_marker`. Ceremony verified from the outside: fresh
clone of the tag, 53/53 tests, the banner reads `sideeye 0.2.0 (trace contract v3)`, the
planted bug still FAILs at crash point 5 of 5, and a forking target without an oracle
answers `boundary_without_oracle`.

## 2026-08-11 — Boundary tolerance ships: a child is judged by what it did

The tolerance rule designed after the first real-target run is now merged (#18, contract
v3): a fork or spawn boundary is explorable when an oracle is present and **no process
other than the subject touched the state directory**. A child that stays out of the state
directory consumes no sequence numbers, so the numbering that refusal was protecting stays
unique — the safety condition and the honesty condition are the same condition. Everything
else refuses with its own detector: a child that writes (`child_touched_state_dir`, from
either witness), any boundary without an oracle (`boundary_without_oracle` — the shim only
sees processes that load it, and "was not seen" is not "did nothing"), the subject
exec'ing over itself, threads, and anything that leaves the containment group.

**Two design pieces did not survive contact with the implementation.**

The planned arming mechanism — the engine sets `SIDEEYE_PRIMARY_PID` before exec — cannot
work at all under an oracle: the engine's direct child is *strace*, the subject is strace's
child, and the engine never knows its pid at setenv time. A trace-file marker ("whoever
wrote the header is primary") died in thought for a familiar reason: the engine does not
delete the reproduce line's trace file, so the printed command would silently stop arming
on its second run — the exact class of quiet inertness the reproduce line has been fixed
for twice. What shipped is the pid captured at the shim's own `init()`: a forked child
inherits the value but answers `getpid()` differently, and the fork is the only child that
inherits a mid-count `seq`. A spawned child re-inits and arms itself — tolerable, because
the kill fires only on a state-directory operation and a child's state-directory operation
already refuses the run. The arm can only go off in a world that is thrown away.

The second was found by the acceptance suite going red: `TOY_DETACH` — fork a child, child
calls `setsid` — was *explored*. The trace's first boundary record is the tolerable
`.fork`, and the engine's refusal switch read only the first boundary; the `.detached`
that must refuse the run arrived later and was masked. `hard_boundary` is now tracked
separately, pid-aware — a **child's** exec is a spawn doing what spawns do and must not
refuse, while the subject's exec must.

**The witnesses are independent, and a mutation proved it.** Disabling the oracle-side
touch check alone let exactly one case through: the spawned child that receives a clean
environment, never loads the shim, and writes into the state directory — the case only the
oracle can see. The shim-side check survived its own mutation under these toys (for
shim-visible children the oracle is a superset) and is kept anyway, with the reason in a
comment: the oracle reads paths textually and misses a child's *relative* spelling, which
the shim resolves against the child's cwd. Neither witness subsumes the other. Disabling
the no-oracle gate produced the most instructive red: the quiet-fork target explored and
the report printed `processes: single process` — the lie the gate exists to prevent,
verbatim.

Outside review: five P1, two P2, all adopted — a raw `clone(CLONE_THREAD)` walked past the
thread refusal; an unshimmed child's `setsid` is invisible to `%process` (measured; both
are now traced explicitly); oracle-only children skipped the quiescence sampling;
`mmap(PROT_WRITE|MAP_SHARED)` of a state file is a mutation with no later write syscall —
a PASS-side hole that predates this PR for the subject itself; a child's read-only open
was refused against the stated rule. The confirmation round then caught the two remaining
fixes reading flags **from the whole strace line instead of the flags argument** — the
same class as v0.1's `AT_REMOVEDIR` fix, which even left behind a test named for the rule.
Corrected with the argument splitter and pinned by a test in which a file named
`O_CREAT.bak` changes nothing.

53 unit tests, 50 acceptance assertions, 12 distinct detectors. The six tolerance cases
run one binary with one environment variable of difference, so an engine that decides by
anything but the child's behaviour cannot pass them all.

## 2026-08-11 — Observing a vfork killed the target; the fix is a call with no frame

Probing the boundary classifications for the tolerance work found a v0.1.0 defect worse
than any misclassification: **interposing `vfork` kills the target.** A vfork child runs
on the parent's stack while the parent is suspended, and the call returns twice. An
ordinary wrapper's frame spans that double return: the child pops the frame on its way
back into the target, runs, and overwrites the memory it occupied — including the saved
frame pointer and return address the parent's resume path will restore. The parent then
resumed into the *child's* branch and exited 127 with no output and no signal. sideeye
reported `UNKNOWN recording_run_failed` — blaming the target for a death it caused.

The control that placed the fault: vfork+exec of `/bin/true` exits 0 without the shim,
127 with it — **and 127 with the shim loaded but inactive**, recording nothing. The
corruption is the wrapper's stack frame itself, not anything the shim does inside it.
glibc's own `vfork` is hand-written frameless assembly for exactly this reason.

The first fix was removal: stop interposing `vfork` entirely, and let the child's exec and
the oracle carry detection. It worked, and it was the wrong trade — counted only after the
question "can this be broken through?" forced a second look. Removal leaves a
vfork-then-`_exit` child invisible on the platform with no oracle. What shipped instead:
record the boundary first (an ordinary call, safely before the fork), then reach the real
`vfork` through a **guaranteed tail call** — `@call(.always_tail)`, which is a compile
error on any backend that cannot honour it. At the jump the stack is exactly as if the
target had called vfork directly; both returns land in the target and the wrapper's frame
never exists across them. The guarantee promptly fired for real: Zig's self-hosted x86_64
backend (the Debug default) refused with "does not support tail calls", so the shim pins
`use_llvm`. Disassembly on both architectures ends in `br x0` / `jmpq *%rax` after a full
epilogue — a jump, not a call.

Also learned, each the hard way: `posix_spawn` survives an ordinary wrapper because glibc
hands its `CLONE_VM|CLONE_VFORK` child a freshly mmap'd stack, and `fork`'s child runs on
a copy — only `vfork` shares. The toy built to pin the fix committed the same class of
crime it was testing (its argv was constructed *in the vfork child*, on the shared stack;
now static and fully initialised before the fork — found in review). macOS has no
`/bin/true`, only `/usr/bin/true`, and the toy looked green anyway because the parent
discards the child's status — the test was quietly measuring less than it claimed. And one
measurement round was voided entirely by a 0-byte probe binary: the shell executes an
empty file as a successful no-op, so every "exit 0" in that round was the measurement of
nothing. `file(1)` before trusting a binary's exit code.

## 2026-08-11 — The structural argument in the entry below was wrong at the only moment that mattered

The entry below records, with some satisfaction, that the `getpgid` guard was removed
because "a freshly allocated pid cannot equal the id of a live process group". Review of
the containment PR (#14) found the flaw: that argument is true at the moment of `fork` and
**false after the reap**. The first implementation signalled the group *after* `waitpid`;
reaping releases the pid, an unrelated process can be allocated it and become a group
leader, and the `SIGKILL` meant for something that no longer exists lands on a stranger.

The fix is ordering, not another guard: `waitid(P_PID, pid, … WEXITED | WNOWAIT)` waits
for the child to exit while leaving it reapable, so the pid — and with it the group id —
stays spoken for across the signal. Kill, then reap. `WNOWAIT` differs between platforms
(`0x01000000` in glibc's headers, `0x00000020` in the macOS SDK) and was read out of both
rather than recalled; `P_PID` and `WEXITED` agree, and the comment says which is which.
The same-class scan — a wait-family call whose side effect is trusted without checking the
call happened — found one more: `waitpid`'s discarded result left `status` zero on
failure, reading a killed world as a clean exit. Now retried, bounded at 8 because nothing
in that file can tell an interruption from a permanent failure.

Merged with every pre-existing verdict unchanged and both directions measured: the
late-writing grandchild's file appears with the group kill disabled and never appears with
it in place. The suite also grew a guard for its own blind spot — `zig-out` holds one
platform's build, so a host build silently replaces the Linux cross-build and 36 checks
fail for one reason that reads like a tool regression; asked directly, the answer is one
line ("CANNOT RUN … built for this platform?"), confirmed against a wrong-architecture
binary on purpose. Two residues were filed rather than widened into the PR: a descendant
that calls `setsid` escapes the group undetected (#15), and quiescence is signalled, not
observed (#16). Both were closed by the tolerance work later the same day.

## 2026-08-10 — The first real target, and a hazard that was there all along

Pointed sideeye at omamori, the v0.4 dogfood subject. Two attempts, two UNKNOWNs, for two
different correct reasons — and the investigation cost three of my own claims.

**The issue I wrote about this was wrong.** I described omamori as "does its file work,
then execs". Decoding the trace: `posix_spawn` twice, **no `exec` at all**, at records 1–2
of 152, *before* any state work. All 143 kill-point operations happen in the process
sideeye already watches. The refusal was throwing away a complete picture.

**And the reason for the refusal was not what the code says.** The comments frame it as
"v0.1 explores single-process targets". The measured reason is *addressing*: `seq` is a
per-process counter while a crash point has to be a globally unique address. `fork` makes
parent and child both number their operations 3 and 4; `exec` resets to 1 and collides with
the parent's early numbers. `SIDEEYE_KILL_AT=3` names two operations, so it names none.

Two adversarial review rounds then broke two premises of the design I wrote for this.

**`runChild` waits for the direct child only.** Everything the target spawns outlives it.
After the subject is killed at crash point k, a grandchild keeps running while the engine
snapshots, restores for the next world, and runs the checker — so the "crashed state" is
whatever happened to be on disk when the engine looked. This is not a new hazard introduced
by tolerating children; **it is present today**, hidden only because such targets are
refused before any world is explored. The recording run still had it.

Confirmed both directions before believing it: a toy whose child sleeps 300 ms and then
writes `late.txt` produces that file with the group kill disabled, and never produces it
with the group kill in place.

**The guard I planned for it turned out to be unnecessary.** The plan said to confirm
`getpgid(child) == child` before signalling, because a failed `setpgid` would leave the
group id equal to the engine's own and `kill(-pgid)` would kill the engine. That cannot
happen: the id being signalled is the child's freshly allocated pid, and POSIX keeps a pid
out of circulation while it is in use as a group id, so it can never be the engine's group.
Removed the check and wrote down the argument instead. A structural reason beats a guard,
and it is one fewer thing that has to stay true.

**The second review found the acceptance condition itself was non-deterministic.** The
design had each child announce itself, and read "no announcement" as "unobserved". A child
killed by the group kill before it announces leaves no announcement, so the same target
would produce different verdicts on different runs. For a tool whose product is
determinism, that is worse than a wrong answer. It also conflates "died before doing
anything" with "ran unobserved" — the confusion this project exists to avoid, one level
down. Replaced by letting the oracle decide, which removed the announcement marker, the
race and the ambiguity together. **The design after two rounds of attack is smaller than
the one before.**

One measurement worth keeping: **the oracle changes the timing of the recording run.**
`strace -f` does not exit until its tracees do, so the same stray child makes the recording
run take 310 ms and its write lands inside the measured window. The recording run and an
explored world are therefore not timing-equivalent. The containment check deliberately runs
without an oracle for that reason — otherwise it would be measuring strace.

## 2026-08-10 — v0.1.0: four documentation gaps, one real defect, and a tag verified from the outside

Release preparation was mostly reading the documents as a stranger would, and the stranger
kept winning. **The PRD contradicted itself**: v0.1 listed `sideeye replay <case>` while
v0.2 listed the case storage a replay would need — a case that was never stored cannot be
replayed, so `replay` moved to v0.2 whole. **DESIGN §12's L0 was wrong as written**: "the
state directory must equal the pre or post snapshot" fails the *corrected* toy, whose
atomic write leaves `key.json.tmp` behind in every world killed inside the window; the
text now matches the implementation (per file, over files present in both snapshots) and
names what the narrower form does not catch. **Two version strings had already drifted**
(`0.1.0` in the manifest, `0.1.0-dev` printed) — a tag would have disagreed with the
binary it tagged; a test now embeds the manifest and holds them together. **And the README
showed a command that does not exist** — the report ended in a mocked
`sideeye replay 000042`; replaced with real output, and the `check.sh` beside it was
executed before being pasted.

**The defect was found while generating that README example, not by review.** A checker
that rejects the operation's normal output produced `FAIL 6 of 6 crash worlds violated an
invariant` — but one of those six is the baseline world, which was never killed. Nothing
that fails there is a consequence of crashing, and attributing it to a crash is the exact
misattribution this tool exists to refuse. It is now `UNKNOWN baseline_violates_invariant`,
paired in acceptance with a control: the same checker, correctly configured, must still
find the planted bug at crash point 5, so the gate cannot be satisfied by swallowing every
L2 finding.

The same-class scan (claims a document makes that the implementation does not support)
walked the CHANGELOG's feature list and found the third structural detector,
`contract_version_mismatch`, had no test and had never been seen firing — the precise
thing PRD says a gate must not be. Unit test with control added, confirmed by making the
decoder ignore the version field.

Tagged `v0.1.0`, released as "v0.1.0 — Deterministic crash points, and a refusal to
guess", and verified from the outside: fresh clone of the tag, build, 45/45 tests, the
buggy toy found at crash point 5 of 5, text and JSON agreeing. The project image landed
separately (640×640, metadata stripped) after declining both social-preview variants.
Two claims measured for the release but *not* asserted by the suite are recorded as such:
ten runs produced an identical crash point and window (the suite compares three), and two
recording runs' traces were byte-identical at 1129 bytes (the suite does not compare
traces at all).

## 2026-08-10 — Second review: the fix that was never run, and the scan that stopped one function short

A second review of the fix branch found fifteen more defects. Three of them are worth
recording because of *how* they survived, not what they were.

**The `reproduce` line still did not reproduce.** The previous entry says it was fixed
and verified by running it. It was neither. The line had been missing
`SIDEEYE_STATE_DIR`; adding that left `SIDEEYE_TRACE_PATH` missing, and the shim returns
from `init()` before arming itself when it has nowhere to write — so the printed command
runs to completion, changes nothing, and looks like an ordinary successful run. The
"verification" was done in a shell that still had those variables exported from an
earlier experiment. **An environment that has been used for experiments is not a place
to check whether a command carries its own environment.** Both the acceptance suite and
the macOS CI job now execute the printed line with `env -i`.

That mistake repeated inside this session. A local check of the same line reported
failure, and the cause was the check: it rebuilt the state in a *different* directory
from the one the report names in `SIDEEYE_STATE_DIR`, so every operation fell outside
what the shim watches. Two probes in a row measured a path that did not reach the thing
under test.

**The same-class scan stopped at the two functions the finding named.** `restore` and
`deleteTree` were fixed for silently ignoring failed writes. `corruptState`, twenty lines
away in the same file, does the same thing for the same reason and was not looked at —
and its failure mode is worse than the others: an uncorrupted state is one the checker is
*right* to accept, so the run reports `checker_not_falsified`, blaming the caller's
checker for the engine's own failed write. A scan driven by the finding's file list is
not a scan of the class.

**Two variables that had to agree, disagreeing.** The text report read a local
`checker_note`; the JSON read a global copied from it on the success path only. An
UNKNOWN therefore printed `unknown_reason: checker_not_falsified` beside
`checker: none configured` — the report contradicting itself about whether a checker
existed. Fixed by deleting one of each pair rather than by copying at the two sites where
it showed.

**A limit fixed in the wrong direction.** The previous round turned a silent truncation
at 256 directory entries into a hard error. That removed the silence and introduced a
worse limit: any state directory with more than 256 entries became unexplorable, reported
as a setup error that named nothing. Deleting in passes removes the bound entirely. A
directory of 301 entries is now in the acceptance suite, because the suite's own state
directories hold one file and would never have noticed.

**The check found a third defect in the same line.** Running the printed command in CI —
the step added by this round — failed on macOS with exit 0 and an untouched state
directory. Not a flaw in the check: `/tmp` is a symlink to `/private/tmp`, the engine
resolves `--state` and the shim filters on the resolved spelling, and a target told the
unresolved one passes *that* to `unlink` and `rename`. Only descriptor-based operations
matched, so no crash point 5 existed to die before. Exploration never showed it because
the engine hands the target the resolved path through the environment; the reproduce line
cannot, because there the target finds its state its own way. The shim now accepts either
spelling and records one, and Linux grows an explicit symlink to reach the same case.

Half of that new check does not discriminate: the "same crash point" assertion stays
green with the fix reverted, for the same reason the defect hid — the toy is handed the
resolved path. Labelled as a baseline rather than left looking like proof.

**And the check killed the suite.** Written with a `set +e` … `set -e` pair around a
command whose failure is expected — a habit from the CI steps, which do start with
`set -eu`. The acceptance suite does not; it runs under `set -u` alone. So the
"restoring" `set -e` switched errexit *on* from that line, and the very next check runs
the buggy toy, where sideeye correctly exits 1. The script ended there. What it printed
was its last *passing* line, followed by nothing, with exit status 1 — indistinguishable
at a glance from an ordinary failing run, and the missing summary was the only clue.

Six increasingly desperate theories went by before measuring: environment leakage (no),
a broken stdout (no), the shim loaded into the shell (no). `strace -f -e trace=%process`
answered it in one run — the shell reaped sideeye's expected exit 1 and immediately called
`exit_group(1)`. The suite now carries an EXIT trap that says so when it stops without
reaching a verdict, confirmed by injecting an early exit.

The shim also gained its first unit tests. It had none, which is backwards for the half
that runs inside somebody else's process, and every defect found in it so far produced a
plausible value rather than an error. Both new tests were confirmed by mutation.

Two smaller notes. The review recommended replacing the hand-written JSON escaper with
`std.json.Stringify.encodeJsonString`; that was checked against the pinned standard
library and is wrong — its default options pass bytes ≥ 0x80 through unchanged, the same
defect, and `escape_unicode` decodes them with `catch unreachable`, so invalid UTF-8 is a
panic instead of a bad document. And the new gate for a non-executable oracle appeared not
to fire inside the container: the same 0644 file on a real filesystem is refused, but
`access(X_OK)` over the Docker bind mount answers permissively. The gate is right; the
mount reports something the filesystem does not.

## 2026-08-10 — Review after merge: four ways to reach PASS, and the report the caller reads

A code review run against the merged branch found fifteen defects. Four of them reached
PASS, which is the failure this project is built to prevent, so they are worth naming.

**The recording run's exit status was discarded.** An operation that failed immediately —
bad argument, missing input, EACCES — still wrote its `shim_ready` marker, recorded no
operations, changed nothing, and every structural detector stayed quiet. The run reported
`PASS  the operation performed no state-directory operations`, exit 0. A partial failure
was worse: five operations become two, and the exploration is confidently complete over a
sequence the target never finishes. `--setup`'s exit code was checked; the operation's,
which the entire trace depends on, was thrown away.

**The state directory was resolved before it existed.** `realpath` failed and the code
fell back to the argument as written. On macOS `/tmp` is a symlink to `/private/tmp`, so
the engine filtered on one spelling while the shim — asking the descriptor via
`F_GETPATH` — saw the other. Every operation fell outside the state directory. The oracle
could not save it, because it was handed the same wrong string and also found nothing:
two views agreeing on nothing is indistinguishable from two views agreeing.

**`deleteTree` stopped silently at 256 entries.** `restore` then wrote the snapshot over
whatever remained and returned success, so every world after the first started
contaminated. An L2 checker would report a violation at crash point k that was residue
from k-1.

**The oracle reported agreement over zero examined lines.** `acceptance.sh` asserts by
hand that more than ten lines were scanned; the tool shipped without the check its own
suite considered necessary.

Also fixed: `AT_REMOVEDIR` was the Linux constant on both platforms, so macOS recorded
`.unlink` where Linux recorded `.rmdir` — the parity claim in the README, the CHANGELOG
and the CI job name was false for any target removing a directory, while the two lines
of context around it *were* platform-branched. And the oracle mapped `unlinkat` to
`.unlink` by name alone, which disagrees with the shim on aarch64 Linux, where glibc
implements `rmdir(3)` as `unlinkat(AT_REMOVEDIR)`: a correct target would have been
reported UNKNOWN.

### The two acceptance conditions that were never checked

PRD's v0.1 acceptance asks for every verdict path to be falsified once — "a gate whose
failure paths were never seen firing is not a gate". UNKNOWN had seven detectors behind
it. **SETUP ERROR had none**, and neither did the new recording-run check. Both now do,
and the second went from red to green when the fix landed, which is the only way to know
a check pins anything.

### JSON report

DESIGN §13 asks for both forms carrying identical content. The acceptance check reads the
fields a caller would branch on and compares them against the text report, rather than
inspecting the document by eye — a report that looks right and does not parse is worse
than no report. UNKNOWN reaches it too, which took wiring, because that verdict exits from
deep inside the run rather than at the end, and it is the one a CI caller is most likely
to be branching on.

Written by hand rather than generated from a type: the schema is explicitly experimental
until v1.0, and generating it would imply a stability this release does not offer.

## 2026-08-10 — CI, green on both platforms, first run

```
linux: success    37/37 tests, ALL ACCEPTANCE CHECKS PASSED
macos: success    37/37 tests, crash point 5 of 5, explored 6 worlds
```

The Linux job runs on **x86_64**, and everything before this had been arm64 — Docker on
an Apple Silicon host, and the host itself. So this is the first evidence that the
verdict holds across architectures as well as across operating systems. The libc symbol
variants that differ between architectures were the specific risk the plan named there.

Two decisions in the workflow are worth keeping:

**Parity is asserted, not described.** The macOS job greps for `crash point 5 of 5` and
`explored 6 worlds`. A sentence in the README claiming parity would have said the same
thing while `fcntl` was quietly making macOS count three operations instead of five;
the numbers would have caught it.

**macOS asserts FAIL, not PASS.** There is no oracle on that platform, so the only claim
it can support is that a real counterexample is found. "No counterexample" needs a
completeness check that SIP makes unavailable, and making PASS the pass condition would
have quietly weakened what green means. The job also checks the report labels the weaker
claim (`NOT VERIFIED`) so that the two kinds of PASS stay distinguishable.

## 2026-08-10 — Same-class scan for the remaining variadic declarations

Three occurrences of one mistake is enough to stop fixing them individually. Every
`extern "c" fn` in the tree, plus every `@extern` in `darwin_libc.zig`, checked against
whether C declares that function variadic.

**23 `extern "c" fn` declarations, 25 `@extern` entries, 48 total. Two are variadic in
C — `open` and `fcntl` — and both are now declared that way. No further instances.**

The ones worth naming as deliberately *not* variadic, since they look similar:
`creat(path, mode)`, `mkdir(path, mode)` and `execvp(file, argv)` are all fixed-arity in
POSIX. (`execl` and friends are the variadic members of that family and are not used
here.) `openat` appears only in the shim, already variadic; the engine never calls it.

A count is recorded rather than "none found", because a scan that examined nothing
produces the same sentence.

## 2026-08-10 — Parity: both operating systems land on the same crash point

`fcntl` was the third instance of the same mistake. Declared with a fixed third
argument, `F_GETPATH` never received its buffer on arm64, so every fd-based operation —
`write`, `fsync`, `close` — failed to resolve a path and was dropped. That is why macOS
counted three operations where Linux counted five, and nothing anywhere reported an
error.

With it declared variadic:

```
                         Linux            macOS
FAIL                     1 of 6           1 of 6
earliest crash point     5 of 5           5 of 5
                         after  unlink(state/key.json)
                         before rename(state/key.json.tmp)
explored                 6 worlds (5 + 1 baseline)
```

**Two entirely different interposition mechanisms — `LD_PRELOAD` with `dlsym` on one
side, a `__DATA,__interpose` table on the other — landed on the same logical crash
point.** That is what acceptance check 3 was written to demand, and it is not something
reusing one implementation could produce.

### The same mistake, three times

`open` in the shim, `open` in the engine, `fcntl` in the shim. Each fixed one changed
the symptom rather than removing it, which is what kept sending the investigation
somewhere new:

| declaration fixed | symptom before | symptom after |
|---|---|---|
| shim `open` | files created mode 0 | files created mode 0251 |
| engine `open` | snapshot fails, looks like shim | works; N=3 against Linux's 5 |
| shim `fcntl` | fd-based ops silently absent | N=5, parity |

Fixed-arity declarations of variadic C functions are correct on Linux and wrong on
arm64 macOS, and wrong in the specific way that produces plausible values rather than
errors. Any remaining one in this codebase is a latent version of this bug; the three
here were found by symptom, not by search. **That search is worth doing once,
deliberately.**

## 2026-08-10 — macOS finds the bug. The defect was in the engine all along.

Inverting the approach found it in one step. Instrumenting the shim showed `mode` read
as `0x1a4` and forwarded as `0x1a4`, and the file landing `-rw-r--r--`. **The shim was
correct.** What was wrong was `src/posix.zig`: the engine's own `open` declaration was
fixed-arity, so every file `restore()` wrote lost its mode — and since the engine then
could not read back what it had just written, the symptom appeared during a snapshot and
looked like the shim's doing.

Five rounds were spent examining the component that was not at fault, because the first
symptom appeared under injection and "macOS interposition is the new thing here" was too
easy an assumption. The engine runs without the shim; it was never a suspect. Calling a
variadic function correctly needs no `@cVaStart` — only receiving does — so the fix is
one declaration and a few literal casts.

macOS now produces the finding:

```
FAIL  1 of 4 crash worlds violated an invariant
invariant   built-in atomicity (L0)
earliest    crash point 3 of 3
            after  unlink(.../state/key.json)
            before rename(.../state/key.json.tmp)
explored    4 worlds (crash points 3 + 1 baseline)
```

Same bug, same logical crash point, second platform.

**But N is 3 here and 5 on Linux.** The shim is not seeing `write` and `fsync` on
Darwin — most likely the `$NOCANCEL` symbol variants, which are their own entry points.
So detection works while observation is incomplete, which is precisely the situation the
completeness rule was written for: this run is only allowed to report FAIL, and it did.
A PASS would have required `--allow-unverified`, and would have carried the label.

Fixing the missing variants is the next macOS task. Linux is unaffected: 37 tests and
the acceptance suite green.

## 2026-08-10 — Where the macOS investigation stands

Four candidate explanations tested against a probe that is walked step by step toward
the shim. Each addition kept `mode` at 0o644 and the file at `-rw-r--r--`:

| added to the probe | result |
|---|---|
| nothing (one interposer, immediate forward) | correct |
| a call between reading and forwarding (`getcwd`, as `note1` does) | correct |
| forwarding through an inline wrapper | correct |
| interposing `openat` alongside `open` | correct — and `openat` never fired, so macOS's `open` does not route through it |

So the defect is not in variadic passing, not in doing work between the two calls, not
in the wrapper, and not in `open`/`openat` interacting. What is left is the remaining
distance between a two-symbol probe and a twenty-five-symbol shim.

**The approach should invert here.** Building the probe up has cost four rounds and
removed four hypotheses without arriving. Taking the shim apart — instrument it directly,
print `mode` where it is read and again where it is forwarded, then remove interposers
until the corruption stops — starts from the artefact that actually misbehaves. The
probe has served its purpose: it established that every mechanism the shim relies on is
sound in isolation, which is why the answer must be in the composition.

Linux is unaffected by all of this and stays green throughout.

## 2026-08-10 — Narrowing: the work done between the two calls is not the problem either

Second step of walking the probe toward the shim. The shim does something between
reading `mode` and forwarding it — `note1`, which resolves the path and therefore calls
`getcwd`. Adding exactly that to the probe:

```
flags=0x00000601
 recv=0x000001a4        still 0o644
                        file lands -rw-r--r--
```

So a call sitting between `@cVaArg` and the forward does not disturb the argument. Two
differences remain between the probe and the shim:

- the shim forwards through an inline wrapper (`common.callOpen`) rather than calling
  the extern directly, and the replacement is reached via a `pub const` alias of a
  function inside a comptime-selected struct;
- the shim installs twenty-five interposers, not one.

Both are testable the same way, one at a time. The pattern of this whole investigation
has been that each measurement removes a plausible explanation, and the plausible ones
are the dangerous ones: promotion and rebinding were both "fixable", and fixing either
would have hidden the defect rather than removed it.

## 2026-08-10 — Variadic passing is not the problem: measured, at last

The probe that earlier panicked before reaching its measurement now runs, because it no
longer depends on a constructor. It reports what the replacement receives:

```
flags=0x00000601      O_WRONLY | O_CREAT | O_TRUNC
 recv=0x000001a4      0o644
```

and the file lands as `-rw-r--r--`.

So variadic passing works. `@cVaStart` and `@cVaArg` read what the caller pushed, and
forwarding through an `@extern` pointer preserves it. Three hypotheses have now been
eliminated in order — dyld rebinding the stored original, argument promotion, and
initialisation order (that one was real and is fixed) — and the remaining defect is
specific to how the shim itself is assembled, not to the platform's calling convention.

That is a much smaller search space than "macOS is different", which is where this
started. The next step is to narrow from the probe toward the shim: the probe replaces
one symbol and calls the original immediately; the shim replaces twenty-five, runs
`note1` in between, and routes through an inline wrapper. Whatever the difference is, it
lives in that gap.

Worth noting how little of this could have been reasoned out. Every step that moved the
investigation forward was a measurement, and two of the three discarded hypotheses were
plausible enough to have been "fixed" — which would have left the real defect in place
under a layer of unnecessary changes.

## 2026-08-10 — The pointer table is gone from the macOS path; one defect remains

The `real` table now exists only where it is needed. It was always a Linux construct —
somewhere to keep what `dlsym(RTLD_NEXT)` returns — and on macOS it introduced a
dependency on initialisation order that the platform does not honour. The replacements
reach the original through `common.call*` wrappers, which go through the table on Linux
and call `darwin_libc.zig` directly on macOS. `bindReal` and the constructor's part in
this are gone.

The wrappers are also what the trace writer uses, so writing a record no longer depends
on the table being populated either.

The failure moved: the run used to die snapshotting the *final* state, and now dies
snapshotting a *crashed* state. The recording run completes, which it never did before.

**Files are still created with mode `--w-r-x---`.** So something remains wrong with how
`mode` crosses the boundary — 0o644 going in, 0o251 landing on disk, and those two share
no obvious relationship (not a shift, not a mask, not umask). It needs the measurement
the last probe never reached: print the value as received inside the replacement, and
again as passed to the original. Guessing at promotions has already cost one wrong
hypothesis.

Linux remains unaffected throughout: 37 tests and the acceptance suite green after every
one of these changes.

## 2026-08-10 — The macOS failure is an initialisation-order problem, not an ABI one

Both hypotheses from the previous entry were wrong, and finding that out took a probe
that separated receiving from forwarding: print the `mode` as received, and compare the
stored "original" pointer against the replacement.

The probe never got that far. It panicked on `real_open.?` — **null** — with a stack
coming from `libxpc.dylib`.

**Interposition takes effect the moment the library is loaded. The constructor that
fills the pointer table runs much later.** Between those two points, system libraries
are already calling `open`, and every one of those calls reached a replacement whose
"original" was still null. `ops.zig` dutifully returned `missing()` — that is, `-1` —
for each of them.

That explains everything that looked like an ABI defect: files created with nonsense
permissions, a state directory the engine could not read, a `mode` that seemed to be
"something, but not what was passed". None of it was about argument passing.

Linux does not show this because `.init_array` runs early enough that the shim is ready
before anything interesting happens. `__DATA,__mod_init_func` does not offer the same
guarantee, and the difference is invisible until a system library gets there first.

### What it means for the design

The `real` table is a Linux construct: it exists because `dlsym(RTLD_NEXT)` has to be
called from somewhere. macOS never needed it — the original is directly callable — and
routing through a stored pointer introduced a dependency on initialisation order that
the platform does not honour.

So on macOS the replacements should call the `extern` declarations directly, with no
table and no constructor in the path. That touches all twenty-six entry points, so it
is the next piece of work rather than a patch squeezed in here.

Worth recording that the earlier standalone probe — the one that proved interposition
works at all — did not catch this. It called `open` directly from the replacement,
which is exactly the shape that turns out to be correct, and so it sailed past the
problem the real shim would hit. A probe that validates a mechanism does not validate
the way the mechanism is used.

## 2026-08-10 — Variadic handling: correct per platform, still not correct enough

`@cVaStart` / `@cVaArg` work in Zig 0.16 — confirmed with a round-trip before touching
the shim — but only on some targets. For `aarch64-linux` the compiler refuses outright:
*"disabled due to miscompilations"*. Which is itself informative: the fixed-arity form
that has been working on Linux is the form Zig trusts there.

So `open` and `openat` now use whichever declaration is correct for the target — variadic
on macOS, fixed on Linux — selected at comptime, with the bodies otherwise identical.
Both build. Linux is unaffected: 37 tests and the full acceptance suite still green.

**macOS still gets `mode` wrong**, differently than before: files now come out `--w-r-x---`
rather than `----------`. Something is being read, and it is not what was passed. Two
candidates, neither confirmed:

- `@cVaArg(&ap, c_uint)` may not match how the argument was promoted, though `mode_t`
  promoting to `int` is what C promises here.
- `common.real.open` holds a function *pointer*, and dyld's interposition rewrites
  pointers in `__DATA`. The original may be getting rebound to the replacement — the
  early standalone probe did not recurse, but it also did not route through a stored
  pointer.

The second explanation would mean the whole `real`-table design needs a different shape
on macOS, so it is worth resolving properly rather than guessing. Recorded here rather
than left as a puzzle for whoever looks next.

## 2026-08-10 — The macOS shim builds, runs, and gets the mode argument wrong

The structure is in place: replacement functions live in one file (`ops.zig`) with
identical bodies on both platforms, and only the installation differs — `linux.zig`
exports the symbols for `LD_PRELOAD`, `macos.zig` lists them in a `__DATA,__interpose`
table and fills `common.real` from `extern` declarations. The constructor section
switches between `.init_array` and `__DATA,__mod_init_func`; `fdPath` switches between
`/proc/self/fd` and `fcntl(F_GETPATH)`; the engine switches between `LD_PRELOAD` and
`DYLD_INSERT_LIBRARIES`. It builds, injects, and the target completes.

Then the engine failed to snapshot the state, and the reason turned out to be the whole
point of testing on the second platform.

**Every file created under the shim had mode `----------`.** Not a crash, not an error
return — the files existed, held the right bytes, and were unreadable. `open` is a
variadic function, and on arm64 macOS variadic arguments are passed **on the stack**,
while the fixed-arity declaration used here passes them **in registers**. So the third
argument was read from a register the caller never wrote, and `mode` came out zero.
Both directions are affected: the target's `mode` never reaches the replacement, and
the replacement's `mode` never reaches the real `open`.

The same code is correct on Linux, where variadic arguments do go in registers. This is
the class of defect that only appears when the second platform arrives, and the reason
the plan put macOS inside v0.1 rather than after it. Discovering it in v0.3 would have
meant discovering it on top of a codebase built around the wrong assumption.

The fix is real variadic handling — `@cVaStart` / `@cVaArg` in the replacements, and
variadic function-pointer types for the originals — which touches every `open`-family
entry point. Left for the next pass rather than rushed. Linux is unaffected: the full
acceptance suite is still green with seven distinct detectors.

Also corrected while here: `O_CREAT`, `O_APPEND` and `O_CLOEXEC` had Linux's values
compiled into the shim unconditionally. On Darwin those constants differ, and the
failure mode would have been a trace file opened with the wrong semantics — records
missing rather than a bad flag reported.

## 2026-08-10 — macOS, measured: interposition works, the oracle does not

Two things the plan said would be decided by running them rather than by reading about
them. Both are now decided.

**`__DATA,__interpose` works from Zig.** A minimal library exporting one replacement for
`open` gets it called, and the control run without injection does not. Two details:
`@intFromPtr` cannot be evaluated at comptime for a function address, so the table holds
`@ptrCast` pointers; and calling `open` from inside the replacement does **not** recurse.
Same-image calls are not interposed, which means macOS needs no `dlsym(RTLD_NEXT)` dance
at all — the original is simply callable.

`fcntl(fd, F_GETPATH, buf)` supplies what `/proc/self/fd` supplies on Linux, including
the same symlink resolution (`/etc/hosts` comes back as `/private/etc/hosts`).

**`dtruss` is not usable.** SIP is enabled and DTrace refuses: *"DTrace requires
additional privileges"*. `sudo dtruss` may work, but a tool that demands sudo to reach
its own correctness check is not a tool anyone will run in CI. The alternatives —
Endpoint Security and friends — need an entitlement a freely distributed binary cannot
carry. The plan predicted this and built the structural detectors so they would not
depend on an oracle; that decision is now load-bearing rather than precautionary.

### The consequence, and the shape of the answer

Requiring an oracle for PASS — the fix from the first review — would mean **macOS never
produces a PASS at all**. FAIL would still work, so the tool would report bugs and never
report their absence. That is not a usable half.

Branching on the platform was the obvious repair and the wrong one: the whole point of
acceptance check 3 is that the same scenario yields the same verdict on both operating
systems, and a rule that only applies to one of them destroys the comparison.

`--allow-unverified` instead. The caller states the weaker claim deliberately, and the
report carries it:

```
oracle: NOT VERIFIED (--allow-unverified) — nothing checked what the shim reported
```

Two PASSes are now distinguishable by reading them, which is the property that matters.
FAIL is untouched by the flag — a counterexample sitting in front of you does not become
less real because the account of the run was incomplete — and that is asserted rather
than assumed.

Still to build: the macOS shim itself. The mechanism is proven; what remains is the
symbol table and the `F_GETPATH` path resolution.

## 2026-08-10 — L2: the checker, and the requirement that it be shown to work

The domain checker runs after each crash, in a fresh process, and its exit code is the
verdict. On the buggy toy the report now reads:

```
invariant   built-in atomicity, and the checker
earliest    crash point 5 of 5
            after  unlink(/tmp/l2/state/key.json)
            before rename(/tmp/l2/state/key.json.tmp)
checker     falsified before the run (corrupted state -> check failed)
```

with `doctor says 'healthy' but the key is unloadable` on stderr. That is DESIGN §13's
worked example arriving on its own — the diagnostic contradicting reality, in the world
where the key is briefly absent. Both invariants fail in the same world, which is what
they should do when they are describing the same bug from different angles.

**Falsification runs first, and refuses to proceed without it** (DESIGN §14-13). A
checker that cannot tell a corrupted state from a healthy one will call every world
fine, and a PASS built on that is a statement about nothing. `/bin/true` as a checker
is the purest case and is now an acceptance check: it must produce UNKNOWN.

The way the state gets corrupted for that probe took a correction. Emptying the
directory is the obvious method and it is wrong here: `check.sh` compares a diagnostic
against reality, and an empty state is perfectly *consistent* — the diagnostic says
unhealthy, nothing loads, they agree. The probe overwrites each file's contents instead,
keeping the structure. Breaking the agreement is the point, not removing the subject.

**Configuration is `--check <cmd>`, not `sideeye.toml`.** The plan called for the file;
Zig has no toml parser and hand-writing one does not advance the spike. What L2 actually
has to demonstrate — a fresh process after restart, an exit code as the verdict, and the
falsification gate — is fully exercised through the flag. The three-commands-and-a-
directory contract of DESIGN §12 is a v0.2 concern.

Seven distinct detectors now fire across the acceptance suite.

## 2026-08-10 — First outside review: three ways to reach PASS while blind

An adversarial review of the whole branch found six real defects, three of them capable
of producing PASS on a target that had not been fully observed. That is the specific
failure this project exists to avoid, so they are worth recording individually.

**PASS was reachable without any completeness check.** `--oracle` was optional and its
absence only produced a line in the report. The reviewer pointed out the case the toys
did not cover: a target that performs *one* ordinary libc operation and then bypasses
libc for the rest. Something was mutated, so `state_changed_without_ops` stays quiet;
the trace is short but not empty, so nothing looks wrong. Every toy so far was either
entirely visible or entirely invisible, and the gap between those was invisible too.
`spike/toys/toy_mixed.c` now occupies it. PASS requires an oracle; FAIL does not,
because a counterexample is real whether or not the account of it was complete.

**The oracle could not see a raw `clone`.** It was invoked with
`-e trace=%file,%desc` and no `-f`, so process creation was outside its view — the same
blind spot the shim documents for itself. A child touching the state directory while
the parent performs ordinary operations passed everything. Now `-f` and `%process`,
with the check placed *before* the state-directory filter, since the child's work never
mentions the directory in the parent's account.

**`restore()` could delete outside the state directory.** It asked `isDirPath`, which
calls `opendir` and therefore follows symlinks; a link inside the state directory
pointing anywhere else would have had its target's contents deleted, once per explored
world. `assertSafeRoot` never had a chance — it only inspects the root string.
Deletion now decides from `dirent.type`, which has not followed anything yet.

Three smaller ones: a truncated trace was parsed as far as it went and then judged; an
operation whose path could not be resolved was dropped silently (`unresolvable_path`
existed as a value and was never produced); and the acceptance suite ran without an
oracle, so none of the above was pinned.

### Two regressions the fixes introduced, both found by running them

Fixing the oracle's blind spot broke the oracle twice, and neither showed up as an
error — both produced confident wrong answers.

`strace -f -o file` prefixes lines with `13    `, not `[pid 13]`. Only the bracketed
form was handled, so every line failed to yield a syscall name, the oracle's view came
back empty, and it reported that the *shim* had invented operations. And strace's own
`execve` of the target was counted as the target creating a child process, so every run
returned `child_process_detected` — the measuring apparatus flagging the act of
measuring.

Both were caught by running the acceptance suite, not by reading the diff. The first
one is a good illustration of why: the code looked right, the tests for it passed, and
the format it parsed was one that documentation and memory both agree exists.

### Where this leaves the boundary

`spike/acceptance.sh` is green with **six distinct detectors** firing across the
out-of-bounds cases, up from four. Two of them cover the same target from different
sides on purpose: `toy-raw` is caught by the oracle when one is available, and by
`state_changed_without_ops` when it is not. macOS is expected to have no usable oracle,
so the second path has to work alone, and now that is asserted rather than assumed.

## 2026-08-10 — Spike-2: the oracle agrees, and disagrees where it should

The completeness comparison is in. The recording run goes through
`strace -y -e trace=%file,%desc`, its output is normalised to the same `OpClass` the
shim records, and the two class sequences are compared position by position.

On the supported toy:

```
oracle      agreed on 6 operations (61 syscall lines examined, 9 touching the state directory)
```

The scan size is in the report on purpose. "Agreed" over zero examined lines reads
exactly like agreement, and there is no way to tell them apart afterwards.

On `toy-raw` the oracle names what was missed and the run ends UNKNOWN. That target is
already caught by `state_changed_without_ops` without any oracle, so running it *with*
one is how the oracle path itself gets exercised rather than assumed — otherwise the
comparison code would sit there having never fired.

Details worth keeping:

- **strace must not have the shim loaded.** Environment reaches the target through
  strace's `-E`, not through the engine's own `setenv`: `LD_PRELOAD` set on the engine
  side would load the shim into strace, and strace's own file operations would land in
  the trace as if the target had produced them.
- **Read-only syscalls are excluded by name** (`newfstatat`, `read`, `access`, …). They
  cannot be crash points in any meaningful sense, and counting them would make the two
  views disagree for no reason. The exclusion is a fixed list, so a syscall that is
  neither modelled nor listed becomes `unsupported_syscall_observed` — UNKNOWN, not a
  silent skip.
- **The oracle comparison runs before the structural detectors**, because when both can
  catch something the oracle can say *which* operation was missed.
- The oracle's two verdicts got their own reasons (`oracle_missed_operation`,
  `oracle_saw_phantom`) rather than reusing `state_changed_without_ops`. Sharing a name
  would have defeated the acceptance check that requires distinct detectors to fire —
  the check would have passed while proving less.

`spike/acceptance.sh` now covers all of it and is green end to end. What remains for
v0.1: the L2 checker, macOS, the JSON report, and CI.

## 2026-08-10 — The engine judges, and the internal gate is passed

All three v0.1 acceptance checks now run for real, in the container, from
`spike/acceptance.sh`:

```
toy-bug   FAIL  crash point 5 of 5, after unlink(...key.json), before rename(...tmp)
toy-fixed PASS  explored (5) == N (4) + 1
toy-raw / toy-static / fork / thread   all exit 2, four *different* detectors
determinism                            3/3 identical reports
```

The distinctness of the four reasons is the part worth keeping honest about: an
implementation that always answers UNKNOWN passes check 2 on its own, and one that
decides everything from `ldd` gives the same reason four times. Requiring four
different detector names makes both of those visible.

### The engine does not use std.Io

`std.fs` no longer holds `File` or `Dir` in 0.16; spawning a child goes through an
`Io` vtable; `std.process.argsAlloc` is gone. Meanwhile everything the engine needs is
plain POSIX — walk a directory, read a file, fork, exec, wait — and the shim had
already shown that `extern "c"` works fine. So `src/posix.zig` binds libc directly and
the engine sits on that. ADR 0001's retreat condition ("two blocks from standard
library churn moves the engine to Rust") is much less likely to be reached now, because
the churning layer is not in the path.

`std.c.Stat` turned out not to describe Linux's `struct stat` usably here, so entry
kinds come from `dirent.type` instead — same information, no extra syscall, defined
identically on both target platforms, with `opendir` as the fallback for filesystems
that report DT_UNKNOWN.

### A real bug, caught by the tool's own detector

The engine first ran the target through `/bin/sh -c`. Every single run came back
`child_process_detected` — correctly, because the shell *forks* to start the program
and LD_PRELOAD applies to the shell too. Switching to `sh -c "exec …"` only trades the
fork for an exec, which the same detector catches. The target has to be executed
directly, so the engine now splits the command itself and calls `execvp`.

Two things fell out of that. The boundary detector was proven to fire on a real
occurrence rather than a contrived one. And the limitation is now explicit: arguments
cannot contain spaces until the CLI takes an argv instead of a string.

### Tests that were not running

`zig build test` reported 19 passing while five more tests sat uncollected: Zig
analyses declarations reachable from the root module, and a `test` block inside an
imported file is not reachable that way. Naming each file with tests explicitly in
`build.zig` took it to 26. Nothing was red at any point — the count was the only
signal, which is the whole argument for asserting how much was measured rather than
that the result was green.

### An acceptance check that was wrong in the safe direction

The first version asserted the corrected toy would report "crash points 5 + 1". It
reports 4 + 1, because without the `unlink` it has one fewer operation — the
implementation was right and the check was wrong. Rewritten to compare `explored`
against `N + 1` as a relation, so it stays true whatever the toy does.

Still open from the plan: the strace oracle comparison (Spike-2). The structural
detectors carry the load in the meantime, and `toy-raw` shows they carry it — its
trace is 30 bytes of "nothing happened" while the state directory visibly changed.

## 2026-08-10 — Spike-1: the interposition ground holds (Linux)

The biggest risk retired first, as PRD.md promised. Measured, not argued.

**The shim works.** A recording run of the buggy toy produces this, in order:
`shim_ready`, `open`(seq 1), `write`(2), `fsync`(3), `close`(seq 0), `unlink`(4),
`rename`(5). `close` carries seq 0 because it is recorded but never a crash point, so
N = 5. The delete-before-rename window is visible in the trace as the gap between
seq 4 and seq 5.

**The kill lands where it is asked to.** `SIDEEYE_KILL_AT=k` for k = 1..5 exits 137
(SIGKILL) with a `kill_landed` record present; k = 6 — that is N+1 — runs to completion
with no marker, which is the baseline world. At k = 5 the state directory contains
`key.json.tmp` and no `key.json`: the bug, caught in the act. **10/10 repetitions land
in the identical state.** The corrected toy keeps `key.json` present at every k.

**Two recording runs produce byte-identical traces.** The determinism claim is a byte
comparison, not an impression.

**Out-of-bounds targets are visibly out of bounds**, and each for its own reason:

| target | what the shim sees | what makes it detectable |
|---|---|---|
| `toy-raw` (syscall(2) directly) | 30 bytes: `shim_ready` and nothing else | the state changed while zero operations were recorded |
| `toy-static` | no trace file at all | the shim never loaded, so no marker exists |
| `toy-bug` + fork | a `fork` record | the boundary detector fired |
| `toy-bug` + thread | a `thread` record | ditto |

`toy-raw` is the one that justifies the engine carrying detectors that do not depend on
interposition: its trace is indistinguishable from "this program touched no files".

**Rust's standard library did not route around the supported operation set.** The
plan rated that a high risk — `open64`, `statx`, `openat2` were all plausible. The
stand-in target produced *exactly* the same operation sequence as the C toy:
`open`, `write`, `fsync`, `close`, `unlink`, `rename`. One measurement is not a
guarantee for every Rust program, but the expected divergence did not happen here.

### What the `zig` skill got wrong

The skill was adopted the same day to reduce the risk of generated code targeting old
APIs, and the plan required recording the first discrepancy rather than quietly working
around it. Three showed up, all in the same area:

| skill says | 0.16.0 actually has |
|---|---|
| `std.mem.trimRight` | `std.mem.trimEnd` (`trimLeft` → `trimStart`) |
| `std.fs.File` | `std.Io.File` — `std.fs` has no `File` member |
| `file.writer(&buf)` | `file.writer(io, buf)` — a `std.Io` instance is required |

The skill states that every 0.16.0 stable pattern in it still holds; its I/O section is
0.15-era. Worth knowing before the engine, which cannot avoid that API the way the shim
can.

### A design correction found by building it

DESIGN §12 defines the L0 invariant as: after restart the state directory equals the
pre-operation snapshot or the post-operation result, never a hybrid. Implementing that
literally fails the *corrected* toy — an atomic write leaves `key.json.tmp` behind at
several crash points, so the directory equals neither snapshot.

The invariant that separates the two toys is narrower: **for every path present in both
the pre and post snapshots, the crashed state must contain it, with content equal to one
of the two.** Paths belonging to neither snapshot (temporaries) are ignored. Under that
reading the buggy toy fails at k = 5 (`key.json` missing) and the corrected toy passes
everywhere, which is the distinction the tool exists to draw. DESIGN will be amended.

### Also decided

- **No `anyzig`.** The plan called for it to fetch the pinned compiler, but Homebrew's
  `zig` 0.16.0 — the exact version wanted — was already installed, and `anyzig` conflicts
  with it (both provide a `zig` binary). The declaration in `build.zig.zon` is what other
  environments need; the fetching mechanism is interchangeable.
- The link-type check in `build-toys.sh` first used `file`, which is absent from the
  image; grep matched nothing and every binary was reported as wrongly linked. It failed
  loudly, which is the right direction, but the check now reads the ELF program headers
  (`readelf -l | grep INTERP`) so it does not depend on an optional tool.

## 2026-08-10 — Inception

Design finalized after an adversarial review pass over the first draft. Eight axes were settled; together they define what Sideeye is:

1. **Primary battleground: an automatic gate in the coding loop.** Non-interactive operation, machine-readable output, and the exit-code contract are v0 core requirements — not future polish. The caller is often an agent or CI; the reader is a human.
2. **LLM boundary.** The core (exploration, verdicts, shrinking, replay) is deterministic and LLM-free, permanently. LLMs are allowed at the edges only: proposing invariants on the way in, explaining reports on the way out.
3. **Pure black-box, elevated to principle.** Sideeye sees a binary, a state directory, and the execution's observable behavior. Nothing else. Language-agnostic by construction.
4. **Counterexamples are the whole product.** A PASS is a search record, not a badge, and we will not build a badge culture around it.
5. **Power failure / torn writes: out of v0, named as a long-term candidate.** v0's crash model is process crash — the OS survives, completed writes persist. Every report says so.
6. **v0 runs natively on macOS and Linux.** This was chosen knowingly: it pushes the mechanism toward userspace interposition (macOS forces every language through libSystem, which makes one mechanism cover Rust/Go/Python; the cost is that hardened-runtime macOS binaries and statically linked Linux binaries are declared unsupported rather than silently mishandled).
7. **Public design doc, in English.** This repository is the document.
8. **Define converges on built-in invariants.** L0 = zero-config atomicity judged from state-dir snapshots; L1 = the program's own success message on stdout, held against it; L2 = domain checker scripts. The whole user-facing contract is three commands and one directory.

Practical decisions the same day:

- **Name check:** crates.io free, GitHub free of significant collisions (max 3 stars). PyPI and npm are taken by unrelated projects (an eye-tracking library and an actively updated package, respectively). Shipped as `sideeye` anyway — distribution will be a single binary, so those registries matter little.
- **License:** dual MIT OR Apache-2.0.
- **Biggest known risk:** the interposition spike — kill a toy binary deterministically at the k-th file operation, on both OSes. It is deliberately the first milestone task in PRD.md; if it fails, better to learn that in week one.
