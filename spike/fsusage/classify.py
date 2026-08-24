#!/usr/bin/env python3
"""Judge fs_usage captures against the shim's trace and the probe's account (#286).

Three inputs, two of which are ground truth of different strengths:

  capture   fs_usage's raw output, one line per event, wide mode.
  ops       the probe's self-account (JSON Lines: hello, sentinel, op).
  trace     the shim's binary trace (SIDEEYE1 header, little-endian records)
            — the account the oracle would actually be compared against.

Three outcomes, kept apart as in the fsevents survey:

  rc 0  the leg measured, and what it looked for held (or was recorded)
  rc 1  the leg measured, and the property failed (DEAD)
  rc 2  the leg could not measure (BROKEN)

An empty or half-delivered capture must never read as a finding, so every
capture is gated on BOTH sentinels (start and end): the probe brackets its
operations with two mutations inside the state directory, and a capture
missing either did not witness the window.

Every line of the capture is classified — syscall_state / diskio_state /
other_state / offstate / unparsed — and other_state is a first-class result,
not a discard: a state-touching line whose CALL this file does not know is
exactly what must not vanish before a human sees it.

Usage:
  classify.py census      CAPTURE OPS
  classify.py liveness    CAPTURE OPS
  classify.py p4          CAPTURE OPS
  classify.py p2-counts   CAPTURE OPS TRACE
  classify.py p2-order    CAPTURE OPS
  classify.py p1-partition CAPTURE HELLO_A HELLO_B
  classify.py p1-pidfilter CAPTURE HELLO_KEPT HELLO_FILTERED
  classify.py p1-child    CAPTURE OPS
  classify.py p3-rename   CAPTURE OPS
  classify.py p3-depth    CAPTURE OPS
  classify.py --selftest
"""
import json
import re
import struct
import sys

OPCLASS = {1: "open", 2: "write", 3: "rename", 4: "unlink", 5: "fsync",
           6: "truncate", 7: "mkdir", 8: "rmdir", 9: "link", 10: "symlink",
           100: "close", 200: "fork", 201: "exec", 202: "thread",
           203: "spawn", 204: "detached",
           900: "shim_ready", 901: "kill_landed", 902: "unresolved"}
MUTATING = {"open", "write", "rename", "unlink", "fsync", "truncate",
            "mkdir", "rmdir", "link", "symlink"}

# CALL tokens this judge knows. Generous on syscall spellings; anything
# state-touching outside both sets lands in other_state and is reported.
SYSCALL_CALLS = {
    "open", "open_nocancel", "openat", "openat_nocancel", "open_dprotected",
    "guarded_open_np",
    "write", "write_nocancel", "pwrite", "pwrite_nocancel", "writev",
    "writev_nocancel", "pwritev", "pwritev_nocancel",
    "read", "read_nocancel", "pread", "pread_nocancel",
    "rename", "renameat", "renamex_np",
    "unlink", "unlinkat",
    "mkdir", "mkdirat", "rmdir",
    "link", "linkat", "symlink", "symlinkat",
    "truncate", "ftruncate", "fsync", "fcntl", "fcntl_nocancel",
    "close", "close_nocancel", "lstat64", "stat64", "fstat64", "fstatat64",
    "getattrlist", "access", "chmod", "chown", "utimensat", "exit",
}
DISKIO_CALLS = {"WrData", "RdData", "WrMeta", "RdMeta", "PgIn", "PgOut",
                "WrMetaThr", "RdMetaThr"}

# One fs_usage wide-mode line: timestamp, CALL, middle, duration, optional W,
# process-name.threadid. Process names may contain dots; the thread id is the
# digits after the LAST dot.
LINE_RE = re.compile(
    r"^(?P<ts>\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(?P<call>\S+)\s+"
    r"(?P<middle>.*?)\s*"
    r"(?P<dur>\d+\.\d{6})\s+"
    r"(?P<wflag>W\s+)?"
    r"(?P<proc>\S+)\.(?P<tid>\d+)\s*$")

ERRNO_RE = re.compile(r"\[\s*(\d+)\]")
FD_RE = re.compile(r"\bF=(\d+)\b")


def norm(path):
    """fs_usage prints pathnames without their leading slash (measured, run
    32687071111: `open ... private/tmp/...`), and /tmp is /private/tmp on
    macOS. Matching goes through this so a state dir spelled either way and a
    capture line spelled fs_usage's way meet."""
    if path.startswith("/private/"):
        path = path[len("/private"):]
    return path.lstrip("/")


