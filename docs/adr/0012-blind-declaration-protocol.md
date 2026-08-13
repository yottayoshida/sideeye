# ADR 0012 — The blind declaration protocol: two seals, and everything decided before it is observed

- **Status:** Proposed (flips to Accepted when the Seal A pull request merges)
- **Supersedes:** nothing. Implements the declaration boundary that issue #83
  (and its 2026-08-13 amendment) defines for DESIGN §17's first condition
- **Scope:** procedure only — `spike/blind-hunt/`, PRD/DESIGN wording. No
  product code

## Context

DESIGN §17's primary criterion begins with "Sideeye discovered it
automatically", and the honest score on the timewarrior finding is *partial*:
a human read the target's plain strace, confirmed the bug by hand, and then
wrote the checker. The hypothesis encoded the answer; what Sideeye automated
was the search. Closing this gap needs at least one real finding whose
invariant was declared **before anyone knew of the specific bug** — and
"before" has to be checkable, not asserted.

Two review rounds shaped this protocol, each killing a simpler design:

1. The first draft swept candidates with `sideeye preflight` and then picked
   the most promising. But preflight's output — operation counts, atomicity
   classification, refusal reasons — correlates with how breakable a target
   looks. A human choosing *after* seeing it is choosing informed, the same
   direction of leak as reading traces, only milder.
2. The second draft sealed the *information sources* before declaring. The
   reviewer's counter: source rules alone do not stop the declarer from
   running the tool, observing outcomes, and then selecting — from the same
   permitted sources — exactly the invariants that fit what was observed.
   Declaration content must be sealed **after** setup knowledge exists but
   **before** the first crash measurement.

Hence two seals.

## Decision

### Seal A — the procedure, fixed before the target is ever executed

Seal A is a pull request merged to main while no candidate has been installed
or run. It fixes, in one commit:

1. **The candidate list and its priority order** (chosen from web-hosted
   documentation only; nothing may be appended later).
2. **The selection predicate, deterministic and discretion-free**: sweep
   *every* candidate with `sideeye preflight --oracle`, record all results in
   one manifest, then take — in priority order — the **first exactly-one**
   candidate for which (a) preflight, run with the oracle, exits 0, and
   (b) every command the define references — the target binary, the setup's
   and operation's first words, and the shim — resolves to an absolute path
   *in the environment the sweep runs in*, which is the pinned container, so
   resolution there is containment in the image by construction. Observed
   operation counts and classifications are *not* inputs to selection.
   (The resolution leg is the structural proxy for "a saved case will replay
   in this image without external builds" — the thing itself is only testable
   once a case exists, and is therefore an acceptance condition on the
   outcome, not a selection input. A second target after Seal B — for any
   reason, including a null result — is a new campaign with new seals; the
   only within-campaign reselection is the pre-Seal-B burned list below.)
3. **The reference rules** (below).
4. **The falsification-wrapper template** — the generic shape that adapts a
   target whose query commands tolerate junk (the todoman precedent: exit 0
   over a corrupted store) into a rejecting checker. The concrete wrapper is
   fixed at Seal B; touching it after Seal B marks that checker *sighted*.
5. **The reviewer covenant and its breach handling** (below).
6. **The criterion wording** in PRD/DESIGN this campaign will be scored
   against (changed *now*, before any result exists — widening a criterion
   after a find would be moving the goalposts).
7. **The sweep harness and the seal verifier** — committed at Seal A so their
   verdict logic cannot be adjusted after results exist. The harness prints
   **exit codes only**; full preflight reports go unread into a sealed local
   artifact whose SHA-256 lands in the manifest.

### Between the seals — install, read the contract, sweep

The candidates are pinned into the container image. The experimenter may now
consult the target's user-facing contract: README, man pages, `--help`,
observed *normal* (non-crash) behavior — plus, per issue #83's amendment, the
minimum operational facts needed to configure the run (state directory
location, setup and build commands), **which may come from the source only
when the docs do not say**, each such consultation logged in the ledger with
the file and the fact taken. Concrete sweep invocations are assembled from
these sources (they cannot exist at Seal A — `--help` requires an installed
tool), and then **committed before the sweep runs**: the sweep manifest embeds
the SHA-256 of the invocations file it actually read, and the verifier
requires it to match the committed `invocations.tsv`. The sweep runs **once**.
If an invocation turns out to be broken (a misspelled flag, a wrong path), the
fix and the re-run are both recorded — the superseded manifest stays committed
beside the new one and the ledger says why — because an unrecorded
tune-and-re-sweep loop is selection steered by exit codes, which is the leak
this stage exists to close.

