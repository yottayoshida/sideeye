# sideeye

<p align="center">
  <img src="docs/sideeye.jpg" alt="Sideeye — doesn't believe it" width="360">
</p>

> *Sideeye doesn't believe it.*

Sideeye finds out what your program leaves on disk when it dies at the worst possible moment. You declare an invariant — *"if this operation said it succeeded, this must still be true after a restart"* — and Sideeye kills your process immediately before each of its state-changing operations, one crash world per operation, then brings back the **earliest failing crash point**, saved as a replayable case. It breaks worlds, not inputs: same input, hostile universe.

It has produced replay-confirmed counterexamples against real tools — timewarrior, topydo, GNU Stow, calcurse, devtodo — with four upstream reports so far: timewarrior's crash-window bug, a topydo recovery misfire found in follow-up analysis of its campaign, and reports to GNU Stow and calcurse that await a maintainer response. The devtodo finding stands in this repository, deliberately unreported upstream; one further claim, against buku, was withdrawn on re-derivation — the recorded evidence was Sideeye's own falsification gate, and buku recovers in every measured world (`spike/assisted/buku/RUNLOG.md`). Verdicts are deterministic: a target Sideeye cannot fully observe is UNKNOWN, never a silent PASS.

**Status: v0.9.0**, trace contract v10. The Define contract, the report schema and the exit codes are **not frozen** until 1.0 and may change in any release. Release history: [CHANGELOG.md](CHANGELOG.md); the road to 1.0: [PRD.md](PRD.md).

## Installation

