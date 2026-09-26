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
- A gate's red leg is a committed transcript, not a claim. `gate.sh --selftest` runs
  **eleven legs — five greens, three reds and three twos**. A wrapper that always answered
  0 fails the six that are not 0; one that always answered 1 fails the eight that are not 1.
  The three twos are there because rule 1 is the one the rest of the design rests on, and a
  gate that could only ever answer 0 or 1 would pass every other leg while breaking it.
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

**Amended 2026-09-22 (the shipped-v160 run, `spike/dogfood/2026-09-22-shipped-v160/`; owner's
ruling).** Visibility and interior are now answered by **the installed engine's own
`sideeye preflight --twice --oracle <strace>`**, and static linkage by `file -L` on the
operation's image; threads stays the gate above, unchanged. Four things move with it.

- *Why the alternative rejected above is taken now.* "It costs a written define per
  candidate" still holds; the run bounds it at twenty candidates, and the logger this gate
  used is the 2026-08-22 one, which does not see what the v1.6.0 shim interposes — a
  `mkstemp`-based atomic replace reads red there (`spike/cohort4/mkstemp-class.txt`) and is
  judged by the engine since contract v13. That is the proxy this ADR's own rule 3 forbids, and a
  preflight is the engine counting what it decides on.
- *preflight's exit is mapped, not passed through* — its 2 is "refused", this gate's 2 is
  "could not measure". The mapping reads the `next` sentence, a fixed string: a refusal
  naming `--observe syscalls` is cleared and followed once in explore (the product's own
  loop); a class wall or an unaccounted boundary is red; "Change the define" is a define
  revision, counted and re-run, never red; the environment and the shim pair are 2. Not
  every row has been seen: the run's `SELECTION.md` lists which were, on what — most on toys,
  the define-revision row on a candidate, the static red on busybox rather than lefthook —
  and the four that were not.
- *Threads is asked from the define's seed.* `gate.sh` reads its reset only in `all`, so a
  caller asking `threads` alone must seed first; the run's first gate did not, measured the
  operation over preflight's already-formatted output, and read "0 writers" on five of seven
  candidates — a green that measured nothing, found in review and re-run. And threads is now
  **stricter than the engine**: it counts writer thread ids without reading their order, so a
  target whose writers are ordered by joins — which preflight accepts and explore judges —
  reads red there (the run's `joinedthreads` toy). Asked only of what preflight accepted, its
  red can only be that disagreement, which is the proxy rule 3 forbids. No candidate met it;
  the next run that uses this gate either drops the question or says what it still catches.
- *The sunset is read by phase.* Preflight runs the recording phases explore does, and prints
  as `not checked` what it cannot run (kill landing, world-side boundaries, baseline, checker
  falsification). The sunset above fires on a refusal in a phase the gate ran — the same
  engine answering twice differently — and not on one the gate says it did not check. The
  shipped-v160 run met neither: its one explore refusal was the gate's own answer repeated.

**Amended 2026-09-26 (the threads-gate run, `spike/dogfood/2026-09-26-threads-gate-virtualenv/`).**
The threads question is dropped: an entry gate asks static linkage and the installed engine's
`preflight --twice --oracle`, and nothing more. It is the answer the 2026-09-22 amendment asked
the next run for, and it follows from where the question sits, not from a measurement.
`entry.sh` asks threads on two paths only. After preflight *accepted*, the engine has already
asked its own thread rule of both recorded runs (`src/main.zig`, `trace.second_writer_thread`
in run A's structural checks and again in run B's; contract 18 at v1.6.0), so a threads red
there can only be this gate disagreeing with the engine — rule 3's proxy. After preflight
answered *FOLLOW* (`--observe syscalls`) the engine's rule has not necessarily run, because
FOLLOW comes from an operation the shim did not number; but what follows FOLLOW is a preflight
or an explore under syscalls, which asks the same rule. On neither path does the question
decide anything the engine does not decide itself.

The run measured the disagreement on the one real target whose writers a join orders:
virtualenv 20.31.2 (Debian's package, the target judged PASS 1382/1382 under v18 on
2026-09-16), through the 2026-09-22 gate unchanged, in the 2026-09-22 box plus Debian's
`python3-virtualenv`. preflight accepted
1381 operations with the account *"2 thread id(s) of the subject's own process wrote the
judged directory; … 2 join(s)"*, and threads counted the same two ids — the main thread and the
pip worker — and answered red. The two contrasts gave their 2026-09-22 answers in the same box.

What it would still catch, and why that is not a reason to keep it: a writer the engine
under-counts. #543's raw `clone` is not one — a thread made that way hides its *creation*, not
its writes, so a second writer through it is refused by the engine at preflight and a single
one is counted as one by both. The other half of #543, a writer going straight to syscalls
that the shim never records, is refused at preflight because an entry gate runs preflight
with `--oracle`, which sees the writes the shim missed; a gate that dropped the oracle would
have to ask again. No other under-count is known.

The copies of `entry.sh` in the 2026-09-22 and 2026-09-26 run directories keep the question,
because sealed records cite them; a run that copies the file forward removes the threads block.
The sunset above is unchanged.