def mentions(raw, path):
    return norm(path) in raw


class Broken(Exception):
    """The apparatus could not measure. Never a hypothesis failing."""


# ---------------------------------------------------------------- parsers --

def parse_capture(text, statedir):
    """Classify EVERY line. Returns dict of buckets; nothing is dropped.

    Descriptor-addressed lines (write/pwrite/writev/close/fstat with F=n and
    no pathname) are resolved through the most recent `open F=n <path>` on
    the same thread. A descriptor nobody saw opened lands in fd_unresolved,
    reported rather than dropped: inherited stdio and the shim's own trace
    descriptor are the expected members of that bucket."""
    key = norm(statedir)
    out = {"syscall_state": [], "diskio_state": [], "other_state": [],
           "offstate": 0, "unparsed": [], "blank": 0, "fd_unresolved": []}
    fdmap = {}   # (tid, fd) -> path as printed
    out["_all_probe"] = []
    for raw in text.splitlines():
        if not raw.strip():
            out["blank"] += 1
            continue
        m = LINE_RE.match(raw)
        if not m:
            out["unparsed"].append(raw)
            continue
        call = m.group("call").split("[")[0]
        mid = m.group("middle")
        tid = int(m.group("tid"))
        rec = {"raw": raw, "call": call, "call_full": m.group("call"),
               "middle": mid, "proc": m.group("proc"), "tid": tid,
               "ts": m.group("ts"), "path": None, "via_fd": False}
        e = ERRNO_RE.search(mid)
        rec["errno"] = int(e.group(1)) if e else None
        f = FD_RE.search(mid)
        fd = int(f.group(1)) if f else None
        slash = mid.find("private/") if "private/" in mid else mid.find("/")
        if slash >= 0 and call not in DISKIO_CALLS:
            rec["path"] = mid[slash:].strip()
        elif slash >= 0:
            # disk-io lines: "D=... B=... /dev/diskNsM  <path>"
            parts = mid.split("/dev/", 1)
            rec["path"] = parts[1].split(None, 1)[1].strip() if len(parts) == 2 and len(parts[1].split(None, 1)) == 2 else mid[slash:].strip()
        if call.startswith("open") and fd is not None and rec["path"] and rec["errno"] is None:
            fdmap[(tid, fd)] = rec["path"]
        elif fd is not None and rec["path"] is None:
            known = fdmap.get((tid, fd))
            if known is not None:
                rec["path"] = known
                rec["via_fd"] = True
            elif call.startswith(("write", "pwrite", "read", "pread")):
                out["fd_unresolved"].append(rec)
        if call.startswith("close") and fd is not None:
            fdmap.pop((tid, fd), None)
        out["_all_probe"].append(rec)
        in_state = (key in raw) or (rec["path"] is not None and key in rec["path"])
        if not in_state:
            out["offstate"] += 1
            continue
        if call in SYSCALL_CALLS:
            out["syscall_state"].append(rec)
        elif call in DISKIO_CALLS:
            out["diskio_state"].append(rec)
        else:
            out["other_state"].append(rec)
    return out


def load_ops(path):
    """The probe's account: hello, both sentinels, ops. BROKEN if any absent."""
    hello, sents, ops = None, {}, []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise Broken(f"{path}:{lineno} is not JSON: {exc}")
                if not isinstance(rec, dict):
                    raise Broken(f"{path}:{lineno} is JSON but not an object")
                t = rec.get("type")
                if t == "hello":
                    hello = rec
                elif t == "sentinel":
                    sents[rec.get("which")] = rec
                elif t == "op":
                    ops.append(rec)
    except OSError as exc:
        raise Broken(f"cannot read {path}: {exc}")
    if hello is None:
        raise Broken(f"{path}: no hello record — the probe never announced itself")
    for which in ("start", "end"):
        s = sents.get(which)
        if s is None:
            raise Broken(f"{path}: no {which} sentinel — the window has no {which} bracket")
        if s.get("rc") != 0:
            raise Broken(f"{path}: the {which} sentinel itself failed (rc={s.get('rc')})")
    return hello, sents, ops


def load_hello(path):
    hello, _, _ = load_ops(path)
    return hello


