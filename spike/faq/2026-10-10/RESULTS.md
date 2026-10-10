# docs/faq.md, measured before it was written (#718)

Every recipe and every measured sentence in `docs/faq.md` comes from a run below; how each run was made is in `box/RUN.md`. Nothing here is a campaign: no blindness, no ledger rows, no funnel stage.

## Where

- **Linux**: `box/Dockerfile`, built by `box/build.sh` — Debian trixie, arm64 under Docker on an Apple-silicon laptop, `--network none`. Sideeye 1.10.0 from the release tarball through `docs/ci-quickstart/release/install-sideeye.sh`, Python 3.13.5 and pytest 8.3.5, cargo 1.85.1, go 1.24.4, strace 6.13. The image trusts this machine's TLS-intercepting proxy CA at build time, as `spike/followup-690/build.sh` does; `build.sh` removes the file after the build and `box/.gitignore` keeps it out.
- **macOS**: the same laptop, macOS on Apple silicon, Homebrew's sideeye 1.10.0, Python 3.14.7 (Homebrew, a framework build), cargo and go from Homebrew. No sudo, so no `fs_usage`.

## The three recipes (`box/py`, `box/rs`, `box/go`)

Each target writes `key.json` under its state directory: by a temporary file and a rename (correct), or by truncating in place and writing (the planted bug — a Python constant, a cargo feature, a Go constant). Each recipe was run four ways (`box/run-py-rs.sh`, `box/run-go.sh`; the cargo recipe again by `box/run-fix.sh`, after it was changed to read the report without depending on its whitespace):

| Run | pytest | cargo test | go test |
|---|---|---|---|
| correct tool | green | green | green |
| planted bug | red: `FAIL 1 of 4` | red: `FAIL 1 of 4` | red: `FAIL 1 of 4` |
| `--oracle` swapped for `--allow-unverified` | red: exit 0, `oracle_verified` false | red: the same | red: the same |
| no `sideeye` on `PATH` | red: "sideeye is not on PATH" | red: the same | red: the same |

The third row is the reason the recipes read the report: Sideeye exits 0 there, and only the report says no witness checked the PASS. The go test runs used `--privileged --cgroupns=private`; under Docker's defaults `--observe supervised` is a SETUP ERROR naming the cgroup it needs (`transcripts/linux/go-default-clean.txt`). `file` calls the Go binary statically linked (`transcripts/linux/go-file.txt`). Each cell is one run.

On macOS, with `--allow-unverified` in place of the witness and the verdict alone checked: cargo test and go test (without `--observe supervised`) green on the correct tool and red on the bug. pytest was red on the correct tool too — `UNKNOWN child_process_detected`, because Homebrew's `python3` is a framework launcher; the detail names the interpreter (`transcripts/macos/py-framework-launcher.txt`), and with that interpreter as the operation's first word, `sideeye explore` run directly (not through pytest) PASSes the correct tool 5/5 and FAILs the bug 1 of 4 (`py-interpreter-clean.txt`, `py-interpreter-bug.txt`, on `box/py/sideeye-macos-interpreter.toml`). With no witness and no flag the correct Rust tool is `UNKNOWN completeness_not_verified` (`rs-no-witness.txt`), and `--oracle-fs-usage` without cached sudo credentials is a SETUP ERROR asking for `sudo -v` (`rs-fs-usage-no-sudo.txt`). The planted-bug Rust tool explores 3 crash points on Linux and 2 on macOS (`linux/rs-bug.txt`, `macos/rs-bug.txt`): its `sync_all` is an `fsync` on Linux and an `fcntl(F_FULLFSYNC)` on macOS, which the shim does not record (`src/fsusage.zig`, `fcntlIsInert`).

## Writes that were never synced (`box/fsync`)

- `nosync.py` writes a temporary file, closes it without syncing, and renames it: PASS 4/4 under `--oracle` (`transcripts/linux/nosync.txt`). A process crash keeps every completed write.
- `unflushed.py` renames the file while its bytes are still in Python's buffer, before the close: FAIL 1 of 4, `key.json` holding neither the old nor the new content (`transcripts/linux/unflushed.txt`). What a process crash loses is what never reached the kernel.

## State in two places (`box/xdg`, `box/run-xdg.sh`, `box/run-home.sh`, `box/run-fix.sh`)

`xdgtool.py` keeps `config.json` under `$XDG_CONFIG_HOME` and rewrites `db.json` under `$XDG_DATA_HOME` in place; each falls back to its place under `HOME` when its variable is unset. `check.sh` reads both through the same variables.

| Run | Result |
|---|---|
| both variables under the state, `HOME` an empty directory | FAIL 1 of 3 at `data/xdgtool/db.json`, checker falsified and run in 3 worlds, `oracle_verified`; `HOME` still empty (`xdg-home.txt`) |
| `XDG_DATA_HOME` not set, with the `apparatus` entries | SETUP ERROR naming `XDG_DATA_HOME` — after the setup had run: it created `.local/share/xdgtool/db.json` under `HOME` (`xdg-missing.txt`, `xdg-missing-home.txt`) |
| `XDG_DATA_HOME` outside the state, no `apparatus` | UNKNOWN `nothing_could_fail` |
| both XDG variables unset, `HOME` under the state, no checker | FAIL 1 of 3 at `home/.local/share/xdgtool/db.json` |

## What this does not show

A GitHub runner was not used: the supervised runs were in a privileged container, not in the delegated cgroup this repository's CI makes. The recipes were run with these toy targets only, once per cell. `fs_usage` was not run (no sudo); the `F_FULLFSYNC` refusal under it is read from the source.
