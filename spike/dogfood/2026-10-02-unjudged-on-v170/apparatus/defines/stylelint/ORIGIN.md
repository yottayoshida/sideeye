# stylelint — origin

Copied byte-for-byte from `spike/dogfood/2026-09-22-shipped-v160/apparatus/defines/stylelint/`
(`seed.sh`, `sideeye.toml`). Already in this run's format. Not measured here.

## Tool and engine at the time

stylelint 17.15.0, `2026-09-22-shipped-v160/apparatus/Dockerfile` line 32:

```
RUN npm install -g --no-fund --no-audit eslint@10.11.0 stylelint@17.15.0 js-beautify@2.0.3 > /tmp/npm.log 2>&1; \
```

on Debian trixie's `nodejs` / `npm` (line 18). `stylelint` is a `#!/usr/bin/env node` script
found on `PATH` (`transcripts/checkers-ktlint-interpreters.txt`).

Engine: the released Sideeye v1.6.0 (`trace contract v18`), installed by the page's installer
at `/opt/se/sideeye-v1.6.0-aarch64-linux/sideeye` (`transcripts/entry/engine.txt`). Box run
with `--network none --cap-add SYS_PTRACE` (`transcripts/commands.txt`).

## What stopped it

The entry gate, not explore: `sideeye preflight --twice --oracle /usr/bin/strace` in the
default observation mode (`apparatus/entry.sh`) answered `UNKNOWN multiple_threads_detected`
— "tid 94 performed open(/s/stylelint/proj/a.css.3201003178) and tid 91 performed
write(/s/stylelint/proj/a.css.3201003178)", a temporary file beside `a.css`
(`transcripts/entry/stylelint.preflight.txt`; row in `transcripts/entry-candidates.txt`,
`gate=1`). Explore was never run (`RESULTS.md`, "stopped at the gate").

## Changed from the original

nothing. (`2026-09-28-shipped-v170/apparatus/run.sh` reads a define the same way
`2026-09-22-shipped-v160/apparatus/run.sh` does; see `../eslint/ORIGIN.md` for what differs
between the two scripts.)
