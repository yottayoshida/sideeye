## What happened

`cabal user-config update -a jobs: 4` was interrupted between two of its own file operations. This is crash point 2 of 3 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `config` | file, 5658 bytes | file, 5620 bytes | absent | yes | yes (at `config.backup`) | no |
| `config.backup` | absent | file, 5658 bytes | file, 5658 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/aux/home/.config/cabal/config
<-- the process was terminated here -->
before: mkdir
        /s/aux/home/.config/cabal
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — config: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/cabal/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/cabal/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/aux/home/.config/cabal`.
