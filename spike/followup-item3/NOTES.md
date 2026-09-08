# item 3 pre-measurement — what strace actually shows around a writing child

Ran 2026-09-08, before the plan was finalised, with the engine's own oracle flags
(`strace -f -y -e trace=%file,%desc,%process,setsid,setpgid`, strace 6.1, aarch64,
`sideeye-spike:latest` for the C toys and `sideeye-reach:2026-09-07` for `pass`).

## The shapes the design rests on exist

- **serial.c** (parent writes a, forks a child that writes b, waits, writes c):
  `28 wait4(29, <unfinished ...>` … child 29's three lines … `28 <... wait4 resumed>…) = 29`.
  The child's whole lifetime sits inside one unfinished wait.
- **sys.c** (`system("printf s > …")`, whose spawn and wait never touch the PLT):
  the same shape — `49 clone(… CLONE_VM|CLONE_VFORK …) = 50`, `49 wait4(50, <unfinished ...>`,
  child 50's write, `49 <... wait4 resumed>) = 50`. **strace sees what the shim cannot**, which
  is why the serialisation evidence belongs to the oracle rather than to a wait wrapper.
- **pass mv** (the slice's poster child): in-scope writers are `mv` (pid 55, `renameat2`) and
  `rmdir` (pid 77, `unlinkat`, which returned ENOTEMPTY and so mutates nothing). Their
  lifetimes are **disjoint**, the subject performs **no** in-scope mutation inside either, and
  the subject is **blocked in an unfinished `wait4(-1, …)`** across each of them. Matches the
  2026-09-07 measurement (`~/.cctmp/reach-ugxdCF/m3.out`), which found the same two writers.

## Two conditions, not one — and each one is needed against a measured counterexample

- **conc.c** (two children forked before either is awaited) shows why "the parent was
  blocked" is not enough on its own: the subject IS blocked in `wait4(39, <unfinished ...>`
  while pid **40** runs and writes too. The lifetimes of 39 and 40 **overlap**, and that is
  the condition that refuses it.
- The reverse case is why blocking is needed at all: a parent that runs concurrently with a
  writing child could write in either order between runs.

So the rule needs both a window and something inside it — but **neither of the two forms
above is what shipped**, and this note is corrected rather than left standing.

What shipped (contract v15, ADR 0053) asks, for each writing child: from the `clone` that
returned it to the wait that reaped it, did any other process perform a state-directory
operation? Two differences from the sentence this paragraph first carried:

- **Not "lifetimes", write intervals — and then not those either.** A process's lifetime is
  not containable in a parent's wait: the capture above shows the child running before the
  `clone` that names it has even resumed. And a write interval cannot be read from the
  trace, where a parent's records always straddle its children's. The window is the child's
  creation to its collection, both read from the oracle's own line order.
- **Not "the parent was blocked".** The `pass` measurement above is why: a shell blocks in
  `wait4` for a foreground command and reaps a pipeline stage with `WNOHANG` afterwards, so
  a blocking requirement would admit a target on one run and refuse it on the next.

The counterexample this note recorded — "a parent that runs concurrently with a writing
child could write in either order between runs" — is what the creation-to-collection window
answers, and the first implementation of the rule got it wrong by starting the window at the
child's first write instead. Review caught that; `TOY_PARENT_WRITES_IN_WINDOW` is the toy
that now measures it.

## A false alarm worth recording

A first pass of the analyser called `pass` a three-writer target with the parent running
through the third one's lifetime — which would have killed the design. It was wrong: the
third "writer" was `find` writing **to a pipe** a string that happened to contain the store's
path, and two of the subject's "mutations" were `dup3` calls naming a store descriptor.
Scope has to be decided from the path argument or from the `-y` annotation of the descriptor,
never from a path that appears anywhere in the line — the same rule the engine's oracle
already follows, and the same trap the symlink exclusion exists for (ADR 0006).

Files: `serial.c`, `conc.c`, `sys.c`, `run.sh`, `pass.sh`, `an.py` (the loose first pass),
`an2.py` (scoped), `out/*.strace`.
