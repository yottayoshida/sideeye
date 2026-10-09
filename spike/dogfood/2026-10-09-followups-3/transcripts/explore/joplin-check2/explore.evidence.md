## What happened

`joplin --profile /s/joplin/jp mknote SecondNote` was interrupted between two of its own file operations. This is crash point 2 of 48 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `database.sqlite` | file, 421888 bytes | file, 421888 bytes | file, 421888 bytes | yes | no | yes |
| `log.txt` | file, 8410 bytes | file, 9159 bytes | file, 8410 bytes | yes | no | yes |
| `tmp` | directory | directory | absent | yes | unknown | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rmdir
        /s/joplin/jp/tmp
<-- the process was terminated here -->
before: mkdir
        /s/joplin/jp
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — tmp: present before and after the operation, but gone from the crashed state

## Checker

The define's own checker accepted the state in this world.

Its output could not be read back, so what it said is unknown.

## Reproducing it

```
sideeye replay /out/joplin-check2/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/joplin-check2/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 2 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/joplin/jp`.
