# Selection — 2026-10-07 user-data-3

The owner's question for this run: **dogfood again in four waves of five, the targets chosen by the
rules, none at a project this repository has already reported to, and only what means something
reported** ("dogfoodingを5item x 4waveで実施する。対象はruleに沿って実施、過去upstreamしたものはやらないように。
意味があるものだけ報告するように"). This file is the selection for all four waves; they share one screen,
one box and one apparatus, so they are one run directory with one `RESULTS.md` split by wave, and one
`RUNS.md` row.

The rules are `spike/cohort4/SCOUT-BRIEF.md`'s 1–17 plus this directory's ordering rule and entry gate
(`../README.md`), read as 2026-10-05 read them:

- rule 5 strictly: state git does not give back, **not formatters**;
- rule 11 at 2026-09-28's bar: **at least three of the last ten bug reports answered by the project
  within seven days** (`apparatus/score11.py`);
- the slate is not shown again before the explores (2026-10-05's reading of the owner's instruction).

What this run adds is the engine: **Sideeye v1.9.0**, released 2026-10-07, which refuses an exploration
in which nothing could fail (`nothing_could_fail`, ADR 0091), names `cwd` when a toml's relative argument
missed (ADR 0093), refuses a define command that cannot be started (ADR 0092), and warns on a command
spelled for a shell (ADR 0095). Waves start as soon as five targets have cleared the gate and the scan;
the screen for later waves runs beside them.

## The exclusion set, declared before the candidates

- `apparatus/fresh.sh` — 2026-10-05's copy with `mine` pointed at this run's directory and one more
  selftest case: 2026-10-05's own target (`tenv`) must read **seen**. Green
  (`transcripts/fresh-selftest.txt`).
- Every `owner/repo` in `spike/upstream-reports.tsv` (35) and Artifex (mutool): not a target, so not a
  place a second report could go. Scouts were given the owners.

## The screen

| pass | names | fresh | transcript |
|---|---|---|---|
| scout 1 — PKI, disk images, containers' local config, games, hardware, backups, audio and e-book metadata | — | 48 kept by the scout (137 seen, 37 below rules 1–2) | `transcripts/scout-1.txt` |
| own re-check of the 32 the box could hold | 32 | 31 | `transcripts/fresh-screen-1.txt`, `word-recheck-1.txt` |

Scouts are fresh read-only subagents; each ran `fresh.sh` itself, and the names kept were screened again
here. Two of scout 1's hits were read, not counted (2026-10-05's rule): `keyring` matched "the GnuPG
keyring" in 2026-09-16's selection, and `openjdk` matched google-java-format's runtime in
`docs/target-classes.md`; neither is a ledger line about the tool.

`fresh.sh` reads cohort 4's rejected candidates since 2026-10-05, but that run also met a candidate only in
cohort 4's other documents (ggshield). After the explores, every name this run explored or turned away at
the gate was searched in all of them with `apparatus/cohort4-recheck.sh`: none appears. The same script on
ffsubsync and ggshield, the two 2026-10-05 found there, finds both (`transcripts/cohort4-recheck.txt`).

Rules 1 and 2 by `apparatus/stars.sh` (`transcripts/stars-*.txt`), and rule 11 by `apparatus/rule11.sh`
(`transcripts/receipts/rule11-*.txt`), one tracker at a time.

### Out before the box, each with its reason

