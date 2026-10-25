## What happened

`/opt/bin/luantiserver --world /s/world --migrate-players sqlite3` was interrupted between two of its own file operations. This is crash point 102 of 286 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `players` | directory | absent | directory | yes | unknown | no |
| `players.bak` | absent | directory | directory | no | — | no |
| `players.bak/alice` | absent | file, 510 bytes | file, 510 bytes | no | — | no |
| `players.bak/bob` | absent | file, 510 bytes | absent | no | — | no |
| `players.bak/carol` | absent | file, 512 bytes | absent | no | — | no |
| `players.bak/dave` | absent | file, 514 bytes | absent | no | — | no |
| `players.bak/eve` | absent | file, 514 bytes | absent | no | — | no |
| `players.sqlite` | absent | file, 36864 bytes | file, 36864 bytes | no | — | no |
| `players/alice` | file, 510 bytes | absent | absent | yes | yes (at `players.bak/alice`) | no |
| `players/bob` | file, 510 bytes | absent | file, 510 bytes | yes | no | no |
| `players/carol` | file, 512 bytes | absent | file, 512 bytes | yes | no | no |
| `players/dave` | file, 514 bytes | absent | file, 514 bytes | yes | no | no |
| `players/eve` | file, 514 bytes | absent | file, 514 bytes | yes | no | no |
| `world.mt` | file, 142 bytes | file, 144 bytes | file, 142 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/world/players/alice
<-- the process was terminated here -->
before: open
        /s/world/players.sqlite-journal
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(luanti): world.mt says files; 4 players read; missing ['alice']; wrong []

## Reproducing it

```
sideeye replay /out/luanti/work-explore/cases/000001.json --oracle /usr/bin/strace --recovery '/s/luanti-recover.sh' --recovery-check '/s/luanti-check.sh'
```

Saved case: `/out/luanti/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

**Pass** — the tool's own recovery, run against this crash state, left a state the declared recovery checker accepted. The crash state above is unchanged by this: it is still what the crash left.

## What this measurement did and did not establish

- The recovery ran against a crash state rebuilt from its snapshot: the names, kinds, contents and permission bits the crash left (a directory with its owner's bits added; not set-id or sticky bits), but restore-time timestamps and the engine's own ownership, so a recovery that decides by modification time saw every file as newly written.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/world`.
