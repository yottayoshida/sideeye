# 0046 — The root vets are held by their relation, not by their address

Status: Accepted (2026-09-04)

Closes #359. The root denylists (`denied_trees`, `denied_exact`) and the shared shape
checks stay in `src/engine.zig`. What this adds is the relation between the two vets over
them, which nothing stated before: **`assertSafeNamingRoot` refuses a subset of what
`assertSafeRoot` refuses, and the one direction they differ in is the depth rule.**

## Context

Two public entry points read those lists. `assertSafeRoot` guards the one genuinely
destructive thing the engine does — emptying the state directory, once per explored world.
`assertSafeNamingRoot` is `mcp.zig`'s startup vet on `SIDEEYE_MCP_ROOT`, whose immediate
job is naming rather than deleting. ADR 0024 records that naming and destruction were
conflated in the first place, and #359 read that as an argument about **where the predicate
lives**: it sits on the destructive side, so `src/contract.zig` — which already holds
`isInsideDir` and `isStrictlyInsideDir` — would stop the two from borrowing each other's
rules by proximity.

#359 named two conditions that would move it: a decision that the split wants a home
neither module offers, or **evidence that the two predicates have drifted in a way
proximity caused**.

The second condition has fired, and how it fired matters. #329 gave the naming side the
outward read of the lists — refuse a root that is an *ancestor* of a denied entry — and
left the destructive side inward-only with its depth rule, which catches `/private` and
`/var` but not `/private/var`. So the predicate that only names files refused a location
the predicate that empties directories accepted.

**It lasted two hours and forty minutes.** `8eaed2a` (#329) landed at 09:28 and `4655363`
(#358) closed it at 12:08 the same morning, and #358 was *filed* at 09:03 — twenty-five
minutes before the merge that introduced the asymmetry. An earlier draft of this ADR said
"for two weeks", which was not measured and inverted what the episode shows.

What it shows is that review caught it, immediately, because a reviewer was looking at
exactly that pair of predicates. That is an argument for leaving the address alone — the
proximity did not hide anything — and a weaker argument for the test below than the one
this ADR was first written around. The test is still worth its lines, for a smaller reason:
it does not need the right reviewer to be looking at the right pair.

So the trigger fired, and the response taken was not relocation. It was extraction:
`assertRootNotDeniedOrAncestor` now holds the shape checks and both lists read in both
directions, and neither vet can be given a check without the other getting it.

## Decision

**Keep the lists in `engine.zig`, and pin the relation with a corpus test.**

The relation is four assertions over `root_relation_corpus`:

0. The equality itself: the destructive vet accepts exactly what the naming vet accepts
   and is deep enough.
1. Everything the naming vet refuses, the destructive vet refuses.
2. Where only the destructive vet refuses, the reason is the depth rule and nothing else.
3. Every cell of the corpus is populated — some root is accepted by naming and refused by
   destruction, some is accepted by both, some is refused by both.

1 and 2 decompose 0 so that a failure names which direction broke. 3 is what keeps them
from being vacuous: without it, a check added to the naming side alone satisfies 1 by
emptying its antecedent.

Twenty-two of the corpus's thirty-nine roots also appear in the hand-written vet tests,
three more appear only in the denylist definitions themselves, and the remaining fourteen
appear nowhere in the file. Being on a denylist is not being tested; the number that
matters is the twenty-two. Measured 2026-09-04, one mutation at a time:

| mutation | tests that failed |
|---|---|
| outward read on the naming side only (#358 reverted) | `#329`, `#358`, and this one |
| depth rule added to the naming side | `#329` and this one |
| depth rule weakened on the destructive side | `#329` and this one |
| naming side refuses roots containing `~` | **this one alone** |
| depth rule given a carve-out: `/data` accepted despite one component | **this one alone** |

Two contributions, and they come from different halves of the test. The `~` mutation is
caught by the corpus: that byte appears in no other root test. The carve-out is caught by
assertion 0 and by nothing else — assertions 1, 2 and 3 all pass, because a depth-1 root
that the destructive vet now accepts leaves containment intact, has no depth-2 counterpart
to violate the depth bound, and still leaves seven roots in the cell it vacates. No
hand-written test names `/opt`, `/repo`, `/srv`, `/nix`, `/cores`, `/data` or `/scratch`;
`/work` is the only depth-1 root whose destructive refusal is pinned by hand.

An earlier draft of this ADR said assertion 0 had no mutation of its own. It had one; the
mutation that was tried ran the wrong way — refusing `/data` on the destructive side is
dead code, since the depth rule already refuses every depth-1 root, and the carve-out that
*accepts* one is the shape a container mount would arrive as.

## Alternatives considered

**Move the lists to `src/contract.zig`.** Declined. That file opens by calling itself "the
single source of truth for everything the shim and the engine must agree on", and a host
filesystem denylist is not that: neither the shim nor the trace format has any use for it.
`shim/src/common.zig` and `shim/src/ops.zig` import the module, and the shim is loaded into
the target process.

What this ADR does **not** claim is a byte cost. Zig analyses top-level declarations
lazily, so a `const` no shim path references is likely neither analysed nor emitted, and
that was not measured. The reason to decline is what the file is for, not what it would
weigh — an earlier draft of this decision asserted the cost and had it removed in review.

**A third file, `src/rootpolicy.zig`.** Declined, and the reason #359 gives does not apply
to it. The filing says a relocated predicate "needs an error set in `contract.zig` and a
mapping back"; a dedicated file needs neither, because it can define exactly
`error{UnsafeRoot}` and Zig widens that into `RestoreError` at the call site with nothing
written. The reason to decline is different: the drift a separate address protects against
is already prevented by the shared helper, and **the same asymmetry can be written inside
a new file just as easily**. The move buys an address.

**Do nothing but record the decision.** Declined. An ADR that says "we thought about it
and decided not to" leaves the risk the address argument stood for exactly where it was.
The relation was the thing nobody had written down.

## Consequences

- **The lists stay where the danger is.** The sunset note above `denied_trees` still
  governs when they are deleted, and this decision does not touch it.
- **A one-sided check is a test failure, and for two shapes this test is the only thing
  that notices.** The table above is the whole measurement, including the three mutations
  where the new test's marginal contribution is zero. Claiming more than that would repeat
  the "two weeks" error in a different register; claiming less, as an earlier draft did
  about assertion 0, hides a real guard behind a wrong measurement.
- **A legitimate asymmetry is not forbidden — it is made visible.** If a future change
  should refuse something on one side only (a network mount on the destructive side, say),
  the corpus test is edited in the same pull request and the reason is added to this ADR's
  list of permitted differences. The test is a speed bump that has to be argued past, not
  a law. A change that edits the test without saying why is what review is for.
- **The corpus is the place to add a root when the lists change.** Adding an entry to
  `denied_trees` or `denied_exact` should come with a corpus root that exercises it, so the
  relation keeps being checked over the new shape rather than only over the old ones.
- **This does not close the address question forever.** What would reopen it: a third
  consumer of the lists whose job is neither naming nor destruction, or an asymmetry that
  survives review more than once — at which point the shared helper is no longer doing the
  work claimed for it here.
