#!/usr/bin/env python3
"""#558: whether joplin's writing threads take turns, read from `strace -f -y -ttt -T` captures.

usage:
  turns.py run <capture> <state dir> --joplin-rc N   one run -> JSON on stdout
  turns.py aggregate <run.json>...                   the valid runs -> the readings and the branch
  turns.py pairs <state dir> <capture>...            every strong overlap in each capture, and the totals
  turns.py --selftest                                synthetic captures, and the mutations that must break them

A run is valid only if every kill-point call the reader met was read and placed. `unparsed` counts
the lines naming the state directory whose kill-point call could not be read — a first version of
the call pattern skipped 35 of 89 such calls in a real capture without a word — and `unplaced` the
kill-point calls whose path could not be resolved. Both are in every run's JSON.

What counts as an operation is what the shim counts: the kill-point classes of `OpClass`
(src/contract.zig), with an open counted when `openIsWriteCapable` (shim/src/common.zig) would
count it, and **failed attempts included** — the shim records before it calls, and the engine
counts a writer whether or not its call succeeded (src/engine/trace.zig).

Threads are named by the order the subject process created them (t0 is the main thread), and
every comparison across runs strips the names: libuv hands a task to whichever pool thread is
free, so the same order of operations can arrive on different threads.

An operation is an interval [start, end]: the entry time strace printed plus the duration -T
printed. For a call split across `<unfinished ...>` and `<... resumed>`, the start is the
unfinished half's time.

The readings, fixed before any run was read (plan 2026-09-13-sideeye-joplin-threads-turns-558):
  (m) the multiset of operations — kind, path under the state directory, ok or errno
  (o) among runs with the same multiset, the order of those operations, names stripped
  (g) which operations shared a thread, names stripped (printed for reference)
  (b) strong overlaps: an operation that wholly contains another thread's and lasts at least
      0.5 ms; within LOG or REST only pairs with both sides in the set, across sets only in ALL
  (c) in REST, each change of thread A -> B, and whether A had exited before B's operation
"""
import json
import re
import sys
from collections import Counter

THRESHOLDS = (0.00025, 0.0005, 0.001)
JUDGED = 0.0005

DEFAULT = {
    "join": True,          # join <unfinished ...> with <... resumed>
    "contain": True,       # a strong overlap is containment, not mere intersection
    "threshold": JUDGED,   # the containing operation must last this long
    "strip_names": True,   # compare orders without thread names
    "removedir": True,     # unlinkat(..., AT_REMOVEDIR) is an rmdir
    "keep_failed": True,   # a failed attempt is an operation
    "split_exit": True,    # an exit strace split (`exit(0 <unfinished ...>`) ends its thread
    "unsplit_duration": True,  # an unsplit call ends at its start plus its -T duration
    "log_either_end": True,    # a two-path operation is LOG when either end is log.txt
    "root_only": True,     # only the subject process's threads, not a child process's
    "rc_validity": True,   # a run whose joplin exited non-zero is not valid
    "count_unread": True,  # a kill-point call not read or not placed makes the run invalid
}

LINE = re.compile(r"^(\d+)\s+(\d+\.\d+)\s+(.*)$")
RESUMED = re.compile(r"^<\.\.\. (\w+) resumed>(.*)$")
# `-y` annotates a returned descriptor as well as an argument (`= 17</w/jp/log.txt>`). The
# first version of this pattern did not allow that, and dropped every successful open in a
# real capture — 35 of its 89 kill-point calls under the state directory — while the selftest,
# whose lines had been written without the annotation, stayed green.
CALL = re.compile(
    r"^(\w+)\((.*)\)\s+=\s+(-?\d+|\?|0x[0-9a-fA-F]+)(?:<[^>]*>)?"
    r"(?:\s+([A-Z][A-Z0-9_]*)\b[^<]*)?(?:\s*<(\d+\.\d+)>)?\s*$"
)
FD_PATH = re.compile(r"^\s*-?\d+<([^>]*)>")
DIR_AND_STRING = re.compile(r'(?:(?:AT_FDCWD|-?\d+)<([^>]*)>,\s*)?"((?:[^"\\]|\\.)*)"')
WRITE_CAPABLE = re.compile(r"\bO_(?:WRONLY|RDWR|CREAT|TRUNC)\b")

