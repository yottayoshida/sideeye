# sideeye

<p align="center">
  <img src="docs/sideeye.jpg" alt="Sideeye — doesn't believe it" width="360">
</p>

> *Sideeye doesn't believe it.*

Sideeye is a deterministic skeptic for the coding loop. You declare an invariant — *"if this operation said it succeeded, this must still be true after a restart"* — and Sideeye explores the worlds where your process died partway through, then brings back the **smallest reproducible counterexample**.

It breaks worlds, not inputs: same input, hostile universe.

## Status

**v0.5 — the loop closes.** The milestones so far, each measured rather than argued
(details in [PRD.md](PRD.md) and the [CHANGELOG](CHANGELOG.md)):

- **Deterministic crash points** (v0.1): a process is killed immediately before its
  k-th state-changing operation, every world is judged, and the same scenario gives
  the same verdict on Linux and macOS. What it will not do is guess — a target it
  cannot fully observe is UNKNOWN, never passing.
- **Process boundaries without guessing** (v0.2): shim/wrapper/launcher shapes are
  explorable when an oracle confirms nobody else touched the state.
- **The full Define contract** (v0.3): `sideeye.toml`, success markers (L1), and
  saved counterexamples with `sideeye replay` — a changed recording answers
  "case no longer applies", never a verdict about a shifted address.
- **A real bug in real software** (v0.4): timewarrior's undo deletes the wrong
  interval after a crash between its commit renames — the crash-world search
  minimized it from a human-declared invariant (the mechanized half is the
  search, not the hypothesis — DESIGN §17 keeps that score honest), reported
  upstream, and replayed across the fix in the dogfood harness (not yet a
  CI-resident case).
- **The report is agent food, proven** (v0.5): a context-free coding agent was
  handed the counterexample and what it names, plus bug-blind replay plumbing
  and the pinned repository — and it fixed that bug. Twice: through the CLI
  plumbing and through the `sideeye mcp` surface, two different models, no
  human translation (DESIGN §17).
