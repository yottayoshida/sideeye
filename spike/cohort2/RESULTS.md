# Cohort 2 — probe outcomes (2026-08-21)

Engine-free probes per PROTOCOL.md's frozen plans, run in the
`sideeye-cohort2` image. The final transcripts come from **one sweep in
cohort order** — drills, positive control, then Borg → Mercurial →
Jujutsu → KeePassXC → Bun — after two committed rounds of harness and
plan iteration disclosed below. Raw strace logs are committed beside the
transcripts (`probes/raw/`). This page is the index and the ruling; the
transcripts are the record.

**What is machine-judged and what is read.** Conditions 1–6 are judged by
the harness's own predicates (the `FAILS` counter in each transcript).
Condition 6 — closure — is **fail-closed accounting**: every successful
mutating syscall must yield an attributable path (kernel-resolved fd
decorations, dirfd-joined arguments, write-fd decorations), every path
must sit under a declared prefix at a component boundary, and a call whose
path strace cannot read counts against the verdict instead of vanishing.
Condition 7 is printed evidence — the ambient's contents and per-run reset
— read, not scored. Every judging predicate has been seen red once against
a violating input: conditions 1, 2, 3, 4 and 6 in `probes/drills.txt`
(closure twice — an undeclared write and an unattributable pointer-arg
call — plus a green control), condition 5 by the positive control
(`probes/positive-control.txt`, the unpinned `borg create`, which split).

## Outcomes

| # | Target | Probe verdict | Transcript |
|---|--------|---------------|------------|
| 1 | BorgBackup 1.4.0 | **named wall: determinism** — conditions 1–4 and 6 pass; two pinned `borg create` runs 2s apart differ in `data/*` segments, `index.5`, `integrity.5` | `probes/borg.txt` |
| 2 | Mercurial 7.2.4 | **pass** — conditions 1–6 machine-green; whole-`.hg` root byte-identical across runs; closure clean | `probes/hg.txt` |
| 3 | Jujutsu 0.44.0 | **pass** — conditions 1–6 machine-green, after two measured pre-explore plan amendments (below) | `probes/jj.txt` |
| 4 | KeePassXC 2.7.10 | **named wall: determinism (pre-declared)** — conditions 1–4 pass; two `keepassxc-cli add` runs produce different `db.kdbx` bytes. Condition 6 additionally refuses fail-closed: 7 successful mutating calls carry pointer arguments strace cannot read (the CLI locks its memory), so closure is unattributable — a second, independent reason this target cannot be spelled | `probes/keepassxc.txt` |
| 5 | Bun 1.4.0 | **pass** — conditions 1–6 machine-green over a local-tarball `bun add`; the same add succeeds under `docker --network=none` | `probes/bun.txt`, `probes/bun-network-independence.txt` |

**The jj amendments** (PROTOCOL "Probe plans" note): the frozen `.jj` root
failed the closure condition — jj 0.44's `jj git init` colocates the git
store at `./.git`, measured in `probes/jj-v1.txt` — and the corrected
repository-wide root then split on one byte run, the reflog line jj's git
export stamps with wall-clock time (`probes/jj-v2.txt`). The final
pre-state sets `core.logAllRefUpdates=false`. Both earlier transcripts
predate the final harness (they carry its older, weaker output format);
they are committed as the amendments' evidence, not as verdicts.

**A flag that dissolved on the raw evidence**: an earlier, weaker harness
listed `/var/lib/libuuid/clock.txt` as a borg write outside the state
root. The committed raw log shows that open fails `ENOENT` — nothing
persists, and the fail-closed harness counts successful calls only, so no
exclusion exists. The earlier flag was the extraction counting failed
calls, not a target behavior.

## Wall rechecks (latest upstream stable, per PROTOCOL "Versions")

- **Borg** (`probes/recheck-borg.txt`): latest stable is 1.4.5
  (2026-07-18, GitHub API). The fetched 1.4.5 `src/borg/archive.py`
  carries the mechanism verbatim: `duration = timedelta(seconds=
  time.monotonic() - self.start_monotonic)`, `end = timestamp + duration`,
  stored as `time_end` in the archive metadata. The wall is a property of
  the current release. Terminal.
- **KeePassXC** (`probes/recheck-keepassxc.txt`): latest stable is 2.7.12
  (2026-03-10, GitHub API). The mechanism is the format — every KDBX save
  derives fresh random salts/IVs. The 2.7.10 CLI's help carries no
  determinism/seed/reproducibility option (measured on the probe image's
  binary, stated as such), and the fetched 2.7.12 changelog's 2.7.11 and
  2.7.12 sections (91 lines) contain no determinism-related change.
  Terminal.

## Engine order (fixed here, before any define or explore)

Walls yield their slots; survivors keep the cohort order:

**Mercurial → Jujutsu → Bun.**

## Shim-visibility forecasts carried into the define phase

Transcript-measured observations; the engine's own refusals decide at
explore time.

- **Mercurial** (`probes/hg.txt`): one successful `CLONE_THREAD` during
  `hg commit` by default; the forecast table measures it per configuration
  — default 1, `worker.enabled=no` 1, `worker.backgroundclose=no` 1,
  `storage.revbranchcache.mmap=no` **0**. The shim notes every
  `pthread_create` and the engine refuses on threads, so the define's
  launcher pins that config.
- **Jujutsu** (`probes/jj.txt`): `ldd /usr/local/bin/jj` prints "not a
  dynamic executable" — a static binary cannot load an `LD_PRELOAD` shim,
  so the engine is expected to refuse at recording. When jj's slot arrives
  the choice is between recording that wall and building a
  dynamically-linked jj as apparatus; neither choice is made here.
- **Bun** (`probes/bun.txt`): dynamically linked (ldd output in the
  transcript), but 6 successful `CLONE_THREAD` creations during `bun add`
  (inline successes plus unfinished/resumed pairs, counted with a
  consistency assertion in the harness) — a `multiple_threads_detected`
  refusal is the expectation unless a single-threaded mode exists; to be
  measured at its slot. The network contact its strace shows is optional
  (the `--network=none` companion transcript), so that part is not the
  blocker.

## What this phase deliberately did not do

No define exists yet; no engine explore has run; no failure of any target
has been observed. The first define (Mercurial) follows the sharpened
mini-seal: define PR to main first, explore after.
