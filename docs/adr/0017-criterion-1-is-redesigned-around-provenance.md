# ADR 0017 — Criterion 1 is redesigned around provenance, not blindness

- **Status:** Accepted (2026-08-15 — the PR introducing this ADR is its implementing
  PR, so the status is set at birth rather than left as a flip debt; ADRs 0012/0015/
  0016 accumulated exactly that debt and are settled in the same commit)
- **Supersedes:** the venue-and-provenance gate of v1.0 entry criterion 1 (PRD) and
  the matching sentence of DESIGN §17. ADR 0012's two-seal protocol, the campaign
  records, and the assisted/blind labeling rules are all unchanged — this decides
  what the v1.0 gate MEASURES, not how either funnel runs.
- **Scope:** PRD (v1.0 entry criterion 1 and its status trail) and DESIGN §17's
  primary-criterion sentence — ADR 0012 names both as the criterion's home, and the
  2026-08-13 precedent changed both in step. No code.

## The decision

v1.0 entry criterion 1 required the qualifying bug to be found on one of three
venues: omamori, the calibration target, or a blind-protocol target. It now requires:

> A real, novel, author-confirmed crash-consistency bug, **discovered by Sideeye's
> deterministic judge from an invariant declared and committed before this project
> observed any failure of the target in execution (reading a report of a failure
> while scouting is not observing one) — with the question's provenance recorded and
> labeled (blind, or assisted with the scout and its sources named)** — fixed, and
> kept as a replayed regression case.

Two things changed, counted honestly: the gate no longer requires the question to
have been posed blind, and the three-venue restriction is gone — any target
qualifies, because the assisted funnel's targets are by design arbitrary ordinary
software. What is unchanged, deliberately: **novel** (a recorded tracker search with
a positive control, as campaign 1 actually scored it), **author-confirmed**,
**fixed**, **replayed regression case**, the rule that an assisted finding is never
presented as blind — and, made explicit rather than implied, **the question must
precede the answer**: the define is committed before this project observes any
failure of the target in execution. A scout READING about failures is not this
project OBSERVING one — scouting stays legal by text, not by charity. Blind
campaigns prove that ordering with machine-checked seals. Assisted runs prove it
more weakly today: the committed define (toml + checker) fixes the question before
the first exploration and the measured windows date it — but the first cohort's
human-readable proposal files were written AFTER exploration on three of five
targets (caught by review via file birth times, recorded in RESULTS.md), and no
verify-seals equivalent exists for the assisted funnel. Machine-checking the
define-precedes-report ordering for assisted runs is open work; until it exists,
an assisted claim against this criterion leans on file history and review rather
than on a seal. *(2026-08-15, #130: the machine check now exists —
`spike/assisted/verify-assisted.sh`, anchored on first-parent order of main with
in-target rename/copy tracking; the claim rule it enforces is PROTOCOL.md's
"Claiming criterion 1" section. Run against the first cohort it reports what this
paragraph already admitted: all five targets red, define and first artifact in
the same merge — a record, not a certification.)*

("§18-class" throughout means a decision of the weight §18 governs — stopping or
redesigning the current direction. No §18 kill criterion has triggered; PRD entry
criterion 3 is untouched.)

## What this does to past scorings

A criterion change re-scores everything previously scored against it, so the record
is settled here rather than left to drift:

