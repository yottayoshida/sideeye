#!/usr/bin/env python3
import collections
import re
import sys

FUNNEL = "spike/outcome-funnel.tsv"
CAMPAIGNS = "spike/outcome-funnel-campaigns.tsv"
WALLS = {"multiple_threads_detected": "threads", "unsupported_syscall_observed": "syscall"}
CROSSED_ON_MAIN = {"duckdb", "dpkg-upgrade"}


def rows(path, width):
    out = []
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        cols = line.rstrip("\n").split("\t")
        if len(cols) != width or cols[0] == "campaign":
            continue
        out.append(cols)
    return out


REASON = re.compile(r"\b([a-z]+(?:_[a-z]+)+)\b")


def reason_from_record(path, target):
    try:
        text = open(path, errors="replace").read()
    except OSError:
        return None
    if path.endswith(".json"):
        m = re.search(r'"unknown_reason"\s*:\s*"([a-z_]+)"', text)
        return m.group(1) if m else None
    if path.endswith(".txt"):
        # Not searched anywhere in the file: a run's own output can quote another refusal.
        m = re.search(r"^UNKNOWN[ \t]+([a-z0-9_]+)", text, re.MULTILINE)
        return m.group(1) if m else None
    # Not the page's first UNKNOWN: a campaign's RESULTS.md quotes every target's refusal,
    # and the first one belongs to whichever target its table lists first.
    first = target.split()[0].lower()
    for line in text.splitlines():
        if line.lower().startswith("| " + first):
            m = REASON.search(line.replace("`", " "))
            return m.group(1) if m else None
    return None


def reason_from_note(note):
    # Not "thread" anywhere: a note can mention threads beside a different refusal.
    if re.search(r"multiple_threads_detected|two writing threads", note):
        return "multiple_threads_detected"
    if "unsupported_syscall_observed" in note:
        return "unsupported_syscall_observed"
    return None


def main():
    order = {c[0]: (c[1], i) for i, c in enumerate(rows(CAMPAIGNS, 5))}
    # Not this run's own rows: the selection is of the funnel as it stood before the run.
    funnel = [r for r in rows(FUNNEL, 9) if r[0] != "dogfood/2026-10-22-walls-v1150"]
    walls, from_note = [], []
    for r in funnel:
        if r[4] != "wall":
            continue
        reason = reason_from_record(r[6], r[1])
        if reason is None:
            reason = reason_from_note(r[8])
            if reason:
                from_note.append(r)
        if reason in WALLS:
            walls.append((r, reason))

    verdicts = collections.defaultdict(list)
    for r in funnel:
        if r[3] in ("pass", "fail"):
            verdicts[r[1].lower()].append(r)

    last_wall = {}
    for r, reason in walls:
        t = r[1].lower()
        if t not in last_wall or order[r[0]] > order[last_wall[t][0][0]]:
            last_wall[t] = (r, reason)

    crossed, on_main, remaining = [], [], []
    for t, (r, reason) in sorted(last_wall.items()):
        later = [v for v in verdicts[t] if v[0] != r[0] and order[v[0]][0] >= order[r[0]][0]]
        if later:
            crossed.append((r, reason, later))
        elif t in CROSSED_ON_MAIN:
            on_main.append((r, reason))
        else:
            remaining.append((r, reason))

    print("wall rows: %d (threads %d, syscall %d; %d of them named only by the note)" % (
        len(walls), sum(1 for _, x in walls if x.startswith("multiple")),
        sum(1 for _, x in walls if x.startswith("unsupported")), len([w for w in walls if w[0] in from_note])))
    print("targets: %d = later verdict %d + crossed on main %d + remaining %d" % (
        len(last_wall), len(crossed), len(on_main), len(remaining)))
    print("\n## remaining\ntarget\twall\tcampaign\tevidence")
    for r, reason in remaining:
        print("\t".join([r[1], WALLS[reason], r[0], r[6]]))
    print("\n## crossed on main (#970)\ntarget\twall\tcampaign\tevidence")
    for r, reason in on_main:
        print("\t".join([r[1], WALLS[reason], r[0], r[6]]))
    print("\n## later verdict\ntarget\twall\tlast wall\tverdicts after it")
    for r, reason, later in crossed:
        print("\t".join([r[1], WALLS[reason], r[0], ", ".join("%s %s" % (v[0], v[3]) for v in later)]))
    print("\n## wall rows read from the note, not the record\ncampaign\ttarget\tnote")
    for r in from_note:
        print("\t".join([r[0], r[1], r[8][:100]]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
