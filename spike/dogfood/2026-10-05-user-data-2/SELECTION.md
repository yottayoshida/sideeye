# Selection — 2026-10-05 user-data-2

The owner's question for this run: **dogfood again in six rounds of five, the targets chosen by the
rules as last time, none at a project this repository has already reported to, and anything headed
upstream only if it is critical, discussed first** ("前回同様"). This file is the selection for all six
rounds; they share one screen, one box and one apparatus, so they are one run directory with one
`RESULTS.md` split by round, and one `RUNS.md` row.

The rules are `spike/cohort4/SCOUT-BRIEF.md`'s 1–17 plus this directory's ordering rule and entry gate
(`../README.md`), read as 2026-10-03 read them — that run is "last time":

- rule 5 strictly: state git does not give back (a keystore, a wallet, notes, a wiki, subtitles, a
  raster, a CAD sketch, a credentials file), **not formatters**;
- rule 11 at 2026-09-28's bar, which 2026-10-03 settled on midway: **at least three of the last ten
  bug reports answered by the project within seven days** (`apparatus/score11.py`, a report whose
  seven days have not run out counted unanswered);
- the owner's instruction to choose by the rules as the sign-off of `PREP.md` §9 step 5 given in
  advance: the slate below was not shown again before the explores.

What this run adds is the engine: **Sideeye v1.8.0**, released 2026-10-03, which names
`--observe supervised` for a statically linked image whether the operation names it by path or bare
(ADR 0090). 2026-10-03 had to name static images by path; here every one is named bare, as a user
writes it.

## The exclusion set, declared before the candidates

- `apparatus/fresh.sh` — 2026-10-03's copy with `mine` pointed at this run's directory and one more
  selftest case: 2026-10-03's own target (`mapshaper`) must read **seen**. Green before the screen.
- Every `owner/repo` in `spike/upstream-reports.tsv` (31) and Artifex (mutool, drafted for its
  Bugzilla on 2026-10-02): not a target, so not a place a second report could go.

## The screen

| pass | names | fresh | seen | transcript |
|---|---|---|---|---|
| 1 — journals, tasks, archives, cloud and image tools | 92 | 28 | 64 | `transcripts/fresh-screen-1.txt` |
| 2 — keystores, system accounts, mail, ML, registries | 86 | 60 | 26 | `transcripts/fresh-screen-2.txt` |
| 3 — the same, by repository name; translations, CAD | 55 | 53 | 2 | `transcripts/fresh-screen-3.txt` |
| 4 — wikis, encrypted volumes, validators, sync | 36 | 30 | 6 | `transcripts/fresh-screen-4.txt` |
| 5 — system-config editors, 2FA secrets | 17 | 14 | 3 | `transcripts/fresh-screen-5.txt` |
| 6 — wallets, env managers, GIS, 3D | 28 | 25 | 3 | `transcripts/fresh-screen-6.txt` |
| 7–23 — spares, as gate walls and vetoes came in | 83 | 69 | 14 | `transcripts/fresh-screen-7.txt` … `-23.txt` |

397 names as written over twenty-three passes, 359 distinct strings — some tools screened under both
their command and their repository (`ethkey`, `go-ethereum`). The match is `fresh.sh`'s, loose on
purpose, and two readings were added to it, each recorded in the transcript beside the hit:

- **A seen parent is a seen tool.** `ebook-meta` (calibre), `ogr2ogr` (GDAL), `ansible-vault` (ansible),
  `operon` (quodlibet/mutagen), `zopflipng` (zopfli) came back fresh by their own names and seen by
  their project's: they are out.
