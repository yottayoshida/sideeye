# 2026-09-16 — outside git: results

Five targets whose state lives outside version control (`SELECTION.md`), explored with the released
v1.4.0 and once more each with main `047592d` (contract v18, not a release), and neovim again after
the first review of this record — Debian's 0.10.4 with a second checker, and the latest release,
0.12.5. As root in a `--privileged` container on Linux aarch64, state on the container's filesystem.
Drivers `apparatus/explore.sh`, `explore-nvim-scratch.sh` and `nvim-v2.sh`; transcripts and JSON
reports in `transcripts/explore/` and `transcripts/nvim-v2/`; predictions committed before each
exploration in `PREDICTIONS.md`.

**The aws-cli probe credentials in every committed script and transcript are substitutes.** The run
used fabricated keys shaped like real AWS keys; before the first push they were replaced with strings
of the same length that no scanner reads as keys, in every commit, and the aws-cli part was run again
with the replacements, together with every checker probe and every `ulimit` probe (`BUILDLOG.md`,
`apparatus/redact-probe-credentials.py`, `transcripts/rerun-after-redaction/`).

| Target | Mode(s) | v1.4.0 | main `047592d` | Predicted | Upstream |
|---|---|---|---|---|---|
| aws-cli 2.23.6 `configure set` | wrappers ×3, syscalls ×1 | **FAIL** 4/4 — `credentials` empty, both profiles' keys gone | FAIL 1/1 | FAIL — hit | no report in the searched titles; the same code on `v2` |
| hatch 1.18.0 `config set` | wrappers ×3, syscalls ×1 | **PASS** 4/4, 6/6 worlds over 5 crash points | PASS 1/1 | PASS — hit | — |
| neovim 0.10.4 `:wshada` | wrappers ×3, syscalls ×1 | first define **UNKNOWN** 4/4 `baseline_violates_invariant`; with `main.shada` scratch **FAIL** 4/4 on the checker, 6 of 13 worlds, with either checker | UNKNOWN 1/1; FAIL 1/1 (each checker) | first define a miss; the scratch define, predicted after, hit | see below |
| neovim 0.12.5 (latest release) `:wshada` | wrappers ×3 (no scratch); wrappers ×3, syscalls ×1 (scratch) | **UNKNOWN** 3/3 without scratch; **FAIL** 4/4 with it, **2 of 13 worlds** | FAIL 1/1 | hit (predicted after the review) | none of twelve issues read names the mechanism |
| jbang 0.141.0 `config set` | wrappers ×3, syscalls ×1 | **FAIL** 4/4 — `jbang.properties` empty | FAIL 1/1 | FAIL — hit | none in the searched titles |
| pyenv 2.8.5 `global` | syscalls ×3 | **FAIL** 3/3 — `version` empty, pyenv falls back to `system` | FAIL 1/1 | FAIL — hit | none in the searched titles |

main gave the same answer as v1.4.0 for every define. **One refusal came from a wall the screen could
not show**: neovim's `baseline_violates_invariant`. A `preflight` runs no uncrashed re-run — its
report says `not checked  kill landing, world-side process boundaries, baseline behavior, checker
falsification` (`transcripts/screen/pass1/nvim.140.wrappers.txt`) — so the falsifier
`PREDICTIONS.md` named for the run's premise did fire, for neovim, and the scratch define is how the
run went on past it.

## aws-cli — FAIL: one failed write empties every profile's credentials

**Crash point 2 of 2, 4 of 4 runs, the same under main** (`transcripts/explore/aws.*`). Between the
`open` and the `write` of `credentials`, the checker — which asks the CLI itself — reports
`default profile's access key is "" (0 bytes in credentials)`. The edited profile was `work`; the
`default` profile's keys are lost with it, because the whole file is rewritten.

The capture: `openat(credentials, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666)` and one 230-byte
`write` (`transcripts/probes/open-flags.txt`, cut from the uncommitted capture by
`apparatus/excerpts.sh`). The source: `awscli/customizations/configure/writer.py` rewrites an existing
file with `with open(config_filename, 'w') as f: f.write(''.join(contents))` — lines 65–66 at tag
`2.23.6`, lines 114–115 on the `v2` branch (`transcripts/meta/upstream-source.txt`; the newest tag
was `2.36.46`, not measured).