def statedir_of(ops_path):
    _, sents, _ = load_ops(ops_path)
    p = sents["start"]["path"]
    return p.rsplit("/", 1)[0]


def parse_trace(path):
    """The shim's binary trace. BROKEN on any structural damage."""
    try:
        b = open(path, "rb").read()
    except OSError as exc:
        raise Broken(f"cannot read trace {path}: {exc}")
    if len(b) < 12 or b[:8] != b"SIDEEYE1":
        raise Broken(f"trace {path}: bad or missing SIDEEYE1 header "
                     f"({len(b)} bytes) — the shim never initialised?")
    ver = struct.unpack_from("<I", b, 8)[0]
    i, recs = 12, []
    while i < len(b):
        if i + 14 > len(b):
            raise Broken(f"trace {path}: truncated record at byte {i}")
        op, seq, pid, plen = struct.unpack_from("<HIII", b, i)
        i += 14
        if i + plen + 4 > len(b):
            raise Broken(f"trace {path}: truncated path at byte {i}")
        p = b[i:i + plen].decode("utf-8", errors="replace")
        i += plen
        alen = struct.unpack_from("<I", b, i)[0]
        i += 4
        if i + alen > len(b):
            raise Broken(f"trace {path}: truncated aux at byte {i}")
        a = b[i:i + alen].decode("utf-8", errors="replace")
        i += alen
        name = OPCLASS.get(op)
        if name is None:
            raise Broken(f"trace {path}: unknown op class {op} at byte {i}")
        recs.append({"op": name, "seq": seq, "pid": pid, "path": p, "aux": a})
    return ver, recs


# ---------------------------------------------------------------- verdicts --

def require_liveness(buckets, sents):
    for which in ("start", "end"):
        path = sents[which]["path"]
        seen = any(mentions(r["raw"], path)
                   for k in ("syscall_state", "diskio_state", "other_state")
                   for r in buckets[k])
        if not seen:
            raise Broken(f"the {which} sentinel ({path.rsplit('/', 1)[1]}) "
                         f"produced no line in this capture: the window is "
                         f"unproven and its silence says nothing")


def v_census(buckets):
    print(f"  census: syscall_state={len(buckets['syscall_state'])} "
          f"diskio_state={len(buckets['diskio_state'])} "
          f"other_state={len(buckets['other_state'])} "
          f"offstate={buckets['offstate']} unparsed={len(buckets['unparsed'])} "
          f"blank={buckets['blank']} fd_unresolved={len(buckets['fd_unresolved'])}")
    for r in buckets["other_state"][:10]:
        print(f"    other_state: {r['raw'][:160]}")
    for raw in buckets["unparsed"][:10]:
        print(f"    unparsed: {raw[:160]}")
    if buckets["unparsed"]:
        print(f"  census: BROKEN-adjacent — {len(buckets['unparsed'])} line(s) "
              f"did not match the grammar; the parser, not the platform, is "
              f"the suspect until they are explained")
        return 2
    return 0


def v_liveness(buckets, sents):
    require_liveness(buckets, sents)
    print("  liveness: both sentinels visible — the capture witnessed the window")
    return 0


def v_p4(buckets, sents, ops):
    require_liveness(buckets, sents)
    fails = [o for o in ops if o.get("rc", 0) < 0]
    if not fails:
        raise Broken("p4 needs a failing operation in the ops account; none found")
    dead = []
    for o in fails:
        path = o["path"]
        hits = [r for k in ("syscall_state", "diskio_state", "other_state")
                for r in buckets[k] if mentions(r["raw"], path)]
        errno_hits = [r for r in hits if r["errno"] is not None]
        print(f"  p4 {o['syscall']}({o.get('errno_name') or o.get('errno')}): "
              f"{len(hits)} line(s) mention the attempted path, "
              f"{len(errno_hits)} with a bracketed errno")
        for r in hits[:4]:
            print(f"    | {r['raw'][:170]}")
        if not hits:
            dead.append(o)
    if dead:
        print(f"  p4: DEAD — {len(dead)} failed attempt(s) left no line at all; "
              f"the shim records those attempts, so the accounts desync")
        return 1
    print(f"  p4: every failed attempt left a visible line")
    return 0


def _sentinel_paths(sents):
    return [sents["start"]["path"], sents["end"]["path"]]


