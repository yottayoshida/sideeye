# 2026-10-12 shipped-v1120 — results

Ten tools chosen for what v1.11.0 and v1.12.0 let through (`SELECTION.md`), each from its own latest
release for linux/arm64, measured with the released Sideeye v1.12.0 installed by the page's
installer, in one box (`apparatus/Dockerfile`), `--network none`, as root in a privileged container.
The gate is `apparatus/entry.sh` (the 2026-10-09 copy), the explore `apparatus/run.sh` (the page's
command, replayed twice on a FAIL); both copied with only the box's name changed.

**Six FAIL, two PASS, two walls.** Of the six, three lose what the user had — Crystal's formatter
leaves the source file empty, `ansible-vault encrypt` destroys the plaintext before the ciphertext
exists, and Bun leaves `package.json` empty as it did before its rewrite — and three move the file
aside and leave both versions whole (rclone, FreeCAD) or stop between two correct rewrites
(SwiftLint).

| Target | Mode | Verdict | Where | What the user is left with |
|---|---|---|---|---|
| Crystal 1.21.1 `crystal tool format` | supervised (static) | **FAIL** 1/3, replayed 2/2 | crash point 2 of 2: after the `open`, before the `write` | `src/inventory.cr` 0 bytes (830 before); the old bytes nowhere |
| ansible-core 2.21.5 `ansible-vault encrypt` | default | **FAIL** 15/18, replayed 2/2 | earliest crash point 3 of 17: after `shred`'s write, before its `fsync` | `secrets.yml` 217 bytes of shredded junk; neither the plaintext nor the vault |
| Bun 1.4.3 `bun add` | syscalls (followed) | **FAIL** 1/11, replayed 2/2 | crash point 10 of 10: after the `open`, before the `write` | `package.json` 0 bytes (349 before); the checker: does not parse |
| rclone 1.75.2 `config update` | supervised (static) | **FAIL** 2/19, replayed 1/2 | earliest crash point 6 of 18: between its two renames | no `rclone.conf`; the old file whole at `rclone.conf.old<n>`, the new one at `rclone.conf<n>` |
| FreeCAD 1.1.4 `freecadcmd` re-saving a part | default, clock pinned | **FAIL** 1/39, replayed 2/2 | crash point 24 of 38: between its two renames | no `part.FCStd`; the old document whole at `part.<time>.FCBak`, the new at `part.FCStd.<uuid>` |
| SwiftLint 0.65.1 `--fix` | default | **FAIL** 8/13, replayed 2/2 | earliest crash point 5 of 12: between two of its rewrites | `Ledger.swift` with one rule's corrections applied, valid Swift (703 bytes = `--only-rule opening_brace`'s output, `transcripts/lab-4.txt`) |
| yq 4.54.1 `-i` | supervised (static) | **PASS** 2/2 | one operation | the temporary is written outside the directory and renamed in once |
| KeePassXC 2.7.10 `keepassxc-cli add`, state on FAT | default, random and clock pinned | **PASS** 6/6 | five operations | the first verdict on KeePassXC this project has (cohort 2 refused it) |
| KeePassXC 2.7.10, state on ext4 | — | wall: `unresolvable_path` at the gate | — | Qt's save through an `O_TMPFILE`, the class `docs/target-classes.md` already names |
| sops 3.13.3 `rotate --in-place` | supervised (static) | wall: the two clean runs differ | — | a static Go binary drawing its keys from `getrandom(2)` and stamping the clock; nothing outside it pins either |
| DuckDB 1.5.6 `UPDATE` | default and syscalls | wall: `unsupported_syscall_observed` (`unlinkat`) | — | see below: an `unlinkat("")` that fails |

**After filing.** crystal-lang/crystal#17620 drew, within the hour, a collaborator's "Don't paste AI.
Especially walls of slop. Write down a summary of findings in your very own voice." — about the
report's form, not its finding; the owner answered in their own words. The two reports filed after
it (rclone, FreeCAD) were shortened at the owner's request.

