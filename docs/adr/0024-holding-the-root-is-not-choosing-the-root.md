# 0024 — Holding the root is not choosing the root

Status: Proposed

## Context

The engine's one genuinely destructive act is emptying the state directory, and it runs
once per explored world — hundreds of times in a single run. Three defences stand in front
of it, and they were written at different times:

- **`assertSafeRoot`** (a depth rule plus two denylists, read inwards — and outwards as well since #358) refuses a root that *names* a place
  nothing sacrificial belongs in. Lexical only.
- **`assertRootResolvesToItself`** (#267) re-resolves the root immediately before the delete
  and requires it to resolve to itself. Its own doc says it narrows the swap window to the
  two syscalls between the check and the `opendir`, and that the window stays open.
- **The walk itself** reached everything by pathname: `opendir`, `unlink`, `rmdir`.

#327 asked for the fourth: hold the root open by descriptor and reach every entry through
`openat`/`unlinkat`.

**Which window that closes needs saying precisely, because an earlier draft of this
paragraph said "the window" and meant the wrong one.** It does not close the check-to-open
race defined just above; the check and the open are still two syscalls. It closes the
window from the open to the end of the walk — which is where every entry used to be
re-resolved by name, once per entry and once per pass, so a resident racer got as many
attempts as the tree had entries. That is the larger of the two by a wide margin, and it is
what stops the retry count belonging to whoever can flip a symlink.

The question this ADR settles is not whether to do that. It is **what the descriptor
replaces**, because two separate notes in the codebase said it replaced something, and both
were wrong in the same way.

## Decision

**The descriptor is added. Neither guard is retired.**

`O_NOFOLLOW` applies to the final component only. With root `/a/b/state`, replacing `/a/b`
with a symlink leaves `open("/a/b/state", O_DIRECTORY|O_NOFOLLOW)` succeeding on a different
tree — which the new walk would then empty race-free and thoroughly. The resolution check
covers exactly that case, and says so in its own doc. Retiring it would have been a pure
loss dressed as a simplification.

**The denylist's sunset note is corrected rather than obeyed.** It read:

> delete this list once the destructive path holds the root open by descriptor
> (openat/unlinkat), which closes the swap window that `assertRootResolvesToItself` only
> narrows.

The list's stated purpose, three lines above that note, is to stop "the mistake that has a
name — a system path where a scratch path was meant". Holding `/etc` by descriptor deletes
`/etc` just as completely. Closing the swap window discharges nothing the list provides:
**pinning identity and picking the right target are different properties**, and the note
treated one as the other.

A second consumer makes this structural rather than a judgement call: `src/mcp.zig` runs
`assertSafeNamingRoot` on `SIDEEYE_MCP_ROOT` at startup (it ran `assertSafeRoot` until
#329 split the two predicates), where it vets a **name** and no delete
follows it at all. A sunset phrased around deletion would have authorised removing a guard
that a naming boundary still depends on.

The replacement condition names both consumers:

> Delete this list when neither consumer can be handed a mistyped location — (1) the
> destructive root stops being a hand-written value, which means both of its arrival paths
> (`--state` and a case's `define.state`) become engine-derived; and (2) the startup vet in
> `mcp.zig` no longer needs a name-based refusal. Closing the swap window is not this
> condition.

`SIDEEYE_MCP_ROOT` and `--state-under` are deliberately **not** arrival paths in that
condition. They constrain where a destructive root may resolve and never supply one, and
listing them among the places a root comes from would repeat, inside the correction, the
exact conflation the correction is about. A first draft of this ADR did list them.

## Alternatives considered

- **Retire `assertRootResolvesToItself`** — rejected on the parent-component case above.
  This was the plan of record until first-look review, and the argument for it ("the
  descriptor is strictly stronger") was true of one component and false of the path.
- **Obey the sunset note and delete the denylist** — rejected. It would have removed the
  only defence against a mistyped root at the moment the batch made that defence look
  redundant, and would have silently weakened MCP startup vetting, which has no delete
  behind it.
- **"Delete the list once an override flag makes a wrong entry a warning"** — rejected, and
  worth recording because it contradicts the paragraph three lines above it: `/opt` and
  `/srv` are *absent* from the list precisely because there is no override flag, so a wrong
  entry is a wall. By that reasoning, an override flag arriving is a reason to *list* those
  trees, not to drop the list. The same event, two opposite conclusions.
- **"Delete the list once the corpus measures zero accidents"** — rejected. A guard whose
  job is to make an accident impossible cannot be retired by the accident not happening;
  that measurement cannot distinguish "the guard works" from "nobody tried".
- **A per-component walk for `restore`'s rebuild** — deferred. Entry paths are
  multi-component, and **both their intermediate components and the final component of a
  file write** are still resolved by name: `openat(fd, rel, O_WRONLY|O_CREAT|O_TRUNC)` in
  `restore`, and the same shape in `corruptState`, carry no `O_NOFOLLOW`. Saying only
  "intermediate" would let a reader conclude the final component is covered, since
  `openRootDir` and `deleteTreeAt` both use the flag. Those directories and files were
  created by the same loop moments earlier, and the root — the part an attacker can reach
  between worlds — is pinned, so what remains is a race measured in syscalls rather than
  the once-per-entry, once-per-pass window that was closed. Stated rather than claimed
  closed.
- **Comparing device and inode across the check and the open** — filed, not done, and this
  ADR is where it stops being free-floating. `assertRootResolvesToItself`'s doc named it
  before this change as the fix for the bind-mount case and marked it "needs that pair
  threaded from the call site". **Holding the root open makes it cheap**: one side of the
  comparison is now an open descriptor, so it is a `stat` at resolution time, an `fstat`
  after `openRootDir`, and one struct threaded through. It would close the check-to-open
  race outright — a swap in that window changes the inode — and would catch a bind mount
  established inside the window, though not one established before the check. Deferred
  because it is a second mechanism with its own error mapping and its own falsification,
  and this change already replaces the walk; recorded here so the residual is not read as
  expensive when the change just made it cheap.
- **An open-probe for the `DT_UNKNOWN` fallback** — rejected. `opendir` passes `O_NONBLOCK`
  and a hand-rolled `openat` does not; this project already retired an open-probe for that
  reason, after a FIFO with no writer blocked one forever (#5 R1). The fallback uses the
  descriptor-relative form of the existing `fstatat` classifier.

## Consequences

- The swap window on the destructive path is closed for the delete, the rebuild and the
  corruption probe: all three run through one descriptor taken once per call.
- `restore`'s `mkdir` of the root moves from *after* the delete to *before* the open. Once
  the descriptor is held, a `mkdir` on the pathname would create a different directory than
  the one every later `mkdirat` is pinned to.
- **A visible reclassification:** a regular file where the state directory should be now
  refuses as `UnsafeRoot` rather than `DeleteFailed`, because the open returns `ENOTDIR`.
- One `open`, two readings of `ENOENT`: `deleteTree` has nothing to delete and returns,
  while `freshDir` has already failed its `mkdir`, so absence there is a missing parent and
  stays loud. Neither call site may inherit the other's reading.
- `fdopendir` takes ownership of the descriptor it is given, so the walk hands it **neither
  the root descriptor nor a `dup` of one**. Both are wrong, for different reasons, and the
  second is the trap:
  - Handing over `dirfd` itself means `closedir` closes the descriptor the rebuild then
    writes through. Loud, and pinned by the existing `restore`/`corruptState` tests.
  - Handing over `dup(dirfd)` **shares the open file description, and with it the read
    offset**. `fdopendir` does not rewind, so the second pass of the reopen loop resumes
    where the first stopped, reads nothing past the tail, and the `count == 0` branch takes
    that for an empty directory — returning success over a directory it did not drain.
    Measured on macOS: 144 of 400 entries left behind, no error. `removed < count` cannot
    see it, because every entry that was *collected* was removed; the loss is in the
    collection. This shipped in the first implementation and was found in review.
  - What the walk takes is `openat(dirfd, ".", O_RDONLY|O_DIRECTORY|O_CLOEXEC)`: a fresh
    description at offset zero on every pass, which is the property the pre-descriptor
    `opendir(path)` supplied and the only part of it this rewrite had to keep. A test
    drains a directory past the 256-entry collection bound and counts what is left.
- Descriptor use goes from O(1) to O(depth), bounded by `max_depth` (32).
- `O_CLOEXEC` is set on the root descriptor. It is **not** load-bearing today: `runChild*`
  is only reached after the destructive calls return, so no fork happens while the root is
  open. That ordering is what makes its absence safe and it is written down nowhere else.
