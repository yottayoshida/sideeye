# 0091 — An exploration in which nothing could fail is UNKNOWN, not PASS

- **Status:** Accepted (owner ruling 2026-10-06)
- **Amends:** `docs/contract-freeze.md` surface 2 (`unknown_reason` gains `nothing_could_fail`,
  34 → 35 members) and surface 3 (which runs exit 0 and which exit 2), each recorded there as a
  dated amendment. ADR 0008's Alternatives entry "Judging post-only file contents" stands; see
  Alternatives below.
- **Refs:** #682, #683 (filed from the 2026-10-05 whole-product review); #487 (the one-crash-point
  clause this extends); ADR 0032 (`reconcile`, whose two-spelling join this reuses); ADR 0040
  (a refusal's next step is chosen where the cause is known); ADR 0079 (`l0_judged_paths`).
- **Scope:** `src/contract.zig`, `src/engine/snapshot.zig`, `src/engine.zig`, `src/refuse.zig`,
  `src/report.zig`, `src/main.zig`, `spike/acceptance.sh` and the CI legs that expected the old
  answer, `README.md`, `spike/check-readme-shape.sh`, `docs/`.

## Context

The README refuses to trust a checker it has not seen fail: "A checker that cannot fail makes
the run UNKNOWN, not PASS." The built-in invariants were not held to the same rule, and two
shapes of PASS followed from it.

1. **No crash point** (#682). An operation that changed nothing inside `--state` PASSed with exit 0:
   "the operation performed nothing that can change the judged state". Measured on v1.8.0: a toml
   in a subdirectory, run from its parent, whose operation wrote `./state/out.txt` — relative to
   the caller, not to the toml — into an unrelated directory; the judged root stayed empty and the
   run PASSed. The same with `state` naming a regular file. `docs/scouting.md` called this PASS
   the tell for a store outside `--state`; `docs/outcome-funnel.md` already refused to count it as
   a verdict. The exit code was the one place that did not say so, and a CI job reads the exit code.
2. **Crash points, nothing judged** (#683). The pre-or-post rule judges a path both snapshots hold.
   An operation that only creates files, with no checker and no marker, ran its worlds and PASSed
   "N/N explored worlds satisfied the built-in atomicity invariant" over nothing — and a run whose
   judged paths were files the operation never wrote (ggshield, "PASS 6/6 over files it did not
   write") was the same PASS with a non-empty list beside it.

In both, no world could have failed. The verdict was true of any target.

## Decision

1. **An exploration in which no world could have failed is UNKNOWN `nothing_could_fail`.** A world
   could have failed when at least one of these holds:
   - a checker was declared (it passed falsification, so it runs in every world);
   - a crash world printed the marker **and** some non-scratch entry is held by only one snapshot
     — the post-success invariant's own ground. It also compares shared paths against the post
     content, but a shared path nothing touched holds that content in every world;
   - some path the atomicity invariant judges is **touched**: it ended other than it began, or a
     crash point named it — `fsync` and `mkdir` aside — or a `rename` named a directory above it.

   No crash point at all is the first case of this, whatever was declared: a checker has no world
   to run in.
2. **Touched is a union, and each half has a reason.** "Ended other than it began" is free and
   independent of spelling, and it catches a change no kill point names (a raw write whose path a
   `close` record named, which `reconcile` accepts). "Named" catches the rewrite with the bytes the
   file already held — `chezmoi apply --force`'s shape — which a difference alone would miss and then
   refuse a run whose torn rewrite was exactly what the atomicity invariant can catch. Naming goes
   through `reconcile`'s two spellings (`relUnderRoot`, `resolveThroughLinks`), so an operation
   spelled through an interior symlink names what it reached. **A record on a link itself names the
   link**: `unlink`, `rename`, `link`, `symlink`, `rmdir` and `mkdir` do not follow a final symlink, so
   only the directories above their last component are resolved (`resolveForRecord`). Resolving the
   whole path counted the targets of links a run only made or removed as touched — the stow shape —
   and, in `reconcile`, let the record that made a link account for a change at its target that nothing
   recorded; both are fixed here, the second as the same class of defect (R1 of the diff).
3. **`fsync` and `mkdir` never count, and only a `rename` counts from above.** Each was found as a way
   to call an untouchable path touched: under the process-crash model `fsync` changes nothing; a
   `mkdir` on a judged path cannot succeed while it is there, and the shim records it before it knows
   (`os.makedirs(…, exist_ok=True)` leaves one per component); above a path, `unlink` and `open` fail
   on a directory, `rmdir` needs it empty, and a parent's `fsync` is the commonest record of all. The
   root (`rel` "") is not a judged path and is no one's ancestor here.
4. **Where it is raised.**
   - No crash point, in `explore`: where the PASS was, **after** the completeness gate. With no oracle
     and no records, the shim's word is all there is — a raw syscall that rewrote a file with its own
     bytes changes no snapshot and leaves no record — and acceptance check 2f pins that the weaker
     claim is the caller's to accept first. Under `--allow-unverified` the detail says so.
   - No crash point, in `preflight`: the README promises preflight refuses with the detector a real run
     would use. Before `--twice`'s second run, which would only measure the repeatability of nothing.
   - Crash points: after every world, immediately before the PASS is printed. A world may take a branch
     the recording did not, and a FAIL there exits first; moved ahead of the worlds, this would refuse a
     run that had a counterexample to show.
   - **Not for a replay.** Its one world answers whether that world still fails. A FAIL fixed by moving
     the marker after the last operation leaves the replayed world with no marker and nothing touched,
     and the answer "it no longer fails" is true; refusing it would break replay's main use.
5. **Three next steps, chosen at the site** (ADR 0040): `nothing_in_state` (no crash point — where an
   undeclared define's commands run, `cwd`, and that a deliberately inert operation has nothing to
   test), `declare_check_or_marker`, and `declare_check` (a marker was declared and judged nothing, or
   there is nothing created or removed outside scratch for one to judge).
   **What `preflight` names without an oracle differs from `explore`**: preflight makes no PASS claim and
   has no completeness gate, so a recording with no crash point is refused `nothing_could_fail` there
   either way, with the detail saying no oracle ran; `explore` asks for the oracle (or
   `--allow-unverified`) first. With either, the two name the same reason.
6. **A PASS whose atomicity invariant compared nothing a crash could change says so.** Such a PASS
   reaches the print only because a checker, or the marker, judged the worlds. The headline keeps its
   claim, which is true — the invariant held — and gains a clause on the same line: ", but the
   operation touched none of the N path(s) it judged" (or ", but it had no path to judge"). The JSON
   carries the count as `l0_judged_paths_touched`, after the two fields it qualifies, measured once every
   check on the trace has held. A replay's PASS carries both: they do not move the verdict, and a
   replay's PASS — not gated — can carry zero with neither a checker nor a marker.
7. **A `state` that exists and is not a directory is SETUP ERROR `define_invalid`**, raised right after
   it is resolved and before anything runs (#682). It used to snapshot as an empty tree.

## Alternatives considered

- **Leave the PASS and change the words** (owner, 2026-10-06: not taken). The headline and a `next`
  line would say "nothing judged", and every caller that reads the exit code — the CI quickstart is
  built on exactly that — would still go green.
- **Refuse only an empty judged set.** ggshield's shape, judged paths the operation never wrote,
  would stay a PASS, and #683's own evidence would not move.
- **Decide "touched" from the snapshots' difference alone.** Refuses the same-bytes atomic rewrite,
  which the atomicity invariant can catch going wrong.
- **Match a parent directory for any operation.** One `mkdir(state)` or `fsync(parent)` would make every
  path below it touched, and the shapes this rule exists for would PASS again.
- **Raise the no-crash-point refusal ahead of the completeness gate**, to spare a macOS user two
  refusals in a row. Taken in the plan's first round and withdrawn in its second: without an oracle
  "nothing could fail" is not established, and check 2f holds that order on purpose.
- **Judge what the operation created** (post-only contents) with the atomicity invariant. ADR 0008
  rejected it because those contents may differ between clean runs, and that reason still holds: the
  baseline world's byte comparison runs over the judged set, so a created file's bytes are compared by
  nothing today. It would be a new promise, not this one.
- **Apply the rule to replay** — see Decision 4.

## Consequences

1. `unknown_reason` has 35 members. `docs/contract-freeze.md` records the break; the
   `surface-changes.tsv` row waits for the next sweep, as the two before it did. `contract_version`
   does not move.
2. Some runs that exited 0 exit 2: every zero-crash-point exploration and preflight, and every
   exploration with no checker, no marker world over a created or removed path, and no touched judged
   path. **A read-only control row has a user**: topydo's `ls` was used as a zero-operation PASS
   control (BUILDLOG 2026-08-16); such a row now answers `nothing_could_fail`. Records taken before this
   are left as they were — they are what that engine said.
3. The MCP tool reports these runs with `isError: true` (refusals are errors there, ADR 0010).
4. **A floor, not a guarantee.** A crash point that names a judged path without changing it still
   counts as touched: a lock file opened for writing (CI's `clone-plus` and `swap-out` legs are
   examples), a call that failed, a `truncate` to the length the file has, a `link` whose source is the
   judged path. Those runs PASS as before, with no clause. Whether the five targets #683 cites now
   refuse was not re-measured.
5. The rule reads what the recording recorded. Under `--observe supervised` the records are written
   before the call, like the shim's, and the root's two spellings are the same ones `reconcile` uses.
