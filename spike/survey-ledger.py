#!/usr/bin/env python3
"""Print the whole-product survey ledger's counts by direction and by surface (#937).

Usage: survey-ledger.py [spike/survey-ledger.tsv] [--issues <gh issue list JSON>]
       survey-ledger.py --selftest

Without `--issues` it asks `gh` for every issue of the repository it runs in.

Exit 0 when the ledger reads whole and every issue in it was among those read; 2 when it does
not read whole (a survey's range missing an issue, ranges that overlap or run backwards, an
issue outside every survey, an unknown direction or surface), when an issue of the ledger was
not among those read, when `gh` or the `--issues` file fails, or when the arguments are wrong.
"""

import json
import re
import subprocess
import sys
from collections import Counter

DIRECTIONS = ("silent", "over-refusal", "other")
SURFACES = ("apparatus", "ci", "cli", "define", "docs", "engine", "evidence", "mcp", "oracle",
            "report", "research", "shim", "supervise", "workdir")
# Anchored to a line's start: the prose of an issue can name `Filed-under:` before its own line.
FILED_UNDER = re.compile(r"^[Ff]iled[-_ ][Uu]nder:?[^A-Za-z]{0,6}([a-z-]+)", re.M)


class LedgerError(Exception):
    pass


def parse(text):
    surveys, issues = [], {}
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if cols[0] == "survey" and len(cols) >= 5:
            surveys.append({"date": cols[1], "commit": cols[2], "first": int(cols[3]), "last": int(cols[4])})
        elif cols[0] == "issue" and len(cols) >= 4:
            num = int(cols[1])
            if num in issues:
                raise LedgerError("line %d: issue %d is listed twice" % (n, num))
            if cols[2] not in DIRECTIONS:
                raise LedgerError("line %d: issue %d has direction %r, not one of %s" % (n, num, cols[2], ", ".join(DIRECTIONS)))
            if cols[3] not in SURFACES:
                raise LedgerError("line %d: issue %d has surface %r, not one of %s" % (n, num, cols[3], ", ".join(SURFACES)))
            issues[num] = {"direction": cols[2], "surface": cols[3]}
        else:
            raise LedgerError("line %d: neither a survey row nor an issue row" % n)
    if not surveys:
        raise LedgerError("no survey rows")
    covered = set()
    for s in surveys:
        if s["first"] > s["last"]:
            raise LedgerError("survey %s: its range runs backwards" % s["date"])
        shared = covered & set(range(s["first"], s["last"] + 1))
        if shared:
            raise LedgerError("survey %s: its range shares issues %s with an earlier survey's" % (s["date"], " ".join(map(str, sorted(shared)))))
        missing = [k for k in range(s["first"], s["last"] + 1) if k not in issues]
        if missing:
            raise LedgerError("survey %s: issues %s are in its range and not in the ledger" % (s["date"], " ".join(map(str, missing))))
        covered.update(range(s["first"], s["last"] + 1))
    stray = sorted(set(issues) - covered)
    if stray:
        raise LedgerError("issues %s are in no survey's range" % " ".join(map(str, stray)))
    return surveys, issues


def filed_under(body):
    found = FILED_UNDER.findall(body or "")
    return found[-1] if found else None


def labels_of(read, issues):
    labels = {i["number"]: filed_under(i.get("body")) for i in read if i.get("number") in issues}
    unread = sorted(set(issues) - set(labels))
    if unread:
        raise LedgerError("%d of the ledger's issues were not among the %d read (first: #%d): another repository, or a partial read" % (len(unread), len(read), unread[0]))
    return labels


def report(surveys, issues, labels):
    out = ["survey      commit     filed  silent  over-refusal  other"]
    for s in surveys:
        nums = range(s["first"], s["last"] + 1)
        c = Counter(issues[k]["direction"] for k in nums)
        out.append("%-11s %-10s %5d  %6d  %12d  %5d" % (s["date"], s["commit"], len(nums), c["silent"], c["over-refusal"], c["other"]))
    out.append("")
    for direction in ("silent", "over-refusal"):
        out.append("%s by surface:" % direction)
        for s in surveys:
            nums = range(s["first"], s["last"] + 1)
            c = Counter(issues[k]["surface"] for k in nums if issues[k]["direction"] == direction)
            out.append("  %-11s %s" % (s["date"], ", ".join("%s %d" % kv for kv in sorted(c.items())) or "-"))
    disagree = sorted(k for k, v in issues.items() if labels.get(k) == "wrong-verdict" and v["direction"] != "silent")
    out.append("")
    unlabelled = sorted(k for k in issues if labels.get(k) is None)
    out.append("filed wrong-verdict, and not a silent verdict in the ledger: %s" % (" ".join("#%d (%s)" % (k, issues[k]["direction"]) for k in disagree) or "none"))
    out.append("no Filed-under line: %d issue(s)" % len(unlabelled))
    return "\n".join(out), disagree


