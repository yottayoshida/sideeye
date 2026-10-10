"""Which threads changed the state, from `strace -f -y`: one line per thread or process that made a
changing call on a path under the state (an open for writing, a write to such a descriptor, a rename,
unlink, truncate, fsync, mkdir, chmod, or a shared writable mapping), with its count and first calls.
Threads (clone with CLONE_THREAD) are told from processes, and each names the one that made it."""
import re, sys
trace, state = sys.argv[1], sys.argv[2].rstrip("/")
line_re = re.compile(r"^(\d+)\s+(\w+)\((.*)\)\s+=\s+(-?\d+|\?)(<[^>]*>)?")
made = {}   # id -> (parent, "thread"|"process")
changes = {}
first = None
def touches(args):
    # A relative path's directory descriptor is shown as AT_FDCWD</cwd>; when the cwd is the state,
    # that annotation is not a path the call changed, so it is cut before looking.
    cwd = re.search(r"AT_FDCWD<([^>]*)>", args)
    if cwd and (cwd.group(1) == state or cwd.group(1).startswith(state + "/")) and re.search(r'AT_FDCWD<[^>]*>, "[^/"]', args):
        return True   # a relative path, and the cwd is inside the state
    args = re.sub(r"AT_FDCWD<[^>]*>", "AT_FDCWD", args)
    return state + "/" in args or ('"' + state + '"') in args or ("<" + state + ">") in args or ("<" + state + "/") in args
for raw in open(trace, errors="replace"):
    m = line_re.match(raw)
    if not m:
        continue
    pid, call, args, ret = int(m.group(1)), m.group(2), m.group(3), m.group(4)
    if call in ("open", "openat", "creat") and m.group(5):
        args += " = " + m.group(5)   # a relative path's file, as the descriptor it returned names it
    if first is None:
        first = pid
    if call in ("clone", "clone3", "fork", "vfork") and ret.lstrip("-").isdigit() and int(ret) > 0:
        made[int(ret)] = (pid, "thread" if "CLONE_THREAD" in args else "process")
        continue
    if not touches(args):
        continue
    kind = None
    if call in ("open", "openat", "creat"):
        if call == "creat" or re.search(r"O_WRONLY|O_RDWR|O_CREAT|O_TRUNC", args):
            kind = "open-w"
    elif call == "mmap":
        if "PROT_WRITE" in args and "MAP_SHARED" in args:
            kind = "mmap-shared-w"
    elif call != "execve":
        kind = call
    if kind is None:
        continue
    if ret.startswith("-"):
        kind += "(failed)"
    paths = re.findall(r'"(' + re.escape(state) + r'[^"]*)"|<(' + re.escape(state) + r'[^>]*)>', re.sub(r"AT_FDCWD<[^>]*>", "", args))
    names = sorted({a or b for a, b in paths}) or ["(relative) " + ",".join(re.findall(r'AT_FDCWD<[^>]*>, "([^/"][^"]*)"', args))]
    changes.setdefault(pid, []).append((kind, " ".join((n[len(state) + 1:] or ".") if n.startswith(state) else n for n in names)))
def lineage(p):
    out = []
    while p in made:
        parent, k = made[p]
        out.append(f"{k} of {parent}")
        p = parent
    return ", ".join(out) or "the first process"
print(f"state {state}: {len(changes)} thread(s)/process(es) changed it")
for pid, cs in sorted(changes.items(), key=lambda kv: kv[0]):
    kinds = {}
    for k, _ in cs:
        kinds[k] = kinds.get(k, 0) + 1
    print(f"- {pid} ({lineage(pid)}): {len(cs)} calls " + " ".join(f"{k}={n}" for k, n in sorted(kinds.items())))
    seen = {}
    for k, n in cs:
        seen.setdefault(n, []).append(k)
    for n, ks in seen.items():
        print(f"    {n}: " + " ".join(sorted(set(ks))))
