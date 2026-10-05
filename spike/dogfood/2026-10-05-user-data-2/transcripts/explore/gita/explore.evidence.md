## What happened

`gita rename a alpha` was interrupted between two of its own file operations. This is crash point 3 of 6 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `groups.csv` | file, 10 bytes | file, 15 bytes | file, 10 bytes | yes | no | no |
| `repos.csv` | file, 30 bytes | file, 36 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/gita/gita/repos.csv
<-- the process was terminated here -->
before: write
        /s/gita/gita/repos.csv
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — repos.csv: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/gita/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.8.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/gita/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.8.0 (trace contract v18) against `/s/gita/gita`.
