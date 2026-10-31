# 0142 — Extended-attribute writes are set aside as metadata, as ownership and permission writes are

- **Status:** Accepted (2026-10-31)
- **Refs:** #947 (the owner's ruling, 2026-10-31); #684 and ADR 0097, which left the writes refused pending this ruling;
  #121, which set the ownership and permission calls aside; `spike/xattr-947/` (the measurement).
- **Scope:** the oracle's reading of strace (`src/oracle.zig`), fs_usage's reader (`src/fsusage.zig`), the `metadata_writes`
  account and the restore's sentence about what it does not put back, `docs/report-schema.md`.

## Context

Since #684 a `setxattr`, `removexattr` or one of their `l`/`f`/`at` forms on the state directory was refused
`unsupported_syscall_observed`, from the subject and from every child, as "a deliberate refusal waiting for a ruling"
(ADR 0097). Two real targets stopped there and nowhere else: vim on ext4, which writes the replaced file's ACL back to
the new one after saving (`setxattr(…, "system.posix_acl_access", …)`), and logrotate 3.22.0, which copies the rotated
file's attributes (`fsetxattr`). vim was judged only on a FAT state, where there is no ACL to write back.

What Sideeye judges is names, kinds, bytes and link targets. The ownership, permission and timestamp calls change none
of those, and #121 set them aside: the oracle observes them, the report names them in `metadata_writes`, and nothing is
judged by them. vim's attribute write is a permission write in another spelling — an ACL is a permission — and the
same is true of most attribute writes met so far.

## Decision

**An extended-attribute write on the state directory is set aside the way an ownership or permission write is:
observed by the oracle, named in `metadata_writes`, excluded from judgement, and never refused.** The owner chose this
over refusing it for good (2026-10-31).

- **Linux.** The oracle places the path forms by the same typed rules as before (relative paths through the subject's
  working directory, the `at` forms through their directory descriptor, an empty path with `AT_EMPTY_PATH` cannot be placed and is named, wherever its descriptor points) and the `f` forms by the path the kernel resolved for the descriptor. A child's relative path is not
  placed by the subject's working directory; one that cannot be placed is named rather than dropped — over-reporting
  an exclusion is the honest direction, as it is for the ownership calls.
- **macOS.** fs_usage's reader names `setxattr`, `fsetxattr`, `removexattr` and `fremovexattr` as metadata, from any
  process whose line reaches the state, as it names the ownership and permission calls.
- **The shim does not interpose them**, as it does not interpose the ownership calls; without an oracle they are not
  observable, and the `metadata_writes` note says so.

## What this gives up

- **A target that keeps meaning in an attribute is judged without it.** A PASS says nothing about attribute contents,
  and the report names the calls in `metadata_writes`, as it names a `chmod`. A target whose correctness lives in its
  attributes needs a checker that reads them.
- **The restore does not carry attributes**, unlike permission bits (DESIGN, the rebuild; ADR 0118). Every run starts
  without the attributes the setup set, and the restore's sentence in the report now says it does not put them back.
  The state directory itself is not rebuilt, so an attribute on it stays as the last run left it — as its mode does.
- **The ownership calls keep the subject's working directory for a child's relative path.** Not changed here; their
  promise is #121's.

## Alternatives considered

| rejected | why |
|---|---|
| Refuse for good, as a decided limit with its own name | The owner's ruling. vim on ext4 and logrotate would stay refused for writing permissions, which Sideeye already sets aside when they are spelled `chmod`. |
| Judge attributes: carry them in the snapshot, the restore and the comparison | Changes what the judged state is, for every target, to cover a class no target has been measured to need. |
| Pass them over as reads | A write would go unnamed; `metadata_writes` exists so that absence of a note is never absence of writes. |
