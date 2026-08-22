# pass (password-store) 1.7.4 — scouting report

Checkout: `targets/pass/`. One 721-line bash script, `src/password-store.sh`, plus
`man/pass.1` and a `tests/` suite that ships a working GPG keyring.

**Read §5 first if you are scheduling engine time.** pass has the best *documented*
invariant of the five targets and the worst determinism story. The operation that maintains
the invariant is the one that will refuse recording.

## 1. Where the persistent state lives

**`$PASSWORD_STORE_DIR`, default `~/.password-store`** — `src/password-store.sh:15`,
documented at `man/pass.1:398-399` and `man/pass.1:412-414`. Read and written.

Contents, all of it state:

- `*.gpg` — one GPG-encrypted file per password, path = password name.
- **`.gpg-id`** — the encryption policy. `man/pass.1:401-405`: "Contains the default gpg key
  identification used for encryption and decryption. Multiple gpg keys may be specified in
  this file, one per line. **If this file exists in any sub directories, passwords inside
  those sub directories are encrypted using those keys.**" There may be one per subtree;
  lookup walks upward to the nearest ancestor (`src/password-store.sh:82-86`).
- `.gpg-id.sig` — optional detached signature, verified on every read of `.gpg-id`
  (`verify_file`, `src/password-store.sh:59-70`, called at `src/password-store.sh:98`).
- `.git/` — optional, and **not a cache**: the manual treats git as part of the product
  ("Sub-directories may be separate nested git repositories", `man/pass.1:44-46`), and every
  mutating command commits.
- `.gitattributes` — written by `pass git init` (`src/password-store.sh:663`).
- `.extensions/` — user code, `man/pass.1:407-409`.

There is **no path flag**: the store location comes only from `$PASSWORD_STORE_DIR`
(`src/password-store.sh:15`). Unlike the other four targets, environment plumbing is
unavoidable here. `$GNUPGHOME` is a second required piece of plumbing — keep it **outside**
the state directory, or gnupg's own `trustdb.gpg` and `random_seed` churn will land in the
baseline.

## 2. Which commands write that state

Every mutating subcommand follows the same two-phase shape: **touch the filesystem, then
reconcile git**. The git half is `git_add_file` → `git_commit`
(`src/password-store.sh:37-48`).

| argv | filesystem writes | git writes |
|---|---|---|
| `init <id>` | `.gpg-id` (truncating `>`), then re-encrypts **every** `.gpg` below it | 2–3 commits |
| `insert`, `edit`, `generate` | one `.gpg` | 1 commit |
| `mv`, `cp` | rename/copy, then selective re-encrypt | 1–2 commits |
| `rm` | unlink, then `rmdir -p` | 1 commit |

**The richest window by a distance is `cmd_init`** (`src/password-store.sh:321-366`):

```sh
printf "%s\n" "$@" > "$gpg_id"                     # line 348 — new policy, first
...
reencrypt_path "$PREFIX/$id_path"                  # line 364 — data catches up, after
```

The policy file is written **before** the data is brought into line with it. For the entire
duration of the re-encryption — a bulk `gpg -d | gpg -e` per password, so seconds to minutes
on a real store — `.gpg-id` names key B while some or all files are still encrypted to key A.
That is the invariant at `man/pass.1:404-405` being false by construction, in the normal
non-crashing case, with a window the size of the store.

Three further details make a crash there durable rather than transient:

1. `reencrypt_path` **skips files whose recipients already match**
   (`src/password-store.sh:134`, `if [[ $gpg_keys != "$current_keys" ]]`). So re-running
   `pass init B` after a crash re-encrypts only the stragglers — which requires **key A's
   private key**, the very key the user was rotating away from. Recovery is possible only
   during the window in which it is not yet needed.
2. Line 348 is a plain truncating `>` on the live `.gpg-id`. No temp file, no rename. A crash
   mid-write leaves it empty or partial. `set_gpg_recipients` reading an empty file
   (`src/password-store.sh:100-108`) produces an **empty** `GPG_RECIPIENT_ARGS`, so the next
   `pass insert` calls `gpg -e` with no `-r` at all and fails; the store is unusable until
   hand-repaired.
3. Per-file, `reencrypt_path` does use the safe idiom —
   `gpg -d … | gpg -e … -o "$passfile_temp" && mv "$passfile_temp" "$passfile" || rm -f "$passfile_temp"`
   (`src/password-store.sh:136-137`). Individual passwords are therefore atomic. The
   atomicity gap is entirely at the *set* level, not the file level. That is a good thing to
   be able to say precisely in a report: pass got the small case right and the large case
   wrong.

