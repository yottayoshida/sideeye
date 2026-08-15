# Novelty round — the four assisted findings against their upstream trackers

2026-08-15. The next step ADR 0017 and the criterion 1 status trail designated:
a recorded tracker search with a positive control, per finding — the same method
campaign 1 used for topydo (search terms + positive control + bodies read,
recorded in that campaign's ledger). "Novel as far as this search sees" is the
strongest claim this file makes anywhere; each section names what its search did
NOT cover. Reading these trackers is scouting, permitted for assisted findings —
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

## calcurse — interrupted `-P --purge` truncates apts, destroying an unnamed bystander: NOT FOUND (novel as searched)

- Tracker: `lfos/calcurse` (canonical; active, 173 open).
- Sweep: purge 4, truncate 3, crash 8, corrupt 6, "data loss" 1, atomic 0,
  interrupted 2, apts 20, "lost events" 0, "empty file" 0.
- Bodies read (nearest two): #306 (periodic save vs caldav merge — concurrency,
  not crash), #143 (io_mutex between threads/hooks — interference, not
  crash-window atomicity; no mention of in-place rewrites tearing). The
  crash-titled hits are segfaults/import crashes, none about what a crash leaves
  in apts.
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
- Positive control: "fold" surfaces 12 real tree-folding discussions (#120,
  #131, #29 …) — the finding's own domain vocabulary demonstrably reaches this
  tracker.
- Not covered, stated: the GNU mailing-list archives (bug-stow, help-stow) were
  not searched; #29's provenance suggests but does not prove that list-reported
  issues reach the tracker. A POSIX framing ("no atomic symlink→directory swap
  exists, so the window is inherent") may await the report — that is an
  attribution conversation, not a prior report of the finding.

## devtodo — in-place XML rewrite tears .todo in 6/8 crash worlds: NOT FOUND (both trackers fully enumerated)

- Trackers: `alecthomas/devtodo` (upstream, legacy line — the Debian package's
  source) and the Debian BTS (the distribution actually shipped).
- Coverage by ENUMERATION, not sampling: GitHub has 8 issues total, all read as
  titles + the two Debian-patches threads (#2, #3) as bodies; Debian BTS lists 4
  bugs (#794015 documentation, #401476 + #239578 + #294472 wishlist features).
  None concerns data integrity, saving, or file writes.
- Positive control: not applicable in vocabulary form — full enumeration IS the
  coverage on trackers this small.
- Counterparty caveat, carried from the scoring: upstream describes itself as
  unmaintained since ~2010 (#2's own words), so the author-confirmed leg of
  criterion 1 has a real "confirmed by whom" problem here whatever the novelty.

## What this round does and does not establish

All four findings are **novel as far as these searches see** — no prior report
of any of them was found. That closes none of criterion 1's legs by itself: the
searches feed the upstream-contact step (which needs owner approval per report,
per the workspace's upstream-report style), and author confirmation, fixes and
replayed cases all remain open. The searches above are re-runnable from the
recorded terms; anyone re-running them should expect the hit COUNTS to drift as
trackers move, and the verdicts to stand or fall on what the new hits say.
