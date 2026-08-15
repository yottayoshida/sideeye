# Novelty round — the four assisted findings against their upstream trackers

2026-08-15. The next step ADR 0017 and the criterion 1 status trail designated:
a recorded tracker search with a positive control, per finding — the shape
campaign 1 used for topydo (search terms + positive control + bodies read,
recorded in that campaign's ledger), at 9–10 terms per target where campaign 1
ran fourteen; the review round then added ~25 more probes of its own, none of
which changed a verdict. "Novel as far as this search sees" is the strongest
claim this file makes anywhere; each section names what its search did NOT
cover. Reading these trackers is scouting, permitted for assisted findings —
and none of it touches the findings' provenance, whose defines were committed
before these searches ran (`REMEASURE.md`).

## Method

Per target: identify the upstream tracker; run a vocabulary sweep
(`gh search issues --repo <r> "<term>" --include-prs=false`, which matches
titles AND bodies); read the bodies of every hit whose title could plausibly be
the finding; establish a positive control (the vocabulary demonstrably reaches a
real, existing issue of adjacent shape — or, for tiny trackers, enumerate
everything, where enumeration IS coverage). Terms and hit counts are recorded so
the sweep is re-runnable.

## buku — torn bookmarks.db after a mid-write crash: NOT FOUND (novel as searched)

- Tracker: `jarun/buku` (canonical; active, 6 open at search time).
- Sweep (term: hits): crash 7, corrupt 3, truncate 3, atomic 0, interrupted 11,
  "data loss" 3, journal 6, "sqlite error" 0, malformed 7, plus the finding's own
  error string "file is not a database" (loose-word hits only, none relevant).
- Bodies read (nearest three): #536 (db trouble over NFS — locking, empty table,
  a different mechanism), #332 (user deleted their own db, asks about recovery),
  #480 (encryption workflow errors). None is a crash-window tear.
- Positive control: "corrupt" surfaces #536 on a BODY-text match ("It does
  corrupt the db file") — the vocabulary reaches issue bodies, not titles only.
- Not covered: nothing structural — this tracker is the project's only one.
- For the report step, not for novelty: whether the tear is buku's sqlite usage
  or unavoidable is an attribution question deliberately left to the upstream
  conversation; the finding as measured (buku's own recovery-open says "file is
  not a database" in 2/22 worlds, oracle agreeing on all 21 operations) is what
  the search looked for and did not find.
- **Corrected 2026-08-15 (after this search ran): the claim in the previous
  bullet overstates what was measured.** The "file is not a database" line is
  the falsification gate's output over a deliberately corrupted db, not any
  crash world's; the 2/22 count is the engine's L0 byte invariant, and an
  instrumented re-run shows buku's recovery-open succeeding in all 22 worlds
  (hot journal present in both torn ones). The finding is withdrawn entirely,
  which moots its report step; the sweep above stands as a search record. Full
  measurement: `buku/RUNLOG.md`, Correction section, and `buku/inspection/`.

## calcurse — interrupted `-P --purge` truncates apts, destroying an unnamed bystander: NOT FOUND (novel as searched)

- Tracker: `lfos/calcurse` (canonical; active, 173 open).
- Sweep: purge 4, truncate 3, crash 8, corrupt 6, "data loss" 1, atomic 0,
  interrupted 2, apts 34, "lost events" 0, "empty file" 0. (The first pass
  recorded apts as 20 — a `--limit 20` ceiling transcribed as a count; review
  caught it. The 14 hits beyond the window were read; two pass the
  plausible-title bar and are disposed below.)
- Bodies read (nearest two): #306 (periodic save vs caldav merge — concurrency,
  not crash), #143 (io_mutex between threads/hooks — interference, not
  crash-window atomicity; no mention of in-place rewrites tearing). The
  crash-titled hits are segfaults/import crashes, none about what a crash leaves
  in apts.
