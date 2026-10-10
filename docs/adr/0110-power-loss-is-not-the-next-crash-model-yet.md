# 0110 — Power loss is not the next crash model yet

- **Status:** Accepted (2026-10-10)
- **Refs:** #699 (from the 2026-10-05 whole-product review); DESIGN §9 "The crash model,
  precisely", §4.3, §4.5, §21; PRD "Out of scope through 1.0".
- **Scope:** a decision only. Nothing in the engine, the report or the contract changes.

## Context

Sideeye's crash is a process crash: the operating system survives, and every write the process
completed is durable (DESIGN §9). Power loss — unsynced data lost, writes reordered — is outside
that model, and a PASS says nothing about it; the `not tested` line of every verdict names power
loss and torn writes first. PRD put it "first in line for *consideration* after 1.0". 1.0 shipped on 2026-08-29, and
nothing since has accepted or declined it.

The class it would catch is real. A tool that writes a temporary file and renames it over the
original without `fsync` PASSes today, and under power loss can leave the new name pointing at
nothing written — the shape behind ext4's zero-length files of 2009, which ext4 answered with
`auto_da_alloc` for exactly that rename. Neighbouring tools model it: ALICE, LazyFS, SQLite's
crash test (a random subset of unsynced writes survives), dm-log-writes.

## Decision

**Not now.** The process crash stays Sideeye's only crash model.

Two reasons are known:

1. **The world it needs is not one the engine can produce.** The engine makes a world by running
   the operation to crash point *k* and killing it; whatever the filesystem then holds *is* the
   world, and nothing is simulated (DESIGN §9: "no filesystem simulation is required"). A
   power-loss world is that state with every file put back to its content at its last sync and
   every directory entry to its directory's last sync — content from earlier points, recorded or
   rebuilt, and composed. That is a filesystem model, not another crash point.
2. **The answer depends on the filesystem.** ext4 (its `auto_da_alloc` and `data=` mode), XFS,
   btrfs and APFS each keep more than POSIX promises, in different places. A counterexample built
   from the POSIX minimum happens on some filesystems and cannot on others. The report would have
   to name the model and the filesystems it speaks for, or a FAIL would claim more than happened
   (§4.5) — and "Reproduce in 3 steps" (§4.3) would hold inside Sideeye and not on the user's
   machine.

Two are unknown, and they are what would reopen this:

3. **Whether a power-loss model separates targets or fails nearly all of them** — and the answer
   depends on how its world is built, which is not decided either. If nearly every target fails,
   the mode is a lint in a counterexample's clothes (§4.3). The committed record says how the
   PASSing targets write, not what they would do: the exploration reports (`explore.json`) carry
   verdicts and judged paths, not the operation sequence, but the outcome funnel's notes say, for
   thirteen targets that PASSed, whether they sync. Five sync nothing (python-dotenv, libdeflate,
   ifcpatch, atac, rpk). Eight sync the file with `fsync` or `fdatasync` (bzip3, juju, aliyun-cli,
   kitty, cook, buildx, skopeo, samtools); of those, the committed strace traces of six show no
   directory sync after the rename or unlink that follows (bzip3 in
   `spike/dogfood/2026-10-03-user-data/`, juju, aliyun-cli and skopeo in `…-10-05-user-data-2/`,
   cook and buildx in `…-10-09-user-data-4/`), kitty has no trace, and samtools rewrites its file
   in place (checked 2026-10-10). What that turns into is the model's choice. Where everything
   unsynced reverts — the rule below — a tool that syncs nothing but replaces by rename keeps its
   old file and passes, and what can fail is an update the tool announced as done (a declared
   marker) being lost wherever the directory was not synced: eleven of the thirteen (twelve if
   kitty, untraced, is like them), for the defines that declare one. Where any subset of unsynced operations may survive — SQLite's crash
   test — the rename can outlive its data, the 2009 shape, and the five that sync nothing are the
   candidates. So the count is not yet one number, and choosing the model comes first.
4. **Whether an upstream acts on a missing-`fsync` finding.** None has been reported from
   Sideeye — the model cannot produce one. One is open elsewhere:
   [theskumar/python-dotenv#713](https://github.com/theskumar/python-dotenv/issues/713), filed by
   that project's maintainer on 2026-10-01 ("set_key and unset_key don't fsync before replacing
   the .env file"), open with no comments when this was written, and recorded in the outcome
   funnel as the reason python-dotenv left the slate (rule 14). How it ends is the first evidence
   for this reason. (The funnel's one `not_worth` row that mentions `fsync`, dotenvx's leftover key
   file, is a process crash inside an `fsync` window: this model's finding, not that one's.)

**Reopen** when any of these happens: a re-run of the committed defines shows the rule below
separates targets rather than failing nearly all of them, once a model is chosen — the traces
above are where to start;
someone asks for it in an issue, for a tool they maintain or use; an upstream accepts and ships a
fix for a missing-`fsync` report made by anyone, python-dotenv#713 being the one open now.

## The rule a reopening starts from

Recorded so that the next decision begins where this one stopped. It is #699's candidate — a guess
to be argued, not a design:

- each file reverts to its content at its last `fsync` or `fdatasync`;
- a create, rename or unlink is durable only once its directory has been synced;
- the report names the model a verdict was judged under;
- it stays a counterexample — a world, kept and replayable — not a warning (§4.3).

Which call counts as a sync is a decision of its own: on macOS, `fsync` does not flush the
device's cache and `fcntl(F_FULLFSYNC)` does, so the rule as written would let a macOS PASS claim
more than happened (§4.5).

The trace already records `fsync` as an operation the engine can kill at (`OpClass.isKillPoint`
in `src/contract.zig`), so the boundaries the rule speaks of are observed today. What is missing is
the world.

## Alternatives considered

- **Open it now, with the rule above.** Pays reasons 1 and 2 without knowing 3 or 4.
- **Measure reason 3 first, then decide.** The owner ruled on 2026-10-10 to decide now; the
  measurement is the first reopening condition instead.

## Consequences

- DESIGN §9's sentence — power loss is "outside this model, and a PASS says nothing about" it —
  stays true and unchanged, and the `not tested` line keeps naming power loss and torn writes.
- PRD's "first in line for *consideration* after 1.0" has happened: it was considered and declined
  for now. PRD and DESIGN §21 point here.
- DESIGN §21 lists its candidates "in no committed order", which PRD's "first in line" had
  contradicted. §21 keeps no order; its power-failure line names this ADR.
