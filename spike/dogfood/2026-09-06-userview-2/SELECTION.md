# 2026-09-06 — selection

The brief was the same as 2026-09-05's: use Sideeye the way a user would, on
Linux in Docker, four targets picked by the selection rules
(`spike/cohort4/SCOUT-BRIEF.md`, rules 1–17). This run follows the ordering rule
the previous one bought — **measure linkage and threads before writing the
candidate table** — and it held: three of the four screened candidates that
survived reached the engine, and the two Go candidates that would have cost image
builds were dropped in minutes.

All repository metadata was measured with `gh api repos/<repo>` and
`gh api repos/<repo>/commits?since=<6 months ago>` on 2026-09-06. `100` in the
commit column means the query hit the API's 100-row page limit: a floor, not a
count.

## What was excluded before any candidate was measured

Checked against every record this repository keeps of what it has already
touched: `docs/target-classes.md`, `spike/unknown-rate/b-exclusions.txt`,
`spike/blind-hunt3/candidates.md`'s taint ledger, and the two rejection tables of
`spike/dogfood/2026-09-05-userview/SELECTION.md`.

| Class | Names |
|---|---|
| Verdicts or walls on record | timewarrior, taskwarrior, calcurse, devtodo, abook, todoman, topydo, khal, buku, GNU Stow, Mercurial, Borg, black, rustfmt, poetry, papis, himalaya, mogrify, qpdf, exiv2, rdiff-backup, trash-cli, watson, pass, git, Jujutsu, chezmoi, gopass, Bun, joplin, beets, cargo, KeePassXC, unison |
| Taint ledger / b-exclusions | jrnl, omamori, khard, stow, hledger (sealed — do not scout) |
| Rejected by the previous run | ledger, rbw, exiftool, direnv, dotbot, mise, uv, pdm, pipenv, mackup, yazi, nnn, ranger, glow, restic, rclone, syncthing, fdupes, irssi, rsnapshot, fclones, cmus, espanso, navi, optipng, rsync, newsboat, oxipng, weechat |
| Being measured elsewhere the same day | ImageMagick (`mogrify`, `magick`, `convert`) — `spike/dogfood/2026-09-06-imagemagick-refix/` |

## Metadata screen (rules 1, 2, 3, 12)

| Candidate | repo | ★ | Lang | 6-month commits | authors | Verdict |
|---|---|---|---|---|---|---|
| metaflac | xiph/flac | 2,410 | C | 7 | 6 | passes |
| mid3v2 | quodlibet/mutagen | 1,955 | Python | 24 | 8 | passes |
| fontforge | fontforge/fontforge | 7,933 | C | 41 | 14 | passes |
| mutool | ArtifexSoftware/mupdf | 2,945 | C | 100 | 7 | passes |
| ocrmypdf | ocrmypdf/OCRmyPDF | 34,679 | Python | 100 | 7 | passes |
| sqlfluff | sqlfluff/sqlfluff | 9,865 | Python | 100 | 43 | passes |
| mlr | johnkerl/miller | 10,010 | Go | 100 | 4 | passes |
| shfmt | mvdan/sh | 9,040 | Go | 100 | 6 | passes |
| yq | mikefarah/yq | 15,923 | Go | 100 | 19 | passes |
| dasel | TomWright/dasel | 8,028 | Go | 76 | 6 | passes |
| sops | getsops/sops | 23,031 | Go | 100 | 7 | passes |
| ruff | astral-sh/ruff | 49,504 | Rust | 100 | 23 | passes |
| taplo | tamasfe/taplo | 2,384 | Rust | 8 | 5 | passes |
| vdirsyncer | pimutils/vdirsyncer | 1,872 | Python | 18 | 3 | passes here, fails rule 11 below |
| beancount | beancount/beancount | 5,973 | Python | 26 | 6 | passes |
| MP4Box | gpac/gpac | 3,299 | C | 100 | 14 | passes here, no install path below |
| picard | metabrainz/picard | 5,170 | Python | 100 | 8 | **rule 4** — GUI is the primary interface |
| yq (jq wrapper) | kislyuk/yq | 2,975 | Python | 19 | **2** | **rule 3** — the dotbot reading of the previous run |
| borgmatic | borgmatic-collective/borgmatic | 2,318 | Python | 100 | **1** | **rule 3** |
| rmlint | sahib/rmlint | 2,418 | C | **1** | **1** | **rules 2, 3** |
| sd | chmln/sd | 7,344 | Rust | **0** | 0 | **rule 2** |
| gifsicle | kohler/gifsicle | 4,313 | C | **0** | 0 | **rule 2** |
| yadm | TheLocehiliosan/yadm | 6,412 | Python | **0** | 0 | **rule 2** |
| jpegoptim | tjko/jpegoptim | 1,810 | C | **0** | 0 | **rule 2** |
| crudini | pixelb/crudini | **491** | Python | 0 | 0 | **rules 1, 2** |
| augeas | hercules-team/augeas | **529** | — | 4 | 3 | **rule 1** |
| par2cmdline | Parchive/par2cmdline | **922** | C++ | 100 | 4 | **rule 1** |
| kid3 | KDE/kid3 | **193** | C++ | 100 | 3 | **rule 1** (GitHub is a mirror; this is the number rule 1 can read) |
| mkvpropedit | mkvtoolnix | — | C++ | — | — | **rule 1** — no GitHub repository (GitLab). The `optipng` reason |
| tiffset | libtiff | — | C | — | — | **rule 1** — same |
| mbsync | isync | — | C | — | — | **rule 1** — same (SourceForge; the GitHub hits are forks at 34★ and below) |

## The measured screen, before the candidate table (rule 10)

