# 2026-10-10 — dotenvx after the fix for #1012, every place it writes

**The fix holds for every write it touched: `encrypt`, `set`, `decrypt` and `del`, six shapes, FAIL on
2.32.4 and PASS on 2.34.2 with the same define, checker and engine. Five calls it did not touch empty a
file the user wrote — four of them under `dotenvx protect` — on a kill and on a full disk alike. And
the fix brings a shape of its own: a kill before its rename leaves `.env.keys.<number>` holding every
key `.env.keys` held, and a `.gitignore` that names `.env.keys` does not cover it.**

The list of what was looked at, and why, is [SELECTION.md](SELECTION.md); every row of it has a result
below. The owner asked whether the first pass was exhaustive; it was not (one process, killed, on a
two-line file, on Linux), and the second pass below took the rest. Three reports went upstream, each
with the owner's approval of the full text: dotenvx/dotenvx#1016, #1017 and #1018 (the last section).

## Apparatus

`apparatus/build.sh` → the box `sideeye-dx1010`: Debian trixie arm64, node v20.19.2, git 2.47.3,
strace 6.13, the released Sideeye v1.10.0 (installed by the page's `install-sideeye.sh`, digest
checked), and dotenvx 2.32.4 and 2.34.2 each in a prefix of its own (`/opt/dx-<version>`; only 2.34.2
carries `write-file-atomic` 5.0.1, `/versions.txt`). `apparatus/run.sh` is 2026-10-09 follow-ups 3's
with the version as a second argument; every explore ran in a box of its own, `--network none`,
`UV_THREADPOOL_SIZE=1` as in #1012's run. Every FAIL was replayed twice and FAILed both times.

Before any explore, `apparatus/lab-3.sh` ran each define by hand: the checker passes before the
operation and after it, and fails when the file it judges is emptied (`transcripts/lab-3.txt`). The
leak checker of C1b was also shown a planted copy of `.env.keys` it had to refuse, and the same copy
under `.env.keys*` it had to accept (`transcripts/lab-6.txt`).

## The fix, beside the version #1012 measured

Checker: every value reads back through `dotenvx get` (the version under test), from whichever files
hold it, with whatever `.env.keys` holds.