def _not_sentinel(rows, sents):
    """The sentinels are the apparatus's own mutations. Counting them against
    the shim's op list, or letting their disk-io lines join an ordering check,
    grades the guard instead of the platform — the selftest caught exactly
    that before the first real capture was judged."""
    sp = _sentinel_paths(sents)
    return [r for r in rows if not any(mentions(r["raw"], p) for p in sp)]


def v_p2_counts(buckets, sents, ops, trace_recs, statedir):
    require_liveness(buckets, sents)
    sp = _sentinel_paths(sents)
    shim_writes = [r for r in trace_recs
                   if r["op"] == "write" and norm(r["path"]).startswith(norm(statedir))
                   and norm(r["path"]) not in [norm(x) for x in sp]]
    if not shim_writes:
        raise Broken("p2-counts needs write ops in the shim trace; none found "
                     "(did the shim load? DYLD stripped?)")
    write_lines = [r for r in _not_sentinel(buckets["syscall_state"], sents)
                   if r["call"].startswith(("write", "pwrite"))]
    wrdata = [r for r in _not_sentinel(buckets["diskio_state"], sents)
              if r["call"].startswith("Wr")]
    via_fd = sum(1 for r in write_lines if r["via_fd"])
    print(f"  p2-counts: shim recorded {len(shim_writes)} write op(s); capture "
          f"holds {len(write_lines)} write-syscall line(s) ({via_fd} placed "
          f"through their descriptor) and {len(wrdata)} Wr* disk-io line(s) on "
          f"the state dir; {len(buckets['fd_unresolved'])} descriptor line(s) "
          f"nobody saw opened")
    for r in write_lines[:5]:
        print(f"    | {r['raw'][:120]}  -> {r['path']}")
    if not write_lines:
        print("  p2-counts: DEAD — write syscalls are not visible as their own "
              "lines; disk-io events cannot be paired 1:1 with the shim's "
              "attempt records")
        return 1
    if len(write_lines) != len(shim_writes):
        print(f"  p2-counts: DEAD — {len(shim_writes)} recorded writes arrived "
              f"as {len(write_lines)} lines; the sequence lengths diverge")
        return 1
    print("  p2-counts: write-syscall lines match the shim's count")
    return 0


def v_p2_order(buckets, sents, ops):
    require_liveness(buckets, sents)
    tail = [o for o in ops if o["syscall"] in ("rename", "unlink")]
    if not tail:
        raise Broken("p2-order needs a rename or unlink in the ops account")
    tail_path = tail[0]["path"]
    order = []
    for r in _not_sentinel(buckets["syscall_state"] + buckets["diskio_state"],
                           sents):
        if r["call"].startswith(("write", "pwrite", "Wr")):
            order.append(("write-ish", r))
        elif r["call"].startswith(("rename", "unlink")) and mentions(r["raw"], tail_path):
            order.append(("tail", r))
    order.sort(key=lambda t: t[1]["ts"])
    kinds = [k for k, _ in order]
    print(f"  p2-order: sequence in capture: {kinds}")
    if "write-ish" not in kinds or "tail" not in kinds:
        raise Broken("p2-order: one side of the pair never appeared; order "
                     "cannot be judged from an absent line")
    if kinds.index("write-ish") < len(kinds) - 1 - kinds[::-1].index("tail"):
        print("  p2-order: a write-ish line precedes the tail operation")
        return 0
    print("  p2-order: DEAD — the tail operation appears before every "
          "write-ish line; capture order does not carry operation order")
    return 1


def v_p1_partition(buckets, hello_a, hello_b):
    tid_a, tid_b = hello_a.get("tid"), hello_b.get("tid")
    if not tid_a or not tid_b:
        raise Broken("p1-partition needs both probes' self-reported tids")
    tids = {}
    for r in buckets["syscall_state"] + buckets["diskio_state"] + buckets["other_state"]:
        tids.setdefault(r["tid"], 0)
        tids[r["tid"]] += 1
    print(f"  p1-partition: probe A tid={tid_a}, probe B tid={tid_b}; "
          f"capture tids on state dir: {sorted(tids.items())}")
    a_seen, b_seen = tid_a in tids, tid_b in tids
    others = [t for t in tids if t not in (tid_a, tid_b)]
    if not a_seen and not b_seen:
        print("  p1-partition: DEAD — neither self-reported tid appears; the "
              "trailing number does not map to pthread_threadid_np, so nothing "
              "in the output attributes a line to a process")
        return 1
    print(f"  p1-partition: mapping holds (A seen={a_seen}, B seen={b_seen}, "
          f"unattributed tids={others or 'none'})")
    return 0