**Without Sideeye and without a crash** (`apparatus/probe-ulimit.sh`, `transcripts/probes/ulimit.txt`):
the probe's own fixture — both profiles' keys in `credentials`, a `config` holding only `[default]` —
and `aws configure set aws_secret_access_key rotated --profile work` under `ulimit -f 0` leave
`credentials` at **0 bytes** (231 before), exit status 120. Measured only as `EFBIG` under a file-size
limit; a full disk was not measured.

The checker's predicates, each broken on its own (`apparatus/probe-checker-predicates.sh`,
`transcripts/probes/checker-predicates.txt`): a changed `work` access key, a `work` secret that is
neither the old nor the new one, and a changed `default` access key are each rejected; the
`default` profile's **secret is not checked**.

## hatch — PASS

**6/6 worlds over 5 crash points, 4 of 4 runs and 1 under main.** A temporary file is created
`O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW`, written, `fsync`ed and renamed over `config.toml`
(`open-flags.txt`). The checker — `hatch config show`, the file parsed, the setting the old value or
the new one — passed in every world. Its value predicate rejects a third value and its content
predicate a removed top-level key, each broken alone (`checker-predicates.txt`); an unparsable file is
refused by `hatch config show` before the parse predicate runs, so that predicate was never shown
rejecting on its own. The contrast inside this run is aws-cli: both are Python tools
writing a user's configuration, and one goes through a temporary file.

## neovim — the shada file is removed before the rename, in every version measured

### Why the first define has no verdict

4 of 4 runs of the first define, and 1 under main, returned `UNKNOWN baseline_violates_invariant`:
the uncrashed re-run left `main.shada` *"holding neither the old nor the new content"*. The shada
format stamps time and process id. `apparatus/probe-shada-after.sh` part A ran the define's operation
three times from one state it built the define's way, on both binaries, and located every differing
byte in both pairs — back to back and one second apart: each is inside a msgpack timestamp (a uint32
in 0.10.4, a uint64 in 0.12.5) or the header's `pid` (`transcripts/probes/shada-after.txt`). The
earlier `probe-shada.sh` located only one pair and knew only the uint32 encoding; `nvim-v2.sh` part 6,
with the same limitation, printed `False` for 0.12.5's one-second pair. The worlds the first define
explored had already printed the checker's failures before the baseline refused. The scratch define
declares `main.shada` scratch (ADR 0043) and gives the claim to the checker.

### 0.10.4: two windows

**FAIL 4 of 4 runs, 6 of 13 worlds, earliest crash point 3 of 12, and 1/1 under main**, first with the
checker `explore.sh` defines (`transcripts/explore/nvim-scratch.*`), and again, the same 6 of 13,
with checker v2 (`transcripts/nvim-v2/nvim.scratch.*`). Four worlds leave `main.shada` at 0 bytes and
two leave it absent with `main.shada.tmp.a` beside it. The operation writes the file twice
(`:wshada`, and again on quitting), so each window appears twice.

The order, in the capture (`nvim-v2.sh` part 2, `transcripts/nvim-v2/nvim-v2-summary.txt`): open
`main.shada.tmp.a` `O_EXCL`, `unlink(main.shada)`, `rename(main.shada.tmp.a, main.shada)`, and only
then the 159-byte `write` and the `fsync`. In the source at `v0.10.4`, `shada_write_file` calls
`vim_rename(tempname, fname)` — which calls `os_remove(to)` before `os_rename(from, to)` in
`src/nvim/fileio.c` — and the buffered contents are written in `close_file(&sd_writer)` afterwards;
`shada_write` has no flush of its own at that version (`transcripts/meta/upstream-source.txt`: 0
`packer_flush(&packer)` calls).

**Without Sideeye, under a file-size limit** (`transcripts/probes/ulimit.txt`, `shada-large.txt`,
`nvim-v2-summary.txt` part 5): `ulimit -f 0` leaves the define's small file at 0 bytes (136 and 138
bytes before, in two runs). A 400-entry file of 25,715 or 25,717 bytes is mostly written into the
temporary before the rename: limits of 4,096, 8,192, 16,384, 20,480, 21,504, 22,528, 23,552, 24,576
and 25,088 bytes stop nvim before the rename, leaving the original intact and `main.shada.tmp.a`
beside it; **25,600 bytes** fails only what is written after the rename, and leaves `main.shada` cut
at 25,600 bytes, which the next nvim reports as `E576: Error while reading ShaDa file: last entry
specified that it occupies 57 bytes, but file ended earlier` while still reading register `a` and 398
history entries. These are `ulimit` measurements; no crash of a large file was explored.

