## What happened

`node node_modules/@docusaurus/core/bin/docusaurus.mjs write-translations --locale fr` was interrupted between two of its own file operations. This is crash point 2 of 11 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `fr/code.json` | file, 6920 bytes | file, 14059 bytes | file, 0 bytes | yes | no | no |
| `fr/docusaurus-plugin-content-blog` | absent | directory | absent | no | — | no |
| `fr/docusaurus-plugin-content-blog/options.json` | absent | file, 318 bytes | absent | no | — | no |
| `fr/docusaurus-theme-classic/footer.json` | absent | file, 1574 bytes | absent | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  open
        /s/docu/i18n/fr/code.json
<-- the process was terminated here -->
before: write
        /s/docu/i18n/fr/code.json
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity, and the checker — fr/code.json: holding neither the old nor the new content

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(docusaurus): a translation file is torn or the translator's messages are gone

## Reproducing it

```
sideeye replay /out/docusaurus/work-explore/cases/000001.json --oracle /usr/bin/strace
```

Saved case: `/out/docusaurus/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/docu/i18n`.
