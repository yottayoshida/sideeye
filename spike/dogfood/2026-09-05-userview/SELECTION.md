# 2026-09-05 — selection, both slates

The brief was: use Sideeye the way a user would, on Linux in Docker, picking
targets by the selection rules, four at a time. Two slates were selected that
day. The first was chosen by reading and forecasting; it reached no verdict. The
second was chosen after screening candidates by measurement; every target
reached one. Both are recorded, because the difference between them is the
finding.

All repository metadata below was measured with `gh api repos/<repo>` and
`gh api repos/<repo>/commits?since=<6 months ago>` on 2026-09-05. `100+` means
the commit query hit the API's 100-row page limit: it is a floor, not a count.

## What was excluded before either slate

Not candidates. These were checked against every record this repository keeps
of what it has already touched — `docs/target-classes.md`,
`spike/unknown-rate/b-exclusions.txt`, `spike/blind-hunt3/candidates.md`'s taint
ledger, and `BUILDLOG.md`.

| Tool | Why it is not a candidate |
|---|---|
| **jrnl** | Measured twice already: **rejected 2026-08-12** after `strace` showed a whole-journal write to an `O_EXCL` temp followed by one rename (BUILDLOG), and then run as the onboarding clock's target, **PASS 4/4** (`spike/onboarding-clock/`). On the taint ledger. |
| **neomutt**, **calcure** | Reached cohort 4's slate and were set aside by owner ruling (`spike/cohort4/SCOUT-ROWS-SLOT2.md`). neomutt's status turns on the rule-9 reading recorded in `spike/cohort4/CANDIDATES-REJECTED.md`, which is a freeze-text decision rather than a probe. |
| **hledger** | Sealed, unread. Do not scout (`spike/README.md`). |
| Everything in `b-exclusions.txt` | topydo, abook, khal, buku, calcurse, devtodo, stow, timewarrior, todoman, watson, pass, taskwarrior, git, omamori, khard. |

**This check was done wrong the first time and the mistake is the reason it is
written out here.** The first pass grepped only this repository, found `qpdf`
absent, and called it fresh. It is fresh *here* — and it is in production in four
of the owner's work repositories, and the owner had filed
[qpdf#1773](https://github.com/qpdf/qpdf/issues/1773) against it the previous
day, describing the same window this run then rediscovered. A freshness check
that reads one repository is not a freshness check.

## Slate 1 — chosen by forecast. Four targets, four walls, no verdict

| Target | ★ | Lang | 6-month activity | Wall forecast | What actually happened |
|---|---|---|---|---|---|
| **chezmoi** | 21,464 | Go | 100+ commits / 5 authors / v2.72.1 | static linkage possible (#390's `gh` row) | `no_shim_marker` — **tarball and `.deb` both static**, and no Debian package exists |
| **gopass** | 7,120 | Go | 100+ / 12 / v1.17.0 | static, plus gpg/git children (`pass`, #123) | `no_shim_marker`, same. The child-process wall was never reached |
| **beets** | 15,619 | Python | 100+ / 9 / v2.13.1 | none — Python has many verdicts on record | `multiple_threads_detected`, **including on read-only `beet ls`** |
| **joplin** | 56,240 | TS/Node | 100+ / 9 / v3.6.16 | thread refusal (libuv), labelled a prediction in `docs/target-classes.md` | `multiple_threads_detected` — the prediction, measured |

Three of the four forecasts were right and it did not help: a forecast that is
right still costs an image build and a preflight to confirm. The fourth (beets)
was wrong in the direction that matters — it predicted no wall.

### Rejected before slate 1

| Target | ★ | Rule it failed | Measured |
|---|---|---|---|
| ledger | 6,026 | 8 — no writing command | README: *"there is no other database or stored state"* |
| rbw | 1,469 | 2 | 0 commits in 6 months |
| exiftool | 5,006 | 3 | 1 author in 6 months (GitHub side may be a mirror) |
| direnv | 15,418 | 2 | 3 commits |
| dotbot | 7,998 | 2, 3 | 9 commits / 2 authors |
| mise, uv | 33,487 | 5 | installed toolchains are re-downloadable — the `bob`/`proto` reason cohort 4 recorded |
| pdm, pipenv | 8,672 / 25,032 | copy question | manifests live in the user's version control — poetry's reason (`spike/README.md`) |
| mackup | 15,320 | 14 | symlink management: the `stow` shape, already measured and reported |
| yazi, nnn, ranger, glow | 41,944 / 21,860 / 17,388 / 27,191 | 5 (judgement) | state is bookmarks and history; not read further |
| beets, joplin, restic, rclone, syncthing | — | 7 (judgement) | SQLite or a repository format suspected; **not verified** — beets and joplin were taken anyway, on the "measure the wall" instruction |

## Slate 2 — chosen by screening. Eight screened, four taken, four verdicts

Before any candidate table was written, every survivor of the metadata rules was
run once inside the image and measured for the two walls that ended slate 1:
`file` for linkage, `strace -f -e trace=clone,clone3` on **a real writing
operation** for threads. Transcript: `apparatus/screen.sh`, `apparatus/screen2.sh`.

| Candidate | ★ | Lang | Linkage | Threads | Children | Taken |
|---|---|---|---|---|---|---|
| **mogrify** (ImageMagick) | 17,336 | C | dynamic | **0** | 0 | ✅ |
| **qpdf** | 5,381 | C++ | dynamic | **0** | 0 | ✅ |
| **exiv2** | 1,158 | C++ | dynamic | **0** | 0 | ✅ |
| **rdiff-backup** | 1,265 | Python | dynamic | **0** | 1 | ✅ |
| rsync | 5,181 | C | dynamic | 0 | **2 (fork)** | no — child-process wall likely, and the slate was full |
| newsboat | 3,899 | C++ | dynamic | **2** | — | no |
| oxipng | 4,203 | Rust | dynamic | **11 default, 2 with `-t 1`** | — | no — `-t 1` sizes rayon's pool, it does not remove it |
| weechat | 3,374 | C | — | — | — | no — `weechat-headless` is not in Debian's `weechat` package |

The screen cost about twenty minutes and removed four candidates. Slate 1 spent
four image builds and eleven preflight runs to learn the same class of fact.

### Rejected before slate 2

| Target | ★ | Rule | Measured |
|---|---|---|---|
| fdupes | 3,009 | 2, 3 | 2 commits / 1 author |
| irssi | 3,134 | 2 | **0 commits** in 6 months |
| rsnapshot | 3,668 | 2, 3 | 1 commit / 1 author |
| fclones | 2,926 | 2 | 0 commits |
| cmus | 6,236 | 2 (borderline) | 7 commits / 4 authors — not screened, the slate filled first |
| espanso, navi | 14,426 / 17,508 | — | not in Debian; release binaries not screened, the slate filled first |
| optipng | — | 1 | no GitHub repository to measure stars against (SourceForge) |

Every taken candidate was also checked for prior contact in this repository
(zero hits for all four, by `git grep -liw`) and, for the two eventually
reported, against the owner's own filed issues.