WRITE_FD0 = {"write", "pwrite64", "writev", "pwritev", "pwritev2", "sendfile"}
FSYNC = {"fsync", "fdatasync"}
KILL_NAMES = WRITE_FD0 | FSYNC | {
    "open", "openat", "openat2", "creat", "ftruncate", "copy_file_range", "truncate", "rename", "renameat",
    "renameat2", "unlinkat", "unlink", "rmdir", "mkdir", "mkdirat", "link", "linkat", "symlink", "symlinkat",
}
NAME = re.compile(r"^(\w+)\(")


def in_scope(path, sd):
    return path is not None and (path == sd or path.startswith(sd + "/"))


def rel(path, sd):
    return "." if path == sd else path[len(sd) + 1:]


def resolve(dirp, p):
    if p.startswith("/"):
        return p
    if dirp:
        return dirp.rstrip("/") + "/" + p
    return None


def classify(name, args, cfg):
    """(kind, [paths]) for a kill-point call, or None. Paths are absolute or None."""
    pairs = [(d, s) for d, s in DIR_AND_STRING.findall(args)]
    paths = [resolve(d, s) for d, s in pairs]
    if name in ("openat", "open"):
        if not pairs or not WRITE_CAPABLE.search(args.split('"')[-1]):
            return None
        return "open", paths[:1]
    if name == "openat2":
        return ("open", paths[:1]) if WRITE_CAPABLE.search(args) else None
    if name == "creat":
        return "open", paths[:1]
    if name in WRITE_FD0 or name in FSYNC or name == "ftruncate":
        m = FD_PATH.match(args)
        kind = "fsync" if name in FSYNC else ("truncate" if name == "ftruncate" else "write")
        return kind, [m.group(1) if m else None]
    if name == "copy_file_range":
        fds = re.findall(r"(-?\d+)<([^>]*)>", args)
        return "write", [fds[1][1] if len(fds) > 1 else None]
    if name == "truncate":
        return "truncate", paths[:1]
    if name in ("rename", "renameat", "renameat2"):
        if name == "renameat2" and re.search(r"RENAME_(?:EXCHANGE|WHITEOUT)", args):
            return None
        return "rename", paths[:2]
    if name == "unlinkat":
        if cfg["removedir"] and "AT_REMOVEDIR" in args:
            return "rmdir", paths[:1]
        return "unlink", paths[:1]
    if name == "unlink":
        return "unlink", paths[:1]
    if name == "rmdir":
        return "rmdir", paths[:1]
    if name in ("mkdir", "mkdirat"):
        return "mkdir", paths[:1]
    if name in ("link", "linkat"):
        return "link", paths[:2]
    if name in ("symlink", "symlinkat"):
        return "symlink", paths[-1:]  # only the link path is the operation's address
    return None


