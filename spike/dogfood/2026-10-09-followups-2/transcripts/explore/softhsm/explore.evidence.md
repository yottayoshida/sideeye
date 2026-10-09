## What happened

`softhsm2-util --import /s/hsm/k2.pem --token t --pin 1234 --label k2 --id 02` was interrupted between two of its own file operations. This is crash point 6 of 282 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `tokens/7d9c51eb-69dd-d293-8ef2-3e41802069b8/0ab42106-4258-9ac4-de9c-b73730e8d570.lock` | absent | file, 0 bytes | absent | no | — | yes |
| `tokens/7d9c51eb-69dd-d293-8ef2-3e41802069b8/0ab42106-4258-9ac4-de9c-b73730e8d570.object` | absent | file, 2225 bytes | absent | no | — | yes |
| `tokens/7d9c51eb-69dd-d293-8ef2-3e41802069b8/74dde1c5-0852-f06d-d827-72d4e629da21.lock` | absent | file, 0 bytes | absent | no | — | yes |
| `tokens/7d9c51eb-69dd-d293-8ef2-3e41802069b8/74dde1c5-0852-f06d-d827-72d4e629da21.object` | absent | file, 810 bytes | absent | no | — | yes |
| `tokens/7d9c51eb-69dd-d293-8ef2-3e41802069b8/generation` | file, 8 bytes | file, 8 bytes | file, 8 bytes | yes | no | yes |
| `tokens/7d9c51eb-69dd-d293-8ef2-3e41802069b8/token.object` | file, 320 bytes | file, 320 bytes | file, 0 bytes | yes | no | yes |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  truncate
        /s/hsm/tokens/7d9c51eb-69dd-d293-8ef2-3e41802069b8/token.object
<-- the process was terminated here -->
before: write
        /s/hsm/tokens/7d9c51eb-69dd-d293-8ef2-3e41802069b8/token.object
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line:

> the token does not list its keys: No slot with token named "t" found

## Reproducing it

```
sideeye replay /out/softhsm/work-explore/cases/000001.json --shim /opt/se/sideeye-v1.10.0-aarch64-linux/libsideeye_shim.so
```

Saved case: `/out/softhsm/work-explore/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The define declared 1 scratch path(s); the built-in invariants judge none of them, in any world.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/hsm`.
