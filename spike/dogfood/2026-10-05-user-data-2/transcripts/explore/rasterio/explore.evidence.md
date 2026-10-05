## What happened

`rio edit-info --crs EPSG:4326 --tag survey=2026 /s/rio/a.tif` was interrupted between two of its own file operations. This is crash point 3 of 5 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `a.tif` | file, 20260 bytes | file, 20714 bytes | file, 20260 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  write
        /s/rio/a.tif
<-- the process was terminated here -->
before: write
        /s/rio/a.tif
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — a.tif: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/rasterio/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.8.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/rasterio/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.8.0 (trace contract v18) against `/s/rio`.
