# sideeye

<p align="center">
  <img src="docs/sideeye.jpg" alt="Sideeye — doesn't believe it" width="360">
</p>

> *Sideeye doesn't believe it.*

Sideeye finds out what your program leaves on disk when it dies at the worst possible moment. You declare an invariant — *"if this operation said it succeeded, this must still be true after a restart"* — and Sideeye kills your process before each state-changing operation, one crash world each, then brings back the earliest failing one as a replayable case. It breaks worlds, not inputs: same input, hostile universe.

It has found replay-confirmed counterexamples in real tools — timewarrior, topydo, GNU Stow, calcurse, himalaya — several reported upstream. Verdicts are deterministic, and a target Sideeye cannot fully observe is UNKNOWN, never a silent PASS. One exception is named rather than hidden: a directory a recorded `rename` moved in from outside the judged tree is attributed to that one record, because its source was never snapshotted — so a later unrecorded write inside that subtree can still ride a PASS. Every report says how many paths that covered (`paths_attributed_to_rename`), and a run reporting zero has no such gap.

## Installation

```
$ brew install yottayoshida/tap/sideeye
```

macOS on Apple silicon, Linux on x86_64 and aarch64. Sideeye is a binary and a shim library, and it looks for the shim beside itself before `../lib`, so a Homebrew install and an untarred release both work as they are. Or take the tarball for your platform from [Releases](https://github.com/yottayoshida/sideeye/releases) and run it where you unpacked it:

```
$ tar xzf sideeye-v1.3.0-aarch64-macos.tar.gz && cd sideeye-v1.3.0-aarch64-macos
$ ./sideeye version
```

Building from source, and what the shim search refuses: [docs/cli.md](docs/cli.md#installing-without-homebrew).

## Usage

Three commands, in the order you will meet them.

```
$ sideeye demo
$ sideeye preflight --state <dir> --operation "<cmd>"
$ sideeye explore --config sideeye.toml --oracle /usr/bin/strace
```

- **`demo`** — sixty seconds, needs a C compiler, writes nothing permanent. It compiles a tool with a planted bug, explores it, prints a real FAIL report. Exit 1 — the bug found — is success, so it doubles as a smoke test of binary and shim.
- **`preflight`** — can Sideeye watch your tool? One observed run: `recording accepted` (exit 0), or a refusal naming the detector a real run would use (exit 2). `--twice` also checks that two clean runs leave the same bytes.
- **`explore`** — the real thing, with the whole define in one file:

```toml
[world]
state = "./state"               # the one directory your tool's state lives in

[define]
setup     = "mytool init"
operation = "mytool rotate-key" # the shim is inserted into this one, not into setup or check
check     = "./check.sh"        # exit 0 = invariant holds; runs after crash + restart
```

- `operation` is the one command the shim is inserted into; `setup` and `check` are ordinary commands. Naming an executable image rather than a `#!` script keeps the insertion independent of the interpreter.
- Command strings split on spaces, no quoting. An argument with a space takes the argv form: `operation = ["mytool", "commit", "-m", "a message"]`.
- `--oracle` is a second witness, checking the shim's account against the kernel's (strace on Linux). Without one, a single-process target reaches PASS only under `--allow-unverified`, and the report says so.
- `--shim` names the shim when it is not beside the binary; `--work` moves the scratch for traces and cases (default `/tmp/sideeye-work`); `--json <path>` writes the report as JSON too.
- Exit codes: **0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR** — and UNKNOWN is never 0.

A FAIL saves its counterexample under `<work>/cases/` and prints the `sideeye replay` line that re-runs it. Every flag, the optional define keys, replay: [docs/cli.md](docs/cli.md).

## Writing the check

The check is where your invariants live. This one cross-examines the tool's own diagnostic — a tool may be broken as long as it says so; the violation is the claim and the observable truth disagreeing:

```sh
claim=$("$TOY" doctor 2>/dev/null) || claim="unhealthy"
"$TOY" load-key >/dev/null 2>&1 && reality="loadable" || reality="unloadable"
case "$claim:$reality" in
    healthy:loadable | unhealthy:unloadable) exit 0 ;;
    *) echo "doctor says '$claim' but the key is $reality" >&2; exit 1 ;;
esac
```

Sideeye refuses to trust a checker it has not seen fail: before exploring, it corrupts the state and requires the check to reject it. A checker that cannot fail makes the run UNKNOWN, not PASS. The report this one produced: [docs/cli.md](docs/cli.md#example). More checkers: [docs/checker-cookbook.md](docs/checker-cookbook.md).

## What the target has to be

Sideeye refuses to guess. Anything outside these limits is UNKNOWN (exit 2), with the refusing detector named and a `next_step` saying what to do. Each limit's reason: [DESIGN.md](DESIGN.md#known-constraints-declared-not-hidden).

- **Dynamically linked**, reaching its files through libc. Static linking and hardened runtimes are refused. Threads are judged while one thread of each process writes the state. `--observe syscalls` (Linux) also counts the operations that bypass libc — a Go runtime's, above all.
- **Under `--observe syscalls`, an `exec`'d image the shim cannot be loaded into dies at its first state-changing call.** Every other limit makes Sideeye refuse; this one changes what the target does — check it before reaching for the flag.
- **Under `--observe syscalls` the shim keeps `SIGSYS` deliverable**, which a target can notice.
- **The shim's footprint on a target thread is bounded**: under 1 KiB of thread-local storage, at most 5 KiB of stack per interposed call (measured on Linux).
- **State in one directory**, declared with `--state` or the toml. Symlinks inside it are snapshotted and restored as links.
- **A clean run exits its declared success status** (default 0) — the crash points are read off that run.
- **Byte-repeatable writes.** A second clean run must leave the same bytes under `--state`; `preflight --twice` measures this before you write a define.
- **Other processes take turns with the state.** Forked helpers are judged under an oracle, provided no two processes' writes interleave and every writing child is reaped. Without an oracle, any process boundary is UNKNOWN.

## Driving it from an agent

`sideeye mcp` is a stateless MCP server with two tools, `sideeye_explore_config` and `sideeye_replay_case`. A config and a saved case are both commands it will run, and a replayed case empties the state directory it names — so run it in a container, over a directory made for it: [docs/mcp.md](docs/mcp.md).

## After the first find

The finding is not the durable artifact — the declaration is. Re-ask after the tool changes with `explore --config`; a saved case answers `case no longer applies` rather than passing silently once the recording moves under it, which is what makes one worth keeping in CI ([docs/ci-quickstart.md](docs/ci-quickstart.md)).

## What Sideeye is not

- **Not property-based testing** — it varies the world the program runs in, not the input.
- **Not an AI code reviewer** — verdicts are deterministic; a language model never decides PASS or FAIL.
- **Not a chaos platform** — one binary, ordinary software, local state.
- **Not a certification** — a PASS is a search record, not a safety claim, and every report names what was *not* tested. Scope is process crash × file-backed state.

## Documentation

| Document | What it is |
|----------|------------|
| [docs/cli.md](docs/cli.md) | Every flag, cases and replay, a full report |
| [docs/mcp.md](docs/mcp.md) | The MCP server: setup, confinement, first call |
| [DESIGN.md](DESIGN.md) | What Sideeye is, what it refuses to be, and why |
| [docs/report-schema.md](docs/report-schema.md) | Every field of the JSON report |
| [docs/target-classes.md](docs/target-classes.md) | Real tool classes against the limits |
| [docs/unknown-rate.md](docs/unknown-rate.md) | How often Sideeye refuses instead of judging |

Also: [docs/checker-cookbook.md](docs/checker-cookbook.md), [docs/ci-quickstart.md](docs/ci-quickstart.md), [docs/apparatus.md](docs/apparatus.md), [docs/contract-freeze.md](docs/contract-freeze.md), [CHANGELOG.md](CHANGELOG.md), [PRD.md](PRD.md), [BUILDLOG.md](BUILDLOG.md), [docs/adr/](docs/adr/) — and the rest of [docs/](docs/).

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT License](LICENSE-MIT), at your option.
