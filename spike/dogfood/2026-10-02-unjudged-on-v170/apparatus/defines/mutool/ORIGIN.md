# mutool — where this define comes from

**Source**: `spike/dogfood/2026-09-06-userview-2/apparatus/run-preflight.sh` lines 33–37
(`setup-pdf.sh`) and 79–83 (`run mutool --state /work/st/mu --setup … --operation "mutool clean
/work/st/mu/a.pdf /work/st/mu/a.pdf"`), with `apparatus/mkpdf.py` (copied here byte for byte).
The target was refused at preflight, so that run wrote no checker and no explore for it.

**Tool then**: mutool from Debian trixie's `mupdf-tools` (the version is not recorded in that
run; SELECTION.md names it "mutool (mupdf)"). `apparatus/Dockerfile.run`:

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates \
      flac python3-mutagen fontforge fonts-dejavu-core lame mupdf-tools
```

**Engine then**: cross-built from that run's own feature branch, printing `sideeye 1.1.0`
while `main` was at v1.2.0 (`spike/dogfood/README.md`) — not a release.

**Refused**: default mode (`--observe wrappers`), preflight (no oracle), `unresolvable_path` —
"an operation was observed whose path could not be determined, so it cannot be placed among the
crash points" (`transcripts/preflight/mutool.txt`). Attributed later to the `close` of the
unlinked input descriptor (`spike/followup-527/`, 2026-09-07) and fixed on 2026-09-08
(`spike/followup-522/`): after the fix the same define refuses `oracle_missed_operation` under
wrappers 16/16 (the stdio wall) and **FAIL 16/16** under `--observe syscalls`, earliest crash
point 2 of 3, after `unlink(a.pdf)` and before the `open` that recreates it
(`docs/target-classes.md`, the mutool row). Those later runs added a `mutool info` checker;
this define keeps the source run's form, with none.

**Form chosen**: the source run's (the only one in `spike/dogfood/`).

**Changed from the original**:
- paths: `/work/st/mu` → `/s/mutool/mu`; both file arguments of the operation moved with it.
- `--setup` is `seed.sh`.
- the box-wide `/ap/env.sh` sets `HOME`, `TMPDIR` and `XDG_*` under `/s/aux`; the original left
  them at the image's defaults.

No checker (the original had none; the built-in atomicity rule judges `a.pdf`).
