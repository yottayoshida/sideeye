# 2026-09-16 — outside git: results

Five targets whose state lives outside version control (`SELECTION.md`), explored with the released
v1.4.0 and once more each with main `047592d` (contract v18, not a release). As root in a
`--privileged` container on Linux aarch64, state on the container's filesystem. Drivers
`apparatus/explore.sh` and `apparatus/explore-nvim-scratch.sh`; transcripts and JSON reports in
`transcripts/explore/`; predictions committed before each exploration in `PREDICTIONS.md`.

| Target | Mode(s) | v1.4.0 | main `047592d` | Predicted | Upstream |
|---|---|---|---|---|---|
| aws-cli 2.23.6 `configure set` | wrappers ×3, syscalls ×1 | **FAIL** 4/4 — `credentials` empty, both profiles' keys gone | FAIL 1/1 | FAIL — hit | no report in the searched results; the same code on `v2` |
| hatch 1.18.0 `config set` | wrappers ×3, syscalls ×1 | **PASS** 4/4, 6/6 worlds over 5 crash points | PASS 1/1 | PASS — hit | — |
| neovim 0.10.4 `:wshada` | wrappers ×3, syscalls ×1 | first define **UNKNOWN** 4/4 `baseline_violates_invariant`; with `main.shada` scratch, **FAIL** 4/4 on the checker, 6 of 13 worlds | UNKNOWN 1/1; FAIL 1/1 | FAIL — the first define missed (no verdict); the second, predicted after, hit | no report of this mechanism in the searched results; the same order on `master` |
| jbang 0.141.0 `config set` | wrappers ×3, syscalls ×1 | **FAIL** 4/4 — `jbang.properties` empty | FAIL 1/1 | FAIL — hit | none in the searched results |
| pyenv 2.8.5 `global` | syscalls ×3 | **FAIL** 3/3 — `version` empty, pyenv falls back to `system` | FAIL 1/1 | FAIL — hit | none in the searched results |

main gave the same answer as v1.4.0 for every define. None of the five was refused at exploration
on a wall its screen had not shown.

## aws-cli — FAIL: one failed write empties every profile's credentials

**Crash point 2 of 2, 4 of 4 runs, the same under main** (`transcripts/explore/aws.*`). Between the
`open` and the `write` of `credentials`, the checker — which asks the CLI itself — reports
`default profile's access key is "" (0 bytes in credentials)`. The edited profile was `work`; the
`default` profile's keys are lost with it, because the whole file is rewritten.

The screen's capture: `openat(credentials, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666)` and one
230-byte `write` (`transcripts/probes/open-flags.txt`, cut from the uncommitted capture by
`apparatus/excerpts.sh`; every strace line this page quotes is there). The source says the same:
`awscli/customizations/configure/writer.py` rewrites an existing file with
`with open(config_filename, 'w') as f: f.write(''.join(contents))` — lines 65–66 at tag `2.23.6`
and lines 114–115 on the `v2` branch (`apparatus/upstream-source.sh`,
`transcripts/meta/upstream-source.txt`; the newest tag was `2.36.46`).

**Without Sideeye and without a crash** (`apparatus/probe-ulimit.sh`, `transcripts/probes/ulimit.txt`):
`ulimit -f 0` and the same command leave `credentials` at **0 bytes** (231 before), exit status 120.
Measured only as `EFBIG` under a file-size limit; a full disk was not measured.

## hatch — PASS

**6/6 worlds over 5 crash points, 4 of 4 runs and 1 under main.** A temporary file is created
`O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW`, written, `fsync`ed and renamed over `config.toml`. The checker —
`hatch config show`, the file parsed, the setting the old value or the new one — passed in every
world. The contrast inside this run is aws-cli: both are Python tools writing a user's
configuration, and one of them goes through a temporary file.

## neovim — FAIL on the checker: the shada file is removed before the rename, and written after it

**The first define refused, and the refusal is the shada format.** 4 of 4 runs (and 1 under main)
returned `UNKNOWN baseline_violates_invariant`: the uncrashed re-run left `main.shada` *"holding
neither the old nor the new content"*. `apparatus/probe-shada.sh` ran the same operation from the
same state three times: back to back the copies differ in 1 byte, one second apart in 3, and every
differing byte is inside a msgpack timestamp or the header's `pid` (`transcripts/probes/shada.txt`).
The worlds that first define explored had already printed the checker's failures —
`main.shada is gone (main.shada.tmp.a )` and `register a is lost (0 bytes in main.shada)` — before
the baseline refused the run.

**The second define declares `main.shada` scratch** (ADR 0043) and leaves the claim to the checker,
which reads back the command-line history entry and register `a` the setup stored, through nvim
itself. **FAIL 4 of 4 runs, 6 of 13 worlds, earliest crash point 3 of 12, and 1/1 under main**
(`transcripts/explore/nvim-scratch.*`). The earliest failing world is *after* `unlink(main.shada)`
and *before* `rename(main.shada.tmp.a)`: `main.shada is gone`. The others are after the rename and
before the write: `register a is lost (0 bytes in main.shada)`. The operation writes the file
twice (`:wshada` and again on quitting), so each window appears twice.

