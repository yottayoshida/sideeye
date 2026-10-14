## What happened

`dpkg-divert --admindir /s/dv/admin --instdir /s/dv/root --rename --divert /usr/bin/tool.distrib --add /usr/bin/tool` was interrupted between two of its own file operations. This is crash point 11 of 11 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `admin/diversions` | file, 0 bytes | file, 38 bytes | file, 38 bytes | yes | unknown | no |
| `admin/diversions-old` | absent | file, 0 bytes | file, 0 bytes | no | — | no |
| `root/usr/bin/tool` | file, 18 bytes | absent | file, 18 bytes | yes | no | no |
| `root/usr/bin/tool.distrib` | absent | file, 18 bytes | absent | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/dv/admin/diversions-new
<-- the process was terminated here -->
before: rename
        /s/dv/root/usr/bin/tool
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> checker(divert) after recovery: a=FAIL(listed=1 moved=0) b=ok

## Reproducing it

```
sideeye replay /out/divert/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.12.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/divert/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.12.0 (trace contract v19) against `/s/dv`.
