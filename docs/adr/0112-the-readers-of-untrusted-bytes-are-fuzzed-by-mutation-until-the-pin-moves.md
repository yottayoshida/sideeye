# 0112 — The readers of untrusted bytes are fuzzed by mutation until the pin moves

- **Status:** Accepted (2026-10-10)
- **Refs:** #695 (from the 2026-10-05 whole-product review); #782 (the move off Zig 0.16.0);
  ADR 0001 (Zig, pinned, and its unused in-tree fuzzer).
- **Scope:** `src/fuzz.zig`, `src/fuzz_parsers.zig`, `build.zig` (the `fuzz` step, `-Dfuzz-runs`,
  `-Dfuzz-seed`), `.github/workflows/fuzz.yml`; `case.read` in `src/case.zig` and `mcp.Lines` /
  `mcp.route` in `src/mcp.zig`, moved out of `main.zig` and `handle` so they could be reached.

## Context

#695 named five readers of bytes someone other than Sideeye chose: the trace the shim writes inside
the target, a `sideeye.toml`, the executable a define names, a saved case, and the lines an MCP
client sends. None had been fuzzed. They are not all such readers — the section below on what this
does not reach names the others. ADR 0001 recorded that Zig has an in-tree fuzzer and
that v0.1 did not need it.

That fuzzer cannot run on the pinned Zig. Measured on 2026-10-10 with a five-line probe:
`zig build test --fuzz=200K` on 0.16.0 fails to compile Zig's own test runner
(`lib/compiler/test_runner.zig:566` passes a `*builtin.StackTrace` where a `*const debug.StackTrace`
is expected), before any user code is involved. The same probe runs on 0.17.0 — which also
showed that a fuzz run there that finds a failure prints it and exits 0, saving the input under
the cache's `f/crash`. Outside fuzz mode, `std.testing.fuzz` feeds an entry point its seeds and
one empty input, and nothing else.

## Decision

**Entry points in the fuzzer's form, driven by a mutator of Sideeye's own until the pin moves.**

- Each reader has one entry point in `src/fuzz.zig`, a `fn (ctx, *std.testing.Smith)` that takes
  its whole input with one `smith.slice` and hands it to the reader's production entry:
  `readTraceCapped` and `image.reobserve` + `image.startable` through a file on disk,
  `config.parse`, `case.read`, and `mcp.Lines` + `mcp.route`. `image.zig` already held that rule
  for its own tests — a harness that skips the production entry point measures its own copy of
  the logic. Four of the entry points hold the reader to one thing beyond not crashing: the trace
  reader returns every byte of its budget, a config refusal names a line the document has, a
  case `read` accepts carries no mode `main.zig` cannot take without checking again (it reads the
  mode with `ObserveMode.parse(m).?`), and every MCP reply is one JSON-RPC 2.0 message on one line.
  The executable entry point is held to not crashing alone.
- `run` passes the entry point to `std.testing.fuzz` with Smith-framed seeds — the form 0.17's
  `zig build test --fuzz` drives, coverage-guided, with no rewrite — and then, under 0.16, runs a
  mutation loop: a seed, one to eight stacked mutations (bit flips, byte replacement, delimiters
  and boundary integers, insertion, deletion, duplication, splicing another seed, truncation,
  copying one byte over another), cut to the entry point's buffer before it is framed, because
  Smith reads an over-long slice as empty.
- **A failure survives the process.** A reader breaks mostly by a safety check, which panics, and
  the test runner is the root, so the handler cannot be replaced. Each input is copied, before it
  runs, into a file through a shared mapping — stores into the mapping are stores into the file's
  pages, which outlive the process — at `/tmp/sideeye-fuzz-<entry point>-XXXXXX/input.bin`, in a
  directory `mkdtemp` made and the file opened `O_EXCL | O_NOFOLLOW`, removed when every run
  passed. The same seed and run count stop at the same input. Exit status is
  non-zero on a failure either way, unlike 0.17's `--fuzz`, so nothing leans on that shape.
- **Seeds and runs are build options that reach only the fuzz binary.** `-Dfuzz-seed` defaults to a
  fixed value, so a pull request's runs are the same inputs every time and an unrelated change
  never turns red over an input nobody asked for; `-Dfuzz-runs` defaults to 1,000 per entry point.
  `zig build test` includes the fuzz binary; `zig build fuzz` is that binary alone. The weekly
  `fuzz.yml` passes the run id as the seed and 200,000 runs, and uploads a failure's input.
