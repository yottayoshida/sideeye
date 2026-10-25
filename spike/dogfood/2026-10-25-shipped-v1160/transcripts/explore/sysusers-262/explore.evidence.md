## What happened

`/opt/bin/systemd-sysusers-262 --root=/s/sysroot /s/sysaux/app.conf` was interrupted between two of its own file operations. This is crash point 43 of 45 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `etc/.#gshadow54da1710fe8bb247` | absent | absent | file, 151 bytes | no | — | no |
| `etc/.#passwdda31d8facc3cd77e` | absent | absent | file, 468 bytes | no | — | no |
| `etc/.#shadowfbe3d8f28c209efa` | absent | absent | file, 358 bytes | no | — | no |
| `etc/.pwd.lock` | absent | file, 0 bytes | file, 0 bytes | no | — | no |
| `etc/group` | file, 156 bytes | file, 177 bytes | file, 177 bytes | yes | yes (at `etc/group-`) | no |
| `etc/group-` | absent | file, 156 bytes | file, 156 bytes | no | — | no |
| `etc/gshadow` | file, 132 bytes | file, 151 bytes | file, 132 bytes | yes | yes (at `etc/gshadow-`) | no |
| `etc/gshadow-` | absent | file, 132 bytes | file, 132 bytes | no | — | no |
| `etc/passwd` | file, 389 bytes | file, 468 bytes | file, 389 bytes | yes | yes (at `etc/passwd-`) | no |
| `etc/passwd-` | absent | file, 389 bytes | file, 389 bytes | no | — | no |
| `etc/shadow` | file, 336 bytes | file, 358 bytes | file, 336 bytes | yes | yes (at `etc/shadow-`) | no |
| `etc/shadow-` | absent | file, 336 bytes | file, 336 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/sysroot/etc/.#group578d04b30b22c317
<-- the process was terminated here -->
before: rename
        /s/sysroot/etc/.#gshadowf0e1e2906af3bb2e
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(sysusers): grpck -r exited 2: group ssl-cert: no user appsvc delete member 'appsvc'? No 'appsvc' is a member of the 'ssl-cert' group in /etc/group but not in /etc/gshadow

## Reproducing it

```
sideeye replay /out/sysusers-262/work-explore/cases/000001.json --oracle /usr/bin/strace
```

Saved case: `/out/sysusers-262/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/sysroot`.
