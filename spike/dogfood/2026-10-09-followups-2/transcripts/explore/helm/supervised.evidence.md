## What happened

`/opt/bin/helm repo remove b --repository-config /s/helm/cfg/repositories.yaml --repository-cache /s/helm/cache` was interrupted between two of its own file operations. This is crash point 2 of 4 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `cache/b-charts.txt` | file, 2 bytes | absent | file, 2 bytes | yes | no | no |
| `cache/b-index.yaml` | file, 27 bytes | absent | file, 27 bytes | yes | no | no |
| `cfg/repositories.yaml` | file, 163 bytes | file, 249 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/helm/cfg/repositories.yaml
<-- the process was terminated here -->
before: write
        /s/helm/cfg/repositories.yaml
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — cfg/repositories.yaml: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/helm/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/helm/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/helm`.
