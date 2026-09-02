# 0040 — A refusal's next step is chosen where the cause is known, and the compiler holds every site to it

Status: Accepted (2026-09-02)

Closes #274. Sibling of ADR 0030 (a refusal reports observations, not causes): this adds
the action beside the observation without letting the two mix. Numbered 0040 because a
parallel branch took 0039 for #357 and said so.

## Context

Refusals helped unevenly. `completeness_not_verified` walked `PATH` and printed a
paste-ready `--oracle /usr/bin/strace`; `unsupported_syscall_observed` printed one
syscall name and nothing else; `no_shim_marker` listed four candidate causes the engine
had not looked at, until #391 replaced the list with what the image actually shows. Each
message was written on its own, and nothing required a refusal to say what the operator
does next — so the unevenness reappeared with every new detector.

The first design for this change was a table: one sentence per `unknown_reason`, held
exhaustive by a `switch`. The design review broke it with a count. The closed set has 34
members and `unknown()` is called from 85 sites; one reason routinely bundles causes
whose remedies differ. `state_unsnapshotable` covers a tree nested deeper than the walk
descends (make the tree shallower), a file that could not be read (fix permissions) and an
entry list the snapshot mis-sorted (Sideeye's defect); `recording_run_failed` covers a
declared status that did not match, a signal death, and a second run diverging from the
first. A sentence keyed on the reason either loses that or lies about it.

## Decision

**The next step is chosen at the site that raises the refusal, where the cause is known,
and `unknown()` takes it as a required argument.**

- `contract.NextStep` is a closed, payload-free enum of **actions** — change the define,
  pass an oracle flag, account for a process boundary with `--oracle`, raise
  `--world-timeout`, this class is refused by design, check `--shim`, rebuild the
  shim/engine pair, re-record the case, fix the environment, re-run once and report if it
  recurs, narrow or flatten `--state`, let the state settle, relaunch from a live parent,
  file it as Sideeye's defect — fourteen at this writing. `render()` is an exhaustive
  `switch` returning a comptime sentence per member.
- `unknown(reason, detail, next)`: the third argument is not optional. Every one of the
  85 sites names a member; a site that does not, does not compile. Where a site's cause is
  decided in a helper — `snapshotOrRefuse`'s `answer`, `rewriteFailureDisposition`'s
  return — the member is decided in that same arm and threaded through, so the helper
  cannot flatten three remedies into one.
- `no_shim_marker` is the one reason whose step is decided from an observation rather
  than a position: `noShimNext()` reads the same image facts `noShimDetail` reports, and
  answers the wall for a static ELF, a Mach-O not linked against dyld, or a code
  directory that names a platform or carries the library-validation or hardened-runtime
  flag; the shim step otherwise.
- The sentence is rendered once in `unknown()` and handed to both forms: the JSON
  `next_step` field (after `message`) and the text report's `next` line (after the
  detail line, which the acceptance suite reads as the line following the reason). The
  MCP summary prints it as a `next:` line after the marked region and before `case` —
  engine text, never target-influenced, so it sits outside the counted region and after
  the prefix #339 fixes.
- `SETUP_ERROR` does not carry a next step. Its `setupError` sites — over a hundred and
  fifty of them — are the define-not-yet-running refusals whose messages already name the
  flag, file or directory to fix; giving them a second field is a separate promise, not
  this one.

## Alternatives considered

- **One static sentence per `unknown_reason`.** Rejected in review, above: the reason is
  the wrong key.
- **A tagged union with a `[]const u8` payload for the flag name, rendered through an
  arena.** Rejected in the second review round. `unknown()` is `noreturn` and the promise
  is "every UNKNOWN carries it"; a sentence assembled at run time can fail to allocate at
  the moment the report is written, and a free-form payload can carry a flag that does
  not exist, or target-chosen bytes, into text the MCP surface prints outside its marked
  region. A closed enum with comptime sentences has neither failure.
- **Append the advice to `message`.** Rejected: ADR 0030 separates what was observed
  from what to do about it, and a consumer that quoted `message` would quote the advice
  with it.
- **A `sideeye diagnose <binary>` subcommand**, the issue's other proposal. Not taken:
  `preflight` is already the pre-define surface, #391 does the linkage reading at refusal
  time, and a third surface would face DESIGN §12's growth test on its own.
- **Fix the one detector the issue named.** Declined by the owner: the next detector
  would reopen the same gap.

## Consequences

- A new optional report field, `next_step`, present on every UNKNOWN; documented in
  `docs/report-schema.md` under surface 2's additive allowance, held to the code by
  `check-report-schema.py`'s two directions, and held to the text report by acceptance
  check 2ns on two refusals with different steps.
- A unit test walks every `NextStep` and checks each `--flag` it names against the help
  text, which moved into a `usage_fmt` constant for the purpose; acceptance checks every
  `docs/*.md` a sentence names against the tree, reading the source table rather than the
  binary's strings.
- Adding a closed-set member, or a new call site, now requires choosing a step; adding a
  step requires writing its sentence. The unevenness the issue described has no place to
  come back through.
- The per-site choices are reviewable in one place: the table the migration printed is in
  BUILDLOG, and disagreements are a one-line change at the site.
