## What happened

`meson setup --reconfigure /s/meson/state /s/meson/aux/ms/src` was interrupted between two of its own file operations. This is crash point 68 of 109 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `compile_commands.json` | file, 299 bytes | file, 299 bytes | file, 0 bytes | yes | no | no |
| `meson-logs/meson-log.txt` | file, 7536 bytes | file, 3042 bytes | file, 3042 bytes | yes | no | yes |
| `meson-private/build.dat` | file, 29956 bytes | file, 30072 bytes | file, 29956 bytes | yes | no | yes |
| `meson-private/coredata.dat` | file, 42254 bytes | file, 42250 bytes | file, 42250 bytes | yes | yes (at `meson-private/coredata.dat.prev`) | yes |
| `meson-private/coredata.dat.prev` | absent | file, 42254 bytes | file, 42254 bytes | no | — | yes |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/meson/state/compile_commands.json
<-- the process was terminated here -->
before: write
        /s/meson/state/compile_commands.json
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — compile_commands.json: holding neither the old nor the new content

## Checker

The define's own checker accepted the state in this world.

Its output could not be read back, so what it said is unknown.

## Reproducing it

```
sideeye replay /out/meson/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/meson/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 2 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/meson/state`.
