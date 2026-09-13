# 2026-09-13 — ansible, contained (#559)

Host: macOS on Apple Silicon, Docker 29.4.0, `linux/arm64`. **Sideeye is a build, not a release**:
the working tree of #559's second half on `main` `0a05c47`, uncommitted and after its second review,
built for `aarch64-linux-gnu` and mounted read-only. It reports `sideeye 1.3.0 (trace contract
v17)`, and `transcripts/apparatus.txt` holds the sha256 of the engine, of `sideeye-testnocgroup`
and of the shim. The version number is the tree's and does not say which change was measured; the
contract version is what tells this build from the release (`spike/dogfood/README.md`, "Which build
a run measures"). The image is `sideeye-559-proto:2026-09-13`, built from `apparatus/Dockerfile`
for the go/no-go prototype the same day: `debian:trixie-slim`, ansible-core 2.19.11, strace 6.13.
The 2026-09-11 run met Debian's ansible-core 2.19.4 under v1.3.0; the version moved with the image,
and the comparison engine below refuses 2.19.11 with the reason and the `processes` line v1.3.0
gave 2.19.4 — its detail and next step are this change's. State and work live on
the container's own filesystem.

## The define

The 2026-09-11 one, unchanged. `apparatus/setup-ansible.sh` writes `alpha` and `beta` to `f.txt`,
and the operation is

```
ansible localhost -c local -i localhost, -e ansible_python_interpreter=/usr/bin/python3 -m lineinfile -a {"path":"$SD/f.txt","line":"gamma"}
```

explored under `--oracle /usr/bin/strace`, once per observation mode, by `apparatus/measure.sh`,
which runs the shipped engine and then `sideeye-testnocgroup` — the same tree built never to contain
a run — and prints each recording trace through `trace-ops`. It ran twice: in a `--privileged`
container as root, where the cgroup v2 mount is writable and the engine can make cgroups, and in a
default container, where the mount is read-only and it cannot. No `preflight` was run; the
prototype's had accepted the recording under both modes.

## Contained, it is judged; not contained, it is refused naming the environment

| Container | Cgroup v2 mount | Engine | `--observe wrappers` | `--observe syscalls` |
|---|---|---|---|---|
| `--privileged`, root | `rw` | shipped | **PASS** 2/2 | **PASS** 2/2 |
| `--privileged`, root | `rw` | `sideeye-testnocgroup` | `child_process_detected` | `child_process_detected` |
| default, root | `ro` | shipped | `child_process_detected` | `child_process_detected` |
| default, root | `ro` | `sideeye-testnocgroup` | `child_process_detected` | `child_process_detected` |

Every explore took 2 seconds or less, every one left `f.txt` reading `alpha`, `beta`, `gamma`, and
neither container held a `sideeye-*` cgroup afterwards (`transcripts/privileged-root.log`,
`transcripts/default.log`, with each run's text report, JSON report and recording trace beside
them).

### The PASS

Under `--observe wrappers`. The `syscalls` report differs in its oracle line, which says how that
mode's capture was read.

```
PASS  2/2 explored worlds satisfied the built-in atomicity invariant, over a single crash point
      explored 2 worlds (crash points 1 + 1 baseline)
      atomicity: 0 path(s) judged pre-or-post; 1 file(s) judged by the history form (appended tails not judged): f.txt
      oracle: agreed on 0 operations (19442 syscall lines examined, 0 in scope of the judged state), witness strace — the SUBJECT's operations only. This run's crash points include operations performed by an awaited child, and those the oracle placed and ordered rather than compared one by one: this is `oracle_verified_subject_only`, and `oracle_verified` stays false. …
      processes: a process other than the subject operated on the judged directory, and those operations hold crash-point addresses: no two processes' operations interleaved and every writing child was reaped (contract v15). …
```

The account reads as any admitted child's, and nothing in it names the detach.

### What the recording traces hold

`trace-ops` prints one `<op> <path>` line per record — a record's first path only, and no pid. Counted
by op:

| Run | `shim_ready` | `cgroup` | `detached` | `exec` | `fork` | `spawn` | `thread` | `rename` | `close` |
|---|---|---|---|---|---|---|---|---|---|
| shipped, `--privileged`, wrappers | 21 | 21 | 1 | 15 | 25 | 1 | 1 | 1 | 1 |
| shipped, `--privileged`, syscalls | 21 | 21 | 1 | 15 | 26 | 1 | 1 | 1 | 1 |
| every refused run | 21 | 0 | 1 | 15 | 25 (wrappers), 26 (syscalls) | 1 | 1 | 1 | 1 |

The trace's one `detached` record is the `setsid` the 2026-09-11 run found with a plain `strace`,
and every one of the 21 images the shim was loaded into wrote a `cgroup` record where the engine
gave the run a cgroup — none where it did not. The one `rename` is the run's one crash point; its
recorded path is a temporary under `/root/.ansible/tmp`, and the `close` is of `f.txt`. Which
process called `setsid` and which renamed is not in this transcript, since the reader prints no pid:
that the writer is a module's `python3` and not the process that detached is the 2026-09-11 run's
reading of its `strace` capture.

### The refusal

The same detail and step in all six refused explores:

```
UNKNOWN  child_process_detected
         a process left the containment group (setsid/setpgid), and the engine could not give this run a cgroup of its own, so it cannot claim to have stopped it. Run the engine where it can make cgroups under its own and move processes into them — a writable cgroup v2 delegated to its user, or root over a writable cgroup v2 (a default container mounts it read-only) — and a process that leaves the group is stopped with the run's cgroup and judged
next        Fix what the detail above names in the environment, then re-run; the define itself is unchanged.
```

Its `processes` line is, word for word, the one v1.3.0 printed for the same refusal on 2026-09-11 —
"a process other than the subject operated on the judged directory; its operations have no
crash-point address; …" — because the account ranks another process's operations above the
boundary that refused the run, as it did then.

## What this does not measure

- **A non-root engine in a delegated cgroup.** CI's second acceptance step runs in that environment
  (`spike/in-delegated-cgroup.sh`); ansible was not run there.
- **ansible-core 2.19.4**, the version 2026-09-11 met, any module other than `lineinfile`, or a
  playbook.
- **A FAIL.** The one write is the safe shape, so a FAIL here would have been a defect in the engine.
  That the engine finds a planted bug written through a detached worker is the acceptance toy's
  claim (`TOY_DETACH_WRITE` in `spike/acceptance.sh`), not this run's.
- **The builds this change had before.** The builds before its first review and before its second
  reached the same eight outcomes on this define; their transcripts were replaced by these.
