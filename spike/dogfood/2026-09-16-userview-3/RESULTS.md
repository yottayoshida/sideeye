# 2026-09-16 — results

Host: macOS on Apple Silicon, Docker 29.4.0, `linux/arm64`, base image
`debian:trixie-slim`. Sideeye is the released v1.4.0 (`trace contract v17`),
mounted read-only from the verified release tarball. Twenty targets over four
slates: **eight counterexamples, three PASS, nine named walls**. Every quoted line
below is the report's own; `…` marks where one is cut.

| Slate | Target | Outcome | Transcript |
|---|---|---|---|
| 1 | **codespell** 2.4.1 | **FAIL** 3/7 | `explore/codespell.*` |
| 1 | **rubocop** | **FAIL** 2/5 | `explore/rubocop.*` |
| 1 | **zoxide** | **PASS** 5/5 (with a pinned clock) | `explore/zoxide2.*` |
| 1 | vim | `unsupported_syscall_observed` — `getxattr`, in both observation modes | `explore/vim2*.txt` |
| 1 | zstd | `multiple_threads_detected` under `--observe syscalls`; `oracle_missed_operation` under wrappers | `explore/zstd*.txt` |
| 2 | **pip** 25.1.1 | **PASS** 5/5 | `explore/pip2.*` |
| 2 | **composer** | **FAIL** 2/5 | `explore/composer3.*` |
| 2 | **pre-commit** | **FAIL** 2/5 | `explore/precommit.*` |
| 2 | rrdtool | `unsupported_syscall_observed` — `mmap(PROT_WRITE\|MAP_SHARED)` | `explore/rrdtool.txt` |
| 2 | fish | `unsupported_syscall_observed` — `inotify_add_watch`; and its history is not written non-interactively at all | `explore/fish*.txt` |
| 3 | **sphinx** | **PASS** 2/2, over a single crash point | `explore/sphinx.*` |
| 3 | **vips** (libvips) | **FAIL** 1/3 | `explore/vips.*` |
| 3 | **tesseract** | **FAIL** 1/3 | `explore/tesseract2.*` |
| 3 | virtualenv | `multiple_threads_detected` — two threads `mkdir` inside the judged root | `explore/virtualenv.txt` |
| 3 | bat | `baseline_violates_invariant` — `metadata.yaml`, and a faked clock does not fix it | `explore/bat2.txt` |
| 4 | **pandoc** | **FAIL** 1/4 | `explore/pandoc.*` |
| 4 | **coreutils cp** (uutils) | **FAIL** 2/5 | `explore/uucp.*` |
| 4 | ninja | a process leaves the containment group in a default container; with `--privileged`, `oracle_missed_operation` on the `.ninja_log` write | `explore/ninja*.txt` |
| 4 | ccache | `kill_did_not_land` — the sequence of state-directory calls varies between runs | `explore/ccache2.txt` |
| 4 | meson | `baseline_violates_invariant` — `meson-logs/meson-log.txt` | `explore/meson.txt` |

## Seven of the eight counterexamples are one shape

The engine names the same window in seven targets, in four languages, across three
slates: **the file is opened for truncation, and the process dies before the write**.
What is left is a zero-length file, and the content that was there is nowhere.

| Target | Earliest crash point | Window | Path |
|---|---|---|---|
| codespell | 2 of 6 | after `open(a.txt)`, before `write(a.txt)` | `a.txt` |
| rubocop | 2 of 4 | after `open(a.rb)`, before `write(a.rb)` | `a.rb` |
| composer | 2 of 4 | after `open(…/autoload_classmap.php)`, before `write(…)` | `vendor/composer/autoload_classmap.php` |
| vips | 2 of 2 | after `open(out.png)`, before `write(out.png)` | `out.png` |
| tesseract | 2 of 2 | after `open(out.txt)`, before `write(out.txt)` | `out.txt` |
| pandoc | 3 of 3 | after `truncate(out.html)`, before `write(out.html)` | `out.html` |
| coreutils `cp` | 2 of 4 | after `open(dst.txt)`, before `open(dst.txt)` | `dst.txt` |

