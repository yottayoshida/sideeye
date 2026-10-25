## What happened

`diesel migration run` was interrupted between two of its own file operations. This is crash point 52 of 52 that Sideeye explored; it is the earliest one the declared checker rejected, which is not necessarily the earliest one that differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `app.db` | file, 32768 bytes | file, 61440 bytes | file, 61440 bytes | yes | no | no |
| `src/schema.rs` | file, 160 bytes | file, 198 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/app/src/schema.rs
<-- the process was terminated here -->
before: write
        /s/app/src/schema.rs
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — src/schema.rs: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(diesel): src/schema.rs (0 bytes) is neither the file before the migration nor the one after

## Reproducing it

```
sideeye replay /out/diesel/work-explore/cases/000002.json --oracle /usr/bin/strace
```

Saved case: `/out/diesel/work-explore/cases/000002.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/app`.
