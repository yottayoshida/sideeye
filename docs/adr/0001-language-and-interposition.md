# ADR 0001 — Implementation language and interposition mechanism

- **Status:** Accepted (2026-08-10)
- **Supersedes:** none
- **Scope:** v0.1 onward; revisiting this means rewriting both halves of the tool

## Context

Sideeye needs to observe a target process's file operations, count them, and kill the
process immediately before the k-th one — deterministically, on both Linux and macOS.
DESIGN §14 stops short of choosing a mechanism but notes that reproducible *logical*
crash points plus native macOS support push toward userspace interposition. That means
the tool ships as two artifacts that must agree with each other:

- an **engine**: a CLI that snapshots state, runs the target, restores, judges, reports;
- a **shim**: a shared library injected into the target, which counts operations and
  kills the process at the requested point.

The two communicate through a trace file. The format of that trace, the set of operation
classes, the environment variable names and the exit codes are a contract between them.

The failure mode that matters most here is not "the tool crashes" — it is **the tool
missing an operation and still reporting PASS**. A user who reads PASS stops looking.
Any design decision that creates a second place where the contract is written down is
a decision to make that failure mode possible, because one copy will eventually be
updated and the other will not, and nothing about that mismatch is loud.

## Decision

**Write everything in Zig — engine, CLI and shim — and pin Zig 0.16.0 (a tagged
release, not a `-dev` build).**

The substance of the decision is a single file, `src/contract.zig`, holding the
`OpClass` enum, the trace record encoding and decoding, the environment variable names
and the exit codes. The shim imports it; the engine imports it. A trace is written and
read by the same functions. There is no second definition to drift from.

Supporting consequences of one language:

- **Cross-compilation is first-class.** `zig build -Dtarget=x86_64-linux-gnu.2.28`
  produces a Linux binary with a chosen glibc version from a macOS host. v0.1 claims
  identical verdicts across two architectures and two operating systems; being able to
  build all of them from one machine is what makes that claim cheap to check.
- **The shim avoids the unstable part of the standard library.** It is written with
  `extern "c"` declarations, `export fn` and thin `std.c.*` bindings. It never touches
  the `std.Io` layer that 0.16 reworked, so the churn that affects the engine does not
  reach the component that runs inside somebody else's process.
- **One build file.** `build.zig` produces both artifacts; the shim is only built for
  targets whose interposition mechanism actually exists.

Zig is pinned to **0.16.0 stable** rather than 0.17.0-dev because ziglang.org keeps only
tagged releases and the current master build: a pinned `-dev` version stops being
downloadable once master moves on. CI is a required gate for v0.1, so a version that
can vanish is not a version that can be pinned.

The local toolchain is the Homebrew `zig` 0.16.0 formula. `anyzig` was considered — it
reads `minimum_zig_version` from `build.zig.zon` and fetches the matching compiler — but
it conflicts with the `zig` formula (both provide a `zig` binary), and the version it
would fetch is the one already installed. The declaration in `build.zig.zon` is what
other environments need; the fetching mechanism is interchangeable.

## Interposition mechanism

| | Linux (v0.1) | macOS (v0.1, after the internal gate) |
|---|---|---|
| Injection | `LD_PRELOAD` | `DYLD_INSERT_LIBRARIES` |
| Symbol replacement | export the same symbol name; reach the real one via `dlsym(RTLD_NEXT, …)` | a `__DATA,__interpose` section holding (replacement, original) pairs; the real one is callable directly |
| Main reason a target is out of bounds | static linking, raw `syscall(2)` | hardened runtime + library validation, SIP-protected binaries |
| Completeness oracle | `strace` | to be measured — `dtruss` is DTrace-based and constrained by SIP |

The skeleton (operation classification, path normalisation, trace format, re-entrancy
guard, kill decision) is shared; only symbol resolution differs per platform.

## Alternatives considered

**Rust CLI + Zig shim** — the original plan. Rejected: the contract would exist twice,
once in Rust and once in Zig. That is precisely the shape that produces "missed an
operation, still reported PASS". It also means two build systems and a more awkward
cross-compilation story on the Rust side.

**All Rust** — tooling, ecosystem and code-generation accuracy are all better. Rejected
because the shim would become `#![no_std]` plus the `libc` crate: dense `unsafe` in the
one component where Rust's guarantees do not apply, while the hazards that motivated
those guarantees (panics, allocation, thread-local access inside an injected library)
remain. Injection hygiene would be maintained by discipline rather than by construction.

**C shim + anything** — suggested during review as the fastest way to measure the
interposition boundary. Rejected: Zig measures the same boundary at the same speed while
keeping bounds checking, defined integer semantics and a build system. The review's
companion advice — start from a minimal operation set rather than a broad one — was
adopted, so the initial implementation is no larger than the C version would have been.

**Go + C** — the Go runtime is unsuitable for an injected library (its own signal
handling, scheduler and stack management fight the host process).

## Consequences

Accepted costs:

- The engine rides on `std.Io`, which 0.16 reworked and 0.17 will move again. Pinning
  0.16.0 means the breakage arrives all at once at the upgrade rather than continuously.
- No JSON Schema generation and no snapshot-testing library; both are hand-written when
  needed. Property testing has an in-tree fuzzer, unused in v0.1 — the determinism claim
  is a byte comparison of two traces, which needs no generator.
- Code generation for Zig is weaker than for Rust because training data predates these
  APIs. Mitigated by a project skill covering the 0.16/0.17 changes; that skill is
  itself unverified, so the first discrepancy found in practice is recorded in
  BUILDLOG.md rather than silently worked around.

**Retreat conditions**, recorded so that changing course later is a decision rather than
a drift:

- If Zig standard-library churn blocks the spike **twice**, move the engine to Rust and
  keep the shim in Zig. The contract then lives in the shim's language and the engine
  gets a generated or hand-checked mirror — a worse position, entered deliberately.
- If the shim itself hits a wall (symbol compatibility, build integration), fall back to
  a C shim. That is the common language of interposition and the smallest detour.

## Notes

The report schema is **not** frozen by this decision. Freezing the config format, report
schema, exit codes and replay compatibility is what v1.0 means (PRD "Versioning
philosophy"); v0.1 keeps the schema experimental so that what the spike learns can still
change its shape.
