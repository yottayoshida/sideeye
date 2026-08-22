# pass (password-store) 1.7.4 — scouting notes

Checkout: `targets/pass`. Single-file program: `src/password-store.sh` (721 lines,
read in full). Also read `man/pass.1` and `README`.

## 1. Persistent state

- **State root**: `$PASSWORD_STORE_DIR` (default `$HOME/.password-store`),
  bound to `PREFIX` at `src/password-store.sh:15`. This directory is read AND
  written by every subcommand — not a cache.
- **Layout**: one `.gpg-id` file per gpg-id scope (root and optionally per
  subfolder, `set_gpg_recipients()` walks up from the target looking for the
  nearest `.gpg-id`, `src/password-store.sh:82-107`), plus one `<name>.gpg`
  file per password entry, plus an *optional* `.git` repo at the store root
  (`cmd_git`, `src/password-store.sh:652-670`) that most commands opportunistically
  commit into if present (`set_git` / `git_add_file` / `git_commit`,
  `src/password-store.sh:30-48`).
- **Not state**: `$SECURE_TMPDIR` (`tmpdir()`, `src/password-store.sh:216-244`)
  — a `/dev/shm`- or `$TMPDIR`-rooted scratch dir, shredded/removed on EXIT via
  `trap`. Used only by `cmd_edit` and by `cmd_git` (to keep git's own tmp files
  off disk unencrypted). Not part of the store's persistent identity.

## 2. Commands that write state, especially multi-file

Every mutating subcommand writes at minimum one `.gpg` file (or `.gpg-id`) and,
if `$INNER_GIT_DIR` is set, a *second*, temporally separate write: a `git add`
+ `git commit` (`git_add_file`, `src/password-store.sh:37-42`). That two-phase
shape (content file first, commit second) applies uniformly to `insert`,
`edit`, `generate`, `rm`, `mv`, `cp`, `init`.

Genuinely **multi-file** operations (richest crash windows):

- **`reencrypt_path()`** (`src/password-store.sh:110-141`): loops over every
  `*.gpg` file under a given path with `find ... -print0`, and for each one
  whose current recipient-key set differs from the target set, does
  `gpg -d ... | gpg -e ... -o "$passfile.tmp.$RANDOM..." ...` then
  `mv "$passfile_temp" "$passfile"` (line 136-137). The `mv` per file is atomic,
  but the loop across N files is not — a crash after file 3 of 7 leaves the
  store with a mixed set of old-key and new-key ciphertexts. Called from:
  - `cmd_init` (`src/password-store.sh:364`) whenever `pass init <gpg-id>` is
    run against a path that already has entries.
  - `cmd_copy_move` (`src/password-store.sh:630`, `647`) after `mv`/`cp` of a
    directory, if the destination falls under a different `.gpg-id` scope.
- **`cmd_init`** (`src/password-store.sh:321-366`) itself writes `.gpg-id`
  (`mkdir -p` + `printf ... > "$gpg_id"`, line 347-348), optionally
  `.gpg-id.sig` (line 357), then calls `reencrypt_path` (multi-file, above),
  then commits — up to three separate `git_add_file` calls in one invocation
  (lines 351, 360, 365), each its own commit if the tree is dirty.
- **`cmd_delete -r`** (`src/password-store.sh:565-595`): `rm -r -f -v "$passdir"`
  unlinks every `.gpg` file under a directory in one shell command, but `rm -r`
  itself is not atomic across files; the store-wide `git rm -qr` + commit
  happens only after the whole `rm -r` returns.
- **`cmd_copy_move`** in `cp` mode (`src/password-store.sh:645-649`): a
  directory copy is `cp -i -r -v "$old_path" "$new_path"`, which GNU cp
  performs file-by-file (not one atomic operation), followed by a conditional
  `reencrypt_path` and a single trailing commit.

## 3. Documented promises (checker material)

- **`man/pass.1:42-44`**: *"If the password store directory is a git
  repository, all password store modification commands will cause a
  corresponding git commit."* This is an explicit, falsifiable global
  invariant: after any mutating subcommand returns (or after recovery from a
  crash mid-command), the working tree of `$PASSWORD_STORE_DIR` must match
  `git status --porcelain` exactly (nothing untracked, nothing uncommitted) —
  or the operation must not have visibly taken effect at all.
- **`man/pass.1:67`** (`init`): *"used in any existing files, these files will
  be reencrypted to use the new id"* — after `pass init <id>` completes, every
  `.gpg` file under the affected path must decrypt-verify under the new
  recipient set (not a mix of old/new).
