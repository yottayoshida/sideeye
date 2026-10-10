# eslint — origin

Copied byte-for-byte from `spike/dogfood/2026-09-22-shipped-v160/apparatus/defines/eslint/`
(`seed.sh`, `sideeye.toml`). Already in this run's format. Not measured here.

## Tool and engine at the time

eslint 10.11.0, `2026-09-22-shipped-v160/apparatus/Dockerfile` line 32:

```
RUN npm install -g --no-fund --no-audit eslint@10.11.0 stylelint@17.15.0 js-beautify@2.0.3 > /tmp/npm.log 2>&1; \
```

on Debian trixie's `nodejs` / `npm` (line 18). `eslint` is a `#!/usr/bin/env node` script
found on `PATH` (`transcripts/checkers-ktlint-interpreters.txt`).

Engine: the released Sideeye v1.6.0 (`trace contract v18`), installed by the page's installer
at `/opt/se/sideeye-v1.6.0-aarch64-linux/sideeye` (`transcripts/entry/engine.txt`). Box run
with `--network none --cap-add SYS_PTRACE` (`transcripts/commands.txt`).

## What stopped it

The entry gate, not explore: `sideeye preflight --twice --oracle /usr/bin/strace` in the
default observation mode (`apparatus/entry.sh`) answered `UNKNOWN multiple_threads_detected`
— "tid 45 performed open(/s/eslint/proj/a.js) and tid 46 performed write(/s/eslint/proj/a.js)
… No thread creation or join the shim recorded orders the first of those before the second"
(`transcripts/entry/eslint.preflight.txt`; row in `transcripts/entry-candidates.txt`,
`gate=1`). Explore was never run (`RESULTS.md`, "stopped at the gate").

## Changed from the original

nothing. (`2026-09-28-shipped-v170/apparatus/run.sh` reads a define the same way
`2026-09-22-shipped-v160/apparatus/run.sh` does — `sh defines/<name>/seed.sh`, then
`explore --config defines/<name>/sideeye.toml`; what the 2026-09-28 script added is a second
follow, `--observe supervised` on a `no_shim_marker` refusal, and a `--privileged
--cgroupns=private` box.)
