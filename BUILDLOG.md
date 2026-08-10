# Buildlog

Development journal, newest first. Decisions are recorded when they are made — including the ones that turn out wrong. This file is allowed to be embarrassing in hindsight; that is what it is for.

## 2026-08-10 — Spike-1: the interposition ground holds (Linux)

The biggest risk retired first, as PRD.md promised. Measured, not argued.

**The shim works.** A recording run of the buggy toy produces this, in order:
`shim_ready`, `open`(seq 1), `write`(2), `fsync`(3), `close`(seq 0), `unlink`(4),
`rename`(5). `close` carries seq 0 because it is recorded but never a crash point, so
N = 5. The delete-before-rename window is visible in the trace as the gap between
seq 4 and seq 5.

**The kill lands where it is asked to.** `SIDEEYE_KILL_AT=k` for k = 1..5 exits 137
(SIGKILL) with a `kill_landed` record present; k = 6 — that is N+1 — runs to completion
with no marker, which is the baseline world. At k = 5 the state directory contains
`key.json.tmp` and no `key.json`: the bug, caught in the act. **10/10 repetitions land
in the identical state.** The corrected toy keeps `key.json` present at every k.

**Two recording runs produce byte-identical traces.** The determinism claim is a byte
comparison, not an impression.

**Out-of-bounds targets are visibly out of bounds**, and each for its own reason:

| target | what the shim sees | what makes it detectable |
|---|---|---|
| `toy-raw` (syscall(2) directly) | 30 bytes: `shim_ready` and nothing else | the state changed while zero operations were recorded |
| `toy-static` | no trace file at all | the shim never loaded, so no marker exists |
| `toy-bug` + fork | a `fork` record | the boundary detector fired |
| `toy-bug` + thread | a `thread` record | ditto |

`toy-raw` is the one that justifies the engine carrying detectors that do not depend on
interposition: its trace is indistinguishable from "this program touched no files".

**Rust's standard library did not route around the supported operation set.** The
plan rated that a high risk — `open64`, `statx`, `openat2` were all plausible. The
stand-in target produced *exactly* the same operation sequence as the C toy:
`open`, `write`, `fsync`, `close`, `unlink`, `rename`. One measurement is not a
guarantee for every Rust program, but the expected divergence did not happen here.

### What the `zig` skill got wrong

The skill was adopted the same day to reduce the risk of generated code targeting old
APIs, and the plan required recording the first discrepancy rather than quietly working
around it. Three showed up, all in the same area:

| skill says | 0.16.0 actually has |
|---|---|
| `std.mem.trimRight` | `std.mem.trimEnd` (`trimLeft` → `trimStart`) |
| `std.fs.File` | `std.Io.File` — `std.fs` has no `File` member |
| `file.writer(&buf)` | `file.writer(io, buf)` — a `std.Io` instance is required |

The skill states that every 0.16.0 stable pattern in it still holds; its I/O section is
0.15-era. Worth knowing before the engine, which cannot avoid that API the way the shim
can.

### A design correction found by building it

DESIGN §12 defines the L0 invariant as: after restart the state directory equals the
pre-operation snapshot or the post-operation result, never a hybrid. Implementing that
literally fails the *corrected* toy — an atomic write leaves `key.json.tmp` behind at
several crash points, so the directory equals neither snapshot.

The invariant that separates the two toys is narrower: **for every path present in both
the pre and post snapshots, the crashed state must contain it, with content equal to one
of the two.** Paths belonging to neither snapshot (temporaries) are ignored. Under that
reading the buggy toy fails at k = 5 (`key.json` missing) and the corrected toy passes
everywhere, which is the distinction the tool exists to draw. DESIGN will be amended.

### Also decided

- **No `anyzig`.** The plan called for it to fetch the pinned compiler, but Homebrew's
  `zig` 0.16.0 — the exact version wanted — was already installed, and `anyzig` conflicts
  with it (both provide a `zig` binary). The declaration in `build.zig.zon` is what other
  environments need; the fetching mechanism is interchangeable.
- The link-type check in `build-toys.sh` first used `file`, which is absent from the
  image; grep matched nothing and every binary was reported as wrongly linked. It failed
  loudly, which is the right direction, but the check now reads the ELF program headers
  (`readelf -l | grep INTERP`) so it does not depend on an optional tool.

## 2026-08-10 — Inception

Design finalized after an adversarial review pass over the first draft. Eight axes were settled; together they define what Sideeye is:

1. **Primary battleground: an automatic gate in the coding loop.** Non-interactive operation, machine-readable output, and the exit-code contract are v0 core requirements — not future polish. The caller is often an agent or CI; the reader is a human.
2. **LLM boundary.** The core (exploration, verdicts, shrinking, replay) is deterministic and LLM-free, permanently. LLMs are allowed at the edges only: proposing invariants on the way in, explaining reports on the way out.
3. **Pure black-box, elevated to principle.** Sideeye sees a binary, a state directory, and the execution's observable behavior. Nothing else. Language-agnostic by construction.
4. **Counterexamples are the whole product.** A PASS is a search record, not a badge, and we will not build a badge culture around it.
5. **Power failure / torn writes: out of v0, named as a long-term candidate.** v0's crash model is process crash — the OS survives, completed writes persist. Every report says so.
6. **v0 runs natively on macOS and Linux.** This was chosen knowingly: it pushes the mechanism toward userspace interposition (macOS forces every language through libSystem, which makes one mechanism cover Rust/Go/Python; the cost is that hardened-runtime macOS binaries and statically linked Linux binaries are declared unsupported rather than silently mishandled).
7. **Public design doc, in English.** This repository is the document.
8. **Define converges on built-in invariants.** L0 = zero-config atomicity judged from state-dir snapshots; L1 = the program's own success message on stdout, held against it; L2 = domain checker scripts. The whole user-facing contract is three commands and one directory.

Practical decisions the same day:

- **Name check:** crates.io free, GitHub free of significant collisions (max 3 stars). PyPI and npm are taken by unrelated projects (an eye-tracking library and an actively updated package, respectively). Shipped as `sideeye` anyway — distribution will be a single binary, so those registries matter little.
- **License:** dual MIT OR Apache-2.0.
- **Biggest known risk:** the interposition spike — kill a toy binary deterministically at the k-th file operation, on both OSes. It is deliberately the first milestone task in PRD.md; if it fails, better to learn that in week one.
