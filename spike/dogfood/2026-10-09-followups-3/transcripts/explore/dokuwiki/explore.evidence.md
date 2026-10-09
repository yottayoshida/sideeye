## What happened

`php /s/dw/bin/dwpage.php commit -m second /s/dw-in/page.txt wiki:start` was interrupted between two of its own file operations. This is crash point 7 of 30 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `attic/wiki/start.1790812800.txt.gz` | file, 93 bytes | file, 101 bytes | file, 93 bytes | yes | no | no |
| `locks/6bba7def63e6d59d07b3206a9f33f3fe.lock` | absent | absent | file, 5 bytes | no | — | no |
| `locks/ec16c969c7e9434c8a028bc5f00aeb14` | absent | absent | directory | no | — | no |
| `meta/_dokuwiki.changes` | file, 48 bytes | file, 97 bytes | file, 48 bytes | yes | yes (at `meta/wiki/start.changes`) | no |
| `meta/wiki/start.changes` | file, 48 bytes | file, 97 bytes | file, 48 bytes | yes | yes (at `meta/_dokuwiki.changes`) | no |
| `meta/wiki/start.meta` | file, 670 bytes | file, 806 bytes | file, 670 bytes | yes | no | no |
| `pages/wiki/start.txt` | file, 73 bytes | file, 85 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/dw/data/pages/wiki/start.txt
<-- the process was terminated here -->
before: write
        /s/dw/data/pages/wiki/start.txt
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — pages/wiki/start.txt: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/dokuwiki/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/dokuwiki/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/dw/data`.