- From the apts tail (review's probes): #490 (open) — a PERSISTENT bad line in
  apts that returns after removal, caldav-suspected; no crash involved. #249 —
  imported appointments deterministically not saved, apts zero-length on every
  run of that path; a save-path failure, not a crash window (and a live
  demonstration that a zero-length apts exists in the wild while our
  "empty file" term returned 0 — zero hits for a phrase never means the
  concept is absent).
- Positive control: "corrupt" surfaces #6 — a real, existing
  apts-file-corruption issue (iCal import escaping) — so apts-corruption
  discussions are reachable by this vocabulary.
- Not covered: nothing structural — this tracker is canonical.

## stow — interrupted unfold destroys the fold symlink before the real directory exists: NOT FOUND on the tracker (novel as searched, boundary stated)

- Tracker: `aspiers/stow` (the maintainer's development repo and de-facto
  tracker; 43 open).
- Sweep: unfold 3, fold 12, interrupt 0, crash 0, atomic 0, partial 1,
  dangling 2, corrupt 0, "broken state" 0, power 0. **Every
  interruption/crash/atomicity term returns zero** — the failure class is absent
  from the tracker's vocabulary entirely.
- Bodies read: #29 (force split-open — a feature request about WHEN to unfold,
  not about the unfold's crash window; notably it arrived from the help-stow
  mailing list, evidence that list traffic funnels into this tracker). The
  fold/unfold hits are behavior/feature discussions.