def parse(text, sd, cfg=DEFAULT):
    root = None
    tgid = {}
    rank = {}
    next_rank = {}
    pending = {}
    exits = {}
    io_uring = Counter()
    threads_created = 0
    unparsed = 0
    # Classified only once the whole capture has been read: a new thread's lines can precede
    # the resumption of the clone that names it, and an operation read before that would be
    # taken for another process's and dropped.
    calls = []
    for raw in text.splitlines():
        m = LINE.match(raw)
        if not m:
            continue
        pid, ts, rest = int(m.group(1)), float(m.group(2)), m.group(3)
        if root is None:
            root = pid
            tgid[pid] = pid
            rank[pid] = 0
            next_rank[pid] = 1
        tgid.setdefault(pid, pid)
        start = ts
        split = False
        if rest.endswith("<unfinished ...>"):
            head = rest[: -len("<unfinished ...>")].rstrip()
            # Most exits in a real capture are split this way and never resumed.
            if cfg["split_exit"] and head.startswith(("exit(", "exit_group(")):
                exits.setdefault(pid, ts)
            if cfg["join"]:
                pending[pid] = (ts, head)
            continue
        rm = RESUMED.match(rest)
        if rm:
            if not cfg["join"] or pid not in pending:
                continue
            start, head = pending.pop(pid)
            rest = head + rm.group(2)
            split = True
        cm = CALL.match(rest)
        if not cm:
            nm = NAME.match(rest)
            if nm and nm.group(1) in KILL_NAMES and sd in rest:
                unparsed += 1
            continue
        name, args, ret, errno, dur = cm.groups()
        if name.startswith("io_uring"):
            io_uring[f"{name}={errno or ret}"] += 1
        if name in ("exit", "exit_group"):
            exits.setdefault(pid, start)
            continue
        if ret == "?" or ret.startswith("0x"):
            if ret == "?" and name in KILL_NAMES and sd in args:
                unparsed += 1
            continue
        r = int(ret)
        if name in ("clone", "clone3") and r > 0:
            if "CLONE_THREAD" in args:
                g = tgid[pid]
                tgid[r] = g
                rank[r] = next_rank.get(g, 1)
                next_rank[g] = rank[r] + 1
                if g == root:
                    threads_created += 1
            else:
                tgid[r] = r
                rank[r] = 0
                next_rank[r] = 1
            continue
        calls.append((pid, start, ts, name, args, r, errno, dur, split))
    ops = []
    unplaced = 0
    for pid, start, ts, name, args, r, errno, dur, split in calls:
        if cfg["root_only"] and tgid.get(pid, pid) != root:
            continue
        c = classify(name, args, cfg)
        if c is None:
            continue
        kind, paths = c
        if None in paths:
            unplaced += 1
            continue
        if not any(in_scope(p, sd) for p in paths):
            continue
        if r < 0 and not cfg["keep_failed"]:
            continue
        result = "ok" if r >= 0 else (errno or "err")
        shown = ",".join(rel(p, sd) if in_scope(p, sd) else p for p in paths)
        end = start + float(dur) if dur and (split or cfg["unsplit_duration"]) else ts
        ends = paths if cfg["log_either_end"] else paths[:1]
        is_log = any(in_scope(p, sd) and rel(p, sd) == "log.txt" for p in ends)
        ops.append({
            "start": start, "end": end, "tid": pid, "rank": rank.get(pid, -1),
            "key": f"{kind}({shown})={result}", "set": "log" if is_log else "rest",
        })
    ops.sort(key=lambda o: (o["start"], o["end"]))
    return {"ops": ops, "exits": exits, "io_uring": dict(io_uring), "threads_created": threads_created,
            "unparsed": unparsed, "unplaced": unplaced}


def holds(a, b, cfg):
    """Whether `a` wholly contains `b` (or, under the mutation, merely intersects it)."""
    if cfg["contain"]:
        return a["start"] <= b["start"] and b["end"] <= a["end"]
    return b["start"] < a["end"] and a["start"] < b["end"]


def strong_pairs(ops, cfg, threshold):
    """Ordered pairs where `a` holds another thread's `b` and lasts at least `threshold` — the one
    definition both the counts and `pairs` read."""
    return [(a, b) for i, a in enumerate(ops) for j, b in enumerate(ops)
            if i != j and a["tid"] != b["tid"] and a["end"] - a["start"] >= threshold and holds(a, b, cfg)]


