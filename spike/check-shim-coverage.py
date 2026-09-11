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

Since contract v14 the check runs further comparisons, for `--observe syscalls`. That
mode counts operations at the syscall boundary, which is the only way to see one a
runtime issues without passing through libc at all — so the two ways of being covered are
not equivalent: being in the trap set catches a raw call as well, while a libc wrapper
alone catches only the calls that reach libc. Three comparisons follow from that, and each
is written so that forgetting fails closed rather than passing quietly:

  2. Of every KILL-POINT member of `known` — the classes `contract.OpClass.isKillPoint`
     admits, read from that function rather than listed here — either it is in the shim's
     trap set or this file says why it is covered at the libc boundary only. Until #542
     this asked only about the `.write` class, which was the whole trap set then.
  3. The oracle's own copy of the trap set (`isTrapped`) against the shim's, in both
     directions. The shim's set is per-architecture and the oracle's is the union of both,
     because one reader may be handed a capture from either machine.
There is no fourth comparison for "every wrapper stays silent while the handler counts",
and there deliberately is not: `common.zig`'s wrapper door asks
`countedAtSyscall() and op.isKillPoint()` once, and the trap set is exactly the kill-point
classes, so the class a wrapper records answers the question and no wrapper has a fact of
its own to forget. An earlier draft of #542 wrote the gate at each of 31 call sites and
this file grew a ninety-line Zig function parser and a fourteen-entry exemption table to
hold them; both went away with the call sites. A check that becomes unnecessary is better
than a check that passes.

Usage: check-shim-coverage.py <src/oracle.zig> <shim/src/linux.zig>
                              [shim/src/syscalls.zig [src/contract.zig]]
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


# Why a kill-point member of `known` is NOT in the syscall-mode trap set. Same discipline
# as NOT_INTERPOSED: a standing decision, and the fix for a wrong one is to add the
# syscall to `trapped` and delete the line.
#
# What being here costs is precise and worth stating: the syscall is counted only when
# it passes through the libc entry point the shim exports, so a RAW call to it is
# invisible in this mode — the same class of hole `--observe syscalls` exists to close.
#
# Both survivors are here for one reason, and it is structural rather than a judgement:
# the re-issue sentinel rides in the sixth argument register, so a syscall that uses all
# six cannot be trapped at all.
NOT_TRAPPED = {
    "pwritev2": "six arguments, so no free register for the re-issue sentinel, and"
                " glibc falls back to a trapped number on a kernel that lacks it while"
                " issuing the real thing on one that has it — so neither counting it in"
                " the wrapper nor silencing the wrapper is right on both. Its wrapper"
                " records .unsupported in syscalls mode and the run refuses",
    "copy_file_range": "six arguments, like pwritev2, so the sentinel's register is not"
                       " free. Unlike pwritev2 there is no fallback that lands on a"
                       " trapped number and nothing in libc issues it from inside"
                       " itself, so its wrapper simply keeps recording in both modes"
                       " (#244)",
}


def kill_point_classes(path):
    """The classes `contract.OpClass.isKillPoint` admits, read from that function.

    Listing them here instead would make this check agree with itself: the point of
    comparison 2 is that a class promoted to a kill point drags its syscalls into the
    question, and a transcribed list would keep answering the old question.
    """
    text = open(path).read()
    start = text.index("pub fn isKillPoint(")
    end = text.index("\n    }", start)
    body = text[start:end]
    true_arm = [ln for ln in body.splitlines() if "=> true" in ln]
    if len(true_arm) != 1:
        raise ValueError("isKillPoint's shape moved: %d arms return true" % len(true_arm))
    return set(re.findall(r"\.([a-z]+)", true_arm[0]))


def oracle_kill_points(path, classes):
    """The members of `known` in src/oracle.zig whose class is a kill point."""
    text = open(path).read()
    start = text.index("const known = [_]Mapping{")
    end = text.index("};", start)
    return [
        m.group(1)
        for m in re.finditer(
            r'\.name = "([a-z0-9_]+)", \.class = \.([a-z]+)\b', text[start:end]
        )
        if m.group(2) in classes
    ]


