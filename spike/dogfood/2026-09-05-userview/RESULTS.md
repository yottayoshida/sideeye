# 2026-09-05 — results

Host: macOS 15 on Apple Silicon, Docker 29.4.0, `linux/arm64`. Engine and shim
cross-built from the checkout with `zig build -Dtarget=aarch64-linux-gnu
-Doptimize=ReleaseSafe`, mounted read-only into the container; Sideeye reports
itself as `sideeye 1.1.0 (trace contract v13)`. Base image `debian:trixie-slim`.
Every raw exit code below was taken before the command's output reached a pipe.

## Verdicts

| Target | Version measured | Verdict | Earliest crash point | What the crashed state holds |
|---|---|---|---|---|
| **mogrify** | ImageMagick 7.1.1-43 Q16 (Debian `8:7.1.1.43+dfsg1-1+deb13u11`) | **FAIL 6 of 13** | 2 of 12 — after `rename(img1.png)`, before `open(img1.png)` | no file at `img1.png`; the original 425 bytes are at **`img1.png~`**, which `identify` reads as 128x128 |
| **qpdf** | 12.4.x (Debian trixie) | **FAIL 1 of 9** | 7 of 8 — after `rename(a.pdf)`, before `rename(a.pdf.~qpdf-temp#)` | no file at `a.pdf`; the original is at `a.pdf.~qpdf-orig#` |
| **exiv2** | 0.28.5 (Debian `0.28.5+dfsg-1`) | **FAIL 3 of 7** | 2 of 6 — after the truncating `open(pic1.jpg)`, before `write` | **`pic1.jpg` is 0 bytes and the original is nowhere**; the other two files are untouched |
| **rdiff-backup** | 2.2.6 (Debian trixie) | **FAIL 1 of 69** | 51 of 68 — after `open(increments/f1.txt….diff.gz)`, before `write` | `rdiff-backup verify` reports one potentially corrupted file, **after `rdiff-backup regress` has run** |