def v_p1_pidfilter(buckets, hello_kept, hello_filtered):
    tid_k, tid_f = hello_kept.get("tid"), hello_filtered.get("tid")
    if not tid_k or not tid_f:
        raise Broken("p1-pidfilter needs both probes' self-reported tids")
    rows = buckets["syscall_state"] + buckets["diskio_state"] + buckets["other_state"]
    kept = [r for r in rows if r["tid"] == tid_k]
    leaked = [r for r in rows if r["tid"] == tid_f]
    print(f"  p1-pidfilter: kept-pid lines={len(kept)}, "
          f"filtered-pid lines={len(leaked)}")
    if not kept:
        print("  p1-pidfilter: DEAD — the pid the filter names produced no "
              "lines; the filter is too strong or the pid argument is not "
              "honoured")
        return 1
    if leaked:
        print("  p1-pidfilter: DEAD — the other process leaked through a "
              "pid-scoped filter")
        for r in leaked[:3]:
            print(f"    | {r['raw'][:170]}")
        return 1
    print("  p1-pidfilter: the filter kept one process and excluded the other")
    return 0


def v_p1_child(buckets, sents, ops):
    require_liveness(buckets, sents)
    child_ops = [o for o in ops if o.get("class") == "child"]
    if not child_ops:
        raise Broken("p1-child needs the child-write op in the account")
    path = child_ops[0]["path"]
    hits = [r for k in ("syscall_state", "diskio_state", "other_state")
            for r in buckets[k] if mentions(r["raw"], path)]
    print(f"  p1-child: the child's file produced {len(hits)} line(s) under "
          f"the parent-scoped capture")
    for r in hits[:3]:
        print(f"    | {r['raw'][:170]}")
    # Either answer is a measurement; the verdict records which one this is.
    print(f"  p1-child: {'children FOLLOW the filter' if hits else 'children are NOT followed'}")
    return 0


def v_p3_rename(buckets, sents, ops):
    require_liveness(buckets, sents)
    ren = [o for o in ops if o["syscall"] == "rename" and o.get("rc", -1) >= 0]
    if not ren:
        raise Broken("p3-rename needs a successful rename in the account")
    old, new = ren[0]["path"], ren[0].get("path2")
    rows = [r for k in ("syscall_state", "diskio_state", "other_state")
            for r in buckets[k]]
    old_hits = [r for r in rows if mentions(r["raw"], old)]
    new_hits = [r for r in rows if new and mentions(r["raw"], new)]
    print(f"  p3-rename: old path on {len(old_hits)} line(s), new path on "
          f"{len(new_hits)} line(s)")
    for r in (old_hits + new_hits)[:4]:
        print(f"    | {r['raw'][:170]}")
    if not new_hits:
        print("  p3-rename: DEAD — the destination never appears; a rename "
              "whose new name is invisible cannot be checked for scope "
              "(either endpoint inside the state dir counts, ADR 0006)")
        return 1
    print("  p3-rename: both endpoints visible")
    return 0


def v_p3_depth(buckets, sents, hello):
    """How long a pathname survives display. Run 32687071111 showed wide
    mode keeping the LAST ~153 characters and dropping the front, so a state
    dir deeper than that cannot be scoped by its own path. This leg finds the
    sentinels by leaf name, on the probe's thread, and reports the cap."""
    tid = hello.get("tid")
    rows = [r for k in ("syscall_state", "diskio_state", "other_state")
            for r in buckets[k]]
    # Scoping by state path fails by construction here, so look at every
    # parsed line on the probe's thread instead.
    allrows = rows + buckets.get("_all_probe", [])
    start, end = sents["start"]["path"], sents["end"]["path"]
    def leaf(p):
        return p.rsplit("/", 1)[1]
    seen_start = [r for r in allrows if leaf(start) in r["raw"] and r["tid"] == tid]
    seen_end = [r for r in allrows if leaf(end) in r["raw"] and r["tid"] == tid]
    if not seen_start or not seen_end:
        raise Broken("p3-depth: a sentinel leaf never appeared on the probe's "
                     "thread; the window is unproven")
    longest = 0
    full = any(mentions(r["raw"], start) for r in seen_start)
    for r in seen_start + seen_end:
        p = r.get("path") or ""
        longest = max(longest, len(p))
    print(f"  p3-depth: full state path {'visible' if full else 'NOT visible'}; "
          f"longest displayed pathname {longest} chars; real sentinel path "
          f"{len(start)} chars")
    for r in seen_start[:2]:
        print(f"    | {r['raw'][:200]}")
    if not full:
        print(f"  p3-depth: DEAD — the displayed pathname is cut from the left "
              f"at about {longest} chars, so a state dir this deep cannot be "
              f"scoped by its own path")
        return 1
    return 0


