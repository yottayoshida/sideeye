# sideeye

<p align="center">
  <img src="docs/sideeye.jpg" alt="Sideeye — doesn't believe it" width="360">
</p>

> *Sideeye doesn't believe it.*

Sideeye finds out what your program leaves on disk when it dies at the worst possible moment. You declare an invariant — *"if this operation said it succeeded, this must still be true after a restart"* — and Sideeye kills your process immediately before each of its state-changing operations, one crash world per operation, then brings back the **earliest failing crash point**, saved as a replayable case. When that earliest world trips only the built-in comparison and some other world falsifies **your own checker**, the report carries that world as a second exhibit — usually the one worth reading, and the reason the first failing world alone is not always the whole answer. It breaks worlds, not inputs: same input, hostile universe.

It has produced replay-confirmed counterexamples against real tools — timewarrior, topydo, GNU Stow, calcurse, devtodo, himalaya — several of them reported upstream. Verdicts are deterministic: a target Sideeye cannot fully observe is UNKNOWN, never a silent PASS. One exception is named rather than hidden: a directory a recorded `rename` moved in from outside the judged tree is attributed to that one record, because its source was never snapshotted — so a later unrecorded write inside that subtree can still ride a PASS. Every report says how many paths that covered (`paths_attributed_to_rename`), and a run reporting zero has no such gap.

## Installation

```
$ brew install yottayoshida/tap/sideeye
```

Covers macOS on Apple silicon and Linux on x86_64 and aarch64. Everything below then works from `PATH`.

