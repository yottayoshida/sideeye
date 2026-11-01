#!/usr/bin/env python3
"""Read the re-recorded traces and say what each would do under the two power-loss rules (#958).

Usage: tabulate.py <transcripts dir>     prints the table (Markdown) and writes table.json there
       tabulate.py --selftest

The rules and what decides them are SELECTION.md's. Exit 0 when every trace read; 2 when one
could not be read or the arguments are wrong; 1 when the selftest fails.
"""

import json
import os
import re
import sys

WRITE_FD0 = {"write", "pwrite64", "writev", "pwritev", "pwritev2", "fallocate", "ftruncate", "sendfile"}
SYNC = {"fsync", "fdatasync"}
SEEN_ONLY = {"syncfs", "sync", "msync", "sync_file_range"}
LINE = re.compile(r"^(\d+)\s+(.*)$")


def split_args(s):
    out, cur, depth, q, i = [], [], 0, False, 0
    while i < len(s):
        ch = s[i]
        if q:
            cur.append(ch)
            if ch == "\\" and i + 1 < len(s):
                cur.append(s[i + 1])
                i += 1
            elif ch == '"':
                q = False
        elif ch == '"':
            q = True
            cur.append(ch)
        elif ch in "<[{(":
            depth += 1
            cur.append(ch)
        elif ch in ">]})":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    if cur or out:
        out.append("".join(cur).strip())
    return out


def unescape(s):
    s = s[1:-1] if s.startswith('"') else s
    s = s.rstrip(".") if s.endswith('"...') else s
    b, i = bytearray(), 0
    while i < len(s):
        ch = s[i]
        if ch == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n in "01234567":
                j = i + 1
                while j < len(s) and j < i + 4 and s[j] in "01234567":
                    j += 1
                b.append(int(s[i + 1 : j], 8))
                i = j
                continue
            if n == "x":
                b.append(int(s[i + 2 : i + 4], 16))
                i += 4
                continue
            b.extend({"n": b"\n", "t": b"\t", "\\": b"\\", '"': b'"'}.get(n, n.encode()))
            i += 2
            continue
        b.extend(ch.encode())
        i += 1
    return b.decode("utf-8", "surrogateescape")


def fd_path(arg):
    m = re.search(r"<(.*)>$", arg)
    return m.group(1) if m else None


def resolve(dir_arg, path_arg):
    p = unescape(path_arg)
    if p.startswith("/"):
        return os.path.normpath(p)
    base = fd_path(dir_arg)
    return os.path.normpath(os.path.join(base, p)) if base else None


def calls(text):
    pending = {}
    for raw in text.splitlines():
        m = LINE.match(raw)
        if not m:
            continue
        pid, rest = m.groups()
        if rest.endswith("<unfinished ...>"):
            pending[pid] = rest[: -len("<unfinished ...>")].rstrip()
            continue
        r = re.match(r"^<\.\.\. (\w+) resumed>(.*)$", rest)
        if r:
            rest = pending.pop(pid, r.group(1) + "(") + r.group(2)
        c = re.match(r"^(\w+)\((.*)\)\s+=\s+(.*)$", rest)
        if c:
            yield c.group(1), split_args(c.group(2)), c.group(3)


def inside(p, root):
    return p is not None and (p == root or p.startswith(root.rstrip("/") + "/"))


