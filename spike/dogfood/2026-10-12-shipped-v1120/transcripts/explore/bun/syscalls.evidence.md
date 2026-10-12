## What happened

`bun add /s/bunaux/dep-1.0.0.tgz` was interrupted between two of its own file operations. This is crash point 10 of 10 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `bun.lock` | absent | file, 378 bytes | file, 378 bytes | no | — | no |
| `node_modules` | absent | directory | directory | no | — | no |
| `node_modules/probe-dep` | absent | directory | directory | no | — | no |
| `node_modules/probe-dep/index.js` | absent | file, 30 bytes | file, 30 bytes | no | — | no |
| `node_modules/probe-dep/package.json` | absent | file, 64 bytes | file, 64 bytes | no | — | no |
| `package.json` | file, 349 bytes | file, 423 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/bun/package.json
<-- the process was terminated here -->
before: write
        /s/bun/package.json
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — package.json: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> checker(bun): package.json does not parse, or lost its scripts - a torn manifest survived the crash

## Reproducing it

```
sideeye replay /out/bun/work-syscalls/cases/000001.json --observe syscalls --shim /opt/se/sideeye-v1.12.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/bun/work-syscalls/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.12.0 (trace contract v19) against `/s/bun`.
