"""Whether a creation or an exit orders the hand-overs between a process's writing threads (#687).

Reads an `strace -f -y` capture — the oracle capture Sideeye leaves in its work directory, or any
capture taken with `-f -y` (with or without `-tt`) — and a state directory. A *write* is a call of
one of the engine's ten kill-point classes (open for writing, write, rename, unlink, fsync,
truncate, mkdir, rmdir, link, symlink) on a path under the state, failed calls included: the
engine counts a failed mkdir as the writer it names. A *hand-over* is two consecutive writes of
one process made by two different threads, A then B. It is ordered when, between A's write and
B's, either A (or a thread A created in that window) created B, or A exited — the two events a
supervisor can see from outside; a join is seen from outside only as the exit, so (b) is the
generous side.

Per capture: `no-handover`, `all-ordered`, or `unordered` (at least one hand-over neither event
orders) — the last is the one recording creations and exits from outside would not admit.

    python3 order.py <capture> <state>       one line of JSON
    python3 order.py --selftest              the synthetic cases, red and green
"""
import json
import re
import sys

LINE = re.compile(r"^(\d+)\s+(?:\d\d:\d\d:\d\d\.\d+\s+)?(.*)$")
CALL = re.compile(r"^(\w+)\((.*)$")
RESUMED = re.compile(r"^<\.\.\. (\w+) resumed>(.*)$")
RET = re.compile(r"\)\s+=\s+(-?\d+|\?)(<[^>]*>)?")
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
FD_PATH = re.compile(r"^\s*-?\w+<([^>]*)>")

OPENS = ("open", "openat", "openat2", "creat")
FD_WRITES = ("write", "pwrite64", "writev", "pwritev", "pwritev2", "ftruncate", "fsync", "fdatasync", "sync_file_range")
PATH_CALLS = ("rename", "renameat", "renameat2", "unlink", "unlinkat", "rmdir", "mkdir", "mkdirat",
              "link", "linkat", "symlink", "symlinkat", "truncate")


def calls(lines):
    """(index, tid, name, args, ret, ret_annotation, kind) in capture order; kind is 'call', 'exit'.
    A split call is joined, and placed at the line where it was entered."""
    pending = {}
    out = []
    for idx, raw in enumerate(lines):
        m = LINE.match(raw.rstrip("\n"))
        if not m:
            continue
        tid, body = int(m.group(1)), m.group(2)
        if body.startswith("+++ exited") or body.startswith("+++ killed"):
            out.append((idx, tid, "+++", "", None, None, "exit"))
            continue
        if body.startswith("---"):
            continue
        r = RESUMED.match(body)
        if r:
            if tid in pending:
                start, name, head = pending.pop(tid)
                full = head + r.group(2)
                rm = RET.search(full)
                out.append((start, tid, name, full, rm.group(1) if rm else None, rm.group(2) if rm else None, "call"))
            continue
        c = CALL.match(body)
        if not c:
            continue
        name, rest = c.group(1), c.group(2)
        if rest.endswith("<unfinished ...>"):
            pending[tid] = (idx, name, rest[: -len("<unfinished ...>")])
            continue
        rm = RET.search(rest)
        out.append((idx, tid, name, rest, rm.group(1) if rm else None, rm.group(2) if rm else None, "call"))
    for tid, (start, name, head) in pending.items():   # a call that never returned (exit, a kill)
        out.append((start, tid, name, head, None, None, "call"))
    out.sort(key=lambda e: e[0])
    return out


def under(path, state):
    return path is not None and (path == state or path.startswith(state + "/"))


def resolve(dirfd_arg, s):
    if s.startswith("/"):
        return s
    fm = FD_PATH.match(dirfd_arg or "")
    return (fm.group(1).rstrip("/") + "/" + s) if fm else None


def written_paths(name, args, ann):
    """The paths a call of the ten classes changes, or None when the call is not one of them."""
    parts = args.split(", ")
    strs = STR.findall(args)
    if name in OPENS:
        if name != "creat" and not re.search(r"O_WRONLY|O_RDWR|O_CREAT|O_TRUNC", args):
            return None
        if ann:
            return [ann[1:-1]]
        if name == "openat" or name == "openat2":
            return [resolve(parts[0], strs[0])] if strs else []
        return [strs[0] if strs else None]
    if name in FD_WRITES:
        fm = FD_PATH.match(args)
        return [fm.group(1)] if fm else []
    if name in PATH_CALLS:
        if name in ("rename", "link", "symlink", "unlink", "rmdir", "mkdir", "truncate"):
            if name == "symlink":
                return [resolve("", strs[1])] if len(strs) > 1 else []
            return [s for s in strs[:2]]
        if name == "symlinkat":   # symlinkat(target, newdirfd, linkpath)
            return [resolve(parts[1] if len(parts) > 1 else "", strs[1])] if len(strs) > 1 else []
        if name in ("renameat", "renameat2", "linkat"):
            # (olddirfd, oldpath, newdirfd, newpath, ...): the string args alternate with the fds
            fds = [p for p in parts if FD_PATH.match(p) or p.strip().startswith("AT_FDCWD")]
            out = []
            for k, s in enumerate(strs[:2]):
                out.append(resolve(fds[k] if k < len(fds) else "", s))
            return out
        return [resolve(parts[0], strs[0])] if strs else []   # unlinkat, mkdirat
    return None


