# Prediction — mutool at the latest release, committed before it is built or run (2026-10-02)

The box holds Debian's mutool 1.25.1 (2024-11-29). The latest release is 1.28.5 (2026-09-25),
and `source/fitz/output.c` changed in 1.27.0: the `fopen` mode lost its `x` on non-Windows
builds (`CLOBBER` is `""`), so the write is `remove()` then `fopen("wb+")` — `unlink`, then an
open with `O_CREAT|O_TRUNC` and no `O_EXCL`. Read from the source at `3a8329655`; nothing built.

Predicted, for `mutool clean a.pdf a.pdf` built from the 1.28.5 source tarball:

- strace: `unlinkat`, then `openat(O_RDWR|O_CREAT|O_TRUNC)` without `O_EXCL`, then `write`.
- `run.sh`: wrappers refused, followed to syscalls, **FAIL** at the same place — after the
  `unlink`, before the `open`, `a.pdf` gone — replayed twice. Fairly sure.
- `ulimit -f 0`: `a.pdf` at 0 bytes.
