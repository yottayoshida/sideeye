"""Read every exploration's text report and JSON under OUT, per mode and subject, as PREDICTIONS.md fixes.

A run has hand-overs when its report's processes line counts any, or when it was refused
multiple_threads_detected (a hand-over the rule did not take refuses in the world that met it, whose
counts the recording's line does not carry). A run with hand-overs succeeds when it was not refused
multiple_threads_detected. Prints one JSON line per mode and subject.
"""
import json, os, re, sys

out = sys.argv[1]
line_re = re.compile(r"of (\d+) hand-over\(s\) .*?, (\d+) taken as ordered .*? and (\d+) not \((\d+) with another call waiting, (\d+) with the earlier writer in a watched call, (\d+) still running, (\d+) unreadable\)")
for mode in ("no-oracle", "oracle"):
    root = os.path.join(out, mode)
    if not os.path.isdir(root):
        continue
    for subject in sorted(os.listdir(root)):
        runs = sorted(f[:-4] for f in os.listdir(os.path.join(root, subject)) if f.endswith(".out"))
        row = {"mode": mode, "subject": subject, "runs": len(runs), "with_handovers": 0, "succeeded": 0,
               "verdicts": {}, "handovers": 0, "taken": 0, "not": [0, 0, 0, 0]}
        for r in runs:
            text = open(os.path.join(root, subject, r + ".out"), errors="replace").read()
            head = next((l for l in text.splitlines() if re.match(r"^(PASS|FAIL|UNKNOWN|SETUP ERROR)", l)), "none")
            verdict = " ".join(head.split()[:2])
            row["verdicts"][verdict] = row["verdicts"].get(verdict, 0) + 1
            m = line_re.search(text)
            threads = "multiple_threads_detected" in head
            if m:
                h, t, nt, q, b, rn, u = (int(x) for x in m.groups())
                row["handovers"] += h; row["taken"] += t
                for k, v in enumerate((q, b, rn, u)):
                    row["not"][k] += v
            if threads or (m and int(m.group(1)) > 0):
                row["with_handovers"] += 1
                if not threads:
                    row["succeeded"] += 1
        print(json.dumps(row, sort_keys=True))
