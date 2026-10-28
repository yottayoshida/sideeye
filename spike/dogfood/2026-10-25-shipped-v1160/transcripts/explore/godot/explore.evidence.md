## What happened

`/opt/bin/godot --headless --path /s/godot --convert-3to4` was interrupted between two of its own file operations. This is crash point 7 of 19 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `.godot` | absent | directory | directory | no | — | yes |
| `.godot/.gdignore` | absent | file, 1 bytes | file, 1 bytes | no | — | yes |
| `.godot/editor` | absent | directory | directory | no | — | yes |
| `.godot/imported` | absent | directory | directory | no | — | yes |
| `default_env.tres` | file, 163 bytes | file, 153 bytes | file, 163 bytes | yes | no | no |
| `project.godot` | file, 521 bytes | file, 609 bytes | file, 0 bytes | yes | no | no |
| `scenes/Crate.tscn` | file, 287 bytes | file, 295 bytes | file, 287 bytes | yes | no | no |
| `scenes/Main.tscn` | file, 526 bytes | file, 535 bytes | file, 526 bytes | yes | no | no |
| `scripts/Crate.gd` | file, 172 bytes | file, 185 bytes | file, 172 bytes | yes | no | no |
| `scripts/Player.gd` | file, 395 bytes | file, 441 bytes | file, 395 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/godot/project.godot
<-- the process was terminated here -->
before: write
        /s/godot/project.godot
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — project.godot: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(godot): 0 of 7 files converted, 1 torn or missing

## Reproducing it

```
sideeye replay /out/godot/work-explore/cases/000001.json --oracle /usr/bin/strace --recovery '/opt/bin/godot --headless --path /s/godot --convert-3to4' --recovery-check '/s/godot-check-recovered.sh'
```

Saved case: `/out/godot/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

**Fail** — the tool's own recovery ran against this crash state and ended, and the declared recovery checker rejected what it left.

## What this measurement did and did not establish

- The define declared 1 scratch path(s); the built-in invariants judge none of them, in any world.
- The recovery ran against a crash state rebuilt from its snapshot: the names, kinds, contents and permission bits the crash left (a directory with its owner's bits added; not set-id or sticky bits), but restore-time timestamps and the engine's own ownership, so a recovery that decides by modification time saw every file as newly written.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/godot`.
