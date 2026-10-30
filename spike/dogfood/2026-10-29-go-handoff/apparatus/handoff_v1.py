"""Whether two thread ids of one process write the judged state in turn, and the same way every run (#987).

Reads `strace -f -ttt -T -y` captures of a target run without Sideeye. A *write* is what #687's
`order.py` counts (its `written_paths`: opens for writing, `FD_WRITES`, `PATH_CALLS`), under the state,
failed calls included, a call a signal took back excluded. A *hand-over* is two consecutive writes of
one process by two thread ids.

- Q1: a hand-over *overlaps* when the earlier write had not returned (its start plus `-T`) when the
  later one started.
- Q2: the runs' sequences of writes — call, paths (runs of six or more digits folded), explicit offset,
  return, and a sha256 of the bytes written when the capture carries them — compared across runs. A
  path the define declares scratch is compared by call, name and return only. A run differs by
  *sequence* when anything but the bytes differs; by *order* when only the bytes differ and each
  differing write's bytes are some other write's of the same shape in the first run (two writes traded
  places); by *content* otherwise (bytes no other run wrote there: a clock, a random id).
- Q3, described only: what the earlier thread did next after its write, and whether it had started
  that call before the later thread's write started.

A capture in which no write is read is an error, never "no hand-over": a reader that cannot parse the
format reads nothing, and nothing must not pass for a measurement.

    python3 handoff.py run <capture> <state> [scratch,...]          one capture, one line of JSON
    python3 handoff.py judge <state> <scratch,...|-> <arm1 dir> <arm2 dir>   the target's result
    python3 handoff.py --selftest
"""
import collections
import hashlib
import importlib.util
import json
import os
import re
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "order", os.path.join(_here, "..", "..", "2026-10-10-thread-order", "apparatus", "order.py"))
order = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(order)

LINE = re.compile(r"^(\d+)\s+(\d+\.\d+)\s+(.*)$")
DURATION = re.compile(r"\s<(\d+\.\d+)>$")
DATA_WRITES = ("write", "pwrite64", "writev", "pwritev", "pwritev2")
OFFSET_LAST = ("pwrite64", "pwritev", "pwritev2")
DIGITS = re.compile(r"\d{6,}")


class ReadNothing(Exception):
    pass


def calls(lines):
    """(start, end, tid, name, args, ret, ann, kind, index). `end` is None when the call never
    returned or carried no `-T`."""
    pending = {}
    out = []
    for idx, raw in enumerate(lines):
        m = LINE.match(raw.rstrip("\n"))
        if not m:
            continue
        tid, t, body = int(m.group(1)), float(m.group(2)), m.group(3)
        if body.startswith("+++ exited") or body.startswith("+++ killed"):
            out.append((t, t, tid, "+++", "", None, None, "exit", idx))
            continue
        if body.startswith("---"):
            continue
        d = DURATION.search(body)
        r = order.RESUMED.match(body)
        if r:
            if tid in pending:
                start, sidx, name, head = pending.pop(tid)
                full = head + r.group(2)
                rm = order.RET.search(full)
                out.append((start, start + float(d.group(1)) if d else None, tid, name, full,
                            rm.group(1) if rm else None, rm.group(2) if rm else None, "call", sidx))
            continue
        c = order.CALL.match(body)
        if not c:
            continue
        name, rest = c.group(1), c.group(2)
        if rest.endswith("<unfinished ...>"):
            pending[tid] = (t, idx, name, rest[: -len("<unfinished ...>")])
            continue
        rm = order.RET.search(rest)
        out.append((t, t + float(d.group(1)) if d else None, tid, name, rest,
                    rm.group(1) if rm else None, rm.group(2) if rm else None, "call", idx))
    for tid, (start, sidx, name, head) in pending.items():
        out.append((start, None, tid, name, head, None, None, "call", sidx))
    out.sort(key=lambda e: (e[0], e[8]))
    return out


def unescape(s):
    out = bytearray()
    i = 0
    simple = {"n": 10, "t": 9, "r": 13, "v": 11, "f": 12, "\\": 92, '"': 34, "0": 0}
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            if s[i + 1] == "x" and i + 3 < len(s) + 1:
                out.append(int(s[i + 2:i + 4], 16))
                i += 4
                continue
            out.append(simple.get(s[i + 1], ord(s[i + 1]) & 0xFF))
            i += 2
            continue
        out.append(ord(s[i]) & 0xFF)
        i += 1
    return bytes(out)


