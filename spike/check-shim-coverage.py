"""Every syscall the oracle classifies is either interposed or explained.

The oracle's `known` table decides what counts as a state-directory operation. The
shim's export list decides what the *other* observer can see. When a syscall is in
the first and missing from the second, a target using it is seen by one observer and
not the other — an `oracle_missed_operation` refusal on Linux, and on macOS, where no
oracle exists, nothing at all. That is how `pwritev`, `pwritev2` and `renameat2` sat
unexported from v0.1 until #256: nothing compared the two lists.

This is NOT a set-equality check, and the difference matters. Measured on the tree
this was written against: before this batch, 28 exported symbols had no `known` entry
(stdio, the process family, the LFS aliases) while 4 `known` entries had no export
(`openat2`, and the three that were the actual gap). Equality would therefore have
started red on 32 differences, 29 of them legitimate — only pwritev, pwritev2 and
renameat2 were real — and the cheapest way to green would have been an exclusion
list — where adding one line is also the cheapest way to hide the
next real gap.

Note what this does NOT cover, so nobody reads a green run as wider than it is: the
oracle's metadata tables (`metadata_path_syscalls`, `metadata_fd_syscalls` — the #121
and #190 families) are separate from `known` and are not compared here, and the check
reads `shim/src/linux.zig` only. A syscall the oracle classifies and macOS does not
interpose is exactly the #256 shape and this check cannot see it.

So the check runs the other way: for each name in `known`, EITHER the shim exports it
OR this file's table says why not. A new `known` entry with neither is a failure. The
table is the exclusion list and the check at once, which is what makes forgetting
fail closed.

Both sides are read from source, never transcribed: EXPORTS comes from the
`@export(…, .{ .name = "…" })` calls in shim/src/linux.zig, so a table that claims an
export the shim does not have cannot pass.

Exit 0 when every classified syscall is accounted for, 1 when one is not, 2 when the
check could not read what it needs — never read a 2 as a pass.

Since contract v14 the check runs a SECOND comparison, for `--observe syscalls`. That
mode counts the write family at the syscall boundary, which is the only way to see a
write libc issues from inside itself — so for a write-class syscall the two ways of
being covered are not equivalent: being in the trap set catches a raw call as well, while
a libc wrapper alone catches only the calls that pass through libc. The check therefore asks,
of every `.write` member of `known`, either it is in the shim's trap set or this file
says why it is covered at the libc boundary only. That keeps the mode's residual
written down where forgetting fails closed, rather than in prose that drifts.

Usage: check-shim-coverage.py <src/oracle.zig> <shim/src/linux.zig> [shim/src/syscalls.zig]
"""

import re
import sys

# Why a syscall the oracle CLASSIFIES (`known`) is not interposed by the shim. Each
# entry is a standing decision, not a to-do: if one becomes wrong, the fix is to
# export the symbol and delete the line.
#
# Only `known` members belong here. The #121/#190 metadata families were in an
# earlier draft of this table and did not belong: they live in the oracle's separate
# `metadata_*` tables, are never compared here, and listing them made the table look
# like it was carrying thirteen decisions it was not. `stale_reasons` below now
# refuses that mistake instead of leaving it to the reader.
NOT_INTERPOSED = {
    # glibc ships no wrapper for this one, so there is no PLT symbol to replace. A
    # target reaching it does so through syscall(2) or inline assembly, which is the
    # #217 observer class rather than a missing export.
    "openat2": "no glibc wrapper exists; reaching it bypasses the PLT entirely (#217)",
}


# Why a `.write` member of `known` is NOT in the syscall-mode trap set. Same discipline
# as NOT_INTERPOSED: a standing decision, and the fix for a wrong one is to add the
# syscall to `trapped` and delete the line.
#
# What being here costs is precise and worth stating: the syscall is counted only when
# it passes through the libc entry point the shim exports, so a RAW call to it is
# invisible in this mode — the same class of hole `--observe syscalls` exists to close
# for `write`.
NOT_TRAPPED = {
    "pwritev2": "six arguments, so no free register for the re-issue sentinel, and"
                " glibc falls back to a trapped number on a kernel that lacks it while"
                " issuing the real thing on one that has it — so neither counting it in"
                " the wrapper nor silencing the wrapper is right on both. Its wrapper"
                " records .unsupported in syscalls mode and the run refuses",
    "copy_file_range": "never issued from inside libc's stdio, so the wrapper sees"
                       " every call that is not raw (#244)",
    "sendfile": "as copy_file_range",
    "sendfile64": "as copy_file_range",
}


def oracle_write_class(path):
    """The `.write` members of `known` in src/oracle.zig, in declaration order."""
    text = open(path).read()
    start = text.index("const known = [_]Mapping{")
    end = text.index("};", start)
    return [
        m.group(1)
        for m in re.finditer(
            r'\.name = "([a-z0-9_]+)", \.class = \.write\b', text[start:end]
        )
    ]


def shim_trap_set(path):
    """The members of `const trapped = [_]SYS{…}` in shim/src/syscalls.zig.

    Read from the declaration the filter is built from, for the reason `shim_exports`
    is read from the export calls: a transcribed list would verify itself.
    """
    text = open(path).read()
    start = text.index("const trapped = [_]SYS{")
    end = text.index("};", start)
    return set(re.findall(r"\.([a-z0-9_]+)", text[start:end]))