# ---------------------------------------------------------------- selftest --

FIX_STATE = "/tmp/fx/state"


def _cap_line(call, path, tid=111, errno=None, ts="10:00:01.000100", dur="0.000100"):
    mid = f"F=3        (_WC_T_______)  {path}"
    if errno is not None:
        mid = f"[{errno:3d}]  {path}"
    return f"{ts}  {call:<16}  {mid}    {dur}   probe.{tid}"


def _fix_capture(lines, sent_tid=111):
    pre = [_cap_line("open", f"{FIX_STATE}/sentinel-start", tid=sent_tid),
           _cap_line("WrData[A]", f"/dev/disk3s5  {FIX_STATE}/sentinel-start",
                     tid=sent_tid)]
    post = [_cap_line("open", f"{FIX_STATE}/sentinel-end", tid=sent_tid,
                      ts="10:00:09.000100")]
    return "\n".join(pre + lines + post) + "\n"


def _fix_ops(ops, tid=111):
    recs = [{"type": "hello", "pid": 42, "tid": tid, "mode": "fx"},
            {"type": "sentinel", "which": "start", "pid": 42,
             "path": f"{FIX_STATE}/sentinel-start", "rc": 0}]
    recs += ops
    recs += [{"type": "sentinel", "which": "end", "pid": 42,
              "path": f"{FIX_STATE}/sentinel-end", "rc": 0}]
    return "\n".join(json.dumps(r) for r in recs) + "\n"


def _fix_trace(recs):
    b = b"SIDEEYE1" + struct.pack("<I", 10)
    rev = {v: k for k, v in OPCLASS.items()}
    for op, path in recs:
        p, a = path.encode(), b""
        b += struct.pack("<HIII", rev[op], 1, 42, len(p)) + p
        b += struct.pack("<I", len(a)) + a
    return b


