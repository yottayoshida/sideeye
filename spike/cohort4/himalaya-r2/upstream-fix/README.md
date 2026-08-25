# Replaying the cohort-4 himalaya case across the upstream fix

The finding this directory sits under was reported as pimalaya/himalaya#738 and
fixed by the maintainer the same day, in a separate crate: pimalaya/io-maildir
commit b4e9080, released as io-maildir 0.3.1. The record here answers one
question and nothing else.

> The committed exhibit replays against the version that **has** the bug, so it
> reproduces rather than detects. Does the saved case say anything about a build
> that carries the fix?

**Measured answer: no.** The case refuses — `UNKNOWN case_no_longer_applies`,
exit 2 — because the fix changes how many state-changing operations the
operation performs, and a case names a crash point inside a recorded sequence.
The refusal is the promised behaviour, not a defect: contract-freeze §4 says a
saved case "replays across 1.x or refuses honestly — `case_no_longer_applies`
when the code changed underneath it".

A second thing fell out that was not being looked for: the frozen checker's
guard states a premise the fix made false, and a fresh explore against the fixed
build therefore FAILs for a reason that reads like the bug is still there.

## What was built, and what the delta is

`Dockerfile` here builds himalaya against io-maildir 0.3.1 and installs it into
the cohort-4 image, which is otherwise untouched. Starting FROM the already-built
image rather than rebuilding the cohort Dockerfile is deliberate: that file says
its apt layer is pinned by BUILD rather than by manifest, so a rebuild may drift.
Replacing one file makes the delta between "the measured target" and "the fixed
target" the himalaya binary and nothing else.

Measured, not asserted:

| | stock image | fixed image |
|---|---|---|
| himalaya sha256 (first 16) | `86a1872f91da1980` | `8155dd56e9e31af5` |
| strace sha256 (first 16) | `e4f0c42a07574df2` | `e4f0c42a07574df2` |
| unison sha256 (first 16) | `fd4583a93eeedd30` | `fd4583a93eeedd30` |
| himalaya tree | v2.1.0, rev ca88bee | v2.1.0, rev ca88bee |

**The himalaya hash in that table is an identity, not a pin.** Building the
fixed image twice from byte-identical inputs produced two different binaries
(`055fc2…` then `8155dd…`), so the output hash cannot stand for the inputs.
Everything in this directory was re-measured against the second one, so the
transcripts and the committed `Dockerfile` describe the same image; the earlier
runs, whose verdicts were identical, are not kept.

**What is pinned is the input side, and the `Dockerfile` checks it in two
parts.** The tree digest is computed over every file except `Cargo.lock` and
must equal `1fc324cc…`, which is the frozen `artifacts/himalaya-src` digested
the same way: the machine-checked statement that nothing but the lock differs
from the pinned v2.1.0 checkout. The lock is then pinned by its own sha256
(`cc703172…`). Both were shown red before being trusted — appending one line to
a source file changes the tree digest and the build stops at that layer, before
cargo runs.

**The size of the edit is not the size of the change.** `Cargo.lock.diff` is
two lines, io-maildir's version and its checksum, and `cargo vendor --locked`
accepting that lock is what says no *other* crate moves. The compiled closure
still differs by an entire crate release, 0.3.0 to 0.3.1 — every change upstream
made between those tags is in this binary, not only the copy fix. A first
attempt let cargo re-resolve the whole lock and moved windows-sys in five places
as a side effect; that lock was discarded and the two lines were edited by hand
instead, so at least nothing travels with the release that did not come from it.

The image build asserts the fix is in the crate cargo actually compiled, on the
**semantics** rather than on a state-variant name. The names moved between the
fix commit (`AwaitCopy`/`AwaitRename`) and the 0.3.1 release (`Copy`/`Rename`),
so grepping the commit's identifiers against the release reports a false absence.
That happened once here before the assertion was written this way.

## The six runs

