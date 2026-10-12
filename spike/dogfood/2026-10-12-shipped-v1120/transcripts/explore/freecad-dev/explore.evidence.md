## What happened

`/opt/freecad-dev/usr/bin/freecadcmd /s/fcaux/edit.py` was interrupted between two of its own file operations. This is crash point 18 of 26 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `.home/.cache/FreeCAD/v26-3/Cache/FreeCAD_Doc_4465f7d0-8f17-4352-bcc3-932d9865d57d_279dd5_6598482683178941696` | absent | absent | directory | no | — | yes |
| `.home/.config/FreeCAD/v26-3/system.cfg` | file, 1100 bytes | file, 1099 bytes | file, 1100 bytes | yes | no | yes |
| `.home/.config/FreeCAD/v26-3/user.cfg` | file, 1146 bytes | file, 1183 bytes | file, 1146 bytes | yes | no | yes |
| `part.20260101-000000.FCBak` | absent | file, 4923 bytes | file, 4923 bytes | no | — | no |
| `part.FCStd` | file, 4923 bytes | file, 4921 bytes | absent | yes | yes (at `part.20260101-000000.FCBak`) | no |
| `part.FCStd.629cc415-a2bd-4fde-a62c-a0e5b2cade92` | absent | absent | file, 4921 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/fc/part.FCStd
<-- the process was terminated here -->
before: rename
        /s/fc/part.FCStd.f0e90b0c-f18d-4efd-9a7a-c5ad0bbc1050
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — part.FCStd: present before and after the operation, but gone from the crashed state

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> <Exception> File '/s/fc/part.FCStd' does not exist!

## Reproducing it

```
sideeye replay /out/freecad-dev/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.12.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/freecad-dev/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 2 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.12.0 (trace contract v19) against `/s/fc`.
