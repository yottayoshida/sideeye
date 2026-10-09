# Predictions — 2026-10-09 follow-ups

Written before any of these runs, while the box was building. Each line: the target, what this run
will do, and the predicted answer with the reason.

| target | run | prediction | why |
|---|---|---|---|
| neovim v0.12.5 `:wshada` (control) | 2026-09-16's scratch define with checker v2, the page's path | **FAIL** on the checker | the release neovim#41940 was measured on: `os_remove(main.shada)` before the rename |
| neovim nightly (v0.13.0-dev-1824, 48 commits past `1dc9728dbd`) | the same define | **PASS** | the fix "do not remove destination file before rename" leaves the old file in place until `rename` replaces it |
| PyMOL 3.1.0 (Debian) `save` of a `.pse` (control) | 2026-10-05's define | **FAIL** | the build pymol-open-source#520 was measured on: `open(..., "wb")` before the write |
| PyMOL master `edcda80f3a` (PR #521) | the same define | **PASS** | `_write_file_atomic`: a temporary in the same directory opened `xb`, written, `os.replace`d over the session; no `fsync`, which a kill does not need |
| DwarFS 0.15.8 `mkdwarfs --recompress -f -i X -o X` (control) | a plain run, no Sideeye | `X` at **0 bytes** | dwarfs#388's finding: `open_output_binary` truncates `X` before reading it |
| DwarFS `mhx/work` at `f7689c9a20` | the same plain run | **refuses**, `X` intact and readable by `dwarfsck` | `fix(mkdwarfs_main): refuse to overwrite input filesystem` (`fe09fbbc05`) |
| Kvantum 1.1.4 `kvantummanager --set` | `--observe supervised` named (2026-10-07's roswell probe) | **UNKNOWN `unresolvable_path`** again | the write goes to an `O_TMPFILE` that has no name until it is linked; counting from outside does not give it one |
| Hydrogen 1.2.2 `h2cli -u` | the same | **UNKNOWN `unresolvable_path`** | the same Qt save |
| yarn 4.18.1 `config set` | the same | **UNKNOWN `multiple_threads_detected`** | Node's writers are unordered threads; supervised keeps a threads refusal of its own |
| trash-cli 7.2.0 `trash` | the same | **UNKNOWN `multiple_threads_detected`** | the same |

## Added after the first ten ran (the recount of what could still be measured, before these two ran)

The 47 targets since 2026-10-03 with no verdict in any campaign were read against what v1.9.0 and
v1.10.0 changed. No wall they met was relaxed: #706 warns and runs nothing differently, #688 says
where two runs differ, #689 refuses a shared mapping on every path. Two remained measurable now:

| target | run | prediction | why |
|---|---|---|---|
| Home Assistant 2026.10.0 `hass --script auth change_password` | the page's path, then `--observe supervised` named | page: **UNKNOWN `unresolvable_path`** (trace-closed-by-target) again; supervised: **UNKNOWN `multiple_threads_detected`** | 2026-10-05's refusal was the target closing the shim's trace descriptor, which supervised has none of (roswell's way past); but the auth store is saved from Home Assistant's executor thread while the event loop runs on another |
| dotter 0.13.5 `deploy -f -y` (the same build as 2026-10-03) | the page's path | **UNKNOWN `kill_did_not_land`** again under supervised | nothing in v1.9.0 or v1.10.0 touched how a kill lands; 2026-10-03 left the cause unmeasured, and the restore's mode bits (#678) are as likely as a varying sequence |

flatpak and ostree are not re-run: both refuse an unlinked-fd write (Qt's and glib's `O_TMPFILE`), the
shape Kvantum and Hydrogen kept under supervised above.
