# Cohort 3 — probe outcomes (2026-08-22)

Engine-free probes per PROTOCOL.md's frozen plans, run in the
`sideeye-cohort3` image. The predicate drills and the positive control
ran first, on this image, before any probe verdict counted
(`probes/drills.txt` — every judging predicate red once;
`probes/positive-control.txt` — the synthetic wall-clock write split the
determinism condition, rc-checked). Conditions 1–6 are machine-judged by
cohort 2's `probes/lib.sh`, sourced in place; condition 7 is printed
evidence. Raw strace logs sit beside the transcripts (`probes/raw/`).

**What the committed transcripts are, precisely** (their own timestamps
are the record): first contact with the targets proceeded in cohort
order, but harness and plan corrections during the sweep mean each
committed transcript is **one clean run of its final harness**, re-run
after its correction — so the committed timestamps are *not* in cohort
order (each transcript's header carries its own). Every committed run
postdates the PROTOCOL
freeze merge on main; the earlier, superseded runs are uncommitted
except where stated (papis-v1). The iterations, disclosed rather than
smoothed over: the papis plan was amended once before its accepted probe
(the PROTOCOL amendment block and `probes/papis-v1.txt` are the record —
see below); the papis round-trip check's anchor was corrected once (the
bare `papis list` prints folder paths, not titles — measured; the check
now reads the document back through `papis list --format` and drills its
own anchor against a wrong id); and cargo's forecast reading was
corrected once (below).

## Outcomes

| # | Target | Probe verdict | Transcript |
|---|--------|---------------|------------|
| 1 | cargo 1.98.0 | **pass** — conditions 1–6 machine-green; Cargo.lock update measured (it does update); single-threaded itself, one vfork child (below) | `probes/cargo.txt` |
| 2 | black 26.5.1 | **pass** — conditions 1–6 machine-green; zero threads, zero children | `probes/black.txt` |
| 3 | rustfmt 1.9.0-stable | **pass** — conditions 1–6 machine-green; zero threads, zero children | `probes/rustfmt.txt` |
| 4 | poetry 2.4.1 | **pass** — conditions 1–6 machine-green; thread forecast measured per configuration (below) | `probes/poetry.txt` |
| 5 | papis 0.16.0 | **pass, under the amended plan** — conditions 1–6 machine-green; `papis_id` pinned by the fixture (determinism holds); 3 in-process threads (below) | `probes/papis.txt` (failed original plan: `probes/papis-v1.txt`) |

**All five primaries hold passing probes.** Stated precisely: four
passed their first probe under the frozen plan; papis passed under a
plan amended after its first probe failed (next section) — the frozen
text defined amendment-before-contact only for bench promotions, so the
papis pass is read as exactly what the record shows, not silently
folded into "five for five". **The bench (taplo → unison → sc-im) is
not activated either way**: even counting papis's first probe as its
outcome, four primaries passed, and the refill rule promotes only below
four.

**Thread-count readings, disclosed**: the cargo and poetry main-pass
transcripts print `inconsistent` from `thread_counts` — its pairing
assertion assumes only `CLONE_THREAD` clones split into
unfinished/resumed strace pairs, and both targets' vfork-style clones
also split, so the machine judge refused rather than guessing (its
fail-closed design working). The thread facts stated below therefore
come from reading the raw logs (`raw/cargo.strace`: the lone
`CLONE_THREAD` belongs to the rustc child, pid-attributed) and from the
clone-only forecast passes, whose counts are consistent. The pairing
assumption is a named limitation of the cohort-2 harness, out of this
batch's scope.

## The papis amendment (before its accepted probe)

The original plan carried metadata via `--set` flags. Its probe
(`papis-v1.txt`) failed conditions 1–4 with a network traceback: with no
`--from`, `papis add` runs importer auto-matching on the file's URI, and
papis 0.16's arxiv importer treats the local path as a candidate arXiv
identifier and **validates it against arxiv.org over HTTPS** — a GET of
`/abs/<the local path>` — so a failed metadata fetch fails a purely
local add. What v1 measured is the fetch dying on TLS certificate
verification under this machine's intercepting proxy — the network was
*reached*; any fetch failure propagates the same way, the exceptions
being uncaught. The importer set has no configuration filter (measured
in `papis/importer/__init__.py`: every plugin is tried, exceptions
propagate); `--from` skips URI matching structurally (`add.py`:
`if from_importer:` precedes the matching branch). The amended plan
carries the same fixed metadata through a frozen YAML fixture and
`--from yaml`. The v1 probe stays what it is — a failed probe of the
original plan — and the PROTOCOL amendment block is the frozen record.
Two more things v1's transcript shows, said here so the narrative does
not understate them: its *setup* add failed the same way, so v1 never
held the frozen pre-state (its library was empty throughout); and its
closing "raw log kept as papis.strace" line was superseded — the
committed `raw/papis.strace` is the accepted run's log.
The network-dependence of a local `papis add` is a target observation
worth remembering; any upstream conversation about it is a separate,
owner-gated step, not part of this cohort's record.

