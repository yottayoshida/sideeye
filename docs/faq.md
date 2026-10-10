# Questions people ask first

One paragraph each, with a link to where the reasoning lives. The recipes and the two-places answer were run before they were written down; the runs are in [`spike/faq/2026-10-10/`](../spike/faq/2026-10-10/).

## Does it check my fsync?

No. Sideeye's crash is a process crash: the process is killed, the operating system survives, and every write the process completed is kept, synced or not ([the crash model](../DESIGN.md#the-crash-model-precisely)). So a missing `fsync` cannot make a run fail: a tool that writes a temporary file, closes it without syncing, and renames it over the original PASSes (measured, 4/4). What a process crash does lose is what never reached the kernel — bytes still in the program's own buffer — and the same tool renaming the file *before* closing it FAILs (measured, 1 of 4: `key.json` holding neither the old nor the new content). An `fsync` is itself a crash point on Linux; on macOS, an `fcntl(F_FULLFSYNC)` — what Rust's `sync_all` and Go's `Sync` call there — is not one (measured: the same Rust tool explores one crash point fewer). None of this says anything about power loss, where unsynced writes vanish and can be reordered. Power loss is outside the model; whether it becomes the next one is [#699](https://github.com/yottayoshida/sideeye/issues/699).

## How is this different from a `kill -9` loop, `strace -e inject`, ALICE or LazyFS?

- **A `kill -9` loop** kills at whatever moment the clock picks. Sideeye kills before each state-changing call in turn, one world per crash point, restores the state before every world, and brings back the earliest failing one as a case you can replay. It also checks its own count of operations against a second witness, and makes your checker fail once on a corrupted state before trusting it.
- **`strace --inject=SET:signal=SIGKILL:when=N`** delivers the signal on entering the N-th call — counted for each system call in the set separately, and for each traced thread separately ([strace(1)](https://man7.org/linux/man-pages/man1/strace.1.html)): one crash point per run, with choosing the set, numbering the points across calls and threads, restoring the state between runs and judging the result left to you. That loop is what Sideeye automates; strace is Linux only.
- **[ALICE](https://research.cs.wisc.edu/adsl/Publications/alice-osdi14.html)** (OSDI '14) takes a system-call trace of your workload and builds the states a file system could leave after a *system* crash — writes split and reordered under a model of the file system's persistence — then runs your checker on each. It asks the power-loss question Sideeye does not. Sideeye runs your actual program and kills it, and needs no model of the file system.
- **[LazyFS](https://github.com/dsrhaslab/lazyfs)** is a FUSE file system that keeps writes in its own cache until they are synced, and can drop that cache on command: power loss again, from below. It complements Sideeye rather than overlapping it.

## How long does it take?

Crash points times the cost of a world, plus one baseline world; a world restores and re-reads the whole state directory. Measured on one laptop without an oracle or a checker: under 0.2 s per world plus 1.4 to 2.2 ms per file per world, and a thousand crash points took 4.2 s on a one-file state and 30 s on a 20 MB one ([DESIGN.md](../DESIGN.md#known-constraints-declared-not-hidden), the bullet on cost). Your checker runs once in every world and adds its own time. The cheapest lever is a small state directory.

## How do I call it from pytest, cargo test or go test?

Run `sideeye explore` on a define that sits next to the test, and pass only on exit 0 **and** a report saying the PASS was verified by the second witness — exit 0 alone also covers a PASS no witness checked. Both the exit codes and the report's fields are frozen surfaces ([contract-freeze.md](contract-freeze.md)). Give each test its own `--work` and report; two tests on one define share its state directory and must not run at the same time. A missing `sideeye` fails the test rather than skipping it. The three below are for Linux with strace at `/usr/bin/strace`, the way [the CI quickstart](ci-quickstart.md) runs; on macOS without sudo, replace `--oracle /usr/bin/strace` with `--allow-unverified` and check the verdict alone — that PASS claims less, and the report says so. Each was run green on a correct tool and red on one with a planted bug, with the witness swapped for `--allow-unverified`, and with no `sideeye` on `PATH`.

pytest, with `sideeye.toml` beside the test file:

```python
import json
import pathlib
import shutil
import subprocess

HERE = pathlib.Path(__file__).parent


def test_no_crash_window(tmp_path):
    sideeye = shutil.which("sideeye")
    assert sideeye, "sideeye is not on PATH"
    report = tmp_path / "report.json"
    run = subprocess.run(
        [sideeye, "explore", "--config", str(HERE / "sideeye.toml"),
         "--oracle", "/usr/bin/strace",
         "--work", str(tmp_path / "work"), "--json", str(report)],
        capture_output=True, text=True,
    )
    assert run.returncode == 0, run.stdout + run.stderr
    result = json.loads(report.read_text())
    assert result["verdict"] == "PASS" and result["oracle_verified"], result
```

On macOS a framework Python's `python3` — Homebrew's, python.org's — is a launcher that replaces itself, and Sideeye refuses it (`child_process_detected`) and names the interpreter to write in the define instead ([what the target has to be](../README.md#what-the-target-has-to-be)).

cargo test, as `tests/crash_consistency.rs`, with `sideeye.toml` at the package root naming `./target/debug/<your-binary>` — cargo builds the package's binaries before it runs integration tests. That path is the one a plain `cargo test` in a single package writes; under `--release`, `--target`, `CARGO_TARGET_DIR` or a workspace member the binary is elsewhere, and a define still naming `./target/debug/` would judge whatever build was left there, so name the path your test command builds:

```rust
use std::process::Command;

#[test]
fn no_crash_window() {
    let dir = std::env::temp_dir().join(format!("sideeye-{}-no_crash_window", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let report = dir.join("report.json");
    let out = Command::new("sideeye")
        .args(["explore", "--config", concat!(env!("CARGO_MANIFEST_DIR"), "/sideeye.toml")])
        .args(["--oracle", "/usr/bin/strace"])
        .arg("--work").arg(dir.join("work"))
        .arg("--json").arg(&report)
        .output()
        .expect("sideeye is not on PATH");
    let text = String::from_utf8_lossy(&out.stdout);
    assert_eq!(out.status.code(), Some(0), "{text}{}", String::from_utf8_lossy(&out.stderr));
    let json = std::fs::read_to_string(&report).unwrap();
    let flat: String = json.chars().filter(|c| !c.is_whitespace()).collect();
    assert!(flat.contains("\"verdict\":\"PASS\"") && flat.contains("\"oracle_verified\":true"), "{json}");
}
```

go test, in the package of the command it builds — `keytool` here — with `sideeye.toml` beside it naming `./bin/keytool`:

```go
package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestNoCrashWindow(t *testing.T) {
	sideeye, err := exec.LookPath("sideeye")
	if err != nil {
		t.Fatal("sideeye is not on PATH")
	}
	if out, err := exec.Command("go", "build", "-o", "bin/keytool", ".").CombinedOutput(); err != nil {
		t.Fatalf("go build: %v\n%s", err, out)
	}
	dir := t.TempDir()
	report := filepath.Join(dir, "report.json")
	out, err := exec.Command(sideeye, "explore", "--config", "sideeye.toml",
		"--observe", "supervised", "--oracle", "/usr/bin/strace",
		"--work", filepath.Join(dir, "work"), "--json", report).CombinedOutput()
	if err != nil {
		t.Fatalf("sideeye: %v\n%s", err, out)
	}
	b, err := os.ReadFile(report)
	if err != nil {
		t.Fatal(err)
	}
	var r struct {
		Verdict        string `json:"verdict"`
		OracleVerified bool   `json:"oracle_verified"`
	}
	if err := json.Unmarshal(b, &r); err != nil {
		t.Fatal(err)
	}
	if r.Verdict != "PASS" || !r.OracleVerified {
		t.Fatalf("wanted a verified PASS:\n%s", b)
	}
}
```

A pure-Go binary is statically linked (one built with cgo is not), so on Linux it is explored under `--observe supervised`: Linux 5.19 or later, and a cgroup v2 the engine can create cgroups in, as root or delegated to its user ([`--observe`](cli.md#usage)). Under Docker's defaults that is a SETUP ERROR naming the cgroup; `docker run --privileged --cgroupns=private` ran it; this repository's own CI delegates one with [`spike/in-delegated-cgroup.sh`](../spike/in-delegated-cgroup.sh). Writes that come from two threads are refused there, and Go's runtime, not your code, decides which thread runs a goroutine — the runs here were one each, so a refusal on a later run is not ruled out. On macOS a Go binary goes through libSystem like everything else, so drop `--observe supervised`.

## My first run on macOS is UNKNOWN. Why?

A PASS needs a second witness that checks Sideeye's own count of operations against the kernel's. On Linux that is strace (`--oracle`); on macOS it is `fs_usage` (`--oracle-fs-usage`), which needs root — run `sudo -v` in the same terminal first. With no witness, an exploration that found nothing is UNKNOWN `completeness_not_verified`, and its next step names both ways on: the witness, or `--allow-unverified`, which turns it into a PASS that says it was not verified. A FAIL needs no witness; a counterexample is evidence on its own. One limit of `fs_usage` read from the source rather than run here: a tool that syncs through `fcntl(F_FULLFSYNC)` — Rust's `sync_all`, Go's `Sync` — on a file in the state is refused under it, because the shim cannot count that call ([`src/fsusage.zig`](../src/fsusage.zig), `fcntlIsInert`). If the reason is something else — a framework Python's launcher, a hardened system binary — the report names it and what to do instead ([what the target has to be](../README.md#what-the-target-has-to-be)).

## My tool keeps state in two places

Sideeye judges one directory, so bring the places under it. If the tool finds them through XDG variables, point those under the state directory when you start Sideeye; the setup, the operation and the check all inherit its environment:

```toml
[world]
state = "/tmp/mytool-state"

[define]
cwd       = "."
setup     = "mytool init"
operation = "mytool sync"
check     = "./check.sh"
apparatus = ["env:XDG_CONFIG_HOME=/tmp/mytool-state/config", "env:XDG_DATA_HOME=/tmp/mytool-state/data"]
```

```
$ mkdir -p /tmp/mytool-home
$ HOME=/tmp/mytool-home XDG_CONFIG_HOME=/tmp/mytool-state/config XDG_DATA_HOME=/tmp/mytool-state/data \
    sideeye explore --config sideeye.toml --oracle /usr/bin/strace
```

Measured on a tool that keeps its config in one and rewrites its database in the other in place: FAIL at `data/…/db.json`, with a checker that read both through the same variables, and nothing written to the empty `HOME`. **Point `HOME` at an empty directory too.** The `apparatus` entries make a run that forgets a variable a SETUP ERROR naming it ([docs/apparatus.md](apparatus.md)) — but they are checked *after* the setup has run, so by then the setup has written wherever the tool falls back to: in the measured run that forgot `XDG_DATA_HOME`, the setup created `.local/share/xdgtool/db.json` under `HOME`, which on your own machine would be your real data. `env:NAME=VALUE` checks the value, which ties the define to that path; `env:NAME` alone only proves the variable is set. A tool that falls back to `HOME` can be moved with `HOME` alone (measured with the XDG variables unset: FAIL under `home/.local/share`, in a run with no checker). Tools that ask macOS for their folders through its own APIs were not measured here. A place left outside is not judged: in the run that left the database outside, the operation wrote nothing under the state, and the verdict was UNKNOWN `nothing_could_fail` rather than a PASS.
