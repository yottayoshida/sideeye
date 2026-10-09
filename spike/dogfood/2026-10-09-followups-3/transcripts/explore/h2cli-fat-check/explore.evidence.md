## What happened

`h2cli -u /s/h2/kit` was interrupted between two of its own file operations. This is crash point 8 of 8 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `drumkit.xml` | file, 698 bytes | file, 2816 bytes | file, 0 bytes | yes | yes (at `drumkit.xml.2026-10-01_00-00-00.bak`) | yes |
| `drumkit.xml.2026-10-01_00-00-00.bak` | absent | file, 698 bytes | file, 698 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/h2/kit/drumkit.xml
<-- the process was terminated here -->
before: write
        /s/h2/kit/drumkit.xml
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> drumkit.xml does not parse: no element found: line 1, column 0

## Reproducing it

```
sideeye replay /out/h2cli-fat-check/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/h2cli-fat-check/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 1 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/h2/kit`.