## Crystal — the formatter empties the file it formats

`crystal tool format src/inventory.cr` opens the file for writing with truncation and then writes
the formatted text; killed between the two, the file is empty and the source exists nowhere
(`transcripts/explore/crystal/supervised.evidence.md`). Under `--observe supervised`, two
operations, oracle agreed on both. Searched on crystal-lang/crystal (`formatter truncate`, `format
empty file`, `tool format data loss`, `format atomic write`, `File.write atomic`, `formatter
interrupted`): nothing on the formatter; #6133 (2018, closed) proposed a `File.atomic_write` for the
standard library and was not merged. **Novel as far as that search reaches.** Filed on 2026-10-12 as
crystal-lang/crystal#17620, the text of `report-crystal.md` approved verbatim by the owner.

## ansible-vault — the plaintext is shredded before the vault is written

`VaultEditor.encrypt_file` calls `write_data(b_ciphertext, filename)`, whose default is
`shred=True`: if the file exists, `_shred_file` overwrites it (`shred`, a child process, or a Python
fallback) and removes it, and only then is the file created again with `O_EXCL` and the vault
written (`ansible/parsing/vault/__init__.py` lines 871–894 and 1007–1080 as installed). Killed in
between, the user has neither: 15 of 18 worlds, from the shredded file (217 bytes, the first) to an
absent one to an empty one. The salt was pinned (`pythonpath:sitecustomize.py`), so the recording's
bytes repeat. ansible/ansible#81455 (2023, closed) is the same order met by another road — a
directory the user cannot write — and was fixed by checking the directory first, which leaves this
window as it was. #80675 (open) refactors vault without changing the order. **Novel in this form.**
Filed on 2026-10-12 as ansible/ansible#87678, the text of `report-ansible-vault.md` approved verbatim
by the owner; the project's AI policy (assistance allowed, disclosed in a preamble) was read first.
The project's bot closed it within seconds: `bug_report.yml` requires a Configuration and an OS /
Environment section, which the draft did not carry (the template was named, not read field by
field). Filed again, with the owner's approval of the two sections, as ansible/ansible#87679.

## Bun 1.4.3 — the rewrite did not move it

The 2026-09-16 define (`crossed-walls`), with a longer manifest: `package.json` is opened with
`O_TRUNC` and written in one call, and a kill between leaves it empty — what 1.4.2 did on
2026-09-16, although the repository's code is mostly Rust now (GitHub's languages on 2026-10-12:
Rust 51 MB, C++ 12 MB). When in that span the writer was rewritten was not looked up. **Known**:
oven-sh/bun#39689, by a collaborator and still open, converts the `package.json` writers to a
temporary and a rename.

## rclone and FreeCAD — both versions survive, the name does not

