# joplin — where this define comes from

**Source**: `spike/dogfood/2026-09-13-joplin-turns/apparatus/preflight-main.sh` lines 16–29
(`SD=/w/jp`; seed `joplin --profile $SD mkbook TestBook && … use TestBook && … mknote SeedNote`
run directly into the state directory, no `--setup`; operation
`$(command -v joplin) [$JOPLIN_FLAGS] --profile $SD mknote SecondNote`). The same seed and
operation as `2026-09-11-past-walls/apparatus/screen.sh` lines 80–86 and 146
(`setup-joplin.sh`, `joplin --profile @SD@ mknote SecondNote`), the run that measured the row.

**Tool then**: joplin CLI 3.7.1 (`npm install -g joplin@3.7.1`), node v20.19.2.
`2026-09-13-joplin-turns/apparatus/Dockerfile`:

```
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps \
      nodejs npm make g++ python3-dev python3-pip libsecret-1-dev pkg-config libnode-dev
RUN pip3 install --break-system-packages \
      --trusted-host pypi.org --trusted-host files.pythonhosted.org setuptools
ENV npm_config_nodedir=/usr
RUN npm config set registry https://registry.npmjs.org/ \
 && npm config set strict-ssl false \
 && npm install -g --unsafe-perm joplin@3.7.1
```

**Engine then**: `main` at `478c954`, built from `git archive` with zig 0.16.0 (Debug), printing
`sideeye 1.3.0 (trace contract v16)`, engine sha256 `7aae148a…` — not a release. Before that,
the released v1.3.0 (2026-09-11-past-walls).

**Refused**: default mode (`--observe wrappers`), `multiple_threads_detected` — "two threads of
process N wrote in the judged directory: tid A performed rmdir(/w/jp/tmp) and tid B performed
mkdir(/w/jp)"; ten threads created, four thread ids writing
(`2026-09-13-joplin-turns/transcripts/preflight-main.txt`,
`preflight-main-flags-none.txt`; five times on v1.3.0 in
`2026-09-11-past-walls/transcripts/explore/joplin.prep{1..5}.txt`). The same refusal with
`--log-level error` (`preflight-main-log-level-error.txt`), which only stops `log.txt`.
Not measured under `--observe syscalls` or `--observe supervised`. The 2026-09-13 run's strace
reading: the four writers' operations do not overlap once the logger is off, but nothing the
shim records orders them (#580).

**Form chosen**: the logger-on form (no flags), the row's define. The other form is the same
operation with `--log-level error` before `--profile`.

**Changed from the original**:
- paths: `/w/jp` → `/s/joplin/jp`; the operation's `--profile` moved with it.
- the operation names `joplin` bare, as `screen.sh` did; `preflight-main.sh` resolved it with
  `command -v joplin` to the installed absolute path before passing it.
- the seed's output is not discarded (`run.sh` keeps it in `seed.log`), and `set -eu` stops the
  seed when a joplin command fails where the original printed `BROKEN: seed` and exited 2.

No checker (the original had none).
