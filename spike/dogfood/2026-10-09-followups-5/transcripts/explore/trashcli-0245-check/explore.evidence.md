## What happened

`/opt/tc0245/bin/trash-put /s/tc/live/doomed.txt` was interrupted between two of its own file operations. This is crash point 5 of 6 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `data/Trash/files/doomed.txt` | absent | file, 7 bytes | absent | no | — | no |
| `data/Trash/info/doomed.txt.trashinfo` | absent | file, 73 bytes | file, 0 bytes | no | — | no |
| `live/doomed.txt` | file, 7 bytes | absent | file, 7 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/tc/data/Trash/info/doomed.txt.trashinfo
<-- the process was terminated here -->
before: write
        /s/tc/data/Trash/info/doomed.txt.trashinfo
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> trash-list: Parse Error: /s/tc/data/Trash/info/doomed.txt.trashinfo: Unable to parse Path.

## Reproducing it

```
sideeye replay /out/trashcli-0245-check/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/trashcli-0245-check/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/tc`.
