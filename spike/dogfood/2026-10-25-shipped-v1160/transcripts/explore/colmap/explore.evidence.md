## What happened

`/opt/bin/colmap point_filtering --input_path /s/colmap/sparse/0 --output_path /s/colmap/sparse/0 --max_reproj_error 4` was interrupted between two of its own file operations. This is crash point 2 of 10 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `sparse/0/images.bin` | file, 1115 bytes | file, 1115 bytes | file, 1115 bytes | yes | no | no |
| `sparse/0/points3D.bin` | file, 908 bytes | file, 876 bytes | file, 908 bytes | yes | no | no |
| `sparse/0/rigs.bin` | file, 24 bytes | file, 24 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/colmap/sparse/0/rigs.bin
<-- the process was terminated here -->
before: write
        /s/colmap/sparse/0/rigs.bin
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — sparse/0/rigs.bin: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(colmap): the model does not load:

## Reproducing it

```
sideeye replay /out/colmap/work-explore/cases/000001.json --oracle /usr/bin/strace
```

Saved case: `/out/colmap/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/colmap`.
