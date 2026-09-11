# The CLI in full

The README carries the shortest path to a first verdict. This page carries the rest: installing without Homebrew, every flag and what it refuses, what a saved case is and how replay reads it, a full report with the checker that produced it, and what the declaration is for once the first finding is in.

## Installing without Homebrew

Take the tarball for your platform from [Releases](https://github.com/yottayoshida/sideeye/releases). Sideeye ships as a binary **and** a shim library, and it looks for the shim beside itself before `../lib`, so run it from the directory you untarred — or pass `--shim`. That search declines a candidate it cannot attribute (a symlink, or a file someone else owns), so an install directory that is not yours alone is refused by name rather than trusted:

```
$ tar xzf sideeye-v1.3.0-aarch64-macos.tar.gz && cd sideeye-v1.3.0-aarch64-macos
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
operation = "mytool rotate-key" # the shim is inserted into this one, not into setup or check
check     = "./check.sh"        # exit 0 = invariant holds; runs after crash + restart
marker    = "Recorded"          # optional: the operation's own success claim
expected_status = "3"           # optional: the exit status that means "completed" (default "0")
cwd       = "./repo"            # optional: where the three commands run (default: sideeye's own cwd)
apparatus = ["env:FAKETIME=@2024-01-01 00:00:00", "preload:libfaketime"]   # optional: what the operation's environment must carry
scratch   = ["COMMIT_EDITMSG", ".hg/wcache"]   # optional: paths under state the built-in invariants leave alone
```

- The same define works as flags: `--state` / `--setup` / `--operation` / `--check` / `--marker` / `--expect-status` / `--cwd` / `--apparatus` (repeatable) / `--scratch` (repeatable). `operation` is **the one command the shim is inserted into**; `setup` and `check` are ordinary commands and may be scripts. What that means for a `#!` script: the kernel hands execution to the interpreter, so the insertion has to reach *that* image rather than the file you named. Whether it can is a property of the interpreter and of the machine — a statically linked one takes no insertion anywhere, and on macOS a platform binary such as `/bin/sh` may have the variable stripped before it starts — so the same define can reach a verdict on one machine and refuse with `no_shim_marker` on another. Naming an executable image directly takes the question away.
- `apparatus` names the devices a deterministic run depends on — a faked clock, a pinned `os.urandom`, a stand-in compiler — so the define is the whole question and the report says what it ran under. Sideeye applies none of it; after `setup` it checks that each `env:`, `preload:` (a line of `/etc/ld.so.preload`) and `pythonpath:` entry is present in the environment the operation inherits and refuses the run as SETUP ERROR when one is not. `note:` entries are carried unchecked. Recipes and the one thing to know about global preloads: [docs/apparatus.md](apparatus.md).
- `scratch` names the paths under `state` that nobody depends on — git's `COMMIT_EDITMSG`, a tool's own cache — each entry covering the path itself and everything beneath it. The built-in invariants judge none of them, in no world: not their bytes, not their presence, whether the recording had them before, after, or both, so a torn scratch file no longer decides the verdict and a scratch file whose bytes differ between two clean runs no longer refuses the run. The price is paid in the open: the report carries the declaration verbatim, its `atomicity` line says how many recorded paths the declaration matched, `not tested` names it, and the saved case carries it (a define that declared everything reads `0 path(s) judged pre-or-post` beside its PASS). What scratch does not silence: a state that changed with no operation recorded, a child the engine could not account for, an entry kind or a file size the snapshot refuses, a tree still being written when it is sampled twice — those are about what the engine observed, not about what is durable. And a checker is still the only thing that says the state is *correct*; scratch only stops the built-in layers from saying it is not (ADR 0043).
- Every command Sideeye runs — your setup, operation and checker among them — starts with its standard input at end-of-file, on the CLI and MCP paths alike. A target that reads stdin sees EOF, never the terminal or pipe Sideeye itself was started from: that input is the caller's, not the define's, and a committed define has to mean the same run everywhere.
- `--shim` names the interposition library when it is not beside the binary (the tarball and zig-out layouts are found on their own). The search that finds it on its own **declines a candidate it cannot attribute** — a symlink, or a file owned by none of {you, root, the owner of the `sideeye` binary} — and says so rather than using it (#423, ADR 0044); a path you pass here is used as named and not checked. The check is a mitigation, not a boundary: it inspects a pathname, and the dynamic linker resolves that pathname again when the target starts. `--work` moves the scratch directory for traces and cases (default `/tmp/sideeye-work`). **A symlink at the trace path is refused rather than followed — by every process the shim is loaded into when it writes the trace (#488), and by the engine when it reads that trace back (#489).** The engine removes the file before each run, but every process the shim reaches opens the name again afterwards and the later ones have nothing standing in front of them, so without the write-side refusal a link planted there would append the run's records to whatever it points at; without the read-side one, the account the verdict is drawn from would be whatever that link pointed at. A **FIFO** appearing at that path after the engine's own removal of it is refused on both sides as well: the read takes regular files only (#400), and the write does two things that answer different cases (#492): it opens **non-blocking**, so a FIFO with no reader fails outright instead of waiting for one — this is the half that stops the wait, in a constructor that runs before the target's `main`, inside a recording run with nothing to time it out — and it then asks what the descriptor turned out to be, closing it unless it is an ordinary file, which is the half that catches a FIFO somebody is already reading, along with a device or a socket. The one thing the write side leaves standing is a kind it could not read at all, a `statx` that fails: a host lacking it goes on refusing with `unresolvable_path`, which names a cause, rather than with a silence that names none. What is **not** refused: a **hard link** is the same file rather than a pointer to one, so no open flag sees it, on either side. Nor is the target on the other side of a boundary here — it holds the trace path in its own environment and can write the work directory, so a target that wants to hand Sideeye a trace it wrote itself is not something this or any flag stops.
- `--json <path>` writes the same report as JSON, for a machine to branch on.
- `--fresh-state` (replay only) empties and recreates the case's state directory before setup, for a caller that cannot hand over a pristine one — a second replay in the same directory would otherwise die in the leftovers of the first.
- Exit codes: **0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR** — and UNKNOWN is never 0.
- Command strings split on spaces, no quoting. An argument that carries a space uses the argv form instead: `operation = ["mytool", "commit", "-m", "a message with spaces"]` — one line, passed verbatim.
- `preflight` reads flags only; a define spelled as argv goes straight to `explore --config`.

A FAIL saves its counterexample to `<work>/cases/NNNNNN.json` and prints the ready-to-paste `sideeye replay` line. When some world failed your checker and it is not the overall earliest, that world is saved as its own case beside the first and the text report gains a `checker red` section naming it — two files, both replayable; one file when the two exhibits are the same world, and none of this when no world failed the checker. Replay re-runs the same pipeline restricted to that crash point; when the code changed underneath the case, it says `case no longer applies` instead of guessing. The path you hand it has to be an ordinary file: a pipe, a device or a process substitution is refused rather than read, because a case that cannot be read whole is not a case — and because reading one that never ends would leave the run with no exit code at all (#400). A relative `define.state` inside a case resolves **against the case file's own directory**, the way a relative path in a `sideeye.toml` resolves against the toml (ADR 0007) — so the same case names the same state directory from anywhere, and replay empties the directory the case meant rather than one named by whoever happened to invoke it. Cases this engine saves always store the resolved absolute path, so this rule is about the hand-written ones.

### The flags the define does not spell

Six flags never appear in a `sideeye.toml`: they belong to the run rather than to the question.

- `--observe wrappers|syscalls` — where operations are counted. The default, `wrappers`, counts at the interposed libc entry points, with buffered stdio observed at flush granularity. `syscalls` (Linux) counts at the kernel boundary instead, through a seccomp filter and a `SIGSYS` handler inside the target's own process — the only way to see an operation libc issues from *inside* itself (an `fwrite` past the buffer), or one that never reaches libc at all: a raw `syscall(SYS_write, ...)`, or a runtime like Go's that issues every file call directly. Its trap set is every operation that can be a crash point. Check the second entry of the README's constraint list before reaching for it: under this mode an `exec`'d image the shim cannot be loaded into dies at its first state-changing call, which is the one limit that changes what the target does instead of making Sideeye refuse.
- `--oracle-fs-usage` — the macOS oracle, in place of `--oracle`. It compares the recording run against `fs_usage`, which needs root, so `sudo` must already hold credentials (`sudo -v` first, in the same terminal — the cache is per-terminal); the run refuses rather than prompting. Narrower than strace by two measured limits: `fs_usage` prints only a rename's old path, and it cuts long pathnames from the left, so a rename it cannot match and a state directory deep enough to be cut are refusals rather than agreements. It cannot account for other processes, so a process boundary under it is UNKNOWN, and a threaded run is refused.
- `--allow-unverified` — accept a PASS with no completeness check. On macOS this is the answer when no privilege is available: SIP leaves DTrace's syscall provider with no probes even as root, and the one candidate that measured oracle-shaped, `fs_usage`, requires it. The report says which claim was made, and this one is weaker.
- `--world-timeout <s>` — a wall-clock budget per explored world (1 to 86400, off by default). A world's operation still running when the budget expires is sent `SIGKILL` and refused UNKNOWN `child_timed_out`, with the budget in the message. Worlds only: a recording run, a setup command or a checker that hangs still hangs, so this is not a promise of a hang-free run.
- `--stop-when-orphaned` — stop at the next world boundary if the process that launched the run exits (UNKNOWN, `parent_exited`). The MCP server passes it on every explore and replay: agent hosts restart MCP servers routinely, and an orphaned exploration otherwise keeps killing processes and rewriting its state directory with nobody left to report to. A run that hangs before a boundary is out of reach.
- `--state-under <dir>` (replay only) — the directory a case's state must resolve strictly inside; anything else is refused before setup runs. A case file names its own state directory, and this is how a caller that vetted only the case's path bounds where the case may point the deletion. The MCP server passes its `SIDEEYE_MCP_STATE_ROOT` (default: the server root) on every replay.

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

The full version is [`spike/check.sh`](../spike/check.sh). Sideeye refuses to trust a checker it has not seen fail: before exploring, it corrupts the state and requires the check to reject it. A checker that cannot fail makes the run UNKNOWN, not PASS. More worked checkers: [docs/checker-cookbook.md](checker-cookbook.md).

## What it is for after the first find

The finding is not the durable artifact — the declaration is. A `sideeye.toml` and its checker are the question, not the answer, so re-asking it after the tool changes is `explore --config` again, and the report says what it looked at that time rather than assuming the last run still holds. A saved case is deliberately narrower: it names one crash point in one recording, and when the recording moves underneath it the answer is `case no longer applies` rather than a silent pass — which is what makes a case worth keeping in CI. This repository keeps its own oldest finding that way, re-recorded under the current trace contract on every push to main and every pull request (the `timew-regression` job in `.github/workflows/ci.yml`). And because a target Sideeye cannot fully observe is UNKNOWN and never exit 0, a machine caller can tell *checked and clean* from *not checked*, which is the distinction an unattended run has to get right. What none of that does is constrain what your declared operation may do — that boundary is the config you vet, as [the MCP page](mcp.md) says.
