# Predictions — written before any target was measured on v1.15.0

What changed between the engines these walls were met on (v1.7.0 to v1.12.0) and v1.15.0, as far as the
two walls go: the thread order (ADR 0067) was already in v1.7.0's contract v18, and since then the
changes were the vfork slots (#821, #901) and the fortified opens (#900). None of the walls below was a
vfork or a fortified open: each thread wall is a write by one thread that no creation or join recorded
orders against another's, and each syscall wall is a call v1.15.0 still refuses by design. So every
target is predicted to meet the same wall.

| target | prediction on v1.15.0 | why |
|---|---|---|
| basic-memory | `multiple_threads_detected` | aiofiles' writer thread beside the event loop's rename (2026-10-09 follow-ups 4) |
| Bitwarden | `multiple_threads_detected` | the data file's lock directory and the file written from two threads |
| codex | `multiple_threads_detected` under `--observe supervised` | `config.toml` from one thread, its `tmp` symlinks from another (follow-ups 4) |
| electrum | `multiple_threads_detected` | the wallet written from a second thread (strace, follow-ups 4) |
| flatpak | `unsupported_syscall_observed` (`fallocate`) | libglnx calls `fallocate` for every non-empty file (follow-ups 4, the source read) |
| goaccess | `unsupported_syscall_observed` (`mmap(PROT_WRITE\|MAP_SHARED)`) | tpl writes every database through a shared mapping (ADR 0098 refuses it) |
| logrotate | `unsupported_syscall_observed` (`fsetxattr`) | attribute writes still refuse; the control a run that passes everything would fail |
| lz4 | `multiple_threads_detected` under `--observe syscalls` | `-BD` still writes the frame from a worker thread |
| ostree | `unsupported_syscall_observed` (`fallocate`) | libglnx, as flatpak |
| prek | `multiple_threads_detected` | the old hook renamed aside on one thread, the new one written on another |
| rrdtool | `unsupported_syscall_observed` (`mmap(PROT_WRITE\|MAP_SHARED)`) | the round-robin database is written through a shared mapping; even past it, its copied checker has never run green on the seed (`defines/rrdtool/ORIGIN.md`), so no verdict would follow |
| rustic | `multiple_threads_detected` | deletes on rayon's worker while the main thread writes the index |
| steamguard | `multiple_threads_detected` | the manifest and the account file from two threads |
| vercel | `multiple_threads_detected` | the config directory's `mkdirp` from a second thread at the top of every command |

A target that meets a different refusal, or none, is a missed prediction; each is explained in
RESULTS.md.
