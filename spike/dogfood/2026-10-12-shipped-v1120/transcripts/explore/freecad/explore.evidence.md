## What happened

`/opt/freecad/usr/bin/freecadcmd /s/fcaux/edit.py` was interrupted between two of its own file operations. This is crash point 24 of 38 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `.home/.cache/FreeCAD/v1-1/Cache/FreeCAD_Doc_3c6b2a71-8b00-4f9f-91f6-fadca4eebde3_279dd5_660862` | absent | absent | directory | no | — | yes |
| `.home/.config/FreeCAD/v1-1/system.cfg` | file, 1100 bytes | file, 1099 bytes | file, 1100 bytes | yes | no | yes |
| `.home/.config/FreeCAD/v1-1/user.cfg` | file, 1146 bytes | file, 1183 bytes | file, 1146 bytes | yes | no | yes |
| `part.20260101-000000.FCBak` | absent | file, 4921 bytes | file, 4921 bytes | no | — | no |
| `part.FCStd` | file, 4921 bytes | file, 4922 bytes | absent | yes | yes (at `part.20260101-000000.FCBak`) | no |
| `part.FCStd.1df5ea42-c843-45b6-b2ed-a72ad0f82486` | absent | absent | file, 4922 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/fc/part.FCStd
<-- the process was terminated here -->
before: rename
        /s/fc/part.FCStd.433f74c7-d550-49c0-a405-5a5b5f5fcb3f
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
sideeye replay /out/freecad/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.12.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/freecad/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 2 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.12.0 (trace contract v19) against `/s/fc`.
