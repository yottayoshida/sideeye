# The checker cookbook

A checker is the declared invariant's sharp end: a command Sideeye runs over each crashed state, exit 0 meaning the invariant holds. It is the layer that found the timewarrior bug, and the layer easiest to get quietly wrong. Everything below is a real committed checker, or a failure pattern with the run that taught it — nothing was invented for this page.

Before any exploration, Sideeye **falsifies** the checker: it corrupts a copy of the state on purpose and requires the checker to go red. A checker that cannot fail anything is refused (`checker_not_falsified`), never trusted. The recipes below are about the subtler failures that gate cannot catch.

## Recipe 1 — cross-examine the tool's own diagnostic

`spike/check.sh`, the acceptance toy's checker (the README quotes it): run the tool's `doctor`, run the operation that depends on the same state, and require the two to **agree** — healthy things must work, unhealthy things must say so. A target is allowed to be broken as long as it says so; the violation is the *mismatch*, a diagnostic answering "healthy" over a store the tool itself cannot read.

## Recipe 2 — the non-destruction form

`spike/loop-closure-timew/define/check.sh`, the checker behind the timewarrior finding: after `timew undo`, the export must have removed *either nothing or exactly the newest interval*. The first draft demanded that undo always remove something — which condemns a correct recovery along with the bug, because a crash may have beaten the intent's commit; `spike/dogfood-timew.sh` carries that rationale beside the checker text. The admission is written down too: this form deliberately allows an undo that always no-ops, so the loop-closure apparatus scores a fix that *lobotomizes* the feature as a failure on a separate gate — declared before the run, not discovered after (`BUILDLOG.md`).

## Recipe 3 — the smallest valid checkers

Two lines is a real checker: `spike/dogfood-watson/check.sh` is `exec watson frames` — the tool's own reader as the whole invariant. And no checker at all is also a valid define: the built-in atomicity form (L0) judges every shared path byte-for-byte on both sides without one. Start there; write a checker when the property you care about is not a byte property.

## Recipe 4 — leg order is part of the contract

`spike/assisted/buku/ops/check.sh` runs its query legs FIRST, deliberately: sqlite's documented contract is recovery-on-next-open, so the bystander query IS the documented next open, and an integrity check placed before it would measure a state the contract never promises. The same file records a dropped leg — asserting the journal file's absence was an undocumented hygiene claim, not the declared property. Order and scope are both part of what you declare.

## Failure patterns, each with the run that taught it

- **Exit-0-on-unreadable.** todoman's `list` prints a traceback and exits 0 — it answers "nothing wrong" precisely when it could not look. The falsification gate refused it: the first real checker rejected as unfalsifiable, as opposed to a synthetic `/bin/true` (`BUILDLOG.md`, the todoman entry). The committed fix is a strict wrapper — exit 0 AND no error text in the output (`spike/dogfood-todoman.sh`).
- **Demanding destruction.** A checker that requires the operation to have visibly happened condemns correct crash recovery along with the bug (recipe 2). Allow the no-op; let a separate gate judge whether a fix gutted the feature.
- **Counting lines when you mean occurrences.** `grep -c` counts lines; devtodo rewrites its whole store onto one XML line, so a duplicated note still counted as 1. `spike/assisted/devtodo/ops/check.sh` counts occurrences instead (`grep -o` piped to a line count) and records the review finding that caught it.
- **Asserting what you did not observe.** The general shape behind all of the above: the claim and the observable truth must agree. Every blind-campaign checker under `spike/blind-hunt/`, `spike/blind-hunt2/` and `spike/blind-hunt3/` ships with a red suite beside it proving each leg can individually fail — the cheapest way to know a checker is load-bearing.
