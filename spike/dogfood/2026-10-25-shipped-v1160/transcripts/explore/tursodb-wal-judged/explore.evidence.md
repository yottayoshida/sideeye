## What happened

`tursodb -q -v syscall shop.db UPDATE orders SET status = 'shipped', cents = cents + 1 WHERE id % 2 = 0` was interrupted between two of its own file operations. This is crash point 6 of 14 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `shop.db` | file, 24576 bytes | file, 28672 bytes | file, 24576 bytes | yes | no | no |
| `shop.db-wal` | file, 0 bytes | file, 0 bytes | file, 32 bytes | yes | unknown | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  write
        /s/turso/shop.db-wal
<-- the process was terminated here -->
before: fsync
        /s/turso/shop.db-wal
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — shop.db-wal: holding neither the old nor the new content

## Checker

The define's own checker accepted the state in this world.

It printed nothing: no line of its output held any text.

## Reproducing it

```
sideeye replay /out/tursodb/work-explore/cases/000001.json --oracle /usr/bin/strace
```

Saved case: `/out/tursodb/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/turso`.