def shape_of(name, args, ret, paths, state, scratch):
    head = args[: order.RET.search(args).start()] if order.RET.search(args) else args
    in_scratch = any(p and any(order.under(p, state.rstrip("/") + "/" + s) for s in scratch) for p in paths)
    rel = tuple(DIGITS.sub("#", p[len(state):] if p and p.startswith(state) else (p or "?")) for p in paths)
    offset = head.rsplit(", ", 1)[-1].strip() if name in OFFSET_LAST and not in_scratch else None
    digest = None
    if name in DATA_WRITES and not in_scratch:
        strs = order.STR.findall(head)
        if strs:
            h = hashlib.sha256(b"".join(unescape(x) for x in strs)).hexdigest()[:16]
            digest = h + ("+trunc" if '"...' in head else "")
    return (name, rel, offset, ret), digest


def run(lines, state, scratch=()):
    state = state.rstrip("/")
    tgid = {}
    writes = []
    by_tid = collections.defaultdict(list)
    for start, end, tid, name, args, ret, ann, kind, idx in calls(lines):
        tgid.setdefault(tid, tid)
        by_tid[tid].append((start, name))
        if kind == "exit":
            continue
        if name in ("clone", "clone3") and ret and ret.isdigit() and "CLONE_THREAD" in args:
            tgid[int(ret)] = tgid[tid]
            continue
        if ret == "?" and "ERESTART" in args:
            continue
        paths = order.written_paths(name, args, ann)
        if paths and any(order.under(p, state) for p in paths):
            shape, digest = shape_of(name, args, ret, paths, state, scratch)
            writes.append({"start": start, "end": end, "tid": tid, "shape": shape, "digest": digest})
    if not writes:
        raise ReadNothing("no write under %s was read" % state)
    handovers = overlaps = 0
    q3 = collections.Counter()
    next_before = 0
    by_proc = collections.defaultdict(list)
    for w in writes:
        by_proc[tgid.get(w["tid"], w["tid"])].append(w)
    for ws in by_proc.values():
        for a, b in zip(ws, ws[1:]):
            if a["tid"] == b["tid"]:
                continue
            handovers += 1
            if a["end"] is None or a["end"] > b["start"]:
                overlaps += 1
            after = [(s, n) for s, n in by_tid[a["tid"]] if s > a["start"]]
            nxt = after[0] if after else (None, "(none)")
            q3[nxt[1]] += 1
            if nxt[0] is not None and nxt[0] < b["start"]:
                next_before += 1
    return {"writes": len(writes), "handovers": handovers, "overlaps": overlaps,
            "writer_tids": len({w["tid"] for w in writes}),
            "q3_next_call": dict(q3.most_common(6)), "q3_next_call_before_later_write": next_before,
            "sequence": [[list(w["shape"][:1]) + [list(w["shape"][1])] + list(w["shape"][2:]), w["digest"]] for w in writes]}


def freeze(seq):
    return [((s[0], tuple(s[1]), s[2], s[3]), d) for s, d in seq]


def compare(seqs):
    """'same', 'content', 'order' or 'sequence' — the worst over runs 2.. against run 1."""
    rank = {"same": 0, "content": 1, "order": 2, "sequence": 3}
    first = freeze(seqs[0])
    worst = "same"
    for other in seqs[1:]:
        o = freeze(other)
        if [s for s, _ in o] != [s for s, _ in first]:
            kind = "sequence"
        elif o == first:
            kind = "same"
        else:
            kind = "content"
            for i, ((s, d), (_, d1)) in enumerate(zip(o, first)):
                if d != d1 and any(j != i and s1 == s and dd == d for j, (s1, dd) in enumerate(first)):
                    kind = "order"
                    break
        if rank[kind] > rank[worst]:
            worst = kind
    return worst


def judge(arm1, arm2, _mode="normal"):
    """arm1, arm2: lists of `run` results. 'pass', 'fail' or 'unmeasured', and why."""
    with_handover = [r for r in arm1 if r["handovers"] > 0]
    q2 = compare([r["sequence"] for r in arm2]) if len(arm2) > 1 else "unmeasured"
    overlaps = sum(r["overlaps"] for r in with_handover)
    if _mode == "always_pass":
        return "pass", {}
    if _mode == "always_fail":
        return "fail", {}
    why = {"arm1_runs_with_handover": len(with_handover), "arm1_handovers": sum(r["handovers"] for r in arm1),
           "arm2_handovers": sum(r["handovers"] for r in arm2), "overlaps": overlaps, "q2": q2}
    if not with_handover:
        return "unmeasured", why
    if overlaps:
        return "fail", why
    if _mode != "no_q2" and q2 in ("sequence", "order", "unmeasured"):
        return "fail", why
    return "pass", why


