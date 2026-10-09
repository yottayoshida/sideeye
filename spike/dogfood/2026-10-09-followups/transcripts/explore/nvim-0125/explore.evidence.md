## What happened

`nvim-0125 --headless -n -u NONE -i /s/nv/main.shada -S /s/nv-in/op.vim` was interrupted between two of its own file operations. This is crash point 4 of 12 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `main.shada` | file, 142 bytes | file, 168 bytes | absent | yes | no | yes |
| `main.shada.tmp.a` | absent | absent | file, 168 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  unlink
        /s/nv/main.shada
<-- the process was terminated here -->
before: rename
        /s/nv/main.shada.tmp.a
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> register a is lost (main.shada absent; files: main.shada.tmp.a )

## Reproducing it

```
sideeye replay /out/nvim-0125/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/nvim-0125/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 1 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/nv`.
