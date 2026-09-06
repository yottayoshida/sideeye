# 0051 — An operation that is not an executable image gets its own step

Status: Accepted (2026-09-06)

## Context

`no_shim_marker` is raised at two sites, and the recording run's is the one that chooses its
`next_step` from an observation rather than from the call site (ADR 0040); `preflight
--twice`'s second observed run keeps the shim step whatever the image says, because the
first run's marker has already answered every image question about that file. At the
recording run, four arms shared `check_shim` on the reasoning
that an image which could not be read or resolved says nothing about linkage, so the shim
stays the honest thing to look at. One of the four does not fit that reasoning.

`.unrecognised` means the file **was** read (`src/image.zig`: "Read, and neither ELF nor
Mach-O"). What it says is not "nothing about linkage" but "there is no linkage question
here". Writing `operation` as a `#!` script — the first thing to try, since the README's
own worked example writes `check` that way and presents all three commands as one triple —
lands here, and the operator is sent to check `--shim` and their environment, where they
find nothing wrong because nothing is (#481). Nowhere on the define surface does it say
that `operation` is different in kind from the other two (#482).

Measured on this platform, with a control: `/bin/sh` carries a code directory naming a
platform (identifier 16), and `DYLD_INSERT_LIBRARIES` does not reach it — a non-platform
binary handed the same variable is terminated by dyld instead of ignoring it. On Linux the
kernel hands the script to its interpreter and `LD_PRELOAD` rides along, so the refusal
never fires there; `spike/acceptance.sh` check 16 runs a script operation through to a
judged world and depends on that.

## Decision

**`.unrecognised` takes a step of its own, `operation_not_an_image`, and the define
surface says why.**

- The sentence names the define and does not diagnose: *"What was read at operation is not
  something the loader inserts a library into. Point operation at an executable image; a
  `#!` script hands execution to its interpreter, which is what the insertion would have to
  reach."* The first clause is the observation. The second is a conditional statement of
  mechanism — it does not claim this file **is** a script, because the engine never
  resolved or read the interpreter (`src/image.zig`: "What the interpreter of a script
  would have been is a separate question and a separate issue"). `noShimDetail`'s doc
  comment forbids naming a cause that was not measured; this stays inside that rule.
- `README.md` says it in the two places a reader meets the define — beside `operation` in
  the toml block, and in the flag line — that `operation` is the one command the shim is
  inserted into, so it has to name an executable image, while `setup` and `check` may be
  scripts. `spike/acceptance.sh` check 2ns holds both, each by its own grep.
- `noShimNext` is split into `noShimNextFor(observed)`, taking its observation as an
  argument, so every arm is pinned in a unit test without a recording behind it.

## Alternatives considered

- **`class_wall`.** Its sentence is *"This target does something Sideeye refuses by
  design"* and sends the reader to the README's "What the target has to be". The limit is
  on how the define spells one command, not on what the target under test is, and #482
  records that readers map "the target" to the tool being tested. Placing this there would
  also require adding the limit to that section — which is false on Linux, where a script
  operation runs to a judged world.
- **`fix_define`.** The right action, the wrong sentence: *"the detail above names the
  declaration this run contradicted"*. Nothing was contradicted. Kept as the fallback if
  fifteen members is judged one too many.
- **Refusing when the define is read, as a SETUP ERROR** (#482's second suggestion).
  `DESIGN.md` §13 defines SETUP ERROR as a problem "as opposed to something it observed
  about the target", and says a refusal that **is** about the target "however unhelpfully,
  is UNKNOWN (2)". This is an observation about the target.
- **Refusing before the recording run, under a new `unknown_reason`.** The closed set is
  frozen (`docs/contract-freeze.md` surface 2) and gaining a member is a breaking change.
  The observation point (`image.observe`, after `setup`) is already the earliest one that
  does not break a define whose setup builds the operation. The current refusal costs
  nothing anyway: `explored: 0`, no worlds run.
- **Splitting the arm by platform.** There is no material to split on: the engine reads the
  file `operation` names and never the interpreter. `src/main.zig` carries the note that
  "the old macOS clause named a cause it had not measured" — deciding by position rather
  than observation is what ADR 0040 moved away from.

## Consequences

- `NextStep` has fifteen members. Nothing frozen moves: what reaches the JSON is the
  rendered sentence, and the frozen closed set is `unknown_reason`, which is unchanged.
  ADR 0040's count and its "otherwise" clause are amended in place.
- The sentence names no flag, so the #274 test (every step's named flag appears in the help
  text) has nothing to check for it.
- The step is exercised as a run on the macOS CI job, two-sided: the sentence this
  observation chooses must be present, and the wall and the shim must be absent. The Linux
  acceptance suite cannot host it — there, the refusal does not happen.
- `.not_resolved` keeps `check_shim` and keeps its known weakness with it
  (`docs/target-classes.md`'s chezmoi/gopass row: the refusal names static linkage only
  when the operation's first word is a path). That arm is a separate question; the pin
  added here says so in a comment rather than pretending the answer is settled.
