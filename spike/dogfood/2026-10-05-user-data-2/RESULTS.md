# Results — 2026-10-05 user-data-2

Thirty targets in six rounds of five (`SELECTION.md`) — the rounds are the slate's grouping, not the
order they ran in (`transcripts/explore-batch-*.txt` has the order) — each explored by
`apparatus/run.sh` in a box of its own with **the released v1.8.0** (`apparatus/explore.sh`; engine
lines in `transcripts/explore/<t>/engine.txt`). Default mode first; where the refusal's next step named
`--observe supervised` (a static image, named bare) or `--observe syscalls`, it was followed once. Every
FAIL was replayed twice (both FAIL) and its evidence bundle written. No checkers: the built-in atomicity
rule judges. `apparatus/verdicts.py` prints each line below from the engine's own JSON.

**22 FAIL, 8 PASS.** Twenty-one of the FAILs are one shape — the rewritten file opened truncating
(wp-cli: opened, then `ftruncate`d) and the kill before its write: the file at 0 bytes, the old bytes
nowhere in the state root. The other is rasterio, which rewrites the GeoTIFF in place in several writes;
killed between two, it holds neither its old nor its new bytes. Seven of the eight PASSes write a
temporary file and rename it over the target; yt-dlp appends one line.

Fourteen of the thirty are static images named bare, and every one reached a verdict under
`--observe supervised` through the next step v1.8.0 added for them (ADR 0090). One static image outside
the thirty did not: aliyun-cli, below.

## Round 1

