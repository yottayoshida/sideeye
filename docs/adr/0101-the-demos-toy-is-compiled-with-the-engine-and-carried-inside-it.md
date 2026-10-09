# 0101 — The demo's toy is compiled with the engine and carried inside it

- **Status:** Accepted (2026-10-09)
- **Refs:** #715 (from the 2026-10-05 whole-product review); `build.zig:164` before this
  change ("the same files the acceptance suite drives, so the demo cannot drift from what
  CI proves").
- **Scope:** `build.zig`, `src/main.zig` (`runDemo`), `src/files.zig`, `src/cli.zig`,
  `spike/acceptance.sh` (check 5), `spike/check-readme-demo.py`,
  `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `README.md`, `docs/cli.md`.

## Context

`sideeye demo` is the sixty-second proof: it explores a planted-bug toy and prints a real
FAIL. It carried the toy's C source and compiled it on the visitor's machine, trying `cc`,
then `gcc`, then `clang`, and refused with a SETUP ERROR when none worked. The review that
filed #715 ran the Homebrew v1.8.0 binary on macOS arm64 and recorded what that means: the
proof fails on a machine with no compiler, which is exactly the machine a prebuilt binary is
most likely to be tried on. The same line of the README also said the demo "writes nothing
permanent", and it leaves its scratch directory under `$TMPDIR` (twelve of them on the
review machine) — on purpose, since the saved case names files in it.

## Decision

**`build.zig` compiles `spike/toys/toy.c` into an executable for the engine's own target and
embeds its bytes; the demo writes them into its scratch directory and runs them.** No
compiler is looked for at run time.

- **Same source, same target, one mode.** The toy is the file the acceptance suite drives,
  built `-DBUGGY=1` as the demo always built it. Its optimisation is fixed at Debug with
  `-O0` rather than following the engine's: following it would give a Debug CI engine and a
  ReleaseSafe release two different toys. The link is dynamic, said rather than defaulted,
  because the shim reaches the toy through the dynamic loader. Zig's C sanitizer is off: the
  toy carries one planted bug, and `cc -O0` never added a second detector. The backend is
  LLVM on every target: Debug on x86_64 defaults to Zig's self-hosted backend and linker,
  which would have made x86_64-linux the one toy not built the way the measurement below
  built all three.
- **Every build of `main.zig` gets the import from one function**, since `main.zig` reads it
  at module scope and a variant one import short fails to compile alone (the reason
  `engineOptions` already gives).
- **The file is created, not overwritten.** `files.writeNewExecutable` opens with
  `O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC` and mode 0700, so the path the demo is about to run
  is one this call made, owner-only from the moment it exists, inside the `mkdtemp`
  directory the demo already used. That is no wider than a compiler writing the same path
  and the demo running it, and the demo no longer runs whatever `cc` is first on `PATH`.
- **The scratch directory stays.** The README line stops claiming otherwise, and
  `docs/cli.md` says where it is and why it is kept.

Measured on 2026-10-09, first with `zig cc` before the build change existed: it compiles `toy.c` for `aarch64-macos`,
`x86_64-linux-gnu.2.28` and `aarch64-linux-gnu.2.28`, and the Linux outputs are dynamically
linked against glibc. On macOS the linker's ad-hoc signature travels in the bytes: a copy
written byte for byte to another file and explored by the released v1.10.0 gave the
README's `FAIL 1 of 6`, crash point 5 of 5; and the demo built from this change, run with
`PATH=/nonexistent` on macOS arm64, wrote its 90,024-byte toy (mode 0700, still
`adhoc,linker-signed`) and printed the same report with exit 1. On Linux, the ReleaseSafe
builds for `aarch64-linux-gnu.2.28` and `x86_64-linux-gnu.2.28` — the release's own
triples — reached the same `FAIL 1 of 6` with exit 1 in `debian:bookworm-slim`, which
carries no compiler at all, run as `nobody` (x86_64 under emulation on an arm64 host); and
the whole acceptance suite passed in the spike container with check 5's demo run under
`PATH=/nonexistent`. CI repeats both where they ship: the release workflow builds all three
targets ReleaseSafe and runs the demo with `PATH=/nonexistent`, and acceptance check 5 does
the same on Linux.

## Alternatives considered

| rejected | why |
|---|---|
| ship the toy in the tarball and the Homebrew formula | the formula is in another repository; the demo would need a search beside the binary like the shim's; a source build would still need the second artifact |
| make the toy a hidden subcommand of `sideeye` | the toy would be rewritten in Zig, and the demo would no longer run what acceptance runs; the engine would also be exploring itself |
| keep compiling, with the embedded binary as the fallback (or the reverse) | two paths, one of which CI never takes |
| delete the scratch directory at the end | the saved case names files in it, so `replay` would have nothing to run; the issue itself calls keeping it reasonable |

## Consequences

- The binary grows by the stripped toy (about 90 KB on macOS arm64).
- The demo's first line now reads `demo  wrote the planted-bug tool into <dir>`;
  `spike/check-readme-demo.py` reads the directory off it.
- Acceptance check 5 lost the two legs that pinned the compiler ladder and the "needs a C
  compiler" refusal, and gained one that runs the demo with `PATH=/nonexistent` — which
  the engine before this change fails with exactly that exit 3.
- A host where Zig's native libc is static (musl) would build a static toy the shim cannot
  enter. That is outside the platforms the README names and is #697's question.