def _w(tid, t, call, dur):
    return f"{tid} {t:.6f} {call} <{dur:.6f}>\n"


SPAWN = "10 0.900000 clone(child_stack=0x4000, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM) = 11 <0.000010>\n"


CLEAN = (SPAWN + _w(10, 1.000, 'pwrite64(3</s/db>, "aaaa", 4, 0) = 4', 0.001)
         + "10 1.001500 futex(0x4000, FUTEX_WAIT_PRIVATE, 0, NULL <unfinished ...>\n"
         + _w(11, 1.002, 'pwrite64(3</s/db>, "bbbb", 4, 4) = 4', 0.001)
         + _w(11, 1.004, 'renameat(AT_FDCWD</s>, "db.tmp.2923683176", AT_FDCWD</s>, "db") = 0', 0.0001))
OVERLAP = (SPAWN + "10 1.000000 pwrite64(3</s/db>, \"aaaa\", 4, 0 <unfinished ...>\n"
           + _w(11, 1.002, 'pwrite64(3</s/db>, "bbbb", 4, 4) = 4', 0.0001)
           + "10 1.005000 <... pwrite64 resumed>) = 4 <0.005000>\n")
SWAPPED = (SPAWN + _w(11, 1.000, 'pwrite64(3</s/db>, "bbbb", 4, 4) = 4', 0.001)
           + _w(10, 1.002, 'pwrite64(3</s/db>, "aaaa", 4, 0) = 4', 0.001))
RACE_A = (SPAWN + _w(10, 1.000, 'pwrite64(3</s/r>, "AAAAAAAA", 8, 0) = 8', 0.0001)
          + _w(11, 1.001, 'pwrite64(3</s/r>, "BBBBBBBB", 8, 0) = 8', 0.0001))
RACE_B = (SPAWN + _w(11, 1.000, 'pwrite64(3</s/r>, "BBBBBBBB", 8, 0) = 8', 0.0001)
          + _w(10, 1.001, 'pwrite64(3</s/r>, "AAAAAAAA", 8, 0) = 8', 0.0001))
CLOCK = CLEAN.replace('"bbbb"', '"bbbc"')
OTHER_PATH = CLEAN.replace('"db.tmp.2923683176", AT_FDCWD</s>, "db"', '"db.tmp.2923683176", AT_FDCWD</s>, "db2"')
RANDOM_NAME = CLEAN.replace("2923683176", "1187340021")
SCRATCH_CLOCK = (SPAWN + _w(10, 1.000, 'pwrite64(3</s/grafana.db>, "t=1", 3, 0) = 3', 0.001)
                 + _w(11, 1.002, 'pwrite64(4</s/journal>, "jj", 2, 0) = 2', 0.001))
ONE_WRITER = _w(10, 1.000, 'write(3</s/a>, "x", 1) = 1', 0.001) + _w(10, 1.002, 'fsync(3</s/a>) = 0', 0.001)
TT_FORMAT = '10 12:00:00.000001 pwrite64(3</s/db>, "aaaa", 4, 0) = 4\n'
REAL_GO = (  # lab-s1-writers.txt's etcd shape, in the -ttt -T -y form strace 6 prints
    "2799  1793266600.500000 clone(child_stack=0x40003b8000, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS) = 2803 <0.000031>\n"
    "2799  1793266601.123456 pwrite64(7</s/etcd/member/snap/db.tmp.2923683176>, \"\\x00\\x01\"..., 4096, 8192) = 4096 <0.000041>\n"
    "2799  1793266601.123600 futex(0x40000a2148, FUTEX_WAKE_PRIVATE, 1) = 1 <0.000012>\n"
    "2803  1793266601.123700 pwrite64(7</s/etcd/member/snap/db.tmp.2923683176>, \"\\x00\\x02\"..., 4096, 12288) = 4096 <0.000039>\n"
    "2803  1793266601.124000 renameat(AT_FDCWD</s/etcd>, \"member/snap/db.tmp.2923683176\", AT_FDCWD</s/etcd>, \"member/snap/db\") = 0 <0.000020>\n")


