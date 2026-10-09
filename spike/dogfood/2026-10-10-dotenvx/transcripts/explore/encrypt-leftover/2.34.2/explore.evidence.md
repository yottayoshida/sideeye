## What happened

`dotenvx encrypt -f /s/repo/.env` was interrupted between two of its own file operations. This is crash point 3 of 10 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `.env` | file, 80 bytes | file, 719 bytes | file, 80 bytes | yes | no | yes |
| `.env.keys` | absent | file, 404 bytes | absent | no | — | yes |
| `.env.keys.1186341028` | absent | absent | file, 404 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  write
        /s/repo/.env.keys.3724148147
<-- the process was terminated here -->
before: fsync
        /s/repo/.env.keys.3724148147
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> git would stage .env.keys.1186341028, which holds a private key

## Reproducing it

```
sideeye replay /out/encrypt-leftover/2.34.2/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/encrypt-leftover/2.34.2/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 3 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/repo`.
