## What happened

`useradd --prefix /s/useradd/root -M -d / -G staff -p $6$s$h -s /bin/sh alice` was interrupted between two of its own file operations. This is crash point 46 of 70 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `root/etc/group` | file, 41 bytes | file, 61 bytes | file, 41 bytes | yes | no | no |
| `root/etc/group-` | absent | file, 41 bytes | absent | no | — | no |
| `root/etc/group.lock` | absent | absent | file, 5 bytes | no | — | no |
| `root/etc/gshadow` | file, 34 bytes | file, 50 bytes | file, 34 bytes | yes | no | no |
| `root/etc/gshadow-` | absent | file, 34 bytes | absent | no | — | no |
| `root/etc/gshadow.lock` | absent | absent | file, 5 bytes | no | — | no |
| `root/etc/passwd` | file, 55 bytes | file, 84 bytes | file, 84 bytes | yes | yes (at `root/etc/passwd-`) | no |
| `root/etc/passwd-` | absent | file, 55 bytes | file, 55 bytes | no | — | no |
| `root/etc/passwd.lock` | absent | absent | file, 5 bytes | no | — | no |
| `root/etc/shadow` | file, 53 bytes | file, 85 bytes | file, 53 bytes | yes | no | no |
| `root/etc/shadow-` | absent | file, 53 bytes | absent | no | — | no |
| `root/etc/shadow.lock` | absent | absent | file, 5 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/useradd/root/etc/passwd+
<-- the process was terminated here -->
before: open
        /s/useradd/root/etc/shadow-
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> checker(useradd) after recovery: a=FAIL b=ok c=FAIL(1 of 4) d=ok

## Reproducing it

```
sideeye replay /out/useradd/work-syscalls/cases/000001.json --observe syscalls --shim /opt/se/sideeye-v1.12.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/useradd/work-syscalls/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.12.0 (trace contract v19) against `/s/useradd`.