def selftest():
    import io
    import contextlib
    import tempfile
    import os
    fails = 0
    rows = []

    def case(name, fn, want):
        nonlocal fails
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                got = fn()
        except Broken:
            got = "BROKEN"
        ok = got == want
        if not ok:
            fails += 1
        rows.append(("ok" if ok else "FAIL", name, got, want))

    def ops_file(text):
        fd, p = tempfile.mkstemp(suffix=".jsonl")
        os.write(fd, text.encode())
        os.close(fd)
        return p

    op_write = {"type": "op", "seq": 0, "pid": 42, "syscall": "write",
                "class": "write", "path": f"{FIX_STATE}/target", "rc": 7,
                "errno": 0, "errno_name": ""}
    op_ren = {"type": "op", "seq": 1, "pid": 42, "syscall": "rename",
              "class": "rename", "path": f"{FIX_STATE}/target",
              "path2": f"{FIX_STATE}/target2", "rc": 0, "errno": 0}
    op_fail = {"type": "op", "seq": 0, "pid": 42, "syscall": "unlink",
               "class": "unlink", "path": f"{FIX_STATE}/missing", "rc": -1,
               "errno": 2, "errno_name": "ENOENT"}

    full = _fix_capture([
        _cap_line("write", f"{FIX_STATE}/target", ts="10:00:02.000100"),
        _cap_line("rename", f"{FIX_STATE}/target", ts="10:00:03.000100"),
    ])
    no_end = full.replace(_cap_line("open", f"{FIX_STATE}/sentinel-end",
                                    ts="10:00:09.000100") + "\n", "")

    def run(vfn, cap_text, ops_text, *extra):
        p = ops_file(ops_text)
        try:
            hello, sents, ops = load_ops(p)
            buckets = parse_capture(cap_text, FIX_STATE)
            if vfn is v_p2_counts:
                return vfn(buckets, sents, ops, extra[0], FIX_STATE)
            if vfn in (v_p4, v_p2_order, v_p1_child, v_p3_rename):
                return vfn(buckets, sents, ops)
            return vfn(buckets, sents)
        finally:
            os.unlink(p)

    # accept side (an always-DEAD judge dies here)
    case("liveness accepts a bracketed capture",
         lambda: run(v_liveness, full, _fix_ops([op_write])), 0)
    case("p2-order accepts write before rename",
         lambda: run(v_p2_order, full, _fix_ops([op_write, op_ren])), 0)
    case("p2-counts accepts 1 write line vs 1 shim write",
         lambda: run(v_p2_counts,
                     _fix_capture([_cap_line("write", f"{FIX_STATE}/target")]),
                     _fix_ops([op_write]),
                     parse_trace_bytes(_fix_trace([("write", f"{FIX_STATE}/target")]))), 0)
    case("p4 accepts a visible failed attempt",
         lambda: run(v_p4,
                     _fix_capture([_cap_line("unlink", f"{FIX_STATE}/missing", errno=2)]),
                     _fix_ops([op_fail])), 0)
    case("p3-rename accepts both endpoints",
         lambda: run(v_p3_rename,
                     _fix_capture([_cap_line("rename", f"{FIX_STATE}/target"),
                                   _cap_line("open", f"{FIX_STATE}/target2")]),
                     _fix_ops([op_ren])), 0)

    # reject side (an always-OK judge dies here)
    case("liveness on a capture missing the end sentinel is BROKEN",
         lambda: run(v_liveness, no_end, _fix_ops([op_write])), "BROKEN")
    case("p4 rejects an invisible failed attempt (the K1 shape)",
         lambda: run(v_p4, _fix_capture([]), _fix_ops([op_fail])), 1)
    case("p2-counts rejects zero write lines against a recorded write",
         lambda: run(v_p2_counts,
                     _fix_capture([_cap_line("WrData[A]",
                                             f"/dev/disk3s5  {FIX_STATE}/target")]),
                     _fix_ops([op_write]),
                     parse_trace_bytes(_fix_trace([("write", f"{FIX_STATE}/target")]))), 1)
    case("p2-order rejects the swapped order",
         lambda: run(v_p2_order, _fix_capture([
             _cap_line("rename", f"{FIX_STATE}/target", ts="10:00:02.000100"),
             _cap_line("write", f"{FIX_STATE}/target", ts="10:00:03.000100"),
         ]), _fix_ops([op_write, op_ren])), 1)
    case("p3-rename rejects an invisible destination",
         lambda: run(v_p3_rename,
                     _fix_capture([_cap_line("rename", f"{FIX_STATE}/target")]),
                     _fix_ops([op_ren])), 1)

    # descriptor resolution: a path-less `write F=3` after `open F=3 <path>`
    # on the same thread is a write on that path (run 32687071111 shape)
    fd_cap = _fix_capture([
        _cap_line("open", f"{FIX_STATE}/target", ts="10:00:02.000100"),
        "10:00:02.000200  write             F=3    B=0x7                        0.000010   probe.111",
    ])
    case("p2-counts places a path-less write through its descriptor",
         lambda: run(v_p2_counts, fd_cap, _fix_ops([op_write]),
                     parse_trace_bytes(_fix_trace([("write", f"{FIX_STATE}/target")]))), 0)
    case("a write on a descriptor nobody saw opened is reported, not counted",
         lambda: (lambda b: 0 if len(b["fd_unresolved"]) == 1 and
                  not [r for r in b["syscall_state"] if r["call"] == "write"] else 1)(
             parse_capture(_fix_capture([
                 "10:00:02.000200  write             F=9    B=0x7                        0.000010   probe.111"]),
                 FIX_STATE)), 0)
    case("a line spelled without the leading slash still scopes to the state dir",
         lambda: (lambda b: 0 if len(b["syscall_state"]) == 1 else 1)(
             parse_capture("10:00:02.000100  unlink            [  2]           "
                           + FIX_STATE.lstrip("/") + "/missing"
                           + "   0.000010   probe.111\n", FIX_STATE)), 0)
    case("a /private-spelled state dir matches an fs_usage line",
         lambda: 0 if mentions("open  private/tmp/fx/state/target  0.1 probe.1",
                              "/private/tmp/fx/state/target") else 1, 0)

    # metamorphic: mutations of the SAME fixture flip or break the verdict
    case("census flags an unknown state-touching CALL as other_state",
         lambda: (lambda b: 0 if len(b["other_state"]) == 1 else 1)(
             parse_capture(_fix_capture(
                 [_cap_line("mystery_call", f"{FIX_STATE}/target")]), FIX_STATE)), 0)
    case("census reports an unparseable line as BROKEN-adjacent (rc 2)",
         lambda: v_census(parse_capture(full + "garbage line\n", FIX_STATE)), 2)
    case("a truncated trace is BROKEN",
         lambda: parse_trace_bytes(_fix_trace([("write", "/x")])[:-3]), "BROKEN")
    case("a trace with the wrong magic is BROKEN",
         lambda: parse_trace_bytes(b"NOTMAGIC" + b"\x00" * 20), "BROKEN")

    # p1 verdicts on synthetic hellos
    hA = {"tid": 111}
    hB = {"tid": 222}
    both = parse_capture(_fix_capture(
        [_cap_line("open", f"{FIX_STATE}/target", tid=111),
         _cap_line("open", f"{FIX_STATE}/target", tid=222)]), FIX_STATE)
    unrelated = parse_capture(_fix_capture(
        [_cap_line("open", f"{FIX_STATE}/target", tid=999)], sent_tid=999),
        FIX_STATE)
    case("p1-partition maps self-reported tids to capture lines",
         lambda: v_p1_partition(both, hA, hB), 0)
    case("p1-partition rejects when no reported tid appears",
         lambda: v_p1_partition(unrelated, hA, hB), 1)
    case("p1-pidfilter rejects a leak of the filtered pid",
         lambda: v_p1_pidfilter(both, hA, hB), 1)
    case("p1-pidfilter accepts a clean partition",
         lambda: v_p1_pidfilter(parse_capture(_fix_capture(
             [_cap_line("open", f"{FIX_STATE}/target", tid=111)]), FIX_STATE),
             hA, hB), 0)

    width = max(len(r[1]) for r in rows)
    for verdict, name, got, want in rows:
        print(f"  selftest {verdict}: {name:<{width}}  -> {got!r} (wanted {want!r})")
    print(f"  selftest cases: {len(rows)}, failures: {fails}")
    return 1 if fails else 0


