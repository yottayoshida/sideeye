# Cohort-3 define: papis (target 5, the cohort's last)

Target: papis 0.16.0 (the image's pinned current stable). Probe:
conditions 1–6 machine-green under the amended plan,
`../probes/papis.txt` — byte-deterministic (the fixture pins
`papis_id`), closure clean, with **3 in-process threads** measured and
"no off switch measured yet — to scout at its slot" recorded.
Scout sources: the probe transcript and its raw strace, papis's own
`parmap` docstring and its `doctor --help` (captured verbatim at the
head of the trials transcript), the thread off-switch scout — **on
main before this define** (`e43d96e`) — the pre-define trials, which
predate the define in fact and **arrive with it in history**, and the
engine's own contract source for what it counts as a kill point.
Assisted provenance.

## Claim standing

Unencumbered: papis has no prior explore and no FAIL verdict, so the
FAIL-freeze rule that bars poetry-r2 does not touch this define. Under
the frozen cohort-3 reading, a run whose earliest violating world has
the declared checker as its violated invariant would be a criterion-1
candidate. **The declaration below expects a PASS** — and says why, in
the write shape.

## The apparatus: PAPIS_NP=0 (scout-measured, free tier)

`../papis/thread-offswitch-scout.txt`, the probe's fixtures under the
probe's predicates: **default = 3 threads, 14 clone lines, 14 distinct
pids; `PAPIS_NP=0` = 0 threads, 0 clone lines, one pid** — rc 0 and the
document landed in both, asserted beside the counts so a zero cannot
mean "died at startup". The switch is papis's own documented one
(`papis/utils.py::parmap`: "The number of processes can also be
controlled using the `PAPIS_NP` environment variable. Setting this
variable to 0 will disable the use of multiprocessing on all
platforms"), so it is an env pin — the cohort's free apparatus tier,
disclosed in the launcher. Under it the scout also re-measured
determinism (two runs ≥2s apart byte-identical), the read-back
(exact, with the wrong-id drill at zero) and closure (unattributed 0).

## The write shape (scout strace, under PAPIS_NP=0)

`papis add` builds the entire document in a temp directory **outside**
the library and moves it in. Fifteen lines of the log touch the
library; exactly two of them mutate it:

1. `renameat(<tmp dir> → <library>/probe-doc)` — atomic;
2. `fchmodat(<library>/probe-doc, 0755)`.

The same shape is already on main from the **default-configuration**
probe (`../probes/raw/papis.strace`, one `renameat` + one `fchmodat`
in root), so the write shape is not an artefact of this define's
`PAPIS_NP=0`. Two bounds on the enumeration, stated rather than
implied: the scout's strace filter (`%file,write,clone,fork,vfork`) is
narrower than the oracle's (`%file,%desc,%process,…`), so the
transcript alone does not exclude an fd-based kill point such as
`fsync` — the argument that closes it is that every descriptor opened
into the library is read-only and the subject's cwd is `/`, and the
engine's own oracle re-measures at explore with the wider filter. And
the single-rename shape holds because the staging directory and the
library are on one filesystem here; across a filesystem boundary
Python's move falls back to copy-then-delete, which has a large
interior. `TMPDIR` is not pinned; both paths are under `/tmp` in this
define.

**Only the first is a kill point.** The engine's `OpClass`
(`src/contract.zig`) counts `open, write, rename, unlink, fsync,
truncate, mkdir, rmdir, link, symlink`; chmod is not among them — the
oracle records `chmod`/`fchmodat`/`fchmodat2` as **metadata observed**
(`src/oracle.zig`) and the report discloses them in its metadata line
without judging them. So the engine-reachable crash states are exactly
one: **kill before the rename → the library is the old library**, the
document not yet present. The un-killed baseline is the completed add.

That is the whole point of measuring this target: an operation with a
single atomic mutation has no interior to crash inside. The cohort's
other four write in place; this one does not.

## The mode seam, declared and deliberately not asserted

The `fchmodat` leaves a real seam — a world killed between the rename
and the chmod would hold the document at the temp directory's 0700
instead of 0755 — but it is unreachable (chmod is not a kill point)
and **a mode leg could not observe it anyway**. The mechanism, read
off the engine rather than assumed: restore creates directories with
`mkdir(…, 0o755)` and files with `open(…, O_CREAT, 0o644)` and never
chmods after (`src/engine.zig`), and those are exactly papis's
post-`fchmodat` modes (scout: 0755 on the directory, 0644 on both
members). So at the container's umask a mode leg is **vacuous** —
green in every world, blind to the seam — and under a stricter umask
it would go red in restored crash worlds while passing the baseline
(which a fresh papis run writes): a **false-candidate generator**.
This is a sharper reading than the cohort-2 `checkisexec` shorthand
("a mode assertion fails its own baseline"), which this define's R1
showed the engine cannot actually produce; the conclusion — do not
assert modes — is unchanged, the reason is corrected. The scout's mode
measurement is evidence for this paragraph, not a checker leg.

## The pre-define trials (engine-free, committed: `pre-define-trials.txt`)

Ten library states — the two engine-reachable ones, five surgery
shapes, and three built to attribute one write — through papis's own
reader and its documented repair. The trials were **re-run once
before this define merged**: the first version invoked `papis doctor`
with no query and no selection flag, so in every two-document library
it fell to the interactive picker and examined nothing — including
the missing-attachment state built specifically for doctor's `files`
check, which therefore never ran. A rejection of doctor as the
documented recovery cannot rest on a measurement that never let it
run (this define's R1). Every doctor invocation now carries `-a`; the
no-flag behaviour is kept in the transcript as a named demonstration,
because the trap is worth the record. Five readings decided the
checker, none of them what intuition would have written:

| state | `papis list` | what papis does |
|---|---|---|
| A: old library | rc 0 | lists `Existing existing0001` |
| B: completed add | rc 0 | lists both documents |
| C: `probe-doc` present but empty | rc 0 | **silently ignores the directory** — lists only Existing |
| D: attachment, no `info.yaml` | rc 0 | **silently ignores it** — the orphaned file is invisible to the tool |
| E: `info.yaml`, no attachment | rc 0 | **lists the document happily** although its file is gone |
| F: torn `info.yaml` | rc 0 | loads it, and **generates and persists a fresh random `papis_id` into the file** |
| G: truncated attachment | rc 0 | lists both — content is not the reader's business |

1. **`papis list` never exits nonzero** — rc 0 in all seven. An rc
   assertion would be a check that cannot fail; the reader leg has to
   assert the *content* of the listing.
2. **The reader is silent about incomplete documents** (C, D) and
   **credulous about missing files** (E). Neither direction of damage
   reaches the user through the tool.
3. **The reader writes, and what it writes is random** — both halves
   attributed by the added states: **H** (torn file, no command run at
   all) has no `papis_id` line; **I** (torn file, *only* `papis list`
   run) has one, so the writer is the reader and not doctor; and **J**,
   a second torn state byte-identical to I's, received a *different*
   id (`d1ea7e76…` vs `b6fc4c7b…`), so the value is generated, not
   derived from content. Hence the checker's structural and byte
   assertions all run *before* the reader — otherwise the checker
   judges its own side effect, non-deterministically.
4. **`papis doctor` is not a recovery here** — now measured with the
   selection flag on each of the seven library states, so the tool
   actually ran everywhere it was judged. Three
   findings, each disqualifying on its own: it is **red on the
   untouched baseline** (six errors — `bibtex-type`,
   `biblatex-type-alias`, `biblatex-required-keys` per document — on
   the two healthy documents of state B, rc 0 while saying so); its
   **one applicable fix discards the data** ("[FIX] Removing file from
   document: 'fixture.txt'", Auto-fixed 1 / 7, leaving `files: []` and
   a document papis still lists happily — the library made consistent
   by forgetting, which the cargo and poetry rulings already refused
   to call recovery); and on a torn `info.yaml` — the damage a repair
   would exist for — **doctor itself dies**, rc 1 with an uncaught
   `AttributeError` from `has_author_initials`. A command that is red
   before the operation, that resolves data loss by forgetting the
   data, and that crashes on the damage it would be called for, is not
   the documented recovery the cohort rule asks for. The rule is
   satisfied by having looked, fairly: there is none that applies, and
   the checker asserts directly. (The doctor crash is a target
   observation, not a crash-consistency finding — it is reachable by
   any hand-damaged `info.yaml`; any upstream conversation about it is
   a separate, owner-gated step.)

## The property (P1)

**Kill `papis add` anywhere; the library holds either the old document
set or the old set plus the COMPLETE new document, and papis's own
reader agrees about which.** Legs, in checker order:

- **guard**: the library exists, its top-level entries are exactly
  `existing-doc` (with both members) or `existing-doc probe-doc` —
  the enumeration the accepted probe asserted and this checker's first
  draft dropped, which is also what decides "is the new document
  present" for the two legs that branch on it (a `-e` test says no to
  a dangling symlink that `ls` says yes to, and the two legs must
  never disagree);
- **leg D**: the new document is all-or-nothing — `probe-doc` absent,
  or a plain directory (not a symlink, not a file) holding `info.yaml`
  **and** `fixture.txt`, the attachment holding the fixture's frozen
  bytes, and the metadata parsing as YAML with the frozen `title` and
  `papis_id`;
- **leg E**: the pre-existing document is conserved — its attachment's
  bytes and its own `title`/`papis_id`;
- **leg C**: the outside-root fixtures (both files, both metadata
  YAMLs) are byte-unmutated;
- **leg R**, last and alone in being able to write: `papis list --all
  --format '{doc[title]} {doc[papis_id]}'` lists **exactly** the
  documents leg D found — `Existing existing0001` always, plus
  `Probe probe0001` iff `probe-doc` is present.

Expected world outcomes, declared ahead: **one crash point, one
world** — the library before the rename, which is the pre-state, green
on every leg. The baseline is the completed add, green. **Expected
verdict: PASS over 2 worlds**, with the report's metadata line
disclosing the `fchmodat` the engine observed and did not judge. If
instead a world comes back checker-red, this target's claim standing is
unencumbered and the frozen reading applies as written.

**Which PASS**, stated because the engine has two and they are
different claims: the expected headline is `PASS 2/2 explored worlds
satisfied the built-in atomicity invariant / explored 2 worlds (crash
points 1 + 1 baseline)`. The other one — `PASS the operation performed
nothing that can change the judged state / explored 0 crash points` —
would mean the shim never saw the rename, and would be a statement
about the apparatus, not about papis. The two-witness design is what
makes the first non-vacuous: a shim blind to the rename yields
`oracle_missed_operation`, a refusal, which is exactly how cargo's
revision ended.

**What such a PASS does and does not establish**, said plainly: in the
one reachable crash world `probe-doc` is absent, so leg D's whole
block is skipped and the document assertion runs only on the un-killed
baseline — which the engine requires green anyway. The PASS therefore
establishes that **the single crash world this operation can produce
is the pre-state, and the pre-state is healthy** — i.e. that the
operation has no crash-visible interior in the library. It does not
exercise the all-or-nothing assertion against damage, because no
reachable damage exists. Two further bounds: a crash during the
staging phase leaves an abandoned temp directory **outside** the
library, which this define does not judge (a leak, not a corruption);
and, as in every cohort-3 define, an infrastructure failure inside the
checker (a `papis list` timeout, a python3/PyYAML failure) is counted
by the engine as a violation like any nonzero exit — the apparatus
reading is that a red naming a timeout is apparatus, not verdict.

Branch rehearsal: thirteen for thirteen in the committed
`checker-drills.txt` — two greens and eleven reds, every fragment
matching exactly one of the checker's messages (verified
mechanically). Coverage, counted rather than characterised: the
checker has **twenty** distinct failure messages and **ten** of them
have been seen red — leg D's five (not a plain directory; missing
`info.yaml`, reached by two different surgeries; missing attachment;
wrong attachment bytes; lost frozen fields), leg E's attachment, leg
C's fixture, leg R's set mismatch, and two guard branches (an entry
the operation cannot produce; the existing document's lost metadata).
The ten not seen red are the symmetric variants of drilled branches
(leg C's other three fixtures, leg E's parse failure and field check,
leg D's own parse failure, the guard's three other absence branches)
plus leg R's rc path. Per-leg red
— the campaign's requirement — is met with room to spare; "every
branch" is not claimed.
Most shapes are surgery-only: with one atomic rename a half-built
document is not engine-reachable, and they are rehearsed anyway
because a branch that has never been seen red is not trusted.

## Rejected shapes

- *Asserting the document directory's mode* — it cannot observe the
  seam: restore assigns its own 0755/0644, which are papis's
  post-chmod modes, so the leg is vacuous at this umask and a
  false-candidate generator under a stricter one. The mechanism is
  measured in "The mode seam" above.
- *Using `papis doctor` as the reader leg* — red on the untouched
  baseline (six type errors over the two healthy documents), rc 0
  while saying so. A check that is red before the operation cannot
  judge what the operation did.
- *Running `papis doctor --fix` as the documented recovery* — measured
  with its selection flag on the seven library states (A–G; H/I/J run
  no doctor by design): for the one damage shape it can act on it
  removes the lost file from the document rather than restoring it,
  and on a torn `info.yaml` it crashes. Forgetting is not recovery,
  and a lever that dies on the damage cannot be applied before
  asserting.
- *Asserting `info.yaml` byte-for-byte* — papis's own reader rewrites
  metadata (trial F), and the generated `ref` field is derived; the
  frozen `title`/`papis_id` pair is the assertion that means what it
  says.

## The pre-define novelty scan (recorded 2026-08-22)

All queries `gh api 'search/issues?q=repo:papis/papis+<term>'`, titles
of the top page read. Damage-shaped: "crash" 29 (all unrelated —
importer/URL/backend crashes; nearest is #1201, `papis add` crashing
on a path with spaces), "interrupted" **0**, "atomic" 1 (#1108,
renaming files in `papis update`), "\"papis add\" corrupt" 2 (both
unrelated), "power" 4 (all unrelated). Recovery-shaped — the round
poetry's R1 forced onto that define and which reversed its narrative,
run here for the same reason: "doctor" 90 (feature requests and check
proposals; none about doctor failing on damaged documents),
"papis_id" 34, "\"papis add\" interrupted" **0**, "recover" 7.
Positive control: "add" 711. No issue names crash damage to a library
or a failed repair of one, which matters only if the expected PASS
does not materialise; the claim-time gate re-runs regardless. No
transcript is committed for the scan — the cohort's standing practice,
noted rather than hidden.

## Stock reproduction

Any finding must reproduce against stock papis with no apparatus beyond
strace fault injection before it is claimed or reported — the cohort
rule, unchanged. The env pins (`PAPIS_NP`, the XDG paths, HOME) and the
library settings (`time-stamp: False`, `use-cache: False`) are
configuration, disclosed in the launcher and in setup.