def overlaps(ops, cfg, thresholds=THRESHOLDS):
    """Strong pairs per threshold, and weak ones: an unordered pair of two threads' operations
    that intersect, counted once."""
    strong = {t: len(strong_pairs(ops, cfg, t)) for t in thresholds}
    weak = sum(1 for i, a in enumerate(ops) for b in ops[i + 1:]
               if a["tid"] != b["tid"] and b["start"] < a["end"] and a["start"] < b["end"])
    return strong, weak


def set_readings(ops, cfg, exits=None):
    order = [o["key"] if cfg["strip_names"] else f"t{o['rank']}:{o['key']}" for o in ops]
    by_thread = {}
    for o in ops:
        by_thread.setdefault(o["tid"], []).append(o["key"])
    strong, weak = overlaps(ops, cfg, tuple(sorted(set(THRESHOLDS) | {cfg["threshold"]})))
    out = {
        "ops": len(ops),
        "threads": len(by_thread),
        "multiset": sorted(Counter(o["key"] for o in ops).items()),
        "order": order,
        "grouping": sorted(by_thread.values()),
        "strong": {f"{t * 1000:g}ms": strong[t] for t in THRESHOLDS},
        "strong_judged": strong[cfg["threshold"]],
        "weak": weak,
    }
    if exits is not None:
        turns = after_exit = 0
        for a, b in zip(ops, ops[1:]):
            if a["tid"] != b["tid"]:
                turns += 1
                if a["tid"] in exits and exits[a["tid"]] < b["start"]:
                    after_exit += 1
        out["turns"] = turns
        out["turns_after_exit"] = after_exit
        out["writers_exited_before_last_op"] = sum(
            1 for t in by_thread if t in exits and ops and exits[t] < ops[-1]["start"])
    return out


def readings(parsed, cfg=DEFAULT, joplin_rc=0):
    ops = parsed["ops"]
    log = [o for o in ops if o["set"] == "log"]
    rest = [o for o in ops if o["set"] == "rest"]
    why = []
    if joplin_rc != 0 and cfg["rc_validity"]:
        why.append(f"joplin rc {joplin_rc}")
    if not any(o["key"].startswith("write(database.sqlite-journal)") for o in ops):
        why.append("no write to database.sqlite-journal: the note was not written")
    if (parsed["unparsed"] or parsed["unplaced"]) and cfg["count_unread"]:
        why.append(f"kill-point calls not read: {parsed['unparsed']} unparsed, {parsed['unplaced']} unplaced")
    return {
        "valid": not why,
        "why_invalid": why,
        "joplin_rc": joplin_rc,
        "unparsed": parsed["unparsed"],
        "unplaced": parsed["unplaced"],
        "threads_created": parsed["threads_created"],
        "io_uring": parsed["io_uring"],
        "all": set_readings(ops, cfg),
        "log": set_readings(log, cfg),
        "rest": set_readings(rest, cfg, parsed["exits"]),
    }


