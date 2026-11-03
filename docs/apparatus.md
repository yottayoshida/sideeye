# Apparatus: declaring what a deterministic run depends on

A target that stamps the clock, draws random ids or numbers its files from an
inode is refused at the baseline (`baseline_violates_invariant`, naming the
path — see "Byte-repeatable writes" in the README's limits). The cohorts that
measured such targets got past the wall by pinning the source of variation
outside the target: a faked clock, a seeded `os.urandom`, a stand-in compiler.
Every one of those lived in a launcher script or in `setup`, and the committed
define said nothing about it.

`[define] apparatus` is where the define says it (ADR 0041). Sideeye applies
none of it — except `pin:random` and `pin:clock`, the two entries the engine applies itself (ADR 0146,
ADR 0151, [below](#pinrandom-randomness-the-engine-pins)). It checks that every entry it can check is present in the
environment the operation will inherit, and refuses the run as SETUP ERROR —
naming the entry and what it looked at — when one is not. The `env:` entries
are checked **before `setup` runs**, so a setup started without a declared
variable does not get to write where the tool falls back to without it; the
rest are checked after `setup`, which may generate them, and before the first
snapshot. A variable exported empty is set: `env:NAME` passes it, and a tool
that reads empty as unset still falls back — `env:NAME=VALUE` pins the value. The report carries the list as declared in `apparatus`, and
the entries it could not check in `apparatus_unchecked`.

```toml
[define]
setup     = "./pins/setup.sh"      # generates sitecustomize.py, plants the flag file
operation = "borg create ::a /src"
apparatus = [
  "env:FAKETIME=@2024-01-01 00:00:00",
  "preload:libfaketime",
  "pythonpath:sitecustomize.py",
  "note:borg's --no-cache-sync is passed on the command line",
]
```

(The example spans lines for reading; the accepted form is one `[` ... `]`
line, the same as the commands' argv form.)

| entry | what is checked | where the device is set |
|---|---|---|
| `env:NAME` | `NAME` is set in the environment the operation inherits | the launcher, or the shell |
| `env:NAME=VALUE` | set, and equal to `VALUE` — for devices whose value *is* the device (`PAPIS_NP=0`, `FAKETIME=...`) | same |
| `preload:LIB` | a line of `/etc/ld.so.preload` names a library whose basename starts with `LIB` | the launcher writes the line (needs root). Linux only |
| `pythonpath:FILE` | some entry of `PYTHONPATH` has `FILE` directly under it. Existence only: the content is not judged | `setup` generates the file; the launcher exports `PYTHONPATH` |
| `note:TEXT` | nothing — carried, listed as unchecked | wherever it lives (an hgrc line, a container's seccomp profile, a pin applied inside the operation's own command line) |
| `pin:random` | nothing to check: the engine applies it (below) | the engine. Linux only, the default mode or `--observe syscalls`, where the engine can make cgroups |
| `pin:clock` | nothing to check: the engine applies it (below) | the engine. Linux only, the default mode or `--observe syscalls` |

## `pin:random`: randomness the engine pins

**A define that writes `pin:random` has the bytes its operation and that operation's children
receive from libc's `getrandom`, `getentropy` and `arc4random*`, and from reads of `/dev/urandom`
and `/dev/random`, come out the same in every run of one invocation — the two runs of
`--twice`, every explored world, and the replay of its case — and different in every process.**
The engine writes a small library, `libsideeye_pin.so`, into the work directory and puts it ahead
of the shim in the operation's `LD_PRELOAD`. Its seed is drawn from the real source once per
`explore` or `preflight`, and kept in the case (`case_version` 8) for the replay; each process
derives its own from its parent's and a count, carried in the environment every exec or spawn
passes on, and claims it once per run with an exclusive create under the work directory's
`pin-claims/`: a seed that reaches two processes — the two children of a relay the library is not
loaded in, a static binary — is drawn from by the first, and the second draws the real source, so
the two runs differ rather than agree on a shared stream. It is the hand-written `pin-random.c` of the dogfood records
(`spike/dogfood/2026-10-12-shipped-v1120/apparatus/`) without the preload file and the root it
needs. The clock is not pinned by this entry: that is [`pin:clock`](#pinclock-the-wall-clock-the-engine-stops)'s.

**The pinned bytes are recomputable by anyone holding the case** — and the reproduce line, which
prints the seed. Do not ask for the pin in a define whose operation touches real keys, a real
`HOME`'s key stores or network credentials, and throw away any key the pinned run left in the
state. A process the operation leaves behind — a daemon it starts — holds the pinned stream too,
which is why the entry needs a cgroup: the engine stops such a process with the run. The
reproduce line runs the operation outside any cgroup of the engine's, so a daemon it starts there
outlives it with the pinned stream.

Refused by name, as SETUP ERROR: under `--observe supervised`, which loads nothing into the
operation; on macOS; on a Linux host where the engine cannot make cgroups; and with a work
directory whose path holds a space, a tab or a colon, or that sits on a `noexec` mount, where the loader
would skip the library without a word.

What the pin does not reach. Each of these leaves the two runs different, which is refused as
before — never a stream silently shared:

- a statically linked binary (Go, for one), a raw `syscall(SYS_getrandom)`, the CPU's `RDRAND`
  (Qt's `QRandomGenerator` uses it on x86_64: KeePassXC was measured on aarch64 only),
  `/proc/sys/kernel/random/uuid`, the auxiliary vector's `AT_RANDOM`;
- a child started through `execl`, `execle`, `execlp`, `fexecve`, `execveat`, `daemon`,
  `forkpty`, a raw `clone`, `_Fork` or a raw `execve`: it receives an empty seed, or one already
  claimed, and draws the real source;
- what glibc draws inside itself (`tmpfile`, `mktemp`, `tmpnam`), and a descriptor of
  `/dev/urandom` carried across an exec;
- a process that cannot create its claim under `pin-claims/` — one that dropped to another user,
  or runs in a chroot or a mount namespace the work directory is not in;
- two threads of one process drawing, in an order that varies between runs, and two threads
  calling `system` or `popen` at once;
- a vfork child that calls `execv` or `execvp` rather than `execve`;
- a stream from `fopen("/dev/urandom")`, whose `fileno` is `-1`; a descriptor duplicated from the
  device's (`dup`), which reads the real device;
- the temporary names the shim builds for `mkstemp` (time and pid).

## `pin:clock`: the wall clock the engine stops

**A define that writes `pin:clock` has the wall clock its operation and that operation's children
read through libc's `clock_gettime`, `time`, `gettimeofday` and `timespec_get` stopped at one
instant in every run of one invocation — the two runs of `--twice`, every explored world and every
run of `invariant = ["rerun"]` — and each call to a wait this page lists,
given a deadline on that clock, waits as long in real time as that deadline lies past the
instant.** The instant is the real time, read once per `explore` or `preflight` after the setup and
before the recording, and kept in the case (`case_version` 11, `pin_clock`) for the replay; the
reproduce line prints it. The re-runs of the rerun invariant read the instant too: they are compared
with runs from the starting state, and a target that keeps the time an earlier run wrote — a
migration recorded with the time it was applied — ends as those runs do only if all of them read
one clock. The library `pin:random`
uses carries the instant, in `SIDEEYE_PIN_CLOCK`, to every process the operation starts. It does
what libfaketime on `/etc/ld.so.preload` did for the dogfood records (KeePassXC,
`spike/dogfood/2026-10-12-shipped-v1120/`), without a preload file that also fakes the clock of
strace and of the engine's own shell. `clock_gettime` is stopped for `CLOCK_REALTIME` and
`CLOCK_REALTIME_COARSE`; the monotonic clocks are left alone, and KeePassXC on FAT reaches PASS
with only the wall clock stopped.

The waits it translates — a deadline D on the stopped clock is waited until the real now plus
D minus the instant: `pthread_cond_timedwait` (when the condition variable waits on the wall
clock: one made with `pthread_condattr_setclock(CLOCK_MONOTONIC)` is left alone),
`sem_timedwait`, `pthread_mutex_timedlock`, `pthread_rwlock_timedrdlock`,
`pthread_rwlock_timedwrlock`, `pthread_timedjoin_np`, `mq_timedreceive`, `mq_timedsend`; and,
when they name `CLOCK_REALTIME`, `pthread_cond_clockwait`, `sem_clockwait`,
`pthread_mutex_clocklock`, `pthread_rwlock_clockrdlock`, `pthread_rwlock_clockwrlock`,
`pthread_clockjoin_np` and `clock_nanosleep` with `TIMER_ABSTIME`. A clock stopped without them
changes what a program does without a word: measured with the clock read but no wait translated,
a wait to be woken after 0.3 seconds ended at once, the same way in every run, so the runs agreed
and the verdict was PASS on a path the program does not take.

Refused by name, as SETUP ERROR: under `--observe supervised`, on macOS, and with a work directory
the loader would skip, as `pin:random` is; beside a `preload:libfaketime` entry, which would fake
the clock twice; and under `--interleave`, whose two copies would read one instant. It does not
need a cgroup: a process left behind holding a stopped clock reads a wrong time, not a key. A
libc whose condition variables do not keep their clock in one bit the library can find stops the
operation, saying so, rather than translate a wait it cannot place — at its start, or, before glibc
2.34 in a process that had not loaded libpthread, at its first `pthread_cond_timedwait`, which a
run may then judge as the way the operation ended. Neither was met on glibc 2.36 or 2.41.

What the pin does not reach, refused. A read of the wall clock the pin does not stop leaves the two
runs different, which is refused as before:

- a statically linked binary (Go, for one), a raw `syscall(SYS_clock_gettime)` or a call into the
  vDSO, `CLOCK_TAI`, `CLOCK_REALTIME_ALARM`, `ftime`;
- a child whose environment lost `SIDEEYE_PIN_CLOCK` on a path the library does not wrap
  (`execle`, `fexecve`, a raw `execve`).

What the pin judges on another path — not refused: a PASS here is about the path the pinned run
took, which is not the one the program takes unpinned:

- a wait entered again with the same deadline — after a spurious wake-up, a broadcast meant for
  another condition, or `EINTR` — waits its whole remainder again, because under a stopped clock
  the program cannot see the time it already waited. Measured with `spike/toys/toy_clock.c`'s
  `rewait`: a one-second deadline, with broadcasts every half second for three seconds, ended after
  4.0 seconds, against 1.0 unpinned;
- a deadline on the stopped clock handed to a wait the library does not translate —
  `timer_settime` or `timerfd_settime` with an absolute time, C11's `cnd_timedwait` and
  `mtx_timedlock`, a raw `futex`, io_uring — ends early by as long as the invocation has run so
  far, and in a replay, whose instant is the case's, at once;
- a loop that times itself by the wall clock alone never sees its period pass: a periodic flush
  driven by `gettimeofday` is not done, and a loop waiting for the clock to pass a time does not
  end (under `--world-timeout` that world is stopped and refused);
- a re-run of the rerun invariant mints the names and ids a crashed run made from the time again —
  a temporary name with nanoseconds, a UUIDv7 or a ULID drawn beside `pin:random` — which no real
  second run could, and a target that refuses a duplicate is judged on that refusal;
- the state's files carry the real time they were restored at, which is after the instant, so a
  tool comparing a file's modification time with the clock sees a file from the future (`make`'s
  clock-skew warning).


## The one thing to know about `preload:`

**Never through `LD_PRELOAD`.** Sideeye replaces `LD_PRELOAD` with its own
shim for every child it spawns (that is how it records the operation), so a
library the launcher put there does not reach the operation — and it would be
a silent absence: the run records, the clock is real, the baseline refuses
without saying why. If `LD_PRELOAD` does name the library and
`/etc/ld.so.preload` does not, the refusal says exactly that.

`/etc/ld.so.preload` is global. A library named there rides on **every**
process on the machine for the duration, the engine's own `/bin/sh -c`
included (the shape that once made every world report
`child_process_detected`) and, under `--oracle`, on `strace`'s children. The
cohorts did this inside a container, and that is the recipe: pin in a
container, name the pin in the define. A pid pin has the same global reach and
no per-target form Sideeye can see, which is why cohort 4's `pin-getpid.c` was
applied inside the operation's command line and is declared as a `note:`.

On macOS there is no global preload file and Sideeye owns
`DYLD_INSERT_LIBRARIES`; a define with a `preload:` entry is refused there as
unsatisfiable.

## What the check does not prove

- `pythonpath:` proves the file exists under some entry, not that it is the
  file the define meant, nor that Python will import it first.
- `env:NAME` without a value proves presence, not that the value is the one
  the run needs; write the value when the value is the device.
- The checker's environment is the define's business. A checker may drop a
  device on purpose (cohort 3's cargo-r2 unsets `RUSTC` to compare against the
  real compiler); the check is about the operation's environment only.
- A case saved from a define with an `env:`, `preload:` or `pythonpath:` entry
  carries the declaration as written (`case_version` 7, ADR 0136), and `replay`
  checks each entry where `explore` does: an `env:` device the replay's
  environment lacks is refused before the setup runs. A define declaring only
  `note:` entries keeps the case version it would otherwise get.
- A case saved before that change carries no declaration, so its `replay`
  checks no entry. That replay is not silent — the baseline does not repeat
  the recorded bytes and the refusal names the path — but the refusal comes
  after the setup and the recording have run: replayed without an `env:`
  device, such a case writes where the tool falls back to.

## Reading a byte difference

A byte-layer `baseline_violates_invariant` says where the two runs' bytes first differ, how long the differing stretch is in each run and what kind of bytes it holds; `preflight --twice` says the same and quotes both stretches (#688, [docs/cli.md](cli.md#usage)). Neither says what produced the difference — ten decimal digits are a clock in one tool and a counter in the next — so the table is where to start looking, not a diagnosis. The devices it names are the ones the cohorts used (below).

| what the stretch holds | what to check first | how the define says it |
|---|---|---|
| decimal digits, the same length in both runs | whether the tool writes the time, a counter, or its process id | `pin:clock`, or the tool's own switch for it, in `apparatus` |
| hex digits | whether it is an id or a hash the tool draws fresh each run | a seeded or pinned source (`pythonpath:sitecustomize.py` pinning `os.urandom`) in `apparatus` |
| any kind, in a file nothing reads back as state — a cache, a log, an editor's message file | whether anything the operation's user depends on reads that file | `scratch` for the path; the report then names it in `not tested` |
| bytes outside printable text, inside a compressed or binary format | whether the format carries a time stamp or an id of its own (PNG text chunks, archive headers) | the tool's option that leaves it out, if it has one, on the operation's command line, and a `note:` saying so |

A stretch the table does not cover is still an observation about the target: the run is refused because a second clean run does not leave what the first one did, which is the README's byte-repeatable-writes limit, and no declaration makes two different results the same one.

## A tool's own switch for one thread

A run whose judged directory is written by two threads of one process, with nothing recorded
ordering their writes, is refused `multiple_threads_detected` (the README's threads limit), and the
refusal's next step sends the reader here. Many runtimes put file calls on a pool of threads, and
many have a switch that makes the pool one thread. Set the switch in the environment Sideeye runs
in — Sideeye applies none of it — and declare it, so the report says what the run ran under and a
run without it stops as a SETUP ERROR rather than being judged as something else. Over MCP the
server passes its children `PATH` and only the names `SIDEEYE_MCP_CHILD_ENV` lists (`docs/mcp.md`):
list the switch there too, or the declared run stops as that SETUP ERROR.

A verdict under the switch is a verdict about the tool run that way. A race two threads produce is
not in it; what the switch takes away is that the trace's numbering would name a different operation
on the next run.

| switch | how the define says it | moved past the wall | not moved, and why | record |
|---|---|---|---|---|
| Node: `UV_THREADPOOL_SIZE=1` | `env:UV_THREADPOOL_SIZE=1` | ten of the thirteen Node targets that met the wall on v1.10.0 — joplin and stylelint to PASS; prettier, svgo, `npm pkg set`, eslint, dotenvx, bibtex-tidy and glTF-Transform to FAIL; lingui to its next wall — and yarn, trash-cli, cspell and capacitor (the last two on Node 22). Without it, all thirteen refuse | Bitwarden CLI (its lock directory is taken on the pool thread), vercel (`mkdirp` of its state directory on the pool thread at every start), gemini-cli (the pool thread writes its home registry) | `spike/dogfood/2026-10-09-followups-3/`, `spike/dogfood/2026-10-09-followups-4/`, `spike/dogfood/2026-10-10-uv-threadpool/` |
| Go: `GOMAXPROCS=1` | `env:GOMAXPROCS=1` | doctl, infracost and plakar, under `--observe supervised` | OpenTofu: with one P the writing thread is still the scheduler's choice per run. etcd 3.7.3 `etcdutl defrag`, Dolt 2.6.0, Grafana 13.2.4, vmrestore 1.154.1, Gogs 0.14.3, gqlgen 0.17.98, JuiceFS 1.4.2 and Navidrome 0.64.2: two thread ids still write under `--observe supervised` (#987; the shape of each, and whether it could be judged, in `spike/dogfood/2026-10-29-go-handoff/RESULTS.md`) | `spike/dogfood/2026-10-09-followups-3/`, `spike/dogfood/2026-10-09-followups-4/`, `spike/dogfood/2026-10-25-shipped-v1160/`, `spike/dogfood/2026-10-29-go-handoff/` |
| zstd: `--single-thread --no-asyncio` | on the operation's command line, and a `note:` | zstd 1.5.7 `--rm` (`--single-thread` alone still writes through an I/O thread) | — | `spike/dogfood/2026-10-09-followups-3/` |
| beets: `threaded: no` | a line in its configuration, and a `note:` | beets 2.1.0 `import` | — | `spike/dogfood/2026-10-09-followups-3/` |
| Rust: `RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1` | — | none: measured, and none of four moved | a second writer neither variable removes — rustic's one rayon worker deletes the old snapshot while the main thread writes the index; prek and steamguard-cli write from two threads of their own; codex's start-up threads make and clear `tmp/arg0` beside the thread writing `config.toml` | `spike/dogfood/2026-10-09-followups-3/`, `spike/dogfood/2026-10-09-followups-4/` |
| lz4: `-T1` | — | none: measured, and it did not move | lz4 1.10.0: an I/O thread writes the blocks, and `-T#` is its only thread switch | `spike/dogfood/2026-10-09-followups-3/`, `spike/dogfood/2026-10-09-followups-4/` |

Under `--observe supervised` no join is recorded, nor which thread a creation made, so a switch is the
only way past there: recording creations and exits from outside was measured and not built (#687,
`spike/dogfood/2026-10-10-thread-order/`).

The refusal reads the switches a variable sets — the Node, Go and Rust rows — from the environment
Sideeye runs in, the one it hands the operation. When one is already `1` there, its step does not ask
for a switch: it says the one set is not the target's runtime's or did not remove the second writer, and
sends the reader here for the others (ADR 0138). A switch set inside the operation (`env GOMAXPROCS=1 tool`) is not seen, and the
step names the switches as if none were set. In any mode, an order between two threads that only a
lock, a queue or a wake sets is outside what Sideeye judges (ADR 0138): a switch moves a run past this
wall only by leaving one thread to write.

## Where the recipes came from

The nine devices cohorts 2-4 used, and how each is declared:

| # | device | record | entry |
|---|---|---|---|
| 1 | libfaketime, preloaded through `/etc/ld.so.preload` | `spike/cohort2/*/ops/explore.sh` | `preload:libfaketime` |
| 2 | `FAKETIME=...`, the pinned clock value | same | `env:FAKETIME=...` |
| 3 | a generated `sitecustomize.py` pinning `time.monotonic` / `os.urandom`, on `PYTHONPATH` | `spike/cohort2/borg-r*/ops/setup.sh` | `pythonpath:sitecustomize.py` |
| 4 | `no-accel-copy.so`, preloaded (made unnecessary by contract v11) | `spike/cohort4/himalaya-r2/ops/explore.sh` | `preload:no-accel-copy` |
| 5 | a `RUSTC` stand-in | `spike/cohort3/cargo-r2/ops/setup.sh` | `env:RUSTC=...` |
| 6 | `PAPIS_NP=0` | `spike/cohort3/papis/ops/explore.sh` | `env:PAPIS_NP=0` |
| 7 | `revbranchcache.mmap = no`, a line in the tool's own hgrc | `spike/cohort2/hg/ops/setup.sh` | `note:` |
| 8 | a seccomp profile (`seccomp-enosys.json`), the container's boundary | `spike/cohort4/` | `note:` |
| 9 | `pin-getpid.c`, applied inside the operation's own command line | `spike/cohort4/` | `note:` |

Six are checkable entries, three are notes.
