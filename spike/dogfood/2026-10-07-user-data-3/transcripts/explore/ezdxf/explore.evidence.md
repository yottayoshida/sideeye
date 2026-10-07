## What happened

`ezdxf strip /s/dxf/drawing.dxf` was interrupted between two of its own file operations. This is crash point 9 of 10 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `drawing.bak` | absent | absent | file, 17465 bytes | no | — | no |
| `drawing.dxf` | file, 17465 bytes | file, 17435 bytes | absent | yes | yes (at `drawing.bak`) | no |
| `drawing.ezdxf.tmp` | absent | absent | file, 17435 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/dxf/drawing.dxf
<-- the process was terminated here -->
before: rename
        /s/dxf/drawing.ezdxf.tmp
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — drawing.dxf: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/ezdxf/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.9.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/ezdxf/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.9.0 (trace contract v18) against `/s/dxf`.
