# ocrmypdf — where this define comes from

**Source**: `spike/dogfood/2026-09-11-read-only-542/apparatus/ocrmypdf.sh` lines 26–29
(`setup.sh`: `mkdir -p "$SD"; python3 /pw/mkpdf.py "$SD/a.pdf"`), 32–45 (`check.sh`) and 54–61
(`--state $SD --setup … --operation "ocrmypdf -q --force-ocr $SD/a.pdf $SD/a.pdf" --check …`,
`SD=/tmp/localrun/st/<mode>-<what>/ocr`), with `HOME` moved to a writable directory (lines
18–22). `mkpdf.py` is `2026-09-11-past-walls/apparatus/mkpdf.py` (byte-identical to
`2026-09-06-userview-2/apparatus/mkpdf.py`), copied here. The row was first measured by
`2026-09-11-past-walls/apparatus/screen.sh` line 144 with the same operation.

**Tool then**: ocrmypdf 16.7.0 (`16.7.0+dfsg1`, `transcripts/ocrmypdf.after.console.txt`),
Debian trixie's packages. `apparatus/Dockerfile`:

```
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps ocrmypdf tesseract-ocr-eng ghostscript
```

**Engine then**: the build of #542's first change ("after"), printing
`sideeye 1.3.0 (trace contract v16)` — not a release; "before" was `main` at `abad4ce`.

**Refused**:
- before #542 (and on the released v1.3.0, 2026-09-11-past-walls): `unsupported_syscall_observed`
  on `faccessat2`, both modes (`transcripts/ocrmypdf.before.{wrappers,syscalls}.preflight.txt`).
- after: preflight accepted in both modes, 2 state-changing operations, the oracle agreeing
  (`transcripts/ocrmypdf.after.{wrappers,syscalls}.preflight.txt`); explore
  `baseline_violates_invariant` in both modes — "the re-run from the restored state left a.pdf
  holding neither the old nor the new content" (`transcripts/ocrmypdf.after.{wrappers,syscalls}.explore.txt`);
  `preflight --twice` not accepted, `a.pdf (content differs)`, plainly and with
  `SOURCE_DATE_EPOCH=1700000000` (`transcripts/ocrmypdf.after.twice-{plain,epoch}.txt`). The
  wall behind `faccessat2` is byte repeatability. Under `--observe syscalls` the transcripts
  also carry #556's `SIGSYS` in the children probing for absent tools (`jbig2`, `pngquant`).
  Not measured under `--observe supervised`.

**Form chosen**: the explore's (plain operation, the checker). The `env SOURCE_DATE_EPOCH=…`
prefix was a `--twice` experiment only, and did not make the two runs agree.

**Changed from the original**:
- paths: `$SD` → `/s/ocrmypdf/ocr`; both file arguments of the operation moved with it.
- `--setup` is `seed.sh`; `mkpdf.py`'s one line of output is kept in `seed.log`.
- `HOME`: the original exported a writable `HOME` under its run directory because it ran as an
  unprivileged user; here the box-wide `/ap/env.sh` sets `HOME=/s/aux/home` (and `TMPDIR`,
  `XDG_*` under `/s/aux`), writable, which is what fontconfig, tesseract and ghostscript need.
  Nothing is declared in the toml for it.
- `check.sh` needs `chmod 755` (the engine execs it; `/ap` is mounted read-only, so set it on
  the host).