def aggregate(runs):
    """The readings over the valid runs, and the branch the plan fixed in advance."""
    valid = [r for r in runs if r["valid"]]
    lines = [f"runs: {len(runs)} given, {len(valid)} valid; kill-point calls not read over all of them: "
             f"{sum(r.get('unparsed', 0) for r in runs)} unparsed, {sum(r.get('unplaced', 0) for r in runs)} unplaced"]
    summary = {}
    for s in ("all", "log", "rest"):
        multisets = Counter(json.dumps(r[s]["multiset"]) for r in valid)
        orders_per_multiset = {}
        for r in valid:
            orders_per_multiset.setdefault(json.dumps(r[s]["multiset"]), set()).add(json.dumps(r[s]["order"]))
        groupings = Counter(json.dumps(r[s]["grouping"]) for r in valid)
        strong_runs = sum(1 for r in valid if r[s]["strong_judged"] > 0)
        summary[s] = {
            "multisets": len(multisets),
            "orders_max_within_a_multiset": max((len(v) for v in orders_per_multiset.values()), default=0),
            "orders_total": sum(len(v) for v in orders_per_multiset.values()),
            "groupings": len(groupings),
            "runs_with_strong_overlap": strong_runs,
        }
        strong_sum = {k: sum(r[s]["strong"][k] for r in valid) for k in valid[0][s]["strong"]} if valid else {}
        ops_counts = sorted(Counter(r[s]["ops"] for r in valid).items())
        lines.append(
            f"{s:4}  (m) {len(multisets)} multiset(s)  (o) at most {summary[s]['orders_max_within_a_multiset']} "
            f"order(s) within one, {summary[s]['orders_total']} in all  (g) {len(groupings)} grouping(s)  "
            f"(b) strong in {strong_runs}/{len(valid)} runs, pairs {strong_sum}  weak pairs "
            f"{sum(r[s]['weak'] for r in valid)}  op counts {ops_counts}  threads "
            f"{sorted(Counter(r[s]['threads'] for r in valid).items())}")
    if valid:
        lines.append(
            f"rest  (c) turns {sum(r['rest']['turns'] for r in valid)}, after the previous thread exited "
            f"{sum(r['rest']['turns_after_exit'] for r in valid)}; writers exited before REST's last operation "
            f"{sum(r['rest']['writers_exited_before_last_op'] for r in valid)}")
        lines.append(f"io_uring lines: {dict(sum((Counter(r['io_uring']) for r in valid), Counter()))}")
    all_simultaneous = summary["all"]["runs_with_strong_overlap"] > 0
    rest_turns = (summary["rest"]["multisets"] == 1 and summary["rest"]["orders_total"] == 1
                  and summary["rest"]["runs_with_strong_overlap"] == 0)
    lines.append("branch: " + ("T1 (ALL: threads write at the same time)" if all_simultaneous
                               else "T1' (ALL: no strong overlap in any run) -> back to the plan"))
    lines.append("branch: " + ("T2 (REST: same operations, same order, no strong overlap)" if rest_turns
                               else "T2' (REST: does not recur the same way)"))
    if all_simultaneous and rest_turns:
        lines.append("both T1 and T2: the logger-off probe (step 6) is required before the #539 question")
    return summary, all_simultaneous, rest_turns, lines


# --- selftest ---------------------------------------------------------------------------------

CLONE = ("{pid} {ts} clone(child_stack=0xffff9a30c940, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|"
         "CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, parent_tid=[{child}], "
         "tls=0xffff9a30d780, child_tidptr=0xffff9a30d130) = {child} <0.000050>")


def cap(*lines):
    head = [CLONE.format(pid=45, ts="1.000000", child=46), CLONE.format(pid=45, ts="1.000100", child=47)]
    return "\n".join(head + list(lines)) + "\n"


# Each line copied in shape from a real capture of `joplin mknote` under `strace -f -y -ttt -T`
# (2026-09-13), including the descriptor annotation `-y` puts on a returned fd: a split rmdir with
# another thread's line inside it, the profile's own mkdir failing, a path that only shares a
# prefix, a read-only open, and a write-capable one.
CASE_A = cap(
    '46 2.000000 unlinkat(AT_FDCWD</w>, "/w/jp/tmp", AT_REMOVEDIR <unfinished ...>',
    '47 2.000010 mkdirat(AT_FDCWD</w>, "/w/jp", 0755) = -1 EEXIST (File exists) <0.000020>',
    '46 2.000030 <... unlinkat resumed>) = 0 <0.000040>',
    '47 2.000100 openat(AT_FDCWD</w>, "/w/jp2/log.txt", O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC, 0666) = 20</w/jp2/log.txt> <0.000030>',
    '46 2.000200 openat(AT_FDCWD</w>, "/w/jp/log.txt", O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC, 0666) = 21</w/jp/log.txt> <0.000030>',
    '47 2.000300 openat(AT_FDCWD</w>, "/w/jp/settings.json", O_RDONLY|O_CLOEXEC) = 22</w/jp/settings.json> <0.000104>',
    '47 2.000400 openat(AT_FDCWD</w>, "/w/jp/database.sqlite", O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC, 0644) = 23</w/jp/database.sqlite> <0.000038>',
)

