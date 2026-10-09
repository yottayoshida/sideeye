## What happened

`easyrsa revoke c1` was interrupted between two of its own file operations. This is crash point 18 of 39 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `a8047135` | absent | absent | directory | no | — | no |
| `a8047135/temp.00` | absent | absent | file, 5325 bytes | no | — | no |
| `a8047135/temp.01` | absent | absent | file, 5252 bytes | no | — | no |
| `a8047135/temp.02` | absent | absent | file, 3285 bytes | no | — | no |
| `index.txt` | file, 138 bytes | file, 151 bytes | absent | yes | yes (at `index.txt.old`) | no |
| `index.txt.attr.new` | absent | absent | file, 20 bytes | no | — | no |
| `index.txt.new` | absent | absent | file, 151 bytes | no | — | no |
| `index.txt.old` | file, 69 bytes | file, 138 bytes | file, 138 bytes | yes | no | no |
| `inline/private/c1.inline` | file, 7683 bytes | absent | file, 7683 bytes | yes | no | no |
| `issued/c1.crt` | file, 4489 bytes | absent | file, 4489 bytes | yes | yes (at `certs_by_serial/FC0D74949A88DF74FE87AF43ACCD2A74.pem`) | no |
| `lock.file` | absent | absent | file, 4 bytes | no | — | no |
| `private/c1.key` | file, 1704 bytes | absent | file, 1704 bytes | yes | no | no |
| `reqs/c1.req` | file, 887 bytes | absent | file, 887 bytes | yes | no | no |
| `revoked/certs_by_serial/FC0D74949A88DF74FE87AF43ACCD2A74.crt` | absent | file, 4489 bytes | absent | no | — | no |
| `revoked/private_by_serial/FC0D74949A88DF74FE87AF43ACCD2A74.key` | absent | file, 1704 bytes | absent | no | — | no |
| `revoked/reqs_by_serial` | absent | directory | absent | no | — | no |
| `revoked/reqs_by_serial/FC0D74949A88DF74FE87AF43ACCD2A74.req` | absent | file, 887 bytes | absent | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/easyrsa/pki/index.txt
<-- the process was terminated here -->
before: rename
        /s/easyrsa/pki/index.txt.new
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — index.txt: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/easyrsa/work-probe-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/easyrsa/work-probe-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- No oracle confirmed that Sideeye saw every state-changing operation of this run, so the crash points are what it observed rather than everything that happened.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/easyrsa/pki`.
