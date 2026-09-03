# Apparatus: declaring what a deterministic run depends on

A target that stamps the clock, draws random ids or numbers its files from an
inode is refused at the baseline (`baseline_violates_invariant`, naming the
path — see "Byte-repeatable writes" in the README's limits). The cohorts that
measured such targets got past the wall by pinning the source of variation
outside the target: a faked clock, a seeded `os.urandom`, a stand-in compiler.
Every one of those lived in a launcher script or in `setup`, and the committed
define said nothing about it.

`[define] apparatus` is where the define says it (ADR 0041). Sideeye applies
none of it. After `setup` and before the first snapshot it checks that every
entry it can check is present in the environment the operation will inherit,
and refuses the run as SETUP ERROR — naming the entry and what it looked at —
when one is not. The report carries the list as declared in `apparatus`, and
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
- The saved case does not carry the declaration. A replay without the
  apparatus is not silent — the baseline does not repeat the recorded bytes
  and the refusal names the path — but the case file itself does not say
  which device was missing.

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
