# 0085 — A selection gate answers with an exit code, and counts what the engine decides on

Status: Accepted (2026-09-21)

## Context

`spike/dogfood/README.md` has said since 2026-09-05 that a dogfood run measures linkage and
threads **before** writing its candidate table, a rule bought by spending four target slots
on four walls in one afternoon.

On 2026-09-21 the release-path run followed it and still lost its only slot. The probe ran.
Its output was read as far as `ELF 64-bit LSB executable`; `statically linked` sits further
along the same line. The run reached `attempted` and `UNKNOWN oracle_missed_operation`,
and the funnel row says so.

So the rule was not the gap. The rule was obeyed and the answer was misread, which means
another sentence — *read to the end of the line* — leaves the same road open. The defect is
in the **shape of the answer**, not in the diligence of the reader.

A second thing surfaced while building the replacement. `spike/cohort4/preflight.sh`
already answers one of the three questions with an exit code, and the plan for this work
asserted that it would have returned 1 for lefthook. It had never been run in that
directory (`grep -rn -i preflight` over it: 0 lines), and `preflight-analyse.py:126` has an
`if not kernel: sys.exit(2)` that a badly chosen state root reaches. The assertion was a
reading of the source written in the past tense.

## Decision

**A dogfood candidate enters only through a gate that answers with an exit code, and every
gate must have been seen returning its red.**

Four rules.

1. **0, 1, 2 — and the 2 is kept.** 0 is clear, 1 is red, 2 is *could not measure*.
   `preflight.sh`'s own header says never to read a 2 as a pass; folding it into 1 would
   turn "the apparatus is missing" into "the target is walled", which is exactly the
   mistake this work nearly made about lefthook. `gate.sh` passes every 2 through.

2. **The red leg is the real target, not a convenient stand-in.** The visibility gate's red
   is lefthook 1.13.6 — the binary the previous campaign admitted, pinned to that version
   because upstream is at 2.1.14 and any other build is a different measurement.
   `spike/toys/toy_raw.c` was rejected for this: it is dynamically linked and issues raw
   syscalls, a different wall class, and `preflight.sh --selftest` already commits its red.

3. **A gate counts what the engine decides on, never a proxy.** The thread gate first
   counted clones carrying `CLONE_THREAD` and went red at one. Measured against
   `overcommit --install` it was red on two, both of them the Ruby VM's startup threads,
   neither touching the judged directory — a rule that disqualifies every Ruby, Python and
   Node candidate there is. Since contract v16 the engine judges a threaded run when **one
   thread wrote the judged directory**, and since v18 when a creation or a join orders two
   writers (ADR 0067). The gate counts thread ids that write inside the state root.

4. **The apparatus is self-tested before the target is judged by it.** Build the image,
   make `preflight.sh --selftest` green in it, and only then measure a candidate. Reversed,
   a missing compiler produces the same exit 2 as an unmeasurable target and the retreat
   is attributed to the wrong thing.

The instrument itself is not modified. `preflight.sh` is used as it stands, because cohort
4's sealed records cite it and changing it would change what those records mean; the two
questions it does not exit-code are wrapped, not patched.

## Alternatives considered

**Add "read the probe output to the end" to `spike/dogfood/README.md`.** The cheapest fix
and the one the failure invites. Rejected: the README already carried the stronger form of
that instruction and it was followed. A rule that depends on a human reading a line
carefully fails the same way the next time, and this repository's own note on the subject
(`feedback_prefer_impossible_over_detected`) says to prefer the shape that cannot be
misread over the check that notices.

**Use the engine's own `preflight` subcommand as the gate.** It answers more, and it costs
a written define per candidate — including for the candidates the gate exists to turn away
before a define is spent. Rejected on that asymmetry.

**Let the threads gate red at any thread creation and accept the false reds.** Simpler to
implement and to explain. Rejected: it is not conservative, it is *wrong* — it turns away
targets the engine judges, and it would have turned away this campaign's own slate.

## Consequences

- The dogfood ordering rule in `spike/dogfood/README.md` now carries the exit-code
  requirement and the two conditions, with this ADR as its reason.
- A gate's red leg is a committed transcript, not a claim. `gate.sh --selftest` runs six
  legs — three reds, three greens — and a wrapper that always answered one value fails
  three of them.
- **The gate does not decide everything the engine does.** Two writing threads is a red
  here and not a refusal: whether a creation or a join orders them is v18's question, which
  needs a real run. The gate says admission depends on something it cannot check.
- `preflight.sh`'s exit-1 reading names the wall *"the cargo class (#217)"*, which is
  raw-syscalls-past-libc. For a statically linked target the shim never loads at all — the
  same wall by a different road — so that line is wrong for lefthook and is left alone.
  Recorded here rather than fixed, because the instrument is cited by sealed records.
- **Sunset**: delete this ADR's rules if a run ever produces a candidate the gate cleared
  and the engine then refused. `spike/dogfood/README.md` already names that as the
  condition for deleting the ordering rule itself, and the two should go together — it
  would mean the gate is not measuring what it claims.
