#!/usr/bin/env python3
"""Every function glibc exports is interposed by the Linux shim or classified.

`check-shim-coverage.py` compares the shim's exports with the syscalls the oracle names, and a
libc entry point that reaches a write without being a syscall's name passes it: that is how the
fortified `__open_2` family and the `closefrom` sweep shipped uninterposed. This check
reads the other list — the functions the CI runner's own `libc.so.6` exports, from `nm`, never
a transcribed list — and requires each one to be either interposed (an `@export` in
`shim/src/linux.zig`) or filed under a family by a row of `spike/glibc-exports.tsv`. An export
in neither fails the run, so a glibc that adds an entry point, or a change that drops an
interposer, turns CI red. A function at the same address as one the shim interposes is the same
function under a second name, as `__open` is `open`, and is required to be interposed too.

A family has a class and a reason:
  write  can change a file, or the state's names, and is not interposed; the reason says what
         sees it instead (the oracle, the snapshots) or why it cannot reach the state
  fd     can close or replace a descriptor, the shim's trace descriptor among them
  none   changes no file and closes no descriptor

What this does NOT do, so nobody reads a green run as wider than it is:
  - "Can change a file" is a judgement, made once per row. A function filed under a `none`
    family that does reach a write is invisible to this check; FAMILIES and the rows under its
    `write` and `fd` families are the record a reviewer reads.
  - It reads one libc: the x86_64 glibc of the runner CI runs it on. aarch64's exports and a
    newer glibc's are not compared; a user's newer glibc can export an entry point this file
    has never classified.
  - `GLIBC_PRIVATE` symbols are left out: no public header declares them, and a program
    linking against them is binding glibc's internals, the way a raw `syscall` is.
  - Being interposed is not being reached: a call libc makes to its own export crosses no PLT,
    so a stdio write that libc issues from inside `fwrite` is not seen by the shim whatever is
    exported here. That class is the oracle's (DESIGN.md, "Where a write is counted").
  - An entry point that does an interposed function's job with code of its own (`__open_2`
    beside `open`, `_Fork` beside `fork`) is at another address; only its row says what it is.
  - A function is filed by what it is for. Almost any of them writes a diagnostic to standard
    error from inside libc when it aborts on misuse (`free` on a corrupted heap); that write is
    the oracle's, and the process is already dying.

Exit 0 when every export is interposed or filed, 1 when one is not, a row contradicts the shim
or names nothing, or a second name of an interposed function is not interposed, 2 when the check
could not read what it needs — never read a 2 as a pass.
"""

import argparse
import collections
import re
import subprocess
import sys

DEFAULT_LIBC = "/lib/x86_64-linux-gnu/libc.so.6"