class World:
    def __init__(self, pre):
        self.pre = set(pre)
        self.name = {}
        self.file = {}
        self.events = {}
        self.dir_syncs = {}

    def new_file(self, origin):
        k = len(self.file)
        self.file[k] = {"origin": origin, "w": None, "s": None}
        return k

    def at(self, p):
        # A name the run did not create is taken as there before it: the trace cannot say otherwise.
        if p not in self.name:
            self.name[p] = self.new_file(p)
        return self.name[p]

    def point(self, p, f, n):
        self.events.setdefault(p, []).append((n, f))
        if f is None:
            self.name.pop(p, None)
        else:
            self.name[p] = f

    def content(self, f):
        rec = self.file[f]
        if rec["w"] is None:
            return "as before"
        if rec["s"] is not None and rec["s"] > rec["w"]:
            return "as written"
        if rec["s"] is None:
            return "as before" if rec["origin"] else "empty"
        return "part written"

    def state(self, f, crashed):
        if f is None:
            return None
        rec = self.file[f]
        who = rec["origin"] or ("new", f)
        if crashed:
            return (who, self.content(f))
        return (who, "as before" if rec["w"] is None else "as written")

    def outcome(self, root):
        touched = set(self.events)
        touched |= {p for p, f in self.name.items() if self.file[f]["w"] is not None}
        old = new = neither = 0
        for p in sorted(touched):
            if not inside(p, root) or p == root:
                continue
            before = (p, "as before") if p in self.pre else None
            after = self.state(self.name.get(p), False)
            durable = [f for n, f in self.events.get(p, []) if self.dir_syncs.get(os.path.dirname(p), -1) > n]
            if durable:
                crash = self.state(durable[-1], True)
            elif p in self.pre:
                f = self.name.get(p) if p not in self.events else None
                crash = self.state(f, True) if f is not None else before
            else:
                crash = None
            if before == after == crash:
                continue
            if crash == before:
                old += 1
            elif crash == after:
                new += 1
            else:
                neither += 1
        if old + new + neither == 0:
            return "no change", old, new, neither
        if neither:
            return "neither old nor new", old, new, neither
        if old and new:
            return "old and new mixed", old, new, neither
        return ("all lost" if old else "all kept"), old, new, neither


def judge(text, root, pre=()):
    w = World(pre)
    renames, b_named, b_unjudged, seen = 0, [], 0, set()

    def wrote(p, n):
        if p is not None:
            w.file[w.at(p)]["w"] = n

    for n, (name, a, ret) in enumerate(calls(text)):
        if ret.startswith("-1") or ret.startswith("?"):
            continue
        if name in WRITE_FD0 and a:
            wrote(fd_path(a[0]), n)
        elif name == "copy_file_range" and len(a) > 2:
            wrote(fd_path(a[2]), n)
        elif name == "truncate" and a:
            p = unescape(a[0])
            wrote(os.path.normpath(p) if p.startswith("/") else None, n)
        elif name in ("openat", "openat2") and len(a) > 2:
            p = fd_path(ret) or resolve(a[0], a[1])
            flags = a[2]
            if p is None:
                continue
            if "O_CREAT" in flags and p not in w.name and p not in w.pre:
                w.point(p, w.new_file(None), n)
            if "O_TRUNC" in flags and "O_RDONLY" not in flags:
                wrote(p, n)
        elif name in SYNC and a:
            p = fd_path(a[0])
            if p is not None:
                if p in w.name:
                    w.file[w.name[p]]["s"] = n
                w.dir_syncs[p] = n
        elif name in ("renameat", "renameat2") and len(a) > 3:
            src, dst = resolve(a[0], a[1]), resolve(a[2], a[3])
            if src is None or dst is None:
                continue
            f = w.at(src)
            rec = w.file[f]
            if inside(dst, root) and dst != root:
                renames += 1
                if rec["w"] is None:
                    b_unjudged += 1
                elif rec["s"] is None or rec["s"] < rec["w"]:
                    b_named.append(os.path.relpath(dst, root))
            w.point(src, None, n)
            w.point(dst, f, n)
        elif name in ("unlinkat", "mkdirat") and len(a) > 1:
            p = resolve(a[0], a[1])
            if p:
                w.point(p, None if name == "unlinkat" else w.new_file(None), n)
        elif name == "linkat" and len(a) > 3:
            src, dst = resolve(a[0], a[1]), resolve(a[2], a[3])
            if src and dst:
                w.point(dst, w.at(src), n)
        elif name == "symlinkat" and len(a) > 2:
            p = resolve(a[1], a[2])
            if p:
                w.point(p, w.new_file(None), n)
        elif name in SEEN_ONLY:
            seen.add(name)

    a_rule, old, new, neither = w.outcome(root)
    return {
        "renames_into_state": renames,
        "b_named": sorted(set(b_named)),
        "b_unjudged": b_unjudged,
        "a_rule": a_rule,
        "a_names_old": old,
        "a_names_new": new,
        "a_names_neither": neither,
        "seen_not_applied": sorted(seen),
    }