# Four pairs, one of each shape: a 0.6 ms fsync wholly containing a write (strong); two short
# writes that only intersect (weak); a 0.6 ms fsync that a write starts inside and outlives
# (intersection, not containment); a 0.1 ms write wholly containing another (containment, too
# short to be strong).
CASE_B = cap(
    '46 3.000000 fsync(17</w/jp/database.sqlite-journal> <unfinished ...>',
    '47 3.000100 write(18</w/jp/log.txt>, "x", 1) = 1 <0.000030>',
    '46 3.000600 <... fsync resumed>) = 0 <0.000600>',
    '47 4.000000 write(18</w/jp/log.txt>, "y", 1) = 1 <0.000040>',
    '46 4.000020 write(17</w/jp/database.sqlite-journal>, "z", 1) = 1 <0.000040>',
    '46 5.000000 fsync(17</w/jp/database.sqlite-journal>) = 0 <0.000600>',
    '47 5.000500 write(18</w/jp/log.txt>, "w", 1) = 1 <0.000300>',
    '46 6.000000 write(17</w/jp/database.sqlite-journal>, "v", 1) = 1 <0.000100>',
    '47 6.000020 write(18</w/jp/log.txt>, "u", 1) = 1 <0.000030>',
)

# The same two operations, the threads swapped between two runs.
CASE_C1 = cap(
    '46 7.000000 openat(AT_FDCWD</w>, "/w/jp/database.sqlite", O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC, 0644) = 22</w/jp/database.sqlite> <0.000030>',
    '47 7.100000 write(17</w/jp/database.sqlite-journal>, "j", 1) = 1 <0.000030>',
)
CASE_C2 = cap(
    '47 7.000000 openat(AT_FDCWD</w>, "/w/jp/database.sqlite", O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC, 0644) = 22</w/jp/database.sqlite> <0.000030>',
    '46 7.100000 write(17</w/jp/database.sqlite-journal>, "j", 1) = 1 <0.000030>',
)

# A turn after the previous thread exited, and one before.
CASE_D = cap(
    '46 8.000000 write(17</w/jp/database.sqlite-journal>, "a", 1) = 1 <0.000030>',
    '46 8.100000 exit(0)         = ?',
    '47 8.200000 write(17</w/jp/database.sqlite-journal>, "b", 1) = 1 <0.000030>',
    '46 8.300000 write(17</w/jp/database.sqlite-journal>, "c", 1) = 1 <0.000030>',
)

# The rest of what the reader decides, each added after review found a mutation no case broke
# (2026-09-13): an exit strace split and never resumed, as it prints three of the four writers'
# exits in a real capture; an unsplit fsync whose -T duration alone makes it contain the main
# thread's write.
CASE_E = cap(
    '46 9.000000 write(17</w/jp/database.sqlite-journal>, "a", 1) = 1 <0.000030>',
    '46 9.100000 exit(0 <unfinished ...>',
    '47 9.200000 write(17</w/jp/database.sqlite-journal>, "b", 1) = 1 <0.000030>',
    '47 10.000000 fsync(17</w/jp/database.sqlite-journal>) = 0 <0.000800>',
    '45 10.000100 write(18</w/jp/log.txt>, "c", 1) = 1 <0.000030>',
)

# A rename whose second path is log.txt, and a child process (a clone without CLONE_THREAD)
# writing the journal beside a thread of the subject.
CASE_F = cap(
    '46 11.000000 renameat(AT_FDCWD</w>, "/w/jp/log.tmp", AT_FDCWD</w>, "/w/jp/log.txt") = 0 <0.000030>',
    '45 11.100000 clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, '
    'child_tidptr=0xffff9a30d130) = 60 <0.000100>',
    '60 11.200000 write(17</w/jp/database.sqlite-journal>, "k", 1) = 1 <0.000030>',
    '47 11.300000 write(17</w/jp/database.sqlite-journal>, "j", 1) = 1 <0.000030>',
)