`cmd_copy_move` (`src/password-store.sh:597-651`) has the same shape one size down:
`mv "$old_path" "$new_path"` at line 630, `reencrypt_path "$new_path"` at line 631. Between
them the moved password sits under the destination's `.gpg-id` while still encrypted to the
source's key.

`cmd_delete` (`src/password-store.sh:565-595`) inverts the order — worktree first, git second:
`rm -r -f "$passfile"` (line 587), then `git rm -qr` and `git_commit` (lines 589-593). A crash
after the `git rm` (which only stages) but before the commit leaves a **staged deletion with
no commit**; the next `pass insert` runs `git add` + `git commit` and silently sweeps that
staged deletion into a commit whose message describes the insert.

## 3. What the documentation promises

- **`man/pass.1:401-405`** — the central invariant, and it is stated as a fact about the
  world, not as a behaviour: "If this file exists in any sub directories, passwords inside
  those sub directories **are encrypted using those keys**." Checkable without any private
  key (see §4).
- **`man/pass.1:66-67`** (`init`): "If the specified *gpg-id* is different from the key used
  in any existing files, **these files will be reencrypted** to use the new id." A
  completeness promise over the whole subtree.
- **`man/pass.1:157-158`** (`mv`) and **`man/pass.1:164-165`** (`cp`): "Passwords are
  selectively reencrypted to the corresponding keys of their new destination."
- **`man/pass.1:153-155`** (`mv`): "Renames the password or directory named *old-path* to
  *new-path*." A rename conserves; nothing else may be lost.
- **`man/pass.1:41-44`**: mutating commands "cause a corresponding git commit" — a
  one-operation-one-commit promise that the `cmd_delete` window above breaks.
- **`man/pass.1:50-52`**: "The **init** command must be run before other commands in order to
  initialize the password store with the correct gpg key id."

## 4. fsck / doctor / verify / undo / repair

**No dedicated command.** No `pass fsck`, no `pass verify`, no `pass doctor`. But pass is the
only target of the five with two *de facto* repair-and-audit mechanisms:

- **`pass init <same-id>` is idempotent re-encryption**, and therefore a repair tool: it walks
  every file and fixes any whose recipients do not match (`src/password-store.sh:134-137`).
  Its limitation is the one in §2 — it needs the old private key.
- **`pass git` exposes the full git repository** (`cmd_git`, `src/password-store.sh:653`;
  `man/pass.1:167-172`), so `git fsck`, `git status` and `git checkout --` are available as
  undo. This is the only target here with real history-based recovery.
- **`verify_file`** (`src/password-store.sh:59-70`) checks the `.gpg-id.sig` detached
  signature on every load when `$PASSWORD_STORE_SIGNING_KEY` is set — a genuine integrity
  check on the policy file, and a good thing for a checker to exercise, since a crash at
  line 348 leaves `.gpg-id` changed while `.gpg-id.sig` still signs the old bytes.

**Checker construction is unusually easy here**, and worth spelling out because it makes the
invariant cheap to assert: `gpg --list-only --list-packets <file>.gpg` (or
`--decrypt --list-only`, as pass itself uses at `src/password-store.sh:132`) prints the
recipient key IDs of an encrypted file **without needing the private key**. So a checker can,
in every crash world, walk the store, resolve each file's nearest ancestor `.gpg-id`, and
compare — exactly the property at `man/pass.1:404-405`, with no secrets involved.

## 5. Determinism expectation — read this before scheduling

**Expectation: every operation that writes a `.gpg` file will refuse. Any store with a
`.git/` will refuse. What is left is `mv` / `cp` / `rm` within a single gpg-id in a non-git
store.**

Sources, each cited:

1. **GPG ciphertext is not reproducible.** Every `gpg -e` picks a fresh random session key
   and IV. `GPG_OPTS` at `src/password-store.sh:9` sets `--compress-algo=none`, which removes
   *one* source of variation but not this one. Any world involving `insert`, `edit`,
   `generate`, or an actual re-encryption inside `init`/`mv`/`cp` produces different bytes on
   every run. Confidence: very high.
2. **`reencrypt_path` randomises the temp filename**:
   `local passfile_temp="${passfile}.tmp.${RANDOM}.${RANDOM}.${RANDOM}.${RANDOM}.--"` —
   `src/password-store.sh:120`. Four `$RANDOM` draws, and the file is created **inside the
   store directory**. So even the intermediate filenames in the state dir differ run to run.
3. **`pass generate` additionally reads `/dev/urandom`** —
   `read -r -n $length pass < <(LC_ALL=C tr -dc "$characters" < /dev/urandom)`,
   `src/password-store.sh:539`. Two independent refusals.