def read_kv(d, f):
    out = {}
    p = os.path.join(d, f)
    if os.path.exists(p):
        for line in open(p):
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                out[k] = v
    return out


def table(tdir):
    rows, bad = [], []
    for t in sorted(os.listdir(tdir)):
        d = os.path.join(tdir, t)
        tr = os.path.join(d, "trace.strace")
        if not os.path.isfile(tr):
            continue
        m = {**read_kv(d, "meta.txt"), **read_kv(d, "op.exit")}
        pre_file = os.path.join(d, "pre.txt")
        if "state" not in m or not os.path.exists(pre_file):
            bad.append(t)
            continue
        root = m["state"]
        pre = [os.path.normpath(os.path.join(root, line.strip())) for line in open(pre_file) if line.strip()]
        r = judge(open(tr, encoding="utf-8", errors="surrogateescape").read(), root, pre)
        r.update({"name": t, "marker": m.get("marker"), "exit": m.get("exit")})
        rows.append(r)
    return rows, bad


def tr(*lines):
    return "".join("7 " + line + "\n" for line in lines)


CREATE_TMP = 'openat(AT_FDCWD</s>, "k.tmp", O_WRONLY|O_CREAT|O_TRUNC, 0666) = 3</s/k.tmp>'
WRITE_TMP = 'write(3</s/k.tmp>, "x", 1) = 1'
RENAME = 'renameat(AT_FDCWD</s>, "k.tmp", AT_FDCWD</s>, "k") = 0'

