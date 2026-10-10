# lefthook — where this define comes from

**Source**: `spike/dogfood/2026-09-27-supervised-static/apparatus/run.sh` lines 59–68
(`lefthook|lefthook-sh|lefthook-nocheck` case: `STATE=/tmp/lh-repo/.git/hooks`,
`SETUP=/ap/lefthook/seed-state.sh`, `CHECK=/ap/lefthook/verify.sh`, `CWD=/tmp/lh-repo`,
`OP=/usr/local/bin/lefthook install`; `lefthook-nocheck` drops the checker) with
`apparatus/lefthook/seed-state.sh` and `apparatus/lefthook/verify.sh`, both byte-identical copies
of `2026-09-21-release-path/apparatus/seed-state.sh` and `verify.sh`, whose `sideeye.toml` is the
define's first form (`state = "/tmp/lh-repo/.git/hooks"`, `cwd = "/tmp/lh-repo"`,
`operation = ["lefthook", "install"]`, `check = "./verify.sh"`).

**Tool then**: lefthook 1.13.6, the project's `lefthook_1.13.6_Linux_arm64` release asset, sha256
`1e61c71d221143e4c2351c551a6ae66d36b62cce1d916cad67c40c4bd9211530` checked by
`apparatus/build.sh` against `lefthook_checksums.txt`. `apparatus/Dockerfile`:

```
    && install -m 755 lefthook_1.13.6_Linux_arm64 /usr/local/bin/lefthook
```

Statically linked (`transcripts/lefthook/entry-linkage.txt`). Needs `git` in the box.

**Engine then**: `main` at `01e6760`, built in the box (ReleaseSafe), printing
`sideeye 1.6.0 (trace contract v18)`, binary sha256 `ccb81449…` — not a release. Before that,
the released **v1.5.0** installed by the page's installer (2026-09-21,
`transcripts/lefthook.engine.txt`).

**Refused**:
- `--observe syscalls` (the row's mode): `oracle_missed_operation`, divergence at operation 1 —
  the oracle saw the `openat` that creates `pre-commit`, the shim's account ends after 0
  operations (`2026-09-21-release-path/transcripts/lefthook.txt`, v1.5.0; reproduced
  `2026-09-27-supervised-static/transcripts/lefthook/entry-preflight.txt`).
- `--observe supervised`, with the checker: preflight accepted 5/5 (4 operations), explores
  `checker_not_falsified` 3/3 — the checker accepted a hooks directory whose every file was
  overwritten with junk (`transcripts/lefthook/sup-explore-{1..3}.txt`).
- `--observe supervised`, without the checker (`lefthook-nocheck`): preflight 5/5, explores
  **PASS 3/3** over 4 crash points, judging git's 13 `*.sample` files, which the operation does
  not change (`transcripts/lefthook-nocheck/`).

**Form chosen**: without the checker, the last define that run used for this target (RESULTS.md,
"Three defines corrected after their result"). The checker form is this toml plus
`check = "/ap/defines/lefthook/check.sh"` (then `chmod 755 check.sh` is needed; `/ap` is mounted
read-only, so set it on the host).

**Changed from the original**:
- paths: `/tmp/lh-repo` → `/s/lefthook/lh-repo` (state and `cwd` moved with it). The operation
  carries no path.
- `--setup /ap/lefthook/seed-state.sh` is folded into `seed.sh` (same commands). The 2026-09-27
  run also ran it once before the engine so that `cwd` exists; here `run.sh`'s seed does that.
- `LH_REPO` / `LH_HOOKS` are no longer exported; `check.sh` keeps the `${LH_HOOKS:-…}` default,
  now pointing at the moved path.