def analyse(lines, state):
    state = state.rstrip("/")
    made = {}        # child -> (parent, index of the parent's clone entry)
    tgid = {}        # thread -> its process
    exits = {}       # thread -> first index it exited at
    writes = []      # (index, tid)
    first = None
    for idx, tid, name, args, ret, ann, kind in calls(lines):
        if first is None:
            first = tid
            tgid[tid] = tid
        tgid.setdefault(tid, tid)
        if kind == "exit" or name in ("exit", "exit_group"):
            exits.setdefault(tid, idx)
            continue
        if name in ("clone", "clone3", "fork", "vfork") and ret and ret.lstrip("-").isdigit() and int(ret) > 0:
            child = int(ret)
            made[child] = (tid, idx)
            tgid[child] = tgid[tid] if "CLONE_THREAD" in args else child
            continue
        paths = written_paths(name, args, ann)
        if paths and any(under(p, state) for p in paths):
            writes.append((idx, tid))

    def created_by_after(a, b, i):
        x = b
        while x in made:
            p, c = made[x]
            if p == a:
                return c > i
            x = p
        return False

    handovers = ordered_create = ordered_exit = 0
    unordered = []
    by_proc = {}
    for idx, tid in writes:
        by_proc.setdefault(tgid.get(tid, tid), []).append((idx, tid))
    writers = {}
    for proc, ws in by_proc.items():
        writers[proc] = sorted({t for _, t in ws})
        for (i, a), (j, b) in zip(ws, ws[1:]):
            if a == b:
                continue
            handovers += 1
            if created_by_after(a, b, i):
                ordered_create += 1
            elif a in exits and i < exits[a] < j:
                ordered_exit += 1
            else:
                unordered.append({"from": a, "to": b, "lines": [i + 1, j + 1]})
    verdict = "no-handover" if handovers == 0 else ("all-ordered" if not unordered else "unordered")
    return {"verdict": verdict, "writes": len(writes), "handovers": handovers,
            "ordered_by_creation": ordered_create, "ordered_by_exit": ordered_exit,
            "unordered": len(unordered), "first_unordered": unordered[:3],
            "writers_by_process": {str(k): v for k, v in writers.items()}}


SELFTEST = {
    # A writes, creates B; B writes and exits; A writes again: both hand-overs ordered.
    "all-ordered": ("all-ordered", """\
10 openat(AT_FDCWD</s>, "a", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</s/a>
10 clone3({flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM, exit_signal=0}, 88 <unfinished ...>
11 openat(AT_FDCWD</s>, "b", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 4</s/b>
10 <... clone3 resumed>) = 11
11 exit(0) = ?
11 +++ exited with 0 +++
10 openat(AT_FDCWD</s>, "c", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</s/c>
"""),
    # B is created before anything is written and lives to the end: nothing orders either hand-over.
    "unordered": ("unordered", """\
10 clone3({flags=CLONE_VM|CLONE_THREAD, exit_signal=0}, 88) = 11
10 openat(AT_FDCWD</s>, "a", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</s/a>
11 write(4</s/b>, "b\\n", 2) = 2
10 openat(AT_FDCWD</s>, "c", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</s/c>
11 +++ exited with 0 +++
"""),
    # A -> B is ordered by the creation, B -> A by nothing (B still alive): one unordered is enough.
    "partial": ("unordered", """\
10 mkdir("/s/d", 0755) = 0
10 clone3({flags=CLONE_VM|CLONE_THREAD, exit_signal=0}, 88) = 11
11 mkdirat(AT_FDCWD</x>, "/s/d", 0755) = -1 EEXIST (File exists)
10 renameat(AT_FDCWD</s>, "t", AT_FDCWD</s>, "c") = 0
11 +++ exited with 0 +++
"""),
    # One writing thread: a thread is created but never writes the state — nothing to order.
    "one-writer": ("no-handover", """\
10 openat(AT_FDCWD</s>, "a", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</s/a>
10 clone3({flags=CLONE_VM|CLONE_THREAD, exit_signal=0}, 88) = 11
11 openat(AT_FDCWD</s>, "a", O_RDONLY) = 4</s/a>
11 write(5</elsewhere/log>, "x", 1) = 1
10 unlinkat(AT_FDCWD</s>, "a", 0) = 0
"""),
    # A creates B, then keeps writing; B writes after A's last write: the creation came before A's
    # last write, so it orders nothing. A reader that only asks "did A create B" says ordered here.
    "created-then-kept-writing": ("unordered", """\
10 openat(AT_FDCWD</s>, "a", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</s/a>
10 clone3({flags=CLONE_VM|CLONE_THREAD, exit_signal=0}, 88) = 11
10 write(3</s/a>, "more", 4) = 4
11 fsync(3</s/a>) = 0
"""),
}


def selftest():
    bad = 0
    for name, (want, text) in SELFTEST.items():
        got = analyse(text.splitlines(True), "/s")["verdict"]
        print(f"{'ok  ' if got == want else 'FAIL'} {name}: {got} (wanted {want})")
        bad += got != want
    # The reader's own red: a version that ignores the window must fail the last case.
    global_created = analyse(SELFTEST["created-then-kept-writing"][1].splitlines(True), "/s")
    if global_created["ordered_by_creation"] != 0:
        print("FAIL the creation window is not read: a creation before A's last write ordered a hand-over")
        bad += 1
    return bad


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(1 if selftest() else 0)
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], errors="replace") as f:
        print(json.dumps(analyse(f.readlines(), sys.argv[2])))