SELF = {
    "rename with no sync": (
        tr(CREATE_TMP, WRITE_TMP, RENAME), ["/s/k"],
        {"b_named": ["k"], "a_rule": "all lost"},
    ),
    "the file synced, the directory not: the rename is lost, so the new content is reached by no name": (
        tr(CREATE_TMP, WRITE_TMP, "fsync(3</s/k.tmp>) = 0", RENAME), ["/s/k"],
        {"b_named": [], "a_rule": "all lost"},
    ),
    "file and directory synced": (
        tr(CREATE_TMP, WRITE_TMP, "fdatasync(3</s/k.tmp>) = 0", RENAME, "fsync(4</s>) = 0"), ["/s/k"],
        {"b_named": [], "a_rule": "all kept"},
    ),
    "the directory synced between create and rename: a temporary file is left beside the old name": (
        tr(CREATE_TMP, WRITE_TMP, "fsync(3</s/k.tmp>) = 0", "fsync(4</s>) = 0", RENAME), ["/s/k"],
        {"b_named": [], "a_rule": "neither old nor new"},
    ),
    "another file synced instead of the source": (
        tr(WRITE_TMP, 'write(5</s/other>, "y", 1) = 1', "fsync(5</s/other>) = 0", RENAME), ["/s/k", "/s/k.tmp", "/s/other"],
        {"b_named": ["k"], "a_rule": "old and new mixed"},
    ),
    "the source synced only after the rename": (
        tr(WRITE_TMP, RENAME, "fsync(3</s/k>) = 0"), ["/s/k.tmp"],
        {"b_named": ["k"]},
    ),
    "a write after the sync": (
        tr(WRITE_TMP, "fsync(3</s/k.tmp>) = 0", 'write(3</s/k.tmp>, "z", 1) = 1', RENAME), ["/s/k.tmp"],
        {"b_named": ["k"]},
    ),
    "a prefix-sharing name synced": (
        tr('write(3</s/k>, "x", 1) = 1', "fsync(5</s/k.tmp>) = 0", 'renameat(AT_FDCWD</s>, "k", AT_FDCWD</s>, "j") = 0'), ["/s/k", "/s/k.tmp"],
        {"b_named": ["j"]},
    ),
    "a relative path through a subdirectory": (
        tr('write(3</s/sub/k.tmp>, "x", 1) = 1', 'renameat(AT_FDCWD</s>, "sub/k.tmp", AT_FDCWD</s>, "sub/k") = 0'), ["/s/sub", "/s/sub/k.tmp"],
        {"b_named": ["sub/k"]},
    ),
    "a source the run did not write": (
        tr(RENAME), ["/s/k.tmp"],
        {"b_named": [], "b_unjudged": 1},
    ),
    "a rename outside the state": (
        tr('write(3</t/k.tmp>, "x", 1) = 1', 'renameat(AT_FDCWD</t>, "k.tmp", AT_FDCWD</t>, "k") = 0'), [],
        {"renames_into_state": 0, "a_rule": "no change"},
    ),
    "a call split across threads, and a failed rename": (
        tr('write(3</s/k.tmp>, "x", 1 <unfinished ...>', "fsync(4</s/q>) = 0", "<... write resumed>) = 1",
           'renameat(AT_FDCWD</s>, "nope", AT_FDCWD</s>, "n") = -1 ENOENT (No such file or directory)', RENAME), ["/s/k.tmp"],
        {"b_named": ["k"], "renames_into_state": 1},
    ),
    "a file rewritten in place, not synced": (
        tr('openat(AT_FDCWD</s>, "k", O_WRONLY|O_CREAT|O_TRUNC, 0666) = 3</s/k>', 'write(3</s/k>, "x", 1) = 1'), ["/s/k"],
        {"a_rule": "all lost"},
    ),
    "a file rewritten in place and synced": (
        tr('openat(AT_FDCWD</s>, "k", O_WRONLY|O_TRUNC) = 3</s/k>', 'write(3</s/k>, "x", 1) = 1', "fdatasync(3</s/k>) = 0"), ["/s/k"],
        {"a_rule": "all kept"},
    ),
    "two files rewritten in place, one synced": (
        tr('write(3</s/a>, "x", 1) = 1', 'write(4</s/b>, "y", 1) = 1', "fsync(3</s/a>) = 0"), ["/s/a", "/s/b"],
        {"a_rule": "old and new mixed"},
    ),
}


def selftest():
    fails = 0
    for name, (trace, pre, want) in SELF.items():
        got = judge(trace, "/s", pre)
        for k, v in want.items():
            if got[k] != v:
                print("FAIL %s: %s is %r, want %r" % (name, k, got[k], v))
                fails += 1
    print("selftest: %d case(s), %d failure(s)" % (len(SELF), fails))
    return 1 if fails else 0


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if len(argv) != 1 or not os.path.isdir(argv[0]):
        print(__doc__)
        return 2
    rows, bad = table(argv[0])
    print("| define | renames into state | (b) named | (b) unjudged | (a) | names: old / new / neither | marker | exit |")
    print("|---|---|---|---|---|---|---|---|")
    for r in rows:
        print("| %s | %d | %s | %d | %s | %d / %d / %d | %s | %s |" % (
            r["name"], r["renames_into_state"], ", ".join("`%s`" % x for x in r["b_named"]) or "—",
            r["b_unjudged"], r["a_rule"], r["a_names_old"], r["a_names_new"], r["a_names_neither"], r["marker"], r["exit"]))
    json.dump(rows, open(os.path.join(argv[0], "table.json"), "w"), indent=1)
    for t in bad:
        print("FAIL %s: no meta.txt or pre.txt — not recorded whole" % t)
    return 2 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
