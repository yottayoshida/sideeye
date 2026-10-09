## What happened

`tofu state rm terraform_data.b` was interrupted between two of its own file operations. This is crash point 7 of 9 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `.terraform.tfstate.lock.info` | absent | absent | file, 193 bytes | no | — | no |
| `terraform.tfstate` | file, 2008 bytes | file, 1401 bytes | file, 0 bytes | yes | yes (at `terraform.tfstate.1791535373.backup`) | no |
| `terraform.tfstate.1791535373.backup` | absent | file, 2008 bytes | file, 2008 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  truncate
        /s/tofu/terraform.tfstate
<-- the process was terminated here -->
before: write
        /s/tofu/terraform.tfstate
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — terraform.tfstate: holding neither the old nor the new content

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/tofu/work-probe-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/tofu/work-probe-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/tofu`.
