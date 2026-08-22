# Cohort 4 — rejected candidates, and the correction to the funnel

The brief (`SCOUT-BRIEF.md`) requires the rejections to be shown to the
owner beside the survivors: *"a slate with no visible rejections is
indistinguishable from a slate chosen by taste."* This is that table. It is
committed rather than left in a scratch directory because it is the
evidence half of a selection, and the owner asked for it after auditing the
funnel below and finding it thin.

**Second pass, 2026-08-22 (owner instruction): every rejection whose basis
was an unverified description line was re-judged against primary sources.**
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
| yadm-dev/yadm | 6,394 | Python (listed) | **unread candidate** | — | a dotfiles manager wrapping git. Forecast: the writes happen in git child processes, which is the `pass` wall (`child_touched_state_dir`, #123). Not rejected — the forecast wants checking |
| GothenburgBitFactory/taskwarrior | 6,014 | C++ | already measured | — | PASS 12/12 record |
| stringer-rss/stringer | 4,126 | Ruby | reject | 4 — self-hosted web reader | description |
| neomutt/neomutt | 3,814 | C | reject | ~~8~~ → **4, as a judgment** | **re-judged, second pass**: the man page lists Batch mode as a first-class mode, so rule 8 does not fail. See §Second pass |
| martinrotter/rssguard | 2,720 | C++ | reject | 4 — GUI | description |
| anufrievroman/calcure | 2,338 | Python | reject | ~~8~~ → **4, uncertain** | **re-judged, second pass**: the README documents argument-driven task/event adding, so rule 8 is unproven. One wiki page would settle it |
| MordechaiHadad/bob | 2,138 | Rust | **unread candidate** | — | neovim version manager: installed versions plus a JSON. Multi-file coherence on paper |
| Rongronggg9/RSS-to-Telegram-Bot | 2,137 | Python | reject | 4 and 5 — a bot service | description |
| GitGuardian/ggshield | 1,991 | Python | reject | 5 — a scanner, no primary store | description |
| OfflineIMAP/offlineimap | 1,859 | Python | reject | 2 and 12 — pushed 2023-06-13, description says "[LEGACY" | pushed date measured; description |
| moonrepo/proto | 1,396 | Rust | **unread candidate** | — | pluggable version manager: tools, a lockfile, config. Multi-file coherence on paper |
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
