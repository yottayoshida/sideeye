# 2026-10-31 — the `--observe syscalls` verdicts, measured again under `--observe supervised` (#938)

`--observe syscalls` is the only observation mode that changes how the target behaves (a
process whose `SIGSYS` is blocked dies), and the question is whether it still earns its place
beside `supervised`. This record answers the half that can be measured: what `supervised` says
about every target whose verdict on `docs/target-classes.md` only `syscalls` reached.

## The rows, counted before anything ran

Read off `docs/target-classes.md` at `651ad406` (v1.17.0's pin merge), from its first table,
"Measured, with verdicts" — the page's supported classes. A row is in scope when its "What
happened" cell holds a verdict (**PASS** or **FAIL**) and the word `syscalls` appears anywhere
in the row: 23 rows. They split three ways. Rows below the first table that reach a verdict
only under `syscalls` — 320 Bun, 325 mlr, 326 cargo, 327 metaflac and fontforge, 340 pyenv —
are outside the supported classes by the page's own rule and are not counted.

**(a) The verdict was reached only under `syscalls` — 14 rows, all measured here.** The row
records a verdict under `syscalls` and none under another mode:

| Row | Target | Recorded in |
|---|---|---|
| 59 | zstd (worker threads, one writing) | `spike/followup-item4/` |
| 86 | todo.txt-cli 2.14.0 | `spike/dogfood/2026-09-22-shipped-v160/` |
| 128 | podman 5.4.2 `system connection default` | `spike/dogfood/2026-10-03-user-data/` |
| 130 | SolveSpace 3.2 `solvespace-cli regenerate` | `spike/dogfood/2026-10-05-user-data-2/` |
| 156 | skopeo 1.18.0 `logout` | `spike/dogfood/2026-10-05-user-data-2/` |
| 163 | ntfs-3g 2022.10.3 `ntfslabel` | `spike/dogfood/2026-10-05-user-data-2/` |
| 185 | ziptool (libzip 1.11.4) `delete` | `spike/dogfood/2026-10-07-user-data-3/` |
| 188 | alacritty 0.17.0 `migrate` | `spike/dogfood/2026-10-07-user-data-3/` |
| 189 | zsh-z 2.0.1 `zshz --add` | `spike/dogfood/2026-10-07-user-data-3/` |
| 192 | acme.sh 3.1.6 `--set-default-ca` | `spike/dogfood/2026-10-07-user-data-3/` |
| 252 | zstd 1.5.7 `--rm`, single-threaded, a checker on the data | `spike/dogfood/2026-10-09-followups-3/` |
| 278 | shadow-utils 4.17.4 `useradd --prefix` | `spike/dogfood/2026-10-14-mechanisms/` |
| 281 | isync 1.5.1 `mbsync` | `spike/dogfood/2026-10-14-mechanisms/` |
| 282 | dpkg 1.22.22 `update-alternatives --install` | `spike/dogfood/2026-10-14-mechanisms/` |

**(b) A verdict under another mode too — 6 rows.** Their verdict does not depend on
`syscalls`, so they say nothing about retiring it. 97 helm already carries a `supervised`
verdict: its own FAIL is one, and its `syscalls` mention is the unmerged helm/helm#32716 build.
The other five carry none and were **not measured here**: 44 mogrify (verdicts under both
`wrappers` and `syscalls`), 76 markdownlint-cli, 77 google-java-format, 78 xz and 79 aws-cli
(three runs under `wrappers` and one under `syscalls` each). Their boxes are gone, and the
owner ruled on 2026-10-31 that #938 closes on the 14 rows of (a) without them.

**Out of scope — 3 rows** whose `syscalls` appears only as a refusal on the way to a
`supervised` verdict: 87 busybox-static, 270 easy-rsa, 301 Salt.

(a) and (b) together are the 20 rows #938 counted at v1.15.0 (`23b5f9fe`): the same rule
applied to that commit's first table gives 22 rows, these 20 plus busybox and easy-rsa; Salt's
row did not exist yet.

## How each row is run

`apparatus/targets.tsv` names, for each (a) row, the image its record built and still on this
machine, and the define its record ran. Every target is explored twice in boxes of its own
(`apparatus/explore.sh`): under `--observe syscalls`, then under `--observe supervised`, both
with the **released v1.17.0** `aarch64-linux` tarball mounted at `/se`, `--config` on the
record's own `sideeye.toml`, `--oracle /usr/bin/strace`, privileged with a private cgroup
namespace (supervised's containment, ADR 0089) and no network. The `syscalls` run is the
control: same engine, same image, same tool build, so the two columns differ by mode alone,
and a row whose `syscalls` result here differs from the page's is a drift to name, not a mode
difference.

Two rows had no image left. Row 59's record (`spike/followup-item4/run.sh`) explored zstd from
flags; its setup, operation and checker are copied into `apparatus/item4/defines/zstd/` and run
in `sideeye-fu3-1009`, whose zstd is the same Debian trixie package. Row 86's todo.txt-cli 2.14.0
is the release tarball the record's Dockerfile fetched
(sha256 `71a703ec…7efb873d`), mounted at `/opt/todo` in `sideeye-ud1007`.

The host is Apple silicon: every run is `aarch64` Linux. The tool versions are the images'; a
row whose page names another version says so in RESULTS.md.
