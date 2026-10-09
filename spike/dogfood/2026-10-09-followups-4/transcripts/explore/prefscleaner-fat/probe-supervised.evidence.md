## What happened

`setpriv --reuid=1000 --regid=1000 --clear-groups bash ./prefsCleaner.sh -s -d` was interrupted between two of its own file operations. This is crash point 3 of 7 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `prefs.js` | file, 276 bytes | file, 117 bytes | absent | yes | yes (at `prefsjs_backups/prefs.js.backup.2026-10-09_0828`) | no |
| `prefsjs_backups` | absent | directory | directory | no | — | no |
| `prefsjs_backups/prefs.js.backup.2026-10-09_0828` | absent | file, 276 bytes | file, 276 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/ffprofile/prefs.js
<-- the process was terminated here -->
before: open
        /s/ffprofile/prefs.js
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

built-in atomicity (L0) — prefs.js: present before and after the operation, but gone from the crashed state

## Checker

None was configured, so nothing here says whether the resulting state is correct for the application.

## Reproducing it

```
sideeye replay /out/prefscleaner-fat/work-probe-supervised/cases/000001.json --observe supervised
```

Saved case: `/out/prefscleaner-fat/work-probe-supervised/cases/000001.json`

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- No oracle confirmed that Sideeye saw every state-changing operation of this run, so the crash points are what it observed rather than everything that happened.

Measured by Sideeye 1.10.0 (trace contract v19) against `/s/ffprofile`.
