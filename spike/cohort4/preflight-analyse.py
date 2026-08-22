import os, re, sys

mode, root, strace_path, logger_path = sys.argv[1:5]
root = os.path.realpath(root)

# The engine counts these classes (src/contract.zig OpClass). chmod and
# friends are metadata, observed and not judged (#121, #190).
SYSCALL_CLASS = {
    "open": "open", "openat": "open", "openat2": "open", "creat": "open",
    "write": "write", "pwrite64": "write", "writev": "write",
    "pwritev": "write",
    "rename": "rename", "renameat": "rename", "renameat2": "rename",
    "unlink": "unlink", "unlinkat": "unlink",
    "fsync": "fsync", "fdatasync": "fsync",
    "truncate": "truncate", "ftruncate": "truncate",
    "mkdir": "mkdir", "mkdirat": "mkdir",
    "rmdir": "rmdir",
    "link": "link", "linkat": "link",
    "symlink": "symlink", "symlinkat": "symlink",
}
# Every class is compared by path. The descriptor classes reach the
# interposer as a number, so the logger resolves them through
# /proc/self/fd; anything it could not resolve is reported separately and
# never used to excuse a mismatch.
# Syscalls whose mutation is addressed by a quoted path argument. The
# rest are addressed by a descriptor, which strace -y decorates with the
# path and the logger resolves through /proc/self/fd - so every class is
# still compared path to path.
TAKES_PATH_ARG = {
    "open", "openat", "openat2", "creat",
    "rename", "renameat", "renameat2",
    "unlink", "unlinkat", "truncate",
    "mkdir", "mkdirat", "rmdir",
    "link", "linkat", "symlink", "symlinkat",
}
MUTATING_OPEN = re.compile(r"O_(CREAT|TRUNC|WRONLY|RDWR|APPEND)")

line_re = re.compile(r"^(?:\[pid\s+\d+\]\s*|\d+\s+)?([a-z_0-9]+)\((.*)\)\s*=\s*(-?\d+|0x[0-9a-f]+)")
# strace -y decorates descriptors as 3</abs/path>
fdpath_re = re.compile(r"<([^>]+)>")
quoted_re = re.compile(r'"((?:[^"\\]|\\.)*)"')

def in_root(p):
    if not p:
        return False
    if not p.startswith("/"):
        p = os.path.join(os.getcwd(), p)
    p = os.path.realpath(p)
    return p == root or p.startswith(root + os.sep)

kernel = {}          # class -> list of (path, rawline)
unlink_is_rmdir = False

with open(strace_path, errors="replace") as fh:
    for raw in fh:
        m = line_re.match(raw.strip())
        if not m:
            continue
        name, args, rc = m.group(1), m.group(2), m.group(3)
        cls = SYSCALL_CLASS.get(name)
        if cls is None:
            continue
        if rc.startswith("-"):        # failed calls change nothing
            continue
        if cls == "open" and not MUTATING_OPEN.search(args):
            continue                  # read-only open is not a mutation
        if name == "unlinkat" and "AT_REMOVEDIR" in args:
            cls = "rmdir"

        # Which argument carries the path is a property of the SYSCALL,
        # not of its class: write(4</p>, "text") has a quoted argument
        # that is payload, and openat(AT_FDCWD</work>, "p") has an
        # angle-bracket decoration that is the wrong directory. Deciding
        # by class silently read the write payload as a path and dropped
        # every write - measured 2026-08-22, caught by the self-test.
        if name in TAKES_PATH_ARG:
            paths = quoted_re.findall(args)
            # rename/link take (from, to); the mutation lands on the last.
            target = paths[-1] if paths else None
        else:
            fds = fdpath_re.findall(args)
            target = fds[0] if fds else None

        if target is None or not in_root(target):
            continue
        kernel.setdefault(cls, []).append((target, raw.strip()))

logger = {}
if os.path.exists(logger_path):
    with open(logger_path, errors="replace") as fh:
        for raw in fh:
            parts = raw.split()
            if len(parts) < 3 or parts[0] != "LOGGER":
                continue
            logger.setdefault(parts[1], []).append(parts[2])

if mode == "interior":
    total = sum(len(v) for v in kernel.values())
    detail = ", ".join("%s=%d" % (k, len(v)) for k, v in sorted(kernel.items())) or "none"
    print("INTERIOR kill points inside the state root: %d (%s)" % (total, detail))
    if total == 0:
        print("  reading: the engine would have nothing to kill between - not a target")
    elif total == 1:
        print("  reading: one atomic mutation - no interior to crash inside;")
        print("           a contrast measurement, not a criterion-1 slot (the papis shape)")
    else:
        print("  reading: %d crash points; the operation has an interior" % total)
    sys.exit(0)

# visibility
missed = []
lines = []
for cls in sorted(kernel):
    seen = kernel[cls]
    logged = logger.get(cls, [])
    unresolved = [p for p in logged if p.startswith("fd=")]
    logged_names = set(os.path.basename(p) for p in logged if not p.startswith("fd="))
    unmatched = [rawline for path, rawline in seen
                 if os.path.basename(path) not in logged_names]
    note = "" if not unresolved else ", %d interposed call(s) had no resolvable path" % len(unresolved)
    lines.append("  %-8s kernel=%d/%d in-root, interposed=%d, unmatched=%d%s"
                 % (cls, len(seen), len(seen), len(logged), len(unmatched), note))
    for rawline in unmatched:
        missed.append((cls, rawline))

if not kernel:
    print("BROKEN no state-root mutation observed at all - wrong root, or the")
    print("       operation did nothing (a zero with no denominator is not a pass)")
    sys.exit(2)

print("\n".join(lines))
if missed:
    print("WALL the kernel mutated the state root past the interposer:")
    for cls, detail in missed:
        print("  %-8s %s" % (cls, detail))
    print("  reading: an LD_PRELOAD shim cannot see these; this is the cargo")
    print("           class (#217), a named wall at probe time, zero defines spent")
    sys.exit(1)

print("PASS every in-root mutation passed through an interposable function")
sys.exit(0)