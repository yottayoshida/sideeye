# Cohort 4 — rejected candidates, and the correction to the funnel

The brief (`SCOUT-BRIEF.md`) requires the rejections to be shown to the
owner beside the survivors: *"a slate with no visible rejections is
indistinguishable from a slate chosen by taste."* This is that table. It is
committed rather than left in a scratch directory because it is the
evidence half of a selection, and the owner asked for it after auditing the
funnel below and finding it thin.

**Second and third passes, 2026-08-22 (owner instruction): every rejection
whose basis was an unverified description line was re-judged against primary
sources, and the rows left resting on a judgment were then read from source
code.**
Six rows were re-opened. Two had their stated rule replaced, one was
weakened to uncertain, three were upheld with the basis upgraded from
recall to measurement. The re-judgments are in §"Second pass" below and are
also written into the affected rows. Nothing was executed: READMEs, man
pages, manifests and lockfiles only.

## The correction first

**The funnel I sent was wrong in two places, and the ~89 derived from it is a consequence of my numbers, not an error in the arithmetic.**

Recounted from `pool.tsv`, the file the enumeration actually wrote:

| What I sent | What the file says |
|---|---|
| Pool (a) = 163 rows | 163 rows, **159 unique repos** (4 repos matched two topics) |
| Language wall forecast: **64** out, **~50** left | **128** out, **31** left. The 64 was Go + TypeScript + JavaScript only; I never added Shell 17, PHP 10, Java 7, Swift 5, Kotlin 4, C# 4, Nix 3, HTML 3, QML 2, Objective-C 2, Lua 2, CMake 2, Vue 1, Vala 1, C++ (kept) and 3 blank-language rows. The "~50 left" was not counted at all — it was written to make the column continue |
| Rule 4/5/7 read: **12** left | **Not a measured stage.** There is no per-row reading log, because the reading was not done per row |

So the honest shape of that stage is: **31 in, 22 rejected, 2 set aside, 3 left as unread candidates, 4 already measured** — not 89 dropped.

**And the basis is weaker than the word "read" implies.** For all 31 rows below, the judgment came from the search result's own `description` field plus my prior knowledge of the tool. **I fetched nothing for any of them.** The five candidates whose READMEs I did fetch (trash-cli, vdirsyncer, pipx, unison, himalaya) came from the recall list, not from this pool. Where prior knowledge is doing the work, the row says so, because for several of these it is knowledge that has not been checked against the current version.

## The 31, one row each

Sorted as the enumeration returned them. "Basis" is what the judgment actually rests on.

