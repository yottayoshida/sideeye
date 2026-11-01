# Predictions, written before the first run (2026-10-31)

- **The `syscalls` control reproduces the page** on all 14 rows: same verdict, same crash-point
  count. A row that does not is drift between the engine of its day and v1.17.0, named in
  RESULTS.md and not counted as a mode difference.
- **`supervised` reaches the same verdict on the single-threaded C, shell and Python targets**:
  todo.txt (bash), ntfslabel, ziptool, zsh-z, acme.sh, zstd `--single-thread --no-asyncio`,
  useradd, mbsync, update-alternatives, SolveSpace. Crash-point counts may differ: supervised
  counts at the kernel boundary from outside, as `syscalls` does from inside.
- **Targets with more than one thread are where the modes differ** (#687: under supervised no
  thread order is recorded, so a second writer refuses). Predicted refusals:
  podman and skopeo (Go runtimes, writes from goroutines on several OS threads), and row 59's
  zstd at its default thread count (two threads created, one writing under `syscalls` — whether
  supervised admits "one writer" the same way is the open part). alacritty (Rust) is uncertain.
- Confidence: 60% that the supervised column matches on at least 10 of 14.