| name | rule | measurement |
|---|---|---|
| ssh-keygen (openssh-portable), qemu-img (qemu), keytool (openjdk), kicad-cli (KiCad) | 11 | GitHub issues off (a mirror); rule 11 cannot be measured on the tracker the project uses, as GnuPG on 2026-09-16 |
| smallstep/cli 1/10, square/certstrap 0/10, lxc/incus 1/10, legendary-gl 0/10 (its `bug` label has no issue), weewx 1/10, snakemake 2/10, netlify/cli 2/10, ohmyzsh 2/10 | 11 | `rule11-bug-reports.txt`, `-2.txt` |
| flutter, quickemu, asciinema, buildah, sapling, openmw, pishrink, winetricks, m4b-tool, dotnet, nextflow, fwupdtool, LibrePCB, ludusavi | 4/8/10 | network at first run, root and loop devices or a daemon, a game or GUI suite, or a heavy source build with no arm64 asset (`scout-1.txt`) |
| git-town, git-secret | 10 | every write is `git config` or gpg's, a child (and gpg-agent a daemon) |

## The box

`apparatus/Dockerfile`, built by `apparatus/build.sh` (`transcripts/build-*.txt`): Debian trixie,
linux/arm64, Sideeye **v1.9.0 installed by the page's installer** (`install-sideeye.sh v1.9.0`, digest
matched). Each tool from its own latest release for linux/arm64 where one exists; PyPI and npm at the
version their registry called latest on 2026-10-07, asked of the registry before any build ran; openssl
4.0.3 built from its release tarball (no binary asset; trixie ships 3.5). From Debian: minisign 0.12
(= upstream's latest tag) and zsh.

Two apparatus errors are kept. The first box's build was still running when it looked stopped (its
transcript ended mid-layer), and a second build was started into the same transcript, which truncated
it; the second was stopped, the first finished, and the box's contents were recorded from inside it
instead (`transcripts/build-first-contents.txt`). And lab 1's `show` printed the exit status of the last
command of its pipe (`cut`), not the tool's; lab 2 and later print the tool's.

## Plain runs, then the entry gate

Each operation was first found by running the tool by hand in the box (`transcripts/lab-*.txt`), then
run once plainly from its seed (`apparatus/plain.sh`, `transcripts/plain-runs*.txt`). The gate is
`apparatus/entry.sh`, 2026-10-05's copy with two more mapping rows for v1.9.0's next steps — a recording
with no crash point, refused `nothing_could_fail`, reads as the interior answer v1.8.0's "nothing to
explore" did, and "Add cwd" reads as a define fix — run through `apparatus/gate-run.sh`.

Candidates that never reached the gate, for a reason found by running them:

| name | why |
|---|---|
| minisign `-C` | changing or removing a password reads the old one from stdin, which a define gives EOF; `-C -W` on a key with no password rewrites the same bytes (`lab-1.txt`) |
| sbctl | its `go install` failed on a missing `libpcsclite`; it also wants root and EFI variables |
| keyring `del` | the write is keyrings.alt's `PlaintextKeyring` (the default backend is the Secret Service over DBus), and jaraco/keyrings.alt has 29 stars: rule 1 on the code that writes (`stars-3.txt`) |

