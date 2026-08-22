# Cohort-3 define: papis (target 5, the cohort's last)

Target: papis 0.16.0 (the image's pinned current stable). Probe:
conditions 1–6 machine-green under the amended plan,
`../probes/papis.txt` — byte-deterministic (the fixture pins
`papis_id`), closure clean, with **3 in-process threads** measured and
"no off switch measured yet — to scout at its slot" recorded.
Scout sources: the probe transcript and its raw strace, papis's own
`parmap` docstring and `doctor` help output, the thread off-switch
scout and the pre-define trials committed beside this file (both
already on main before this define), and the engine's own contract
source for what it counts as a kill point. Assisted provenance.

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
the library and moves it in. The state root sees exactly two calls:

1. `renameat(<tmp dir> → <library>/probe-doc)` — atomic;
2. `fchmodat(<library>/probe-doc, 0755)`.

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
**and unjudgeable if it were**: the engine's restore does not
reproduce permission state ("crash worlds run at the engine's default
modes"), so a checker asserting a mode fails its own un-killed
baseline. That is the cohort-2 lesson from mercurial's `checkisexec`,
applied here before the fact. The scout recorded the modes (0755 on
the directory, 0644 on both members) as evidence for this paragraph,
not as a checker leg.

## The pre-define trials (engine-free, committed: `pre-define-trials.txt`)

Seven library states — the two engine-reachable ones and five surgery
shapes — through papis's own reader and its documented repair. Four
readings decided the checker, none of them what intuition would have
written:

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
3. **The reader writes.** In state F papis persisted a generated
   `papis_id` into the very file the crash damaged. So the checker's
   structural and byte assertions must all run *before* the reader —
   otherwise the checker judges its own side effect.
4. **`papis doctor` is not a recovery here** — measured, not assumed:
   in a multi-document library it falls to the interactive picker
   ("Cannot show the picker… No documents retrieved") and returns
   rc 0 having examined nothing; where it does run it reports the same
   three type errors (`bibtex-type`, `biblatex-type-alias`,
   `biblatex-required-keys`) on the **untouched pre-state baseline**,
   and `--fix` reports "Auto-fixed 0 / 3 errors". A red-on-baseline,
   fixes-nothing command cannot be the documented recovery the cohort
   rule asks for. The rule is satisfied by having looked: there is
   none that applies, and the checker asserts directly.

## The property (P1)

**Kill `papis add` anywhere; the library holds either the old document
set or the old set plus the COMPLETE new document, and papis's own
reader agrees about which.** Legs, in checker order:

- **guard**: the library exists and the existing document is there
  with both members;
- **leg D**: the new document is all-or-nothing — `probe-doc` absent,
  or present with `info.yaml` **and** `fixture.txt`, the attachment
  holding the fixture's frozen bytes, and the metadata parsing as YAML
  with the frozen `title` and `papis_id`;
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

Branch rehearsal: eleven for eleven in the committed
`checker-drills.txt`, each red attributed by a branch-specific
fragment — leg D's four distinct messages (empty directory, missing
`info.yaml` with the attachment present, missing attachment, torn
metadata, wrong attachment bytes), leg E, leg C, leg R (a third
structurally valid document that only the reader can see), and the
guard. Most are surgery-only shapes: with one atomic rename a
half-built document is not engine-reachable, and they are rehearsed
anyway because a branch that has never been seen red is not trusted.

## Rejected shapes

- *Asserting the document directory's mode* — unjudgeable by
  construction (restore flattens modes); it would fail its own
  baseline. Declared above instead.
- *Using `papis doctor` as the reader leg* — red on the untouched
  baseline (three type errors on a healthy document), and rc 0 while
  saying so. A check that is red before the operation cannot judge
  what the operation did.
- *Running `papis doctor --fix` unconditionally as a recovery* —
  measured impotent for every damage shape here (retrieves nothing
  non-interactively in the two-document states; auto-fixes 0 of 3
  where it runs), and it mutates metadata on healthy documents, which
  would make the checker judge its own edit.
- *Asserting `info.yaml` byte-for-byte* — papis's own reader rewrites
  metadata (trial F), and the generated `ref` field is derived; the
  frozen `title`/`papis_id` pair is the assertion that means what it
  says.

## The pre-define novelty scan (recorded 2026-08-22)

All queries `gh api 'search/issues?q=repo:papis/papis+<term>'`, titles
of the top page read: "crash" 29 (all unrelated — importer/URL/backend
crashes; nearest is #1201, `papis add` crashing on a path with spaces),
"interrupted" **0**, "atomic" 1 (#1108, renaming files in `papis
update`), "\"papis add\" corrupt" 2 (both unrelated), "power" 4 (all
unrelated). Positive control: "add" 711. No issue names crash damage
to a library, which matters only if the expected PASS does not
materialise; the claim-time gate re-runs regardless.

## Stock reproduction

Any finding must reproduce against stock papis with no apparatus beyond
strace fault injection before it is claimed or reported — the cohort
rule, unchanged. The env pins (`PAPIS_NP`, the XDG paths, HOME) and the
library settings (`time-stamp: False`, `use-cache: False`) are
configuration, disclosed in the launcher and in setup.
