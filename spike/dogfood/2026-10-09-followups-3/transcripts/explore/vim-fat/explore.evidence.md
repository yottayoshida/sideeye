## What happened

`vim -es -u NONE -c set nobackup noswapfile nowritebackup -c %s/old/new/g -c wq /s/vim/state/a.txt` was interrupted between two of its own file operations. This is crash point 10 of 11 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `a.txt` | file, 50 bytes | file, 50 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  truncate
        /s/vim/state/a.txt
<-- the process was terminated here -->
before: write
        /s/vim/state/a.txt
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — a.txt: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> a.txt が空になった

## Reproducing it

```
sideeye replay /out/vim-fat/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/vim-fat/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/vim/state`.
