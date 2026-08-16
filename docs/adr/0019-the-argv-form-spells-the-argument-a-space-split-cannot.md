# 0019. The argv form spells the argument a space-split cannot

Date: 2026-08-16
Status: Accepted
Amends: ADR 0007 (decision 5)

## Context

ADR 0007 decision 5 made command strings split on spaces — no quoting parser, no
escapes — with the rule "anything an argument cannot spell belongs in a script
file". That kept the parser small, but issue #95 names the cost precisely: the
complexity is not removed, it is relocated into shell wrappers the user must
write, version and point the config at, for the one common case of an argument
containing a space.

The #84 sweep then measured the wrapper path failing structurally. Two of the
B-group's twenty machine-selected targets (hnb — a space-carrying argument;
lbdb — a stdin redirect) could only be spelled through `op.sh` wrappers, and a
wrapper that performs nothing state-changing before its `exec` is an image
change the v10 observation rules refuse (`spike/unknown-rate/defines-b/`,
BUILDLOG 2026-08-16). The escape hatch ADR 0007 pointed at is, for exactly the
targets that need it most, a wall.

Two facts stated against the motivation, not hidden under it. First, no met
v1.0 criterion depends on this change: criterion 4 was met with the spelling
UNKNOWNs counted in the denominator, and the threshold held. The reason to do
this is criterion 5's timing alone — the config format freezes at v1.0, and a
second command shape *after* the freeze is a breaking-change debate, while
before it it is an addition. Second, DESIGN §12 carries a standing sentence —
"If Define ever needs more than this, that is movement toward the kill criteria
in §18, and we should notice." This ADR is the noticing, the third on record.

## Decision

An **additive argv form** for the three command keys (`setup`, `operation`,
`check`), alongside the string form, whose semantics do not change by one bit:

```toml
operation = ["mytool", "commit", "-m", "a message with spaces"]
```

1. **The grammar is deliberately narrower than TOML's arrays.** One `[` ... `]`
   on a single line; every element one double-quoted string; elements separated
   by commas; an inline `#` comment allowed after the closing bracket. Refused,
   each with its line: multi-line arrays, unclosed quotes, missing commas,
   trailing commas, empty arrays, empty elements, non-string elements,
   trailing content, and the array form on any non-command key (`state`,
   `marker`, `expected_status`). Elements carry the same byte discipline as
   every value here — no escapes, no control bytes.
2. **The elements are argv, verbatim.** No splitting, no substitution, no
   joining. The string form keeps its split-on-space rule untouched; the two
   spellings meet only at the spawn site, where both become the executor's
   `argv`. Element 0 resolves against the toml's directory under the
   names-a-place rule the string form's argv[0] has always had — minus that
   rule's leading-space skip: the skip mirrors how the space-split executor
   finds argv[0], and the argv form has no split, so an element 0 with a
   leading space is the author's own byte string, passed through untouched
   and failing loudly at exec. The remaining elements are arguments — data,
   never paths to rewrite.
3. **The case format pairs the shape with a version (the ADR 0014 law).** A
   saved case whose define carries an argv-form command is `case_version: 3`; a
   case spelled entirely in strings stays version 2, byte-shaped exactly as
   before. Reading side: v3 accepts both shapes, and a version 1 or 2 file
   carrying an argv-form command is refused as malformed — the shape arrived
   with version 3, and reading it under a guessed contract would replay a
   define no v2-era binary ever produced. The trace contract is untouched: no
   shim or record change, and every existing saved case replays as it did.

## Alternatives considered

- **A quoting parser for the string form** (`operation = "mytool -m 'a b'"`) —
  rejected. This is the exact complexity ADR 0007 refused: quoting rules must
  be documented, remembered and escaped, and the parser's width becomes a
  contract nobody decided. The argv form has no quoting rules at all.
- **Unconditional case_version 3** — rejected. It would flip the acceptance
  pins on every string-form case for no information gained, and break the
  version-shape pairing law's cleanest reading: the version moves when the
  shape does.
- **Full TOML arrays** (multi-line, trailing commas, mixed types) — rejected
  for the same reason ADR 0007 rejected a TOML dependency: every accepted form
  is contract width, and none of the extra width carries an argument.

## Consequences

- **`sideeye preflight` cannot take an argv-form define.** Preflight reads the
  define-surface flags only and refuses `--config` (its own report says
  `sideeye explore --config` answers strictly more), and flags always carry
  the string form. A target whose define needs the argv form goes straight to
  `explore --config` — whose falsification gate and refusal set answer
  everything preflight would have, strictly more. Documented in the README and
  the CI quickstart beside the array form itself.
- The config parser gains one value shape, and a named line-numbered refusal
  for every way of leaving it, pinned by unit tests and the acceptance suite;
  the DESIGN §12 ledger paragraph records this noticing beside the two before
  it.
- `spike/followup-95/` measures the change against the target that motivated
  it: hnb, refused under the wrapper spelling in the #84 sweep, re-posed with
  an argv-form define. lbdb stays out of reach — a stdin redirect is not an
  argument, and no argv shape can carry it.
