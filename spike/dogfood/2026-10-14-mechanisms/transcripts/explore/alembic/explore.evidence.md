## What happened

`python3 -m alembic -c /s/al-aux/proj/alembic.ini upgrade head` was interrupted between two of its own file operations. This is crash point 15 of 42 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `app.db` | file, 16384 bytes | file, 20480 bytes | file, 20480 bytes | yes | no | yes |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  unlink
        /s/al/app.db-journal
<-- the process was terminated here -->
before: open
        /s/al/app.db-journal
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> checker(alembic) after recovery: a=ok b=ok c=ok d=FAIL(exit 1: (Background on this error at: https://sqlalche.me/e/20/e3q8))

## Reproducing it

```
sideeye replay /out/alembic/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.12.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/alembic/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 2 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.12.0 (trace contract v19) against `/s/al`.
