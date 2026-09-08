import re, sys
lines = open(sys.argv[1], errors='replace').read().splitlines()
pid_re = re.compile(r'^(\d+)\s+(.*)$')
WRITE = ('openat','open','write','pwrite','writev','rename','renameat','renameat2',
         'unlink','unlinkat','mkdir','mkdirat','rmdir','fsync','fdatasync','truncate',
         'ftruncate','link','linkat','symlink','symlinkat','dup3','creat')
STORE = sys.argv[2]
ev = []           # (index, pid, text)
for i, ln in enumerate(lines):
    m = pid_re.match(ln)
    if m: ev.append((i, int(m.group(1)), m.group(2)))
def name(t):
    m = re.match(r'([a-z_0-9]+)\(', t)
    return m.group(1) if m else None
# in-scope mutations per pid (writes naming a path under STORE, read-only opens excluded)
writers = {}
for i, pid, t in ev:
    n = name(t)
    if n not in WRITE: continue
    if STORE not in t: continue
    if n in ('openat','open','creat') and 'O_RDONLY' in t: continue
    writers.setdefault(pid, []).append((i, n))
# lifetimes: clone returning pid -> its "+++ exited" line
born, died = {}, {}
for i, pid, t in ev:
    m = re.search(r'^clone[0-9]*\(.*\)\s+=\s+(\d+)$', t)
    if m: born[int(m.group(1))] = i
    m = re.search(r'^<\.\.\. clone[0-9]* resumed>.*\)\s+=\s+(\d+)$', t)
    if m: born[int(m.group(1))] = i
    if t.startswith('+++ exited'): died[pid] = i
subject = ev[0][1]
print(f"subject pid = {subject};  in-scope writers = {sorted(writers)}")
for pid, ops in sorted(writers.items()):
    b, d = born.get(pid), died.get(pid)
    print(f"\n--- pid {pid}: {len(ops)} in-scope mutation(s) {[o[1] for o in ops]}"
          f" at lines {[o[0]+1 for o in ops]}; clone@{b+1 if b else '?'} exit@{d+1 if d else '?'}")
    if pid == subject: continue
    # what the parent did between clone and exit
    inside = [(i, p, t) for (i, p, t) in ev if b is not None and d is not None and b < i < d and p != pid]
    print(f"    other-pid lines inside its lifetime: {len(inside)}")
    for i, p, t in inside[:6]:
        print(f"      {i+1}: {p}  {t[:110]}")
    # the parent's line immediately before the clone and immediately after the exit
    prev = [(i, p, t) for (i, p, t) in ev if i < b and p != pid]
    nxt = [(i, p, t) for (i, p, t) in ev if i > d and p != pid]
    if prev: print(f"    parent-side line before clone: {prev[-1][0]+1}: {prev[-1][1]}  {prev[-1][2][:110]}")
    if nxt:  print(f"    parent-side line after  exit : {nxt[0][0]+1}: {nxt[0][1]}  {nxt[0][2][:110]}")
# overlap between writers' lifetimes
ws = [p for p in writers if p != subject]
for a in range(len(ws)):
    for c in range(a+1, len(ws)):
        p, q = ws[a], ws[c]
        if p in born and p in died and q in born and q in died:
            ov = not (died[p] < born[q] or died[q] < born[p])
            print(f"\nlifetimes {p} vs {q}: {'OVERLAP' if ov else 'disjoint'}")
