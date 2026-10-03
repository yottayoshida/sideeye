# Results — 2026-10-03 user-data

Twenty targets in four rounds of five (`SELECTION.md`) — the rounds are the slate's grouping, not the order they ran in (`transcripts/explore-batch-*.txt` has the order) — each explored by `apparatus/run.sh`
in a box of its own with **the released v1.7.0** (hcloud twice, below) (`apparatus/explore.sh`; engine lines in
`transcripts/explore/<t>/engine.txt`). Default mode first; a static target's `no_shim_marker` named
`--observe supervised` and was followed, podman's `oracle_missed_operation` named
`--observe syscalls` and was followed. Every FAIL was replayed twice (both FAIL) and its evidence
bundle written. No checkers: the built-in atomicity rule judges.

**12 FAIL, 7 PASS, 1 named wall.** All twelve FAILs are one shape — the rewritten file opened (or
`truncate`d) and the kill before its write: the file at 0 bytes, the old bytes nowhere in the state
root. The seven PASSes say why they passed; five of them are the temporary-file-and-rename the FAILs
lack.

## Round 1

| target | verdict | where | report |
|---|---|---|---|
| samtools 1.24 `reheader -i` | **PASS** 4/4 (3 crash points) | the new header is one 302-byte `write` over the old one in an `O_RDWR` file, then `fdatasync` — a single write a process kill cannot split. A torn write (power loss) is exactly what it cannot survive and was not measured | — |
| doing 2.1.124 `now` | **FAIL** 1/3, crash point 2 of 2 | `doing.md` opened `O_TRUNC`, killed before the write | not filed: doing copies the file to its backup directory **before** truncating it (`transcripts/probe-doing-backup-order.txt`), so `doing undo` restores it |
| mapshaper 0.7.72 `-o force` | **FAIL** 5/11, first at crash point 2 of 10 | `a.shp` opened truncating, killed before its write: 0 bytes beside the untouched `.shx` and `.dbf`. The report itemises only the earliest of the five violating worlds | **filed, [mbloch/mapshaper#706](https://github.com/mbloch/mapshaper/issues/706)** |
| hcloud 1.69.0 `context use` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `cli.toml` opened truncating | not filed: API tokens a user re-issues from the console — 2026-09-28's kubectl reason. Measured twice: the first seed's placeholder tokens had a real token's length, so they were shortened and the gate and explore re-run; same verdict |
| talosctl 1.14.2 `config context` | **FAIL** 1/3, crash point 2 of 2 (supervised) | the talosconfig opened truncating; at talos `main` (`3663614`) the writer is `fileutils.WriteSecret` → `os.WriteFile`. The measured 1.14.2 run recorded no permission write | not filed — see below |

## Round 2

| target | verdict | where | report |
|---|---|---|---|
| kakoune 2026.05.21 `-f` | **FAIL** 2/5, crash point 2 of 4 | each file opened truncating | not filed: `writemethod` defaults to `overwrite` and documents `replace` (a temporary and a rename) as the alternative; the files are usually under version control |
| nushell 0.116.0 `save -f` | **FAIL** 1/4, crash point 3 of 3 | `a.json` opened truncating | not filed: nushell's `AGENTS.md` says an agent must never create an issue — a policy this report could not follow |
| Babel 2.18.0 `pybabel update` | **PASS** 7/7 (6 crash points) | each catalogue written to `tmpmessages.po` and renamed over `messages.po` | — |
| notesmd-cli 0.3.7 `move` | **FAIL** 2/6, crash point 3 of 5 (supervised) | the move rewrites every note that links to the moved one with `os.WriteFile`; the killed world leaves `daily/2026-10-01.md` empty | **filed, [Yakitrak/notesmd-cli#137](https://github.com/Yakitrak/notesmd-cli/issues/137)** |
| kubectx 0.11.0 | **FAIL** 6/9, crash point 3 of 8 (supervised) | `truncate(config)` then the write | not filed: the kubeconfig reason of 2026-09-28 (regenerable; one write long) |

## Round 3

| target | verdict | where | report |
|---|---|---|---|
| transmission-edit 4.1.0~beta2 `-a` | **PASS** 4/4 (3 crash points) | `linux-isos.torrent.tmp.XXXXXX` created `O_EXCL`, renamed over the torrent | — |
| perl 5.40.1 `-i -pe` | **PASS** 7/7 (6 crash points) | each file written to a random name in the same directory and renamed over it (perl's in-place editing since 5.28) | — |
| z.lua 1.8.26 `--add` (clock pinned) | **PASS** 6/6 (5 crash points) | `zlua.db.<time><random>` written and renamed over `zlua.db` | — |
| kubecm 0.35.1 `delete` | **FAIL** 1/3, crash point 2 of 2 (supervised) | the kubeconfig opened truncating | not filed, as kubectx |
| podman 5.4.2 `system connection default` | **PASS** 7/7 (6 crash points, `--observe syscalls`) | a `.lock` file, then `.tmp-podman-connections.json<n>` created `O_EXCL` and renamed | — |

## Round 4

| target | verdict | where | report |
|---|---|---|---|
| bzip3 1.5.4 `-e --rm` | **PASS** 5/5 (4 crash points) | `a.log.bz3` written and `fsync`ed, then `a.log` unlinked | — |
| dotter 0.13.5 `deploy -f` | **UNKNOWN `kill_did_not_land`** (supervised, 8 worlds of 10 crash points) | the report: "a world was asked to die before a given operation and did not". It counted 4 violations among the 8 worlds before refusing, and 4 `fchmod`/`fchmodat` writes; preflight accepted both recorded runs at 10 operations. The cause was not measured — restore resetting modes is as plausible as a varying sequence | — |
| luarocks 3.13.0 `config` | **FAIL** 1/5, crash point 4 of 4 | `config-5.4.lua` opened truncating | not filed: a settings file a user rewrites in a line |
| minikube 1.39.0 `config set` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `config.json` opened truncating | not filed, as luarocks |
| kustomize 5.8.2 `edit set image` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `kustomization.yaml` opened truncating | not filed: under version control |

`transcripts/write-paths-pass*.txt` holds each PASS's write path as `strace` printed it.

## What was filed, and how it was decided

The owner asked that only critical findings go upstream and that they be discussed first. Critical
was read as 2026-09-07 read it: the bytes are gone and nothing gives them back. After the explores,
four findings were put to the owner with that reading. The owner chose all four, then — talosctl's
tracker turning out to ask for no AI-generated explanation — approved three texts verbatim and chose
not to file the fourth:

| finding | why critical | filed |
|---|---|---|
| notesmd-cli `move` empties the notes that link to the moved one | an Obsidian vault is often not under version control, and the note lost is not the one the user touched | [Yakitrak/notesmd-cli#137](https://github.com/Yakitrak/notesmd-cli/issues/137) |
| mapshaper `-o force` empties `.shp` while `.shx`/`.dbf` stay old | the layer no longer imports, and the original geometry is in no other file (`transcripts/probe-mapshaper-after.txt`) | [mbloch/mapshaper#706](https://github.com/mbloch/mapshaper/issues/706) |
| DwarFS `--recompress -f` onto its own input destroys it | found in a plain run, no crash: the image is gone the first time a user tries it | [mhx/dwarfs#388](https://github.com/mhx/dwarfs/issues/388) |
| talosctl empties the talosconfig | the client certificate and key for every context; without the cluster's secrets bundle, a user is locked out | **not filed** — see below |

Each was reproduced with no crash before it was written up. DwarFS needs nothing: its loss is a plain
run. For the others `ulimit -f 0` stood in for the failed write (`transcripts/ulimit-repro.txt`):
notesmd-cli 51 → 0 bytes, mapshaper `a.shp` 184 → 0, talosctl 3,086 → 0 (and nushell, not put forward, 53 → 0) and `talosctl config contexts` then fails `error reading config:
EOF`. Each cites the writer at a named commit read in a shallow clone: notesmd-cli `0b6f10f`
(`Note.UpdateLinks`, `os.WriteFile`), mapshaper `8e8a24e` (`cli.writeFileSync` from
`mapshaper-file-export.mjs`), DwarFS v0.15.8 `75140c4` (`open_output_binary` at line 1276 before
the input filesystem at line 1329). Each is within twice its tracker's median issue length (143, 65
and 65 words; 260, 99 and 87 written). The texts are `report-*.md`.

Contribution policies, read before writing: notesmd-cli has a bug template and no AI policy; mapshaper
and DwarFS have neither; **siderolabs/talos's bug template asks for "evidence from the failure, not a
long code analysis or an AI-generated explanation"**, so the owner's choice was not to file it
(writing it in their own words was the other option); nushell's `AGENTS.md` forbids an agent to create
issues, so nushell was not put forward.

## A Sideeye limit the run met twice

`recording_run_failed` on upx and argocd is one cause: **restore does not reproduce permission
bits** — the report's own `metadata` line says crash worlds run at the engine's default modes — so a
target that checks a mode in its state root behaves differently on the second recorded run.
`apparatus/probes/modebit/` shows it with no target at all (`transcripts/probe-modebit.txt`): a
`0755` script in the state root is `0644` after the first restore and cannot be exec'd. preflight
says "Change the define", and no define can. The owner chose to file it on this repository's own
tracker (`issue-sideeye-mode-restore.md`, filed after this record is on `main` because it points
here).

## What this run does not say

- The packaged builds (perl, transmission-cli, podman, mu, flatpak) are Debian's, behind upstream.
  None of them is a filed FAIL.
- notesmd-cli's gate refused `multiple_threads_detected` in 2 of 5 runs; the explore that judged it
  happened to be accepted. A rerun may refuse.
- No power loss, no torn writes (samtools' PASS depends on the second).
- The funnel counts DwarFS as an explored, judged FAIL (its filing has no stage that is not an engine
  counterexample; the row's note says so), so `docs/outcome-funnel.md` shows 13 new FAILs to this
  record's 12.
