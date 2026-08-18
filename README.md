# sideeye

<p align="center">
  <img src="docs/sideeye.jpg" alt="Sideeye — doesn't believe it" width="360">
</p>

> *Sideeye doesn't believe it.*

Sideeye finds out what your program leaves on disk when it dies at the worst possible moment. You declare an invariant — *"if this operation said it succeeded, this must still be true after a restart"* — and Sideeye kills your process immediately before each of its state-changing operations, one crash world per operation, then brings back the **earliest failing crash point**, saved as a replayable case. It breaks worlds, not inputs: same input, hostile universe.

It has produced replay-confirmed counterexamples against real tools — timewarrior, topydo, GNU Stow, calcurse, devtodo — several of them reported upstream. Verdicts are deterministic: a target Sideeye cannot fully observe is UNKNOWN, never a silent PASS.

## Installation

Download the tarball for your platform (x86_64/aarch64 Linux, aarch64 macOS) from [Releases](https://github.com/yottayoshida/sideeye/releases), then:

```
$ tar xzf sideeye-v0.11.0-aarch64-macos.tar.gz && cd sideeye-v0.11.0-aarch64-macos
```

Or build from source with Zig 0.16.0: `zig build` — binaries land in `zig-out/bin` and `zig-out/lib`.

## Usage

Three commands, in the order you will meet them.

**1. See it work** — sixty seconds, needs a C compiler, writes nothing permanent:

```
$ ./sideeye demo
```

The demo compiles a small planted-bug tool, explores it, and prints a real FAIL report. Exit 1 — the planted bug found — is success, which makes the demo double as a smoke test of the binary + shim pair.

**2. Ask whether Sideeye can watch your tool** — before writing any config:

```
$ ./sideeye preflight --state <dir> --operation "<cmd>"
```

One observed run: either `recording accepted` (exit 0) or a refusal naming the same detector a real run would use (exit 2).

**3. Explore** — the real thing, with the whole define in one file:

```
$ ./sideeye explore --config sideeye.toml --oracle /usr/bin/strace
```

```toml
[world]
state = "./state"               # the one directory your tool's state lives in

[define]
setup     = "mytool init"
operation = "mytool rotate-key"
check     = "./check.sh"        # exit 0 = invariant holds; runs after crash + restart
marker    = "Recorded"          # optional: the operation's own success claim
expected_status = "3"           # optional: the exit status that means "completed" (default "0")
```

- The same define works as flags: `--state` / `--setup` / `--operation` / `--check` / `--marker` / `--expect-status`.
- `--shim` names the interposition library when it is not beside the binary (the tarball and zig-out layouts are found on their own); `--work` moves the scratch directory for traces and cases (default `/tmp/sideeye-work`).
- `--json <path>` writes the same report as JSON, for a machine to branch on.
- Exit codes: **0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR** — and UNKNOWN is never 0.
- Command strings split on spaces, no quoting. An argument that carries a space uses the argv form instead: `operation = ["mytool", "commit", "-m", "a message with spaces"]` — one line, passed verbatim.
- `preflight` reads flags only; a define spelled as argv goes straight to `explore --config`.

A FAIL saves its counterexample to `<work>/cases/NNNNNN.json` and prints the ready-to-paste `sideeye replay` line. Replay re-runs the same pipeline restricted to that crash point; when the code changed underneath the case, it says `case no longer applies` instead of guessing.

## Example

Real output — the same planted delete-before-rename bug the demo uses (`spike/toys/toy.c`), explored with a checker and the strace oracle; the paths are the container's, and the engine hands the target its state directory via `TOY_STATE`:

```
$ TOY=/tmp/se/toy-bug /work/zig-out/bin/sideeye explore --state /tmp/se/state \
    --setup "/tmp/se/toy-bug init" --operation "/tmp/se/toy-bug rotate" \
    --check /work/spike/check.sh --shim /work/zig-out/lib/libsideeye_shim.so \
    --work /tmp/se/work --oracle /usr/bin/strace

FAIL  1 of 6 explored worlds violated an invariant

invariant   built-in atomicity, and the checker
earliest    crash point 5 of 5
            after  unlink(/tmp/se/state/key.json)
            before rename(/tmp/se/state/key.json.tmp)
path        key.json
observed    present before and after the operation, but gone from the crashed state
explored    6 worlds (crash points 5 + 1 baseline)
expected    exit 0
atomicity   1 path(s) judged pre-or-post
oracle      agreed on 5 operations (68 syscall lines examined, 12 in scope of the judged state)
metadata    none observed. Restore does not reproduce ownership/permission state: crash worlds run at the engine's default modes
checker     falsified before the run (corrupted state -> check failed); ran in 6 world(s)
l1          no marker configured
case        /tmp/se/work/cases/000001.json
replay      sideeye replay /tmp/se/work/cases/000001.json --shim /work/zig-out/lib/libsideeye_shim.so
processes   single process
not tested  power loss, torn writes, concurrent processes

reproduce   SIDEEYE_STATE_DIR=/tmp/se/state SIDEEYE_TRACE_PATH=/tmp/se/work/trace-repro.bin LD_PRELOAD=/work/zig-out/lib/libsideeye_shim.so SIDEEYE_KILL_AT=5 <operation>
```

Read the account block, not just the verdict: `explored` says how much was looked at, `oracle` says a second witness (strace) checked the shim's account against the kernel's, `checker` says the invariant was proven able to fail before the run began, and `not tested` names what this verdict is silent about.

The `check` script is where your invariants live. This one cross-examines the tool's own diagnostic — a tool is allowed to be broken as long as it says so; the violation is the claim and the observable truth disagreeing:

```sh
#!/bin/sh
claim=$("$TOY" doctor 2>/dev/null) || claim="unhealthy"
"$TOY" load-key >/dev/null 2>&1 && reality="loadable" || reality="unloadable"

case "$claim:$reality" in
    healthy:loadable | unhealthy:unloadable) exit 0 ;;
    *) echo "doctor says '$claim' but the key is $reality" >&2; exit 1 ;;
esac
```

The full version is [`spike/check.sh`](spike/check.sh). Sideeye refuses to trust a checker it has not seen fail: before exploring, it corrupts the state and requires the check to reject it. A checker that cannot fail makes the run UNKNOWN, not PASS. More worked checkers: [docs/checker-cookbook.md](docs/checker-cookbook.md).

## What the target has to be

Sideeye refuses to guess. Anything outside these limits is UNKNOWN (exit 2) with the refusing detector named:

- **Dynamically linked and single-threaded**, reaching its files through libc — buffered stdio included. State-changing raw syscalls, static linking, hardened runtimes and threads are refused.
- **State in one directory**, declared with `--state` or the toml. Symlinks inside it are snapshotted and restored as links.
- **A clean run exits its declared success status** (default 0) — the crash points are read off that run.
- **Other processes stay away from the state.** Forked helpers are fine when the oracle (`--oracle`, Linux) confirms nobody else touched it. Without an oracle any process boundary is UNKNOWN. For a single-process target with no oracle, a PASS requires `--allow-unverified`, and the report says the weaker claim out loud.

How real tool classes have fared against these limits: [docs/target-classes.md](docs/target-classes.md). The full contract, and the reason behind each refusal: [DESIGN.md](DESIGN.md).

## Driving it from an agent (MCP)

`sideeye mcp` is a stateless MCP server (stdio) with two tools: `sideeye_explore_config {config_path}` and `sideeye_replay_case {case_path}`. The tools take *paths* inside `SIDEEYE_MCP_ROOT`, never raw commands — the config file is the trust boundary you vet. Operational settings come from `SIDEEYE_MCP_*` environment variables (ADR 0010 and 0011). The root confines which config may be named, not what that config's operation does: run the server inside a container, network-off where the target allows it.

Measured here, not aspirations: a context-free agent, handed a counterexample and bug-blind replay plumbing, produced the fix — twice: once through the CLI, once through this MCP server (`spike/loop-closure-timew/`) — an LLM scout authored the defines for five real targets under a fixed protocol (`spike/assisted/`; the method: [docs/scouting.md](docs/scouting.md)), and a context-free agent set Sideeye up **from this README alone** — tarball to a real verdict on an external tool in under five minutes, protocol declared before the clock (`spike/onboarding-clock/`).

## What Sideeye is not

- **Not property-based testing** — it varies the world the program runs in, not the input.
- **Not an AI code reviewer** — verdicts are deterministic; a language model never decides PASS or FAIL.
- **Not a chaos platform** — one binary, ordinary software, local state.
- **Not a certification** — a PASS is a search record, not a safety claim; every report names what was *not* tested. Scope is process crash × file-backed state: power loss, network faults, clocks and concurrency are out.

## Documentation

| Document | What it is |
|----------|------------|
| [DESIGN.md](DESIGN.md) | What Sideeye is, and what it refuses to be |
| [PRD.md](PRD.md) | The road to v1.0 |
| [CHANGELOG.md](CHANGELOG.md) | Releases |
| [BUILDLOG.md](BUILDLOG.md) | Decisions as they happen, including the wrong ones |
| [docs/report-schema.md](docs/report-schema.md) | Every field the JSON report carries, held to the code by CI |
| [docs/ci-quickstart.md](docs/ci-quickstart.md) | Running sideeye in GitHub Actions — the example is a live workflow |
| [docs/scouting.md](docs/scouting.md) | Handing the repo-reading to an agent |
| [docs/target-classes.md](docs/target-classes.md) | Real tool classes against the constraint list, each row backed by a recorded run |
| [docs/checker-cookbook.md](docs/checker-cookbook.md) | Annotated real checkers, and the failure patterns that taught them |
| [docs/adr/](docs/adr/) | One record per irreversible decision |

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT License](LICENSE-MIT), at your option.