def selftest():
    bad = 0

    def check(label, got, want):
        nonlocal bad
        print(f"{'ok  ' if got == want else 'FAIL'} {label}: {got} (wanted {want})")
        bad += got != want

    def r(text, state="/s", scratch=()):
        return run(text.splitlines(True), state, scratch)

    check("clean hand-over: overlaps", (r(CLEAN)["handovers"], r(CLEAN)["overlaps"]), (1, 0))
    check("a write still running when the other starts", r(OVERLAP)["overlaps"], 1)
    check("the real -ttt -T -y lines are read", (r(REAL_GO, "/s/etcd/member/snap")["writes"], r(REAL_GO, "/s/etcd/member/snap")["handovers"]), (3, 1))
    check("Q3 sees the earlier thread in futex before the later write", r(REAL_GO, "/s/etcd/member/snap")["q3_next_call_before_later_write"], 1)
    try:
        r(TT_FORMAT)
        check("a capture in another time format", "read", "error")
    except ReadNothing:
        check("a capture in another time format", "error", "error")
    seq = lambda t, s=(): r(t, "/s", s)["sequence"]
    check("two identical runs", compare([seq(CLEAN), seq(CLEAN)]), "same")
    check("a random name in a temporary", compare([seq(CLEAN), seq(RANDOM_NAME)]), "same")
    check("two writes traded places", compare([seq(CLEAN), seq(SWAPPED + CLEAN.split("\n", 4)[4])]), "sequence")
    check("same shape, bytes traded", compare([seq(RACE_A), seq(RACE_B)]), "order")
    check("new bytes (a clock)", compare([seq(CLEAN), seq(CLOCK)]), "content")
    check("another path", compare([seq(CLEAN), seq(OTHER_PATH)]), "sequence")
    check("a clock in a scratch file", compare([seq(SCRATCH_CLOCK, ("grafana.db",)), seq(SCRATCH_CLOCK.replace("t=1", "t=2"), ("grafana.db",))]), "same")
    J = lambda a, b, **k: judge([r(x) for x in a], [r(x) for x in b], **k)[0]
    cases = {
        "clean": (([CLEAN] * 3, [CLEAN] * 3), "pass"),
        "overlap": (([OVERLAP] * 3, [CLEAN] * 3), "fail"),
        "race": (([RACE_A, RACE_B, RACE_A], [RACE_A, RACE_B, RACE_A]), "fail"),
        "clock": (([CLEAN] * 3, [CLEAN, CLOCK, CLEAN]), "pass"),
        "one writer": (([ONE_WRITER] * 3, [ONE_WRITER] * 3), "unmeasured"),
    }
    for name, ((a, b), want) in cases.items():
        check(f"judge {name}", J(a, b), want)
    for label, mode, case, broken in (("always pass", "always_pass", "overlap", "pass"),
                                      ("always fail", "always_fail", "clean", "fail"),
                                      ("Q2 unread", "no_q2", "race", "pass")):
        (a, b), want = cases[case]
        got = J(a, b, _mode=mode)
        print(f"{'ok  ' if got != want else 'FAIL'} a reader that reads '{label}' reads {case} as {got}, not {want} (the case catches it)")
        bad += got == want
    return bad


def load(d, state, scratch):
    out = []
    for f in sorted(os.listdir(d)):
        if f.endswith(".strace"):
            with open(os.path.join(d, f), errors="replace") as fh:
                try:
                    out.append(run(fh.readlines(), state, scratch))
                except ReadNothing as e:
                    sys.exit(f"{d}/{f}: {e}")
    return out


if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["--selftest"]:
        sys.exit(1 if selftest() else 0)
    if len(a) in (3, 4) and a[0] == "run":
        with open(a[1], errors="replace") as f:
            try:
                res = run(f.readlines(), a[2], tuple(x for x in (a[3] if len(a) > 3 else "").split(",") if x))
            except ReadNothing as e:
                sys.exit(f"{a[1]}: {e}")
        res.pop("sequence")
        print(json.dumps(res))
    elif len(a) == 5 and a[0] == "judge":
        sc = tuple(x for x in a[2].split(",") if x and x != "-")
        arm1, arm2 = load(a[3], a[1], sc), load(a[4], a[1], sc)
        result, why = judge(arm1, arm2)
        why.update({"result": result, "arm1_runs": len(arm1), "arm2_runs": len(arm2),
                    "q3_next_call": dict(sum((collections.Counter(r["q3_next_call"]) for r in arm1), collections.Counter())),
                    "q3_next_call_before_later_write": sum(r["q3_next_call_before_later_write"] for r in arm1)})
        print(json.dumps(why))
    else:
        sys.exit(__doc__)