def gh_issues():
    raw = subprocess.run(
        ["gh", "issue", "list", "--state", "all", "--limit", "5000", "--json", "number,body"],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(raw)


def selftest():
    ledger = "\n".join([
        "# a comment",
        "survey\t2026-01-01\tabc\t1\t4\tfirst",
        "survey\t2026-02-01\tdef\t5\t6\tsecond",
        "issue\t1\tsilent\tshim\t",
        "issue\t2\tsilent\toracle\t",
        "issue\t3\tover-refusal\toracle\t",
        "issue\t4\tother\tdocs\t",
        "issue\t5\tover-refusal\tshim\t",
        "issue\t6\tsilent\tmcp\t",
    ])
    read = [
        {"number": 1, "body": "x\n\nFiled-under: wrong-verdict — silent"},
        {"number": 2, "body": "Filed-under: broken-promise — silent under another\n\nA later note on the `Filed-under: reach` line"},
        {"number": 3, "body": "Filed-under: wrong-verdict — but it refuses"},
        {"number": 4, "body": "no line"},
        {"number": 5, "body": "Filed-under: hang — first\n\nFiled-under: broken-promise — the last line is the one read"},
        {"number": 6, "body": "Filed-under: reach — x"},
    ]
    fails = []
    surveys, issues = parse(ledger)
    labels = labels_of(read, issues)
    text, disagree = report(surveys, issues, labels)
    for want, what in [
        ("2026-01-01  abc            4       2             1      1", "the first survey's counts, silent and over-refusal unequal"),
        ("2026-02-01  def            2       1             1      0", "the second survey's counts"),
        ("  2026-01-01  oracle 1, shim 1", "silent by surface in the first survey"),
        ("  2026-01-01  oracle 1\n", "over-refusal by surface in the first survey"),
        ("no Filed-under line: 1 issue(s)", "the issue with no line counted"),
    ]:
        if want not in text + "\n":
            fails.append("%s:\n%s" % (what, text))
    if labels.get(5) != "broken-promise":
        fails.append("of two Filed-under lines the last is read, got %r" % labels.get(5))
    if labels.get(2) != "broken-promise":
        fails.append("a body naming `Filed-under:` in its prose is read by its own line, got %r" % labels.get(2))
    if disagree != [3]:
        fails.append("only a wrong-verdict issue the ledger does not call silent is listed, got %s" % disagree)
    try:
        labels_of([i for i in read if i["number"] != 4], issues)
        fails.append("accepted a read missing one of the ledger's issues")
    except LedgerError:
        pass
    for bad, why in [
        (ledger.replace("issue\t4\tother\tdocs\t\n", ""), "a survey's range missing an issue"),
        (ledger + "\nissue\t9\tother\tdocs\t", "an issue outside every survey"),
        (ledger.replace("over-refusal\toracle", "refusal\toracle"), "an unknown direction"),
        (ledger.replace("other\tdocs", "other\tdoc"), "an unknown surface"),
        (ledger.replace("silent\tmcp", "silent\t"), "an empty surface"),
        (ledger + "\nissue\t1\tother\tdocs\t", "an issue listed twice"),
        (ledger.replace("def\t5\t6", "def\t4\t6"), "two ranges sharing an issue"),
        (ledger.replace("abc\t1\t4", "abc\t1\t6").replace("def\t5\t6", "def\t6\t5"), "a range that runs backwards"),
        ("# nothing but a comment", "no survey rows"),
    ]:
        try:
            parse(bad)
            fails.append("accepted a ledger with " + why)
        except LedgerError:
            pass
    real = open(__file__.rsplit("/", 1)[0] + "/survey-ledger.tsv").read()
    try:
        parse(real)
    except LedgerError as e:
        fails.append("the committed ledger: %s" % e)
    for f in fails:
        print("FAIL " + f)
    if fails:
        print("selftest: %d case(s) failed" % len(fails))
        return 1
    print("selftest: the counts by direction and surface, the one-way disagreement, the anchored label, and nine malformed ledgers behave; the committed ledger reads whole")
    return 0


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    issues_file, rest = None, []
    it = iter(argv)
    for a in it:
        if a == "--issues":
            issues_file = next(it, None)
            if issues_file is None:
                print(__doc__)
                return 2
        else:
            rest.append(a)
    if len(rest) > 1:
        print(__doc__)
        return 2
    path = rest[0] if rest else __file__.rsplit("/", 1)[0] + "/survey-ledger.tsv"
    try:
        surveys, issues = parse(open(path).read())
    except (LedgerError, ValueError) as e:
        print("FAIL %s: %s" % (path, e))
        return 2
    try:
        read = json.load(open(issues_file)) if issues_file else gh_issues()
        labels = labels_of(read, issues)
    except (OSError, ValueError, subprocess.CalledProcessError, LedgerError) as e:
        print("FAIL reading the issues: %s" % e)
        return 2
    print(report(surveys, issues, labels)[0])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