Or take the tarball for your platform from [Releases](https://github.com/yottayoshida/sideeye/releases). Sideeye ships as a binary **and** a shim library, and it looks for the shim beside itself before `../lib`, so run it from the directory you untarred — or pass `--shim`:

```
$ tar xzf sideeye-v1.0.0-aarch64-macos.tar.gz && cd sideeye-v1.0.0-aarch64-macos
$ ./sideeye version
```

Or build from source with Zig 0.16.0: `zig build` — binaries land in `zig-out/bin` and `zig-out/lib`, which is the same shape.

## Usage

Three commands, in the order you will meet them.

**1. See it work** — sixty seconds, needs a C compiler, writes nothing permanent:

```
$ sideeye demo
```

The demo compiles a small planted-bug tool, explores it, and prints a real FAIL report. Exit 1 — the planted bug found — is success, which makes the demo double as a smoke test of the binary + shim pair.

**2. Ask whether Sideeye can watch your tool** — before writing any config:

```
$ sideeye preflight --state <dir> --operation "<cmd>"
```

One observed run: either `recording accepted` (exit 0) or a refusal naming the same detector a real run would use (exit 2).

Add `--twice` and it observes a second run from the restored pre-state, at least two seconds later, and compares the two. Byte repeatability is a property of two runs — one observation structurally cannot see it, and a tool that rewrites a timestamp on every run passes everything else preflight asks and is refused only once a full define has been written and explored. Equal post-states: exit 0. Different: the differing paths are named and the command exits 1, which is the negative answer to the question `--twice` asked, not a FAIL verdict — preflight produces none. What it does not establish is that the target is deterministic: the comparison covers file bytes, entry kinds and symlink targets under `--state`, and two runs are not all runs.

**3. Explore** — the real thing, with the whole define in one file:

```
$ sideeye explore --config sideeye.toml --oracle /usr/bin/strace
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
cwd       = "./repo"            # optional: where the three commands run (default: sideeye's own cwd)
```

- The same define works as flags: `--state` / `--setup` / `--operation` / `--check` / `--marker` / `--expect-status` / `--cwd`.
- `--shim` names the interposition library when it is not beside the binary (the tarball and zig-out layouts are found on their own); `--work` moves the scratch directory for traces and cases (default `/tmp/sideeye-work`).
- `--json <path>` writes the same report as JSON, for a machine to branch on.
- `--fresh-state` (replay only) empties and recreates the case's state directory before setup, for a caller that cannot hand over a pristine one — a second replay in the same directory would otherwise die in the leftovers of the first.
- Exit codes: **0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR** — and UNKNOWN is never 0.
- Command strings split on spaces, no quoting. An argument that carries a space uses the argv form instead: `operation = ["mytool", "commit", "-m", "a message with spaces"]` — one line, passed verbatim.
- `preflight` reads flags only; a define spelled as argv goes straight to `explore --config`.

A FAIL saves its counterexample to `<work>/cases/NNNNNN.json` and prints the ready-to-paste `sideeye replay` line. When some world failed your checker and it is not the overall earliest, that world is saved as its own case beside the first and the text report gains a `checker red` section naming it — two files, both replayable; one file when the two exhibits are the same world, and none of this when no world failed the checker. Replay re-runs the same pipeline restricted to that crash point; when the code changed underneath the case, it says `case no longer applies` instead of guessing. The path you hand it has to be an ordinary file: a pipe, a device or a process substitution is refused rather than read, because a case that cannot be read whole is not a case — and because reading one that never ends would leave the run with no exit code at all (#400).

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
metadata    none observed. Restore does not reproduce ownership/permission/timestamp state: crash worlds run at the engine's default modes, with timestamps assigned during restore
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
- **Other processes stay away from the state.** Forked helpers are fine when the strace oracle (`--oracle`, Linux) confirms nobody else touched it. On macOS, `--oracle-fs-usage` buys the same comparison for a single-process run — it pays root once per run and refuses rather than prompting — but cannot account for other processes, so a process boundary under it is UNKNOWN. Without an oracle any process boundary is UNKNOWN. For a single-process target with no oracle, a PASS requires `--allow-unverified`, and the report says the weaker claim out loud.

How real tool classes have fared against these limits: [docs/target-classes.md](docs/target-classes.md). The full contract, and the reason behind each refusal: [DESIGN.md](DESIGN.md).

## Driving it from an agent (MCP)

`sideeye mcp` is a stateless MCP server (stdio) with two tools: `sideeye_explore_config {config_path}` and `sideeye_replay_case {case_path}`. The tools take *paths* inside `SIDEEYE_MCP_ROOT`, never raw commands — the config file is the trust boundary you vet, **and a saved case is the same boundary**: its setup/operation/check are executed on replay, exactly as a config's are on explore. The root confines which config or case may be named, not what its commands do: run the server inside a container, network-off where the target allows it. A single-component mount is fine (`/work`, `/repo` — a directory the container exists to hold); what the server refuses at startup is `/`, a system tree or scratch parent (`/usr`, `/var/lib`, `/tmp`), **and any directory that contains one** — so `/var` and, on macOS, `/private` are refused for holding `/var/lib` and `/private/tmp`. The denylist stops the mistake that has a name, not every bad choice: **with `SIDEEYE_MCP_STATE_ROOT` unset the root is also the declared destruction range**, so name a directory whose contents are yours to lose — `/opt` passes the vet and is where installed software lives. One thing more IS confined (#266): the state directory a replayed case names — the directory replay empties and rebuilds — must resolve strictly inside `SIDEEYE_MCP_STATE_ROOT` (default: the root). Cases made at the CLI conventionally keep state under `/tmp`; set `SIDEEYE_MCP_STATE_ROOT=/tmp` to replay them through the server. Widen that knob, never the root (ADR 0022).

### The first call

The server speaks MCP schema **2026-07-28**. Two consequences a client written against an older mental model will meet immediately: there is no `initialize` — the server exposes `server/discover`, and `tools/list` works without either — and **`_meta` is per-request and mandatory**, with the protocol version and client capabilities under their namespaced keys exactly as spelled below.

Everything the server reads from its environment:

| Variable | Required | Meaning |
|---|---|---|
| `SIDEEYE_MCP_ROOT` | **yes** | The directory tool paths are confined to, vetted at startup (above). |
| `SIDEEYE_MCP_SHIM` | no | An override. Unset, the server looks where the install note above says it looks: beside the binary, then `../lib` — the same order the CLI uses, so a tarball and a Homebrew install both resolve with nothing set. Until #389 this command demanded the variable instead, which made it the one place the product did not do what that sentence promises. **That search trusts the install directory**: whoever can write `bin/` or `../lib` chooses the library injected into your target, and a symlink there is followed. This is how the CLI has resolved the shim since #78 — it is the product's posture, not a property of the server — but it is now this command's posture too. Where that directory is not yours alone, set this variable, or fix the permissions. Closing it product-wide is #423. |
| `SIDEEYE_MCP_STATE_ROOT` | no | Where a replayed case's state directory may live. Default: the root (ADR 0022). |
| `SIDEEYE_MCP_WORK` | no | Scratch for traces and cases. Default `/tmp/sideeye-mcp`. |
| `SIDEEYE_MCP_ORACLE` | no | The second witness. Without one a would-be PASS refuses as `completeness_not_verified`; a FAIL stands on its own evidence either way. |
| `SIDEEYE_MCP_CHILD_ENV` | no | Comma-separated names of variables to pass through to the target. Nothing else reaches it (ADR 0011). |

One value is yours to supply, and it is written as `/path/to/…`. Nothing else has to be set:

```sh
export SIDEEYE_MCP_ROOT=/path/to/your/workspace
```

With a `sideeye.toml` in that workspace — the Usage section above shows the shape; fill it in for your own tool — this reaches a verdict, or refuses with a named reason:

```jsonrpc
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}},"name":"sideeye_explore_config","arguments":{"config_path":"/path/to/your/workspace/sideeye.toml"}}}
```

`isError` follows the verdict structure, not the outcome: a FAIL is a real answer and comes back `false` (ADR 0010). **Both blocks are run on every pull request and every push to main, extracted from this page, against the built server, with nothing else in the environment** — on Linux as `spike/mcp-acceptance.sh` check 15 and on macOS as a step of its own, both calling `spike/check-readme-mcp-call.sh`. They are a record of what the server does today, not an addition to the frozen surface — what v1.0 froze is the two tool names, their input schemas and that `isError` rule (`docs/contract-freeze.md`, surface 5).

Measured here, not aspirations: a context-free agent, handed a counterexample and bug-blind replay plumbing, produced the fix — twice: once through the CLI, once through this MCP server (`spike/loop-closure-timew/`) — an LLM scout authored the defines for five real targets under a fixed protocol (`spike/assisted/`; the method: [docs/scouting.md](docs/scouting.md)), and a context-free agent set Sideeye up **from the README alone** — tarball to a real verdict on an external tool in under five minutes, protocol declared before the clock, measured twice (`spike/onboarding-clock/`: run 1 at 4 m 22 s, 2026-08-17; run 2 at 2 m 55.7 s, 2026-08-28, against this page as it stood at the freeze — the criterion's evidence).

## What it is for after the first find

The finding is not the durable artifact — the declaration is. A `sideeye.toml` and its checker are the question, not the answer, so re-asking it after the tool changes is `explore --config` again, and the report says what it looked at that time rather than assuming the last run still holds. A saved case is deliberately narrower: it names one crash point in one recording, and when the recording moves underneath it the answer is `case no longer applies` rather than a silent pass — which is what makes a case worth keeping in CI. This repository keeps its own oldest finding that way, re-recorded under the current trace contract on every push to main and every pull request (the `timew-regression` job in `.github/workflows/ci.yml`). And because a target Sideeye cannot fully observe is UNKNOWN and never exit 0, a machine caller can tell *checked and clean* from *not checked*, which is the distinction an unattended run has to get right. What none of that does is constrain what your declared operation may do — that boundary is the config you vet, as the MCP section above says.

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
| [docs/scouting.md](docs/scouting.md) | Handing the repo-reading to an agent — and how capable that agent has to be |
| [docs/target-classes.md](docs/target-classes.md) | Real tool classes against the constraint list, each row backed by a recorded run |
| [docs/unknown-rate.md](docs/unknown-rate.md) | How often Sideeye refuses instead of judging — measured on a corpus frozen before the sweep ran, with the threshold set from the data |
| [docs/kill-criteria-review.md](docs/kill-criteria-review.md) | The project's own conditions for abandoning it, scored against the collected data |
| [docs/checker-cookbook.md](docs/checker-cookbook.md) | Annotated real checkers, and the failure patterns that taught them |
| [docs/contract-freeze.md](docs/contract-freeze.md) | What v1.0 freezes, and what a break would cost — the normative list |
| [docs/freeze-audit.md](docs/freeze-audit.md) | Every open issue classified against those frozen surfaces, generated from a committed manifest and held to a committed snapshot |
| [docs/adr/](docs/adr/) | One record per irreversible decision |

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT License](LICENSE-MIT), at your option.
