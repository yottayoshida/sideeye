# Results — the two power-loss rules over 46 re-recorded PASS rows (#958)

Recorded 2026-11-01 on Apple silicon: every box `aarch64` Debian, strace 6.13 (`transcripts/*/meta.txt`).
Rows, boxes, defines, rules and controls are `SELECTION.md`'s. The boxes, by image id:
`sideeye-ud1003` `efe80b2ec534`, `sideeye-ud1005` `b512dc31e4e2`, `sideeye-ud1007` `0ca202cca216`,
`sideeye-fu3-1009` `74b5777f4274`, `sideeye-m1014` `a5dca934ffd7`, `sideeye-sv1012` `944375f16467`,
`sideeye-sv170` `0fa8bb99f57e`, `sideeye-r1029` `4a06f64d4d25`.

## The answer to the reopen condition

Of the 85 PASS rows, 46 were re-recorded; the other 39 carry their reason in SELECTION.md.

- **(b) "a rename persists before its data" separates the targets.** 31 of the 46 rename a file
  into their state; **19 do it with no sync of the file first** and are candidates, the other 12
  sync it (or rename something they did not write: 2 such renames, counted apart). 27 of 46 are
  not candidates.
- **(a) "anything unsynced is lost" fails nearly none of them, rather than nearly all.** **37 lose
  every change** — each name back as it was before the operation, which a checker passes; **2 keep
  every change** (samtools, which rewrites in place and `fdatasync`s; ROOT's `rootrm`); **7 leave
  some name as it was at no point** — six over SQLite (Django, sqlite-txn, sqlite-utils, joplin,
  beets, vdirsyncer), each a `-journal` whose create the directory sync made durable and whose
  delete it did not — the journal SQLite rolls back from at its next open, which takes the
  database back to before — and RocksDB's `ldb`, whose `LOG` and newest `.log` are left empty and
  whose `MANIFEST` was written after its last sync. Three of the seven (beets, joplin, `ldb`) also
  leave some names as before and some as after; no row has that mix as its only outcome. No define here
  declares a marker, so (a)'s one failure in ADR 0110's account — an update the tool reported done
  is lost — has nothing to fail against in these rows.

So the condition's "separates targets rather than failing nearly all of them" holds for (b). For
(a) it holds only in the letter: it fails nearly none, and the seven it touches are stores built
to recover from exactly that.

A (b) candidate is a counterexample in all but name: the new name can hold an empty file, which
the built-in invariant judges as neither the old nor the new content. The rows' checkers were
not run here; that the 19 would FAIL is that reading, not a measurement.

The (b) count follows a file through every rename: a file written at one name and renamed twice
is a candidate at its last name, its data never synced under any name.

## The controls

| control | (b) | (a) | wanted |
|---|---|---|---|
| `nosync` (write, rename, no sync) | named | all lost | named, all lost |
| `syncfile` (file synced, then renamed; directory not synced) | not named | all lost | not named, all lost — the rename is lost, so the new content is reached by no name |
| `sync` (file synced, renamed, directory synced) | not named | all kept | not named, all kept |

`apparatus/tabulate.py --selftest` holds fifteen hand-written traces: a sync of another file or of
the directory instead of the source, a sync after the rename, a write after the sync, a
prefix-sharing name, a relative path, a directory synced between a create and its rename (a
temporary file left beside the old name), files rewritten in place with and without a sync, and a
call split across threads.

## The table

| define | renames into state | (b) named | (b) unjudged | (a) | names: old / new / neither | marker | exit |
|---|---|---|---|---|---|---|---|
| alacritty | 2 | `alacritty.toml`, `colors.toml` | 0 | all lost | 2 / 0 / 0 | no | 0 |
| alternatives | 2 | — | 1 | all lost | 3 / 0 / 0 | no | 0 |
| babel | 2 | `translations/fr/LC_MESSAGES/messages.po`, `translations/ja/LC_MESSAGES/messages.po` | 0 | all lost | 2 / 0 / 0 | no | 0 |
| beets-check | 0 | — | 0 | neither old nor new | 2 / 2 / 1 | no | 0 |
| broot | 0 | — | 0 | all lost | 13 / 0 / 0 | no | 0 |
| bzip3 | 0 | — | 0 | all lost | 2 / 0 / 0 | no | 0 |
| conan | 1 | `remotes.json` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| control-nosync | 1 | `key.json` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| control-sync | 1 | — | 0 | all kept | 0 / 1 / 0 | no | 0 |
| control-syncfile | 1 | — | 0 | all lost | 1 / 0 / 0 | no | 0 |
| django | 0 | — | 0 | neither old nor new | 0 / 1 / 1 | no | 0 |
| dotenv | 1 | `.env` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| ggshield | 0 | — | 0 | all lost | 3 / 0 / 0 | no | 0 |
| gitlfs | 4 | `gitconfig` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| joplin-check3 | 0 | — | 0 | neither old nor new | 1 / 2 / 1 | no | 0 |
| juju | 1 | — | 0 | all lost | 1 / 0 / 0 | no | 0 |
| juliaup | 1 | — | 0 | all lost | 1 / 0 / 0 | no | 0 |
| jump | 2 | `scores.json` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| keepassxc-fat | 1 | — | 0 | all lost | 1 / 0 / 0 | no | 0 |
| kitten | 2 | — | 0 | all lost | 3 / 0 / 0 | no | 0 |
| kvantum-fat | 1 | — | 0 | all lost | 1 / 0 / 0 | no | 0 |
| ldb | 2 | — | 0 | neither old nor new | 3 / 2 / 3 | no | 0 |
| lighthouse | 1 | `validators/validator_definitions.yml` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| nerdctl | 1 | `config.json` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| opam | 1 | `config` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| oras | 1 | `config.json` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| perl | 2 | `a.txt`, `b.txt` | 0 | all lost | 2 / 0 / 0 | no | 0 |
| plakar | 1 | `states/8d/8db9d897b7741e3303eb4e5a3ea373c0795ab0e1d175e7573376cb82c3be1dd0` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| podman | 1 | — | 0 | all lost | 2 / 0 / 0 | no | 0 |
| regctl | 1 | `config.json` | 0 | all lost | 1 / 0 / 0 | no | 1 |
| rootrm-check | 0 | — | 0 | all kept | 0 / 1 / 0 | no | 0 |
| rumdl-nocache | 1 | `a.md` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| samtools | 0 | — | 0 | all kept | 0 / 1 / 0 | no | 0 |
| skopeo | 1 | — | 0 | all lost | 1 / 0 / 0 | no | 0 |
| sqlite-txn | 0 | — | 0 | neither old nor new | 0 / 1 / 1 | no | 0 |
| sqlite-utils | 0 | — | 0 | neither old nor new | 0 / 1 / 1 | no | 0 |
| stylelint | 1 | — | 0 | all lost | 1 / 0 / 0 | no | 0 |
| todo.txt | 0 | — | 0 | all lost | 2 / 0 / 0 | no | 0 |
| toybox | 2 | `a.txt`, `b.txt` | 0 | all lost | 2 / 0 / 0 | no | 0 |
| transmission | 1 | `linux-isos.torrent` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| trash | 1 | — | 1 | all lost | 6 / 0 / 0 | no | 0 |
| vdirsyncer | 0 | — | 0 | neither old nor new | 0 / 3 / 1 | no | 0 |
| xbps | 1 | — | 0 | all lost | 2 / 0 / 0 | no | 0 |
| yq | 1 | `deploy.yaml` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| yt-dlp | 0 | — | 0 | all lost | 1 / 0 / 0 | no | 0 |
| ziptool | 1 | `a.zip` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| zlua | 1 | `zlua.db` | 0 | all lost | 1 / 0 / 0 | no | 0 |
| zstd | 0 | — | 0 | all lost | 2 / 0 / 0 | no | 0 |
| zstd-check | 0 | — | 0 | all lost | 2 / 0 / 0 | no | 0 |

Two traces (`todo.txt`, `ldb`) named the operation's standard output by the host's path to the
mounted `/out`; that path is replaced by `/out` in them, which changes no figure here.

`regctl` exits 1 as its define declares (`expected_status = "1"`: the registry is unreachable and
the configuration is written anyway). `exit` is the operation's under strace.

ADR 0110 counted kitty as untraced; re-recorded here as `kitten`, it syncs its file and not the
directory, like nine others here (alternatives, juju, juliaup, keepassxc-fat, kvantum-fat, podman,
skopeo, stylelint, xbps).

## What this does not measure

- **A file rewritten in place with `O_TRUNC`** and not synced falls under both rules as "lost":
  the content reverts to before. A rule that empties it — ext4's other 2009 case — is a third model.
- **Writes through a shared mapping**: the traces carry `msync` but not `mmap`, so a write that
  never calls `write` is not seen; none of the 46 calls `msync`, `syncfs` or `sync`. RocksDB's
  `ldb` calls `sync_file_range` six times, which neither rule counts as a sync (ADR 0110). No
  trace holds an `O_SYNC` or `O_DSYNC` open.
- **A name the run touched without creating it** is taken as there before the operation when
  `pre.txt` does not list it — a name outside the state directory, or one a child made. Three
  shapes the judge reads wrongly occur in none of the 46: such a name written and synced reads as
  lost; a listed name synced in place and then replaced by a lost rename reads as before; and a
  name is judged by its own directory's syncs only, so a child outlives a parent's lost rename.
- **The 39 rows not re-recorded**, and filesystems: the rules are POSIX's minimum, not ext4's,
  XFS's or APFS's (ADR 0110's second reason).