def shim_trap_set(path):
    """The trap set of `const trapped: []const Trap = switch (…)`, per architecture.

    Read from the declaration the filter is built from, for the reason `shim_exports`
    is read from the export calls: a transcribed list would verify itself. Returns a dict
    keyed by architecture — the set differs between them, because the legacy spellings
    (`open`, `rename`, `unlink`, …) exist as syscalls on x86-64 only.
    """
    text = open(path).read()
    start = text.index("const trapped: []const Trap = switch")
    end = text.index("\n};", start)
    parts = re.split(r"\n    \.([a-z0-9_]+) => ", text[start:end])
    # parts[0] is everything before the first architecture; then arch, body, arch, body…
    return {
        parts[i]: set(re.findall(r"\.sys = \.([a-z0-9_]+)", parts[i + 1]))
        for i in range(1, len(parts) - 1, 2)
    }


def oracle_trap_copy(path):
    """The members of `isTrapped`'s own list in src/oracle.zig.

    The oracle parses text and the shim builds a BPF program, so the two cannot share a
    declaration; the oracle keeps its own copy of the trapped set, spelled the way strace
    prints it. Read from the function rather than transcribed here, for the reason
    `shim_trap_set` is read from the declaration the filter is built from.
    """
    text = open(path).read()
    start = text.index("fn isTrapped(")
    end = text.index("\n}", start)
    body = text[start:end]
    start = body.index("const set = [_][]const u8{")
    end = body.index("};", start)
    return set(re.findall(r'"([a-z0-9_]+)"', body[start:end]))


def check_trap_copy(oracle_path, syscalls_path):
    """The third comparison: the oracle's copy of the trap set against the shim's.

    The copy decides which appended entry a `--- SIGSYS ---` retracts (ADR 0054). A member
    the oracle's copy lacks costs a retraction that should have happened, and the
    completeness comparison then refuses on the extra operation — loud rather than silent,
    but loud in a place that names neither list. A member the oracle's copy has and the
    filter does not is worse and quieter: nothing raises a signal for it, so nothing is
    retracted and nothing says the copy disagrees.
    """
    try:
        copy = oracle_trap_copy(oracle_path)
        per_arch = shim_trap_set(syscalls_path)
    except (OSError, ValueError) as exc:
        print("  BROKEN could not read the trap set or the oracle's copy: %s" % exc)
        return 2
    if not copy or not per_arch or not all(per_arch.values()):
        print("  BROKEN one side parsed empty (oracle copy=%d, arches=%s) — a zero here"
              " means the parse broke, not that the two agree"
              % (len(copy), {a: len(s) for a, s in sorted(per_arch.items())}))
        return 2
    # The union, because ONE reader serves both machines: a capture from either arrives at
    # the same `isTrapped`, so a name trapped on one of them has to be in the copy, and a
    # name in the copy has to be trapped on at least one or nothing can ever raise the
    # signal it claims to know about.
    trapped = set().union(*per_arch.values())
    # No libc-to-kernel mapping on either side here, unlike `check_trap_set` above: the
    # `SYS` enum members ARE kernel names, and strace prints kernel names, so the oracle's
    # copy is already spelled that way. A mapping would only hide a real disagreement.
    missing = sorted(trapped - copy)
    extra = sorted(copy - trapped)
    print("  the shim traps %s; the oracle's copy holds %d"
          % (", ".join("%d on %s" % (len(s), a) for a, s in sorted(per_arch.items())),
             len(copy)))
    if missing:
        print("  FAILED trapped by the filter but missing from isTrapped: %s"
              % ", ".join(missing))
        print("         a refusal for one of these retracts nothing, and the completeness"
              " comparison refuses on the operation that was counted twice")
    if extra:
        print("  FAILED in isTrapped but in neither architecture's trap set: %s"
              % ", ".join(extra))
        print("         nothing ever raises SIGSYS for these, so the entry says a rule"
              " applies where no rule can fire")
    if missing or extra:
        return 1
    print("  ok   the oracle's copy of the trap set is both architectures' trap sets")
    return 0