| candidate | version | language | gate | why |
|---|---|---|---|---|
| openssl `ca -revoke` | 4.0.3 (release tarball) | C | 0 | accepted, 8 operations, with the clock pinned (unpinned: index.txt's revocation time differed between the two runs, and the gate's next step asked for the pin; `entry-candidates-2.txt`) |
| duplicacy `set -no-backup` | 3.2.5 | Go | 0 SUPERVISED | accepted, 2 operations |
| ferium `profile delete` | 4.7.1 | Rust | 0 SUPERVISED | accepted, 3 operations |
| lxc (lxd's client) `alias remove` | 6.9 | Go | 0 SUPERVISED | accepted, 2 operations |
| sfntedit (afdko) `-a` | 5.0.1 | Python/C | 0 | accepted, 2 operations |
| acme.sh `--set-default-ca` | 3.1.6 | sh | 0 FOLLOW | `oracle_missed_operation`, the next step names `--observe syscalls` |
| easyrsa `revoke` | 3.2.7 | sh (openssl) | 0 FOLLOW | `child_touched_state_dir`, the next step names `--observe syscalls` |
| zsh-z `zshz --add` | 2.0.1 | zsh | 0 FOLLOW | `oracle_missed_operation`, the next step names `--observe syscalls` |
| git-lfs `install --skip-repo` | 3.8.0 | Go | 0 SUPERVISED | accepted, 17 operations — **out**: every one is the `git config` it runs, and git is in the funnel (2026-09-16 crossed-walls) |
| keyring `del` | 25.7.0 / keyrings.alt 5.0.2 | Python | 0 | accepted, 2 operations — **out** on rule 1 (above) |
| espsecure `sign-data` | esptool 5.4.0 | Python | **1** | byte-repeatability: the ECDSA signature is randomized, nothing to pin |
| plakar `rm -apply -tag` | 1.1.7 | Go | **1** SUPERVISED | byte-repeatability: snapshot identifiers and the encryption's nonces differ by design |
| rustic `forget --prune` | 0.11.4 | Rust | **1** | wall: multiple_threads_detected |
| TiddlyWiki `--load … --deletetiddlers … --render` over its own file | 5.4.1 | JS | 0 | accepted, 2 operations (`entry-candidates-3.txt`) |
| broot `--install` | 1.61.0 | Rust | 0 | accepted, 22 operations |
| ziptool (libzip) `delete` | 1.11.4 (release tarball) | C | 0 FOLLOW | `oracle_missed_operation`, the next step names `--observe syscalls` |
| prek `install` | 0.5.5 | Rust | **1** | wall: multiple_threads_detected |

TiddlyWiki's define is the one that met v1.9.0's new warning (ADR 0095): its argument `$:/core/save/all`
is a TiddlyWiki title, and Sideeye named it as "a word beginning `$` … nothing expands it". The sentence is
true — the word reaches the program as written — but a shell would pass `$:` as written too (`:` is not a
parameter name), so the warning is a false positive by the shell's own rule: the word-initial `$` is counted
whatever follows it, where the mid-word `$` counts only before a name character, `{` or `(`. Recorded in
`RESULTS.md` as a finding about Sideeye; it changes no verdict.

### The second screen

| pass | names | fresh | transcript |
|---|---|---|---|
| scout 2 — accounting, contacts, feeds, dotfiles, DNS, bookmarks, clipboards, notebooks, mods, config switchers | — | 31 kept (184 seen, 41 below rules 1–2 or issues off) | `transcripts/scout-2.txt` |
| own re-check of the 16 tried | 16 | 13 | `word-recheck-2.txt` |

Read, not counted: `TiddlyWiki` in topydo's documentation format (2026-09 blind hunt) and `libzip-dev` as a
build dependency in 2026-10-03's Dockerfile. Out by the re-check: Home Assistant (`homeassistant` is
2026-10-05's own gate row and in the funnel; the scout had screened `hass`) and f2 (in `b2-targets.txt`, a
study in flight).

| name | rule | measurement |
|---|---|---|
| toot 0/10 (any label; `bug` held two) | 11 | `rule11-relabel-2.txt` |
| chia, kubo | 6/7 | the tool's main store is SQLite (chia) and leveldb (kubo) |
| gguf-set-metadata (llama.cpp) | 5 | a model file is downloaded again; and its edit is through a shared mapping, the write Sideeye does not count (#689) |
| kitty `kitten themes` | 8 | the theme list is fetched over the network on first use |
| dnscontrol, octodns | 5 | the zone files they write are generated from the define in `dnsconfig.js` / the YAML source |
| alacritty `migrate` | — | no Linux asset, and trixie's 0.15 is not upstream's 0.17: a Rust source build this box does not carry |
| GRASS | — | trixie's 8.4 is not upstream's 8.5, and its source build needs GDAL and PROJ |
| clipse | 8 | its arm64 build is the X11 or Wayland one: no clipboard without a display (`lab-3.txt`) |
| lnav | 8 | `-n -c ':config …'` does not persist a setting without the interface (`lab-4.txt`) |
| oh-my-fish | 5/8 | offline only the default theme is installed; themes and packages are `omf install`, over the network (`lab-3.txt`) |

### The third screen

| pass | names | fresh | transcript |
|---|---|---|---|
| scout 3 — config editors, media tags, archives, scientific formats, images in place, game and boot images, PKI | — | 25 kept (~150 seen, ~35 below rules 1–2 or issues off) | `transcripts/scout-3.txt` |
| own re-check of the 15 tried | 15 | 15 | `word-recheck-3.txt` (`tinc`'s five substring hits are all "distinct") |

Out before the box: grav's `bin/plugin login` (the write is getgrav/grav-plugin-login's, 48 stars — rule 1 on
the code that writes, as keyring), LibreSSL's `openssl ca` (the same CA-database code as openssl, whose
explore already answered), krew (its receipts come back with a reinstall: rule 5).