All four are `oracle_verified` against `strace`. All four checkers were falsified
against deliberately corrupted state before the run, and every checker asserts
through the target's own command (`identify`, `qpdf --check`, `rdiff-backup
verify`) rather than over raw bytes.

### The rdiff-backup checker was wrong the first time

The first measurement asserted `rdiff-backup verify` immediately after the crash
and returned **FAIL 5 of 69**. That checker ignores the tool's own recovery
contract: an interrupted backup is meant to be repaired by `regress`, which the
next invocation runs automatically. Re-measured with `regress` ahead of the
assert — which is what `spike/cohort4/SCOUT-BRIEF.md`'s checker sketch asks for,
*"which documented recovery step precedes the assert"* — **four of the five
worlds recover** and one does not.

This is the buku lesson (`docs/target-classes.md`) reached from the other
direction: there, judging a journalled store by bytes was stricter than its
contract. Here, judging a journalled store without running its journal was.

## Named walls

| Target | Version | Wall | Detail |
|---|---|---|---|
| **chezmoi** | 2.72.1 | `no_shim_marker` | Statically linked. Measured on **both** published Linux artifacts — `chezmoi_2.72.1_linux_arm64.tar.gz` and `…_arm64.deb` — and Debian trixie has no `chezmoi` package, so no Linux install path is dynamic |
| **gopass** | 1.17.0 | `no_shim_marker` | Same, both artifacts. Non-interactive setup is possible (`GOPASS_AGE_PASSWORD` with `--crypto age --storage fs`), so rule 8 holds; the wall is linkage alone |
| **beets** | 2.13.1 | `multiple_threads_detected` | Present on **read-only `beet ls`** and on `beet modify`, and `config: threaded: no` does not remove it. `python3` writing a file is `recording accepted`; so is `python3` after `import beets`. The thread belongs to the `beet` entry point. Not `threading.Thread` — a patch on `Thread.start` never fired, so it is a C extension |
| **joplin** | 3.6.x (npm) | `multiple_threads_detected` | `node[54]: pthread_create: Invalid argument` in the recording run. **This is the first real Node/libuv target measured in this repository**; `docs/target-classes.md` carried the thread refusal for Node as a labelled prediction |

## Two things about the refusals themselves

**`no_shim_marker` diagnoses correctly only when the operation names a path.**
Same target, same wall, two different explanations:

| Operation as written | What Sideeye says |
|---|---|
| `chezmoi apply …` (through `PATH` — how a user writes it) | *"the operation's first word names no path, so the OS resolved it through PATH and Sideeye did not"* |
| `/usr/local/bin/chezmoi apply …` | *"it names no interpreter, so it is statically linked and no preloaded library can reach it"* |

The first reads as an instruction to use a full path. Using one changes nothing
about whether the target can be measured.

**Wrapping an operation in a shell script changes which wall you meet.** The
first gopass attempt used a `sh` wrapper to carry environment variables, and
`sh` — being dynamic — loaded the shim, so the refusal became
`boundary_without_oracle` (the wrapper `exec`s a child) rather than
`no_shim_marker`. Passing the environment to the engine instead, as
`docs/scouting.md`'s lessons say to, produced the real wall.

## Novelty check

Run with `spike/cohort4/novelty-prescan.sh` (transcripts in `transcripts/novelty/`),
plus targeted `gh` searches and, for both reported findings, a reading of the
current upstream source to confirm the code path still exists.

| Finding | Already known? | Reported |
|---|---|---|
| exiv2 truncates in place | **No** — `interrupted` returns 1 hit (an unrelated Olympus makernote issue), `atomic` 4 (all unrelated). `FileIo::transfer`'s generic branch on current `main` still does `open("w+b")` then `write`, while the same function's `FileIo` branch uses `rename` | **filed: [Exiv2/exiv2#9482](https://github.com/Exiv2/exiv2/issues/9482)** |
| mogrify leaves the name empty | **No** — `mogrify+interrupted` 1 hit, `mogrify+atomic` 1, `mogrify+lost` 8, none about interruption. Current `main` carries the same rename/write/remove block | **filed: [ImageMagick/ImageMagick#8939](https://github.com/ImageMagick/ImageMagick/issues/8939)**, written as minor with an explicit "closing this is a fine outcome" |
| qpdf leaves the name empty | **Yes — this project's own**: [qpdf#1773](https://github.com/qpdf/qpdf/issues/1773), filed 2026-09-04, same two-rename window | not re-filed |
| rdiff-backup leaves an unrecoverable increment | **Yes — a third party's**: [rdiff-backup#1084](https://github.com/rdiff-backup/rdiff-backup/issues/1084), open since 2025-10-04 against the same 2.2.6, reporting that regression cannot handle an interrupted compressed file in `increments/` | not filed |

Neither filed report claims a broken promise. `mogrify`'s documentation says the
original is overwritten and says nothing about atomicity; exiv2's says nothing
either. What is claimed is that the window exists, that it is silent, and — for
exiv2 — that the data is not recoverable afterwards.

## What installing the targets cost, since a user pays it too

`joplin` needed four rounds to install on Debian trixie, and each failure is a
property of the environment rather than of Sideeye:

1. `keytar`'s `node-gyp` build cannot find libsecret headers → `libsecret-1-dev`
2. `node-gyp` fetches Node headers from `nodejs.org` and dies on this machine's
   TLS-intercepting proxy (`prebuild-install warn install self-signed certificate
   in certificate chain`) → `libnode-dev` plus `npm_config_nodedir=/usr` removes
   the fetch. This is the same proxy cohort 2 recorded in its Dockerfile
3. `npm config set nodedir` is not a valid npm option — it has to be the
   environment variable
4. `node-gyp` 8.4.1's bundled gyp does `from distutils.version import
   StrictVersion`, and Debian trixie ships Python 3.13, where `distutils` is gone
   → `setuptools` supplies it

And after all four, `joplin version` still fails with `Cannot find module
'../package.json'` — a packaging fault in the published CLI. Other subcommands
work, so the image asserts on `joplin --help` instead.
