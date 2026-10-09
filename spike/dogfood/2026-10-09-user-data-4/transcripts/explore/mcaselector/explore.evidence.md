## What happened

`/opt/mcaselector/bin/mcaselector --mode delete --world /s/mc/world --query InhabitedTime < 1000` was interrupted between two of its own file operations. This is crash point 2 of 2 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `region/r.0.0.mca` | file, 32768 bytes | file, 20480 bytes | absent | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  unlink
        /s/mc/world/region/r.0.0.mca
<-- the process was terminated here -->
before: rename
        /tmp/r.0.0.mca17726668882124732747.tmp
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — region/r.0.0.mca: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/mcaselector/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/mcaselector/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/mc/world`.