| name | rule | measurement |
|---|---|---|
| mosquitto 0/10 (no bug label but "Not a bug"), tinc 1/10, rgbds 2/10 | 11 | `rule11-bug-reports-4.txt` |
| lasinfo (LAStools) `-set_file_source_ID` | 8 | on a minimal LAS 1.2 file it reported version 255.255 and exited 1; whether the file or the tool, not settled (`lab-5.txt`) |
| extract-xiso `-r` | 8 | an image `-c` makes is already optimized, so `-r` skips it; no way to make an unoptimized one here (`lab-5.txt`) |
| TIC-80 | 8 | saving a cart takes a command with a space in its argument, which a string-form command cannot carry |
| Limine `bios-install` | — | the stage-1 code it writes is built for the target with clang and nasm and embedded in the host utility |
| testdisk | 8 | the box has neither sfdisk nor a mkfs, so no lost partition to find and write back; lab 5's change was its log (`lab-6.txt`) |
| qalc `-f` | 8 | definitions saved from a file of commands reach disk empty (`lab-6.txt`) |

### The fourth and fifth screens

| pass | kept by the scout | transcript |
|---|---|---|
| scout 4 — prompts and terminals, image optimizers, fonts, `config set` subcommands, AI-agent CLIs | 20 (~180 seen, ~36 below rules 1–2 or issues off) | `transcripts/scout-4.txt` |
| scout 5 — the last pass, told the walls met so far | 2 clean (~140 seen, ~45 below rules 1–2); the scout's own word: "the space is all but dug out" | `transcripts/scout-5.txt` |

