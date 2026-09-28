## What happened

`nbqa black nb.ipynb` was interrupted between two of its own file operations. This is crash point 10 of 12 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `nb.ipynb` | file, 260 bytes | file, 349 bytes | file, 0 bytes | yes | no | no |
| `nb149zu126_nbqa_ipynb.py` | absent | absent | file, 74 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/nbqa/proj/nb.ipynb
<-- the process was terminated here -->
before: write
        /s/nbqa/proj/nb.ipynb
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — nb.ipynb: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> nb.ipynb is not JSON: Expecting value: line 1 column 1 (char 0)

## Reproducing it

```
sideeye replay /out/nbqa/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.7.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/nbqa/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- No oracle confirmed that Sideeye saw every state-changing operation of this run, so the crash points are what it observed rather than everything that happened.

Measured by Sideeye 1.7.0 (trace contract v18) against `/s/nbqa/proj`.
