# fontforge — where this define comes from

**Source**: `spike/dogfood/2026-09-06-userview-2/apparatus/run-explore.sh` lines 39–43
(`setup-ttf2.sh`), 73–80 (`check-ttf.sh`) and 106–108 (`go fontforge /work/st/ff … 'fontforge
-lang=ff -c Open("/work/st/ff/f.ttf");Generate("/work/st/ff/f.ttf"); '`), the same files under
`apparatus/declared/`; the wrapper `op.sh` is `run-preflight.sh` lines 39–42 (`op-ttf.sh`:
`exec fontforge -lang=ff -c 'Open("/work/st/ff/f.ttf"); Generate("/work/st/ff/f.ttf");'`).

**Tool then**: fontforge 20230101 (the banner in `transcripts/explore/fontforge.txt`:
`Version: 20230101`, `Based on sources from 2025-01-07`), Debian trixie's package, with
`fonts-dejavu-core` for the seed. `apparatus/Dockerfile.run`:

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates \
      flac python3-mutagen fontforge fonts-dejavu-core lame mupdf-tools
```

**Engine then**: cross-built from that run's own feature branch, printing `sideeye 1.1.0`
while `main` was at v1.2.0 (`spike/dogfood/README.md`); `contract_version` 13 in
`transcripts/explore/fontforge.json` — not a release.

**Refused**: default mode (`--observe wrappers`), explore, `oracle_missed_operation` —
"divergence at operation 4: the oracle saw: write(4</work/st/ff/f.ttf>, …, 4096) = 4096; the
shim's account ends after 3 operation(s)" — a full stdio buffer written from inside `fwrite`
(`transcripts/explore/fontforge.txt`). Preflight (no oracle) had accepted the direct spelling
with 3 operations (`transcripts/preflight/fontforge.txt`); the wrapper spelling, tried first,
refused `child_process_detected` on that engine (RESULTS.md, "the three apparatus errors", 2).
Not measured by that run under `--observe syscalls`; `spike/followup-527/` (2026-09-07, a later
build) measured the direct spelling wrappers 4/4 the same refusal and syscalls **FAIL 4/4,
183 of 185 worlds over 184 crash points**, and the wrapper spelling (`ffwrapper`) the same
verdict with the same counts, `processes` reading "the subject replaced its own image … chain
unbroken (#123)" (`docs/target-classes.md`, the stdio row).

**Form chosen, and the one deviation that matters**: the direct spelling cannot be written in a
`sideeye.toml` — the parser takes one double-quoted string with no escapes and closes at the
first `"` (`src/config.zig`, `stripQuoted`), and the FontForge statements need double quotes.
So the operation is `/bin/sh /ap/defines/fontforge/op.sh`, the source run's own wrapper with the
path moved. **The image the engine starts is `/bin/sh`, not `fontforge`**, and the run carries
one `exec`: on the 2026-09-06 engine that spelling refused `child_process_detected`; on the
2026-09-07 build it reached the direct spelling's verdict and counts. The alternative not taken
(unmeasured anywhere): `fontforge -lang=ff -script <file.pe>` with the statements in a script
file, which keeps the image but changes the argument form. `op.sh` is run through `/bin/sh`,
so it needs no execute bit.

**Changed from the original**:
- paths: `/work/st/ff` → `/s/fontforge/ff`; the paths inside the FontForge statements moved
  with it.
- the operation is the wrapper, as above; the FontForge statements are the wrapper's own
  (`Open(…); Generate(…);`, a space between them where the direct spelling had none).
- `--setup` is `seed.sh`.
- the box-wide `/ap/env.sh` sets `HOME`, `TMPDIR` and `XDG_*` under `/s/aux`; the original left
  them at the image's defaults (fontforge keeps its preferences under `$HOME/.config`).
- `check.sh` needs `chmod 755` (the engine execs it; `/ap` is mounted read-only, so set it on
  the host).