| target | verdict | where | report |
|---|---|---|---|
| solvespace-cli 3.2 `regenerate` | **FAIL** 15/17, crash point 2 of 16 (`--observe syscalls`, the next step) | `part.slvs` opened truncating, killed before its first `write`: 60,318 → 0 bytes. With writes failing (`ulimit -f 0`) it prints `Written '/s/ss/part.slvs'.` and exits 0 on a 0-byte file | **filed, [solvespace/solvespace#1783](https://github.com/solvespace/solvespace/issues/1783)** |
| wp-cli 2.12.0 `config set` | **FAIL** 1/4, crash point 3 of 3 | `wp-config.php` opened without truncating, `ftruncate`d to 0, killed before the `write` (`file_put_contents(..., LOCK_EX)` in wp-config-transformer): 369 → 0 bytes | **filed, [wp-cli/config-command#233](https://github.com/wp-cli/config-command/issues/233)** |
| rasterio 1.5.2 `rio edit-info` | **FAIL** 3/6, crash point 3 of 5 | the GeoTIFF rewritten in place by several `write`s; killed between two, `a.tif` is neither its old nor its new bytes (same length as the old) | not put forward: whether the half-updated file still opens was not measured |
| goi18n 2.6.1 `merge` | **FAIL** 2/5, crash point 2 of 4 (supervised) | `active.ja.toml` truncated, then the kill: 92 → 0 bytes | not filed: translation files live under version control |
| juju 3.6.29 `remove-credential --client` | **PASS** 5/5 (supervised) | `credentials.yaml<n>` created `O_EXCL`, `fsync`ed, renamed | — |

## Round 2

| target | verdict | where | report |
|---|---|---|---|
| PyMOL 3.1.0 `save` (`.pse`) | **FAIL** 1/3, crash point 2 of 2 | `model.pse` opened `O_TRUNC`, killed before its one `write`: 6,078 → 0 bytes. With writes failing it prints the `OSError` and exits 0 | **filed, [schrodinger/pymol-open-source#520](https://github.com/schrodinger/pymol-open-source/issues/520)** |
| i18n-tasks 1.1.2 `add-missing` | **FAIL** 2/5, crash point 2 of 4 | `en.yml` truncated, then the kill | not filed: under version control |
| dynaconf 3.3.5 `write toml -s` | **FAIL** 1/3, crash point 2 of 2 | `.secrets.toml` truncated: 84 → 0 bytes | not filed: secrets a user re-issues (2026-09-28's kubectl reason) |
| stripe-cli 1.53.0 `config --set` | **FAIL** 1/6, crash point 4 of 5 (supervised) | `config.toml` (API keys per profile) truncated: 260 → 0 bytes | not filed: keys a user re-issues |
| tenv 4.15.1 `tf constraint` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `Terraform/constraint` truncated | not filed: a setting rewritten in a line |

## Round 3

| target | verdict | where | report |
|---|---|---|---|
| gltfpack (meshoptimizer v1.3) `-i x -o x` | **FAIL** 1/3, crash point 2 of 2 | `terrain.glb` opened truncating: 3,788 → 0 bytes; with writes failing, `Error saving`, exit 4 | not filed: meshoptimizer's `CONTRIBUTING.md` closes AI-generated issues and may ban repeat submitters |
| wrangler 4.147.0 `telemetry disable` (clock pinned) | **FAIL** 1/4, crash point 3 of 3 | `metrics.json` truncated | not filed: a setting |
| kaggle 2.2.4 `config set` | **FAIL** 1/3, crash point 2 of 2 | `kaggle.json` (username and API key) truncated: 62 → 0 bytes | not filed: a key the user re-issues |
| velero 1.18.4 `client config set` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `config.json` truncated | not filed: a setting |
| crictl 1.37.0 `config --set` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `crictl.yaml` truncated: 136 → 0 bytes | not filed: a setting |

## Round 4

| target | verdict | where | report |
|---|---|---|---|
| toybox 0.8.14 `sed -i` | **PASS** 10/10 (9 crash points) | each file written to a random name in its directory and renamed over it | — |
| go 1.27.1 `env -w` (telemetry off in the seed) | **FAIL** 1/3, crash point 2 of 2 (supervised) | the `GOENV` file truncated: 112 → 0 bytes | not filed: a setting rewritten in a line |
| gita 0.16.8.2 `rename` | **FAIL** 2/7, crash point 3 of 6 | `repos.csv` truncated: 30 → 0 bytes | not filed: a registry `gita add` rebuilds |
| k8sgpt 0.4.39 `auth remove` | **FAIL** 1/4, crash point 2 of 3 (supervised) | `k8sgpt.yaml` (every AI backend's key) truncated: 546 → 0 bytes | not filed: keys a user re-issues |
| kubeadm 1.37.1 `config migrate` onto its input | **FAIL** 1/3, crash point 2 of 2 (supervised) | `kubeadm.yaml` truncated: 1,179 → 0 bytes | not filed: a config file kept beside the cluster, usually under version control |

## Round 5

| target | verdict | where | report |
|---|---|---|---|
| sheldon 0.8.5 `add` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `plugins.toml` truncated (`config.to_path` → `fs::write`) | not filed: a dotfile |
| yt-dlp 2026.8.19 `--download-archive` | **PASS** 3/3 | the archive opened `O_APPEND` and one line written | — |
| conan 2.33.0 `remote disable` | **PASS** 5/5 | `remotes.json.tmp` written and renamed | — |
| skopeo 1.18 (Debian) `logout` | **PASS** 5/5 (`--observe syscalls`, the next step) | `.tmp-auth.json<n>` created `O_EXCL`, `fdatasync`ed, renamed | — |
| regctl 0.11.6 `registry set` | **PASS** 6/6 (supervised) | `config.json<n>` created `O_EXCL` and renamed | — |

## Round 6

| target | verdict | where | report |
|---|---|---|---|
| turbo 2.11.7 `telemetry disable` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `telemetry.json` truncated | not filed: a setting |
| wandb 0.30.0 `offline` | **FAIL** 1/5, crash point 4 of 4 | `wandb/settings` truncated | not filed: a setting |
| platformio 6.2.0 `settings set` (clock pinned) | **FAIL** 1/5, crash point 3 of 4 | `appstate.json` truncated | not filed: a setting |
| nerdctl 2.4.1 `logout` | **PASS** 4/4 (supervised) | `config.json<n>` created `O_EXCL` and renamed (docker/cli's `configfile`) | — |
| oras 1.3.4 `logout` | **PASS** 4/4 (supervised) | `oras_credstore_temp_<n>` created `O_EXCL` and renamed | — |

`transcripts/write-paths-pass.txt` holds each PASS's write path, `transcripts/write-paths-out.txt` those of the
PASSes taken out of the slate, and `transcripts/write-paths-reports.txt` each filed FAIL's, as `strace` printed them (`apparatus/write-paths.sh`).

## Explored, then out of the slate

Their explores ran before the reading that took them out (`SELECTION.md`, "The receipts"); the results
are kept and are not part of the thirty.

| target | verdict | why out |
|---|---|---|
| uv 0.12.23 `auth logout` | **FAIL** 1/6: `credentials.toml` 218 → 0 bytes | met before: the 2026-09-05 selection turned uv away (rule 5). This run screened it as `uv-cli`, a spelling no ledger carries, so the screen never asked about `uv`; found while writing the ledger rows, and go took its place |
| ffsubsync 0.5.1 `--overwrite-input` | **FAIL** 1/3: `movie.srt` 2,500 → 0 bytes; with writes failing, an `OSError` and exit 0 | met before: a cohort-4 candidate rejected on rule 5, in a ledger `fresh.sh` did not read. Filed anyway on the owner's choice, made before this was found: [smacke/ffsubsync#240](https://github.com/smacke/ffsubsync/issues/240) |
| huggingface_hub 2.1.1 `hf auth logout` | **FAIL** 1/8: `stored_tokens` truncated | rule 14: #5013 reported exactly this write; its fix (#5021) changed the encoding, and `_write_secret` still opens `O_TRUNC` |
| ntfs-3g `ntfslabel` | **FAIL** 1/5 (syscalls): the volume image neither old nor new | rule 14: #104, an NTFS volume corrupted by an interrupted in-place write |
| opam 2.6.0 `option` | **PASS** 6/6 (supervised) | rule 14: #4157 and the fix #5489 ("make all writes atomic") |
| juliaup 1.22.7 `config` | **PASS** 59/59 (supervised) | rule 14: #1221 and the fix #1295 |
| python-dotenv 1.2.4 `set` | **PASS** 4/4 | rule 14: #713 (open), no `fsync` before the replace |
| azure-cli 2.90.0 `config set` (clock pinned) | **FAIL** 3/25: `config` truncated, crash point 22 of 24 | rule 14: #34060 (open) — the session files the same run rewrites through `_session.py`'s `'w'` |
| ggshield 1.55.0 `config set` | **PASS** 6/6 — of a file the operation does not write | rule 14: #1243 (open); also a cohort-4 candidate. The judged path was the seeded `.gitguardian.yaml`; `config set` wrote `auth_config.yaml`, absent before, with a truncating `open` (`transcripts/write-paths-out.txt`), and a new path is not judged. A define error |
| aliyun-cli 3.5.1 `configure delete` | **UNKNOWN** `oracle_missed_operation` on the page's path (default, then the `--observe syscalls` it named); **PASS** 7/7 with `--observe supervised` named (`transcripts/probe-aliyun-supervised.txt`) | rule 14: #1387 made this write atomic in July |

## A Sideeye limit the run met: a static image with a dynamic child

aliyun-cli 3.5.1 is statically linked (`file` says so), and its default-mode refusal is not the
`no_shim_marker` that v1.8.0 answers with `--observe supervised`: it is `oracle_missed_operation`, whose
next step names `--observe syscalls`, and syscalls refuses again with no mode named. The cause is a child:
the static `aliyun` runs `/usr/bin/uname` three times (`transcripts/probe-aliyun-exec.txt`), the dynamic
`uname` loads the shim and leaves its marker, and the static parent's writes are then the operations the
shim did not see. With `--observe supervised` named it is judged, PASS 7/7. The other eighteen static
images in this run had no such child and were sent to supervised. lefthook met the same dead end on
2026-10-02 on v1.7.0, and its `install` also starts git, a dynamic child
(`../2026-10-02-unjudged-on-v170/RESULTS.md`); this is the second time, and the first on v1.8.0, whose
new step reaches a static image only when nothing it starts carries the shim.

## What was filed, and how it was decided

The owner asked that only critical findings go upstream and that they be discussed first. Critical was
read as 2026-10-03 read it: the bytes are gone and nothing gives them back — not files under version
control, not credentials a user re-issues, not a setting rewritten in a line. After 26 of the thirty
explores, four findings were put to the owner with that reading; the owner chose all four, then approved
the four texts verbatim:

| finding | why critical | filed |
|---|---|---|
| SolveSpace: a failed save empties the sketch and still reports success; in the GUI that success deletes the autosave (read in the source, not run) | a sketch is the design itself | [solvespace/solvespace#1783](https://github.com/solvespace/solvespace/issues/1783) |
| PyMOL: `save` truncates the session before writing it | a session holds scenes, views and selections the structure files do not | [schrodinger/pymol-open-source#520](https://github.com/schrodinger/pymol-open-source/issues/520) |
| ffsubsync: `--overwrite-input` empties the only copy of the subtitle | the timings a user synced are gone (a downloaded subtitle can be fetched again) | [smacke/ffsubsync#240](https://github.com/smacke/ffsubsync/issues/240) |
| wp-cli: `wp config set` empties `wp-config.php` | the site stops; rebuilding needs the database credentials from elsewhere and new salts | [wp-cli/config-command#233](https://github.com/wp-cli/config-command/issues/233) |

Each was reproduced with no crash before it was written up: `ulimit -f 0` stood in for a full disk, with
`SIGXFSZ` ignored so a C or C++ target meets a failed write rather than a kill, and the tool's output
captured through a pipe (`transcripts/ulimit-repro.txt`; the first two versions of that script recorded
a SolveSpace killed by the signal and every output as empty, because a log *file* cannot be written under
the limit either). Each cites the writer on the project's current `main` — SolveSpace `581f4cb`
(`SaveToFile`, the same lines as the measured `v3.2`), PyMOL `5e8bfca` (`exporting.py`), ffsubsync
`de310ac` (`generic_subtitles.py`), wp-config-transformer `28896ee` (`save()`). Each is within twice its
tracker's median issue length (171, 231, 70 and 299 words; 327, 333, 115 and 388 posted). The texts are
`report-*.md`.

Contribution policies, read before writing: SolveSpace has a `CONTRIBUTING.md` and an issue template and
no AI policy; PyMOL and ffsubsync have bug templates and no AI policy; wp-cli has an `AGENTS.md` for
coding agents and a handbook page on bug reports, neither forbidding tool-assisted reports. **meshoptimizer's
`CONTRIBUTING.md` says AI-generated issues are closed and repeat submissions may be banned**, so gltfpack
was not put forward.

## What this run does not say

- The Debian builds (skopeo, ntfs-3g, pymol) are Debian's; pymol's is upstream's latest tag, and no
  filed FAIL rests on the others.
- No power loss, no torn writes, no concurrent processes.
- rasterio's half-updated GeoTIFF was not opened to see what a reader makes of it.
- turbo's and kubeadm's explores ran before their trackers' scans had finished cleanly
  (`SELECTION.md`, "The receipts"); the clean scans, read afterwards, found no veto.
