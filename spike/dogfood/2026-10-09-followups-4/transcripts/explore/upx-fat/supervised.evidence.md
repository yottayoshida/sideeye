## What happened

`upx -q /s/upx/prog` was interrupted between two of its own file operations. This is crash point 34 of 34 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `prog` | file, 1412096 bytes | file, 564416 bytes | absent | yes | no | no |
| `prog.upx` | absent | absent | file, 564416 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  unlink
        /s/upx/prog
<-- the process was terminated here -->
before: rename
        /s/upx/prog.upx
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — prog: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/upx-fat/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/upx-fat/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/upx`.
