# Selection — 2026-10-09 user-data-4

The owner's question for this run: **dogfood again in four waves of five, the targets chosen and the
upstream reports decided as before** ("sideeye dogfooding 5app x 4wave、対象選定やupstream報告基準はこれまでと同じ").
As on 2026-10-07, the four waves share one screen, one box and one apparatus, so they are one run
directory with one `RESULTS.md` split by wave, and one `RUNS.md` row.

The rules are `spike/cohort4/SCOUT-BRIEF.md`'s 1–17 plus this directory's ordering rule and entry gate
(`../README.md`), read as 2026-10-05 and 2026-10-07 read them:

- rule 5 strictly: state git does not give back, **not formatters**;
- rule 11 at 2026-09-28's bar: **at least three of the last ten bug reports answered by the project
  within seven days** (`apparatus/score11.py`);
- the slate is not shown again before the explores;
- a report goes out only for data the user cannot get back from the tool's own documented command
  (2026-09-07's bar, as 2026-10-07 applied it), none at a project this repository has already reported
  to, and every report's text approved by the owner in full before it is filed.

What this run adds is the engine: **Sideeye v1.10.0**, released 2026-10-08, whose refusals say what to
do where they said "Change the define" or "refused by design" (#710, ADR 0097), whose
`multiple_threads_detected` names the README's threads limit in its own sentence, whose `nothing_could_fail`
next step says to declare a check or a marker, and whose FAIL prints `replay`, `evidence` and `reproduce`
as commands that run as printed (#709, #711). `apparatus/entry.sh` maps the new sentences (each named at
its row). The engine also refuses a state file written through a shared memory mapping on every path
(#689, ADR 0098, contract v19).

## The exclusion set, declared before the candidates

- `apparatus/fresh.sh` — 2026-10-07's copy with `mine` pointed at this run's directory and one more
  selftest case: 2026-10-07's own target (`roswell`) must read **seen**. Green
  (`transcripts/fresh-selftest.txt`).
- Every `owner/repo` in `spike/upstream-reports.tsv` (35 owners) and Artifex (mutool): not a target, so
  not a place a second report could go. Scouts were given the owners.

## The screen

Before any scout, the run's own list of 75 names from fields the earlier runs had not named as a
heading — in-place media editing, encrypted and secret files, IaC state, cloud CLI configuration,
duplicate-file tools, personal data, bookkeeping, certificate management, sync-tool configuration —
went through `fresh.sh` (`transcripts/fresh-screen-1.txt`): **64 seen, 11 fresh**. Of the eleven,
`word-recheck.sh` and `stars.sh` (`transcripts/word-recheck-1.txt`, `stars-0.txt`) leave one:

| name | why out |
|---|---|
| mkcert (59.7k) | rule 2: last push 2024-08-13 |
| mp4v2 (enzo1982) | rule 1: 190 stars |
| s3cmd (4.9k) | rule 2: last push 2025-10-22; its only write is the interactive `--configure` |
| cfssl (9.5k) | rule 5: every command writes a new file; nothing in place |
| ledger-cli | `ledger` is read-only over a journal the user writes by hand; the hit is the word, not the tool |
| wireguard, glab | hosted at git.zx2c4.com and gitlab.com: rule 1 cannot be measured |
| git-absorb | rule 5: it rewrites git history |
| mcfly | rule 7: SQLite |
| gitea-cli | the same tool as `tea`, which is seen |

Kept for the box: **scw** (scaleway/scaleway-cli, 1,012 stars, pushed 2026-10-08).

Four scouts then ran in parallel, each a fresh read-only subagent given one field, the rules, the
excluded owners and `fresh.sh`; each ran `fresh.sh` itself, and the names kept were screened again
here. Reports are `transcripts/scout-{1,2,3,4}.txt`.

### Scout 1 — in-place media editing (`transcripts/scout-1.txt`)

105 names seen, 96 out (33 seen in the ledgers, 21 under 1,000 stars, 9 pushed before 2026-04-09,
4 archived, 14 writing only a new file, 7 needing the network, 7 GUI-only, 1 a library), 6 kept,
3 put to the run as judgement calls. The calls, decided here:

- **f2** (ayoisaiah/f2, 2,453 stars, pushed 2026-10-04) was turned away on 2026-10-07 as "in
  `b2-targets.txt`, a study in flight". The hit was `otf2bdf`, a substring; searched by whole word in
  the three B2 files, the funnel and `docs/target-classes.md`, `f2` is nowhere
  (`transcripts/word-recheck-2.txt`, which also shows the only whole-word hits are `cut -f2` in four
  scripts). The earlier reading was wrong, and f2 is **fresh**. Scout 3 found the same four
  substring errors (`utt` in neomutt, `meli` in timeline, `f2` in otf2bdf, `MPD` in TMPDIR).
- **Writing back to the input path** (`otiotool -i cut.otio … -o cut.otio`; melt's `xml:` consumer the
  same way) counts as in place for the slate, as TiddlyWiki's `--render … wiki.html` did on 2026-10-07;
  whether it counts for a report is RESULTS.md's question. melt itself stays out (a rendering engine).
- **Av1an** stays out: its only in-place write is the resume ledger `done.json`, and the encode's
  inputs survive.

| name | rule | why out |
|---|---|---|
| kcc | 4/10 | the GUI's AppImage is the only arm64 build; `kcc-c2p` forks a multiprocessing pool and `kcc-c2e` runs 7z and kindlegen |
| Audiveris | 10/— | no arm64 asset (x86_64 .deb only); a gradle build of a JavaFX application with Tesseract |
| sickbeard_mp4_automator | 10 | ffmpeg writes the output and the tool deletes the input: every write is a child's |

Rule 11 (`transcripts/receipts/rule11-bug-reports-1.txt`, `rule11-score-1.txt`): SubtitleEdit 3/10,
OpenImageIO 3/10, OpenTimelineIO 6/10, f2 5/10, scaleway-cli 5/10 — all pass.

### Scout 3 — personal data (`transcripts/scout-3.txt`)

147 names seen, 122 out (57 seen, 25 under 1,000 stars, 2 with issues off, 14 stale or archived,
16 on rules 3–6, 8 past the table's size), 25 kept. Of the 25, most write only a new file or tree
(mvt, chdman, kcc-c2e, imessage-exporter, abe, ffmpeg-normalize, signalbackup-tools, WhatsApp-Chat-Exporter,
evernote2md, Chunker, zk `new`, memo `new`) — the state Sideeye judges is a path that exists before and
after, so those are out as on 2026-10-07 (gh); six are a GUI or a daemon reached through another process
(RetroArch, CopyQ, MPD, steam-rom-manager, BoilR, profile-sync-daemon) — out on rules 4 and 10. Seven
went on:

| name | rule 11 | word re-check (`word-recheck-3.txt`) | box |
|---|---|---|---|
| sheets (maaslalani) | **0/10**, no bug label, pushed 2026-07-18 | the word only (grading sheets) | out |
| organize (tfeldmann) | **1/10** (also 1 on 2026-10-03) | 2026-10-03's pool, out there on rule 11 too | out |
| cookcli (cooklang) | 3/10 pass | in 2026-10-03's candidate pool, never boxed — fresh | **in** |
| prefsCleaner (arkenfox/user.js) | 5/10 pass | none | **in** |
| MCA Selector (Querz) | 4/10 pass | none | **in** |
| zim | 3/10 pass | the word only (an image) | out: trixie's 0.76.3 is not upstream's 0.77.2, the GTK dependency tree is the GUI's, and `--convert-notebook` writes elsewhere |

## The box

`apparatus/Dockerfile`, built by `apparatus/build.sh` (`transcripts/build-*.txt`): Debian trixie,
linux/arm64, Sideeye **v1.10.0 installed by the page's installer** (`install-sideeye.sh v1.10.0`,
digest `cb176c41…` matched; the working tree's copy of the installer differs from the tag's in two
comment lines naming the version, `build-base.txt`). Each tool from its own latest release for
linux/arm64 where one exists, versions as GitHub and PyPI answered on 2026-10-09: scw 2.65.1, f2 2.2.2,
SeConv 5.2.0 (the stable tag under a beta a day), opentimelineio 0.18.1, cookcli 0.38.0, MCA Selector
2.9 (its .deb, with its own runtime; `xdg-utils` added for its dependency), arkenfox prefsCleaner.sh at
tag 144.0 (commit `bb45863b`). From Debian: openimageio-tools 2.5.18 (upstream 3.2.1.1 ships no binary
and no `iconvert` in its wheel).

## Plain runs, then the entry gate

Each operation was first run by hand in the box (`transcripts/lab-*.txt`), then once plainly from its
seed (`apparatus/plain.sh`, `transcripts/plain-runs*.txt`), then through `apparatus/entry.sh`
(`transcripts/entry-candidates*.txt`). Two changes to the apparatus this run: `entry.sh` maps the next
sentences v1.10.0 added (ADR 0097), and both `entry.sh` and `plain.sh` take a define in the argv form,
handed to `preflight --config` (#704) — mcaselector's query holds a space, and spelled without one the
query selects nothing (`lab-7.txt`'s follow-up).

| candidate | version | language | gate | why |
|---|---|---|---|---|
| scw `config set default-region=fr-par` | 2.65.1 | Go | 0 SUPERVISED | accepted, 2 operations. The config file is seeded by hand: `config set` refuses when it is absent and `init` is interactive (`lab-1.txt`, `lab-2.txt`) |
| f2 `-f IMG_ -r trip_ -x` | 2.2.2 | Go | 0 SUPERVISED | accepted, 3 operations. A batch rename leaves no path that exists before and after, so the first explore was `nothing_could_fail` (ADR 0091); a checker that reads whether the batch is whole, and that each photo's bytes survive under either name, was added (`defines/f2/check.sh`; the first version read names only and was refused `checker_not_falsified`) |
| seconv `subs.srt subrip --offset:-2000 --overwrite` | 5.2.0 | C# | 0 | accepted, 3 operations — after `DOTNET_EnableDiagnostics=0` in the define's env: the .NET runtime's startup `mknodat` of its diagnostics FIFOs was `unsupported_syscall_observed` (`entry-candidates.txt`, `-2.txt`) |
| iconvert `--inplace --caption hello --keyword k photo.jpg` | 2.5.18 (Debian) | C++ | **DEFINE → wall** | `recording_run_failed`, SIGABRT. By hand it exits 0; with the shim preloaded alone (no engine) iconvert and oiiotool both die of `std::system_error: Unknown error -1`, with `--threads 1` too, and `--observe syscalls` ends the same way (`lab-3.txt`). #555's shape (the shim's static TLS and a thread's stack), closed 2026-09-11; recorded in RESULTS.md as a finding about Sideeye |
| otiotool `-i cut.otio --redact -o cut.otio` | 0.18.1 | Python | 0 | accepted, 2 operations |
| cook `pantry add dairy eggs --quantity 6` | 0.38.0 | Rust (musl) | 0 SUPERVISED | accepted, 5 operations (`lab-3.txt`: a temporary file, `fsync`, rename) |
| prefsCleaner `-s -d` through `setpriv --reuid=1000` | 2.1 (tag 144.0) | bash | **1** | wall: `child_process_detected`, "an image replacement whose chain of observation broke" — setpriv's drop to uid 1000. The script refuses root (`lab-3.txt`) and refuses when any file is root's (`lab-4.txt`), so setpriv is what lets it run. `--observe syscalls` refuses the same way; `--observe supervised` ends `recording_run_failed` on the second run of `--twice` — the restore rebuilds bytes and not owners (#678), so the second run finds its files root's and refuses (`lab-6.txt`) |
| mcaselector `--mode delete --query "InhabitedTime < 1000"` | 2.9 | Java | 0 | accepted, 2 operations, 34 threads created and one writer. Over a region file this run writes itself (`defines/mcaselector/make_region.py`, six chunks of the 1.18+ shape); `lab-7.txt`: the new file goes to `/tmp` (java.io.tmpdir, not TMPDIR), then `unlink` of the region file, then `rename` |

### Scout 2 — keys, certificates, secrets, connection settings (`transcripts/scout-2.txt`)

141 names seen, 116 out (60 seen, 28 under 1,000 stars, 11 stale, 3 archived, 2 with issues off,
12 on rules 3–6), 20 kept and 5 put as judgement calls. The calls: keychain starts ssh-agent (a
daemon) and writes through a temporary name and rename — out; rage's only write is a new key file —
out; dotnet nuget's writing code is NuGet/NuGet.Client (822 stars, issues off) — out on rule 1 as
keyring was; qshell's account list is leveldb — out as kubo was; sing-box `format -w` rewrites a
config that lives outside git and holds secrets — in as a candidate (rule 5's "not formatters"
is about code). Of the 20, those that only create files (nebula-cert, zerotier-idtool, imgtool,
aws-iam-authenticator's `init`), need a daemon, FUSE or root (caddy's storage, cryfs, fscrypt),
hand the write to a child (tfmigrate, assh), or install only through nix (attic, cachix) were
out; kubeseal's SealedSecret is designed to live in git (rule 5). Ten went to rule 11
(`receipts/rule11-bug-reports-3.txt`, `rule11-relabel-3.txt`, `rule11-score-3.txt`):

| name | rule 11 | box |
|---|---|---|
| uplink (storj) | **1/10** | out |
| nmctl (gravitl/netmaker) | 3/10 pass | **in** |
| aptos | **0/10** | out |
| yarn (yarnpkg/berry) | 4/10 pass (`yarn` in the ledgers is 2026-09-21's "not a target: no network" row, not a measurement) | **in** |
| ziti (openziti) | **0/10** | out |
| authelia | 1 issue returned under any label — the tracker is discussions; rule 11 cannot be measured | out |
| softhsm2 (softhsm/SoftHSMv2) | 4/10 pass | **in** |
| in-toto | **1/7** | out |
| sing-box | **0/10** | out |

### Scout 4 — operations over sets of files (`transcripts/scout-4.txt`)

200 names seen (its report came in three messages: the first was cut at its PDAL row), 168 out
(87 seen, 56 under 1,000 stars, 12 stale, 1 archived, 2 with issues off, 10 on rules 3–6), 23 kept
and 9 put as judgement calls. The calls: pm2, mutagen (Go) and the five log agents are daemons —
out; systemd-repart starts mkfs and needs root — out; **trash** (sindresorhus/trash-cli, a Node
implementation, not andreafrancia's, whose `trash-cli` this project reported to) — in. Of the 23,
those that write only a new file or tree (binwalk, unblob, Bento4, nydus-image, tippecanoe,
ffmpeg-normalize, PDAL, dcm2niix), delete regenerable trees (npkill, kondo), need root, loop devices,
FUSE or a daemon (Ventoy, mergerfs, rpi-imager, btrbk, syslog-ng, rsyslog, ollama, BleachBit's
wipe), reach the network (mnamer), or ship only inside an APK (magiskboot) were out. Two compress
a file and remove the input — the gzip shape, which GNU gzip itself cannot bring here (not on
GitHub): **libdeflate-gzip** (ebiggers/libdeflate, rule 11 **6/10**) in; igzip (intel/isa-l, 1/5) out.
trash: 3/10 under any label (its `bug` label returned one issue).

### Scout 5 — the remaining fields (`transcripts/scout-5.txt`)

Its report was cut by the message limit inside its list of seen names, and the scout then stopped on its
account's usage limit before it could re-send the rest; the transcript keeps what arrived and says so.
Twelve were kept. Taken on: **chdman** (`addmeta` rewrites an existing CHD in place — scout 3 had dropped
MAME's tools on `createcd`, which writes a new file), **stack**, **carapace**, **cabal**, **hunspell** (an
append, kept as a contrast) and **Kvantum**. Out: Aseprite and LibreSprite (a Skia or CMake source build for
arm64, and the GUI's batch mode), me_cleaner (its seed is a real Intel ME region, not synthesisable),
euporie (`--run` starts an ipykernel child, and its unreleased `main` already makes the save atomic), picotool
(a UF2 declaring config items needs a pico-sdk cross build), sad (rule 11 **1/9**, any label).

Rule 11 (`receipts/rule11-bug-reports-5.txt`, `-6.txt`, `rule11-relabel-6.txt`): MAME 5/10, stack 3/10,
carapace-bin 4/10, cabal 5/10, Kvantum 6/7, hunspell 5/10 — all pass. `cabal` read seen in `fresh.sh`
on `cabal-fmt` (2026-09-28's formatter row): the word, not the tool (`word-recheck-5.txt`).

### The run's own screens, between and after the scouts

Scout 5 stopped on the usage limit at about two hours into the run, and the next scouts could not be
started until the model was changed. In between, the run screened names of its own
(`transcripts/fresh-screen-3..11.txt`, `stars-1..6.txt`), about 230 names over version managers, language
toolchains' user config, cloud-native CLIs, desktop and Qt config tools, file managers and time-series
files. What came through: **micromamba** (mamba-org/mamba, rule 11 **0/10** on any label and **2/10** on
`type::bug` — out), **buildx** (docker/buildx, 5/10, in) and **zvm** (tristanisham/zvm, 5/10, in). Four
substring hits read and not counted: `fisher` in kingfisher, `john` in johnkerl and JohnnyMorganz, `cabal`
in cabal-fmt, `ROOT` in "state root". Out on rules 1–2 among the fresh: ghcup (archived), elan 653,
gmic 235, exoscale 92, Ghost-CLI 498, augeas 532, netplan (issues off), wakatime-cli 461, podofo 611,
cdown/srt (2024), pimterry/notes (2024), fisher (pushed 2026-01-31), zigup (2025-06), devpod (2025-11),
whisper (2025-12), scummvm (issues off), qmk_cli 187, papirus-folders 811, Flips (archived). One
fresh name with stars and a responsive tracker was taken out by the run before it was boxed; it is
named in the funnel's screen count only.

### Scouts 6 and 7 — single-binary user config, and binary user data rewritten at its path

Started on the model the session moved to (`transcripts/scout-6.txt`, `scout-7.txt`; scout 6's report
was lost on its way and re-sent when asked). Scout 6: 128 seen, 11 kept, 2 judgement calls (goose,
whose main store is SQLite — out; OpenRCT2, a GUI game — out). Scout 7: about 130 tools seen, 8 kept,
1 call (RetroArch, whose headless `--scan` exists only on unreleased `master` — out).

From scout 6: **fly** (Concourse, 4/10), **kafkactl** (5/10), **rpk** (Redpanda, 9/10 on `kind/bug`),
**atac** (8/9) in; kew out (trixie's 3.2.0 against upstream's 4.3.8, and its source build is a media
stack); ddev out (refuses root, and a `setpriv` drop met the restore's owners on prefsCleaner);
apptainer, cachix and matugen out (no arm64 release: RPM extraction, Nix or cabal, cargo); wasmer out
(tokio, the threads wall forecast); woodpecker-cli out (3/10, and its update check reaches the network
unless disabled). From scout 7: **ifcpatch** (IfcOpenShell, 4/10), **CKAN** (6/10), **Hydrogen's
h2cli** (8/10) and **ROOT's rootrm** (4/10) in; BoilR out (tokio, and a cargo build), OpenUSD's
usdupdatecrate, QuPath and LOOT out (source builds on arm64; usdupdatecrate's update runs in a spawned
child). Receipts: `receipts/rule11-bug-reports-8.txt`, `-9.txt`, and the scouts' own counts for the rest.

## The box, continued

Third layer (`build-fourth.txt`; the first attempt, `build-fourth-timeout.txt`, died on a TLS
handshake to Docker Hub): nmctl 1.7.0 (netmaker's linux-arm64 asset), yarn 4.18.1 (`@yarnpkg/cli-dist`
from npm), sindresorhus's trash-cli 7.2.0 (npm), Debian's softhsm2 2.6.1 (upstream's tag is 2.7.0).
Fourth layer (`build-fifth.txt`): libdeflate 1.26 built from its release tarball.

| candidate | version | language | gate | why |
|---|---|---|---|---|
| nmctl `context set c1 …` | 1.7.0 | Go | 0 SUPERVISED | accepted, 2 operations (`lab-8.txt`: `config.yml`, master key and all, opened `O_TRUNC`) |
| yarn `config set npmAuthToken …` | 4.18.1 | TS (Node 20) | **1** | wall: `multiple_threads_detected` — the sentence v1.10.0 gives it (ADR 0097), mapped by `entry.sh`. The placeholder token first written into this define and lab 8 began with the four characters of a chat-service token's prefix; it was renamed before commit, and lab 8 and this gate re-run on the new one (same answer) |
| trash `report.txt` | trash-cli 7.2.0 | JS (Node 20) | **1** | wall: `multiple_threads_detected`. The define had a checker (a move leaves no path before and after) and XDG_DATA_HOME under the state root |
| softhsm2-util `--import k2.pem …` | 2.6.1 (Debian) | C++ | **1** | byte-repeatability: the imported key's object and lock are named by a random UUID, different in the two runs; nothing to pin |
| libdeflate-gzip `notes.txt` | 1.26 | C | 0 | accepted, 3 operations (`lab-9.txt`: `notes.txt.gz` created `O_EXCL`, one write, close, then `unlink` of the input; no fsync) |

Fifth layer (`build-sixth.txt`): stack 3.11.1, carapace-bin 1.8.0 and cabal-install 3.18.2.0 from their
linux-aarch64 assets; hunspell 1.7.5 built from its release tarball (trixie ships 1.7.2) with trixie's
en_US dictionary; chdman (mame-tools 0.276) and Kvantum (qt6-style-kvantum 1.1.4) from Debian — upstream
is 0.289 and 1.1.8, and either source build is MAME's or a Qt6 tree. Sixth (`build-seventh.txt`): buildx
0.38.0 and zvm 0.9.1 from their assets. The eighth build (`build-eighth.txt`) is the box rebuilt after one
layer was taken out before any of its gates ran. Seventh (`build-ninth.txt`): ifcpatch and ifcopenshell
0.9.0 from PyPI, CKAN 1.36.4's release .deb on trixie's Mono 6.12, Hydrogen 1.2.2 from trixie (upstream
1.2.7), ROOT 6.40.04 from conda-forge through micromamba 2.9.0 (ROOT publishes no linux-aarch64 binary).
Eighth (`build-tenth.txt`): fly 8.3.1, kafkactl 5.20.0, rpk 26.2.2 and atac 0.23.1 (musl) from their
assets, and the Mono component CKAN's first run asked for (`System.ComponentModel.Composition`, `lab-14.txt`).

| candidate | version | language | gate | why |
|---|---|---|---|---|
| stack `config set install-ghc false --global` | 3.11.1 | Haskell | 0 SUPERVISED | accepted, 116 operations, with the global project seeded: without it `config set` asks the network for `snapshots.json` (`lab-10.txt`, `lab-11.txt`). The pantry and stack SQLite caches are scratch |
| cabal `user-config update -a 'jobs: 4'` | 3.18.2.0 | Haskell | 0 SUPERVISED | accepted, 3 operations (`lab-10.txt`: `config` renamed to `config.backup`, a new file renamed in from TMPDIR) |
| carapace `--style carapace.Error=red` | 1.8.0 | Go | 0 SUPERVISED | accepted, 2 operations |
| chdman `addmeta -i d.chd -t NOTE -vt hello` | 0.276 (Debian) | C++ | 0 | accepted, 4 operations, on an uncompressed CHD (a compressed one is refused "File not writeable", `lab-11.txt`; `lab-12.txt`: three `pwrite64` in place) |
| kvantummanager `--set KvFlat` | 1.1.4 (Debian) | C++/Qt | **1** | wall: `unresolvable_path` — "unlinked-fd write": Qt's save writes an `O_TMPFILE` and names it afterwards (`lab-10.txt` shows the lock and the rename) |
| hunspell `-a -d en_US -p my.dic` through `sh -c` | 1.7.5 | C++ | 0 | accepted, 2 operations: it reads its commands on stdin, which a define gives EOF, so the operation is the argv form `sh -c '… < words.txt'` |
| buildx `create --append --name b1 --node b1x …` | 0.38.0 | Go | 0 SUPERVISED | accepted, 13 operations, on the remote driver (no daemon needed to record a builder, `lab-13.txt`); `activity` (a timestamp per builder) is scratch |
| zvm `vmu zls …` | 0.9.1 | Go | 0 SUPERVISED | accepted, 4 operations, once the seed runs one command first: on a home with no `~/.zvm`, the first `vmu` fails "unable to create settings.json" (`entry-out/entry/zvm.seed-1.log`) |
| ifcpatch `-i model.ifc -r Optimise` | 0.9.0 | Python/C++ | 0 | accepted, 47 operations, with the clock pinned (`lab-15.txt`: the header's time differs run to run); the first spelling of the pin, a path in `preload:`, was refused SETUP ERROR — v1.10.0 names a library by the start of its basename |
| rootrm `data.root:h2` | ROOT 6.40.04 | C++/Python | **DEFINE → wall** | `recording_run_failed`, SIGABRT at `TUUID.cxx:171` (`GetCryptoRandom` failed) with the shim loaded; by hand it exits 0. Without the shim conda's ROOT opens `/dev/urandom`; with it, no such open reaches the kernel, while the box's own C, C++ and Python opens of `/dev/urandom` work under the shim (`lab-16.txt`) — not settled. Under `--observe supervised` (`lab-17.txt`) `--twice` differs: ROOT writes a random UUID into the file |
| h2cli `-u /s/h2/kit` | Hydrogen 1.2.2 (Debian) | C++/Qt | **1** | wall: `unresolvable_path`, an unlinked-fd write — Kvantum's shape |
| fly `-t ci edit-target --team-name t2` | 8.3.1 | Go | 0 SUPERVISED | accepted, 2 operations (`lab-18.txt`: `.flyrc` opened `O_TRUNC`) |
| kafkactl `config use-context b` | 5.20.0 | Go | 0 SUPERVISED | accepted, 3 operations (`current-context.yml` opened `O_TRUNC`, written, `fsync`ed) |
| rpk `profile use a` | 26.2.2 | Go | 0 SUPERVISED | accepted, 3 operations (a temporary name renamed over `rpk.yaml`) |
| atac `request new demo/pong …` | 0.23.1 | Rust | 0 SUPERVISED | accepted, 7 operations (`demo.json_` renamed over `demo.json`, twice); `atac.log` is scratch |
| ckan `compat add 1.7` | 1.36.4 | C# (Mono) | 0 | accepted, 2 operations. The first define added 1.11, which the fake instance already lists, so the file was rewritten with the same bytes; 1.7 is not listed |

Off the page's path (`lab-17.txt`): iconvert's define, under `--observe supervised` named by hand, is
accepted with 6 operations — it is explored that way in `RESULTS.md`, as 2026-10-07 explored roswell.

## The scan's readings (rule 14)

`apparatus/prescan-all.sh`, one tracker at a time (`transcripts/prescan-log.txt`,
`receipts/*.prescan.txt`), read with `apparatus/prescan-read.py` (`transcripts/prescan-read-*.txt`).
Each veto is decided from the issue's body, as on 2026-10-05 and 2026-10-07. Every explore waited for
its tracker's scan to end (`apparatus/explore-after-scan.sh`); no target was vetoed.

Read and not a veto: scaleway-cli (`#4857` asks for a confirmation before a config is overwritten, a
feature), f2 (`#45`, data loss through `--fix-conflicts`, another path), SubtitleEdit (`#13308` the GUI's
save through the desktop portal leaving a temporary name; `#15156` asks seconv for `--overwrite`, which it
now has — none a write cut short), OpenTimelineIO (none on writing), cookcli (`#431`, closed: the shopping
list was written non-atomically and is now staged, fsynced and renamed — the shape the pantry's PASS
shows; `#429` a round-trip corrupting the pantry's comments, another cause), MCA Selector (`#155` a
defragment on corrupt section sizes; none on deleting chunks), netmaker (`#4045`, open, netclient's
`.json`/`.bak` corrupted by Windows Fast Startup — another program in the same tracker, not nmctl's
`config.yml`), libdeflate (none on the gzip program's write).

Read and not a veto, the rest: stack (`#4559`, open, "non-atomic file writes in GHC and stack" — its body
says every occurrence so far is GHC's build output; `#6897` a `config set snapshot` rewriting the value
wrongly, another cause), cabal (`#10964`, `#10938` on `writeFileAtomic`, which the update's new file goes
through; none on the backup rename), carapace-bin (none on writing), MAME (`#12605` `createdvd` on CIFS,
another command and cause), hunspell (none on the personal dictionary), buildx (none on the instance
store), zvm (`#83` a rename of zls, another path), IfcOpenShell (none on ifcpatch's output write),
Concourse (none on `.flyrc`; `#722` and `#813` are the server's database and volumes), ATAC (none),
CKAN (`#2754`, closed in 2019, "Aborting a `ckan scan` halfway through leaves a corrupt registry.json", and
`#1114` the same database in 2015 — the registry, which now writes through a transaction manager, not the
game's compatible-versions file this explore cut), Redpanda (none on rpk's profile file; rpk passed), kafkactl
(`#269` pods left behind by an interrupted command, another resource). kafkactl's first scan ended rc=2 and
was re-run at the end of its list (`prescan-log.txt`), and its explore waited for the re-run.

## The slate — four waves, twenty-two targets

The owner asked for five in each of four waves. The screen ran thin, as on 2026-10-07: five scouts and the
run's own screens brought sixteen to an explore; the last two scouts (started on the model the session moved
to after scout 5's usage limit) put eight more in the box, of which six reached an explore. Every target that
cleared the gate was explored — the owner's ruling of 2026-10-02 that a dogfood run measures everything it
can measure now — so the fourth wave has seven. Waves are in the order the targets were explored.

| wave | targets |
|---|---|
| 1 | scw (Go), f2 (Go), seconv (C#), otiotool (Python), cook (Rust) |
| 2 | mcaselector (Java), nmctl (Go), libdeflate-gzip (C), stack (Haskell), cabal (Haskell) |
| 3 | carapace (Go), chdman (C++), hunspell (C++), buildx (Go), zvm (Go) |
| 4 | iconvert (C++, `--observe supervised` named), ifcpatch (Python/C++), fly (Go), atac (Rust), ckan (C#), rpk (Go), kafkactl (Go) |

Walls at the gate, not in the slate: prefsCleaner, yarn, trash, softhsm2-util, Kvantum, h2cli, rootrm.