| # | target | checker | verdict | transcript |
|---|---|---|---|---|
| 1 | 0.3.0 | frozen | replay: FAIL 1 of 2, leg D, "the case reproduced" | `replay-stock.txt` |
| 2 | **0.3.1** | frozen | replay: **UNKNOWN `case_no_longer_applies`**, exit 2 | `replay-fixed.txt` |
| 3 | 0.3.1 | frozen | explore: FAIL 2 of 4, **guard**, crash point in `Archive/tmp` | `explore-fixed.txt` |
| 4 | 0.3.1 | relaxed | explore: **PASS 4/4** | `explore-fixed-relaxed.txt` |
| 5 | 0.3.0 | relaxed | explore: FAIL 1 of 3, leg D | `explore-stock-relaxed.txt` |
| 6 | both | — | un-killed operation: one complete 307-byte copy, nothing staged, on **both** targets | `functional-control.txt` |

Run 6 is the functional control and it was added after review, because the first
version of this record did not have one. Neither the frozen checker nor the
relaxed instrument pins the copy's *presence*: an empty target folder is one of
the two states the property allows, so a build that returned 0 while copying
nothing would satisfy the checker in every world and produce PASS 4/4. The
engine's falsification gate does not close that either — it corrupts the state
and the checker goes red through source conservation, which fires whether or not
a copy would ever be made. `functional-control.sh` runs the operation once,
un-killed, outside the engine, and asserts what the checker deliberately does
not. It was shown red by replacing `himalaya` with a script that exits 0 and
does nothing: "the target folder holds 0 entries, want exactly 1".