- **A hit inside another word is read, not counted.** `geth` (in "together"), `jump` (in z.lua's
  "Directory-jump database"), `ouch` ("touched"), `llm` ("cargo's LLM-usage policy") and `juju`
  ("Jujutsu", five times) matched no ledger line about the tool; each was then screened by its
  repository name too, and read fresh. `proto` ("the bob/proto reason" — moonrepo/proto, met by cohort
  4) and `dvc` (in the release-path run's list of met names) did match the tool: out.

Rules 1 and 2 (≥1,000 stars; a push since 2026-04-05, not archived), by `gh api repos/<r>`
(`apparatus/stars.sh`, `transcripts/stars-*.txt`), and rule 11 by `apparatus/rule11.sh`
(`transcripts/receipts/rule11-*.txt`). Where the default bug labels found fewer than ten reports, the
project's own bug label was looked up and the receipt re-taken (`rule11-relabel.txt`): foundry
(`T-bug`), systemd (`bug 🐛`), FreeCAD (`Type: Bug`), vercel (`triaged: bug`), mamba (`type::bug`),
wandb (`ty:bug`), buildpacks (`type/bug`), golang/go (`BugReport`, `rule11-bug-reports-23.txt`); with none, the last ten issues of any label (cosmos-sdk,
granted, ntfs-3g, nbdime, prysm, wp-cli/config-command).

### Out before the box, each with its reason

| name | rule | measurement |
|---|---|---|
| ultralist (952), linode-cli (442), civo (208), shadow (402), Leanify (853), Efficient-Compression-Tool (746), heroku/cli (889), railway (622), comictagger (837), optimizt (185), go-pmtiles (604), netplan (849, issues off), kanbn (45), e2fsprogs (481), wakatime-cli (460), azure-dev (570), comtrya (605), rimage (421) | 1 | stars below 1,000 |
| 2fa, hostctl, autojump, imap-backup, saml2aws, aws-sso-util, lftp, kubeswitch, dendron, httpie, dotenv-linter, meshio, devpod, ossutil, timetrace, tidwall/jj (also issues off) | 2 | last push before 2026-04-05 |
| sc0ty/subsync, kimi-cli, xsv, minio/mc, localstack | 2 | archived |
| foundry 2/10, systemd 0/10, FreeCAD 1/2, mlflow 2, cosmos-sdk 0/8, simonw/llm 1, salt 0, puppet 0, VeraCrypt 1, flyctl 0, go-containerregistry (crane) 1, granted 0, supabase 1, mamba 2, jupyterlab 1, nbdime 1, agave 0, BentoML 0, pixi 1, prysm 2/8, prefect 0, sq 0, tanka 2, spack 0, arduino-cli 2, vfox 2, crc 0/1, buildpacks 0, kubescape 1, modelcontextprotocol/python-sdk 0, fastmcp 2, angular-cli 2, cosign 1 | 11 | fewer than three of the last ten bug reports answered within seven days |
| dijo, k9s, kubie, lazygit, gitui | 4/8 | an interface, not a command (TUI, or a spawned shell) |
| pdftk, fiona, qsv, darktable, rawtherapee | 15 | write a new output; nothing that exists before the operation changes |
| zpaq | 7 | its own journalling archive is the store |
| pixz, vultr-cli, eksctl, k3d, lieer, signal-cli, subliminal | 8 | no offline mutating command (network or a container daemon), or read-only config |
| immich, photoprism, osxphotos, mblaze, prs, ripasso, kpcli, betterbib, biber | 1/4 | servers, macOS only, or below the star floor |
| sui | — | no linux/arm64 release, and a source build of the whole chain is out of this box's reach |
| JabRef | 4 | the latest release (5.15, 2024-07) has no command-line editor; `jabkit` is unreleased |

## The box

`apparatus/Dockerfile`, built by `apparatus/build.sh` in twelve layers as candidates came in
(`transcripts/build-first.txt` … `build-twelfth.txt`): Debian trixie, linux/arm64, Sideeye **v1.8.0
installed by the page's installer** (`install-sideeye.sh v1.8.0`, digest matched). Each tool from its
own latest release for linux/arm64 where one exists; PyPI, npm and RubyGems at the version their
registry called latest on 2026-10-05; built from the latest tag where the release has no arm64 asset
(gltfpack from meshoptimizer v1.3, solvespace-cli v3.2, toybox 0.8.14, xmake v3.1.1; goi18n and jump
by `go install` at their tags). From Debian, named as such: firewalld, skopeo, ntfs-3g and pymol
(3.1.0, upstream's latest tag). Node 22 from nodejs.org, because wrangler refuses trixie's Node 20;
Python 3.14 from uv's standalone builds for homeassistant only. go 1.27.1 from go.dev, its digest checked
against go.dev's own listing, ahead of trixie's go 1.24.4 (which built goi18n and jump).

Five apparatus errors are kept. The first build's npm loop wrote each log to `/tmp/npm-<package>.log`
and the scoped `@google/gemini-cli` put a `/` in that path, so npm never ran for it; it was installed in
a later layer. Versions for the PyPI and npm pins were first written from memory and every one was
wrong (basic-memory 0.15 against 0.23.2, and so on); they were replaced by the registries' answers
before any build ran — and the same slip recurred for conan and platformio, caught before their build.
The fourth: go's records were written under three names already in use — `build-thirteenth.txt`
(aliyun-cli's build), `plain-runs-13.txt` and `entry-candidates-14.txt` (firebase-tools'). go's are now
`build-sixteenth.txt`, `plain-runs-16.txt` and `entry-candidates-17.txt`; firebase-tools' plain run and
gate were run again into their old names, each with a first line saying so, and gave the first result again
(`child_touched_state_dir`). aliyun-cli's build log is lost; its layer shows as cached in every later build.
The fifth: juju's and aliyun-cli's seeds wrote fake keys in AWS's and Alibaba Cloud's key-ID shapes, the
shape a 2026-09-16 run had already been stopped by push protection for. They were replaced, before anything
was pushed, by same-length strings no scanner matches, and both targets were gated and explored again with
them (`entry-candidates-18.txt`, `explore-batch-10.txt`, the aliyun-cli probe, `lab-17.txt`,
`write-paths-pass.txt`): the same rows and verdicts, operation for operation.

## Plain runs, then the entry gate

Each operation was first found by running the tool by hand in the box (`transcripts/lab-1.txt` …
`lab-17.txt`), then run once plainly from its seed (`apparatus/plain.sh`, `transcripts/plain-runs*.txt`).
The gate is `apparatus/entry.sh`, 2026-10-03's copy with one more mapping row — v1.8.0's `next` naming
`--observe supervised` — and run through `apparatus/gate-run.sh`, a pinned define in a box of its own.
A command string splits on spaces with no quoting (`docs/cli.md`), so no argument carries a space.

Candidates that never reached the gate, for a reason found by running them:

| name | why |
|---|---|
| go-ethereum `geth account update` | its help gives `--password` as the non-interactive form; after the subcommand the flag is undefined, and before it the old password is read and the new one asked on a terminal (`lab-2.txt`) |
| git-credential-manager `store` | reads the credential from stdin, which a define gives EOF (`docs/cli.md`) |
| micro `-clean` | asks `Continue [Y/n]` on stdin and stops at EOF |
| serverless 4.43.0 `config credentials` | v4 resolves its engine over the network at run time: `No version found` |
| oh-my-posh `config migrate` | 31.4.1 has no such command (`dsc` and `export` only) |
| stack `config set` | reached for the network and wrote nothing |
| meltano 4.4.0 | settings commands address plugins, and adding a plugin needs the network |
| lima `limactl edit --set` | refuses to run as root; its static image needs supervised, which needs the engine's root |

| candidate | version | language | gate | why |
|---|---|---|---|---|
| aliyun-cli `configure delete` | 3.5.1 | Go | 0 SUPERVISED | accepted, 6 operations |
| azure-cli `config set` | 2.90.0 | Python | 0 | accepted, 24 operations |
| conan `remote disable` | 2.33.0 | Python | 0 | accepted, 4 operations |
| crictl `config --set` | 1.37.0 | Go | 0 SUPERVISED | accepted, 2 operations |
| DokuWiki `dwpage.php commit` | 2026-07-14c | PHP | 0 | accepted, 30 operations |
| python-dotenv `set` | 1.2.4 | Python | 0 | accepted, 3 operations |
| dynaconf `write toml -s` | 3.3.5 | Python | 0 | accepted, 2 operations |
| ffsubsync `--overwrite-input` | 0.5.1 | Python | 0 | accepted, 2 operations |
| ggshield `config set` | 1.55.0 | Python | 0 | accepted, 5 operations |
| gita `rename` | 0.16.8.2 | Python | 0 | accepted, 6 operations |
| gltfpack `-i x -o x` | meshoptimizer v1.3 | C++ | 0 | accepted, 2 operations |
| go `env -w` | 1.27.1 | Go | 0 SUPERVISED | accepted, 2 operations |
| goi18n `merge` | 2.6.1 | Go | 0 SUPERVISED | accepted, 4 operations |
| huggingface_hub `hf auth logout` | 2.1.1 | Python | 0 | accepted, 7 operations |
| i18n-tasks `add-missing` | 1.1.2 | Ruby | 0 | accepted, 4 operations |
| juju `remove-credential --client` | 3.6.29 | Go | 0 SUPERVISED | accepted, 4 operations |
| juliaup `config` | 1.22.7 | Rust | 0 SUPERVISED | accepted, 58 operations |
| jump `clean` | 0.69.0 | Go | 0 SUPERVISED | accepted, 12 operations |
| k8sgpt `auth remove` | 0.4.39 | Go | 0 SUPERVISED | accepted, 3 operations |
| kaggle `config set` | 2.2.4 | Python | 0 | accepted, 2 operations |
| kubeadm `config migrate` | 1.37.1 | Go | 0 SUPERVISED | accepted, 2 operations |
| lighthouse `account validator modify` | 8.2.3 | Rust | 0 | accepted, 7 operations |
| nerdctl `logout` | 2.4.1 | Go | 0 SUPERVISED | accepted, 3 operations |
| ntfs-3g `ntfslabel` | 2022.10.3 (Debian, = upstream) | C | 0 FOLLOW | `oracle_missed_operation`, the next step names `--observe syscalls` |
| opam `option` | 2.6.0 | OCaml | 0 SUPERVISED | accepted, 5 operations |
| oras `logout` | 1.3.4 | Go | 0 SUPERVISED | accepted, 3 operations |
| platformio `settings set` | 6.2.0 | Python | 0 | accepted, 4 operations |
| PyMOL `save` (.pse) | 3.1.0 (Debian, = upstream tag) | C++/Python | 0 | accepted, 2 operations |
| rasterio `rio edit-info` | 1.5.2 | Python/C | 0 | accepted, 5 operations |
| regctl `registry set` | 0.11.6 | Go | 0 SUPERVISED | accepted, 5 operations |
| sheldon `add` | 0.8.5 | Rust | 0 SUPERVISED | accepted, 2 operations |
| skopeo `logout` | 1.18 (Debian) | Go | 0 FOLLOW | `oracle_missed_operation`, the next step names `--observe syscalls` |
| solvespace-cli `regenerate` | 3.2 (tag build) | C++ | 0 FOLLOW | `oracle_missed_operation`, the next step names `--observe syscalls` |
| stripe-cli `config --set` | 1.53.0 | Go | 0 SUPERVISED | accepted, 5 operations |
| tenv `tf constraint` | 4.15.1 | Go | 0 SUPERVISED | accepted, 2 operations |
| toybox `sed -i` | 0.8.14 | C | 0 | accepted, 9 operations |
| turbo `telemetry disable` | 2.11.7 | Rust | 0 SUPERVISED | accepted, 2 operations |
| uv `auth logout` | 0.12.23 | Rust | 0 | accepted, 5 operations |
| velero `client config set` | 1.18.4 | Go | 0 SUPERVISED | accepted, 2 operations |
| wandb `offline` | 0.30.0 | Python | 0 | accepted, 4 operations |
| wp-cli `config set` | 2.12.0 | PHP | 0 | accepted, 3 operations |
| wrangler `telemetry disable` | 4.147.0 | JS | 0 | accepted, 3 operations |
| yt-dlp `--download-archive` | 2026.8.19 | Python | 0 | accepted, 2 operations |
| basic-memory `tool edit-note` | 0.23.2 | Python | **1** | wall: multiple_threads_detected |
| codex `mcp add` | 0.160.0 | Rust | **1** SUPERVISED | wall: multiple_threads_detected |
| firebase-tools `experiments:disable` | 15.32.1 | JS | **1** | wall: child_touched_state_dir |
| firewalld `firewall-offline-cmd` | Debian | Python | **1** | wall: unsupported_syscall_observed |
| astropy `fitscheck -w` | 8.0.1 | Python | **1** | wall: unsupported_syscall_observed |
| gemini-cli `mcp add` | 0.62.0 | JS | **1** | wall: multiple_threads_detected |
| glTF-Transform `weld` | 4.5.1 | JS | **1** | wall: multiple_threads_detected |
| Home Assistant `--script auth` | 2026.9.4 | Python | **1** | wall: unresolvable_path |
| infracost `configure set` | 0.10.46 | Go | **1** SUPERVISED | byte-repeatability: --twice found different bytes |
| lingui `extract` | 6.9.0 | JS | **1** | wall: multiple_threads_detected |
| monero-wallet-cli `set_description` | 0.18.5.1 | C++ | **1** | byte-repeatability: --twice found different bytes |
| steamguard-cli `decrypt` | 0.18.4 | Rust | **1** | wall: multiple_threads_detected |
| vercel `telemetry disable` | 62.2.0 | JS | **1** | wall: multiple_threads_detected |
| xmake `g` | 3.1.1 | Lua/C | **1** | byte-repeatability: --twice found different bytes |

57 defines went through the gate (`transcripts/entry-candidates*.txt`, seventeen runs as candidates came in;
each row is the define's last run). Four rows changed between runs, each a define fix the gate's own
`next` step asked for: wrangler and monero were re-run with the clock pinned (wrangler then cleared;
monero's wallet cache still differed); azure-cli with `AZURE_LOGGING_ENABLE_LOG_FILE=no`, after each run
had written a command log named by its pid; regctl with its `expected_status` written as the quoted
string `docs/cli.md` gives — unquoted, the gate's flags accepted it and `explore --config` refused it at
setup (`transcripts/explore/regctl-setup-error-unquoted-status/`). Each gate run overwrote the define's
files in `transcripts/entry-out/entry/`, so the unpinned runs' preflight texts survive only as the rows in
`entry-candidates.txt` and `entry-candidates-2.txt`.

## The receipts (rules 11 and 14)

Rule 11 per candidate: `transcripts/receipts/rule11-bug-reports*.txt` and `rule11-relabel.txt`, scored
by `apparatus/score11.py`.

The novelty pre-scan (`spike/cohort4/novelty-prescan.sh`) ran one tracker at a time
(`apparatus/prescan-all.sh`, log `transcripts/prescan-log.txt`), controls green in every transcript that
is not kept as `.broken` or `.stopped`. Reading it is the one question of rule 14 — is this operation's
write shape on the tracker — and `apparatus/prescan-read.py` only lists the titles that name a write
shape; **every veto below was decided from the issue's or pull request's body**, after one was first
decided from a title and was wrong (stripe-cli, below).

Explores were started by `apparatus/explore-after-scan.sh` as each target's scan ended, so a scan always
started before its explore and the veto reading came from the tracker's text alone. The readings
themselves came after some explores; a target vetoed after its explore leaves the slate with its result
kept (`RESULTS.md`, "Explored, then out of the slate").

Vetoes (rule 14), each this operation's file and write shape:

| target | the tracker's text |
|---|---|
| DokuWiki `dwpage.php commit` | `#677` pages saved empty when the disk filled; `#1303` `users.auth.php` replaced by a zero-byte file, fixed with a write-new-then-rename |
| lighthouse `validator modify` | `#2338` (closing `#2159`) writes `validator_definitions.yml` through a temporary file and a rename, "to avoid truncating the primary file" |
| jump `clean` | `#9` `scores.json` malformed on a full disk, `#10` atomic writes to fix it |
| ntfs-3g `ntfslabel` | `#104` an NTFS volume corrupted by an interrupted write; the label is an in-place write to the same volume through the same library |
| huggingface_hub `auth logout` | `#5013` `stored_tokens` opened `O_TRUNC` and left at 0 bytes by a failed write (its fix, `#5021`, changed the encoding only) |
| opam `option` | `#4157` configuration emptied on `ENOSPC`, `#5489` "make all writes atomic" |
| juliaup `config` | `#1221` `juliaup.json` at 0 bytes after a quota error, `#1295` makes its save atomic |
| python-dotenv `set` | `#713` (open) no `fsync` before the rename; `#721` |
| azure-cli `config set` | `#34060` (open, fixing `#9427`) the session files `_session.py` writes with `'w'`, rewritten by this same run |
| ggshield `config set` | `#1243` (open) the truncate-in-place writes of `core/config/utils.py`, through whose `save_yaml_dict` `config set` saves |
| aliyun-cli `configure delete` | `#1387` (merged July) writes `config.json` through a temporary file and a rename |

Read and not a veto, each named here because a title looked like one: stripe-cli `#1109` (its "atomic"
is read-modify-write in viper, read from the body after the title had first been taken as a veto and the
target dropped; it came back), sheldon `#111` (the editor's temporary file left by an interrupted `edit`;
`add` writes through `fs::write`), skopeo (every "atomic" hit is Project Atomic), nerdctl `#4324` (its own
state files; `logout` saves through docker/cli's `configfile`), regclient `#18` (memory aliasing), conan
(`#20055` a user's syntax error; the atomic-replace PRs are package downloads), wp-cli `#1887`, gita `#2`,
cri-tools `#605` (comments dropped, not a write cut short), kaggle `#397`, solvespace `#249` and `#1778`,
rasterio `#2414`, platformio `#5473`, juju `#23400`, workers-sdk `#15089`.

**One more exclusion, found after the explores: `fresh.sh` does not read cohort 4's rejected candidates.**
Searching every fresh name in `spike/cohort4/` (`apparatus/cohort4-recheck.sh`,
`transcripts/cohort4-recheck.txt`) found ffsubsync and ggshield there, both rejected on rule 5; the other
hits were other words (`microsoft`) or another row's text (`yt-dlp`). ffsubsync left the slate as seen;
ggshield was already out. `fresh.sh` now reads that file (`cohort4-rejected`, with a note that this run's
screen ran without it).

**And one the screen never asked: uv.** It was screened as `uv-cli`, because `uv` alone is a substring of
half the repository, and `uv-cli` is a spelling no ledger carries — so the screen answered a question
nobody asked. The 2026-09-05 selection had turned uv away on rule 5 (`b2-exclusions.txt` already carried it
as `read`); it was found while writing the ledger rows, after its explore. Every name on the slate was then
searched again as a whole word across `spike/` and `docs/` (`apparatus/word-recheck.sh`,
`transcripts/word-recheck-slate.txt`) — `fresh.sh` answers with the first substring hit only, which is how
`libuv` stood in front of uv and `dotenvx` in front of tenv. uv was the only tool met before; the other
hits were `libjpeg-turbo`, `Jujutsu` and cohort 4's `yt-dlp` sentence. uv left the slate with its explore
kept, and go was screened for its place (`fresh-screen-23.txt`, `word-recheck-23.txt`: composer, skaffold,
conda, npm, pnpm, eyeD3 and metaflac had been met; doppler is below the star floor; `gh`, met on
2026-09-27, was found the same way). golang/go's scan finished clean before go's explore, and its reading
found no veto: no title names `go env -w`'s write (`#8984` is gofmt on `ENOSPC`, `#45208` the
installers).

**The order did not hold twice, both on the last two trackers.** `explore-after-scan.sh` waited for a
`prescan end` line without reading its exit status. turborepo's first scan ended rc=2 (it could not
measure), so turbo's explore started before the re-run; kubeadm's scan was started by a waiter with the
same fault, ran beside turborepo's re-run, and both broke on the search rate limit — kubeadm's explore
started on that rc=2 line too. Both were scanned again, alone, and finished clean (06:35 and 06:41); their
readings found no veto (turborepo `#1508` is remote-cache configuration, kubeadm `#1232` an HA set-up
followed wrongly). The script now waits for rc=0.
It was edited while an instance was running, and that instance stopped on a syntax error after its last
explore had finished (`transcripts/explore-batch-8.txt`).

Three queued scan loops also never started: each waited on `pgrep -f prescan-all.sh`, which matched its
own command line. They were stopped and the trackers run as one loop.

## The slate — six rounds of five

The first three vetoes (DokuWiki, lighthouse, jump) were replaced by candidates screened for the purpose
(dynaconf, conan and platformio, tenv). From then on spares cleared the gate before they were needed and
were promoted in an order written down before any of them was explored (crictl, k8sgpt, ggshield, uv,
juju, aliyun, turbo, kubeadm, extended as each cleared): hf → crictl, opam → k8sgpt, juliaup → ggshield,
python-dotenv → uv, azure-cli → juju, ggshield → aliyun, ffsubsync → turbo, aliyun → kubeadm; and,
with the spares spent, uv → go, screened for the purpose.
stripe-cli's veto, withdrawn, had promoted one spare more, and the last one promoted, juju, went back to
the head of the spares until azure-cli's veto. Ordered by coverage, not by expected yield (rule 14's last
paragraph): the thirteen Go targets two per round and three in round 4, so no round is one language
(rule 13).

| round | targets |
|---|---|
| 1 | solvespace (C++), wp-cli (PHP), rasterio (Python/C), goi18n (Go), juju (Go) |
| 2 | PyMOL (C++/Python), i18n-tasks (Ruby), dynaconf (Python), stripe-cli (Go), tenv (Go) |
| 3 | gltfpack (C++), wrangler (JS), kaggle (Python), velero (Go), crictl (Go) |
| 4 | toybox (C), go (Go), gita (Python), k8sgpt (Go), kubeadm (Go) |
| 5 | sheldon (Rust), yt-dlp (Python), conan (Python), skopeo (Go), regctl (Go) |
| 6 | turbo (Rust), wandb (Python), platformio (Python), nerdctl (Go), oras (Go) |

No checkers: the built-in atomicity rule judges, as on 2026-10-03.
