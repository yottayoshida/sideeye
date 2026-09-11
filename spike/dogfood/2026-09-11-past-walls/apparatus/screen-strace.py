"""Read an `strace -f -y` capture and say which threads of which process wrote the state.

usage: screen-strace.py <capture> <state dir>

Contract v16 asks one question of threads — how many threads of one process wrote the
judged directory — and contract v15 one of processes — which processes wrote it. This
answers both from the capture, independently of the engine, so a refusal can be read
against what the target actually did. `<unfinished ...>` / `<... resumed>` pairs are
joined first: the item-4 measurement found a third wall in exactly those split lines.
"""
import re
import sys
from collections import defaultdict

cap, sd = sys.argv[1], sys.argv[2].rstrip("/")
line_re = re.compile(r"^(\d+)\s+(.*)$")
call_re = re.compile(r"^(\w+)\((.*)\)\s+=\s+(-?\d+|\?)")
WRITE_FD = {"write", "pwrite64", "writev", "pwritev", "ftruncate", "fsync", "fdatasync"}
PATHY = {"rename", "renameat", "renameat2", "unlink", "unlinkat", "mkdirat"}

pending = {}
tgid = {}
root = None
threads = procs = 0
execs = defaultdict(int)
exec_of = {}
wrote = defaultdict(lambda: defaultdict(list))  # tgid -> tid -> [op]
errors = 0

for raw in open(cap, errors="replace"):
    m = line_re.match(raw.rstrip("\n"))
    if not m:
        continue
    pid, rest = int(m.group(1)), m.group(2)
    if root is None:
        root = pid
        tgid[pid] = pid
    tgid.setdefault(pid, pid)
    if rest.endswith("<unfinished ...>"):
        pending[pid] = rest[: -len("<unfinished ...>")].rstrip()
        continue
    rm = re.match(r"^<\.\.\. (\w+) resumed>(.*)$", rest)
    if rm:
        rest = pending.pop(pid, rm.group(1) + "(") + rm.group(2)
    cm = call_re.match(rest)
    if not cm:
        continue
    name, args, ret = cm.group(1), cm.group(2), cm.group(3)
    if ret == "?" :
        continue
    r = int(ret)
    if name in ("clone", "clone3", "fork", "vfork") and r > 0:
        if "CLONE_THREAD" in args:
            threads += 1
            tgid[r] = tgid[pid]
        else:
            procs += 1
            tgid[r] = r
        continue
    if name == "execve" and r == 0:
        prog = args.split(",", 1)[0].strip('"').rsplit("/", 1)[-1]
        execs[prog] += 1
        exec_of[tgid[pid]] = prog
        continue
    if r < 0:
        errors += 1
        continue
    if sd not in args:
        continue
    op = None
    if name == "openat":
        if re.search(r"O_WRONLY|O_RDWR|O_CREAT|O_TRUNC", args):
            path = re.search(r'"([^"]*)"', args)
            op = "open(%s)" % (path.group(1).rsplit("/", 1)[-1] if path else "?")
    elif name in WRITE_FD:
        fd = re.match(r"\d+<([^>]*)>", args)
        if fd and fd.group(1).startswith(sd):
            op = "%s(%s)" % (name, fd.group(1).rsplit("/", 1)[-1])
    elif name in PATHY:
        paths = re.findall(r'"([^"]*)"', args)
        op = "%s(%s)" % (name, ",".join(p.rsplit("/", 1)[-1] for p in paths))
    if op:
        wrote[tgid[pid]][pid].append(op)

print("  strace: %d thread(s) created, %d process(es) created, execve %s"
      % (threads, procs, dict(sorted(execs.items(), key=lambda kv: -kv[1])[:8]) or "none"))
if not wrote:
    print("  strace: nothing written under the state directory")
for g, tids in wrote.items():
    who = exec_of.get(g, "?") + (" (the subject)" if g == root else "")
    print("  strace: process %d %s — %d tid(s) wrote the state" % (g, who, len(tids)))
    for t, ops in tids.items():
        uniq = []
        for o in ops:
            if o not in uniq:
                uniq.append(o)
        print("    tid %d: %d op(s): %s%s" % (t, len(ops), ", ".join(uniq[:6]), " …" if len(uniq) > 6 else ""))