Run 1 is the positive control and it is why the rest can be read: it reproduces
the committed transcript. Not field for field by eye — **diffed**, after
normalising the two things that cannot be equal across runs, the minted filename
and the per-run work path. The diff is empty. That covers the verdict, both
crash-point classes, leg D's wording including "0 bytes on disk against 307 in
the source", `oracle: agreed on 2 operations (139 syscall lines examined, 30 in
scope of the judged state)`, the eight paths judged and the one excluded fchmod.
The minted name is what the checker is deliberately name-agnostic about.

Run 5 is the negative control, and it exists because a relaxation written by the
person who wants a PASS can only confirm the breakage that person imagined. It
asks whether relaxing the guard disarmed the detector: it did not — the original
defect is still caught, through leg D, with the same wording. Under 0.3.0 the
target folder's staging directory holds **0 entries in every world**, which is
the direct measurement that "this operation stages nothing" was true when it was
written.

## Finding 1: the case cannot be leg C

Run 2's message names the mechanism exactly:

    the recording now counts 3 state-changing operation(s); the case was
    recorded over 2

The third operation is the rename. The fix copies into the target's staging
directory and renames the result into place, so a case recorded over two
operations addresses a sequence that no longer exists.

This is decidable against a bar this repository has already written down rather
than against an opinion. `spike/dogfood-timew-replay.sh` is the CI regression for
the timewarrior finding — the leg the workflow names "Replay across the fix:
record, FAIL unpatched, PASS patched" — and its leg C says:

    leg C: expected a clean replay PASS (exit $rc_c). A case_no_longer_applies
    here is honest but does NOT meet the v0.4 acceptance

Applying that bar to the himalaya case: legs A and B are satisfied by the
committed run, and **leg C is not reachable**.

**What the two findings do and do not license, said carefully.** The measured
part is a contrast between two cases, and nothing more: the timewarrior patch
left the operation sequence intact and its case survived its own fix; the
himalaya patch adds an operation and its case did not. That much is in the two
CI legs and the six runs here.

The tempting generalisation — that fixes which change the operation sequence are
the common kind, so cases routinely orphan themselves — is **a hypothesis, and
this record does not measure it.** n is two. Nothing here samples repairs across
targets, and the claim that staging-then-rename is the usual repair for this
defect class is not backed by any artifact in this repository. What can be said
without measuring anything is narrower and still worth filing: **a case pins a
crash point inside a recorded operation sequence, so any fix that changes that
sequence orphans the case, whatever the frequency of such fixes turns out to
be.** That is a property of what a case pins, not of these two targets. The
frequency question is the part that would need a survey.

What this does NOT decide: how v1.0 criterion 1 should be scored. That reading —
whether "kept as a replayed regression case" means the committed transcript or a
CI leg in the timewarrior sense — is an owner adjudication, and re-scoring a
criterion inside a measurement record is the move this repository refuses. What
changes is that the adjudication now has a measurement under it instead of a
choice between two readings of a sentence.

## Finding 2: the guard states a premise the fix falsified

Run 3 is a fresh explore against the fixed build, through the frozen checker, and
it FAILs. The message it printed, quoted from `explore-fixed.txt` as that file
stands:

    new/ or tmp/ is not empty: this operation stages nothing, so 1
    entry/entries there is damage or a shape the define did not declare

**That reason text has since been corrected** (#306, 2026-08-25). The guard now
reports how many entries it found and scopes the premise to the version the
define was measured against, instead of stating "this operation stages nothing"
as a fact about the operation. The assertion is unchanged, so a re-run against
the fixed build still FAILs 2 of 4 — with a message that no longer asserts what
the fix removed. The transcripts here keep the old wording because they record
runs that happened, and the quotation above is of the run rather than of the
file as it stands today.

Read quickly, the old message says himalaya still fails, and worse than before —
2 of 4 worlds rather than 1 of 3. It says no such thing. Separating what the
guard looks at from why it looks:

- **What it checks:** every staging directory, the target's included, is empty.
- **Why it checked that:** io-maildir 0.3.0's `messages copy` was the one arm
  that did not stage. The cohort's own RESULTS.md says so: it "mints the name,
  builds the final path, and fills the file in place."

The second half is an observation of one implementation, and 0.3.1 falsified it.
The guard survives with its reason still printed in the failure message, so the
failure asserts the thing that stopped being true.

The property the define declares is not violated. It asks that the store hold
either the old message set, or the old set plus a **complete** copy in the target
folder. A stray file in the target's staging directory is not in the target
folder, and the checker's own reader leg says so: leg R runs the tool's
`envelope list` in every world, including the two that hold a staged file, and
agrees with what leg D found there — nothing. That is measured for **this**
reader, which is the one the property names. It is not a general claim about what
every maildir reader does with a stale staging entry; that was not measured here.

Run 4 measures that. `check-relaxed.diff` relaxes exactly one assertion — the
target's staging directory may hold at most one entry — leaves the three
directories the operation still does not touch strict, and records both
directories in every world. Run against each target, the instrument prints the
whole difference:

    # 0.3.1, the fixed build — PASS 4/4
    falsification probe: Archive/tmp holds 0, Archive/cur holds 0
    invocation 2: Archive/tmp holds 0, Archive/cur holds 0
    invocation 3: Archive/tmp holds 1, Archive/cur holds 0
      staged:    1787619301.#0M553229678P93.af770025d3f1 (0 bytes)
    invocation 4: Archive/tmp holds 1, Archive/cur holds 0
      staged:    1787619301.#0M564614178P133.af770025d3f1 (307 bytes)
    invocation 5: Archive/tmp holds 0, Archive/cur holds 1
      in target: 1787619301.#0M578209803P173.af770025d3f1:2,S (307 bytes)

    # 0.3.0, the target the cohort measured — FAIL 1 of 3, leg D
    falsification probe: Archive/tmp holds 0, Archive/cur holds 0
    invocation 2: Archive/tmp holds 0, Archive/cur holds 0
    invocation 3: Archive/tmp holds 0, Archive/cur holds 1
      in target: 1787619301.#0M867828553P93.b4f840af8c80:2,S (0 bytes)
    invocation 4: Archive/tmp holds 0, Archive/cur holds 1
      in target: 1787619301.#0M880578970P137.b4f840af8c80:2,S (307 bytes)

**Read the labels before the contents.** The blocks are numbered because there
is one more of them than there are worlds: the engine runs the checker once on
the corrupted state it builds to falsify it before the run, and that is
invocation 1. Five blocks for four explored worlds, four for three. And the
engine does not tell the checker which crash point it is in, so **no block here
names a crash point.** The blocks say what was on disk; the report in
`explore-fixed.txt` says where the kill landed.

The third line of the 0.3.0 block is the finding, stated as bytes on disk: a
message at its final name, carrying the source's flag suffix, holding nothing.
Under 0.3.1 the target folder never holds that state — it holds either no entry
or one of 307 bytes, the source's full length — and the partial states appear in
the staging directory instead, at 0 bytes and at 307.

What those two sizes mean is read off the sizes themselves, not off any world
index: a staged file of 0 bytes is one nothing had been written to yet, and one
of 307 is one whose fill had completed while the rename had not. The engine
supplies the matching half independently — `explore-fixed.txt` names the
earliest violating window under the frozen checker as `after open(…/Archive/tmp/<id>)`
and `before write(…)`, which is a crash point of exactly the first kind.

**The target folder's contents are recorded rather than inferred**, and the
instrument was changed to make that so. An earlier version printed only the
staging directory, and the sentence it supported — "the target folder is empty
in both" — was reasoning from "the checker passed", which is satisfied by an
empty folder *and* by a folder holding the complete copy. Those are different
worlds and the record should not have to guess which.

**PASS 4/4**, with the checker still falsified before the run, so it is not
passing vacuously.

Scope, stated because the run is small: this measures the four worlds this
define explores, under this apparatus, on 0.3.1. It is not a claim that no
crash-consistency defect remains anywhere in io-maildir's copy path.

`check-relaxed.diff` is a measurement instrument and is committed as a diff
rather than as a file, so it cannot be mistaken for a second checker. **The
frozen checker's assertions are not changed by this record.** Whether they
should be, and what that costs against the freeze, is a separate decision — the
define is frozen material and this is a measurement.

**The diff was regenerated on 2026-08-25 and the instrument was not.** #306
corrected the reason text the guard prints, which moved the lines this patch
removes, so the patch stopped applying. What it produces is unchanged, and that
is checked rather than asserted: applying the regenerated diff to the corrected
`check.sh` yields a file byte-identical to the one the transcripts were produced
with, reconstructed by applying the previous diff to the previous `check.sh`.
The instrument's own header still quotes the pre-correction wording, deliberately
— it describes what it was relaxing at the time it ran.

### Where else the same shape lives

The class is "a checker's failure message states a premise about the target's
implementation, and the target can change underneath it." Scanned across every
committed cohort checker:

    grep -rn 'fail "' spike/cohort*/*/ops/check.sh |
        grep -iE 'this operation|does not|should not|cannot|never |always |stages|is not able|could not have'

The pattern was widened once, after review. A narrower first version omitted
`should not` and missed the leg-C conservation line in both himalaya checkers —
a premise about the operation, stated in a failure message, that the scan was
supposed to reach. The count below is from the widened pattern.

**18 checkers, 18 hits in 6 files**, classified rather than counted:

- **Falsified, 2 lines.** The staging guard is in **two** files, not one:
  `spike/cohort4/himalaya/ops/check.sh:100` and `spike/cohort4/himalaya-r2/ops/check.sh:100`.
  The two files are byte-identical, which is what the r2 record says of them
  ("the property, the checker, the setup and the fixtures are r1's, byte for
  byte") and what `diff -q` confirms. r1 never reached a verdict, but the
  premise is committed twice.
- **Same shape, still true, and measured so — 8 lines.** The store-root,
  source-folder and one-copy guards, and leg C's "the operation should not have
  been able to remove it", in both files. Run 4 kept every one of them strict
  against the fixed build and passed, so they were exercised rather than assumed.
- **Same shape, not measured — 1 line.** `spike/cohort3/papis/ops/check.sh:84`.
  Same construction. Whether papis has changed underneath it was **not checked**;
  the honest statement is that the exposure exists and was not measured, not that
  nothing upstream has moved.
- **A different class — 7 lines.** Assertions about a parse (`does not parse`),
  a resolution (`metadata does not resolve it`), or an observed failure (leg R's
  "the reader cannot read it back") rather than a premise about what the
  operation does.

## Reproducing

Prerequisites: the `sideeye-cohort4` image built from `spike/cohort4/Dockerfile`
with its artifacts fetched, and the engine cross-built for the container's
architecture from the repository root:

    zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-linux-gnu

**The build context**, assembled outside the repository so the frozen artifacts
are never edited in place. `$C4` is `spike/cohort4`; `$B` is any scratch
directory:

    cp -R "$C4/artifacts/himalaya-src"                     "$B/himalaya-src"
    cp    "$C4/artifacts/rust-1.98.0-aarch64-unknown-linux-gnu.tar.xz" "$B/"
    cp    "$PWD/spike/cohort4/himalaya-r2/upstream-fix/Dockerfile"     "$B/"
    printf 'target/\n.git/\n' > "$B/.dockerignore"

    # apply Cargo.lock.diff — two lines, io-maildir's version and checksum
    ( cd "$B/himalaya-src" && patch -p0 < "$PWD/spike/cohort4/himalaya-r2/upstream-fix/Cargo.lock.diff" )

    # re-vendor. --locked is the check: it fails if 0.3.1 needs any other
    # crate to move, which would make the delta larger than the two lines.
    ( cd "$B/himalaya-src" && cargo vendor --locked "$B/vendor" > /dev/null )

    docker build -t sideeye-cohort4-fixed "$B"

The build stops at the digest layer if `himalaya-src` is not the frozen tree
plus exactly that lock, so a mistake in the two steps above is a build failure
rather than a silently different measurement.

**The runs**, from the repository root. `$U` is
`spike/cohort4/himalaya-r2/upstream-fix`:

    # runs 1 and 2 — the saved case, against each target
    docker run --rm -v "$PWD":/work -v "$PWD/$U":/driver:ro \
        sideeye-cohort4       sh /driver/run-replay.sh
    docker run --rm -v "$PWD":/work -v "$PWD/$U":/driver:ro \
        sideeye-cohort4-fixed sh /driver/run-replay.sh

    # run 3 — a fresh explore against the fixed build, frozen checker
    docker run --rm -v "$PWD":/work sideeye-cohort4-fixed \
        /work/spike/cohort4/himalaya-r2/ops/explore.sh --json /tmp/report.json

    # runs 4 and 5 — the same explore through the relaxed instrument.
    # The ops directory is copied and patched; the frozen one is not touched.
    cp -R spike/cohort4/himalaya-r2/ops "$B/ops-relaxed"
    ( cd "$B/ops-relaxed" && patch -p0 < "$PWD/$U/check-relaxed.diff" )
    for img in sideeye-cohort4-fixed sideeye-cohort4; do
        docker run --rm -v "$PWD":/work -v "$B/ops-relaxed":/ops-relaxed:ro "$img" \
            sh -c 'sh /ops-relaxed/explore.sh --json /tmp/r.json; rc=$?;
                   echo; cat /tmp/relaxed-evidence.txt; exit $rc'
    done

    # run 6 — the functional control, on both targets
    for img in sideeye-cohort4 sideeye-cohort4-fixed; do
        docker run --rm -v "$PWD":/work "$img" \
            sh /work/spike/cohort4/himalaya-r2/upstream-fix/functional-control.sh
    done

**Checking run 1's claim** needs no container:

    sh spike/cohort4/himalaya-r2/upstream-fix/verify-positive-control.sh