4. **git makes any store non-reproducible, in two ways that differ in fixability:**
   - Commit objects embed author and committer timestamps. This one **is** pinnable —
     `src/password-store.sh:24` unsets `GIT_DIR`, `GIT_WORK_TREE`, `GIT_NAMESPACE`,
     `GIT_INDEX_FILE`, `GIT_INDEX_VERSION`, `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR`, but
     **not** `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE`, so the engine can export those.
   - **`.git/index` embeds per-file `st_dev`, `st_ino`, `st_mtime` and `st_ctime`.** That is
     not pinnable by clock control, and a restored state directory will not reproduce inode
     numbers. Confidence: high, and this is the one I would expect to be discovered the hard
     way. Unless the engine can exclude `.git/index` from the baseline, **use a non-git
     store for every pass run.**
5. **Keep `$GNUPGHOME` outside the state directory.** Even read-only pass operations invoke
   `gpg --list-config` and `gpg --list-keys` (`src/password-store.sh:112`,
   `src/password-store.sh:131`), and gnupg rewrites `trustdb.gpg` and `random_seed` in its own
   home. Point it at `targets/pass/tests/gnupg`, which ships a ready-made keyring
   (`pubring.gpg`, `secring.gpg`, `private-keys-v1.d/`, `trustdb.gpg`) — copied out to a
   scratch location, since it will be written to.

**What survives:** in a store with a single root `.gpg-id` and no `.git/`, `reencrypt_path`
reaches line 134, finds `gpg_keys == current_keys`, and takes no branch — no temp file, no
GPG output, no writes at all. `mv`, `cp` and `rm` then reduce to plain filesystem operations
on deterministic bytes. All three proposals below are built on that.

## 6. Candid assessment

pass is the **weakest fit** of the five targets for this engine, and the reason is structural
rather than incidental: its state is *defined* to be encrypted, and encryption is
deterministic-hostile. The proposals below are honest about being the residue. If the engine
ever gains the ability to pin GPG's RNG, P1 should immediately be replaced by
`pass init -p <subdir> <new-id>` on a populated subtree, which is the real target here.

---

# Proposals

## P1 — `mv` a directory: rename, then a re-encryption pass that must not disturb it

- **argv:** `pass mv -f team old-team`
  Environment: `PASSWORD_STORE_DIR=$STATE/store`, `GNUPGHOME=$SCRATCH/gnupg` (a copy of
  `targets/pass/tests/gnupg`, outside the state dir). Pre-state: a store with a **single root
  `.gpg-id`** and **no `.git/`**; `store/team/` containing ~6 `.gpg` files across two levels
  of subdirectory; a few passwords elsewhere in the store as controls. `-f` forces
  non-interactive `mv` (`src/password-store.sh:626-627`).
- **why:** The operation is `mkdir -p` on the destination parent, a `mv` of the subtree
  (`src/password-store.sh:630`), a full `reencrypt_path` walk over the destination
  (`src/password-store.sh:631`), and a `rmdir -p` unwinding the source's now-empty parents
  (`src/password-store.sh:645`). The `reencrypt_path` walk is the part that matters: it runs
  `find`, and for **every** file computes recipients and compares them, and it is the code
  path that in the non-degenerate case rewrites files in place. Here the comparison must
  come out equal for all six, so a correct run must leave every file's bytes untouched —
  which means any world where a `.gpg` file's content differs is unambiguous evidence that
  the guard at `src/password-store.sh:134` was not honoured under interruption. The
  `rmdir -p` tail is a second, independent window: it walks *upward* from the old location
  removing empty directories, and a crash partway leaves a partial skeleton.
- **what property:** *A rename conserves every password, and re-encryption that is not needed
  changes nothing.* In every crash world: (a) the multiset of `.gpg` file **contents** in the
  store must be exactly the pre-state's — same six blobs, byte for byte, plus the controls,
  reachable under either the old or the new path but never lost or altered; (b) the
  documented invariant must hold — for every `.gpg` file, its recipient key IDs (read with
  `gpg --list-only --list-packets`, no private key needed) must equal the ids listed in its
  nearest ancestor `.gpg-id`; (c) no file matching `*.tmp.*.--` may be left behind, since
  that name only exists between lines 136 and 137 of a re-encryption that should never have
  started.