Every metadata survivor that had an install path was run once inside the image
and measured for the two walls that ended the 2026-09-05 slate 1: `file -L` for
linkage, `strace -f -e trace=clone,clone3` on **a real writing operation** for
threads. Transcripts: `apparatus/screen.sh`, `screen2.sh`, `screen3.sh`,
`screen4.sh`.

| Candidate | Linkage | Threads | Children | Taken |
|---|---|---|---|---|
| **metaflac** | dynamic | **0** | 0 | ✅ |
| **mid3v2** | script → `python3` | **0** | 0 | ✅ |
| **fontforge** | dynamic | **0** | 0 | ✅ |
| **mutool** | dynamic | **0** | 0 | ✅ |
| mlr | dynamic | **6** | — | no |
| shfmt | **static** | 4 | — | no |
| dasel | **static** | 5 | — | no — the only Linux artifact the project publishes |
| ocrmypdf | script → `python3` | 0 | **execve 31, clone 12** before the operation began | no |
| vdirsyncer | script → `python3` | 0 | 0 | no — rule 11 below |
| sqlfluff | — | — | — | no — pip only, and `pypi.org` is unreachable from this machine (`CERTIFICATE_VERIFY_FAILED`, self-signed in chain). The same TLS-intercepting proxy the 2026-09-05 run hit through `node-gyp` |
| MP4Box | — | — | — | no — `gpac` has no installation candidate in Debian trixie. The `weechat-headless` reason |

Two screening results that reading would not have produced:

- **`mid3v2` starts no thread.** The 2026-09-05 run measured `beet ls` — a
  read-only command — tripping `multiple_threads_detected`, and recorded that
  "Python is not a safe class on its own". Generalising that the other way would
  have dropped the one candidate in this slate that reached a verdict.
- **Go is three for three.** `mlr` threads, `shfmt` and `dasel` are static *and*
  thread. Consistent with chezmoi and gopass, and it cost minutes rather than
  image builds.

## Rule 11, measured on bug reports (rules 11, 17)

Measured with `apparatus/rule11-github.py`, which takes the most recent issues,
skips pull requests, and times the first comment **from somebody other than the
reporter**. mupdf needed a second instrument: its GitHub repo has
`has_issues=false` and its README names `bugs.ghostscript.com`, so
`apparatus/rule11-bugzilla.py` reads that tracker's REST API instead.

| Candidate | Receipts | Reading |
|---|---|---|
| **fontforge** | #5886 0.1d, #5885 0.1d, #5878 0.1d (heap-buffer-overflow), #5876 0.0d (use-after-free), #5874 0.2d | passes, strongly. The three newest issues have no reply and are 1–10 days old |
| **mutool** | Bugzilla 709680 2.0d, 709678 3.1d, 709674 5.3d | passes |
| **metaflac** | #928 2.9d, #923 0.1d | passes. #929 and #925 sit at zero |
| **mid3v2** | #721 0.0d, #720 3.7d | passes. #714 answered after 21.5d, and its reporter is a maintainer |
| vdirsyncer | #1216 0.0d, #1214 0.1d, #1210 0.1d, #1224 5.6d, #1218 34.2d | **fails 17.** Every fast reply is on documentation, a feature request, or a version question; #1224 is "Time for a new release?". No bug report with a measured response was found in the 60 most recent issues |
| ocrmypdf | #1727 0.0d, #1741 0.5d, #1726 0.6d, #1715 19.4d | passes — but the child wall above had already removed it |

One measurement was wrong before it was right, and the correction is the reason
the Bugzilla instrument exists: the first query filtered with
`f1=creation_time&o1=greaterthan&v1=…` and returned **0 bugs**, which reads
identically to "this project gets no bug reports". The filter was not applied.
Fetching the product unfiltered and sorting locally shows five reports between
2026-08-26 and 2026-09-04. A zero from a filter nobody falsified is not a zero.

## The slate

| # | Target | Language | The single operation measured |
|---|---|---|---|
| 1 | metaflac (flac 1.5.0) | C | `metaflac --set-tag=ARTIST=probe a.flac b.flac c.flac` |
| 2 | mid3v2 (mutagen) | Python | `mid3v2 -a probe a.mp3 b.mp3 c.mp3` |
| 3 | fontforge 20230101 | C | `fontforge -lang=ff -c Open(f.ttf);Generate(f.ttf);` |
| 4 | mutool (mupdf) | C | `mutool clean a.pdf a.pdf` |

Language diversity (rule 13): C 3, Python 1 — not a single-language slate.

The fourth slot was an owner decision. Three candidates satisfied every rule;
the remaining choices were "a target whose class is already measured" or "relax
one rule". The owner picked mupdf, which satisfies every rule and whose class
(PDF) the 2026-09-05 run already reached through qpdf — so the slate carries a
same-target-different-implementation comparison rather than a new class.

**Write paths, measured before any define existed.** This is what made the slate
worth running: four tools, four mechanisms, and not one of them keeps a copy.

| Target | Write path | What a crash leaves |
|---|---|---|
| metaflac | `openat(O_RDWR)` alone; 20 bytes changed inside the padding block, file size unchanged | the file, possibly with a torn padding block |
| mid3v2 | `openat(O_RDWR)` alone; size changes | the file, ID3 partly written |
| fontforge | `openat(O_RDWR\|O_CREAT\|O_TRUNC)` | a zero-byte font — the exiv2 shape |
| mutool | `unlinkat` **then** `openat(O_CREAT\|O_EXCL\|O_TRUNC)` | **nothing at that name** |

mutool's is the sharper form of the qpdf window this project reported: qpdf
renames the original aside and a crash leaves it recoverable at
`.~qpdf-orig#`, while mutool removes it first and there is nothing to recover.
Whether that is reachable is what the run set out to measure.
