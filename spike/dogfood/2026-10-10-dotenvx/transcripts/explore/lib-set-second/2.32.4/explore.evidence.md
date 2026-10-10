## What happened

`node -e require('@dotenvx/dotenvx').set('PROD_DB_PASSWORD', 'prod-value-two-not-real', { path: '/s/dx/.env.production', envKeysFile: '/s/dx/.env.keys' })` was interrupted between two of its own file operations. This is crash point 2 of 4 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `.env.keys` | file, 404 bytes | file, 518 bytes | file, 0 bytes | yes | no | yes |
| `.env.production` | file, 27 bytes | file, 582 bytes | file, 27 bytes | yes | no | yes |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/dx/.env.keys
<-- the process was terminated here -->
before: write
        /s/dx/.env.keys
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> .env API_TOKEN_PLACEHOLDER: dotenvx get reads 'encrypted:BKdVSbwdHmeW3iWsE7qZQ7WTyhig4s' (exit 1) ☠ [DECRYPTION_FAILED] could not decrypt DB_PASSWORD, API_TOKEN_PLACEHOLDER. fix: [https:

## Reproducing it

```
sideeye replay /out/lib-set-second/2.32.4/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/lib-set-second/2.32.4/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 3 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/dx`.
