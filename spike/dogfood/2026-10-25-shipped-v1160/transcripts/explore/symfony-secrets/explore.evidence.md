## What happened

`php bin/console secrets:generate-keys --rotate --env=prod` was interrupted between two of its own file operations. This is crash point 3 of 24 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `prod.DATABASE_URL.8ea85a.php` | file, 410 bytes | file, 413 bytes | file, 410 bytes | yes | no | no |
| `prod.MAILER_DSN.97e321.php` | file, 364 bytes | file, 364 bytes | file, 364 bytes | yes | no | no |
| `prod.STRIPE_SECRET.df0204.php` | file, 341 bytes | file, 302 bytes | file, 341 bytes | yes | no | no |
| `prod.encrypt.public.php` | file, 180 bytes | file, 180 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  truncate
        /s/sf/config/secrets/prod/prod.encrypt.public.php
<-- the process was terminated here -->
before: write
        /s/sf/config/secrets/prod/prod.encrypt.public.php
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — prod.encrypt.public.php: holding neither the old nor the new content

## Checker

The define's own checker accepted the state in this world.

It printed nothing: no line of its output held any text.

## Reproducing it

```
sideeye replay /out/symfony-secrets/work-explore/cases/000001.json --oracle /usr/bin/strace
```

Saved case: `/out/symfony-secrets/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/sf/config/secrets/prod`.
