## What happened

`stripe config --set color off` was interrupted between two of its own file operations. This is crash point 4 of 5 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `config.toml` | file, 260 bytes | file, 251 bytes | file, 0 bytes | yes | no | no |
| `docs` | absent | directory | directory | no | — | no |
| `docs/cache` | absent | directory | directory | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/aux/home/.config/stripe/config.toml
<-- the process was terminated here -->
before: write
        /s/aux/home/.config/stripe/config.toml
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — config.toml: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/stripe/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/stripe/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.8.0 (trace contract v18) against `/s/aux/home/.config/stripe`.
