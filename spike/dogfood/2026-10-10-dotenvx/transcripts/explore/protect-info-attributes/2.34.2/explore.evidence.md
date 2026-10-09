## What happened

`dotenvx protect` was interrupted between two of its own file operations. This is crash point 2 of 2 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `attributes` | file, 83 bytes | file, 99 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/repo/.git/info/attributes
<-- the process was terminated here -->
before: write
        /s/repo/.git/info/attributes
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — attributes: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> /s/repo/.git/info/attributes: no line 'vendor/** linguist-vendored' (0 bytes)

## Reproducing it

```
sideeye replay /out/protect-info-attributes/2.34.2/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/protect-info-attributes/2.34.2/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/repo/.git/info`.