| Repo | ★ | Lang | Verdict | Rule | Basis |
|---|---|---|---|---|---|
| sansan0/TrendRadar | 61,656 | Python | reject | 4 | **measured, second pass**: the README leads with a hosted site and webhook badges |
| huginn/huginn | 49,833 | Ruby | reject | 4 — Rails web application ("Create agents that monitor and act on your behalf") | description |
| Homebrew/brew | 49,232 | Ruby | **set aside, no rule cited** | — | judgment: taps are git repos and the Cellar is large; the probe cost looked high. This is a cost call, not a rule failure, and it should be revisited if slots stay open |
| pnpm/pnpm | 36,173 | Rust (top language) | reject | 16 — the shipped CLI is Node | **measured, second pass**: README calls the Rust port (pacquet) experimental; see §Second pass |
| python-poetry/poetry | 34,288 | Python | already measured | — | cohort 3 record |
| dgtlmoon/changedetection.io | 33,284 | Python | reject | 4 — self-hosted web service | description |
| ArchiveBox/ArchiveBox | 28,157 | Python | reject | ~~7~~ → **4 and 16** | **re-judged, second pass**: the store is files, SQLite is the index; the archiving is done by child processes. See §Second pass |
| microsoft/winget-cli | 26,333 | C++ | reject | out of platform scope — Windows | description |
| timqian/chinese-independent-blogs | 23,840 | Python | reject | 4 and 5 — a curated list, not a tool | description |
| NixOS/nix | 17,549 | C++ | reject | 7 — own store plus a SQLite database | prior knowledge |
| rust-lang/cargo | 15,408 | Rust | already measured | — | cohort 3 record (wall) |
| mail-in-a-box/mailinabox | 15,392 | Python | reject | 4 — server provisioning | description |
| CocoaPods/CocoaPods | 14,834 | Ruby | **set aside, no rule cited** | — | needs an Xcode-shaped environment; probe cost. Same status as brew |
| astral-sh/rye | 14,167 | Rust | reject | 2 and 12 — pushed 2026-02-05 and superseded by uv | pushed date **measured**; superseded status is prior knowledge |
| megadose/holehe | 13,948 | Python | reject | 2 (pushed 2024-09-10) and 5 (no local store) | pushed date measured; state claim from description |
| sissbruecker/linkding | 11,085 | Python | reject | 4 — self-hosted web app | description |
| smacke/ffsubsync | 7,849 | Python | reject | 5 | **measured, second pass**: a CLI exists; what fails is rule 5 — its output is derived from its inputs |
| samuelclay/NewsBlur | 7,593 | Python | reject | 4 — web reader | description |
| jarun/buku | 7,179 | Python | already measured, and 7 | — | cohort 1 record; withdrawn as a bug claim because a journalled DB's mid-transaction state is what its journal is for |
| yadm-dev/yadm | 6,394 | sh (GitHub says Python: the tests) | reject | 16 | **third pass, measured**: `yadm` is a `#!/bin/sh` script re-execing under bash; state mutations run in git child processes — the `pass` wall (#123) |
| GothenburgBitFactory/taskwarrior | 6,014 | C++ | already measured | — | PASS 12/12 record |
| stringer-rss/stringer | 4,126 | Ruby | reject | 4 — self-hosted web reader | description |
| neomutt/neomutt | 3,814 | C | **returned to the pool** | ~~8~~ — overturned; rule 4 open as a judgment | **third pass**: batch mode does Fcc (send.c), and the maildir write is libc `open` + `rename`, no mkstemp. See §Third pass |
| martinrotter/rssguard | 2,720 | C++ | reject | 4 — GUI | description |
| anufrievroman/calcure | 2,338 | Python | **no longer rejected** | ~~8~~ — overturned | **third pass**: `--task` and `--event` add and exit. Ranked low on a measured forecast (atomic `Path.replace`, no loss window) — see §Third pass |
| MordechaiHadad/bob | 2,138 | Rust | reject | 5 | **third pass**: the state is downloaded toolchains, which are re-downloadable |
| Rongronggg9/RSS-to-Telegram-Bot | 2,137 | Python | reject | 4 and 5 — a bot service | description |
| GitGuardian/ggshield | 1,991 | Python | reject | 5 — a scanner, no primary store | description |
| OfflineIMAP/offlineimap | 1,859 | Python | reject | 2 and 12 — pushed 2023-06-13, description says "[LEGACY" | pushed date measured; description |
| moonrepo/proto | 1,396 | Rust | reject | 5 | **third pass**: same shape as bob; its user-authored `.prototools` is the only primary-data part, worth a second look only if slots stay empty |
| mongodb/kingfisher | 1,206 | Rust | reject | 5 — a secrets scanner | description |

## What the first pass did not contain, said plainly (superseded in part by the second)

- **No project was read in the first pass.** Rules 4, 5, 7 and 8 were judged from one description line and, for eight rows, from prior knowledge that was not re-checked. The brief says a candidate row missing a measurement is an incomplete row; by that standard every row was incomplete. **The second pass fixed six of them** — the four that were marked "unverified" plus two whose description could have been wrong in a way that changed the answer. The remaining rows still rest on a description line; they are the obvious ones (Rails apps, GUIs, a curated list, a Windows-only tool, and three whose `pushed` dates measured out on rule 2).
- ~~**Three rejections I would re-examine first**~~ — **done in the second pass**: `pnpm` upheld on its own README, `neomutt`'s rule 8 withdrawn, `ArchiveBox`'s rule 7 withdrawn. Details below.
- **Two rows were set aside with no rule at all** — brew and CocoaPods, on probe cost. That is a judgment the owner may want to reverse, and it is not a rule the brief authorises.
- **Three unread candidates remain in the pool**: yadm, bob, proto. yadm carries a `child_touched_state_dir` forecast.


## Second pass — the six re-judgments, against primary sources

Read 2026-08-22. Sources named per row; no target was run.

### pnpm — **upheld, basis upgraded**

Read: pnpm/pnpm repo tree, `Cargo.toml`, `README.md`, and the language
byte counts (Rust 18,549,988 / TypeScript 10,132,487).

The Rust workspace is real — `Cargo.toml`, `rust-toolchain.toml`,
`deny.toml`, `dylint.toml`, members under pnpm/crates/* — so the "top
language: Rust" that made me doubt the rejection is not an artifact. But
the README settles what ships: **"Experimental Rust port. Includes
[pacquet](./pnpm), an experimental port of the CLI written in Rust."** The
CLI users run is still the TypeScript/Node one, so the libuv-thread
forecast applies to the thing rule 12 says to measure. Rejection stands,
now on the project's own sentence instead of my recollection.

### neomutt — **rule 8 withdrawn; rejection now rests on rule 4, and is a judgment**

Read: docs/neomutt.man from neomutt/neomutt.

My basis was wrong. **"Batch mode" is a first-class mode in neomutt's own
man page** (listed among the modes at line 255), `-e/--command` runs a
command after the config is read, and `-H/--draft` accepts a full RFC822
message on stdin with the note that *"draft files are processed the same in
interactive and batch mode"*. Non-interactive paths exist, so **rule 8 does
not fail.**

What remains is rule 4 — the primary interface is an interactive TUI and
batch mode is a secondary send path — and that is a judgment about the word
"primary", not a measured rule failure. Recorded as such so the owner can
overturn it. Two further things a slot decision would need: whether the
optional header cache (tokyocabinet/lmdb/bdb) counts against rule 7 when it
is a cache rather than the store, and whether a batch send with a local
`record` writes into the judged maildir non-interactively — the second is
the interesting question and it is unanswered here.

### ArchiveBox — **rule 7 withdrawn; upheld on rule 4 and rule 16**

Read: `README.md` from ArchiveBox/ArchiveBox.

My basis was wrong. The primary data is **files**: the README documents
data/archive/{Snapshot.id}/ holding `index.html`, `index.json`,
`singlefile.html`, a wget clone with warc/TIMESTAMP.gz, a DOM dump. And
`index.sqlite3` is described by the project as *"your index"* —
`sqlite3 ./index.sqlite3 # run SQL queries directly on your index`. Under
rule 7's wording ("SQLite … is **not** the main store") ArchiveBox passes.

It is still rejected, on two measured grounds instead:

- **Rule 4** — the README lists five interfaces and puts the browser
  extension first: *"you can interact with it through the: Browser
  Extension, CLI, self-hosted web interface, Python API, or filesystem."*
- **Rule 16** — the archiving is performed by **child processes**: the
  README names Chrome, `wget` and `yt-dlp` as the tools that produce the
  files. That is `child_touched_state_dir`, the `pass` wall (#123), and it
  is the stronger objection of the two.

### TrendRadar — **upheld, basis upgraded**

Read: `README.md` from sansan0/TrendRadar. The page leads with a hosted
website and a row of webhook badges; the product is a monitoring service
that pushes notifications. Rule 4 stands on the project's own framing.

### calcure — **weakened to uncertain**

Read: `README.md` from anufrievroman/calcure, Usage section.

My basis (rule 8, interactive-only) is **not proven**: the README says
*"Various user arguments can be added started in special mods add tasks and
events"*, which points at an argument-driven mutation path documented on an
external wiki page this pass did not open. Its own one-liner — *"Modern TUI
calendar and task manager"* — makes rule 4 the more likely objection, the
same shape as neomutt.

**Status: rejected on rule 4 as a judgment, with rule 8 unresolved.** If
slots stay open this is a cheap row to finish: one wiki page settles it.

### ffsubsync — **upheld, basis upgraded**

Read: `README.md` from smacke/ffsubsync. There *is* a CLI — *"For bulk or
scripted use, install the command-line tool below"* — so rule 4 is fine.
Rule 5 is what fails: the tool synchronises subtitle files against a video
or reference, and its output is derived from its inputs. Nothing it keeps
is primary data a user would lose. Measured from the project's own
description of what it does rather than from the search result's summary.

## What the second pass changed, counted

- **Bases replaced: 2** (neomutt rule 8 → rule 4; ArchiveBox rule 7 →
  rules 4 + 16).
- **Weakened to uncertain: 1** (calcure).
- **Upheld with the basis upgraded from recall to measurement: 3** (pnpm,
  TrendRadar, ffsubsync).
- **Returned to the candidate pool: 0.** No rejection was fully overturned
  — but two now stand on a judgment about the word "primary" rather than on
  a rule a measurement can settle, and the owner should see that
  difference.
- **Still unread from the original pool: 3** (yadm, bob, proto) plus the
  two set aside on cost (brew, CocoaPods), which the owner has kept out of
  scope for this pass.


## Third pass — the two judgment rows and the three unread, read from source

Owner instruction after the second pass: finish the rows that were left
resting on a judgment, and read the three unread candidates. Reading only;
sources named per row.

### neomutt — **returns to the pool, and is the strongest row this pass produced**

Two questions were open after the second pass. Both are now answered from
the source, and both answer favourably.

- **Does batch mode mutate the judged maildir?** Yes. send/send.c carries
  the branch `if (rc && (flags & SEND_BATCH))` under the comment *"Printed
  when an Fcc in batch mode fails."* Fcc runs in batch mode, so with
  `record` pointed at a local maildir a non-interactive invocation writes
  into the state root. Rule 8 passes on the code, not on the man page alone.
- **Is the write path visible to an interposer?** Yes, and this is the
  question the mkstemp measurement (#39) made cheap to ask of any C
  candidate. maildir/message.c opens the temp file with
  `fd = open(path, O_WRONLY | O_EXCL | O_CREAT, 0666)` and moves it with
  `rename(oldpath, fullpath)` — plain libc calls, no `mkstemp`, no raw
  syscalls. Rule 16's forecast is favourable.

What remains, and it is not small: **rule 4** — the primary interface is an
interactive TUI, which is the judgment this pass was asked to finish and
which it cannot settle by reading; and **rule 9** — no obvious
non-interactive read-back command, so a checker would read the maildir
directly rather than through the tool. Cohort 3's checkers used their
target's own commands.

What it brings that the current slate lacks: **C**. himalaya is Rust and
vdirsyncer is Python, so rule 13's language diversity currently rests on
two languages cohort 3 already measured.

### calcure — **rule 8 overturned, and the write shape then argues against the slot**

calcure/configuration.py defines `--task NAME` ("add a task and exit") and
`--event YYYY-MM-DD-name` ("add an event and exit"). Rule 8 passes
outright; the second pass's "unproven" was too generous to my own
rejection, which was simply wrong.

But calcure/savers.py settles what a slot would buy. The save writes every
row into `<file>.bak` and then calls `Path.replace()` onto the original — an
atomic rename, with no fsync and a fixed temp name inside the state root.
**There is no window in which the user's tasks are lost**: the original
stands until the replace. The forecast is therefore PASS, with L0 noise from
the `.bak` file appearing in the judged root — the `COMMIT_EDITMSG` shape
(#35). Storage is CSV (`csv` module, plain text), so rules 6 and 7 pass, and
rule 9 is weak for the same reason as neomutt's: no non-interactive
read-back.

**Status: no longer rejected, and ranked low on a measured forecast rather
than on a wrong rule.** That distinction is the point of this pass.

### yadm — **rejected on rule 16, measured**

GitHub reports the language as Python (the test suite); the tool itself is
`yadm`, a `#!/bin/sh` script that re-execs under bash. Its state mutations
are performed by **git child processes**, which is `child_touched_state_dir`
— the `pass` wall (#123, open). The forecast the first pass guessed is now
read from the file.

### bob, proto — **rejected on rule 5**

Both are version managers: the state is downloaded toolchains, which are
re-downloadable, so what they keep is not primary data a user would lose.
proto has one genuine primary-data file (a user-authored `.prototools`),
which is the only part worth a second look if slots stay open. Both also
need the network to install, so a probe would need offline fixtures — a cost
note, not a rule.

## The slate after three passes

| # | Candidate | Language | Axis | State |
|---|---|---|---|---|
| 1 | himalaya | Rust | A (maildir) | clean; **cost**: the distribution is musl-static, so the measured binary must be a self-build, and the freeze has to say so |
| 2 | vdirsyncer | Python | A + C (status ↔ vdir, `repair`) | clean; rule 11 borderline (comment counts only), and condition 9 is a gate — a count of 1 means no slot |
| 3 | **neomutt** | **C** | A (maildir) | write path measured visible; **rule 4 is a judgment** and rule 9 needs a checker that does not use the tool |
| 4 | — | — | — | empty |
| 5 | — | — | — | empty |
| bench | — | — | — | empty |

Two of five primary slots remain empty, and the bench is empty. The
population argument in the first pass has not changed: 128 of 159 enumerated
repositories were excluded by language wall forecast, and the two walls
doing that work (#201 static linkage, #202 threads) are both scheduled
after v1.0.

## Why the funnel came out wrong

The table was assembled after the work rather than during it, and the columns were filled to be continuous rather than counted. Two of its four numbers were arithmetic I did not do. The register in `spike/cohort4/PREP.md` lists this defect — claims written from memory rather than from an open source — as row E4, and the check it prescribes (grep the diff for digits, open the primary source for each) is a check on *diffs*, which a chat message is not. That gap is real: the message was not a commit, so nothing made me re-derive the numbers before sending them.

## A note on how references are written here

Repository names and paths that live inside *other* projects are written
without backticks, because acceptance check 11 extracts every backticked
token containing a slash from the pages it guards and requires it to resolve
in this repository. Upstream issue references survive backticks only because
the check excludes tokens containing `#`. This page is not on check 11's
list today; written this way it stays safe if it is ever added, and it
matches how `docs/target-classes.md` already writes its upstream references.