def parse_trace_bytes(b):
    """Selftest helper that routes through the production trace parser."""
    import tempfile
    import os
    fd, p = tempfile.mkstemp(suffix=".trace")
    os.write(fd, b)
    os.close(fd)
    try:
        _, recs = parse_trace(p)
        return recs
    finally:
        os.unlink(p)


# -------------------------------------------------------------------- main --

def main():
    args = sys.argv[1:]
    if args == ["--selftest"]:
        sys.exit(selftest())
    if len(args) < 3:
        print(__doc__)
        sys.exit(2)
    leg, cap_path = args[0], args[1]
    try:
        cap_text = open(cap_path, encoding="utf-8", errors="replace").read()
        if leg == "p1-partition" or leg == "p1-pidfilter":
            ha, hb = load_hello(args[2]), load_hello(args[3])
            sd = statedir_of(args[2])
            buckets = parse_capture(cap_text, sd)
            fn = v_p1_partition if leg == "p1-partition" else v_p1_pidfilter
            sys.exit(fn(buckets, ha, hb))
        hello, sents, ops = load_ops(args[2])
        sd = sents["start"]["path"].rsplit("/", 1)[0]
        buckets = parse_capture(cap_text, sd)
        if leg == "census":
            sys.exit(v_census(buckets))
        if leg == "liveness":
            sys.exit(v_liveness(buckets, sents))
        if leg == "p4":
            sys.exit(v_p4(buckets, sents, ops))
        if leg == "p2-counts":
            _, recs = parse_trace(args[3])
            sys.exit(v_p2_counts(buckets, sents, ops, recs, sd))
        if leg == "p2-order":
            sys.exit(v_p2_order(buckets, sents, ops))
        if leg == "p1-child":
            sys.exit(v_p1_child(buckets, sents, ops))
        if leg == "p3-rename":
            sys.exit(v_p3_rename(buckets, sents, ops))
        if leg == "p3-depth":
            sys.exit(v_p3_depth(buckets, sents, hello))
        print(__doc__)
        sys.exit(2)
    except Broken as exc:
        print(f"  BROKEN: {exc}")
        sys.exit(2)


if __name__ == "__main__":
    main()
