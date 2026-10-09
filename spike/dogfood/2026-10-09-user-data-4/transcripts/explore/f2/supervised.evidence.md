## What happened

`f2 -f IMG_ -r trip_ -x` was interrupted between two of its own file operations. This is crash point 2 of 3 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `IMG_1.jpg` | file, 72 bytes | absent | absent | yes | yes (at `trip_1.jpg`) | no |
| `IMG_2.jpg` | file, 72 bytes | absent | file, 72 bytes | yes | no | no |
| `IMG_3.jpg` | file, 72 bytes | absent | file, 72 bytes | yes | no | no |
| `trip_1.jpg` | absent | file, 72 bytes | file, 72 bytes | no | — | no |
| `trip_2.jpg` | absent | file, 72 bytes | absent | no | — | no |
| `trip_3.jpg` | absent | file, 72 bytes | absent | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/f2/IMG_1.jpg
<-- the process was terminated here -->
before: rename
        /s/f2/IMG_2.jpg
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> checker(f2): half-renamed: 2 IMG_, 1 trip_

## Reproducing it

```
sideeye replay /out/f2/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/f2/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/f2`.