**Not allowed before Seal B, and never for the declarer:** traces of the
target (strace or otherwise), write-ordering inspection, deliberate crash
experiments, reading source to locate windows, or the target's bug tracker
and known-issue reports. Reading state-file bytes is out too, with one
exception: where the file format itself is normative public documentation
(the todo.txt class), checks against that format may be declared with a
`source: doc` citation of the spec — there, the file *is* the documented
contract. The default remains: invariants speak through the target's own
query interfaces.

### Seal B — the declaration, fixed before the first crash measurement

A second pull request, merged before any exploration of the selected target,
fixing:

- the invariants, each line carrying its provenance — `source: doc <cite>` or
  `source: observed-normal <transcript>` (the two are not the same strength
  and are never conflated);
- the operation inventory, taken from `--help`, with exclusions justified
  only from the fixed vocabulary `interactive` / `network` /
  `destructive-by-design` / `not-stateful`;
- the concrete checkers, the wrapper instantiation, and the `sideeye.toml`.

Exploration then runs **from the Seal B commit, in a clean working tree**;
every run manifest records `git rev-parse HEAD`, and the verifier requires it
to equal Seal B.

### Breach handling

If a reviewer names target internals, observed failure behavior, or known
bug reports during either PR — or the experimenter consults a forbidden
source — that target leaves the blind set. There is no cure: blind is once
per target. What happens next depends on when the burn lands:

- **Before Seal B**: the burned name is appended to a committed
  `burned.txt`, the ledger records what leaked, and selection re-runs over
  the sealed priority order with the burned names skipped — the selector
  takes the burned list as an explicit input, so the exclusion is machine-
  checkable, not a judgment call. No measurement has happened yet, so the
  campaign itself survives.
- **After Seal B**: the campaign ends. A burned *selected* target cannot be
  swapped mid-flight — the declaration was written for it — so the next
  attempt is a new campaign with new seals, and this one's ledger entry is
  its result.

### What this protocol honestly cannot prove

- **Ordering is auditable, not proven.** The seals are public pushes; a
  reader who trusts the push history can verify the sequence. Nothing
  prevents an author from measuring locally first and constructing the
  commits afterwards. §17 will carry the claim at exactly this strength.
- **The sealed sweep reports are discipline, plus a late-detection hash.**
  The harness shows exit codes only and the full reports go unread into a
  hashed artifact — but a local file can be opened, and nothing proves it
  was not. What the committed hash provides is narrower: while the reports
  are retained, a later substitution is detectable (the verifier's R2 leg
  recomputes them when the reports are supplied).
- **The experimenter is a language model.** Its training data may contain
  public information about these targets, including bug reports. No protocol
  un-knows that. What the seals make auditable is the *recorded*
  consultations and the commit order; the ledger itself is self-reported,
  and an unrecorded consultation is exactly what it cannot detect. The
  residual is stated in §17 rather than hidden.

## Alternatives considered

- **One seal** (procedure and declaration together): cannot hold — concrete
  invocations and invariants need `--help` and normal-run output, which need
  installation; and "checkers are written after the seal" contradicts
  "exploration runs at the seal's HEAD" unless there are two commits.
- **Signed tags / CI-held artifacts as the seal:** equal evidentiary strength
  to a public push timestamp, more machinery. Rejected.
- **Random target sampling:** the population definition smuggles the same
  choice back in ("file-backed stateful CLIs" is already a class pick).
  Choosing openly and saying so is more honest than laundering the choice
  through a sampling frame. The candidates are therefore named **high-risk
  blind targets** — multi-file, cross-file state chosen on purpose — and this
  campaign does not claim to be the §18 *average-target calibration*, which
  timewarrior already satisfied (2026-08-12).
- **Re-running timewarrior on another surface:** the target's traces are
  already in this project's head; "born informed" cannot be washed out.
- **A synthetic target:** §18 exists precisely to forbid shooting at a target
  built to fall.

## Consequences

- §17's first condition becomes measurable: the finding (if any) carries a
  machine-verifiable declaration order instead of an assertion of innocence.
- A null result is not waste: the sweep's refusal ledger feeds the UNKNOWN
  rate measurement (#84) and the target-class page (#79), and a no-find
  campaign is §18 data recorded at full strength.
- The campaign is slower than a naive hunt — two PRs and a sweep before any
  exploration — and that cost is the point: the speed of the naive hunt was
  exactly the freedom this protocol removes.
