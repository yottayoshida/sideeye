## What happened

`infracost configure set api_key ico-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` was interrupted between two of its own file operations. This is crash point 4 of 4 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `.state.json` | absent | file, 106 bytes | file, 106 bytes | no | — | yes |
| `credentials.yml` | file, 116 bytes | file, 116 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/aux/home/.config/infracost/credentials.yml
<-- the process was terminated here -->
before: write
        /s/aux/home/.config/infracost/credentials.yml
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — credentials.yml: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/infracost/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/infracost/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 1 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/aux/home/.config/infracost`.