FAMILIES = {
    # write
    "stdio": ("write", "stdio, or a call that writes through a FILE or to a descriptor from inside libc (a read"
                       " that flushes an update stream's pending bytes, exit flushing every stream, a diagnostic on"
                       " standard error):"
                       " the shim sees buffered output at the flush points it exports (fflush, fclose, the seek"
                       " family), and a write libc issues from inside a call is seen by the oracle, which refuses"
                       " (DESIGN.md, \"Where a write is counted\")"),
    "metadata": ("write", "ownership, permission or timestamp: the oracle lists it in metadata_writes, and the verdict"
                          " does not judge what it changes (#121)"),
    "xattr": ("write", "an extended-attribute write: refused by the oracle (#684)"),
    "mapping": ("write", "maps or remaps memory a store can reach a file through, or punches a hole in a shared file"
                         " mapping (MADV_REMOVE): the oracle refuses a writable shared mapping of a state file (ADR"
                         " 0098)"),
    "async": ("write", "an asynchronous write or sync, issued by a thread inside libc: not recorded by the shim, seen"
                       " by the oracle"),
    "unrecorded": ("write", "writes, or opens for a write, along a path the shim does not wrap (splice into a file,"
                            " a spawn's file action, a file handle, tmpfile): not recorded by the shim, seen by the"
                            " oracle"),
    "ioctl": ("write", "a clone into a state file (FICLONE, FICLONERANGE) is refused by the oracle; the other requests"
                       " that change a file's bytes are caught only by the per-path reconciliation (DESIGN.md, \"Some"
                       " calls put bytes in a file\")"),
    "node": ("write", "creates a FIFO, a device node, a socket or a regular file by mknod: refused by the oracle inside"
                      " the state, and a node other than a regular file is refused at the snapshot"),
    "admin": ("write", "a mount-table or system change that needs CAP_SYS_ADMIN or the like: refused by the oracle"
                       " inside the state"),
    "libc-files": ("write", "writes a file libc names itself (utmp, wtmp, gmon.out, /etc/hostid, the password lock),"
                            " or one the caller names, through libc's own descriptor: not recorded by the shim, seen"
                            " by the oracle"),
    "ipc-names": ("write", "creates or removes a name under /dev/shm or the mqueue file system, never a path the caller"
                           " chooses"),
    "raw": ("write", "a raw system call (#217): --observe syscalls counts the kill points among them, and the oracle"
                     " sees the rest"),
    # fd
    "duplicate": ("fd", "replaces or closes a descriptor without passing the shim, by decision (ADR 0013): every"
                        " descriptor is placed by its path at each operation, and the trace descriptor sits above the"
                        " numbers these reach by accident; a deliberate dup2 onto it stays outside the guard"),
    "close-passed": ("fd", "closes a descriptor the caller handed it (fdopendir's, a message queue's, an RPC"
                           " transport's) without passing the"
                           " shim's close: a caller that hands over the trace descriptor's number ends the channel"
                           " unannounced, as a deliberate dup2 onto it would (ADR 0013)"),
    "close-own": ("fd", "closes descriptors libc opened for itself (a pipe, a directory walk, the syslog socket, a"
                        " database file, an RPC socket), never one the caller chose"),
    # none
    "boundary": ("none", "starts a process, or moves one to another process group, without passing the shim's fork,"
                         " vfork, exec, spawn, setsid or setpgid wrappers: no boundary is recorded for it, and what a"
                         " new process writes is its own calls"),
    "handler": ("none", "sets a signal's disposition or mask, or restores a saved one, without passing the shim's"
                        " sigaction, signal or"
                        " sigprocmask: under --observe syscalls a target can reset or block SIGSYS this way and dies at"
                        " its next trapped call (DESIGN.md)"),
    "string": ("none", "reads and writes the caller's memory"),
    "number": ("none", "arithmetic, bit operations, random numbers and number conversion"),
    "ctype": ("none", "character classification and case"),
    "locale": ("none", "locale, multibyte conversion and message catalogs"),
    "formatting": ("none", "formatting into memory, or reading a stream's state without moving it"),
    "thread": ("none", "threads, their locks and their keys"),
    "memory": ("none", "the process's own memory"),
    "process": ("none", "waits for, queries or adjusts a process and changes no file"),
    "signal": ("none", "signals, without changing a disposition"),
    "time": ("none", "clocks, timers and time conversion"),
    "network": ("none", "sockets, name resolution and RPC"),
    "accounts": ("none", "reads the user, group, host and login databases"),
    "system": ("none", "the environment, system information, the working directory, the loader and logging setup"),
    "search": ("none", "sorting, searching, hashing and pattern matching in memory, and reading mount tables"),
    "files-read": ("none", "reads, queries, polls or waits on files and descriptors without changing them"),
    "flush": ("none", "flushes without changing a byte; whether that counts for power loss is ADR 0110's"),
    "pipes": ("none", "moves data between pipes and memory"),
    "names": ("none", "returns a name and creates nothing"),
    "ipc": ("none", "System V and POSIX IPC through an id or a descriptor already open"),
    "stubs": ("none", "a stub that fails with ENOSYS on Linux"),
}


class Broken(Exception):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message):
        print("  BROKEN %s" % message)
        sys.exit(2)