| # | operation | 2.32.4 | 2.34.2 |
|---|---|---|---|
| A1 | `encrypt -f .env` (#1012) | **FAIL** 1/5 — `.env` emptied | **PASS** 11/11 |
| A2 | `encrypt -f .env.production` while `.env.keys` holds `.env`'s key | **FAIL** 2/5 — `.env.keys` emptied: the encrypted `.env` cannot be decrypted (world 2) | **PASS** 11/11 |
| A3 | `encrypt -f .env -f .env.production` | **FAIL** 2/7 | **PASS** 16/16 |
| A4 | `set` on an encrypted `.env` | **FAIL** 2/5 | **PASS** 11/11 |
| A5 | `decrypt -f .env -f .env.production` | **FAIL** 2/5 | **PASS** 11/11 |
| A6 | `del` on an encrypted `.env` | **FAIL** 1/3 | **PASS** 6/6 |

A2 is the worst of the six on 2.32.4: `.env` is encrypted and usually committed, and its only private
key was in the file being rewritten. The issue's own reproduction line no longer kills 2.34.2 at all —
its writes go to a temporary name `-P .env` does not match — and `encrypt` completes
(`transcripts/lab-1.txt`); the explores are what say the window is closed.

## Writes the fix did not reach (2.34.2)

Checker: the lines the user wrote are still in the file.

| # | where | result | without Sideeye (`transcripts/lab-5.txt`) |
|---|---|---|---|
| B1 | `protect` → `uninstallPrecommitHook.js:62`: `.git/hooks/pre-commit` holding the user's hook and the block `precommit --install` appended | **FAIL** 1/3 — 0 bytes | SIGKILL: 438 → 0 bytes. ENOSPC on the write: exit 1, 0 bytes |
| B2 | `protect` → `installProtectFilter.js:46`: the global attributes file holding the old `filter=dotenvx` lines | **FAIL** 1/4 — 0 bytes | the same, both ways; `filter.dotenvx.required` is already `true` |
| B3 | `protect` → `removeLegacyProtectFilter.js:39`: `.git/info/attributes` with the legacy local filter | **FAIL** 1/3 — 0 bytes | the same, both ways |
| B4a | `protectSettings.removeIgnore()`: the global ignore file | **FAIL** 1/6 — 0 bytes | — |
| B4b | `protectSettings.removeFilter()`: the global attributes file | **FAIL** 1/3 — 0 bytes | — |
| B5 | `spec --overwrite` → `services/init.js:70`: `Envfile` | **FAIL** 1/3 — 0 bytes | the same, both ways |
| B6 | `gitignore --pattern` (`fs.appendFileSync`) | **PASS** 3/3 | — |

`precommit --install` prints `[DEPRECATED] dotenvx precommit. fix: run [dotenvx protect]`, so B1 is the
path dotenvx itself sends a user with an existing hook down. B4 is reached by unticking a protection
in the interactive prompt, which needs a terminal; the operation calls the two functions that path
calls (`node -e "require(...protectSettings.js).removeIgnore()"`): the same code, not the same entry.
B4a's first explore was **UNKNOWN `kill_did_not_land`**, and the mistake was this run's: the function
unsets `dotenvx.protect.ignoreFile` in git's global config after its write and refuses to run without
it, and that config sat outside the state, so no world after the first was restored to it. With
`GIT_CONFIG_GLOBAL` under the state (scratch) it reached a verdict. The five lines are the same on
`main` at `23d7887d5c`.

## The shape the fix brings

`write-file-atomic` writes `<file>.<number>` and renames it over `<file>`; its cleanup is a
`signal-exit` handler, which SIGKILL never reaches.

| # | setup | result |
|---|---|---|
| C1 | first `encrypt` of a plaintext `.env`, `.gitignore` naming `.env.keys` | **FAIL** 2/11 — `.env.keys.<number>` stageable; the key in it encrypts nothing yet (`.env` was not written), so on its own this one leaks nothing |
| C1b | `.env` encrypted and committed, then `encrypt -f .env.production`, `.gitignore` naming `.env.keys` | **FAIL** 2/11 on 2.34.2 — `.env.keys.<number>` stageable, and it decrypts the committed `.env` (worlds 3 and 4: after the temporary file's write, and after its fsync). 2.32.4 FAILs the same define the A2 way, `.env.keys` emptied |

Without Sideeye (`transcripts/lab-4.txt`, `lab-5-c1b.txt`), SIGKILL at the first rename:
`git add -A` stages `.env.keys.318634236`, and `dotenvx get DB_PASSWORD -f .env -fk
.env.keys.318634236` prints the committed value. A later `encrypt` succeeds and leaves the file where it
is. `decrypt` killed at its rename leaves `.env.<number>` in plaintext, staged the same way. A
`.gitignore` holding `.env*` (the pattern `dotenvx gitignore` writes by default) ignores both, and
`protect` refuses both at `git add` (`PRIVATE_KEY_FILE` for any name starting `.env.keys`,
`PLAINTEXT_ENV` for the other). The name-only line is the one `dotenvx help` still shows
(`dotenvx gitignore --pattern .env.keys`).

## Read, not measured

| # | where | read |
|---|---|---|
| D1 | `armor down` (`armorDown.js:37–61`) | the POST to the armor service comes before `.env.keys` is written. Whether that POST drops the service's copy cannot be seen from here; not raised |
| D2 | `native up/down`, and `encrypt` storing a key in the OS store (`resolveLocalKey.js:51`) | store, read back, then remove from `.env.keys`; write `.env.keys`, then delete from the store. No OS secret store in the box |
| D3 | `1password` / `bitwarden` (`custodyTransfer.js`) | set, read back, then remove locally; write locally, read back, then delete remotely |
| D4 | `login`, `settings` (`conf` in `@dotenvx/tooling`) | written through `atomically` |
| D5 | power loss | not modelled; `write-file-atomic` fsyncs the file and not the directory |

## Second pass: what Sideeye does not test, and the custody paths

| # | what | result |
|---|---|---|
| E1 | two `set` at once on one `.env` (`apparatus/lab-8.sh`) | one value lost, 20/20 rounds, both versions; one after the other, both kept |
| E2 | two first `encrypt`s of `apps/a/.env` and `apps/b/.env` at once, one `-fk .env.keys` | **one file undecryptable**, 20/20, both versions: its plaintext replaced by ciphertext under a key the other run's write dropped |
| E3 | the same with a third file already encrypted under the shared file | one of the two new files undecryptable, 20/20 |
| — | where the key goes when an OS secret store is present (`lab-15.sh`, the stand-in `secret-tool`) | into the store, even with `-fk`; `.env.keys` only with `--no-native` or `DOTENVX_NO_NATIVE`. E2 and E3 need keys kept in the file |
| F1 | 27 value shapes through `encrypt`, `decrypt` and `set` (`lab-9.py`), then a `$` in a password (`lab-10.sh`) | **`decrypt` drops the backslash of `\$`**: `PW=pa\$sword` reads `pa$sword` before and after `encrypt`, and `pa` after `decrypt`, encrypting again keeping `pa`; double quotes the same, single quotes not. Both versions. `set KEY '$HOME'` expanding on read is the documented behaviour (dotenvx/dotenvx#562) and not counted |
| G1 | modes, owners, symlinks, hard links, and the commands the first pass did not run (`lab-11.sh`, `lab-12.sh`) | `genexample`, `precommit --install`, `set --plain`, `encrypt -k`, an Envfile and `-fk` elsewhere behave the same on both versions. 2.34.2 keeps `.env`'s mode and owner and sets `.env.keys` to 0600 (2.32.4 left a chmod in place). Two changes from the fix: a hard link to `.env` is broken (the twin keeps the plaintext), and a `.env.keys` symlink whose target does not exist yet is replaced by a regular file in the project (an existing target is written through, as before) |
| H1 | 2.34.2's `encrypt`, `set` and `decrypt` with every write, fsync or rename failing ENOSPC, EACCES or EIO (`lab-11.sh`) | 27/27 hold the old values and leave no temporary file |
| I1 | `native up` / `down`, `encrypt` with a secret store, `1password up` / `down`, against stand-ins (`fake/`) that save through a rename | **PASS** 5/5 with Sideeye, 6 to 21 explored worlds; the checker finds the key in `.env.keys`, the stand-in keyring or the stand-in 1Password, and refuses a state with all three emptied (`lab-13.sh`) |

Dropped, with the reason: **Bitwarden** — the order on dotenvx's side is the same `custodyTransfer` as
1Password's, its provider creates, reads back and records in the same order, and a stand-in would
have to play `bw`'s unlock and session exchange. **armor** — the service is dotenvx's. Power loss and
macOS are outside this box.

E1 to E3 and F1 are not Sideeye verdicts: Sideeye's reports list concurrent processes under `not tested`,
and F1 involves no crash. Their records are plain scripts, and the reports say so.

## Reported upstream (2026-10-10)

Picked by value, not by FAIL: a FAIL was filed when the loss is of something git does not hold and the
conditions are ones a user meets, and each report covers what one pull request would fix (the owner's
ruling: issues may be grouped, but by the fix).

| report | what | the record |
|---|---|---|
| dotenvx/dotenvx#1016 | `decrypt` drops the backslash of `\$` (F1) | `report-escape.md`, `transcripts/lab-10.txt`, `lab-14.txt` (the text's reproduction run verbatim) |
| dotenvx/dotenvx#1017 | two `encrypt` at once on one shared key file (E2, with E1 named) | `report-concurrent.md`, `transcripts/lab-8.txt`, `lab-14.txt` |
| dotenvx/dotenvx#1018 | `protect`'s four `fs.writeFileSync` call sites and `spec --overwrite` (B1 to B5) | `report-protect.md`, `transcripts/lab-5.txt`, `lab-7.txt` |

Not filed: C1b (a SIGKILL in the fsync window, a name-only ignore and an unread `git add -A`, all three
needed), the two G1 changes, and a comment on #1012, which is closed (its one line of news is the last
paragraph of #1018).
