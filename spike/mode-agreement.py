#!/usr/bin/env python3
"""Hold the three observation modes to one account of the same toy.

    mode-agreement.py show STATE TRACE
    mode-agreement.py validate TABLE TOY...
    mode-agreement.py compare TABLE TOY ARCH STATE EXPECT MODE=TRACE MODE=TRACE [MODE=TRACE]

`compare` requires EXPECT (a record the toy exists to produce, or `-`) in the first mode's
account, diffs every other mode's account against it, and fails on any difference the
table does not allow and on any table row, for a pair and CPU it ran, that did not occur.
`validate` fails on a row naming a toy, a mode, a CPU or a side the check does not run.
"""
import difflib
import os
import struct
import sys

MAGIC = b"SIDEEYE1"
KILL_POINTS = {1: "open", 2: "write", 3: "rename", 4: "unlink", 5: "fsync", 6: "truncate",
               7: "mkdir", 8: "rmdir", 9: "link", 10: "symlink"}
BOUNDARIES = {200: "fork", 201: "exec", 202: "thread", 203: "spawn", 204: "detached"}
PLACEMENT = {902: "unresolved", 903: "unsupported"}
# Not compared, and named rather than left to fall through: an op the contract gains that one
# mode records would otherwise vanish from both accounts and read as agreement.
NOT_COMPARED = {100, 205, 206, 207, 900, 901, 904}
TWO_PATHS = {"rename", "link"}
COLUMNS = ("base", "mode", "arch", "toy", "side", "record", "why")


def records(path):
    b = open(path, "rb").read()
    if b[:len(MAGIC)] != MAGIC:
        raise SystemExit(f"{path}: not a Sideeye trace")
    i = len(MAGIC) + 4
    while i < len(b):
        if i + 22 > len(b):
            raise SystemExit(f"{path}: truncated record at byte {i}")
        op, _seq, pid, _tid, plen = struct.unpack_from("<HIIQI", b, i)
        p = b[i + 22:i + 22 + plen]
        i += 22 + plen
        if i + 4 > len(b):
            raise SystemExit(f"{path}: truncated record at byte {i}")
        (alen,) = struct.unpack_from("<I", b, i)
        a = b[i + 4:i + 4 + alen]
        i += 4 + alen
        if i > len(b):
            raise SystemExit(f"{path}: truncated record at byte {i}")
        yield op, pid, p.decode("utf-8", "replace"), a.decode("utf-8", "replace")


def relative(p, roots):
    if not p:
        return ""
    for r in roots:
        if p == r:
            return "S"
        if p.startswith(r + "/"):
            return "S/" + p[len(r) + 1:]
    return "<outside>"


def account(state, trace):
    roots = sorted({state.rstrip("/"), os.path.realpath(state)}, key=len, reverse=True)
    ordinal, lines = {}, []
    for op, pid, p, a in records(trace):
        if op in NOT_COMPARED:
            continue
        name = KILL_POINTS.get(op) or BOUNDARIES.get(op) or PLACEMENT.get(op)
        if name is None:
            raise SystemExit(f"{trace}: op {op} is neither compared nor named as not compared")
        n = ordinal.setdefault(pid, len(ordinal) + 1)
        if name == "exec":
            p, a = "", ""
        elif name in TWO_PATHS:
            p, a = relative(p, roots), relative(a, roots)
        elif name in PLACEMENT.values():
            p = relative(p, roots)
        else:
            p, a = relative(p, roots), ""
        lines.append((n, f"p{n} {name} {p} {a}".rstrip()))
    lines.sort(key=lambda x: x[0])
    return [line for _, line in lines]


def load_table(path):
    rows = []
    for raw in open(path, encoding="utf-8"):
        if not raw.strip() or raw.startswith("#"):
            continue
        cols = raw.rstrip("\n").split("\t")
        if len(cols) != len(COLUMNS):
            raise SystemExit(f"{path}: a row needs {len(COLUMNS)} tab-separated columns: {raw!r}")
        rows.append(dict(zip(COLUMNS, cols)))
    return rows


def validate(table, toys):
    bad = 0
    for r in load_table(table):
        problems = []
        if r["base"] != "wrappers":
            problems.append("its base is not wrappers, the mode every other is compared against")
        if r["mode"] not in ("syscalls", "supervised"):
            problems.append(f"no mode {r['mode']!r} is compared")
        if r["arch"] not in ("any", "x86_64", "aarch64"):
            problems.append(f"no CPU {r['arch']!r}")
        if r["toy"] not in toys:
            problems.append(f"no toy {r['toy']!r} is run")
        if r["side"] not in ("base", "mode"):
            problems.append(f"side {r['side']!r} is neither base nor mode")
        for problem in problems:
            print(f"FAIL mode-agreement.tsv row {r['record']!r}: {problem}, so it would never be judged")
            bad += 1
    if not bad:
        print("ok   every row of mode-agreement.tsv names a toy, a mode, a CPU and a side the check runs")
    return bad


def compare(table, toy, arch, state, expect, pairs):
    rows = load_table(table)
    modes = [p.split("=", 1) for p in pairs]
    base_mode, base_trace = modes[0]
    base = account(state, base_trace)
    total = 0
    if expect != "-" and not any(expect in line for line in base):
        print(f"FAIL {toy}: no {expect!r} in the {base_mode} account, so the toy did not do what this leg compares")
        return 1
    for mode, trace in modes[1:]:
        bad = 0
        other = account(state, trace)
        diff = [d for d in difflib.ndiff(base, other) if d[:1] in "+-"]
        unused = [r for r in rows if r["base"] == base_mode and r["mode"] == mode
                  and r["toy"] == toy and r["arch"] in ("any", arch)]
        for d in diff:
            side = "base" if d[0] == "-" else "mode"
            match = next((r for r in unused if r["side"] == side and r["record"] == d[2:]), None)
            if match is not None:
                unused.remove(match)
                continue
            print(f"FAIL {toy}: {base_mode} and {mode} disagree ({arch}): only under "
                  f"{base_mode if side == 'base' else mode}: {d[2:]}")
            bad += 1
        for r in unused:
            where = base_mode if r["side"] == "base" else mode
            print(f"FAIL {toy}: the table allows {r['record']!r} only under {where} "
                  f"({base_mode} vs {mode}, {r['arch']}), and it did not occur: a stale row")
            bad += 1
        if not bad:
            how = "keep the same account" if not diff else "differ only as the table allows"
            print(f"ok   {toy}: {base_mode} and {mode} {how} ({len(base)} records, {arch})")
        total += bad
    return total


def main(argv):
    if len(argv) == 4 and argv[1] == "show":
        print("\n".join(account(argv[2], argv[3])))
        return 0
    if len(argv) >= 4 and argv[1] == "validate":
        return 1 if validate(argv[2], set(argv[3:])) else 0
    if len(argv) >= 9 and argv[1] == "compare":
        return 1 if compare(argv[2], argv[3], argv[4], argv[5], argv[6], argv[7:]) else 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
