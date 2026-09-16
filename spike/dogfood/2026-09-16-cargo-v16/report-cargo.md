**Where `Cargo.lock` is under version control, no data is lost by this — `git checkout Cargo.lock` restores it.** What breaks is every cargo command until someone does that: a `cargo add` killed while it is rewriting `Cargo.lock` leaves the lockfile torn, `cargo metadata` and `cargo build` then fail with `failed to parse lock file`, and the message does not say the file is truncated. The empty lockfile is the quiet case: cargo's next command re-resolves and rewrites it, printing its usual resolving lines (`Locking …`, `Adding …`) and nothing about the file having been empty; where the lock was not committed there is nothing to restore it from, and the next command resolves afresh.

## What happens

`write_pkg_lockfile` (`src/ops/lockfile.rs`, master `f325466` as of 2026-09-16) writes the lockfile in place:

```rust
lock_root
    .open_rw_exclusive_create(LOCKFILE_NAME, ws.gctx(), "Cargo.lock file")
    .and_then(|mut f| {
        f.file().set_len(0)?;
        f.write_all(out.as_bytes())?;
```

Between `set_len(0)` and the end of `write_all` the file on disk is empty, then a prefix of the new contents. The manifest has no such window: `cargo add` writes `Cargo.toml` through `paths::write_atomic` (a temporary in the same directory, then `persist`), which is why the manifest survives the same crash and the lockfile does not. A process killed inside the window — a crash, `kill -9`, power — reaches neither an error branch nor a retry.

## Measured

- cargo 1.97.1 (c980f4866 2026-06-30), the `rust:1.97.1-slim-bookworm` image, aarch64 Linux. The block above is unchanged on master.
- Without any tool, a file-size limit standing in for the crash: a project with 19 path dependencies (`Cargo.lock` 1212 bytes), then `sh -c 'ulimit -f 2; cargo add --offline --path ../dep20'`. `cargo add` dies of `SIGXFSZ` (exit 153) after the manifest is rewritten (`dep20` present) and while the lockfile is: `Cargo.lock` is 1024 bytes, cut inside a `[[package]]` entry. The next `cargo metadata --offline` exits 101 — `error: failed to parse lock file at: …/Cargo.lock` — and so does every command after it.
- With a crash-consistency tool (Sideeye, which kills the process at each state-changing syscall and checks what is left): 7 crash points inside `cargo add --offline --path`, three runs; the world killed between `truncate(Cargo.lock)` and `write(Cargo.lock)` leaves a zero-length `Cargo.lock`. `cargo metadata` on that state exits 0, prints `Locking 1 package to latest compatible version` and `Adding depcrate v0.1.0 (…)`, and writes a fresh lockfile — in this offline, path-only project byte-identical to the one before; nothing says the file was empty.
- Recovery: `git checkout Cargo.lock` where it is tracked; otherwise deleting it and letting cargo resolve again, with whatever versions the registry offers that day.

## Not claimed

That the window is reached in ordinary use without a crash or a signal. That the regenerated lockfile differs — in the offline measurement above it is byte-identical, every dependency being a path. Whether this is worth changing is yours to weigh: a lockfile that is usually committed is a lockfile that usually comes back.

<details><summary>Disclosure</summary>

Found by Sideeye, a crash-consistency tool I am building; the `ulimit` reproduction and the reading of `lockfile.rs` were done by hand. If reports of this kind are not wanted here, say so and there will not be another.

</details>
