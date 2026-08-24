#!/usr/bin/env python3
"""Judge one FSEvents capture against the probe's own account (#286).

Three outcomes, kept apart on purpose:

  rc 0  the leg measured, and the thing it looked for held
  rc 1  the leg measured, and the hypothesis failed its test (DEAD)
  rc 2  the leg could not measure (BROKEN)

Conflating 1 and 2 is how an apparatus failure becomes a finding. This survey
has already produced one: a settle shorter than the stream's latency gave five
consecutive empty captures that looked exactly like "FSEvents reported
nothing". So an empty capture is never a verdict here. Every --run ends with a
sentinel mutation whose event must arrive; if it does not, the capture is
BROKEN and its silence carries no information.

What the verdicts do and do not claim:

  mapping     per PATH, not per operation. Several operations on one path
              collapse into one entry, so an entry cannot be attributed to a
              particular operation, and this judge does not pretend otherwise.
              It reports paths with no event at all (the counterexample), and
              reports the entry count against the operation count separately.

  coalescing  entries against operations, and how they divide into callback
              deliveries. Requires the sentinel.

  ordering    whether ids are monotonic AND whether the entry count can carry
              the operation order at all. Fewer entries than operations means
              the order is not recoverable, which is a finding, not a pass.

  attribution whether two runs differing only in WHO acted are separable.

Usage:
  judge.py soundness   EVENTS OPS
  judge.py mapping     EVENTS OPS
  judge.py coalescing  EVENTS OPS
  judge.py ordering    EVENTS OPS
  judge.py attribution EVENTS_A EVENTS_B
  judge.py --selftest
"""
import json
import sys

# Flags that mean the stream stopped being a faithful log and asked for a
# rescan. A run carrying any of them is not scored: grading it would grade a
# run the API itself disowned.
DISOWNING = ("MustScanSubDirs", "UserDropped", "KernelDropped",
             "EventIdsWrapped", "RootChanged")


class Broken(Exception):
    """The apparatus could not measure. Never a hypothesis failing."""


def _rec_list(text, label):
    recs = []
    for lineno, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            raise Broken(f"{label}:{lineno} is not JSON: {exc}")
        # A JSON scalar parses fine and then explodes on .get(). Schema is
        # checked here so a malformed transcript is BROKEN rather than a
        # Python traceback that the shell would read as rc 1, i.e. as DEAD.
        if not isinstance(obj, dict):
            raise Broken(f"{label}:{lineno} is JSON but not an object: {obj!r}")
        if not isinstance(obj.get("type"), str):
            raise Broken(f"{label}:{lineno} has no string 'type' field")
        recs.append(obj)
    return recs


