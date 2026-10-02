# chezmoi — where this define comes from

**Source**: `spike/dogfood/2026-09-27-supervised-static/apparatus/run.sh` lines 31–41
(`chezmoi|chezmoi-force` case: `HOME=/tmp/cz/home`, the two source files, `STATE=/tmp/cz/dest`,
`SETUP=/ap/cz-setup.sh`, the operation) and `apparatus/cz-setup.sh` (clears chezmoi's database
under `$HOME`). That run took the define from `2026-09-05-userview/apparatus/run-preflight2.sh`
(the full-path spelling, line 27–29).

**Tool then**: chezmoi 2.72.1, the project's `chezmoi_2.72.1_linux_arm64.tar.gz` release asset,
sha256 `75508ef41216b6d64f3145986b751729d7f92d09c6bad77d51cf2895ab35a508` checked by
`apparatus/build.sh` against `chezmoi_2.72.1_checksums.txt`. `apparatus/Dockerfile`:

```
    && tar xzf chezmoi_2.72.1_linux_arm64.tar.gz -C /opt/cz \
    && install -m 755 /opt/cz/chezmoi /usr/local/bin/chezmoi \
```

Statically linked (`transcripts/chezmoi/entry-linkage.txt`).

**Engine then**: `main` at `01e6760`, built in the box (ReleaseSafe), printing
`sideeye 1.6.0 (trace contract v18)`, binary sha256 `ccb81449…` — not a release.

**Refused**:
- default mode (`--observe wrappers`): `no_shim_marker` — `transcripts/chezmoi/entry-preflight.txt`
  (one `preflight --twice`). The same refusal on 2026-09-05 with `sideeye 1.1.0`
  (`2026-09-05-userview/transcripts/preflight-round1/chezmoi-fullpath.txt`).
- `--observe supervised`, the fixed define (`apply` without `--force`): `recording_run_failed`
  5/5 — the second observed run exits 1, `chezmoi: .second: EOF`
  (`transcripts/chezmoi/sup-preflight-{1..5}.txt`). Shown to happen with no engine at all
  (`transcripts/chezmoi/no-engine-control.txt`): chezmoi's database remembers the first run.
- `--observe supervised`, corrected with `--force`: preflight accepted 4/5 (one
  `multiple_threads_detected`), explores **PASS 3/3** judging 0 files
  (`transcripts/chezmoi-force/`).

**Form chosen**: the corrected one (`--force`), the last define that run used for this target
(RESULTS.md, "Three defines corrected after their result"). The fixed form is the same line
without `--force`.

**Changed from the original**:
- paths: `/tmp/cz/{src,dest,home}` → `/s/chezmoi/{src,dest,home}`; the operation's `--source`
  and `--destination` moved with them.
- `--setup /ap/cz-setup.sh` (clear `$HOME/.config/chezmoi`, `.local/share/chezmoi`,
  `.cache/chezmoi`) is folded into `seed.sh`, which removes `/s/chezmoi` whole before every
  engine run. The engine's own `setup` also ran once per invocation, so the timing is the same.
- the original exported `HOME` in `run.sh`; here `env.sh` (sourced by `run.sh` after the box-wide
  `/ap/env.sh`, before the seed and the engine) exports it, and `apparatus =
  ["env:HOME=/s/chezmoi/home"]` is new in the toml: the engine checks the entry and refuses as a
  SETUP ERROR if the export did not reach it.

No checker (the original had none).
