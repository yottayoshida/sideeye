## What happened

`mbsync -c /s/mb/rc ch` was interrupted between two of its own file operations. This is crash point 6 of 45 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `far/.uidvalidity` | file, 13 bytes | file, 13 bytes | file, 13 bytes | yes | yes (at `near/.uidvalidity`) | no |
| `far/new/1002.1.host` | file, 109 bytes | absent | file, 109 bytes | yes | no | no |
| `far/new/1002.1.host,U=3` | absent | file, 109 bytes | absent | no | — | no |
| `far/new/1767225600.43_1.c9344e11b2e4,U=4:2,` | absent | file, 127 bytes | absent | no | — | no |
| `near/.uidvalidity` | file, 13 bytes | file, 13 bytes | file, 13 bytes | yes | no | no |
| `near/cur/1767225600.35_1.c9344e11b2e4,U=1:2,S` | absent | file, 124 bytes | absent | no | — | no |
| `near/new/1003.1.host` | file, 106 bytes | absent | file, 106 bytes | yes | no | no |
| `near/new/1003.1.host,U=3` | absent | file, 106 bytes | absent | no | — | no |
| `near/new/1767225600.35_1.c9344e11b2e4,U=1:2,` | file, 124 bytes | absent | file, 124 bytes | yes | no | no |
| `near/new/1767225600.43_2.c9344e11b2e4,U=4:2,` | absent | file, 130 bytes | absent | no | — | no |
| `st/INBOX` | file, 94 bytes | file, 105 bytes | file, 94 bytes | yes | no | no |
| `st/INBOX.lock` | absent | absent | file, 0 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  write
        /s/mb/far/.uidvalidity
<-- the process was terminated here -->
before: truncate
        /s/mb/far/.uidvalidity
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — far/.uidvalidity: holding neither the old nor the new content

## Checker

The define's own checker accepted the state in this world.

Its last output line:

> checker(mbsync) after recovery: a=ok b=ok c=ok d=ok

## Reproducing it

```
sideeye replay /out/mbsync/work-syscalls/cases/000001.json --observe syscalls --shim /opt/se/sideeye-v1.12.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/mbsync/work-syscalls/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.12.0 (trace contract v19) against `/s/mb`.
