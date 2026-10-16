# Card — quilt 0.68-1, `quilt push -a`

**Operation.** In a source tree whose `patches/series` names two patches, each changing a different
file, `quilt push -a` applies both.

**Documented contract** (quilt(1), "push", "pop"; the `.pc` directory): `.pc/applied-patches`
lists the patches applied to the working tree, in order, and `.pc/<patch>/` keeps each file the
patch touches as it was before the patch, which `quilt pop` restores.

**Legs.**

- **(a) Applied means present.** Every patch `.pc/applied-patches` lists has its changes in the
  working files. *Broken alone:* `.pc/applied-patches` lists p1 while the file p1 changes still
  holds its original content.
- **(b) Present means applied.** No patch it does not list has its changes in the working files.
  *Broken alone:* the file p2 changes holds p2's change while `.pc/applied-patches` lists p1 only.
- **(c) The undo works.** `quilt pop -a` exits 0 and leaves both files as they were before the
  operation. *Broken alone:* `.pc/p1.diff/` holds a backup whose content is not the original, so
  the files are consistent with `applied-patches` but `pop` restores the wrong bytes.

**Admissible after a crash:** any prefix of the push — none, p1, or both applied — with the files
and `.pc` agreeing. A `.pc` directory with a partial backup for the patch being applied is
admissible only if `quilt pop` or a repeated `quilt push` leaves the tree in one of those states.

**Not claimed:** quilt's handling of fuzz or rejected hunks; anything about `quilt refresh`.
