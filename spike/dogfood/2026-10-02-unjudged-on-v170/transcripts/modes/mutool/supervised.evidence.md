## What happened

`mutool clean /s/mutool/mu/a.pdf /s/mutool/mu/a.pdf` was interrupted between two of its own file operations. This is crash point 2 of 3 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `a.pdf` | file, 537 bytes | file, 563 bytes | absent | yes | no | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  unlink
        /s/mutool/mu/a.pdf
<-- the process was terminated here -->
before: open
        /s/mutool/mu/a.pdf
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — a.pdf: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/mutool/modes/work-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/mutool/modes/work-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.7.0 (trace contract v18) against `/s/mutool/mu`.
