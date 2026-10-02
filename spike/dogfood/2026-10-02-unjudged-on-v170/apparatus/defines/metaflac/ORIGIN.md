# metaflac — where this define comes from

**Source**: `spike/dogfood/2026-09-06-userview-2/apparatus/run-explore.sh` lines 19–27
(`setup-flac2.sh`), 47–58 (`check-flac.sh`) and 98–100 (`go metaflac /work/st/fl …`), the same
files committed under `apparatus/declared/`, and `apparatus/mkwav.py` (copied here byte for
byte). The preflight form (`run-preflight.sh` lines 13–18, 62–65) had no ORIG tag and no checker.

**Tool then**: flac 1.5.0 (SELECTION.md slate 1), Debian trixie's package.
`apparatus/Dockerfile.run`:

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates \
      flac python3-mutagen fontforge fonts-dejavu-core lame mupdf-tools
```

**Engine then**: cross-built from that run's own feature branch, printing `sideeye 1.1.0`
while `main` was at v1.2.0 (`spike/dogfood/README.md`, "Which build a run measures");
`contract_version` 13 in `transcripts/explore/metaflac.json` — not a release.

**Refused**: default mode (`--observe wrappers`), explore, `oracle_missed_operation` —
"divergence at operation 3: the oracle saw: write(3</work/st/fl/a.flac>, …, 4096) = 4096; the
shim recorded: open(/work/st/fl/b.flac)" — a full stdio buffer written from inside `fwrite`,
ADR 0005's far side (`transcripts/explore/metaflac.txt`). Preflight (no oracle) had accepted it
with 6 operations (`transcripts/preflight/metaflac.txt`). Not measured by that run under
`--observe syscalls`; `spike/followup-527/` (2026-09-07, a later build, same define) measured
wrappers 8/8 the same refusal and syscalls **PASS 8/8** over 12 crash points
(`docs/target-classes.md`, the stdio row).

**Form chosen**: the explore's (ORIG tag in the seed, the checker), the only explored form.

**Changed from the original**:
- paths: `/work/st/fl` → `/s/metaflac/fl`; the three file arguments of the operation moved with
  it. `/tmp/src.wav` is where it was.
- `--setup` is `seed.sh`; `set -eu` stops the seed when a command fails where the original went
  on.
- the box-wide `/ap/env.sh` sets `HOME`, `TMPDIR` and `XDG_*` under `/s/aux`; the original left
  them at the image's defaults.
- `check.sh` needs `chmod 755` (the engine execs it; `/ap` is mounted read-only, so set it on
  the host).