- **The entrance is paved** (v0.6.0): every release now ships prebuilt
  binaries with the shim, `sideeye demo` reaches a real FAIL report in about
  a minute with nothing written, and `sideeye preflight` answers "does the
  recording accept my tool?" before a define exists — see
  [Getting it](#getting-it).

The Define contract, the report schema and the exit codes are **not frozen** until 1.0 and
may change in any release.

| Document | What it is |
|----------|------------|
| [DESIGN.md](DESIGN.md) | What Sideeye is, and what it refuses to be |
| [PRD.md](PRD.md) | The road from v0.1 to v1.0 |
| [BUILDLOG.md](BUILDLOG.md) | Decisions as they happen, including the wrong ones |
| [CHANGELOG.md](CHANGELOG.md) | Releases |
| [docs/report-schema.md](docs/report-schema.md) | Every field the JSON report carries, held to the code by CI |
| [docs/ci-quickstart.md](docs/ci-quickstart.md) | Running sideeye in GitHub Actions — the example is a live workflow |

### What the target has to do

Sideeye refuses to guess. A target outside these limits is reported UNKNOWN (exit 2),
never as passing — and the refusal names its detector.

- **Exit zero during the recording run.** The crash points are read off that run, so a
  target that fails partway through would have Sideeye explore a sequence it never
  performs. There is no way yet to declare a different expected status.
- **Be dynamically linked and single-threaded**, and reach its files through libc —
  which includes buffered stdio (observed at flush granularity) and the hard-link
  family (`link`/`linkat`). Raw syscalls (a Rust target pulling in `rustix`, say),
  static linking, a hardened runtime, threads, and symlinks inside the state
  directory are detected and refused.
- **Keep other processes away from its state.** A target that forks or spawns helpers is
  explorable when an oracle is present (`--oracle`, Linux) and no process other than the
  target itself touched the state directory — the common shim/wrapper/launcher shape.
  A child that writes into the state directory, a target that `exec`s over itself, or a
  process that leaves Sideeye's containment group is refused. Without an oracle, any
  process boundary is UNKNOWN: the shim only sees processes that load it, and "was not
  seen" is not "did nothing".
- **Keep its state in one directory**, declared with `--state` or the toml's
  `[world] state`.

## Getting it

Every release from [v0.6.0](https://github.com/yottayoshida/sideeye/releases/tag/v0.6.0)
on ships prebuilt tarballs for x86_64-linux, aarch64-linux and aarch64-macos:
`sideeye` plus `libsideeye_shim` — the shim travels with the binary, it is half
the product. Download from
[Releases](https://github.com/yottayoshida/sideeye/releases), unpack, done:

```
$ tar xzf sideeye-v0.6.0-aarch64-macos.tar.gz && cd sideeye-v0.6.0-aarch64-macos
```

(v0.5.0 and earlier predate the artifacts; build those from source: Zig 0.16.0,
`zig build`, binaries in `zig-out/bin` and `zig-out/lib`.)

Two commands answer the first two questions before you write anything:

```
$ sideeye demo
```

Sixty seconds to a real FAIL report on your own machine: the demo compiles a small
planted-bug tool (it needs a C compiler — `cc`, `gcc` or `clang`) and explores it,
printing the same report shown below. **Exit 1 — the planted bug found — is
success**, which makes the demo double as a smoke test of the binary + shim pair.

```
$ sideeye preflight --state <dir> --operation "<cmd>" --shim ./libsideeye_shim.so
```

Does the recording phase accept your tool? One observed run, then either
`recording accepted` (exit 0, with the observed operation count and the `explore`
command to graduate to) or a refusal naming the same detector a real run would
use (exit 2). What only a real exploration can check — kill landing, world-side
process boundaries, baseline behavior, checker falsification — is listed as
`not checked`, never silently claimed.

## What it looks like

Against a tool with a delete-before-rename bug — real output, regenerated for this
version, not a mock-up:

```
$ TOY=./mytool sideeye explore --state /tmp/se/state \
    --setup "./mytool init" --operation "./mytool rotate" \
    --check ./check.sh --shim ./libsideeye_shim.so \
    --work /tmp/se/work --oracle /usr/bin/strace

FAIL  1 of 6 crash worlds violated an invariant

invariant   built-in atomicity, and the checker
earliest    crash point 5 of 5
            after  unlink(/tmp/se/state/key.json)
            before rename(/tmp/se/state/key.json.tmp)
path        key.json
observed    present before and after the operation, but gone from the crashed state
explored    6 worlds (crash points 5 + 1 baseline)
atomicity   1 file(s) judged pre-or-post
oracle      agreed on 5 operations (63 syscall lines examined, 9 touching the state directory)
checker     falsified before the run (corrupted state -> check failed); ran in 6 world(s)
l1          no marker configured
case        /tmp/se/work/cases/000001.json
replay      sideeye replay /tmp/se/work/cases/000001.json --shim ./libsideeye_shim.so
processes   single process
not tested  power loss, torn writes, concurrent processes

reproduce   SIDEEYE_STATE_DIR=/tmp/se/state SIDEEYE_TRACE_PATH=/tmp/se/work/trace-repro.bin LD_PRELOAD=./libsideeye_shim.so SIDEEYE_KILL_AT=5 <operation>
```

Read the account block first, not the verdict. `explored` says how much was looked
at, `oracle` says a second witness checked that account against the kernel's,
`checker` says the invariant was shown to be capable of failing before the run
began, and `not tested` says what this verdict is silent about. `case` and `replay`
are the counterexample made portable — the saved case replays through every trust
gate, and hands to a coding agent as-is. A report that only said FAIL would be
asking to be believed.

`--json` writes the same content for a caller to branch on. Exit codes are 0 PASS,
1 FAIL, 2 UNKNOWN, 3 SETUP ERROR — and UNKNOWN is never 0.

The `check` script is where the interesting invariants live. This one cross-examines the
tool's own diagnostic:

```sh
#!/bin/sh
# The invariant is not "the key is readable" — a tool is allowed to be broken as long as
# it says so. The invariant is that the claim and the observable truth agree.
claim=$("$TOY" doctor 2>/dev/null) || claim="unhealthy"
"$TOY" load-key >/dev/null 2>&1 && reality="loadable" || reality="unloadable"

case "$claim:$reality" in
    healthy:loadable | unhealthy:unloadable) exit 0 ;;
    *) echo "doctor says '$claim' but the key is $reality" >&2; exit 1 ;;
esac
```

The full version is [`spike/check.sh`](spike/check.sh). Sideeye refuses to trust a checker
it has not seen fail: before exploring, it overwrites the state with junk and requires the
check to reject it. A checker that cannot fail makes the run UNKNOWN, not PASS.

The define surface — three commands and one directory ([DESIGN.md](DESIGN.md) §12) —
can be a `sideeye.toml`, passed with `--config`:

```toml
[world]
state = "./state"               # resolves against this file's directory

[define]
setup     = "mytool init"
operation = "mytool rotate-key"
check     = "./check.sh"        # exit 0 = invariant holds, run after crash + restart
marker    = "Recorded"          # optional: the operation's own success claim (L1) —
                                # in worlds where it reached stdout before the kill,
                                # the new state must survive
```

A FAIL saves its counterexample to `<work>/cases/NNNNNN.json` and prints the
ready-to-paste `sideeye replay <case.json>` line. Replay re-runs the same pipeline —
every trust gate included — restricted to that crash point; when the code changed
underneath the case, the answer is `case no longer applies`, never a verdict about a
shifted address.

The parser accepts exactly this shape and refuses everything else with the offending
line named — an ignored key would be a declared invariant that silently never fires.
`--config` is mutually exclusive with the define-surface flags
(`--state`/`--setup`/`--operation`/`--check`); operational flags (`--shim`,
`--oracle`, `--work`, `--json`, `--allow-unverified`) stay flags and combine with it.
Command strings split on spaces — no quoting; anything an argument cannot spell
belongs in a script file (ADR 0007).

## Driving it from an agent (MCP)

`sideeye mcp` is a stateless MCP server (stdio, protocol 2026-07-28) so a coding agent
can drive sideeye through the standard tool surface. Two tools, both taking a path
inside `SIDEEYE_MCP_ROOT`:

- `sideeye_explore_config` `{config_path}` — explore a target defined by a `sideeye.toml`
- `sideeye_replay_case` `{case_path}` — replay a saved counterexample case

The tools take *paths*, never a raw command: the operation lives in the config file,
which is a **trust boundary** — its operation is executed, so the config is what you
vet, and the server confines *which* config (inside the root), not what it may do.
Operational settings come from the environment, not tool input: `SIDEEYE_MCP_SHIM`
(required), `SIDEEYE_MCP_ROOT` (required), `SIDEEYE_MCP_ORACLE`, `SIDEEYE_MCP_WORK`
and `SIDEEYE_MCP_CHILD_ENV` (optional). The server self-execs the canonical binary,
captures the child's output so it never touches the MCP transport, and runs it with a
near-minimal environment: PATH, plus exactly the variable names the operator lists in
`SIDEEYE_MCP_CHILD_ENV` (comma-separated), each resolved from the server's own
environment — for targets that locate their state through a variable, like
timewarrior's `TIMEWARRIORDB` (ADR 0011). A listed name absent from the server
environment is a loud tool error. The list is the operator's trust decision: names
like `LD_PRELOAD` or `DYLD_INSERT_LIBRARIES` would load code into the child, so list
only what the target reads. Replays through this surface always run with
`--fresh-state` — the server lives for the whole client session, and the case's state
directory is emptied before each setup so the second replay does not die in the
leftovers of the first. v1 is synchronous — a long exploration blocks the connection;
async is future work.

## What Sideeye is not

- **Not a property-based testing library.** It varies the world the program runs in, not the input.
- **Not an AI code reviewer.** Verdicts are deterministic; a language model never decides PASS or FAIL.
- **Not a chaos platform.** One binary, ordinary software, local state.
- **Not a certification.** A PASS is a search record, not a safety claim — every report says what was *not* tested.

## v0 scope

Process crash × persistent state consistency, for stateful CLIs and local tools that keep their state in files. Power loss, network faults, clocks, and concurrency are explicitly out of scope for v0 — see [DESIGN.md](DESIGN.md) §9 and §15.

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT License](LICENSE-MIT), at your option.