- **`man/pass.1:157-158`, `164-165`** (`mv`/`cp` onto a directory target):
  *"Passwords are selectively reencrypted to the corresponding keys of their
  new destination."* Same shape of promise, scoped to the moved/copied subtree.
- **`cmd_generate` usage text** (`src/password-store.sh:298-302`, mirrored in
  the man page): `--in-place` *"replace only the first line of an existing
  file with a new password"* — an explicit conservation promise: lines 2+ of
  the decrypted file must be byte-identical before and after.

## 4. fsck / doctor / verify / undo

**No such subcommand exists.** The dispatch table (`src/password-store.sh:705-720`)
has exactly: `init, help, version, show/ls/list, find/search, grep, insert/add,
edit, generate, delete/rm/remove, rename/mv, copy/cp, git, <extension-or-show>`.
There is no `pass fsck`, `pass check`, `pass verify`, or `pass doctor`. The only
built-in verification is `verify_file()` (`src/password-store.sh:59-69`), which
checks a detached GPG signature on the **`.gpg-id` file only**, and only when
`$PASSWORD_STORE_SIGNING_KEY` is set — not a store-wide integrity check.
Recovery, if any, is expected to come from `pass git <git-command>`
(`cmd_git`, line 652) — i.e. the store's own git history is the only
undo/repair mechanism the tool provides. That makes the promise in §3
(“every mutation ⇒ a commit”) doubly load-bearing: if it's violated, `git
checkout .` / `git reset --hard` cannot be trusted to recover to a known-good
state, because the tool itself said every mutation *would* be captured.

## 5. Determinism expectation

**Expect trouble, target-dependent.** Two independent randomness sources:

1. **GPG public-key encryption is not deterministic ciphertext-for-plaintext.**
   Every `$GPG -e` call (`insert`, `edit`, `generate`, `reencrypt_path`) embeds
   a fresh random session key and padding per OpenPGP framing, so encrypting
   the *same* plaintext to the *same* recipient twice produces different
   bytes each time — independent of any crash-consistency engine. `--compress-algo=none`
   (`src/password-store.sh:9`) removes one non-determinism source (gzip
   internals) but not this one. **Any proposal whose crash-window operation
   calls `gpg -e` is at high risk of baseline-recording refusal on ciphertext
   bytes**, unless the harness treats `.gpg` payload bytes as opaque and only
   checks decrypted content / file existence / git-tree consistency rather
   than raw bytes.
2. **`cmd_generate` explicitly reads `/dev/urandom`** (`tr -dc "$characters" < /dev/urandom`,
   `src/password-store.sh:539`) to build the new password value itself —
   nondeterministic by design, on top of (1).
3. Temp filenames use `$RANDOM` four times (`src/password-store.sh:120`, `544`)
   — transient, renamed away before the command returns, but a crash landing
   *between* the temp write and the `mv` would leave a nondeterministically-named
   stray file in the directory listing, which could itself defeat a
   byte-reproducible baseline if the checker/recorder inventories directory
   contents rather than just the final tracked paths.
4. Git commits stamp author/committer time unless `GIT_AUTHOR_DATE` /
   `GIT_COMMITTER_DATE` are pinned by the harness — a generic git-tool caveat,
   not specific to `pass`.

Net: operations that **avoid calling `gpg -e`** (a same-scope `cp`/`rm` that
never triggers `reencrypt_path`) are the best determinism bet; anything
touching `init`, `generate`, or a cross-scope `mv`/`cp` should be assumed to
fail baseline recording on raw bytes unless the engine can special-case or
intercept GPG's/urandom's randomness.

## Proposals

### P1 — same-scope directory `cp` (deterministic multi-file copy + trailing commit)

- **argv**: `pass -- cp -r work/clientA work/clientA-copy` run with
  `PASSWORD_STORE_DIR=<state-dir>` exported, where `<state-dir>` already has a
  single root `.gpg-id` (no nested `.gpg-id` under `work/`), a git repo
  (`pass git init` already run), and `work/clientA/` contains 3+ `.gpg`
  entries plus a subdirectory.
- **why**: `cmd_copy_move` (`src/password-store.sh:645-649`) does a
  non-atomic, file-by-file `cp -r`, then calls `reencrypt_path "$new_path"`
  (line 647) — which, because source and destination share the same
  `.gpg-id` scope, finds `gpg_keys == current_keys` for every file
  (`src/password-store.sh:134`) and re-encrypts **nothing**, then a single
  `git_add_file` commits the whole new tree. A crash mid-`cp` leaves a
  destination directory with some but not all entries copied and zero commits
  referencing it — the richest available crash window that stays byte-deterministic.
- **what property**: the documented invariant from `man/pass.1:42-44` — every
  mutation ⇒ a matching git commit — checked as: after recovery, either (a)
  `work/clientA-copy/` doesn't exist or is fully absent from git status (the
  copy never "started" from git's point of view), or (b) it exists, is fully
  populated (every entry present, byte-identical ciphertext to its
  `work/clientA/` counterpart, since same-scope copy never re-encrypts), and
  `git status --porcelain` is clean for that path. A partially-populated,
  uncommitted `work/clientA-copy/` directory (files present but git unaware)
  violates the promise.
- **where from**: `src/password-store.sh:645-649` (the cp path), `:110-141`
  (`reencrypt_path`, specifically the `$gpg_keys != $current_keys` skip
  condition at line 134), `man/pass.1:42-44` (the commit promise) and
  `man/pass.1:164-165` (the reencryption promise, which this scenario is
  designed to make a documented no-op, isolating the copy-atomicity question).

### P2 — recursive `rm` of a multi-entry directory (deterministic multi-file delete)

- **argv**: `pass -- rm -rf work/clientA` (force flag to skip the interactive
  `yesno` prompt) with the same fixture store as P1, `work/clientA/`
  containing 4 `.gpg` entries.
- **why**: `cmd_delete` (`src/password-store.sh:565-595`) runs one
  `rm -r -f -v "$passfile"` over the whole subtree — GNU `rm -r` unlinks files
  one at a time internally, so it is not atomic — and only *after* that
  completes does it run `git -C "$INNER_GIT_DIR" rm -qr "$passfile"` +
  `git_commit` (lines 589-593). A crash mid-`rm -r` yields a directory with
  some entries deleted and some still present, with the git tree still
  reflecting the pre-delete, fully-populated state.
- **what property**: same git-commit-correspondence promise
  (`man/pass.1:42-44`), from the deletion side: after recovery, the working
  tree for `work/clientA/` must either (a) exactly match what `git show
  HEAD:work/clientA` says was there before the delete (nothing removed took
  effect), or (b) be fully absent, matching a commit that removed it. A
  half-deleted directory that git's HEAD still claims is fully present is the
  violation — and per §4, `pass git checkout -- work/clientA` is the tool's
  own advertised recovery path, so the checker can literally invoke that
  recovery and confirm the tree becomes internally consistent again (every
  `.gpg` file present decrypts, nothing stray left over).
- **where from**: `src/password-store.sh:565-595` (`cmd_delete`), particularly
  the ordering of `rm` (line 587) before `git rm`/`git_commit` (lines 590-593);
  `man/pass.1:42-44` for the promise; `cmd_git` (`src/password-store.sh:652-670`)
  for the recovery path being a first-class subcommand of the tool itself,
  not an external workaround.

### P3 — `pass init <new-gpg-id>` reinit over an existing multi-entry store

- **argv**: `pass -- init NEWKEYID` with `PASSWORD_STORE_DIR=<state-dir>`
  pointed at a store whose root `.gpg-id` already contains a different key
  and which has 5+ `.gpg` entries at top level, all under git.
- **why**: `cmd_init` (`src/password-store.sh:321-366`) rewrites `.gpg-id`
  (line 348) then unconditionally calls `reencrypt_path "$PREFIX/$id_path"`
  (line 364), which loop-reencrypts every entry that doesn't already match
  the new recipient set — i.e. all 5 — via decrypt-pipe-encrypt-to-temp-then-`mv`
  (`src/password-store.sh:136-137`). This is the single richest multi-file
  write path in the whole tool: N independent gpg round-trips, each replacing
  a file, inside one invocation, with the git commit for the whole reencrypted
  tree only at the very end (line 365).
- **what property**: `man/pass.1:67`'s explicit promise — *"these files will
  be reencrypted to use the new id"* — checked as: after recovery, every
  `.gpg` file under the store either (a) still decrypts under the **old**
  key and the `.gpg-id` file has not changed (reinit visibly didn't happen),
  or (b) decrypts under the **new** key and `.gpg-id` has changed, for
  *every* file uniformly — never a mix, and never "`.gpg-id` says new key but
  file X still only decrypts under old key," which would silently lock the
  user out of an entry while `pass show` gives no indication anything is wrong
  until that specific file is opened.
- **where from**: `src/password-store.sh:321-366` (`cmd_init`), `:110-141`
  (`reencrypt_path`), `man/pass.1:67` for the documented guarantee text.
- **caveat (see §5)**: this scenario calls `gpg -e` on every file, so the
  produced ciphertext bytes are expected to differ on every recording attempt
  even with identical inputs — flagging a likely baseline-recording refusal
  on raw `.gpg` bytes for this specific proposal, distinct from P1/P2 which
  avoid `gpg -e` entirely.
