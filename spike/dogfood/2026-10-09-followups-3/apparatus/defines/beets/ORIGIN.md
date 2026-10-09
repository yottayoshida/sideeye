# beets — where this define comes from

**Source**: `spike/dogfood/2026-09-16-threads-take-turns/apparatus/run-v18.sh` lines 54–69
(`setup-beets.sh`, `check-beets.sh`) and 105 (`run beets /lib setup-beets.sh 'beet -c
@SD@/config.yaml import -q @SD@/in2' check-beets.sh`: state `$SD/lib`), with
`apparatus/mkwav.py` (copied here byte for byte). That run says the define is
`spike/followup-item4/run.sh`'s, verbatim; the first measurement was
`2026-09-05-userview/apparatus/run-preflight*.sh`.

**Tool then**: beets 2.1.0 on Python 3.13.5 (`transcripts/v18/environment.txt`), Debian trixie's
packages. `apparatus/Dockerfile.probe` (the base of `Dockerfile.measure`):

```
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends beets lame python3 ca-certificates && python3 --version && beet version
```

`lame` is the seed's encoder.

**Engine then**: the #539 branch build (contract v18), cross-built on the host, printing
`sideeye 1.4.0 (trace contract v18)` (`transcripts/v18/version.txt`) — not a release. Before
that, `sideeye 1.1.0 (trace contract v13)` on 2026-09-05.

**Refused**: `multiple_threads_detected`, 3/3 under `--observe wrappers` and 3/3 under
`--observe syscalls` — "two threads of process N wrote in the judged directory: tid A performed
unlink(…/lib/library.db-journal) and tid B performed open(…/lib/library.db). No thread creation
or join the shim recorded orders the first of those before the second"; three threads created,
three thread ids writing, one hand-over, three joins
(`transcripts/v18/beets.{wrappers,syscalls}.{1,2,3}.txt`). The two writers are pipeline
siblings ordered by a queue the shim does not see (`transcripts/probe/import.{1,2,3}.jl`).
Not measured under `--observe supervised`. 2026-09-05: the same reason under the rule of the
time (`2026-09-05-userview/transcripts/preflight-round1/beets.txt`).

**Form chosen**: the only one (`import -q` of a second album over a library holding the first).

**Changed from the original**:
- paths: `$SD` = `/localrun/st/<mode>/beets/<rep>` → `/s/beets` (state `/s/beets/lib`); the
  operation's `-c` and import paths moved with it. `/tmp/src.wav`, the intermediate wav, is
  where it was.
- `--setup` (run once per engine invocation) is `seed.sh`, run by `run.sh` before every engine
  invocation; `set -eu` stops the seed when a command fails where the original went on.
- the box-wide `/ap/env.sh` sets `HOME`, `TMPDIR` and `XDG_*` under `/s/aux`; the original left
  them at the image's defaults. beets reads `-c`, so the library is unaffected.
- `check.sh` needs `chmod 755` (the engine execs it; `/ap` is mounted read-only, so set it on
  the host).