Read, not counted: `cline` (every hit is "declined"), `astro` (every hit is astropy), `forge`/`sui` in other
words. Out on the re-check: sui (2026-10-05's own candidate table). Out before the box, each a reason the
scout named or a rule: qwen-code (gemini-cli's fork, the same `mcp add`; gemini-cli walled on threads
2026-10-05), mini-swe-agent (writes through python-dotenv's `set_key`, measured), hermes-agent, forgecode
and promptfoo (each tool's main store is SQLite — rules 6/7), vscode and code-server (Electron or Node
worker threads, and the marketplace), jscodeshift, hexo, changesets, doctoc (their files are in git), ruler
and rulesync (they write files generated from `.ruler/` and kept in git — rule 5, as dnscontrol), semgrep
(spawns semgrep-core), MuseScore, Bottles, webmin (rule 4), qshell (Go, and its other commands are network),
inspec (`inspec.lock` is in git), knife (`config use-profile` lives in chef/knife, 1 star — rule 1 on the code
that writes), optuna (its journal file is optuna's own storage engine — rule 7), oh-my-zsh 2/10.

| name | rule | measurement |
|---|---|---|
| cline 2/10, vercel-labs/skills 0/10, mistral-vibe 0/10, comfy-cli 1/10, gatsby 2/10, flashrom 1/10 | 11 | `rule11-bug-reports-5.txt`, `-6.txt`, `-7.txt` |
| thv (toolhive) | 8 | every `config` subcommand first asks for a container runtime (`lab-7.txt`) |
| testdisk | 8 | with fdisk and e2fsprogs added, two `/cmd` spellings still wrote nothing back (`lab-7.txt`, `lab-8.txt`) |
| lasinfo | — | on txt2las's own file too, `-set_file_source_ID` rewrote the version field to 255.255 and exited 1 — an editing defect of its own, not this run's subject, not pursued (`lab-7.txt`) |

Node 22 from nodejs.org (digest checked) went in under `/opt/node22` for pi, cspell, capacitor and astro, which
refuse trixie's Node 20; each of those defines puts it first on PATH, and the Node targets explored before it
kept the Node they ran on. kitten runs offline on its theme archive fetched at build, with the JSON comment it
reads its cache age from added to the copy. roswell's `config` runs on the SBCL `ros setup` fetched at build;
its define's ROSWELL_HOME holds the config file and symlinks to the rest (197 MB), compared by target.

| candidate | version | language | gate | why |
|---|---|---|---|---|
| minizip (minizip-ng) `-e` | 4.2.2 (tag build) | C | 0 | accepted, 2 operations (`entry-candidates-4.txt`) |
| xbps-pkgdb `-m hold` | 0.60.7 (tag build) | C | 0 | accepted, 5 operations |
| mcpm `edit` | 2.15.0 | Python | 0 | accepted, 32 operations |
| sndfile-metadata-set `--str-comment` | 1.2.2 (Debian, = upstream) | C | 0 | accepted, 3 operations |
| ezdxf `strip` | 1.4.4 | Python | 0 | accepted, 10 operations |
| pi `install` | 1.0.4 | TS (Node 22) | 0 | accepted, 8 operations (`entry-candidates-5.txt`) |
| doit `forget` (JSON backend) | 0.37.0 | Python | 0 | accepted, 2 operations |
| kitten `themes` | kitty 0.49.2 | Go | 0 SUPERVISED | accepted, 10 operations |
| cspell `link add` | 10.3.6 | TS (Node 22) | **1** | wall: multiple_threads_detected |
| alacritty `migrate` | 0.17.0 (tag build) | Rust | 0 FOLLOW | `oracle_missed_operation`, the next step names `--observe syscalls` (`entry-candidates-6.txt`) |
| gitmoji `-i` | 9.7.0 | JS | 0 | accepted, 2 operations |
| astro `preferences disable --global` | 7.3.6 | TS (Node 22) | 0 | accepted, 3 operations |
| goaccess `--persist --restore` | 1.12 (tag build) | C | **1** | wall: `unsupported_syscall_observed`, a `MAP_SHARED` write (#689). The gate row's reason is blank: goaccess's progress line ends without a newline, so Sideeye's `UNKNOWN` line began mid-line and `entry.sh`'s `^UNKNOWN` did not match |
| ostree `remote add` | libostree 2026.4 (release tarball) | C | **1** | wall: unresolvable_path |
| capacitor `telemetry off` | 8.5.2 | TS (Node 22) | **1** | wall: multiple_threads_detected |
| roswell `config set` | 26.02.116 | C (SBCL) | 0 SUPERVISED | accepted, 2 operations (`entry-candidates-7.txt`) |

## The scan's readings (rule 14)

Each veto is decided from the issue's or pull request's body, as on 2026-10-05.

| target | the tracker's text |
|---|---|
| zsh-z `zshz --add` | `#67` (merged 2022) guards the database against being clobbered when the write to its temporary file fails on `ENOSPC`; `#19` asked that `~/.z` not be overwritten through a symlink, which is why the database is now written in place rather than renamed — the shape this explore measured. **Veto**, decided after its explore: the result is kept, the target leaves the slate |

| acme.sh `--set-default-ca` | `#7247` (open, 2026-09) `$domain.conf` emptied when the disk is full, "leaving not-renewable state even after space is freed" — the same `_setopt` writer that rewrites `account.conf`. **Veto**, decided after its explore: the result is kept |
| openssl `ca -revoke` | `#2867` (closed 2017) "CA file rotation is not atomic": two `openssl ca` racing over the same `serial.new`/`index.txt.new` renames — the two-rename rotation this explore measured, found by a targeted search after the scan (`receipts/targeted-searches.txt`). **Veto**, after its explore |
| sfntedit (afdko) `-a` | `#594` (open since 2018) "Replace hacky temp file solutions" names sfntedit's temporary-file write path (`sfntedit.<pid>.tmp`, `sfntedit.BAK`, then `copy_file` over the source) — the write this explore cut. **Veto**, after its explore |
| minizip `-e` | `#985` (merged 2026-04) places the erase command's temporary file on the archive's filesystem — the temporary-file-and-rename erase this explore measured; `#836` an erase corrupting an encrypted archive. **Veto**, after its explore |

Read and not a veto: canonical/lxd (every write-shape hit is the server's storage or database —
`#3634`, `#8111`, `#17087` — none the client's `config.yml`), gilbertchen/duplicacy (`#116` restores
overwriting `preferences` on purpose, `#474` a blank Keychain password; neither a cut-short write of
`preferences`), gorilla-devs/ferium (two hits, neither `config.json`), adobe-type-tools/afdko (none
`sfntedit`'s in-place write; `#1400` asks for UFO output to overwrite, a feature), OpenVPN/easy-rsa
(`#572` a renew broken off at its password prompt, `#1322`/`#1323` temporary-file creation; `#1172`/`#997`
ask revoke not to move files — none a revoke cut short), TiddlyWiki (`#8138` a client-server cache, `#7157`
an import; none the single file rendered over itself), Canop/broot (none the rc-file patch), nih-at/libzip
(`#135` asks for a way to cancel a long `zip_close`, a feature), void-linux/xbps (`#547` an install broken
off in its configure step, another command), pathintegral-institute/mcpm.sh (no write-shape title;
targeted, none on `servers.json`), libsndfile (`#70` an RDWR open-and-close dropping samples through a
header-logic bug, not a write cut short), mozman/ezdxf (none on saving), earendil-works/pi (`#1060` keeps
an invalid `settings.json` from being overwritten, `#10437` reports save failures — neither a write cut
short), pydoit/doit (`#182` dbm.dumb corrupted by concurrent use, another backend and cause),
kovidgoyal/kitty (`#10495` the terminal's own startup on a full disk), alacritty (`#9042` cleans up its
IPC sockets), carloscuesta/gitmoji-cli and withastro/astro (no hit on the hook or the settings file),
roswell (`#522`, `#92` caches after a crash during `ros install` or a load, not `config set`).

## The slate — four waves, eighteen targets

The owner asked for five in each of four waves. The screen ran out first: five scouts and about 1,100 names,
about 790 of them already met, and five targets explored and then vetoed on rule 14 with no spare left to
promote. The owner's ruling (2026-10-07, asked when the count stood at eighteen): **close at eighteen, the
rules unchanged**, so the fourth wave has three. Waves are in the order the targets were explored.

| wave | targets |
|---|---|
| 1 | lxc (Go), duplicacy (Go), ferium (Rust), easyrsa (sh), TiddlyWiki (JS) |
| 2 | broot (Rust), ziptool (C), xbps-pkgdb (C), mcpm (Python), sndfile-metadata-set (C) |
| 3 | ezdxf (Python), pi (TS), doit (Python), kitten (Go), alacritty (Rust) |
| 4 | gitmoji (JS), astro (TS), roswell (C/SBCL) |

Explored, then out of the slate on rule 14 (results kept in `RESULTS.md`): zsh-z, openssl, sfntedit, acme.sh,
minizip. No checkers: the built-in atomicity rule judges, as on 2026-10-05.