### 0.11 and later: one window, and nothing says it happened

**The source.** From `v0.11.0`, `shada_write` ends with `packer.packer_flush(&packer)` at
`shada_write_exit:` — every byte reaches the temporary before `shada_write_file` renames it — and
`vim_rename` still calls `os_remove(to)` first; the same at `v0.12.5` and on `master`
(`upstream-source.txt`). The first version of this page said the `v0.10.4` order held on `master`;
that was read from four fixed lines that could not show the added flush, and the first review of this
record found it.

**Measured on the v0.12.5 release** (`nvim-v2.sh`, `transcripts/nvim-v2/`): the capture writes 170
bytes into `main.shada.tmp.a`, then unlinks `main.shada` and renames the temporary, then `fsync`s.
`preflight` is accepted with 12 operations in both modes and both builds. Without scratch, 3 of 3
explorations are UNKNOWN `baseline_violates_invariant`. With `main.shada` scratch and checker v2,
**FAIL 4 of 4 runs and 1/1 under main, 2 of 13 worlds, earliest crash point 4 of 12**: both failing
worlds are the kill between the unlink and the rename — `register a is lost (main.shada absent; files:
main.shada.tmp.a )`. The window after the rename is gone: `ulimit -f 0` leaves `main.shada` intact at 144
bytes with `main.shada.tmp.a` beside it, and on a 27,319-byte file the six limits measured — 4,096,
8,192, 16,384, 26,112, 26,624 and 27,136 bytes — each stop nvim before the rename with the original
intact, while 27,648 lets the rewrite finish.

**What the window leaves, and what the next session does** (`apparatus/probe-shada-window.sh`,
`transcripts/probes/shada-window.txt`, both binaries): strace injects `SIGKILL` at nvim's first
`renameat`, after the unlink. **0.12.5 leaves `main.shada.tmp.a` of 168 bytes — the complete new file
— and no `main.shada`. 0.10.4 leaves `main.shada.tmp.a` of 0 bytes and no `main.shada`**: its
temporary is still empty at the rename, so nothing of the history or registers is left anywhere. In
both, the next two headless sessions start with an empty register and no command-line history
(`:history cmd` lists no entry), print nothing (0 bytes on stdout and stderr) and have an empty
`:messages`; the first writes a new `main.shada` of 82 bytes (0.12.5) or 84 bytes (0.10.4), and the
temporary is still there, unread, after the second. An interactive session was not measured.
`probe-shada-after.sh` part B had built the world by hand with the complete file as the temporary for
both versions — true of 0.12.5 only — and kept no session output.

### Checker v2

The first checker was shown rejecting only its register predicate, did not ask nvim when
`main.shada` was absent, and would pass a file nvim reports as `E576` (the first review). Checker v2
asks nvim in every case and fails on an `E57x` message, a missing register or a missing history
entry. `nvim-v2.sh` part 1 falsified each predicate on both binaries: it passes the setup's and the
operation's states and leaves the file unchanged, and rejects an emptied file, an absent file with a
complete temporary, a file cut by 20 bytes (`E576`), a file with history and no register, and one with
a register and no history.

### Upstream

