# gopass — where this define comes from

**Source**: `spike/dogfood/2026-09-27-supervised-static/apparatus/run.sh` lines 42–54
(`gopass|gopass-rm` case: `GOPASS_AGE_PASSWORD=testpassphrase`, the golden store made once with
`gopass --yes setup --crypto age --storage fs --name tester --email tester@example.com` and
`printf 'first\n' | gopass insert -f seed/entry0`, `GOPASS_HOMEDIR=/tmp/gp`,
`STATE=/tmp/gp/.local/share/gopass/stores/root`, `SETUP=/ap/gp-setup.sh`, the operation) and
`apparatus/gp-setup.sh` (copies the golden store's `.config` and store into place). That run took
the define from `2026-09-05-userview/apparatus/run-preflight4.sh`.

**Tool then**: gopass 1.17.0 (`gopass 1.17.0 (08ebbadb) go1.25.0 linux arm64`,
`transcripts/build.txt`), the project's `gopass-1.17.0-linux-arm64.tar.gz` release asset, sha256
`dc716451c395264e47e3f13702cdab4a7721f375a7465f6969c872f7c75092e2` checked by
`apparatus/build.sh` against `gopass_1.17.0_SHA256SUMS`. `apparatus/Dockerfile`:

```
    && tar xzf gopass-1.17.0-linux-arm64.tar.gz -C /opt/gp \
    && install -m 755 /opt/gp/gopass /usr/local/bin/gopass \
```

Statically linked (`transcripts/gopass/entry-linkage.txt`).

**Engine then**: `main` at `01e6760`, built in the box (ReleaseSafe), printing
`sideeye 1.6.0 (trace contract v18)`, binary sha256 `ccb81449…` — not a release.

**Refused**:
- default mode (`--observe wrappers`): `no_shim_marker` — `transcripts/gopass/entry-preflight.txt`.
  The same on 2026-09-05 with `sideeye 1.1.0`
  (`2026-09-05-userview/transcripts/preflight-round1/gopass-direct.txt`).
- `--observe supervised`, the fixed define (`gopass generate --print=false test/generated 20`):
  `preflight --twice` not accepted 5/5, `test/generated.age (content differs)` — a random secret,
  age-encrypted (`transcripts/gopass/sup-preflight-{1..5}.txt`). A property of that operation,
  not of the engine.
- `--observe supervised`, corrected to `gopass rm -f seed/entry0`: preflight accepted 5/5
  (3 operations), explores **PASS 3/3**, judging `.age-recipients` only
  (`transcripts/gopass-rm/`).

**Form chosen**: the corrected one (`rm -f seed/entry0`), the last define that run used for this
target (RESULTS.md, "Three defines corrected after their result"). The fixed form is
`operation = "/usr/local/bin/gopass generate --print=false test/generated 20"`.

**Changed from the original**:
- paths: `/tmp/gp-golden` → `/s/gopass/golden`, `/tmp/gp` → `/s/gopass/gp`; `GOPASS_HOMEDIR`
  moved with them. The operation carries no path.
- the golden store's creation (run.sh, once per container) and `--setup /ap/gp-setup.sh` (copy
  into place, once per engine run) are both in `seed.sh`: the golden store is built when absent
  and copied before every engine run. `golden-setup.txt` goes to `/s/gopass/`, not to the output
  directory.
- the original exported both in `run.sh`; here `env.sh` (sourced by `run.sh` after the box-wide
  `/ap/env.sh`, before the seed and the engine) exports them, and `apparatus =
  ["env:GOPASS_HOMEDIR=/s/gopass/gp", "env:GOPASS_AGE_PASSWORD=testpassphrase"]` is new in the
  toml: the engine checks the entries and refuses as a SETUP ERROR if an export did not reach
  it. The passphrase is the original run's test value, not a real secret. (`seed.sh` sets both
  for its own gopass commands as well.)
- the box-wide `/ap/env.sh` sets `HOME=/s/aux/home`; the original left `HOME` at the image's
  default. `GOPASS_HOMEDIR` is what gopass reads, so the store is unaffected.

No checker (the original had none).
