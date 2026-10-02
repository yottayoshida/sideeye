# terraform#39303 at 28a34e9b8 — predictions, written before any build or run (2026-10-02)

Read from the diff only (`gh pr diff 39303`), nothing run yet.

The write is now: create `main.tf<random>` beside the file (backup), write the original into it,
close; open the target `O_WRONLY` (no truncation); write the formatted bytes from offset 0;
`ftruncate` to the formatted length; close; unlink the backup.

1. 09-28 define (seed 84 bytes, formatted 86 — the file grows): supervised explore **PASS**.
   No world loses the file; the write extends it, so no stale tail before the `ftruncate`.
2. `ulimit -f 0`: `main.tf` keeps its 84 bytes, exit 2, no backup file left.
3. Modes 0600 / 0664 / 0755 are kept (the target is opened, not replaced).
4. Relative symlink, all three spellings (`-recursive` from the parent, `fmt mod`, inside
   `mod/`): the real target is formatted, exit 0. `tf39303-wrong.sh`: the unrelated
   `/w/versions.tf` is untouched.
5. A seed whose formatted form is **shorter** than the original (new define, same checker):
   **FAIL** at the crash point between the `write` and the `ftruncate` — `main.tf` holds the
   formatted bytes followed by the original's tail, and the backup file with the original is
   left beside it under a name nothing prints. Not a loss (the backup holds the original);
   whether it is worth saying upstream is the owner's call.
6. Base (merge-base `e3b5fc125`): FAIL on the 09-28 define as on 09-29 (truncating open, 0 bytes).