- **timewarrior** stays exactly where §17 put it: "discovered automatically —
  partial." Under the new text it does not slip through the assisted door, because
  the ordering requirement blocks it: the human scout observed the failure in a
  strace first and wrote the checker afterwards (DESIGN §17's own account). The
  question did not precede the answer, and no relabeling changes that.
- **topydo** stays where the 2026-08-14 ruling put it: found-by-Sideeye blind, not
  novel; the recovery misfire is analysis, not discovery. Nothing in this redesign
  revisits either half.
- **The four assisted findings** (stow, devtodo, buku, calcurse) gain nothing but
  eligibility: their questions preceded their answers (committed defines, measured
  windows), their provenance is labeled assisted, and every remaining leg — novelty
  first — is open. *(2026-08-15, later the same day: the novelty searches ran,
  four-for-four not previously reported; buku's finding was then withdrawn as a
  contract-level claim — its remaining leg was a misread of the falsification
  gate's output, and buku recovers in every crash world
  (`spike/assisted/buku/RUNLOG.md`, Correction). Three assisted findings carry a
  live claim.)*

## Why this is a redesign and not a moved goalpost

Steelmanned, the accusation reads: "two blind campaigns returned null, so you
widened the gate." The defence is the recorded order of events, stated precisely:

1. **The sealed candidate pool was run to exhaustion first.** Campaign 1 (topydo)
   found 12/13 counterexamples under machine-verified seals — and the find was not
   novel. Campaigns 2 and 3 (abook, khal) returned null under the same seals. The
   remaining sealed candidate (hledger) is unselectable while its sweep refusal
   stands. What is spent is the pool those seals inherited: ADR 0012 permits a
   fourth campaign under fresh seals over a fresh pool, and declining to run one is
   a resourcing judgement, made with eyes open — campaign 3, the one campaign
   measured end to end, took about 1.5 hours of wall clock including seals, reviews
   and exploration (#118 records the measurement and its scope).
2. **The redesign path was pre-committed after the nulls were known and before any
   assisted evidence existed.** #118 was filed 2026-08-14 13:32 UTC — citing the
   nulls as its motivation, openly — and its 13:36 UTC revision added the rule, in
   substance: an assisted success is never scored as satisfying criterion 1; the
   only path it opens is an explicit entry-criteria redesign in PRD, decided
   deliberately. The first assisted run began 13:54 UTC. Seventeen minutes is a thin
   margin, and it is the true one; the commitment preceded every byte of assisted
   evidence, and the edit history that shows this is public.
3. **The experiment then measured where the constraint actually was.** Its scoring
   (#120) recorded an inversion: question quality 5/5 — the vacuous-question failure
   mode the metadata gate was built against never appeared — while the binding
   constraint on reaching any verdict was the judge's reach. The three measured
   syscall gaps closed the next day (#121, #122); the fourth gap, exec image
   replacement (#123), was deliberately deferred, and only pass still stands behind
   it. The same committed defines then reached verified, replay-confirmed
   counterexamples on stow, devtodo and buku, and re-recorded calcurse's — which was
   verified before the gaps closed and is the control showing the funnel, not the
   gap-closing, produced the question (`spike/assisted/REMEASURE.md`). *(buku's
   counterexample later resolved to an engine-level byte observation inside
   sqlite's recovery contract and was withdrawn as a finding on 2026-08-15; the
   verified/replay-confirmed statement here is engine-level and stands.)*

What this evidence does NOT do is falsify the value of blind provenance, and this
ADR does not claim it does. topydo reached verified counterexamples blind and still
failed criterion 1 on novelty; the assisted four stand today at exactly that same
station, novelty unchecked. What the evidence measured is narrower, and sufficient
to justify dropping the provenance gate: the binding constraint on reaching a
verdict is the judge's reach, not the question's provenance. Provenance was a proxy
for the property that actually matters — that the question preceded the answer —
and the new text gates on that property directly instead of through the proxy,
while the legs that actually carry the value claim (novel, confirmed, fixed,
replayed) never depended on provenance at all. The product's own thesis line, in
#118 from filing: *"AI may propose the question. Sideeye answers whether the
proposed question survives hostile execution."* The gate now measures the product
that sentence describes, and blind remains the stronger provenance a finding can
carry — nothing assisted may borrow it.

## The cost, stated

A future reader can still say "you widened the gate after nulls" — and the dates
agree with them up to a point: the nulls were known when the redesign path was
written down. What the record then shows is the discipline around that fact: the
commitment preceded the assisted evidence; the widening's precedent (2026-08-13,
before any campaign ran, changing PRD and DESIGN in step) is the same rule applied
earlier; the legs that carry honesty were left untouched; and the one scoring the
new text could have quietly improved (timewarrior's) is explicitly held where it
was. The remaining exposure is real and accepted: this is the second widening of
the same criterion in three days, and a third would be evidence about the process,
not the products.