`apparatus/upstream-neovim-issues.sh` fetched thirteen neovim issues — body and every comment — chosen
by title from the novelty search's results (`E576`, `E138`, a failure to parse the ShaDa file,
corruption, history lost when instances are killed) plus neovim/neovim#11955, which neovim/neovim#8587 cites; it
prints each one's size and every line that names a rename, an unlink, a temporary, a crash or a kill
(`transcripts/meta/upstream-neovim-issues.txt`). Other titles in those results, such as
neovim/neovim#6957 *"Broken shada files can cause assertion error"*, were not fetched. **None of the
thirteen names the removal before the rename.** What they do report is what this window leaves
behind: `main.shada.tmp.*` files that stay — neovim/neovim#8587 (open, `E138`), neovim/neovim#11955
(open, some of them empty), neovim/neovim#6875 (open), and the `E136: … Do not forget to remove
…main.shada.tmp.X` lines in neovim/neovim#23345, neovim/neovim#4169 and neovim/neovim#8064 — and
corruption when processes are killed quickly (neovim/neovim#11876, open, Windows). The long thread of
neovim/neovim#8587 traces its temporaries to nvim aborting inside the shada write on exit (a hashmap
rehash), a different crash that leaves the same file. Whether any report came from this window is not
known.

## jbang — FAIL, the truncating rewrite

**Crash point 2 of 2, 4 of 4, the same under main.** `openat(jbang.properties,
O_WRONLY|O_CREAT|O_TRUNC)` and one 45-byte `write`; the checker, `jbang config get first.key` through
the jar, returns nothing: `No configuration option found with that name: first.key`. It also rejects
`first.key` holding another value (`checker-predicates.txt`). `ulimit -f 0` leaves the file at 0 bytes
(21 before). Measured through the jar, which is what the `jbang` script runs; the script itself is
refused `child_touched_state_dir` (`SELECTION.md`).

## pyenv — FAIL, under the syscall observer only

**3 of 3 runs under `--observe syscalls`, 2 of 4 worlds, earliest crash point 2 of 3, and 1/1 under
main.** A bash child opens `version` `O_WRONLY|O_CREAT|O_TRUNC`, then again `O_APPEND` and writes
`3.12.4`; killed between the two opens, `version` is empty and `pyenv version-name` answers `system`.
**The oracle compared none of the subject's own operations**: `oracle_verified` is false and
`oracle_verified_subject_only` true, `agreed on 0 operations` — every write is the child's, so no crash
point in this verdict was compared by the second witness. `ulimit -f 0` gives the same loss without Sideeye (7 bytes to
0). Under `--observe wrappers` the recording is refused `state_changed_without_ops`, in both builds.
The checker also rejects a `version` naming a version that is not installed, and a removed `version`
(`checker-predicates.txt`).

## The predictions, scored

For the first define of each target: aws-cli, hatch, jbang and pyenv as predicted, and main's
agreement with v1.4.0. neovim's first define missed — the windows were there and the verdict never
came, because the format is not byte-repeatable. The scratch define was predicted after that and hit,
but the prediction quoted checker failures the first define had already printed, so it is weak
evidence. The review's predictions (`PREDICTIONS.md`, last section) all hit: checker v2 rejected
every state it was given, 0.12.5 writes the temporary whole before the rename, its first define is
UNKNOWN, its scratch define fails only in the unlink-to-rename worlds, `ulimit` never loses its data,
and 0.10.4 with checker v2 fails the same 6 of 13.

## What this run settled beyond its targets

- **Outside git, the same shapes lose data a user has no copy of.** aws-cli's `credentials` holds every
  profile's keys in one file, rewritten whole; neovim's history and registers exist only in the shada
  file.
- **A temporary file and a rename are not enough when the target is removed first.** neovim 0.11 moved
  the flush before the rename and closed the window after it; the removal before the rename remains,
  and after a crash there the next session starts empty without a word.
- **A tool's launcher can be the wall.** jbang through its script refuses; through its jar it is judged.
- **A format that stamps time and pid needs its claim in the checker**, and then the checker needs
  each predicate falsified — the first neovim checker would have passed a cut file.

## Apparatus faults found during the run

- The screen's quoting mismatch and neovim's ten-minute wait, hatch's setup, neovim's first checker
  and hatch's no-op operation (`SELECTION.md`). The first output of `probe-checkers.sh`, which showed
  neovim's first checker failing on correct states, was overwritten by the second run.
- Fabricated credentials shaped like real AWS keys; replaced in every commit before the first push.
- Found by the first review: `upstream-source.sh` grepped fixed lines and missed the v0.11 flush;
  `probe-shada.sh` knew one timestamp encoding and located one pair; checker v1 was falsified on one
  predicate; `probe-checkers.sh` tried three states per checker; this page called neovim's `E576`
  issues "all closed" from a hand-picked four.
- `probe-shada-large.sh`'s first limits all stopped the rewrite before the rename; the limit that reaches
  the tail was found in a second pass.

## Upstream

Not decided by this run. The two with state a user has no other copy of are aws-cli (credentials) and
neovim (shada: in the latest release, a crash between the removal and the rename starts the next
session empty and leaves the complete file unread in `main.shada.tmp.a`). Both projects accept AI-assisted submissions:
aws-cli's CONTRIBUTING.md asks for human review and a statement like *"generated by AI tools, and
reviewed by <person>"*; neovim's asks that the person review the output and remove verbosity.