## Shim-visibility forecasts carried into the define phase

Transcript-measured observations; the engine's own refusals decide at
explore time.

- **cargo** (`probes/cargo.txt`): cargo itself is single-threaded; every
  fresh `cargo add` vforks one child, `rustc -vV`, whose **internal
  thread** the shim will observe. A warm `CARGO_HOME` does **not** remove
  the version probe — measured per state from fresh pre-state copies
  (an earlier ad-hoc "warm = zero clones" reading had measured a no-op
  add on an already-edited manifest, which short-circuits before the
  resolver; the transcript's fresh-pre-state loop is the honest form).
  If the engine refuses on that thread, the documented `RUSTC` override
  would be apparatus with its own gate — recorded as an option, not
  assumed.
- **black**, **rustfmt**: zero threads, zero children — inside the
  engine's observation range as measured.
- **poetry** (`probes/poetry.txt`): the default `add --lock` builds a
  virtualenv under the cache (its seeder spawns the threads) plus
  python-discovery forks. With poetry's documented
  `POETRY_VIRTUALENVS_CREATE=false`: **threads 0**, discovery forks
  remain (children are oracle-accountable; threads were the refusal
  class). That configuration rides the define's launcher.
- **papis** (`probes/papis.txt`): 3 in-process threads during `add`
  (CPython-level; no off switch measured yet). To scout at its slot.
  One nuance under `use-cache: False`: no cache *file* is written, but
  the cache directory skeleton still appears (condition-7 evidence in
  the transcript) — "no cache layer" holds for contents, not for the
  empty directories.

## Engine order (fixed here, before any define or explore)

All five passed, so the cohort order stands unchanged:

**cargo → black → rustfmt → poetry → papis.**

## Engine outcomes (updated as targets complete)

- **cargo (2026-08-22)** — **named wall, two layers deep, terminal**:
  r1 refused `child_process_detected` (the probe's forecast — the
  `rustc -vV` child's internal raw thread); the owner-approved RUSTC
  stand-in lifted that boundary (`single process` in the r2 report) and
  r2 then refused `oracle_missed_operation`: **the manifest's atomic
  rename is a raw syscall** — cargo imports libc `rename` but does not
  route this call through it, measured with an interposing logger
  against a libc-routed positive control
  (`cargo-r2/raw-rename-diagnosis.txt`) — past every function an
  LD_PRELOAD shim can interpose. The two-witness design refused rather
  than judging blind; both refusals reproduced on second runs. A
  ptrace-grade observer is engine architecture, the after-1.0 family of
  #201/#202. Measured binary = current stable, recheck inherent.
  Ruling: `cargo-r2/RUNLOG.md`. The torn-lock question this define froze
  (its checker-red ruling, drilled at the edges in both revisions)
  stays asked, not answered. The cohort order continues with black.

- **black (2026-08-22)** — **FAIL, candidate shape, closed at the
  novelty gate**: the cohort's first full crash-world verdict — 1 of 3
  worlds, the earliest case at crash point 2 (after the truncating
  `open`, before the single `write`: the empty file the define's R1
  predicted), violated invariant **"built-in atomicity, and the
  checker"** (leg E: parses, different program), `oracle_verified`
  true, reproduced identically three times. A candidate under the
  frozen reading — and the recorded novelty search found the
  phenomenon known upstream: psf/black#2479 (open since 2021, the same
  in-place wipe under disk-full) with fix PR psf/black#5207 open since
  2026-07-01, after the measured stable shipped. No criterion-1 claim;
  nothing filed upstream (owner-gated). The verdict still proves the
  sweet-spot thesis: frozen define to checker-red verdict in three
  worlds and minutes, on the most-used Python formatter, finding the
  exact defect its tracker took 2021-2026 to converge on. Ruling:
  `black/RUNLOG.md`. Inherited by target 3: the same thread publicly
  names rustfmt as a direct in-place writer — its novelty gate gets
  checked before its define exists.

- **rustfmt (2026-08-22)** — **FAIL, known-surface verdict, novelty
  pre-closed**: measured by owner decision with the gate already closed
  before the define existed (rust-lang/rustfmt#6041, open since
  2024-01-24; recorded pre-define search in the proposals). The explore:
  1 of 3 worlds, crash point 2 — the empty file the declaration named —
  combined invariant (leg V: rustc E0601 on an empty bin crate),
  `oracle_verified` true, reproduced identically twice. The
  cross-language proof point beside black: same class, same discipline,
  Rust target, minutes. No claim, nothing filed. Ruling:
  `rustfmt/RUNLOG.md`. The formatter half of the matrix is now fully
  measured; the criterion-1 search continues with poetry and papis.

## What the probe phase deliberately did not do

At the probe phase's close, no define existed and no engine explore had
run. The defines follow the sharpened mini-seal: define PR to main first,
explore after; each explore's outcome lands here as its target completes.