Each report's `observed` line is the same sentence: *"holding neither the old nor
the new content"*. In five of the seven the checker agreed independently — the
invariant line reads `built-in atomicity, and the checker` — and in composer's case
the consequence is the one a user meets: PHP's `require 'vendor/autoload.php'` then
cannot load a class that was there before, which is what `check-composer.sh` tests.

**This class is not new to this project and the four reports it already filed are
the reason to read the result carefully.** `spike/dogfood/2026-09-06-userview-2/`
filed fonttools#4170, beancount#1051, pyupgrade#1101 and libjpeg-turbo#914; the
2026-09-11 run filed oxipng#873. Their state on 2026-09-16:

| Report | State | What upstream said |
|---|---|---|
| fonttools#4170 | closed | *"If the position is that `--output-file` naming the input is the caller's risk — i would say so, yes."* |
| pyupgrade#1101 | closed | *"please spend your tokens on something actually valuable instead of useless spam"* |
| oxipng#873 | closed | *"this type of behaviour is pretty common but exceedingly unlikely to occur in practice … you should be writing to a different output file"*, and *"this hand-holding is out of scope"* |
| beancount#1051 | open | no comment in ten days |
| libjpeg-turbo#914 | open | three comments, still under discussion |

Five filings, three explicit declines, one silence, one live discussion. The
distinguishing property a sixth filing would have to carry is that **the tool has no
"write somewhere else" option** — `codespell --write-changes` and `rubocop
--autocorrect` exist in order to rewrite the file you point them at, so the oxipng
answer does not transfer. Whether that is enough is a judgement about the people on
the other end, and this run does not make it alone: see "Reporting" below.

## The eighth: pre-commit loses the hook's name, not its content

`pre-commit install` documents that it moves an existing hook aside — the file it
writes is `pre-commit.legacy`. The engine's L0 invariant fired anyway:

> earliest crash point 3 of 4 — after `rename(.git/hooks/pre-commit)`, before
> `open(.git/hooks/pre-commit)`; observed: *"present before and after the operation,
> but gone from the crashed state"*

So the window is between the rename and the creation of the replacement: crash there
and `.git/hooks/pre-commit` does not exist, while `.git/hooks/pre-commit.legacy`
holds the user's original. **No content is lost** — the checker, which looks for the
original in either place, passed in those worlds. What the user loses is that the
hook does not run until someone notices and re-installs. That is the correct reading
of an L0 FAIL whose checker did not fail, and it is why the two are reported
separately.

## Three PASSes, and what each one cost to reach