- **where from:** promise — `man/pass.1:153-155` ("Renames the password or directory named
  *old-path* to *new-path*") and `man/pass.1:157-158` ("Passwords are selectively reencrypted
  to the corresponding keys of their new destination"), plus the standing invariant at
  `man/pass.1:401-405`; implementation — `src/password-store.sh:597-651` (`cmd_copy_move`),
  specifically line 630 (`mv`), line 631 (`reencrypt_path`), line 645 (`rmdir -p`), and
  `src/password-store.sh:110-141` (`reencrypt_path`, with the skip guard at line 134 and the
  temp-file idiom at lines 136-137).

## P2 — `cp -r` a directory: a many-file copy with the source as a fixed reference

- **argv:** `pass cp -f team archive/team-2026`
  Same environment and pre-state as P1.
- **why:** `cp -r` (`src/password-store.sh:648`) is the only pass operation that writes many
  files in one go **while a pristine reference copy remains on disk**, which makes it the
  cleanest place to detect a partial write: the source is still there to compare against,
  so a checker does not have to reason about which of two legal outcomes it is looking at.
  It also creates directories along the way (`mkdir -p -v "${new_path%/*}"`,
  `src/password-store.sh:622`), so crash worlds include ones where the destination tree
  exists but is incomplete — and pass has no notion of a half-copied subtree, so nothing will
  ever notice. A copy that lands short is materially worse than a copy that fails outright:
  the user sees `archive/team-2026` in `pass ls` and believes the archive is complete.
- **what property:** *A copy never alters the source, and every file it does create is a
  faithful, correctly-encrypted copy.* In every crash world: (a) `store/team/` must be
  byte-for-byte identical to the pre-state — the operation has no business touching it, and
  `reencrypt_path` is invoked with the *destination* path only (`src/password-store.sh:649`),
  so nothing may reach the source; (b) every file that exists under `archive/team-2026/` must
  be byte-identical to its counterpart under `team/`, never truncated or partial; (c) the
  standing `.gpg-id` invariant from `man/pass.1:401-405` holds for every file present;
  (d) no `*.tmp.*.--` residue. Note that a *missing* destination file is permitted in a crash
  world — the assertion is about the source's integrity and the created files' fidelity, not
  about completeness.
- **where from:** promise — `man/pass.1:160-165` ("Copies the password or directory named
  *old-path* to *new-path*… Passwords are selectively reencrypted to the corresponding keys
  of their new destination") and `man/pass.1:401-405`; implementation —
  `src/password-store.sh:647-650` (the `cp -r` branch, the `reencrypt_path "$new_path"` call
  scoped to the destination), `src/password-store.sh:622` (`mkdir -p`),
  `src/password-store.sh:110-141` (`reencrypt_path`).

## P3 — `rm -r` a directory: unlink cascade plus an upward `rmdir -p`

- **argv:** `pass rm -r -f team`
  Same environment and pre-state as P1. `-f` skips the `yesno` prompt
  (`src/password-store.sh:585`); note `yesno` returns 0 immediately when stdin is not a tty
  (`src/password-store.sh:50`), but pass `-f` anyway so the behaviour does not depend on how
  the engine wires stdin.
- **why:** `rm -r -f -v "$passfile"` (`src/password-store.sh:587`) unlinks six files and
  several directories, then `rmdir -p "${passfile%/*}"` (`src/password-store.sh:594`) walks
  *upward* from the removed path deleting every parent that is now empty — and `rmdir -p`
  does not stop at the store root by itself; it stops only when a directory is non-empty.
  In a store where `team/` was the only entry under some parent, that unwind can climb
  further than the user expects. The crash windows are the individual unlinks (leaving a
  partially deleted subtree, which is benign-looking but means `pass ls` shows a directory the
  user believes is gone) and the upward `rmdir` chain. This is the weakest of the three
  because deletion has no conservation promise to violate; I include it because it is fully
  deterministic, it exercises a different syscall mix from P1 and P2, and it is the operation
  whose *partial* outcome is hardest for a user to notice.
- **what property:** *Deletion is confined to the named path, and never climbs above the store
  root.* In every crash world: (a) every password **outside** `team/` — the controls — must
  still exist with unchanged bytes; (b) `$PASSWORD_STORE_DIR` itself and the root `.gpg-id`
  must still exist, so that the store remains initialised per `man/pass.1:50-52` ("The
  **init** command must be run before other commands…"); (c) whatever remains under `team/`
  must still satisfy the `man/pass.1:401-405` recipient invariant, i.e. partial deletion may
  not strand a `.gpg` file in a subtree whose `.gpg-id` was removed first.
- **where from:** promise — `man/pass.1:147-151` (the `rm` description, with `--recursive`
  and `--force`), `man/pass.1:50-52` (store must remain initialised),
  `man/pass.1:401-405`; implementation — `src/password-store.sh:565-595` (`cmd_delete`),
  specifically line 587 (`rm $recursive -f -v`), line 594 (`rmdir -p`), and lines 588-593
  (the git block, inert in a non-git store and the reason this proposal specifies one).
