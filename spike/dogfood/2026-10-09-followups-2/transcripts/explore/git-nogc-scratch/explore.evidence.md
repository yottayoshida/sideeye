## What happened

`git -c gc.auto=0 -c maintenance.auto=false -C /s/git/state commit -q -m second` was interrupted between two of its own file operations. This is crash point 12 of 38 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `.git/COMMIT_EDITMSG` | file, 3 bytes | file, 7 bytes | file, 0 bytes | yes | no | no |
| `.git/index` | file, 262 bytes | file, 281 bytes | file, 281 bytes | yes | no | yes |
| `.git/logs/HEAD` | file, 430 bytes | file, 574 bytes | file, 430 bytes | yes | yes (at `.git/logs/refs/heads/master`) | no |
| `.git/logs/refs/heads/master` | file, 430 bytes | file, 574 bytes | file, 430 bytes | yes | yes (at `.git/logs/HEAD`) | no |
| `.git/objects/4b` | absent | directory | directory | no | — | no |
| `.git/objects/4b/d006752ef49da80b87aff1291110cbff08d2e0` | absent | file, 104 bytes | file, 104 bytes | no | — | no |
| `.git/objects/5c` | absent | directory | absent | no | — | no |
| `.git/objects/5c/78416deef243757b2dffe80a580e5c8be465cf` | absent | file, 149 bytes | absent | no | — | no |
| `.git/refs/heads/master` | file, 41 bytes | file, 41 bytes | file, 41 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/git/state/.git/COMMIT_EDITMSG
<-- the process was terminated here -->
before: write
        /s/git/state/.git/COMMIT_EDITMSG
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — .git/COMMIT_EDITMSG: holding neither the old nor the new content

## Checker

The define's own checker accepted the state in this world.

Its output could not be read back, so what it said is unknown.

## Reproducing it

```
sideeye replay /out/git-nogc-scratch/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/git-nogc-scratch/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 1 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/git/state`.
