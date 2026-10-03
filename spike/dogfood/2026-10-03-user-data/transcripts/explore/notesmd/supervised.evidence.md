## What happened

`/opt/bin/notesmd-cli move projects/alpha projects/alpha-2026 --vault vault` was interrupted between two of its own file operations. This is crash point 3 of 5 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `vault/daily/2026-10-01.md` | file, 51 bytes | file, 61 bytes | file, 0 bytes | yes | no | no |
| `vault/index.md` | file, 27 bytes | file, 32 bytes | file, 27 bytes | yes | no | no |
| `vault/projects/alpha-2026.md` | absent | file, 24 bytes | file, 24 bytes | no | — | no |
| `vault/projects/alpha.md` | file, 24 bytes | absent | absent | yes | yes (at `vault/projects/alpha-2026.md`) | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/notes/vault/daily/2026-10-01.md
<-- the process was terminated here -->
before: write
        /s/notes/vault/daily/2026-10-01.md
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — vault/daily/2026-10-01.md: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/notesmd/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/notesmd/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.7.0 (trace contract v18) against `/s/notes`.
