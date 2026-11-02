#!/usr/bin/env python3
"""Reads the probe engine's lines for one measurement and applies the criteria PREDICTIONS.md fixed
before the runs.

  classify.py judge <transcripts/probe>   one JSON object per target, then the conclusion
  classify.py --selftest

A hand-over counts only where the engine's own thread-order reader called the later write `unordered`
(the one it refuses on): a `verdict` line for the same seq. Hand-overs inside the judged state that a
creation or a join orders, and writes the define declared scratch, have no such line and are not
counted. Each counted hand-over is classified by where the earlier writer W was when the later call
was notified, before the engine answered it:
  A  W in a call the supervising filter does not watch (futex, fcntl, sched_yield, ...): returned
  B  W stopped in a different watched call: returned
  C  W in the same call number, `running`, or anything else: cannot tell
  D  W's /proc entries unreadable (W gone, or no permission)
"""
import json, math, os, re, sys

# aarch64 numbers of the calls src/supervise_linux.zig's common_watched lists.
WATCHED = {64, 68, 66, 70, 287, 71, 285, 56, 437, 38, 276, 35, 34, 37, 36, 45, 46, 82, 83, 57,
           221, 281, 220, 435, 157, 154, 47}
TARGETS = ["dolt", "grafana", "gogs", "gqlgen", "juicefs", "navidrome-restore"]
RECORDED_ONLY = ["etcdutl", "vmrestore"]
P_MIN = 0.2
MISS_MAX = 0.05
TARGETS_NEEDED = 5
CONDVAR_RUNS_NEEDED = 9

HANDOVER = re.compile(r"^handover seq=(\d+) pid=(\d+) w=(\d+) w_nr=(\d+) w_sys=(\S+) w_state=(\S+) t=(\d+) t_nr=(\d+)$")
VERDICT = re.compile(r"^verdict seq=(\d+) pid=(\d+) tid=(\d+) (\w+)$")


def classify(w_nr, w_sys, w_state):
    if w_sys == "unreadable" or w_state == "unreadable":
        return "D"
    if not w_sys.isdigit():
        return "C"
    nr = int(w_sys)
    if nr == w_nr:
        return "C"
    return "B" if nr in WATCHED else "A"


def read_run(text):
    unordered = set()
    hands = []
    for line in text.splitlines():
        m = VERDICT.match(line)
        if m and m.group(4) == "unordered":
            unordered.add(int(m.group(1)))
            continue
        m = HANDOVER.match(line)
        if m:
            hands.append((int(m.group(1)), int(m.group(4)), m.group(5), m.group(6)))
    counts = {"A": 0, "B": 0, "C": 0, "D": 0}
    for seq, w_nr, w_sys, w_state in hands:
        if seq in unordered:
            counts[classify(w_nr, w_sys, w_state)] += 1
    return counts, len(hands)


def target_summary(directory):
    runs = []
    for name in sorted(os.listdir(directory)):
        if re.match(r"run\d\d\.probe$", name):
            runs.append(read_run(open(os.path.join(directory, name)).read()))
    tot = {"A": 0, "B": 0, "C": 0, "D": 0}
    for c, _ in runs:
        for k in tot:
            tot[k] += c[k]
    n = sum(tot.values())
    return {"runs": len(runs), "counted": n, "all_handovers": sum(h for _, h in runs), "classes": tot,
            "runs_all_returned": sum(1 for c, _ in runs if c["C"] == 0 and c["D"] == 0 and sum(c.values()) > 0),
            "runs_with_c": sum(1 for c, _ in runs if c["C"] > 0)}