def check_trap_set(oracle_path, syscalls_path, contract_path):
    """The second comparison: every kill point the oracle knows is trapped or explained."""
    try:
        classes = kill_point_classes(contract_path)
        kill_points = oracle_kill_points(oracle_path, classes)
        per_arch = shim_trap_set(syscalls_path)
    except (OSError, ValueError) as exc:
        print("  BROKEN could not read the trap set: %s" % exc)
        return 2
    if not classes or not kill_points or not per_arch or not all(per_arch.values()):
        print("  BROKEN one side parsed empty (classes=%d, kill-point names=%d,"
              " arches=%s) — a zero here means a declaration moved, not that the sets"
              " agree" % (len(classes), len(kill_points),
                          {a: len(s) for a, s in sorted(per_arch.items())}))
        return 2
    # The union, for the reason `check_trap_copy` takes it: a name trapped on either
    # machine is covered at the syscall boundary on that machine, and a name trapped on
    # neither is the gap this comparison is looking for.
    trapped = set().union(*per_arch.values())

    # The trap set is written in kernel spelling and `known` in libc spelling; the
    # names that differ are the LFS aliases, which the kernel does not have. `pwrite`
    # and `pwrite64` are one syscall, and so are `sendfile` and `sendfile64`.
    def kernel_name(libc_name):
        return {
            "pwrite": "pwrite64",
            "pwritev64": "pwritev",
            "sendfile64": "sendfile",
            "ftruncate64": "ftruncate",
            "truncate64": "truncate",
        }.get(libc_name, libc_name)

    unaccounted = sorted(
        n for n in kill_points
        if kernel_name(n) not in trapped and n not in NOT_TRAPPED
    )
    contradicted = sorted(
        n for n in NOT_TRAPPED if kernel_name(n) in trapped
    )
    stale = sorted(n for n in NOT_TRAPPED if n not in kill_points)

    print("  oracle classifies %d syscalls as kill points (%d classes); the trap set holds"
          " %d across both architectures; %d covered at the libc boundary only"
          % (len(kill_points), len(classes), len(trapped), len(NOT_TRAPPED)))
    if unaccounted:
        print("  FAILED a kill point, but neither trapped nor explained: %s"
              % ", ".join(unaccounted))
        print("         add it to `trapped` in shim/src/syscalls.zig, or to NOT_TRAPPED"
              " in this file with what a raw call to it would cost")
    if contradicted:
        print("  FAILED explained as not-trapped, but the trap set holds it: %s"
              % ", ".join(contradicted))
        print("         the reason is stale; delete the NOT_TRAPPED entry")
    if stale:
        print("  FAILED explained here but not classified as a kill point: %s"
              % ", ".join(stale))
        print("         this reason covers no syscall — a typo, or a name whose class"
              " moved")
    if unaccounted or contradicted or stale:
        return 1
    print("  ok   every kill point the oracle classifies is trapped or explained")
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
    if len(argv) not in (3, 4, 5):
        print("  BROKEN usage: check-shim-coverage.py <oracle.zig> <linux.zig>"
              " [syscalls.zig [contract.zig]]")
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
    # The extra paths are optional so that a two-argument invocation keeps working; the
    # acceptance suite and CI pass all four, so neither comparison below is optional
    # in practice. Each is skipped only when the path it reads was not supplied — never
    # when it fails, and a skipped one prints nothing rather than an "ok".
    if len(argv) >= 4:
        rc = check_trap_copy(argv[1], argv[3])
        if rc != 0:
            return rc
    if len(argv) >= 5:
        rc = check_trap_set(argv[1], argv[3], argv[4])
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