# A write whose line the reader cannot read (what strace prints for a call the process's end cut
# off), and a kill-point call on a relative path with no directory to place it.
CASE_G = cap(
    '47 12.000000 write(17</w/jp/database.sqlite-journal>, "j", 1) = 1 <0.000030>',
    '46 12.100000 write(17</w/jp/database.sqlite-journal>, "q", 1) = ? <unavailable>',
    '46 12.200000 unlinkat(AT_FDCWD, "stray.txt", 0) = 0 <0.000020>',
)


def run_cases(cfg):
    sd = "/w/jp"
    results = []

    def case(label, ok):
        results.append((label, bool(ok)))

    a = readings(parse(CASE_A, sd, cfg), cfg)
    case("A: the split rmdir, the failed mkdir and the two write-capable opens, in order, and nothing else",
         a["all"]["order"] == ["rmdir(tmp)=ok", "mkdir(.)=EEXIST", "open(log.txt)=ok", "open(database.sqlite)=ok"])
    case("A: the open of log.txt is LOG and the other three are REST",
         a["log"]["ops"] == 1 and a["rest"]["ops"] == 3)
    case("A: a run with no journal write is not valid", not a["valid"])

    b = readings(parse(CASE_B, sd, cfg), cfg)
    case("B: exactly one strong overlap at 0.5 ms, in ALL", b["all"]["strong_judged"] == 1)
    case("B: a pair across LOG and REST is not counted inside either set",
         b["log"]["strong_judged"] == 0 and b["rest"]["strong_judged"] == 0)
    case("B: the 0.1 ms containment is strong at no threshold of 0.25 ms or more",
         b["all"]["strong"]["0.25ms"] == 1)
    case("B: a run with a journal write and joplin rc 0 is valid", b["valid"])

    c1 = readings(parse(CASE_C1, sd, cfg), cfg)
    c2 = readings(parse(CASE_C2, sd, cfg), cfg)
    case("C: the same operations on swapped threads are one order",
         c1["all"]["order"] == c2["all"]["order"] and c1["all"]["ops"] == 2)

    d = readings(parse(CASE_D, sd, cfg), cfg)
    case("D: two turns in REST, one of them after the previous thread exited",
         d["rest"]["turns"] == 2 and d["rest"]["turns_after_exit"] == 1)

    e = readings(parse(CASE_E, sd, cfg), cfg)
    case("E: an exit strace split still ends its thread before the next turn",
         e["rest"]["turns"] == 1 and e["rest"]["turns_after_exit"] == 1)
    case("E: an unsplit fsync's own duration makes it contain another thread's write",
         e["all"]["strong_judged"] == 1)

    f = readings(parse(CASE_F, sd, cfg), cfg)
    case("F: a rename onto log.txt is LOG", f["log"]["ops"] == 1)
    case("F: a child process's write is not the subject's", f["rest"]["ops"] == 1)

    g = readings(parse(CASE_G, sd, cfg), cfg)
    case("G: a call not read and a call not placed are counted, and make the run invalid",
         g["unparsed"] == 1 and g["unplaced"] == 1 and not g["valid"])
    case("B: a run whose joplin exited non-zero is not valid",
         not readings(parse(CASE_B, sd, cfg), cfg, joplin_rc=1)["valid"])

    return results


