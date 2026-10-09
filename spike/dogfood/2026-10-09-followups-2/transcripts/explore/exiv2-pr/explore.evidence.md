## What happened

`/opt/bin/exiv2-pr rm /s/ex/pic1.jpg /s/ex/pic2.jpg /s/ex/pic3.jpg` was interrupted between two of its own file operations. This is crash point 4 of 15 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `pic1.jpg` | file, 319 bytes | file, 301 bytes | absent | yes | yes (at `pic2.jpg`) | no |
| `pic1.jpg.exv-tmp-149-0` | absent | absent | file, 301 bytes | no | — | no |
| `pic2.jpg` | file, 319 bytes | file, 301 bytes | file, 319 bytes | yes | yes (at `pic3.jpg`) | no |
| `pic3.jpg` | file, 319 bytes | file, 301 bytes | file, 319 bytes | yes | yes (at `pic2.jpg`) | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  unlink
        /s/ex/pic1.jpg
<-- the process was terminated here -->
before: rename
        /s/ex/pic1.jpg.exv-tmp-130-0
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — pic1.jpg: present before and after the operation, but gone from the crashed state

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> pic1.jpg is missing

## Reproducing it

```
sideeye replay /out/exiv2-pr/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/exiv2-pr/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/ex`.
