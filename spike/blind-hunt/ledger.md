# Campaign ledger — every consultation, deviation, and breach, as it happens

Seal A artifact (ADR 0012). Append-only; entries are dated and never rewritten. The
sealed-at-A sections of `candidates.md` record what was consulted *before* the seal;
this file records everything after it.

What belongs here:

- **Source consultations** under issue #83's operational-facts carve-out: the file
  looked at, the single fact taken (state directory location, setup command), and why
  the docs did not answer. Nothing else may be taken from source.
- **Invocation edits**: diffs to `invocations.tsv` after its first commit, with the
  permitted source (`--help`, man page) each change came from.
- **Wrapper edits after Seal B** — these mark the checker *sighted* (ADR 0012 breach
  handling); the entry says so explicitly.
- **Reviewer-covenant breaches**: who named target internals or known issues, in which
  PR, and which target left the blind set because of it.
- **Experimenter deviations**: any forbidden source consulted, even by accident. The
  target leaves the blind set (before Seal B: appended to `burned.txt` and selection
  re-runs over the sealed order; after Seal B: the campaign ends — ADR 0012 breach
  handling).
- **Sweep re-runs**: if an invocation was broken and the sweep ran again, both
  manifests stay committed and the entry says what changed and why — an unrecorded
  tune-and-re-sweep is selection steered by exit codes.

## Entries

(none yet — the campaign has not passed Seal A)
