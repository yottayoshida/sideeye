# 2026-10-10 — every place dotenvx writes a file, after the fix for dotenvx/dotenvx#1012

The maintainer fixed #1012 in 2.34.2 (dotenvx/dotenvx#1014: `fsx.writeFileX` and `fsx.writeFileXSync`
now go through `write-file-atomic`) the same day, asked "did it find anything else?", and closed the
issue with "just open more for anything you find". This run takes that at its word: every call in
2.34.2 that writes, appends, truncates or removes a file, found by reading the source, each with what
was done about it.

Source read: the `v2.34.2` tarball (`588238c571`), `src/` in full, and its three `@dotenvx/*`
dependencies as npm resolves them today (`primitives` 3.3.0, `providers` 0.3.5, `tooling` 1.0.5).

## The fix itself, beside the build before it (2.32.4, the version #1012 measured)

| # | operation | what is at stake | what this run does |
|---|---|---|---|
| A1 | `encrypt -f .env` — the #1012 shape | `.env` | Sideeye, both versions; the issue's strace line, both versions |
| A2 | `encrypt -f .env.production` while `.env.keys` already holds `.env`'s key | **`.env.keys`**: the private key for a `.env` that is committed encrypted | Sideeye, both versions |
| A3 | `encrypt -f .env -f .env.production` | the two env files and the key file, together | Sideeye, both versions |
| A4 | `set` on an encrypted `.env` | `.env` | Sideeye, both versions |
| A5 | `decrypt -f .env -f .env.production` | the two env files | Sideeye, both versions |
| A6 | `del` on an encrypted `.env` | `.env` | Sideeye, both versions |

## Writes the fix did not reach (2.34.2)

| # | where | call | what is at stake | what this run does |
|---|---|---|---|---|
| B1 | `protect` → `uninstallPrecommitHook.js:62` | `fs.writeFileSync(hookPath, next)` | `.git/hooks/pre-commit` when it holds the user's own hook beside the block `precommit --install` appended; not under version control | Sideeye |
| B2 | `protect` → `installProtectFilter.js:46` | `fs.writeFileSync(attributesPath, migrated)` | the user's global git attributes file (`core.attributesFile`), rewritten when it holds the old `filter=dotenvx` lines | Sideeye |
| B3 | `protect` → `removeLegacyProtectFilter.js:39` | `fs.writeFileSync(attributesPath, updated)` | the repository's `.git/info/attributes` | Sideeye |
| B4 | `protect`, interactive, a protection unticked → `protectSettings.js:23` | `fs.writeFileSync(filename, updated)` | the user's global git ignore file and attributes file | needs a terminal; tried under `script` |
| B5 | `spec --overwrite` → `services/init.js:70` | `O_TRUNC` open of `Envfile` | `Envfile` (generated from the env files; usually committed) | Sideeye |
| B6 | `gitignore`, `precommit --install`, `protect` (ignore) | `fs.appendFileSync` | `.gitignore`, the hook, the global ignore file | Sideeye on `gitignore` (append, no truncation) |

## Shapes the fix brings

| # | what | what this run does |
|---|---|---|
| C1 | `write-file-atomic` writes `<file>.<hash>` and renames it; its cleanup runs on exit signals but not on SIGKILL. A kill leaves `.env.keys.<hash>` (the private key) or, during `decrypt`, `.env.<hash>` (plaintext) beside the real file. `dotenvx help` still shows `dotenvx gitignore --pattern .env.keys`, an exact name the leftover does not match | strace kill, then `git status` under that `.gitignore`, and under `protect` |

## Read, not measured

| # | where | why not measured |
|---|---|---|
| D1 | `armor down` (`services/armorDown.js:37–61`): the POST to the armor service comes before `.env.keys` is written | the service is dotenvx's; whether that POST drops the server's copy cannot be seen from here |
| D2 | `native up/down` (`keychainUp.js`, `keychainDown.js`), and `encrypt` storing a new key in the OS store (`resolveLocalKey.js:51`) | no OS secret store in the box. Order read: store, verify, then remove from `.env.keys`; write `.env.keys`, then delete from the store |
| D3 | `1password` / `bitwarden` up/down/push/pull (`custodyTransfer.js`) | needs those services. Order read: set, read back, then remove locally; write locally, read back, then delete remotely |
| D4 | `login`, `settings` (the `conf` store bundled in `@dotenvx/tooling`) | read: written through `atomically` (temporary file and rename) |
| D5 | power loss | Sideeye does not model it. `write-file-atomic` fsyncs the file, not the directory |

## Second pass: what the first pass did not reach

The first pass covered every write in `src/` with one process, killed before each syscall, on a two-line
`.env`, on Linux. The owner asked whether that was exhaustive; it was not. Added:

| # | what | how |
|---|---|---|
| E1 | two `set` at once on one `.env` / `.env.keys` | parallel processes, many rounds, every value read back |
| E2 | two `encrypt` at once, different env files, one shared `.env.keys` (`-fk`, the monorepo layout) | the same |
| E3 | `encrypt` while `run`/`get` reads | the same; a reader must see the old or the new values |
| F1 | value shapes through `encrypt` → `get`, `decrypt`, `set`: multi-line, quotes of each kind, `#`, `$` and `${}`, backslashes, CRLF, `export`, duplicate keys, empty, no trailing newline, unicode, long | every value read back equal to what `get` read before |
| G1 | `genexample`, `precommit --install` (new hook and appended), `set --plain`, `encrypt -k`/`--exclude-key`, `encrypt` with an Envfile, `-fk` in another directory, `.env` / `.env.keys` as symlinks | Sideeye where it writes; modes and owners after |
| H1 | 2.34.2's `encrypt`, `set`, `decrypt` with the write, fsync or rename failing (ENOSPC, EACCES, EIO) | strace inject; every value read back |
| I1 | `1password` / `bitwarden` up/down/push/pull against a stand-in `op` / `bw` on PATH | Sideeye on the `.env.keys` side, the stand-in's store judged with it |
