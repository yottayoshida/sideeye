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
| sqlfluff | — | — | — | **this row is wrong — see slate 2's correction below.** What was written: pip only, and `pypi.org` is unreachable from this machine (`CERTIFICATE_VERIFY_FAILED`, self-signed in chain). The same TLS-intercepting proxy the 2026-09-05 run hit through `node-gyp` |
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

---

# Slate 2 — same day, four more, and a correction to slate 1

The owner asked for four more after slate 1 closed. Slate 1 had ended with one
verdict and three walls, two of which were the same wall — **stdio writes that
overflow the buffer** — so slate 2's screen carries a third axis on top of
linkage and threads: **does the tool's write go through `FILE*` or through raw
`open`/`write`?** Measured the same way, before the candidate table.

## A correction to slate 1's rejection table

Slate 1 rejected **sqlfluff** with "pip only, and `pypi.org` is unreachable from
this machine". The first half is false: `apt-cache policy sqlfluff` in Debian
trixie returns **3.3.1-1**. The pip attempt failed and the conclusion drawn from
it was about the wrong thing — the package was one `apt-get install` away. It is
in slate 2's screen below, where it fails on threads instead. The rejection was
right by accident, which is the worst kind.

## Metadata screen (rules 1, 2, 3, 12)

| Candidate | repo | ★ | Lang | 6-month commits | authors | Verdict |
|---|---|---|---|---|---|---|
| fonttools | fonttools/fonttools | 5,231 | Python | 100 | 13 | passes |
| bsdtar | libarchive/libarchive | 3,608 | C | 100 | 12 | passes |
| bean-format | beancount/beancount | 5,973 | Python | 26 | 6 | passes; `bean-format -o FILENAME` satisfies rule 8 |
| sqlfluff | sqlfluff/sqlfluff | 9,865 | Python | 100 | 43 | passes here, threads below |
| libvips | libvips/libvips | 11,628 | C | 100 | 15 | passes here, threads below |
| zstd | facebook/zstd | 27,711 | C | 57 | 8 | passes here, threads below |
| ansible | ansible/ansible | 70,592 | Python | 100 | 30 | passes here, threads + children below |
| bundler | rubygems/rubygems | 3,964 | Ruby | 100 | 6 | passes here, threads below |
| git-annex | (Debian `git-annex`) | — | Haskell | — | — | screened for the language record; threads + children below |
| certbot | certbot/certbot | 33,233 | Python | 75 | 14 | **not screened** — its state is certificates and renewing them needs an ACME server; out of scope for a local run |
| csvkit | wireservice/csvkit | 6,411 | Python | 21 | 6 | **rule 8** — `csvformat` and friends write to stdout; there is no in-place mutation |
| asciidoctor | asciidoctor/asciidoctor | 5,212 | Ruby | 10 | 3 | **rule 8** — generates output beside the input |
| offlineimap3 | OfflineIMAP/offlineimap3 | **633** | Python | 56 | 7 | **rule 1** |
| pngquant | kornelski/pngquant | 5,747 | C | **4** | **2** | **rules 2, 3** — the dotbot reading |
| ruff | astral-sh/ruff | 49,504 | Rust | 100 | 23 | **no install path** — not packaged in Debian trixie |
| xmlstarlet | — | **28** | C | — | — | **rule 1** — the GitHub repositories are forks; upstream is SourceForge |
| vdirsyncer | pimutils/vdirsyncer | 1,872 | Python | 18 | 3 | **rule 17**, re-measured — see below |

### vdirsyncer, measured a second time

Slate 1 rejected it on rule 17 after 60 issues. Re-measured over 100, filtering
to issues whose title or labels name a bug:

| Issue | Created | First reply from someone else |
|---|---|---|
| #1225 | 2026-08-30 | none |
| #1222 | 2026-06-16 | none |
| #1212 | 2026-03-30 | none |
| #1208 | 2026-02-10 | 106.2d |
| #1202 | 2025-10-27 | 34.4d |
| #1191 | 2025-08-30 | 0.1d |
| #1188 | 2025-08-27 | 0.1d |

The three most recent bug reports have no reply at all, and the two before them
were answered after a month and after three. The only replies inside a week are
from August 2025, which is not "recent" in rule 11's sense. The rejection stands,
and now it stands on a measurement that looked for the opposite.

## The measured screen (rules 10 and, new here, the stdio axis)

`apparatus/screen6.sh`, `screen7.sh`, `screen8.sh`. Linkage with `file -L`,
threads with `strace -f -e trace=clone,clone3` on a real writing operation, and
the write sizes with `strace -f -e trace=write` — a run of writes at exactly 4096
bytes is the stdio buffer overflowing, which is the wall slate 1 hit.

| Candidate | Linkage | Threads | Children | Writes | Taken |
|---|---|---|---|---|---|
| **fonttools** | script → `python3` | **0** | 1 | 1 | ✅ |
| **bsdtar** | dynamic | **0** | 1 | 1 | ✅ |
| **bean-format** | script → `python3` | **0** | 1 | — | ✅ |
| sqlfluff | script → `python3` | **2** | — | 5, none at 4096 | no |
| libvips | dynamic | **8** | — | — | no — and `vips copy f.png f.png` left **a zero-byte file** and exited 1, which is a finding this run did not pursue |
| zstd | dynamic | **3** | — | — | no. Its write path is the safe order: create `f.zst`, then `unlink` the input |
| ansible | script → `python3` | **2** | **43 execve** | — | no |
| bundler | script → `ruby` | **2** | 3 | 3 | no |
| git-annex | dynamic | **12** | **113 execve** | 76 | no |

Ruby and Haskell now have a linkage/thread measurement on record, which they did
not before; both refuse for the same reason as Go, one layer up.

## The slate

| # | Target | Language | The single operation measured |
|---|---|---|---|
| 1 | fonttools 4.57.0 | Python | `fonttools subset f.ttf --output-file=f.ttf --unicodes=U+0041-005A` |
| 2 | bsdtar (libarchive 3.7.4) | C | `bsdtar -uf a.tar -C src f3.txt` |
| 3 | bean-format (beancount 3.1.0) | Python | `bean-format -o l.beancount l.beancount` |

Three, not four. Every remaining candidate that satisfied rules 1–3 failed the
screen (threads, in every case), and the ones that passed the screen failed
rule 8 or had no install path. The slate is short and the rejection table above
is why; a fourth taken on a relaxed rule would have been a different kind of
record.
