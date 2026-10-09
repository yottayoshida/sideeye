## What happened

`/opt/bin/dotter deploy -f -y` was interrupted between two of its own file operations. This is crash point 2 of 18 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `cfg/.dotter/cache` | absent | directory | absent | no | — | no |
| `cfg/.dotter/cache.toml` | absent | file, 98 bytes | absent | no | — | no |
| `cfg/.dotter/cache/bashrc` | absent | file, 18 bytes | absent | no | — | no |
| `cfg/.dotter/cache/gitconfig` | absent | file, 18 bytes | absent | no | — | no |
| `home/.bashrc` | file, 42 bytes | file, 18 bytes | absent | yes | no | no |
| `home/.gitconfig` | file, 19 bytes | file, 18 bytes | file, 19 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  unlink
        /s/dotter/home/.bashrc
<-- the process was terminated here -->
before: mkdir
        /s/dotter/home
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — home/.bashrc: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/dotter-incfg/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/dotter-incfg/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/dotter`.