- **The fuzz binary is its own test executable, and the parsers reach it as a module.** Zig
  collects a test block from every file of the root module that a test reaches. With the entry
  points beside their parsers, config.zig's ran in seven test binaries; with the parsers imported
  as files of `fuzz.zig`, their own four hundred-odd tests ran a second time in the fuzz binary,
  36 s of its 36 s step. As a separate module (`src/fuzz_parsers.zig`) they are not collected.

Two readers could not be reached without moving code. Replay's validation of a case lived inline
in `main.zig`, each refusal a `setupError` that ends the process; it is `case.read` now, and
`main.zig` refuses with what it returns — the twenty-five string literals of the moved block,
compared before and after, are the same in the same order. The MCP server's framing lived inside
`runServer`'s read loop and its envelope check inside `handle`, which writes to fd 1 and spawns; the
framing is `mcp.Lines` and the decision is `mcp.route`, which returns the reply to write or the
tool to run, and `handle` writes or runs it. Unit tests pin both.

### Shown able to go red

For each entry point, a `@panic` was planted where a seed does not reach and a one-place mutation
of a seed does — an unknown key in `[define]`; a trace cut short after a record was read; an ELF
with more than one program header; a version-6 case whose `observe` names no mode; an unknown
MCP tool. For each, with the seeds alone (`-Dfuzz-runs=0`) the binary passed, with the default
runs it failed naming the plant and left exactly one input behind, and run again it stopped at a
byte-identical input. The first version of the mutator drew the number of stacked mutations
evenly from one to eight, and it missed the case plant in the default thousand runs: every extra
mutation is another chance to break a JSON document at its first check. Weighting the count toward
one (one half of the time, two a quarter, …) and adding the byte-copying mutation reached it —
from the default seed and from each of five others (1 to 5) — and all five plants were measured
again after the change.

### What this does not reach

- **Other readers of untrusted bytes.** The strace output the oracle parses (`oracle.parse`, whose
  lines carry paths the target chose), the evidence bundle `sideeye evidence` and the MCP
  `sideeye_evidence` read beside a case (`evidence.parseBundle`, in a work directory the target
  can write), and the macOS `fs_usage` reader have no entry point. #695 named five; these are
  candidates for the next.
- **One door of the executable reader.** The entry point drives `reobserve` (the header) and
  `startable` (a `#!` line and the interpreter it names), not `frameworkPython`, which reads a
  script's `#!` line again on macOS to tell a framework Python's launcher from its binary.
- **What follows a reader.** The MCP entry point stops at `route`: the path resolution inside the
  root and everything a tool does are not driven. The case entry point stops at `read`: what
  `main.zig` does with an accepted case afterwards (resolving paths, normalising scratch entries,
  which refuse on their own) is not.
- **Branches no seed comes near**, the limit of a mutator without coverage (below).

Memory is bounded because each run allocates from libc's `malloc` (`std.heap.c_allocator`), not
`std.testing.allocator`: that DebugAllocator keeps a record of every allocation it served, and a
review measured the weekly run headed for some 3.5 GB (20,000 runs of the MCP entry point: 161 MB;
of all five: 353 MB). After the change, 20,000 runs of each of the five peaked at 7 MB (measured
2026-10-10, macOS arm64). The trace entry point's budget, which counts for itself whatever
allocator is under it, still catches a reader that leaks.

## Alternatives considered

- **Move to Zig 0.17 first, then use `--fuzz`.** The move's depth is unmeasured (#782 measured the
  first two layers), and it would tie this to it. The entry points are what carries over.
- **An external fuzzer (AFL++, libFuzzer).** A C ABI seam and sanitizer builds for each reader, for
  coverage guidance that arrives with the pin anyway.
- **`std.testing.fuzz` alone.** Under 0.16 it feeds the seeds and one empty input: a corpus replay.
- **A memory-backed `Reader` for the executable header, and the trace decoded from a slice.** Both
  would test a branch production never takes; `image.zig` names that as the thing not to do.

## Consequences

- Not coverage-guided. The mutator reaches past a format's first checks only because it starts
  from inputs that pass them; a branch no seed comes near is reached by chance or not at all.
  When the pin moves, `zig build test --fuzz` drives the same entry points with coverage, and a CI
  step built on it has to read its output, not its exit status.
- The trace and the executable header are read from a file each run; on a workstation with
  endpoint scanning, a file write costs about a millisecond (measured), which the shared mapping
  removed for the driver's own copy.
- A failure found by the weekly run is fixed with its input added to the entry point's seeds.