Both save by renaming the file aside, then renaming the new one in. Between the two renames the name
the user knows is gone. rclone then says `Config file "/s/rclone/rclone.conf" not found - using
defaults`, lists no remote, and `rclone config update` itself exits 2 (`transcripts/lab-4.txt`, the
directory rebuilt from the evidence table): every remote looks lost until the user renames
`rclone.conf.old<n>` back by hand. FreeCAD reports `File '/s/fc/part.FCStd' does not exist!`
(the checker). Nothing is lost in either; the stop is `no_content_lost`, as f2's and cabal's were.
rclone/rclone#6656 (closed) met the same rename-aside save from Docker's side, a bind-mounted file
that cannot be renamed. rclone's was filed on 2026-10-12 as rclone/rclone#10076: the owner's draft,
arranged into the sections `bug.yml` requires (read field by field this time, after ansible's bot) and
shortened at the owner's request (`report-rclone.md` holds the text filed). FreeCAD's was filed as
FreeCAD/FreeCAD#33493 after its development release, 26.3rc1 (FreeCAD 26.3.0), FAILed the same way,
1/27 and replayed twice (`transcripts/explore/freecad-dev/`, `apparatus/Dockerfile.freecad-dev`):
FreeCAD's AI policy asks that descriptions be the contributor's own, so the owner wrote it in
Japanese and it was translated (`report-freecad.md`).

rclone's FAIL replayed once and then refused `multiple_threads_detected`; with `GOMAXPROCS=1`
declared the gate itself refused it (`transcripts/entry-candidates-3.txt`) — OpenTofu's shape in
`docs/apparatus.md`, the writing thread the scheduler's choice per run.

**FreeCAD's configuration, outside the judged state.** Before its configuration was moved into the
state as scratch, killed worlds left `~/.config/FreeCAD/v1-1/user.cfg` and `system.cfg` unreadable
to the next run ("Failed to access file for reading"), and a document's transient directory under
`TMPDIR` made the next run take a fresh random UUID and save different bytes. Both split the
baseline (`transcripts/explore-batch-1.txt`, `-2.txt`; the text of those explores was overwritten by
the re-run in the same directory). What a kill does to that configuration is not measured here.

## SwiftLint — a valid intermediate

`--fix` applies its rules one after another and saves after each through Foundation's atomic write
(`.dat.nosync<n>` renamed over the file). Killed between two saves, the file holds the earlier
rules' corrections and not the later ones' — valid Swift, nothing lost. `no_content_lost`.

## KeePassXC — past cohort 2's wall, onto Qt's, and past that on FAT

Every save draws fresh salts and IVs; cohort 2 stopped there. Pinning `getrandom()` alone did not
move it: Debian's build reads `/dev/urandom` (`transcripts/lab-3.txt`, one `openat` of it and one
raw `getrandom` of 8 bytes). `apparatus/pin-random.c` hands an open of either device a fixed file,
and with libfaketime the two clean runs wrote the same bytes (`transcripts/lab-4.txt`). The seed
runs with the pins off: pinned, every process draws the same entry UUID, and three `add`s left one
entry. On ext4 the gate then met Qt's `O_TMPFILE` save (`unresolvable_path`); on FAT, where that
open fails and Qt saves through a named temporary, PASS 6/6 with the checker opening the database
in every world.

## sops — the wall the selection predicted

`sops set` could not be written as a define: its path expression needs double quotes, which a
define string cannot escape and an argv element cannot hold (`transcripts/entry-candidates*.txt`);
a script in between made the dynamic `sh` the operation (`child_process_detected`). `rotate
--in-place` needs no quotes, and two clean runs left different bytes — new data keys and IVs from
`getrandom(2)` and a `lastmodified` stamp, in a static Go binary nothing outside can pin.

## DuckDB — a wall about Sideeye

The gate refused `unsupported_syscall_observed` naming `unlinkat`, in both observation modes
(`transcripts/lab-2.txt`). strace shows two (`transcripts/lab-3.txt`): the WAL removed at
checkpoint, and `unlinkat(AT_FDCWD, "", 0) = -1 ENOENT` — an unlink of the empty path, which fails
and changes nothing. A refusal on a call that touched nothing is the engine's to reconsider; it is
recorded here and not filed.

## What this run measured about Sideeye

- **A define cannot spell a double quote.** No escapes in a string, double-quoted strings only in
  argv: `sops set`'s path expression has no form at all.
- **A replay ends where the run completes**, so a crashed state's bytes are read from the evidence
  table, not from the state directory after `replay` (`transcripts/lab-3.txt`).
- **A pinned source pins every process the same way**: a seed that makes several records under the
  pins can make them collide.
- **Apparatus outside the state carries over between worlds.** A tool that keeps per-run files in
  `TMPDIR` or its configuration directory, and does not clean them when killed, changes the next
  world; moving them into the state as scratch is what made FreeCAD's baseline repeat.
