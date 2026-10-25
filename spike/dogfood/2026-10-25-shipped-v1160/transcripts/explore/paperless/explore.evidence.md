## What happened

`/opt/paperless-venv/bin/python /opt/paperless-ngx/src/manage.py document_renamer --no-progress-bar` was interrupted between two of its own file operations. This is crash point 11 of 209 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `data/db.sqlite3` | file, 1449984 bytes | file, 1449984 bytes | file, 1449984 bytes | yes | no | yes |
| `media/documents/archive/0000001.pdf` | file, 217 bytes | absent | file, 217 bytes | yes | no | no |
| `media/documents/archive/0000002.pdf` | file, 217 bytes | absent | file, 217 bytes | yes | no | no |
| `media/documents/archive/0000003.pdf` | file, 217 bytes | absent | file, 217 bytes | yes | no | no |
| `media/documents/archive/0000004.pdf` | file, 217 bytes | absent | file, 217 bytes | yes | no | no |
| `media/documents/archive/0000005.pdf` | file, 217 bytes | absent | file, 217 bytes | yes | no | no |
| `media/documents/archive/0000006.pdf` | file, 217 bytes | absent | file, 217 bytes | yes | no | no |
| `media/documents/archive/Bank` | absent | directory | absent | no | — | no |
| `media/documents/archive/Bank/Letter 3.pdf` | absent | file, 217 bytes | absent | no | — | no |
| `media/documents/archive/Bank/Letter 6.pdf` | absent | file, 217 bytes | absent | no | — | no |
| `media/documents/archive/Landlord` | absent | directory | absent | no | — | no |
| `media/documents/archive/Landlord/Letter 2.pdf` | absent | file, 217 bytes | absent | no | — | no |
| `media/documents/archive/Landlord/Letter 5.pdf` | absent | file, 217 bytes | absent | no | — | no |
| `media/documents/archive/Tax Office` | absent | directory | absent | no | — | no |
| `media/documents/archive/Tax Office/Letter 1.pdf` | absent | file, 217 bytes | absent | no | — | no |
| `media/documents/archive/Tax Office/Letter 4.pdf` | absent | file, 217 bytes | absent | no | — | no |
| `media/documents/originals/0000001.pdf` | file, 218 bytes | absent | file, 218 bytes | yes | no | no |
| `media/documents/originals/0000002.pdf` | file, 218 bytes | absent | file, 218 bytes | yes | no | no |
| `media/documents/originals/0000003.pdf` | file, 218 bytes | absent | file, 218 bytes | yes | no | no |
| `media/documents/originals/0000004.pdf` | file, 218 bytes | absent | file, 218 bytes | yes | no | no |
| `media/documents/originals/0000005.pdf` | file, 218 bytes | absent | file, 218 bytes | yes | no | no |
| `media/documents/originals/0000006.pdf` | file, 218 bytes | absent | absent | yes | yes (at `media/documents/originals/Bank/Letter 6.pdf`) | no |
| `media/documents/originals/Bank` | absent | directory | directory | no | — | no |
| `media/documents/originals/Bank/Letter 3.pdf` | absent | file, 218 bytes | absent | no | — | no |
| `media/documents/originals/Bank/Letter 6.pdf` | absent | file, 218 bytes | file, 218 bytes | no | — | no |
| `media/documents/originals/Landlord` | absent | directory | absent | no | — | no |
| `media/documents/originals/Landlord/Letter 2.pdf` | absent | file, 218 bytes | absent | no | — | no |
| `media/documents/originals/Landlord/Letter 5.pdf` | absent | file, 218 bytes | absent | no | — | no |
| `media/documents/originals/Tax Office` | absent | directory | absent | no | — | no |
| `media/documents/originals/Tax Office/Letter 1.pdf` | absent | file, 218 bytes | absent | no | — | no |
| `media/documents/originals/Tax Office/Letter 4.pdf` | absent | file, 218 bytes | absent | no | — | no |
| `media/media.lock` | absent | file, 0 bytes | file, 0 bytes | no | — | yes |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/paperless/media/documents/originals/0000006.pdf
<-- the process was terminated here -->
before: mkdir
        /s/paperless/media/documents/archive/Bank
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(paperless): Found 1 document(s) with errors and 1 global warning(s).

## Reproducing it

```
sideeye replay /out/paperless/work-explore/cases/000001.json --oracle /usr/bin/strace --recovery '/opt/paperless-venv/bin/python /opt/paperless-ngx/src/manage.py document_renamer --no-progress-bar' --recovery-check '/s/paperless-check.sh'
```

Saved case: `/out/paperless/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

**Pass** — the tool's own recovery, run against this crash state, left a state the declared recovery checker accepted. The crash state above is unchanged by this: it is still what the crash left.

## What this measurement did and did not establish

- The define declared 3 scratch path(s); the built-in invariants judge none of them, in any world.
- The recovery ran against a crash state rebuilt from its snapshot: the names, kinds, contents and permission bits the crash left (a directory with its owner's bits added; not set-id or sticky bits), but restore-time timestamps and the engine's own ownership, so a recovery that decides by modification time saw every file as newly written.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/paperless`.