- **zoxide 5/5.** The first define was refused: `baseline_violates_invariant` on
  `db.zo`, because the database carries access times. With libfaketime in
  `/etc/ld.so.preload` and `apparatus = ["env:FAKETIME=@2024-01-01 00:00:00",
  "preload:libfaketime"]` declared in the toml, it reaches a verdict — and the
  report carries the apparatus line, so the pin is part of the record rather than a
  launcher detail (ADR 0041's point, met in practice).
- **pip 5/5**, with the exception the README names on its own report: *"493 path(s)
  attributed to a directory a recorded `rename` moved in from outside the judged
  root"*. pip unpacks into a temporary directory and renames it in, so almost the
  whole install arrives through the one gap this engine declares rather than hides.
  A PASS here says the rename was atomic; it does not say the 493 paths were each
  checked.
- **sphinx 2/2, "over a single crash point"** — the `#487` tell. An incremental
  rebuild of an unchanged document writes one file inside the judged root, and the
  report says so in the verdict line rather than letting 2/2 read like 44/44.

## Nine walls, three of them new shapes for this project

- **vim — `getxattr`.** Refused in both observation modes, with `set nobackup
  noswapfile nowritebackup` in the define (argv form, so the options carrying spaces
  survive). An editor's save path asks for the extended attributes of the file it is
  about to replace; the engine has no wrapper for that call and refuses rather than
  recording an incomplete account.
- **zstd — the same run, two different refusals.** Under wrappers:
  `oracle_missed_operation`, *"the oracle saw: `write(4</…/f.bin.zst>, …, 3578)`; the
  shim recorded: `unlink("/…/f.bin")`"*. Under `--observe syscalls`:
  `multiple_threads_detected`, *"tid 22 performed `open(…f.bin.zst)` and tid 23
  performed `write(…f.bin.zst)`"*. The second names the cause; the first reads as a
  shim gap. `--single-thread` does not change it — the flag sizes the pool, the same
  measurement `oxipng -t 1` produced on 2026-09-05.
- **ccache — `kill_did_not_land`**, *"an operation whose sequence of state-directory
  calls varies between runs cannot be explored at a fixed index"*. This is the first
  time this project has met that refusal on a real target. Reaching it needed a
  checker that could fail: the first one ("`ccache -s` still runs") was accepted over
  a state whose every file had been overwritten with junk, so the engine refused with
  `checker_not_falsified` — correctly. The checker that replaced it recompiles the
  file cached in `setup` and requires `direct_cache_hit` to rise.
- **ninja — two walls in sequence.** In a default container: a process leaves the
  containment group (`setsid`/`setpgid`) and the engine cannot make a cgroup, so it
  refuses rather than claim to have stopped it. Re-run `--privileged` (the shape
  #559 built): `oracle_missed_operation` on the `.ninja_log` write — stdio again,
  past ADR 0005's flush boundary.
- **rrdtool — `mmap(PROT_WRITE|MAP_SHARED)`.** An RRD is updated through a shared
  mapping; there is no call to interpose.
- **fish — two defines, two answers.** The history file is not written by a
  non-interactive `fish -c` at all (`checker_not_falsified`: the state directory was
  empty). Universal variables are written non-interactively, and then
  `inotify_add_watch` refuses the run.
- **virtualenv — `multiple_threads_detected`**, *"tid 154 performed
  `mkdir(…/v2)` and tid 156 performed `mkdir(…/v2/lib/python3.13/site-packages/pip-…)`"*.
- **bat and meson — non-deterministic writers.** `metadata.yaml` and
  `meson-logs/meson-log.txt` differ between two clean runs. For bat a pinned clock
  did not fix it, so the variation is not the clock.

## Novelty

- **codespell**: `transcripts/meta/novelty-codespell.txt` (51 terms, controls green).
  No issue describing a crash leaving a file empty. The hits under `crash`,
  `truncate`, `corrupt` are unrelated (a pre-commit interaction, dictionary
  requests).
- **rubocop**: `transcripts/meta/novelty-rubocop.txt`. `crash` and `empty` saturate
  the page limit, but every hit reads as a cop raising an exception while inspecting
  a file, not as a file lost while being rewritten. The `atomic` hits are
  `Lint/NonAtomicFileOperation` — a cop rubocop ships to warn about non-atomic file
  operations *in the code it inspects*, while its own `--autocorrect` writes the way
  this run measured.
- The other five are the shape already on this project's own record, filed five
  times; novelty is not the question for them.

## Reporting

Whether anything here goes upstream is the owner's call, made per run
(`spike/dogfood/README.md`). The material for it is the five-filing table above:
same shape, three explicit declines, one silence. This run's own reading is that
only codespell and rubocop carry a property the declined reports did not — no
alternative output path — and that the other five are the same request that was
already answered.

**Decision (owner, 2026-09-16): file codespell and rubocop, and nothing else.**
[codespell-project/codespell#4025](https://github.com/codespell-project/codespell/issues/4025) and
[rubocop/rubocop#15720](https://github.com/rubocop/rubocop/issues/15720), texts at
`report-codespell.md` and `report-rubocop.md`, both approved verbatim before filing. Both carry
the `ulimit -f 0` reproduction, which shows the window without a crash and without this project's
engine — the shape `oxipng#873` used. The other six are recorded here and in
`docs/target-classes.md`, and not filed: composer, vips, tesseract, pandoc and uutils `cp` can all
be told to write somewhere else, which is the answer the declined reports already got, and
pre-commit loses no content.