def conclude(summaries):
    race = summaries.get("ctl-race")
    cond = summaries.get("ctl-condvar")
    out = {}
    p = race["classes"]["C"] / race["counted"] if race and race["counted"] else 0.0
    out["p"] = p
    out["criterion_1"] = p >= P_MIN
    measured, passing = [], []
    for t in TARGETS:
        s = summaries.get(t)
        if not s or s["counted"] == 0 or p <= 0 or (1 - p) ** s["counted"] > MISS_MAX:
            continue
        measured.append(t)
        if s["classes"]["C"] == 0 and s["classes"]["D"] == 0:
            passing.append(t)
    out["measured"] = measured
    out["passing"] = passing
    out["criterion_2"] = len(measured) >= TARGETS_NEEDED and len(passing) >= TARGETS_NEEDED
    out["criterion_3"] = bool(cond) and cond["runs_all_returned"] >= CONDVAR_RUNS_NEEDED
    out["build"] = out["criterion_1"] and out["criterion_2"] and out["criterion_3"]
    out["n_needed"] = math.ceil(math.log(MISS_MAX) / math.log(1 - p)) if 0 < p < 1 else None
    return out


def selftest():
    fails = 0
    def check(name, got, want):
        nonlocal fails
        if got != want:
            print("FAIL %s: got %r, want %r" % (name, got, want)); fails += 1
        else:
            print("ok   %s" % name)
    check("a futex is A", classify(68, "98", "S"), "A")
    check("a different watched call is B", classify(68, "57", "S"), "B")
    check("the same call is C", classify(68, "68", "S"), "C")
    check("running is C", classify(68, "running", "R"), "C")
    check("-1 is C", classify(68, "-1", "S"), "C")
    check("unreadable is D", classify(68, "unreadable", "unreadable"), "D")
    text = "\n".join([
        "verdict seq=3 pid=10 tid=12 unordered",
        "verdict seq=4 pid=10 tid=11 turned",
        "handover seq=3 pid=10 w=11 w_nr=68 w_sys=98 w_state=S t=12 t_nr=68",
        "handover seq=4 pid=10 w=12 w_nr=68 w_sys=68 w_state=S t=11 t_nr=68",
        "handover seq=9 pid=10 w=11 w_nr=68 w_sys=68 w_state=S t=12 t_nr=68",
    ])
    c, h = read_run(text)
    check("only hand-overs the reader called unordered are counted", c, {"A": 1, "B": 0, "C": 0, "D": 0})
    check("every hand-over line is seen", h, 3)
    race = {"counted": 100, "classes": {"A": 70, "B": 0, "C": 30, "D": 0}, "runs_all_returned": 0}
    cond = {"counted": 20, "classes": {"A": 20, "B": 0, "C": 0, "D": 0}, "runs_all_returned": 10}
    good = {t: {"counted": 20, "classes": {"A": 20, "B": 0, "C": 0, "D": 0}, "runs_all_returned": 10} for t in TARGETS}
    check("build when all three hold", conclude(dict(good, **{"ctl-race": race, "ctl-condvar": cond}))["build"], True)
    blind = dict(race, classes={"A": 100, "B": 0, "C": 0, "D": 0})
    check("a probe that never sees an overlap cannot build", conclude(dict(good, **{"ctl-race": blind, "ctl-condvar": cond}))["build"], False)
    few = {t: {"counted": 2, "classes": {"A": 2, "B": 0, "C": 0, "D": 0}, "runs_all_returned": 2} for t in TARGETS}
    check("targets with too few hand-overs are not measured, so they cannot build", conclude(dict(few, **{"ctl-race": race, "ctl-condvar": cond}))["build"], False)
    gone = {t: {"counted": 20, "classes": {"A": 19, "B": 0, "C": 0, "D": 1}, "runs_all_returned": 9} for t in TARGETS}
    check("a D in a target fails it", conclude(dict(gone, **{"ctl-race": race, "ctl-condvar": cond}))["build"], False)
    return fails


def main():
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(1 if selftest() else 0)
    if len(sys.argv) != 3 or sys.argv[1] != "judge":
        print(__doc__); sys.exit(2)
    root = sys.argv[2]
    summaries = {}
    for t in TARGETS + RECORDED_ONLY + ["ctl-race", "ctl-condvar"]:
        d = os.path.join(root, t)
        if os.path.isdir(d):
            summaries[t] = target_summary(d)
            print(json.dumps({"target": t, **summaries[t]}))
    print(json.dumps({"conclusion": conclude(summaries)}))


if __name__ == "__main__":
    main()