- Disposed for future re-runners (review's probe): **#69 "Restow does not
  actually write between removing and creating"** — the title reads exactly
  like our window and the body is its INVERSE: a complaint that `-R` does NOT
  remove-and-recreate (symlink mtimes never change), plus doc-wording
  discussion. Anyone re-running natural stow vocabulary will hit it; it is not
  a prior report of the finding.
- Positive control: "fold" surfaces 12 real tree-folding discussions (#120,
  #131, #29 …) — the finding's own domain vocabulary demonstrably reaches this
  tracker.
- Not covered, stated: the GNU mailing-list archives (bug-stow, help-stow) were
  not searched; #29's provenance suggests but does not prove that list-reported
  issues reach the tracker. A POSIX framing ("no atomic symlink→directory swap
  exists, so the window is inherent") may await the report — that is an
  attribution conversation, not a prior report of the finding.

## devtodo — in-place XML rewrite tears .todo in 6/8 crash worlds: NOT FOUND (both trackers enumerated — the second one twice)

- Trackers: `alecthomas/devtodo` (upstream, legacy line — the Debian package's
  source) and the Debian BTS (the distribution actually shipped).
- GitHub, by enumeration: 8 items total — 4 issues + 4 pull requests — all
  titles read, the Debian-patches threads (#2, #3) read as bodies. None
  concerns data integrity, saving, or file writes.
- **Debian BTS: the first pass enumerated the OPEN view (4 bugs) and called it
  the tracker — review caught the wrong denominator.** The combined
  open+archived view holds exactly **72 bugs** (pinned by counting the bug
  links in the raw page — a first re-fetch summarizer silently dropped two,
  #117364 manpage typo and #173566 package filename conflict, both since read
  and both data-unrelated). All 72 titles read; the data-adjacent set,
  disposed one by one:
  - **#511342 (grave, "does not check for file creation errors") is the
    nearest prior report on mechanism and it is a different one**:
    `open(".todo", O_WRONLY|O_CREAT|O_TRUNC)` FAILS with EACCES and devtodo
    exits 0 having written nothing — ignored error returns on the very same
    in-place-rewrite path our finding kills midway through. No crash, no
    interruption, no torn file (the reporter notes no write() ever happened);
    fixed in 0.1.20-4. The reporter's forward-looking sentence is the closest
    thing in the whole BTS to a partial-write concern — "it would be good to
    check if the program correctly detects write(), flush() and close()
    failures (e.g. when filesystem runs out of space)" — a wish for error
    checking, still not a crash window. The same code path's failure, from the
    other side of the syscall boundary.
  - **#239581 ("race condition") is the only bug in the BTS reporting OBSERVED
    .todo corruption, and it carries the maintainer's own account of the write
    path**: eleven parallel `tda` processes against one database left 2 of 11
    items alive and the loader saying "no database loaders for database format
    or database corrupt"; Alec Thomas replied "This is not surprising; there
    is no locking of any form in devtodo." The mechanism is concurrent
    unserialized read-modify-write — no kill, no interruption anywhere in it —
    so it is not our finding; but any upstream conversation about this write
    path starts from that quote, and the corruption CLASS (an unreadable
    .todo) is the same one our crash worlds produce by a different route.
  - #93641 (grave, .todo world-readable) — permissions, and plausibly the
    ancestor of the per-rewrite chmod our #121 run observes and excludes (the
    fix era introduced permission-restricting behavior; the link is inference,
    not stated in the bug).
  - #173904 / #108791 / #91820 / #307226 — segfaults on display/EOF/arch
    paths, not the save path (though #307226-adjacent #308706 has a segfault
    MODE too, below). #516604 — `--purge` endless loop, data integrity
    verified by the reporter (identical .todo MD5 before/after). #308706 —
    `--purge` freeze AND a segfault on complex nested-note files; nobody
    reported file damage, and nobody verified its absence either. #175730 —
    display formatting.
- Positive control: enumeration is the coverage — and the review's independent
  probe confirmed `gh search issues` reaches comment text too (a comment-only
  word on GitHub #2 is findable), so nothing in the small trackers hid below
  the title layer.
- Counterparty, corrected by review: the "unmaintained since ~2010" line in the
  scoring materials came from #2's OPENER (Debian QA), and the upstream
  maintainer replied in the same thread: "It is maintained, it's just stable"
  — commits into 2021, a 2026 issue closed within the hour. The
  author-confirmed leg has a live counterparty after all; slow-moving, not
  absent.

## What this round does and does not establish

All four findings are **novel as far as these searches see** — no prior report
of any of them was found. That closes none of criterion 1's legs by itself: the
searches feed the upstream-contact step (which needs owner approval per report,
per the workspace's upstream-report style), and author confirmation, fixes and
replayed cases all remain open. The searches above are re-runnable from the
recorded terms; anyone re-running them should expect the hit COUNTS to drift as
trackers move, and the verdicts to stand or fall on what the new hits say.

## Upstream round (2026-08-15, same day)

Reports filed, each written as a plain bug report with a reproduction the
maintainer can run using only strace's fault injection (no tooling from this
project is named or needed):

- calcurse: https://github.com/lfos/calcurse/issues/529
- stow: https://github.com/aspiers/stow/issues/139
- devtodo: filed as https://github.com/alecthomas/devtodo/issues/9 and then
  WITHDRAWN the same day, on the owner's judgement that reporting into a small
  dormant project we do not use is not fair play: the evidence value accrues
  here while the work lands on a maintainer who never asked for it. The finding
  itself stands and stays in this repository. The selection rule this produced
  is written into PROTOCOL.md, applied at target selection rather than at report
  time, because that is where the cost is actually incurred.

**buku is HELD, and the reason is a correction to this project's own record.**
Before writing its report, the finding was re-derived with plain tooling: kill
the process at write N of the transaction and see whether buku can still read
its store. Measured, in the same pinned container: injections on bookmarks.db
writes (8 points), on journal writes (10 points), and on the two files
interleaved (20 points) all end with sqlite rolling the transaction back and
buku reading its store normally. **Zero of 38 plain attempts reproduce it.**

What the engine recorded is not withdrawn: the checker did fail in one world
with buku's own `initdb(): file is not a database`, and that transcript is
committed. But two things follow. First, no upstream report can be written on
evidence a maintainer cannot reproduce, so buku waits until the world is
reachable by ordinary means. Second, the earliest violation in that run was
`built-in atomicity (L0)`, a BYTE comparison, and for a journaled database a
mid-transaction byte state is exactly what the journal exists to recover from
— L0 is stricter than sqlite's contract here, which is a limitation of judging
a journaled store by file bytes, not a defect in buku. The finding's strength
therefore rests on the one checker failure alone, and reproducing that world
with plain tooling is the open work.

This is the "measured with the defect I was describing" class caught before it
left the repository: the novelty search above asked whether the finding was
already reported, and answered honestly, but the report step asked the harder
question first — can anyone else see it — and the answer for buku today is no.
