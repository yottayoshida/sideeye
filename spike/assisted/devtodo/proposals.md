# devtodo — scout proposals (assisted, #118)

T0: 20260814T141453Z. Sources: `devtodo --help` (pinned 0.1.20), behavior
probes. No external service needed.

## P1 — `--remove <index>` (IMPLEMENTED)

- argv: `devtodo --database <state>/.todo --remove 1` (AdaNote sorts to
  index 1, measured; GraceNote is the bystander)
- **why**: every devtodo write rewrites the XML database; removing one note
  is the rewrite whose interruption could take the others with it.
- **what property**: *removing one note conserves the other* — exactly one
  GraceNote in the XML, the file stays well-formed XML, and the target's
  own listing still shows it.
- **where from**: the help text (`--remove ARG`, `--database ARG`); probes:
  `--remove` writes no new timestamp and is byte-identical over the same
  pre-state even 2 seconds apart.

## P2 — `--done <index>` / `--add` (recorded: refusal-shaped, the worst kind)

- **why excluded**: both stamp epoch seconds into the XML
  (`time=`/`done=`), measured differing across a 2-second gap — baseline
  reproducibility that HOLDS when recording and baseline land in the same
  second and BREAKS otherwise. Per-second flakiness is worse than honest
  nondeterminism: it would pass most runs and refuse unpredictably.

## P3 — `--reparent` (recorded, not implemented)

- tree surgery over the same XML; deferred as a variant of P1's rewrite
  window.
