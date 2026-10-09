## What happened

`node -e require('/opt/dx-2.34.2/lib/node_modules/@dotenvx/dotenvx/src/lib/helpers/protectSettings.js').removeIgnore()` was interrupted between two of its own file operations. This is crash point 2 of 5 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `config` | file, 93 bytes | file, 41 bytes | file, 93 bytes | yes | no | yes |
| `ignore` | file, 34 bytes | file, 23 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/xdg/git/ignore
<-- the process was terminated here -->
before: write
        /s/xdg/git/ignore
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — ignore: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> /s/xdg/git/ignore: no line '.idea/' (0 bytes)

## Reproducing it

```
sideeye replay /out/protect-remove-ignore/2.34.2/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/protect-remove-ignore/2.34.2/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- No oracle confirmed that Sideeye saw every state-changing operation of this run, so the crash points are what it observed rather than everything that happened.
- The define declared 2 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/xdg/git`.