**The order, in the capture and in the source.** nvim 0.10.4 opens `main.shada.tmp.a`
`O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW`, unlinks `main.shada`, renames the temporary over it, and only
then issues the 160-byte `write` and the `fsync` on the same descriptor. In `src/nvim/shada.c`,
`shada_write_file` fills a buffered writer, calls `vim_rename(tempname, fname)`, and flushes in
`close_file(&sd_writer)` afterwards; `vim_rename` in `src/nvim/fileio.c` calls `os_remove(to)`
before `os_rename(from, to)`. Both are at the same places on `master` as at `v0.10.4`
(`transcripts/meta/upstream-source.txt`; the latest release is `v0.12.5`, which was not measured).

**A shada file of ordinary size is cut, not emptied** (`apparatus/probe-shada-large.sh`,
`transcripts/probes/shada-large.txt`). With 400 history entries the file is 25,715 bytes, and the
writer flushes its 4 KiB buffer to the temporary file as it fills, so most of the file is written
before the rename. A file-size limit of 4,096 to 25,088 bytes stops nvim before the rename: the
original survives and `main.shada.tmp.a` is left beside it. At **25,600 bytes** only the tail after
the rename fails: `main.shada` is left at 25,600 bytes, and the next nvim reports
**`E576: Error while reading ShaDa file: last entry specified that it occupies 57 bytes, but file
ended earlier`** and reads 398 history entries. `E576` appears in earlier neovim issues —
neovim/neovim#23345, neovim/neovim#29186, neovim/neovim#3469, neovim/neovim#4108, all closed —
whose causes this run did not read; whether any came from this window is not known.

**Without Sideeye**, the small file of the define: `ulimit -f 0` kills nvim with `SIGXFSZ` (status
153) and leaves `main.shada` at **0 bytes** (136 before) (`transcripts/probes/ulimit.txt`).

## jbang — FAIL, the truncating rewrite

**Crash point 2 of 2, 4 of 4, the same under main.** `openat(jbang.properties,
O_WRONLY|O_CREAT|O_TRUNC)` and one 45-byte `write`; the checker, `jbang config get first.key`
through the jar, returns nothing: `No configuration option found with that name: first.key`.
`ulimit -f 0` leaves the file at 0 bytes (21 before). Measured through the jar, which is what the
`jbang` script runs; the script itself is refused `child_touched_state_dir` (`SELECTION.md`).

## pyenv — FAIL, under the syscall observer only

**3 of 3 runs under `--observe syscalls`, 2 of 4 worlds, earliest crash point 2 of 3, and 1/1 under
main.** A bash child opens `version` `O_WRONLY|O_CREAT|O_TRUNC`, then again `O_APPEND` and writes
`3.12.4`; killed between the two opens, `version` is empty and `pyenv version-name` answers
`system`. `ulimit -f 0` gives the same (7 bytes to 0). Under `--observe wrappers` the recording is
refused `state_changed_without_ops`, in both builds.

## The predictions, scored

Four of five as predicted for the first define of each (aws-cli, hatch, jbang, pyenv), and main's
agreement with v1.4.0. The miss is neovim: the prediction named the right windows and the verdict
it expected never came, because the shada format is not byte-repeatable across two clean runs. The
second define was predicted after that and before it ran, and hit; it is scored separately.

## What this run settled beyond its targets

- **Outside git, the same shapes lose data a user has no copy of.** aws-cli's `credentials` holds
  every profile's keys in one file, rewritten whole; neovim's history and registers exist only in
  the shada file.
- **A rename is not enough when the write comes after it.** neovim uses a temporary file, and the
  crash windows are still there — one because the target is removed first, one because the buffer
  is flushed after the rename.
- **A tool's launcher can be the wall.** jbang through its script refuses; through its jar it is
  judged.
- **A format that stamps time and pid needs its claim in the checker.** neovim reached a verdict
  only with the file declared scratch; the checker's reading of history and registers carried it.

## Apparatus faults found during the run

- The screen's quoting mismatch and neovim's ten-minute wait, hatch's setup, neovim's first checker
  and hatch's no-op operation (`SELECTION.md`). The first version of `probe-checkers.sh`'s output,
  which showed neovim's checker failing on correct states, was overwritten by the second run.
- `probe-shada-large.sh`'s first limits (4,096 to 20,480 bytes) all stopped the rewrite before the
  rename; the limits that reach the tail were found in a second pass.

## Upstream

Not decided by this run. The two with state a user has no other copy of are aws-cli (credentials)
and neovim (shada). Both projects accept AI-assisted submissions: aws-cli's CONTRIBUTING.md asks for
human review and a statement like *"generated by AI tools, and reviewed by <person>"*; neovim's asks
that the person review the output and remove verbosity. Neither search turned up a report of these
mechanisms (`apparatus/novelty.sh`, `transcripts/meta/novelty.txt`).
