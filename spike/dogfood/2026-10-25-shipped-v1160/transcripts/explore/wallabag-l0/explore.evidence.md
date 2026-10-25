## What happened

`php bin/console wallabag:import wallabag /s/wbaux/second.json --importer=v2 --env=prod -n` was interrupted between two of its own file operations. This is crash point 66 of 87 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `wallabag.sqlite` | file, 233472 bytes | file, 241664 bytes | file, 233472 bytes | yes | no | no |
| `wallabag.sqlite-journal` | absent | absent | file, 78488 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  write
        /opt/wallabag/data/db/wallabag.sqlite
<-- the process was terminated here -->
before: write
        /opt/wallabag/data/db/wallabag.sqlite
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — wallabag.sqlite: holding neither the old nor the new content

## Checker

The define's own checker accepted the state in this world.

It printed nothing: no line of its output held any text.

## Reproducing it

```
sideeye replay /out/wallabag/work-explore/cases/000001.json --oracle /usr/bin/strace
```

Saved case: `/out/wallabag/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/opt/wallabag/data/db`.
