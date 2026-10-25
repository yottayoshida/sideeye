## What happened

`/opt/salt/salt/bin/python3.14 /opt/salt/salt/salt-call -c /s/salt --local grains.setval maintainer ops-oncall` was interrupted between two of its own file operations. This is crash point 2 of 2 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `grains` | file, 148 bytes | file, 171 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/salt/grains
<-- the process was terminated here -->
before: write
        /s/salt/grains
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — grains: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(salt-grains): grain value tokyo-2 is gone: {    "local": {        "datacenter": "",        "environment": "",        "owner": "",        "rack": "",        "cost_center": ""    }}

## Reproducing it

```
sideeye replay /out/salt-grains/work-supervised/cases/000001.json --observe supervised --oracle /usr/bin/strace
```

Saved case: `/out/salt-grains/work-supervised/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/salt`.
