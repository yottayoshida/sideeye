# 2026-09-16 — selection

Four slates of five, run back to back, using Sideeye the way a user would: on Linux
in Docker, against tools picked by the selection rules
(`spike/cohort4/SCOUT-BRIEF.md`, rules 1–17). The brief is the 2026-09-05 and
2026-09-06 runs' — what happens when Sideeye meets a tool it was not chosen for —
with the ordering rule those runs bought applied to every slate: **measure linkage
and threads before writing the candidate table**.

Repository metadata was measured with `gh api repos/<repo>` and
`gh api repos/<repo>/commits?since=<6 months ago>` on 2026-09-16. `100` in the
commit column is the API's page limit: a floor, not a count. Rule 11 was measured
with `apparatus/rule11-github.py`, which skips pull requests and times the first
comment **from somebody other than the reporter**; transcripts are under
`transcripts/meta/`.

Sideeye is the released **v1.4.0**, not a build: `sideeye-v1.4.0-aarch64-linux.tar.gz`
from the GitHub release, sha256 `7090573718945...b5b08820` matched against the digest
the release publishes, mounted read-only at `/se`. It reports
`sideeye 1.4.0 (trace contract v17)`. State and work live on the container's own
filesystem (#528).

## What was excluded before any candidate was measured

Checked against every record this repository keeps of what it has already touched:
`docs/target-classes.md`, `spike/unknown-rate/b-exclusions.txt`,
`spike/blind-hunt3/candidates.md`'s taint ledger, and the rejection tables of the
three earlier dogfood runs.

| Class | Names |
|---|---|
| Verdicts or walls on record | timewarrior, taskwarrior, calcurse, devtodo, abook, todoman, topydo, khal, buku, GNU Stow, Mercurial, Borg, black, rustfmt, poetry, papis, himalaya, mogrify, qpdf, exiv2, rdiff-backup, trash-cli, watson, pass, git, Jujutsu, chezmoi, gopass, Bun, joplin, beets, cargo, KeePassXC, unison, metaflac, mid3v2, fontforge, mutool, ocrmypdf, mlr, fonttools, bean-format, pyupgrade, jpegtran, bsdtar, isort, oxipng, rsync, newsboat, ansible-core |
| Taint ledger / b-exclusions | jrnl, omamori, khard, stow, hledger (sealed — do not scout) |
| Rejected by earlier runs | ledger, rbw, exiftool, direnv, dotbot, mise, uv, pdm, pipenv, mackup, yazi, nnn, ranger, glow, restic, rclone, syncthing, fdupes, irssi, rsnapshot, fclones, cmus, espanso, navi, optipng, weechat, sqlfluff, shfmt, yq, dasel, sops, ruff, taplo, vdirsyncer, MP4Box, picard, borgmatic, rmlint, sd, gifsicle, yadm, jpegoptim, crudini, augeas, par2cmdline, kid3, mkvpropedit, tiffset, mbsync |

## Slate 1 — tools that rewrite a file in place

| Candidate | repo | ★ | Lang | 6-month commits | authors | Verdict |
|---|---|---|---|---|---|---|
| codespell | codespell-project/codespell | 2,425 | Python | 100 | 25 | passes |
| rubocop | rubocop/rubocop | 12,902 | Ruby | 100 | 8 | passes |
| vim | vim/vim | 40,892 | C | 100 | 28 | passes |
| zstd | facebook/zstd | 27,868 | C | 56 | 8 | passes |
| zoxide | ajeetdsouza/zoxide | 39,487 | Rust | 43 | 7 | passes |
| typos | crate-ci/typos | 4,134 | Rust | 100 | 5 | passes here, **rule 10** below |
| yapf | google/yapf | 13,986 | Python | **0** | 0 | **rule 2** |
| autopep8 | hhatto/autopep8 | 4,660 | Python | 24 | **2** | **rule 3** |
| autoflake | PyCQA/autoflake | **952** | Python | 18 | 5 | **rule 1** |
| add-trailing-comma | asottile/add-trailing-comma | **373** | Python | 14 | 2 | **rule 1** |
| djLint | djlint/djLint | **948** | Python | 100 | 5 | **rule 1** |
| tidy | htacg/tidy-html5 | 2,847 | C | **0** | 0 | **rule 2** (last push 2024-05-04) |
| shellharden | anordal/shellharden | 4,805 | Rust | 4 | **1** | **rule 3** |
| 7zz | ip7z/7zip | 3,926 | C++ | 3 | **1** | **rule 3** |
| exiftool | exiftool/exiftool | 5,041 | Perl | 10 | **1** | **rule 3** (the 2026-09-05 reading, re-measured) |
| uncrustify | uncrustify/uncrustify | 3,068 | C++ | 100 | 11 | **rule 11** — #4782, #4780, #4777, #4775: no reply from anyone but the reporter |
| StyLua | JohnnyMorganz/StyLua | 2,292 | Rust | 26 | 3 | **rule 11** — #1155, #1154, #1153, #1151: same |
| PHP-CS-Fixer | PHP-CS-Fixer/PHP-CS-Fixer | 13,550 | PHP | 100 | 16 | **rule 11** — #9838, #9829, #9827: same |
| calibre | kovidgoyal/calibre | 25,910 | Python | 100 | 8 | **rule 11 unmeasurable** — GitHub issues are off; the tracker is Launchpad, and no instrument for it was written |
| clang-format | llvm/llvm-project | 40,486 | LLVM | 100 | 63 | **rule 4** — the repository's primary interface is a compiler toolchain and its libraries; `clang-format` is one artifact of it |

**rule 10, measured**: the only Linux aarch64 artifact `typos` publishes is
`typos-v1.50.2-aarch64-unknown-linux-musl.tar.gz`, and `file` on the unpacked binary
reads `statically linked`. That is `no_shim_marker` before a define exists, and
Debian trixie has no package, so there is no build a user would have.

Rule 11 receipts for the five taken: codespell #4003 1.8d; rubocop #15671 3.0d and
#15639 closed in 5 days with no comment; vim #21318 0.3d, #21315 0.0d; zstd #4779
1.4d; zoxide #1283 5.6d.

## Slate 2 — tools that keep their own store

| Candidate | repo | ★ | Lang | 6-month commits | authors | Verdict |
|---|---|---|---|---|---|---|
| fish | fish-shell/fish-shell | 34,204 | Rust | 100 | 10 | passes |
| pip | pypa/pip | 10,286 | Python | 100 | 20 | passes |
| rrdtool | oetiker/rrdtool-1.x | 1,117 | C | 96 | 8 | passes |
| composer | composer/composer | 29,522 | PHP | 100 | 19 | passes |
| pre-commit | pre-commit/pre-commit | 15,575 | Python | 37 | 4 | passes |
| neomutt | neomutt/neomutt | 3,834 | C | 100 | 11 | **rule 8** — measured: `neomutt -f <mbox> -e 'push "<delete-message><sync-mailbox><quit>"'` answers `No recipients specified` and leaves the mbox byte-identical. No non-interactive mutating invocation was found |
| aria2 | aria2/aria2 | 42,363 | C++ | 4 | 3 | held in reserve, not measured |
| libvips | libvips/libvips | 11,646 | C | 100 | 15 | moved to slate 3 |

Rule 11 receipts: fish #13000 0.2d; pip #14315 0.0d, #14309 0.0d, #14307 0.0d;
rrdtool #1358 5.3d; composer #13055 0.0d, #13047 0.0d; pre-commit #3753 0.0d,
#3749 0.0d, #3744 0.2d; neomutt #5033 0.1d.

## Slate 3 — tools that write a derived artifact next to your files

| Candidate | repo | ★ | Lang | 6-month commits | authors | Verdict |
|---|---|---|---|---|---|---|
| bat | sharkdp/bat | 60,464 | Rust | 100 | 18 | passes |
| sphinx | sphinx-doc/sphinx | 8,015 | Python | 14 | 11 | passes |
| virtualenv | pypa/virtualenv | 5,044 | Python | 100 | 12 | passes |
| vips | libvips/libvips | 11,646 | C | 100 | 15 | passes |
| tesseract | tesseract-ocr/tesseract | 76,502 | C++ | 100 | 14 | passes |
| logrotate | logrotate/logrotate | 1,548 | C | 15 | 5 | **rule 11** — #718, #717, #713, #705: no reply from anyone but the reporter |
| pipx | pypa/pipx | 12,965 | Python | 100 | 21 | **rule 11** — the one answered issue (#2030) took 8.4d; #2021, #2015, #2014 sit at zero |
| gpsbabel | gpsbabel/gpsbabel | **550** | C++ | 67 | 9 | **rule 1** |

Rule 11 receipts: bat #4007 2.2d; sphinx #14664 0.7d; virtualenv #3205, #3199,
#3181, #3171 all carry replies; vips #5194 0.1d, #5187 0.4d (#5195 at 8.7d is the
counter-evidence, stated); tesseract #4624 0.3d, #4621 2.3d, #4619 0.8d.

## Slate 4 — build and cache tools

| Candidate | repo | ★ | Lang | 6-month commits | authors | Verdict |
|---|---|---|---|---|---|---|
| ninja | ninja-build/ninja | 13,230 | C++ | 100 | 21 | passes |
| ccache | ccache/ccache | 2,955 | C++ | 100 | 14 | passes |
| pandoc | jgm/pandoc | 46,296 | Haskell | 100 | 5 | passes |
| meson | mesonbuild/meson | 6,632 | Python | 100 | 6 | passes |
| coreutils (uutils) | uutils/coreutils | 24,089 | Rust | 100 | 23 | passes |
| hyperfine | sharkdp/hyperfine | 28,867 | Rust | **1** | **1** | **rules 2, 3** |

Rule 11 receipts: ninja #2834 0.7d; ccache #1812 0.0d, #1809 0.3d; pandoc #11867
0.0d; meson #16212 0.2d, #16205 1.0d, #16203 0.7d, #16199 0.1d; uutils #14563,
#14556, #14552 all carry replies.

## The measured screen, before each slate was fixed (rule 10)

Every metadata survivor was run once inside the image on **a real writing
operation** — not `--version`, which is what the 2026-09-05 run's `beet ls` lesson
paid for. `file -L` for linkage, `strace -f -e trace=clone,clone3` for threads.
Transcripts: `transcripts/screen/r1-screen.txt` … `r4-screen.txt`; scripts
`apparatus/screen.sh`, `screen2.sh`, `screen2b.sh`, `screen3.sh`, `screen4.sh`.

| Candidate | Linkage | Threads | Children (clone) | Taken |
|---|---|---|---|---|
| codespell | script → `python3` | 0 | 0 | ✅ |
| vim | dynamic | 0 | 0 | ✅ |
| zstd | dynamic | **3** | 3 | ✅ — v17 judges a run whose state writes come from one thread per process, so a thread count is not a refusal on its own |
| rubocop | script → `ruby` | **2** | 2 | ✅ — same |
| zoxide | dynamic | 0 | 0 | ✅ |
| fish | dynamic | 2 | 2 | ✅ |
| pip | script → `python3` | 0 | 2 | ✅ |
| rrdtool | dynamic | 0 | 0 | ✅ |
| composer | script → `php` | 0 | **20** | ✅ |
| pre-commit | script → `python3` | 0 | 7 | ✅ |
| neomutt | dynamic | 2 | 14 | ❌ rule 8 (rc=1, mbox unchanged) |
| bat | dynamic | 0 | 0 | ✅ |
| sphinx | script → `python3` | 0 | 0 | ✅ |
| virtualenv | script → `python3` | **3** | 3 | ✅ |
| vips | dynamic | **8** | 8 | ✅ |
| tesseract | dynamic | **4** | 4 | ✅ |
| ninja | dynamic | 0 | 3 | ✅ |
| ccache | dynamic | 0 | 10 | ✅ |
| pandoc | dynamic | **5** | 5 | ✅ |
| meson | script → `python3` | 0 | **21** | ✅ (its first screen failed on the image, not the target: `meson` picked up the image's `ccache cc` and then `gcc` without `libc6-dev`, so its compiler check could not link. Fixed in `Dockerfile.run4`) |
| coreutils cp | dynamic | 0 | 0 | ✅ |

What the screen produced that reading would not have:

- **`zstd --rm` starts three threads**, and `--single-thread` does not remove them —
  the same shape as `oxipng -t 1` on 2026-09-05. Under `--observe syscalls` two of
  them turn out to write the state directory (the refusal in `RESULTS.md`).
- **`rubocop` threads and is still judged.** A Ruby VM's timer thread does not write
  the state, and contract v17 counts writers rather than threads.