def load(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return _rec_list(fh.read(), path)
    except OSError as exc:
        raise Broken(f"cannot read {path}: {exc}")


def load_str(text, label="<memory>"):
    return _rec_list(text, label)


def _need(rec, field, types, label):
    v = rec.get(field)
    if not isinstance(v, types):
        raise Broken(f"{label}: record {rec.get('type')!r} has {field}={v!r}, "
                     f"expected {types}")
    return v


def split_events(recs):
    """Return (config, events, done) after checking the protocol completed."""
    for r in recs:
        if r.get("type") == "broken":
            raise Broken(f"watcher reported broken: {r.get('reason')}")
    kinds = [r["type"] for r in recs]
    for required in ("config", "ready", "done"):
        if required not in kinds:
            raise Broken(f"capture has no {required} record: the watcher did "
                         f"not complete its protocol")
    config = next(r for r in recs if r["type"] == "config")
    done = next(r for r in recs if r["type"] == "done")
    events = [r for r in recs if r["type"] == "event"]
    for e in events:
        _need(e, "path", str, "event")
        _need(e, "flags_decoded", list, "event")
        _need(e, "event_id", int, "event")
        _need(e, "batch", int, "event")
    if _need(done, "events", int, "done") != len(events):
        raise Broken(f"done says {done['events']} events, capture holds "
                     f"{len(events)}: the transcript is truncated")
    return config, events, done


def load_ops(recs):
    """Return (ops, sentinel). The sentinel is the run's liveness control."""
    ops = [r for r in recs if r["type"] == "op"]
    sentinels = [r for r in recs if r["type"] == "sentinel"]
    if not ops:
        raise Broken("the probe recorded no operation, so there is nothing to "
                     "judge the capture against")
    for o in ops:
        _need(o, "path", str, "op")
        _need(o, "syscall", str, "op")
        _need(o, "rc", int, "op")
    if len(sentinels) != 1:
        raise Broken(f"expected exactly one sentinel record, found "
                     f"{len(sentinels)}: this run has no liveness control")
    s = sentinels[0]
    _need(s, "path", str, "sentinel")
    if _need(s, "rc", int, "sentinel") != 0:
        raise Broken(f"the sentinel mutation itself failed (rc={s['rc']}): "
                     f"nothing in this capture can be interpreted")
    return ops, s


def require_liveness(events, sentinel):
    """The sentinel's event must be present, in THIS capture.

    Without it an empty capture cannot be told from a run where delivery did
    not work, and this survey has produced exactly that failure already.
    """
    if not any(e["path"] == sentinel["path"] for e in events):
        raise Broken("the sentinel mutation produced no event in this capture, "
                     "so delivery is unproven for this run and its silence "
                     "says nothing about FSEvents")


def measured_events(events, sentinel):
    """Events other than the sentinel's own."""
    return [e for e in events if e["path"] != sentinel["path"]]


def op_paths(ops):
    paths = []
    for o in ops:
        for key in ("path", "path2"):
            p = o.get(key)
            if isinstance(p, str) and p not in paths:
                paths.append(p)
    return paths


def disowned(events):
    hits = []
    for e in events:
        for f in e["flags_decoded"]:
            if f in DISOWNING and f not in hits:
                hits.append(f)
    return hits


def v_soundness(events, ops, sentinel):
    require_liveness(events, sentinel)
    ev = measured_events(events, sentinel)
    paths = op_paths(ops)
    seen = {e["path"] for e in ev}
    covered = [p for p in paths if p in seen]
    print(f"  soundness: sentinel delivered; {len(ops)} operation(s) over "
          f"{len(paths)} path(s); {len(ev)} event(s) besides the sentinel; "
          f"{len(covered)}/{len(paths)} path(s) produced at least one event")
    if not covered:
        print("  soundness: FAIL - no event for any path the probe touched")
        return 1
    print("  soundness: ok - the apparatus is alive")
    return 0


def v_mapping(events, ops, sentinel):
    require_liveness(events, sentinel)
    ev = measured_events(events, sentinel)
    seen = {}
    for e in ev:
        seen.setdefault(e["path"], []).append(e)

    paths = op_paths(ops)
    unseen = [p for p in paths if p not in seen]

    for o in ops:
        targets = [p for p in (o.get("path"), o.get("path2")) if isinstance(p, str)]
        hit = [t for t in targets if t in seen]
        flags = sorted({f for t in hit for e in seen[t] for f in e["flags_decoded"]})
        print(f"  op seq={o.get('seq')} {o['syscall']} class={o.get('class')} "
              f"rc={o['rc']} errno={o.get('errno_name') or o.get('errno')}: "
              f"path(s) {'observed' if hit else 'NOT observed'} {flags}")

    # Stated separately and deliberately: an entry cannot be attributed to one
    # operation when several operations share a path, so "every operation was
    # observed" is not a claim this judge is able to make.
    print(f"  mapping: {len(ops)} operation(s) -> {len(ev)} entry(ies) over "
          f"{len(paths)} path(s); per-operation attribution is not available "
          f"when operations share a path")
    if unseen:
        print(f"  mapping: DEAD - {len(unseen)} path(s) with an operation and "
              f"no event: " + ", ".join(unseen))
        print("  mapping: the shim records those attempts, so a comparison "
              "against this capture desyncs (shim/src/ops.zig)")
        return 1
    if len(ev) < len(ops):
        print(f"  mapping: every path was observed, but {len(ops)} operation(s) "
              f"arrived as {len(ev)} entry(ies): the sequence is not "
              f"recoverable from this capture")
    return 0


def v_coalescing(events, ops, sentinel):
    require_liveness(events, sentinel)
    ev = measured_events(events, sentinel)
    d = disowned(ev)
    if d:
        print(f"  coalescing: NOT SCORED - the stream disowned this run: {d}")
        return 0
    if not ev:
        print("  coalescing: DEAD - the sentinel arrived but the operations "
              "produced no entry at all")
        return 1
    batches = sorted({e["batch"] for e in ev})
    per_path = {}
    for e in ev:
        per_path.setdefault(e["path"], []).append(e)
    print(f"  coalescing: {len(ops)} operation(s) -> {len(ev)} entry(ies) in "
          f"{len(batches)} callback delivery(ies)")
    for p, es in per_path.items():
        flags = sorted({f for e in es for f in e["flags_decoded"]})
        print(f"    {p}: {len(es)} entry(ies), union of flags {flags}")
    return 0


def v_ordering(events, ops, sentinel):
    require_liveness(events, sentinel)
    ev = measured_events(events, sentinel)
    d = disowned(ev)
    if d:
        print(f"  ordering: NOT SCORED - the stream disowned this run: {d}")
        return 0
    ids = [e["event_id"] for e in ev]
    rc = 0
    if ids != sorted(ids):
        print(f"  ordering: ids are not monotonic across the capture: {ids}")
        rc = 1
    else:
        print(f"  ordering: ids monotonic across {len(ids)} entry(ies)")
    # Monotonic ids over too few entries carry no order. Saying "monotonic"
    # and stopping would be a pass on a vacuous check.
    if len(ev) < len(ops):
        print(f"  ordering: DEAD - {len(ops)} operation(s) arrived as "
              f"{len(ev)} entry(ies), so no entry order can carry the "
              f"operation order")
        rc = 1
    for e in ev:
        t = e.get("mono_ns")
        inside = [o.get("seq") for o in ops
                  if isinstance(t, int)
                  and o.get("start_ns", 0) <= t <= o.get("end_ns", 0)]
        after = [o.get("seq") for o in ops
                 if isinstance(t, int) and o.get("end_ns", 0) < t]
        print(f"    entry batch={e['batch']}.{e.get('index_in_batch')} "
              f"id={e['event_id']} inside op(s) {inside or '[]'}, "
              f"after op(s) {after or '[]'}")
    return rc


def shape_of(events):
    """Observable content only. Ids and arrival times differ between any two
    runs, so including them would make every pair look distinguishable for a
    reason carrying no information about who acted."""
    return [(e["path"], tuple(sorted(e["flags_decoded"]))) for e in events]


def v_attribution(ea, eb):
    sa, sb = shape_of(ea), shape_of(eb)
    print(f"  attribution: run A {len(sa)} entry(ies), run B {len(sb)} entry(ies)")
    for label, s in (("A", sa), ("B", sb)):
        for p, f in s:
            print(f"    {label}: {p} {list(f)}")
    if not sa or not sb:
        raise Broken("one of the two captures is empty, so equality would "
                     "prove nothing about attribution")
    if sa == sb:
        print("  attribution: INDISTINGUISHABLE - the runs differ only in "
              "which process acted, and the captures agree in path and flags")
        return 1
    print("  attribution: the captures differ")
    return 0


def j_soundness(e, o):
    _, ev, _ = split_events(load(e))
    ops, s = load_ops(load(o))
    return v_soundness(ev, ops, s)


def j_mapping(e, o):
    _, ev, _ = split_events(load(e))
    ops, s = load_ops(load(o))
    return v_mapping(ev, ops, s)


def j_coalescing(e, o):
    _, ev, _ = split_events(load(e))
    ops, s = load_ops(load(o))
    return v_coalescing(ev, ops, s)


def j_ordering(e, o):
    _, ev, _ = split_events(load(e))
    ops, s = load_ops(load(o))
    return v_ordering(ev, ops, s)


def j_attribution(a, b):
    _, ea, _ = split_events(load(a))
    _, eb, _ = split_events(load(b))
    return v_attribution(ea, eb)


# --------------------------------------------------------------------------
# Selftest. Drives the PRODUCTION functions: the parse, the protocol check and
# the verdicts are the ones the file entry points call. An earlier version
# re-implemented the rules here, which would have let every fixture pass while
# the shipped judge was wrong.
#
# Covered in all three directions, because a one-sided suite cannot tell an
# always-accept judge from an always-reject one from the real thing.
# --------------------------------------------------------------------------

SENT = "/s/sentinel"


def _cap(event_lines, n=None, with_sentinel=True):
    lines = list(event_lines)
    if with_sentinel:
        lines.append(_ev(SENT, ["ItemCreated"], batch=9, eid=10 ** 6))
    head = ['{"type":"config","path":"/s","latency":0}', '{"type":"ready"}']
    tail = ['{"type":"done","batches":1,"events":%d}'
            % (len(lines) if n is None else n)]
    return "\n".join(head + lines + tail) + "\n"


def _ev(path, flags, batch=0, idx=0, eid=1, mono=100):
    return ('{"type":"event","batch":%d,"index_in_batch":%d,"event_id":%d,'
            '"flags_raw":"0x0","flags_decoded":%s,"path":"%s","mono_ns":%d}'
            % (batch, idx, eid, json.dumps(flags), path, mono))


def _op(seq, syscall, cls, path, rc=0, err=0, t0=10, t1=20):
    return ('{"type":"op","seq":%d,"syscall":"%s","class":"%s","path":"%s",'
            '"rc":%d,"errno":%d,"errno_name":"","start_ns":%d,"end_ns":%d}'
            % (seq, syscall, cls, path, rc, err, t0, t1))


def _sent(rc=0):
    return ('{"type":"sentinel","path":"%s","rc":%d,"errno":0,'
            '"start_ns":30,"end_ns":40}' % (SENT, rc))


def selftest():
    fails = 0
    rows = []

    def run(kind, ev_text, op_text):
        ev = split_events(load_str(ev_text, "events"))[1]
        ops, s = load_ops(load_str(op_text, "ops"))
        return {"mapping": v_mapping, "soundness": v_soundness,
                "coalescing": v_coalescing, "ordering": v_ordering}[kind](ev, ops, s)

    def case(name, fn, want):
        nonlocal fails
        try:
            got = fn()
        except Broken:
            got = "BROKEN"
        ok = got == want
        if not ok:
            fails += 1
        rows.append(("ok" if ok else "FAIL", name, got, want))

    one_op = _op(0, "open", "open", "/s/target") + "\n" + _sent()
    three_ops = "\n".join([_op(0, "open", "open", "/s/target"),
                           _op(1, "write", "write", "/s/target"),
                           _op(2, "fsync", "fsync", "/s/target"),
                           _sent()])

    # --- accept side: an always-reject judge dies here ---
    case("mapping accepts one op with one event",
         lambda: run("mapping", _cap([_ev("/s/target", ["ItemCreated"])]), one_op), 0)
    case("soundness accepts a live apparatus",
         lambda: run("soundness", _cap([_ev("/s/target", ["ItemCreated"])]), one_op), 0)
    case("coalescing accepts and records a collapsed run",
         lambda: run("coalescing", _cap([_ev("/s/target", ["ItemCreated"])]), three_ops), 0)
    case("ordering accepts monotonic ids with one entry per op",
         lambda: run("ordering",
                     _cap([_ev("/s/a", ["ItemCreated"], eid=1),
                           _ev("/s/b", ["ItemCreated"], idx=1, eid=2)]),
                     _op(0, "open", "open", "/s/a") + "\n"
                     + _op(1, "open", "open", "/s/b") + "\n" + _sent()), 0)

    # --- reject side: an always-accept judge dies here ---
    case("mapping rejects an op whose path saw nothing (the K1 shape)",
         lambda: run("mapping", _cap([]),
                     _op(0, "unlink", "unlink", "/s/missing", rc=-1, err=2)
                     + "\n" + _sent()), 1)
    case("mapping rejects when only one of two paths was seen",
         lambda: run("mapping", _cap([_ev("/s/a", ["ItemCreated"])]),
                     _op(0, "open", "open", "/s/a") + "\n"
                     + _op(1, "unlink", "unlink", "/s/b") + "\n" + _sent()), 1)
    case("soundness rejects a capture with no event for any op path",
         lambda: run("soundness", _cap([_ev("/s/elsewhere", ["ItemCreated"])]),
                     one_op), 1)
    case("ordering rejects non-monotonic ids",
         lambda: run("ordering",
                     _cap([_ev("/s/a", ["ItemCreated"], eid=9),
                           _ev("/s/b", ["ItemCreated"], idx=1, eid=2)]),
                     _op(0, "open", "open", "/s/a") + "\n"
                     + _op(1, "open", "open", "/s/b") + "\n" + _sent()), 1)
    case("ordering rejects fewer entries than operations as unrecoverable",
         lambda: run("ordering", _cap([_ev("/s/target", ["ItemCreated"])]),
                     three_ops), 1)
    case("coalescing rejects zero entries beside a delivered sentinel",
         lambda: run("coalescing", _cap([]), three_ops), 1)

    # --- the claim this judge must NOT make: per-operation attribution ---
    def three_ops_one_entry_text():
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            run("mapping", _cap([_ev("/s/target", ["ItemCreated"])]), three_ops)
        return buf.getvalue()
    case("mapping never claims 'every operation produced an event'",
         lambda: "every one of" not in three_ops_one_entry_text(), True)
    case("mapping says the sequence is not recoverable when entries < ops",
         lambda: "not\nrecoverable" in three_ops_one_entry_text()
                 or "not recoverable" in three_ops_one_entry_text(), True)

    # --- BROKEN side: apparatus failures are never verdicts ---
    case("malformed JSON is BROKEN",
         lambda: run("mapping", '{"type":"config"}\nnot json\n', one_op), "BROKEN")
    case("a JSON scalar line is BROKEN, not a traceback",
         lambda: run("mapping", '{"type":"config"}\n42\n', one_op), "BROKEN")
    case("flags_decoded of the wrong type is BROKEN",
         lambda: run("mapping",
                     '{"type":"config"}\n{"type":"ready"}\n'
                     '{"type":"event","batch":0,"event_id":1,'
                     '"flags_decoded":null,"path":"/s/target"}\n'
                     '{"type":"done","events":1}\n', one_op), "BROKEN")
    case("a missing ready record is BROKEN",
         lambda: run("mapping", '{"type":"config"}\n{"type":"done","events":0}\n',
                     one_op), "BROKEN")
    case("a truncated capture is BROKEN",
         lambda: run("mapping",
                     '{"type":"config"}\n{"type":"ready"}\n'
                     + _ev("/s/target", ["ItemCreated"]) + '\n'
                     '{"type":"done","events":5}\n', one_op), "BROKEN")
    case("a watcher broken record is BROKEN",
         lambda: run("mapping",
                     '{"type":"config"}\n{"type":"ready"}\n'
                     '{"type":"broken","reason":"start failed"}\n'
                     '{"type":"done","events":0}\n', one_op), "BROKEN")
    case("no sentinel record is BROKEN",
         lambda: run("mapping", _cap([_ev("/s/target", ["ItemCreated"])]),
                     _op(0, "open", "open", "/s/target")), "BROKEN")
    case("a sentinel that failed is BROKEN",
         lambda: run("mapping", _cap([_ev("/s/target", ["ItemCreated"])]),
                     _op(0, "open", "open", "/s/target") + "\n" + _sent(rc=-1)),
         "BROKEN")
    case("a sentinel with no event of its own is BROKEN "
         "(the empty-capture trap)",
         lambda: run("mapping",
                     _cap([_ev("/s/target", ["ItemCreated"])], with_sentinel=False),
                     one_op), "BROKEN")
    case("an empty capture with no sentinel event is BROKEN, not DEAD",
         lambda: run("mapping", _cap([], with_sentinel=False),
                     _op(0, "unlink", "unlink", "/s/missing", rc=-1, err=2)
                     + "\n" + _sent()), "BROKEN")

    # --- attribution, all three directions ---
    def attr(a, b):
        return v_attribution(split_events(load_str(a, "A"))[1],
                             split_events(load_str(b, "B"))[1])
    same = _cap([_ev("/s/target", ["ItemCreated", "ItemIsFile"], eid=1, mono=1)])
    same_other_ids = _cap([_ev("/s/target", ["ItemIsFile", "ItemCreated"],
                               eid=999, mono=77)])
    diff = _cap([_ev("/s/other", ["ItemCreated", "ItemIsFile"])])
    case("attribution reports indistinguishable when only ids/times differ",
         lambda: attr(same, same_other_ids), 1)
    case("attribution reports a difference when paths differ",
         lambda: attr(same, diff), 0)
    case("attribution on an empty capture is BROKEN, not agreement",
         lambda: attr(_cap([], with_sentinel=False),
                      _cap([], with_sentinel=False)), "BROKEN")

    width = max(len(r[1]) for r in rows)
    for verdict, name, got, want in rows:
        print(f"  selftest {verdict}: {name:<{width}}  -> {got!r} "
              f"(wanted {want!r})")
    print(f"  selftest cases: {len(rows)}, failures: {fails}")
    return 1 if fails else 0


def main():
    args = sys.argv[1:]
    if args == ["--selftest"]:
        sys.exit(selftest())
    table = {"soundness": j_soundness, "mapping": j_mapping,
             "coalescing": j_coalescing, "ordering": j_ordering,
             "attribution": j_attribution}
    if not args or args[0] not in table or len(args) != 3:
        print(__doc__)
        sys.exit(2)
    try:
        sys.exit(table[args[0]](args[1], args[2]))
    except Broken as exc:
        print(f"  BROKEN: {exc}")
        sys.exit(2)


if __name__ == "__main__":
    main()
