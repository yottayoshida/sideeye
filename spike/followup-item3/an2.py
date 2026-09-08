import re, sys
lines = open(sys.argv[1], errors='replace').read().splitlines()
STORE = sys.argv[2]
pid_re = re.compile(r'^(\d+)\s+(.*)$')
PATH_OPS = {'openat','open','creat','renameat','renameat2','rename','unlink','unlinkat',
            'mkdir','mkdirat','rmdir','link','linkat','symlink','symlinkat','truncate'}
FD_OPS   = {'write','pwrite','pwrite64','writev','pwritev','pwritev2','ftruncate','fsync','fdatasync'}
def name(t):
    m = re.match(r'([a-z_0-9]+)\(', t)
    return m.group(1) if m else None
def in_scope(n, t):
    """Scope decided the way the engine does: paths from the path argument, fd calls from
    the -y annotation of the descriptor. Never from a string that merely contains the dir."""
    if n in PATH_OPS:
        if n in ('openat','open','creat') and ('O_RDONLY' in t and 'O_CREAT' not in t and 'O_TRUNC' not in t):
            return False
        # every quoted path argument, plus the -y annotations on dirfds
        args = t[t.index('(')+1:]
        for q in re.findall(r'"([^"]*)"', args):
            if q.startswith(STORE + '/') or q == STORE: return True
        for a in re.findall(r'<([^<>]*)>', args):
            if a.startswith(STORE) : return True
        return False
    if n in FD_OPS:
        m = re.match(r'[a-z_0-9]+\(\s*\d+<([^<>]*)>', t)
        return bool(m and m.group(1).startswith(STORE + '/'))
    return False
ev = [(i, int(m.group(1)), m.group(2)) for i, ln in enumerate(lines) if (m := pid_re.match(ln))]
writers, born, died = {}, {}, {}
for i, pid, t in ev:
    n = name(t)
    if n and in_scope(n, t): writers.setdefault(pid, []).append((i, n, t[:90]))
    m = re.search(r'^(?:<\.\.\. )?clone[0-9]*(?: resumed>)?.*\)\s+=\s+(\d+)$', t)
    if m: born[int(m.group(1))] = i
    if t.startswith('+++ exited'): died[pid] = i
subject = ev[0][1]
print(f"subject={subject}  in-scope writers={sorted(writers)}")
for pid, ops in sorted(writers.items()):
    tag = " (SUBJECT)" if pid == subject else ""
    print(f"\npid {pid}{tag}: clone@{born.get(pid,'-')} exit@{died.get(pid,'-')}")
    for i, n, t in ops: print(f"   line {i+1}: {n}   {t}")
kids = [p for p in writers if p != subject]
for a in range(len(kids)):
    for c in range(a+1, len(kids)):
        p, q = kids[a], kids[c]
        ov = not (died.get(p,10**9) < born.get(q,-1) or died.get(q,10**9) < born.get(p,-1))
        print(f"lifetimes {p} vs {q}: {'OVERLAP' if ov else 'disjoint'}")
for p in kids:
    b, d = born.get(p), died.get(p)
    if b is None or d is None: print(f"pid {p}: lifetime incomplete"); continue
    subj_inside = [i for i, n, t in writers.get(subject, []) if b < i < d]
    span = [(i, q, t) for i, q, t in ev if b < i < d and q != p]
    unf = [t for i, q, t in span if q == subject and '<unfinished' in t]
    print(f"pid {p}: subject's in-scope mutations inside its lifetime: {len(subj_inside)}; "
          f"subject lines inside: {len([1 for _,q,_ in span if q==subject])}; "
          f"subject blocked in an unfinished call: {'yes: ' + unf[0][:40] if unf else 'no'}")
