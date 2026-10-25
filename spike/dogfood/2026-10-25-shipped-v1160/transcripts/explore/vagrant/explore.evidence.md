## What happened

`ruby /opt/vagrant-gems/bin/vagrant global-status --prune` was interrupted between two of its own file operations. This is crash point 10 of 35 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `data/machine-index/0000000000000000000000005eed0000.lock` | absent | absent | file, 0 bytes | no | — | no |
| `data/machine-index/index` | file, 2016 bytes | file, 27 bytes | file, 0 bytes | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/vagrant.d/data/machine-index/index
<-- the process was terminated here -->
before: write
        /s/vagrant.d/data/machine-index/index
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — data/machine-index/index: holding neither the old nor the new content

## Checker

The define's own checker accepted the state in this world.

It printed nothing: no line of its output held any text.

## Reproducing it

```
sideeye replay /out/vagrant/work-explore/cases/000001.json --oracle /usr/bin/strace
```

Saved case: `/out/vagrant/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/vagrant.d`.
