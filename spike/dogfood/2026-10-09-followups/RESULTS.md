# Results — 2026-10-09 follow-ups

What could be measured right after the 2026-10-09 user-data-4 run, counted first (the owner's ruling of
2026-10-02 that a dogfood run measures everything it can measure now): three upstream fixes this project
had not re-measured, four walls of that run not yet asked under `--observe supervised`, and one upstream
report closed without a fix whose record still said it was awaiting a reply. Released **v1.10.0**,
installed by the page's installer, in one box (`apparatus/Dockerfile`, `transcripts/build.txt`; the first
build linked the bash-completion file named `mkdwarfs` instead of the binary, `build-first.txt`).
`PREDICTIONS.md` was committed before each run (`63648a7`, `d03c9f8`, `b57dc0e`); **13 of its 14 predictions held**,
the miss is Home Assistant's below.

## Upstream fixes, each beside the build its report was measured on

| report | build | verdict | where |
|---|---|---|---|
| neovim/neovim#41940 | v0.12.5 (the release measured on 2026-09-16) | **FAIL** 2/13, crash point 4 of 12, on the checker | `unlink` of `main.shada`, and the kill before `main.shada.tmp.a` is renamed in: `main.shada` absent (142 bytes before), the new one whole beside it. 2026-09-16's define: checker v2, falsified before the run, `main.shada` scratch. Replayed twice |
| | nightly v0.13.0-dev-1824+g27ee55c09d (48 commits past the fix `1dc9728dbd`, "do not remove destination file before rename") | **PASS** 11/11, the checker in every world | 10 operations where v0.12.5 has 12 |
| schrodinger/pymol-open-source#520 | PyMOL 3.1.0 (Debian, the build measured on 2026-10-05) | **FAIL** 1/3, crash point 2 of 2 | `model.pse` opened `O_TRUNC` and the kill before its write: 6,078 → 0 bytes. Replayed twice |
| | master `edcda80f3a` (the merge of PR #521), built with pip | **PASS** 4/4 | `_write_file_atomic`: a temporary created `xb` beside the session, written, `os.replace`d over it; no `fsync` |
| mhx/dwarfs#388 | 0.15.8 (the release measured on 2026-10-03) | a plain run, no Sideeye: `mkdwarfs --recompress -f -i X -o X` exits 1 and **`X` is 0 bytes**; `dwarfsck` finds no filesystem | the finding as filed |
| | the `mhx/work` CI build at `f7689c9a20`, 10 commits past the fix `fe09fbbc05` (artifact 11445581881, digest matched) | the same run exits 1 with "refusing to overwrite input file system", **`X` intact** (2,109 bytes) and read whole by `dwarfsck` | the fix is on the `mhx/work` branch, not on `main` or in a release yet |

`transcripts/followups.txt` has every line; the engine's reports are in `transcripts/explore/`.

## The walls, asked under `--observe supervised` by name

As 2026-10-07 asked it of roswell, whose `unresolvable_path` gave way to supervised (`apparatus/probe-supervised.sh`).
None gave way here:

| target | supervised |
|---|---|
| Kvantum 1.1.4 `kvantummanager --set` | **UNKNOWN `unresolvable_path`** — "unlinked-fd write fd:5": Qt's `O_TMPFILE` has no name for the supervising engine either |
| Hydrogen 1.2.2 `h2cli -u` | **UNKNOWN `unresolvable_path`**, the same |
| yarn 4.18.1 `config set` | **UNKNOWN `multiple_threads_detected`** — tid 27 opened `.yarnrc.yml`, tid 28 wrote it, nothing recorded orders them |
| trash-cli 7.2.0 `trash` | **UNKNOWN `multiple_threads_detected`** — two threads made the trash's directories |

So roswell's way past (a static parent whose dynamic child supervised can count) is not a way past these:
an unnamed file and unordered writer threads are refused in both modes.

## The record moved without a run

`mbloch/mapshaper#706` was closed by its owner on 2026-10-07 as `wontfix` ("This failure mode has never
been reported in actual use … and the proposed solution (writing to temp files and renaming) has
downsides"). The 2026-10-03 row moves from `awaiting` to `declined`. Nothing to reply to: the owner closed
it, and the report had said closing it was fine.

## The recount, and the two it left

After those ran, the 47 targets that no campaign since 2026-10-03 had carried to a verdict
(`spike/outcome-funnel.tsv`) were read against what v1.9.0 and v1.10.0 changed. No wall they met was
relaxed: #706 warns about a shell-spelled string and runs nothing differently, #688 says where two clean
runs differ, #689 refuses a shared mapping on every path, and threads are refused under supervised too
(above). flatpak and ostree refuse an unlinked-fd write, Kvantum's shape. Two were left:

| target | run | result |
|---|---|---|
| Home Assistant 2026.10.0 `hass --script auth change_password` | the page's path | **UNKNOWN `unresolvable_path`** — "trace-closed-by-target", as on 2026-10-05; the next step says refused by design |
| | `--observe supervised` named | **UNKNOWN `baseline_violates_invariant`**, not the threads wall predicted: one thread wrote. The uncrashed re-run left `.storage/auth_provider.homeassistant` different from 175 for 70 bytes, printable text (#688's words) — the password hash's fresh salt; the next step says to declare the path scratch |
| | the store scratch, and a checker: alice logs in with her old or new password and bob with his, through `hass --script auth validate` (`apparatus/defines/homeassistant-check/`) | **PASS** 8/8, the checker falsified before the run and run in all 8 worlds; the store is written through a temporary and a rename |
| dotter 0.13.5 `deploy -f -y`, the build 2026-10-03 measured | the page's path | **UNKNOWN `kill_did_not_land`** under supervised, as on 2026-10-03. Its next step names "a cache kept beside the configuration"; `preflight --twice` found `--state` equal and `.dotter/cache.toml` written beside the configuration, outside it (`transcripts/dotter-twice.txt`) |
| | the configuration moved inside `--state` (`apparatus/defines/dotter-incfg/`) | **FAIL** 12/19, crash point 2 of 18 — `.bashrc` unlinked and the kill before the new one is made. Replayed twice. Not filed: `-f` discards the hand edit by design, and a second `dotter deploy` writes the file again from its template |

**dotter was already settled.** #690's follow-up (`spike/followup-690/NOTES.md`, 2026-10-08) measured the same
cause and the same FAIL 12/19, and `docs/target-classes.md` says so; the funnel's row still read
`explored`, and the recount read the funnel alone. So this is the same result on the released v1.10.0,
not a finding. A recount should read `docs/target-classes.md` and `spike/followup-*` beside the funnel.

What this says about v1.10.0: the next step on `kill_did_not_land` (ADR 0097) names the cause a user can
act on, and `baseline_violates_invariant` now says where and what kind (#688), which is what pointed at
the salt. Both led to a verdict in one step each.