Every release from v0.6.0 on ships prebuilt tarballs for x86_64-linux, aarch64-linux and aarch64-macos (earlier tags predate the artifacts): `sideeye`, `libsideeye_shim` — the shim travels with the binary, it is half the product — and both license files. Download the tarball for your platform from [Releases](https://github.com/yottayoshida/sideeye/releases), then:

```
$ tar xzf sideeye-v0.9.0-aarch64-macos.tar.gz && cd sideeye-v0.9.0-aarch64-macos
```

Or build from source with Zig 0.16.0: `zig build` — binaries land in `zig-out/bin` and `zig-out/lib`.

## Usage

Three commands, in the order you will meet them.

**1. See it work** — sixty seconds, needs a C compiler (`cc`, `gcc` or `clang`), writes nothing permanent:

```
$ ./sideeye demo
```

The demo compiles a small planted-bug tool, explores it, and prints a real FAIL report. **Exit 1 — the planted bug found — is success**, which makes the demo double as a smoke test of the binary + shim pair.

**2. Ask whether Sideeye can watch your tool** — before writing any config:

```
$ ./sideeye preflight --state <dir> --operation "<cmd>"
```

One observed run: either `recording accepted` (exit 0, with the `explore` command to graduate to) or a refusal naming the same detector a real run would use (exit 2). What only a real exploration can check is listed as `not checked`, never silently claimed.

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
marker    = "Recorded"          # optional: the operation's own success claim (L1)
expected_status = "3"           # optional: the exit status that means "completed"
                                # (default "0") — for git-style conventions
```

The same define works as flags (`--state`/`--setup`/`--operation`/`--check`/`--marker`/`--expect-status`); `--json <path>` writes the identical report for a machine to branch on. Exit codes: **0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR** — and UNKNOWN is never 0. Command strings split on spaces, no quoting; anything an argument cannot spell belongs in a script file (ADR 0007).

A FAIL saves its counterexample to `<work>/cases/NNNNNN.json` and prints the ready-to-paste `sideeye replay <case.json>` line. Replay re-runs the same pipeline — every trust gate included — restricted to that crash point; when the code changed underneath the case, the answer is `case no longer applies`, never a verdict about a shifted address.

## Example

Real output, regenerated for this release: the same planted delete-before-rename bug the demo uses (`spike/toys/toy.c`), explored with a checker and the strace oracle. A bare `sideeye demo` prints the same report shape; here the `oracle` and `metadata` lines carry measured values instead of "not run", and the paths are the container's. The command and its output, verbatim as run (the engine itself hands the target its state directory — `TOY_STATE` is set to `--state` for every child):

```
$ TOY=/tmp/se/toy-bug /work/zig-out/bin/sideeye explore --state /tmp/se/state \
    --setup "/tmp/se/toy-bug init" --operation "/tmp/se/toy-bug rotate" \
    --check /work/spike/check.sh --shim /work/zig-out/lib/libsideeye_shim.so \
    --work /tmp/se/work --oracle /usr/bin/strace

FAIL  1 of 6 crash worlds violated an invariant

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

Read the account block, not just the verdict: `explored` says how much was looked at, `oracle` says a second witness (strace) checked the shim's account against the kernel's, `checker` says the invariant was proven able to fail before the run began, and `not tested` names what this verdict is silent about. A report that only said FAIL would be asking to be believed.

The `check` script is where your invariants live. This one cross-examines the tool's own diagnostic — the invariant is not "the key is readable" (a tool is allowed to be broken as long as it says so) but "the claim and the observable truth agree":

```sh
#!/bin/sh
claim=$("$TOY" doctor 2>/dev/null) || claim="unhealthy"
"$TOY" load-key >/dev/null 2>&1 && reality="loadable" || reality="unloadable"

case "$claim:$reality" in
    healthy:loadable | unhealthy:unloadable) exit 0 ;;
    *) echo "doctor says '$claim' but the key is $reality" >&2; exit 1 ;;
esac
```

The full version is [`spike/check.sh`](spike/check.sh). Sideeye refuses to trust a checker it has not seen fail: before exploring, it corrupts the state — every file overwritten, every symlink retargeted — and requires the check to reject it. A checker that cannot fail makes the run UNKNOWN, not PASS. More worked checkers, and the failure patterns that taught them: [docs/checker-cookbook.md](docs/checker-cookbook.md).

## What the target has to be

Sideeye refuses to guess. Anything outside these limits is UNKNOWN (exit 2) with the refusing detector named:

- **Dynamically linked and single-threaded**, reaching its files through libc — buffered stdio, the hard-link family and symlink creation included. State-changing raw syscalls (writes that bypass libc), static linking, hardened runtimes and threads are refused; read-only raw opens are tolerated, which is what let a `rustix`-carrying Rust target clear a full run (#19). A descriptor's *location* decides observation, never its number: a state file rebound onto stdout with `dup2` is still seen, and startup descriptor-hygiene sweeps are tolerated (ADR 0013).
- **State in one directory**, declared with `--state` or the toml's `[world] state`. Symlinks inside it are first-class (snapshotted and restored as links, target verbatim); ownership/permission changes are observed but outside the judged state, and every report says so.
- **A clean run exits its declared success status** (`--expect-status`, default 0) — the crash points are read off that run.
- **Other processes stay away from the state.** Forked helpers are fine when the oracle (`--oracle`, Linux) confirms nobody else touched it; a target that `exec`s over itself is judged when the chain of observation survives the image change (contract v10 carries the operation count across it) and refused when it does not, and a process that escapes Sideeye's containment group is refused. Without an oracle any process boundary is UNKNOWN, full stop — the shim only sees processes that load it, and "was not seen" is not "did nothing". For single-process targets with no oracle, a PASS requires `--allow-unverified`, and the report says the weaker claim out loud.

How real tool classes have fared against these limits — verdicts and named walls, each backed by a recorded run: [docs/target-classes.md](docs/target-classes.md).

The full contract, and the reason behind each refusal: [DESIGN.md](DESIGN.md).

## Driving it from an agent (MCP)

`sideeye mcp` is a stateless MCP server (stdio) with two tools: `sideeye_explore_config {config_path}` and `sideeye_replay_case {case_path}`. The tools take *paths* inside `SIDEEYE_MCP_ROOT`, never raw commands — the config file is the trust boundary you vet. Operational settings come from `SIDEEYE_MCP_*` environment variables (shim, root, oracle, work dir, and an explicit allowlist of variable names the target may read); the child runs with a near-minimal environment and its output never touches the MCP transport. Details: ADR 0010 and 0011.

The root confines *which* config may be named — it is not a sandbox for what that config's operation does: a vetted config's operation can still read `$HOME`, reach the network, or write outside the workspace. For agent-driven use, run the server inside a container or an otherwise restricted workspace, network-off where the target allows it; the loop-closure runs are the worked example (sealed container, mount discipline).

### What an agent has already done here, measured

Two agent workflows are recorded facts in this repository, not aspirations:

- **Writing the fix from the report.** A context-free coding agent, handed only the counterexample — the report JSON, the case it names, the invariant it points at, bug-blind replay plumbing — and the target's pinned checkout, produced the fix and the judge's own replay passed, feature intact. Measured twice: once through the CLI plumbing, once through this MCP server (`spike/loop-closure-timew/`).
- **Writing the define.** An LLM scout, working under a fixed scouting protocol (assisted, never blind — it may read source, docs, tests, anything, and its contacts are recorded), authored the committed defines for five real targets in 1m25s–5m02s each; re-run unmodified, four of the five reached verified, replay-confirmed counterexamples, and the fifth is a named refusal on a deliberate contract gap (`spike/assisted/`).

What is *not* measured: an agent — or anyone — setting Sideeye up from this README alone; that path has no recorded run yet. The doors an agent needs are the report schema ([docs/report-schema.md](docs/report-schema.md)), the CI quickstart ([docs/ci-quickstart.md](docs/ci-quickstart.md)), and the MCP surface above.

## What Sideeye is not

- **Not property-based testing** — it varies the world the program runs in, not the input.
- **Not an AI code reviewer** — verdicts are deterministic; a language model never decides PASS or FAIL.
- **Not a chaos platform** — one binary, ordinary software, local state.
- **Not a certification** — a PASS is a search record, not a safety claim; every report names what was *not* tested. v0 scope is process crash × file-backed state: power loss, network faults, clocks and concurrency are out ([DESIGN.md](DESIGN.md) §9, §15).

## Documentation

| Document | What it is |
|----------|------------|
| [DESIGN.md](DESIGN.md) | What Sideeye is, and what it refuses to be |
| [PRD.md](PRD.md) | The road from v0.1 to v1.0 |
| [CHANGELOG.md](CHANGELOG.md) | Releases |
| [BUILDLOG.md](BUILDLOG.md) | Decisions as they happen, including the wrong ones |
| [docs/report-schema.md](docs/report-schema.md) | Every field the JSON report carries, held to the code by CI |
| [docs/ci-quickstart.md](docs/ci-quickstart.md) | Running sideeye in GitHub Actions — the example is a live workflow |
| [docs/target-classes.md](docs/target-classes.md) | Real tool classes against the constraint list — verdicts and named walls, each row backed by a recorded run |
| [docs/checker-cookbook.md](docs/checker-cookbook.md) | Annotated real checkers, and the failure patterns that taught them |
| [docs/adr/](docs/adr/) | One record per irreversible decision — the descriptor contract (0013), links and symlinks (0006, #122), the MCP surface (0010, 0011), the blind protocol (0012) among them |

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT License](LICENSE-MIT), at your option.
