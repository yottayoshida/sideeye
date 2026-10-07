## What happened

`openssl ca -config /s/ca/ca.cnf -revoke /s/ca/b.crt -batch` was interrupted between two of its own file operations. This is crash point 6 of 8 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `index.txt` | file, 108 bytes | file, 121 bytes | absent | yes | yes (at `index.txt.old`) | no |
| `index.txt.attr.new` | absent | absent | file, 20 bytes | no | — | no |
| `index.txt.new` | absent | absent | file, 121 bytes | no | — | no |
| `index.txt.old` | file, 72 bytes | file, 108 bytes | file, 108 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/ca/index.txt
<-- the process was terminated here -->
before: rename
        /s/ca/index.txt.new
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — index.txt: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/openssl/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.9.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/openssl/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.9.0 (trace contract v18) against `/s/ca`.