MUTATIONS = {
    "no join of unfinished/resumed": {"join": False},
    "intersection instead of containment": {"contain": False},
    "no duration condition": {"threshold": 0.0},
    "orders compared with thread names": {"strip_names": False},
    "AT_REMOVEDIR not read": {"removedir": False},
    "failed attempts dropped": {"keep_failed": False},
    "a split exit not read": {"split_exit": False},
    "an unsplit call's -T duration ignored": {"unsplit_duration": False},
    "LOG read from the first path only": {"log_either_end": False},
    "other processes' calls kept": {"root_only": False},
    "joplin's exit status ignored": {"rc_validity": False},
    "calls not read or placed ignored": {"count_unread": False},
}


def selftest():
    failures = 0
    print("== the cases, as built")
    for label, ok in run_cases(DEFAULT):
        print(("ok   " if ok else "FAIL ") + label)
        failures += 0 if ok else 1
    print()
    print("== each mutation must break at least one case")
    for name, change in MUTATIONS.items():
        broken = [label for label, ok in run_cases({**DEFAULT, **change}) if not ok]
        if broken:
            print(f"ok   {name}: breaks {len(broken)} — first: {broken[0]}")
        else:
            print(f"FAIL {name}: breaks nothing, so no case measures it")
            failures += 1
    print()
    print("== the branch, on synthetic run readings")

    def fake(strong_all, rest_order, rest_strong=0):
        base = readings(parse(CASE_D, "/w/jp"))
        base["valid"] = True
        base["all"]["strong_judged"] = strong_all
        base["rest"]["order"] = rest_order
        base["rest"]["strong_judged"] = rest_strong
        return base

    for label, runs, want in (
        ("a strong overlap in ALL and REST recurring the same way is T1 and T2",
         [fake(1, ["x"]), fake(0, ["x"])], (True, True)),
        ("REST in two orders is T2'", [fake(1, ["x", "y"]), fake(1, ["y", "x"])], (True, False)),
        ("no strong overlap anywhere is T1'", [fake(0, ["x"]), fake(0, ["x"])], (False, True)),
        ("a strong overlap inside REST is T2'", [fake(1, ["x"], 1), fake(1, ["x"])], (True, False)),
    ):
        _, t1, t2, _ = aggregate(runs)
        ok = (t1, t2) == want
        print(("ok   " if ok else "FAIL ") + label)
        failures += 0 if ok else 1
    print()
    print(f"== selftest failures: {failures}")
    return 1 if failures else 0


def main(argv):
    if argv[1:2] == ["--selftest"]:
        return selftest()
    if argv[1:2] == ["run"] and len(argv) >= 4:
        rc = 0
        if "--joplin-rc" in argv:
            rc = int(argv[argv.index("--joplin-rc") + 1])
        with open(argv[2], errors="replace") as fh:
            text = fh.read()
        json.dump(readings(parse(text, argv[3].rstrip("/")), DEFAULT, rc), sys.stdout)
        sys.stdout.write("\n")
        return 0
    if argv[1:2] == ["pairs"] and len(argv) >= 4:
        sd = argv[2].rstrip("/")
        containing, contained = Counter(), Counter()
        for path in argv[3:]:
            with open(path, errors="replace") as fh:
                found = strong_pairs(parse(fh.read(), sd)["ops"], DEFAULT, JUDGED)
            print(f"{path.rsplit('/', 1)[-1]}: {len(found)} pair(s)")
            for a, b in found:
                print(f"    {a['key']} ({(a['end'] - a['start']) * 1000:.3f} ms) contains "
                      f"{b['key']} ({(b['end'] - b['start']) * 1000:.3f} ms)")
                containing[a["key"]] += 1
                contained[b["key"]] += 1
        print(f"total: {sum(containing.values())} pair(s) at {JUDGED * 1000:g} ms")
        print(f"containing: {dict(sorted(containing.items()))}")
        print(f"contained: {dict(sorted(contained.items()))}")
        return 0
    if argv[1:2] == ["aggregate"]:
        runs = []
        for path in argv[2:]:
            with open(path) as fh:
                runs.append(json.load(fh))
        _, _, _, lines = aggregate(runs)
        print("\n".join(lines))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