# A name's versions can sit at different addresses (posix_spawn's do), so each name keeps all of them.
def libc_functions(nm_text):
    functions = collections.defaultdict(set)
    for line in nm_text.splitlines():
        fields = line.split()
        if len(fields) != 3 or fields[1] not in ("T", "W", "i"):
            continue
        name, _, version = fields[2].partition("@")
        if version.lstrip("@") != "GLIBC_PRIVATE":
            functions[name].add(fields[0])
    return dict(functions)


def shim_exports(path):
    with open(path) as f:
        return set(re.findall(r'@export\([^)]*\.name = "([A-Za-z0-9_]+)"', f.read()))


def table_rows(path):
    rows = {}
    with open(path) as f:
        for n, line in enumerate(f, 1):
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 2 or fields[1] not in FAMILIES:
                raise Broken("%s:%d is not name<TAB>family, with the family one of FAMILIES" % (path, n))
            if fields[0] in rows:
                raise Broken("%s:%d names %s twice" % (path, n, fields[0]))
            rows[fields[0]] = fields[1]
    return rows


def main():
    parser = Parser(description="Every function glibc exports is interposed by the Linux shim or classified.")
    parser.add_argument("linux_zig")
    parser.add_argument("table")
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--libc", default=DEFAULT_LIBC)
    source.add_argument("--exports-from", help="nm output to read instead of running nm")
    args = parser.parse_args()

    try:
        if args.exports_from is not None:
            with open(args.exports_from) as f:
                nm_text = f.read()
        else:
            out = subprocess.run(["nm", "-D", "--defined-only", "--with-symbol-versions", args.libc],
                                 capture_output=True, text=True, timeout=120)
            if out.returncode != 0:
                raise Broken("nm exited %d on %s: %s" % (out.returncode, args.libc, out.stderr.strip()[:200]))
            nm_text = out.stdout
        functions = libc_functions(nm_text)
        interposed = shim_exports(args.linux_zig)
        rows = table_rows(args.table)
    except (OSError, Broken, subprocess.TimeoutExpired) as exc:
        print("  BROKEN %s" % exc)
        print("         could not read what it needs — never read a 2 as a pass")
        return 2

    # A parse that finds a fraction of glibc read a format it does not understand, not a small libc.
    if len(functions) < 2000 or not {"open", "write", "rename"} <= set(functions) or len(interposed) < 50:
        print("  BROKEN read %d functions and %d shim exports, or the anchors open, write and rename are missing"
              % (len(functions), len(interposed)))
        return 2

    failures = []
    for n, family in sorted(rows.items()):
        if n in interposed:
            failures.append("%s is filed under %s and the shim interposes it: delete the row" % (n, family))
        if n not in functions:
            failures.append("%s is filed under %s but libc does not export it: the row is stale" % (n, family))
    for family in sorted(set(FAMILIES) - set(rows.values())):
        failures.append("family %r files no row: delete it" % family)
    by_address = collections.defaultdict(set)
    for n, addresses in functions.items():
        for address in addresses:
            by_address[address].add(n)
    for n in sorted(interposed & set(functions)):
        for alias in sorted(set().union(*(by_address[a] for a in functions[n])) - interposed):
            failures.append("%s is %s under a second name (same address) and is not interposed" % (alias, n))
    for n in sorted(set(functions) - interposed - set(rows)):
        failures.append("%s is exported by libc, not interposed, and filed nowhere" % n)

    if failures:
        for f in failures:
            print("  FAILED %s" % f)
        print("         interpose it in shim/src/linux.zig, or file it in %s under a family" % args.table)
        return 1
    by_class = collections.Counter(FAMILIES[family][0] for family in rows.values())
    print("  libc exports %d functions: %d interposed, %d filed (%s) under %d families"
          % (len(functions), len(interposed & set(functions)), len(rows),
             ", ".join("%s %d" % kv for kv in sorted(by_class.items())), len(FAMILIES)))
    print("  ok   every function glibc exports is interposed or filed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
