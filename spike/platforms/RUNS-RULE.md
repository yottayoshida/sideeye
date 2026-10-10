# The platform probe — how it is run and read, decided before the first dispatch

The table in `docs/cli.md` (#697, ADR 0105) takes its measured cells from
`.github/workflows/spike-platforms.yml`, dispatched at the commit that merged this apparatus.
These rules were committed with the apparatus, before its first dispatch.

**What came before them.** A dry run of `measure.sh` on the maintainer's machine (aarch64,
Docker Desktop) was run first, and it changed the define: a shell redirect
(`printf … > a.txt`) measured which shell `/bin/sh` is rather than the platform — bash's and
busybox's `printf` write from inside libc, so the default mode refused `oracle_missed_operation`
on Rocky 8 and Alpine and judged Ubuntu's dash, and Ubuntu with `/bin/bash` refused the same way.
The define is `dd` since. That dry run is not the record and nothing in the table rests on it.

## Which runs count

- **Whether WSL2 starts is decided by the first dispatch whose `wsl2` job reaches its import
  step.** WSL2 started when `wsl -d probe -u root -- uname -r` exits 0 with `WSL2` in its output
  (a WSL1 distribution's kernel string has none); the workflow writes that as `started: yes|no`
  in the record's `wsl.txt`, beside `wsl -l -v`, what the runner reported about WSL and
  virtualization, and the result of `wsl --update`. If it says `no` — the import failed, WSL is
  not there, or the kernel is not WSL2's — the WSL2 row is **unmeasured**, its reason the
  `wsl.txt` lines, and WSL2 is not dispatched again to try for a different answer.
- **Any other failure is the apparatus's**: a script error, a download or digest failure, line
  endings, a package that would not install, a leg that left no record. It is fixed and
  dispatched again — with `jobs` naming only the side that failed, so a Linux fault does not
  run WSL2 a second time. Every run is listed in the record's `RESULTS.md`, completed or not,
  with what stopped it.

## How a cell is read

- **The control is the `host` leg of the same runner**, per observation mode: the release target
  itself (Ubuntu 24.04, glibc 2.39), installed as an adopter installs it. The Alpine legs and
  the Rocky 8 legs are read against the host leg of their own architecture; WSL2 against the
  x86_64 host leg — the one from the last completed `linux` run at the same commit and release,
  when the two sides came from separate dispatches. The define's right answer is FAIL: the earliest violation after the
  `open` of `/s/st/a.txt` and before its `write`, `oracle_verified` — compared by that pair of
  operations, not by the crash point's number, since dd differs between the platforms.
- **A cell is supported** where, in the same mode, the control is that FAIL and the cell is
  that FAIL too.
- **If the control is not that FAIL in some mode, nothing is concluded from the run for that
  mode, and it goes back to the owner** before the table is written: the control is a release
  target, so the define and the engine are both in question, and a release row is not left
  "supported" beside a record of the release answering wrong.
- **A row where some modes agree with the control and others do not** is supported, and its
  cell names the verdict of every mode, the ones that differ included. A row that started but
  agrees in no mode goes to the owner for its word.
- The Rocky 8 legs are the release targets' glibc floor (2.28) measured in a container on the
  runner's kernel: they speak for glibc 2.28's userland, not for an older kernel or cgroup v1.