def check_trap_set(oracle_path, syscalls_path):
    """The second comparison. Returns (exit code, printed already)."""
    try:
        writes = oracle_write_class(oracle_path)
        trapped = shim_trap_set(syscalls_path)
    except (OSError, ValueError) as exc:
        print("  BROKEN could not read the trap set: %s" % exc)
        return 2
    if not writes or not trapped:
        print("  BROKEN one side parsed empty (write-class=%d, trapped=%d) — a zero"
              " here means the declaration moved, not that the sets agree"
              % (len(writes), len(trapped)))
        return 2

    # The trap set is written in kernel spelling and `known` in libc spelling; the
    # names that differ are the LFS aliases, which the kernel does not have. `pwrite`
    # and `pwrite64` are one syscall, and so are `sendfile` and `sendfile64`.
    def kernel_name(libc_name):
        return {"pwrite": "pwrite64", "pwritev64": "pwritev"}.get(libc_name, libc_name)

    unaccounted = sorted(
        n for n in writes
        if kernel_name(n) not in trapped and n not in NOT_TRAPPED
    )
    contradicted = sorted(
        n for n in NOT_TRAPPED if kernel_name(n) in trapped
    )
    stale = sorted(n for n in NOT_TRAPPED if n not in writes)

    print("  oracle classifies %d syscalls as writes; the trap set holds %d; %d of the"
          " write class covered at the libc boundary only"
          % (len(writes), len(trapped), len(NOT_TRAPPED)))
    if unaccounted:
        print("  FAILED write-class but neither trapped nor explained: %s"
              % ", ".join(unaccounted))
        print("         add it to `trapped` in shim/src/syscalls.zig, or to NOT_TRAPPED"
              " in this file with what a raw call to it would cost")
    if contradicted:
        print("  FAILED explained as not-trapped, but the trap set holds it: %s"
              % ", ".join(contradicted))
        print("         the reason is stale; delete the NOT_TRAPPED entry")
    if stale:
        print("  FAILED explained here but not classified as a write: %s"
              % ", ".join(stale))
        print("         this reason covers no syscall — a typo, or a name whose class"
              " moved")
    if unaccounted or contradicted or stale:
        return 1
    print("  ok   every write the oracle classifies is trapped or explained")
    return 0


def oracle_known(path):
    """Names from `const known = [_]Mapping{…}` in src/oracle.zig."""
    text = open(path).read()
    start = text.index("const known = [_]Mapping{")
    end = text.index("};", start)
    return set(re.findall(r'\.name = "([a-z0-9_]+)"', text[start:end]))


def shim_exports(path):
    """Names from the `@export(&ops.x, .{ .name = "…" })` calls in shim/src/linux.zig.

    Read from the export calls themselves rather than from a list kept beside them:
    a table that says "exported" about a symbol the shim does not export would
    otherwise verify itself.
    """
    text = open(path).read()
    return set(re.findall(r'@export\([^)]*\.name = "([a-z0-9_]+)"', text))


def main(argv):
    if len(argv) not in (3, 4):
        print("  BROKEN usage: check-shim-coverage.py <oracle.zig> <linux.zig>"
              " [syscalls.zig]")
        return 2
    try:
        known = oracle_known(argv[1])
        exports = shim_exports(argv[2])
    except (OSError, ValueError) as exc:
        print("  BROKEN could not read the declarations: %s" % exc)
        return 2
    if not known or not exports:
        print("  BROKEN one side parsed empty (known=%d, exports=%d) — a zero here means"
              " the parse broke, not that everything is covered" % (len(known), len(exports)))
        return 2

    # A reason for a symbol the shim actually exports is stale: the reason and the
    # export contradict each other, and whichever is wrong, silence is worse.
    contradicted = sorted(n for n in NOT_INTERPOSED if n in exports)
    unaccounted = sorted(n for n in known if n not in exports and n not in NOT_INTERPOSED)
    # A reason for a name the oracle does not classify explains nothing — a typo, or
    # an entry that wandered in from one of the metadata tables. Without this, such a
    # line sits in the table looking like a decision and covering no syscall at all,
    # which is what the first version of this table did with thirteen of them.
    stale = sorted(n for n in NOT_INTERPOSED if n not in known and n not in exports)

    explained = sorted(n for n in NOT_INTERPOSED if n in known)
    print("  oracle classifies %d syscalls; shim exports %d symbols; %d of the"
          " classified ones explained here rather than interposed"
          % (len(known), len(exports), len(explained)))
    if unaccounted:
        print("  FAILED classified but neither interposed nor explained: %s"
              % ", ".join(unaccounted))
        print("         export it from shim/src/linux.zig, or add it to NOT_INTERPOSED"
              " in this file with the reason")
    if contradicted:
        print("  FAILED explained as not-interposed, but the shim exports it: %s"
              % ", ".join(contradicted))
        print("         the reason is stale; delete the NOT_INTERPOSED entry")
    if stale:
        print("  FAILED explained here but not classified by the oracle: %s"
              % ", ".join(stale))
        print("         this reason covers no syscall — a typo, or a name that belongs"
              " to the oracle's metadata tables rather than to `known`")
    if unaccounted or contradicted or stale:
        return 1
    print("  ok   every syscall the oracle classifies is interposed or explained")
    # Optional so the older two-argument invocation keeps working; the acceptance suite
    # and CI pass the third path, so the trap comparison is not optional in practice.
    if len(argv) == 4:
        rc = check_trap_set(argv[1], argv[3])
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
