# ADR 0006 — The oracle resolves paths by type, and links become first-class

- **Status:** Accepted (2026-08-11)
- **Supersedes:** nothing. Replaces the whole-line scope scan added in v0.1 with a typed
  resolver; extends the addressed operation set of ADR 0003 with the link family
- **Scope:** the oracle's scope decision and the shim's two-path `observe`; a new
  `OpClass.link`; trace contract v5 → v6

## Context

With stdio observed (#32), the first two real targets measure — and git's account stops
diverging on `COMMIT_EDITMSG` and diverges one wall later, on
`mkdirat(AT_FDCWD</g1/repo>, ".git/objects/cc", …) = 0`. The path is relative, the
return value is 0 (no result-fd annotation), and no absolute state-directory string
appears anywhere on the line. `touchesStateDir` scans the whole line for such a string,
finds none, and declares the operation out of scope. The shim records it — it resolves
the path against the process cwd — so the accounts diverge and the run refuses. This is
a fail-open of the tool's central promise (*refuse what you cannot see*): the operation
was seen, and silently dropped from scope. The same shape is what makes todoman's
`linkat` refuse (#31), and the whole-line scan has a matching false-positive: a
`write(1, "/tmp/state/x")` whose buffer merely contains a state-directory string is read
as touching the state directory.

Measured before decided (2026-08-11):

- **aarch64** (the dev container): every relative call is an `*at` syscall, and
  `strace -y` annotates `AT_FDCWD</current/dir>` per line, tracking relative `chdir` and
  `fchdir` both. The line resolves on its own.
- **x86-64** (CI): glibc 2.36's `mkdir`/`link`/`unlink`/`rmdir`/`symlink`/`chdir` are
  generic (`syscalls.list`) and issue the legacy syscalls; `rename` prefers `__NR_rename`.
  Confirmed in the glibc source, because qemu-user cannot be ptraced to measure it. The
  line is `mkdir("state/sub", …)` with no annotation, and the cwd must be tracked.
- `openat2` annotates and positions its path exactly as `openat` does.

## Decision

### 1. A typed argument table is the only scope authority

Every syscall the oracle judges falls in exactly one bucket:

- **Path syscalls** carry a table of path arguments: `*at` forms as `(dirfd_idx,
  path_idx)` pairs (`renameat`/`renameat2`/`linkat` have two; `symlinkat` has one — its
  first argument is the link *content*, not a path to resolve), legacy forms as plain
  path positions (`open`/`creat`/`mkdir`/`rmdir`/`unlink`/`truncate`/`link`/`rename`/
  `symlink`/`chdir`). Scope is decided from the **resolved** paths only.
- **Fd syscalls** (`write`, `pwrite*`, `writev`, `fsync`, `fdatasync`, `close`,
  `ftruncate*`, `fchdir`) read only their `<fd>` annotation. Never the quoted arguments —
  which is what stops a state-directory string inside a write buffer from being read as
  scope.
- **Everything else** falls to the old whole-line scan, kept solely as a conservative
  net. That path routes only to `unsupported`, so a false hit refuses; it never passes.

A path is resolved by: absolute → `normalizePath`; relative → the `dirfd` annotation if
present, else the tracked cwd. Containment is tested against **both** the canonical
state directory and its alt spelling (the oracle was handed only the canonical one
before this change — a gap that relative resolution would have widened). A relative path
that cannot be resolved — the cwd is unknown, or there is neither annotation nor cwd — is
**not** dropped: for a non-read-only syscall it becomes `unsupported` from the subject
and `child_touched` from a child. Unseen is never read as untouched.

### 2. The cwd is tracked, from the engine's and the subject's own steps

`parse` receives the engine's initial cwd. The **subject's** `chdir` that succeeds
(`= 0`) updates it (a relative `chdir` resolved against the current value); `fchdir`
updates it from the descriptor's annotation. A child's `chdir` does not move the
subject's cwd — **except** that a `clone`/`clone3` carrying `CLONE_FS` shares the fs
context, so a child could move the subject's cwd; such a clone is refused as a boundary,
alongside `CLONE_THREAD`, by the same whole-line token check and for a kindred reason.

### 3. Two-path operations are in scope iff either path is inside

`rename` and `link` touch the state directory when the old *or* the new path is inside
it. This rule goes into both observers: the oracle resolves both paths, and the shim's
`observe`, which judged scope from the first path only, is extended to judge both. That
closes a pre-existing blind spot — an `outside → state` rename is a real mutation the
first-path test dropped (masked until now by the oracle's own refusal of the whole run).
Because scope no longer depends on argument order, the trace can keep recording `link`
as `(path=new, aux=old)` — the same orientation as `rename` — without a careful-ordering
comment being load-bearing.

### 4. The link family is first-class (contract v6)

`OpClass.link` is a kill point and a mutation: creating a second name for an inode
changes the tree. The shim interposes `link`/`linkat` on both platforms; the oracle maps
them in its known table. `linkat(…, "", …, AT_EMPTY_PATH)` — link-by-descriptor — is
refused (`unsupported` from the oracle, `.unresolved` from the shim), not silently
mis-scoped. Trace contract bumps to v6 for the new class value, the same reason v2 added
`.unresolved`.

`symlink`/`symlinkat` are **not** made first-class: the engine cannot yet snapshot or
restore a symlink inside the state directory (#5). Typed resolution still improves them —
a relative-spelled `symlinkat` now reaches the `unsupported` net honestly instead of
being dropped — which is the fail-open→honest-refusal upgrade this change is about,
without pretending to a fidelity the restore path does not have.

## Alternatives considered

- **Keep `touchesStateDir` and OR it with resolution.** Rejected — it re-lets every hole
  the table closes, because the old scan still answers yes to a buffer string or a link's
  content. The table is only authoritative as the sole authority.
- **A dedicated `noteLink(old, new)` wrapper to protect the record order.** Rejected —
  making scope order-independent (decision 3) removes the hazard structurally, so the
  `note2` orientation is safe and there is nothing for a special wrapper to protect.
- **Ship in stages: annotations first, cwd tracking later.** Rejected — CI is x86-64,
  where the legacy syscalls carry no annotation, so the spelling-invariance check that
  proves the fix cannot even run without cwd tracking.
- **Track each child's fs context.** Rejected — refusing `CLONE_FS` is enough, the
  tracking is heavy, and no real target presents the case.

## Consequences

- git's account stops diverging on relative mkdir/link and the run reaches a real
  verdict; with pinned author/committer dates this is also the first chance to measure
  #24's deferred "non-reproducible rewrite" direction on git's refs.
- L0's judgement is unchanged. Restore splits a hard link into independent files with
  equal content, so the atomicity invariant reads the same; **inode identity, `nlink`
  and hardlink topology are outside the model**, and a checker that inspects them is not
  supported. `normalizePath` is lexical (like the shim's), so a state-relative path
  through a symlinked intermediate can resolve wrong and fall to the refusal side; the
  alt-spelling containment absorbs the one such case the engine creates on macOS.
- The scope decision changes for lines that the whole-line scan mis-scoped: those are
  false hits (buffer strings, link contents) that stop being counted, and relative real
  paths that start being counted. Both directions are pinned by the acceptance suite,
  which is run first and read from its reds.
