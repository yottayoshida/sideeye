## What happened

`stack config set install-ghc false --global` was interrupted between two of its own file operations. This is crash point 116 of 116 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `config.yaml` | file, 255 bytes | file, 256 bytes | file, 0 bytes | yes | no | no |
| `pantry` | absent | directory | directory | no | — | yes |
| `pantry/pantry.sqlite3` | absent | file, 131072 bytes | file, 131072 bytes | no | — | yes |
| `pantry/pantry.sqlite3.pantry-write-lock` | absent | file, 0 bytes | file, 0 bytes | no | — | yes |
| `stack.sqlite3` | absent | file, 53248 bytes | file, 53248 bytes | no | — | yes |
| `stack.sqlite3.pantry-write-lock` | absent | file, 0 bytes | file, 0 bytes | no | — | yes |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  truncate
        /s/aux/home/.stack/config.yaml
<-- the process was terminated here -->
before: write
        /s/aux/home/.stack/config.yaml
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — config.yaml: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/stack/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/stack/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 4 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/aux/home/.stack`.
