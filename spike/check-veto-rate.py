#!/usr/bin/env python3
"""The veto's rate table is recomputed from the transcripts, not transcribed (#293).

`spike/fsevents/RESULTS.md` makes that promise — "Every number below is recomputable
from them" — but about `survey-veto-1..3.txt`, the 55-run transcripts, and it was made
by #311. #433 added the rate table and the 330-run transcripts and made **no** such
promise about them. So this is not a hand-kept promise becoming a command: **it is a
new obligation**, taken because ADR 0035 rests a decision on those figures, and the
rate section of the record now carries the sentence to match.

WHAT THIS COMPARES. Two real things, neither transcribed here: the per-mode
`name:outside/runs` block each transcript prints, and the markdown table in
RESULTS.md. Every figure in the table — the per-set counts, the per-set Wilson
intervals, the pooled counts and interval, and the chi-squared homogeneity statistic
the prose quotes — is derived from the first and asserted against the second.

WHY THE TRANSCRIPT'S OWN SUMMARY AND NOT ITS RUN BLOCKS. The survey prints at most
three run blocks per mode while counting all thirty, so counting `-- mode run N`
headers gives 5 where the truth is 32. The per-mode block is the transcript's own
tally and is checked for internal consistency instead: the per-mode denominators must
sum to the run total, and the per-mode outside counts must equal runs-minus-held. A
transcript failing that is BROKEN, not a disagreement — it means the tally and the
runs it summarises have come apart, and neither side can then be believed.

WHAT THIS DOES NOT DO. The unrelated bucket is read over the outside runs L7b PRINTS,
which is 16 of the 97 that were classified: the survey prints at most three blocks per
mode and L7b carries no bucket tally, so the other 81 classifications exist nowhere in
the committed record. The number printed beside the verdict says so rather than leaving
a reader to assume the sets. It does not re-run the survey; the transcripts are the record
of runs that happened on one machine on one day and re-running them would produce
different counts, which is the whole reason three sets were taken. It says nothing
about whether the relation being measured is the right one — that is the ruling, and
the ruling is in the ADR. And it checks the table plus one sentence — the chi-squared
one, which is pinned by value and by wording, so rewording it goes BROKEN. Everything
else in the prose is outside this: a sentence that misdescribes a figure it does not
restate is not read here.

Fail-closed: exit 2 (BROKEN) when a transcript or the table cannot be parsed, when a
set is internally inconsistent, or when the table has fewer rows than there are
transcripts. Never read a 2 as a pass.

Usage:
  check-veto-rate.py [<results.md>] [<transcript-dir>]
  check-veto-rate.py --selftest

sunset: delete this when the fsevents record is retired, or when the ruling it guards
stops quoting figures. It exists because a decision cites numbers; if nothing cites
them, nothing needs to hold them.
"""

import math
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

Z = 1.959963985  # two-sided 95%
DEFAULT_RESULTS = "spike/fsevents/RESULTS.md"
DEFAULT_DIR = "spike/fsevents"
SETS = (1, 2, 3)
POOL_EXCLUDES = "link"  # held out of the pool: it is near-certain and the rest are rare


def broken(msg):
    print(f"BROKEN {msg}")
    print("       could not read what it needs — never read a 2 as a pass")
    sys.exit(2)


def wilson(k, n):
    """Wilson score interval, as percentages."""
    if n <= 0:
        broken("a Wilson interval was asked for over zero runs")
    p = k / n
    d = 1 + Z * Z / n
    centre = (p + Z * Z / (2 * n)) / d
    half = Z * math.sqrt(p * (1 - p) / n + Z * Z / (4 * n * n)) / d
    return (max(0.0, centre - half) * 100, min(1.0, centre + half) * 100)


def sections(text):
    """Each L7 leg's lines, keyed by leg name, in the order they appear."""
    marks = [(m.group(1), m.start()) for m in re.finditer(r"^\s*-- (L7[a-z]):", text, re.M)]
    out = {}
    for i, (name, start) in enumerate(marks):
        end = marks[i + 1][1] if i + 1 < len(marks) else len(text)
        out[name] = text[start:end]
    return out


def unrelated_pair(path, text):
    """The `unrelated` bucket over the outside runs L7b PRINTS, the number of those, and
    the planted neighbour in L7d that makes a zero a measurement rather than an unreached
    branch.

    The denominator is returned because it is not the run count and not the outside
    count. `survey.sh` prints a run block only for the first three outside runs of each
    mode, so a set with 32 outside runs puts 5 of them in the transcript; the other 27
    classifications were made and are not recorded anywhere. A caller that reports this
    zero without the denominator is claiming 97 runs' worth of evidence from 16.

    L7b prints no bucket tally, so this is the whole of what the committed transcripts
    can support. Reading it from a tally would be strictly better and would need the
    survey re-run, which would produce different runs."""
    legs = sections(text)
    for leg in ("L7b", "L7d"):
        if leg not in legs:
            broken(f"{path.name}: no {leg} section, so the unrelated bucket has no control")
    printed = len(re.findall(r"^\s*-- \S+ run \d+\s*$", legs["L7b"], re.M))
    return (legs["L7b"].count("unrelated to the account"), printed,
            legs["L7d"].count("unrelated to the account"))


def read_set(path):
    """The transcript's own per-mode tally, checked against its own run total."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        broken(f"cannot read {path}: {e}")
    per = {m.group(1): (int(m.group(2)), int(m.group(3)))
           for m in re.finditer(r"^\s+([a-z-]+):(\d+)/(\d+)$", text, re.M)}
    if len(per) < 5:
        broken(f"{path.name}: parsed only {len(per)} per-mode rows; the block moved or the parse is wrong")
    held = re.search(r"containment held in (\d+)/(\d+) runs", text)
    if not held:
        broken(f"{path.name}: no 'containment held in N/M runs' line")
    h, runs = int(held.group(1)), int(held.group(2))
    if sum(n for _, n in per.values()) != runs:
        broken(f"{path.name}: per-mode denominators sum to "
               f"{sum(n for _, n in per.values())}, the run total says {runs}")
    if runs - h != sum(k for k, _ in per.values()):
        broken(f"{path.name}: {runs - h} runs were not held but the per-mode counts "
               f"add to {sum(k for k, _ in per.values())}")
    if POOL_EXCLUDES not in per:
        broken(f"{path.name}: no '{POOL_EXCLUDES}' row, so the pool cannot be formed")
    return per, unrelated_pair(path, text)


def read_table(path, text):
    """The rows of the rate table in the record, addressed by their leading label.

    Takes the text rather than the path: the chi-squared sentence is read from the same
    document and reading it twice would let two halves of one check disagree about what
    the file says, which is the shape this whole check exists to close."""
    rows = {}
    # The link cell carries a bare `k/n` on the per-set rows and `k/n = P% [lo%, hi%]`
    # on the pooled one. An earlier version skipped that tail with `[^|]*`, which meant
    # two published figures sat inside the guarded table and were not guarded: measured,
    # rewriting the pooled interval to [9.91%, 12.00%] left this green.
    row = re.compile(
        r"^\|\s*\**(\w+)\**\s*\|\s*\**(\d+)/(\d+)"
        r"(?:\s*=\s*([\d.]+)%\s*\[([\d.]+)%,\s*([\d.]+)%\])?\s*\**\s*\|"
        r"\s*\**(\d+)/(\d+)\**\s*\|"
        r"\s*\**([\d.]+)%\s*\[([\d.]+)%,\s*([\d.]+)%\]\**\s*\|", re.M)
    for m in row.finditer(text):
        if m.group(1) in rows:
            broken(f"{path}: two table rows are labelled '{m.group(1)}'; which one is guarded "
                   f"would be decided by document order, which is not a decision")
        link_stats = None
        if m.group(4) is not None:
            link_stats = (float(m.group(4)), float(m.group(5)), float(m.group(6)))
        rows[m.group(1)] = dict(
            link=(int(m.group(2)), int(m.group(3))), link_stats=link_stats,
            other=(int(m.group(7)), int(m.group(8))),
            pct=float(m.group(9)), lo=float(m.group(10)), hi=float(m.group(11)))
    return rows


def main():
    argv = [a for a in sys.argv[1:] if a != "--selftest"]
    results = pathlib.Path(argv[0]) if argv else pathlib.Path(DEFAULT_RESULTS)
    tdir = pathlib.Path(argv[1]) if len(argv) > 1 else pathlib.Path(DEFAULT_DIR)

    parsed = {n: read_set(tdir / f"survey-veto-rate-{n}.txt") for n in SETS}
    sets = {n: p for n, (p, _) in parsed.items()}
    try:
        page = results.read_text(encoding="utf-8")
    except OSError as e:
        broken(f"cannot read {results}: {e}")
    table = read_table(results, page)
    for label in [str(n) for n in SETS] + ["all"]:
        if label not in table:
            broken(f"{results}: no table row labelled '{label}'; the table moved or its shape changed")

    fails = []

    def cmp(what, got, want):
        if got != want:
            fails.append(f"{what}: recomputed {got}, the record says {want}")

    pool_k = pool_n = link_k = link_n = 0
    counts = []
    for n in SETS:
        per = sets[n]
        lk, ln = per[POOL_EXCLUDES]
        ok = sum(k for m, (k, _) in per.items() if m != POOL_EXCLUDES)
        on = sum(d for m, (_, d) in per.items() if m != POOL_EXCLUDES)
        counts.append((ok, on))
        link_k += lk; link_n += ln; pool_k += ok; pool_n += on
        r = table[str(n)]
        if r["link_stats"] is not None:
            # The same shape as the pooled cell one row down, which sat unguarded until
            # review found it. A figure published inside the guarded table has to be
            # guarded or absent; a third state is how the first version passed.
            slo, shi = wilson(lk, ln)
            cmp(f"set {n} link rate", round(100 * lk / ln, 2), r["link_stats"][0])
            cmp(f"set {n} link interval", (round(slo, 2), round(shi, 2)),
                (r["link_stats"][1], r["link_stats"][2]))
        cmp(f"set {n} link", (lk, ln), r["link"])
        cmp(f"set {n} pool", (ok, on), r["other"])
        lo, hi = wilson(ok, on)
        cmp(f"set {n} rate", round(100 * ok / on, 2), r["pct"])
        cmp(f"set {n} interval", (round(lo, 2), round(hi, 2)), (r["lo"], r["hi"]))

    # The unrelated bucket read zero on every set, and that zero is only a measurement
    # because L7d's planted neighbour walked through the same branch in the same run.
    seen = unseen = 0
    for n in SETS:
        b, printed, d = parsed[n][1]
        outside = sum(k for k, _ in sets[n].values())
        seen += printed; unseen += outside - printed
        if b != 0:
            fails.append(f"set {n} unrelated: L7b printed {b} unrelated classification(s) "
                         f"over the {printed} outside runs it records")
        if d < 1:
            fails.append(f"set {n} control: L7d planted a neighbour and the unrelated bucket "
                         f"did not see it ({d}) — the zero above is then an unreached branch, "
                         f"not a measurement")

    a = table["all"]
    cmp("pooled link", (link_k, link_n), a["link"])
    if a["link_stats"] is None:
        broken(f"{results}: the pooled row's link cell carries no `= P% [lo%, hi%]`; the "
               f"record publishes those figures, so a table without them is a table this "
               f"cannot hold")
    llo, lhi = wilson(link_k, link_n)
    cmp("pooled link rate", round(100 * link_k / link_n, 2), a["link_stats"][0])
    cmp("pooled link interval", (round(llo, 2), round(lhi, 2)),
        (a["link_stats"][1], a["link_stats"][2]))
    cmp("pooled pool", (pool_k, pool_n), a["other"])
    lo, hi = wilson(pool_k, pool_n)
    cmp("pooled rate", round(100 * pool_k / pool_n, 2), a["pct"])
    cmp("pooled interval", (round(lo, 2), round(hi, 2)), (a["lo"], a["hi"]))

    # The homogeneity statistic the prose quotes, recomputed from the same counts. Each
    # set carries its own denominator rather than an average of them: an earlier version
    # used `pool_n // len(SETS)`, which on unequal denominators produces a number that is
    # neither the record's nor the right one, and then reports the record as wrong.
    p = pool_k / pool_n
    chi = sum((k - n * p) ** 2 / (n * p) + ((n - k) - n * (1 - p)) ** 2 / (n * (1 - p))
              for k, n in counts)
    # Whitespace-flexible between every word: this record hard-wraps its prose, so the
    # sentence straddles a line break and a literal-space pattern silently finds nothing.
    quoted = re.search(
        r"chi-squared\s+test\s+of\s+homogeneity\s+over\s+the\s+three\s+counts\s+gives\s+([\d.]+)",
        page)
    if not quoted:
        broken(f"{results}: the chi-squared sentence is not where this expects it")
    cmp("chi-squared", round(chi, 2), float(quoted.group(1)))

    if fails:
        print("FAIL the record's figures are not what the transcripts produce:")
        for f in fails:
            print(f"     {f}")
        return 1
    print(f"ok   the rate table is reproduced from {len(SETS)} transcripts: "
          f"link {link_k}/{link_n}, pool {pool_k}/{pool_n} = "
          f"{100 * pool_k / pool_n:.2f}% [{lo:.2f}%, {hi:.2f}%], chi-squared {chi:.2f}")
    print(f"     unrelated: zero over the {seen} outside runs the transcripts print; "
          f"{unseen} more were classified and not recorded, and L7d's planted neighbour "
          f"is what makes the printed zero a measurement")
    return 0


def selftest():
    """Both sides falsified: a changed figure in the record, and a changed count in a
    transcript. A checker that only ever reads agreement is indistinguishable from one
    that always says yes."""
    root = pathlib.Path(__file__).resolve().parent.parent
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        shutil.copytree(root / DEFAULT_DIR, tmp / "fsevents")
        shutil.copy(root / DEFAULT_RESULTS, tmp / "RESULTS.md")

        def run(label, expect):
            r = subprocess.run([sys.executable, __file__, str(tmp / "RESULTS.md"),
                                str(tmp / "fsevents")], capture_output=True, text=True)
            got = "red" if r.returncode == 1 else ("green" if r.returncode == 0 else f"broken({r.returncode})")
            print(f"  {label}: {got}" + ("" if got == expect else f"  <-- wanted {expect}"))
            for line in r.stdout.splitlines()[:3]:
                print(f"      | {line}")
            return got == expect

        ok &= run("untouched copy", "green")

        page = (tmp / "RESULTS.md").read_text()
        (tmp / "RESULTS.md").write_text(page.replace("| **all** | **90/90 = 100% [95.91%, 100%]** | **7/900** | **0.78% [0.38%, 1.60%]** |",
                                                     "| **all** | **90/90 = 100% [95.91%, 100%]** | **7/900** | **0.79% [0.38%, 1.60%]** |"))
        ok &= run("one digit changed in the record", "red")
        (tmp / "RESULTS.md").write_text(page)

        t = tmp / "fsevents" / "survey-veto-rate-2.txt"
        s = t.read_text()
        t.write_text(s.replace("      link:30/30", "      link:29/30"))
        ok &= run("one count changed in a transcript", "broken(2)")

        # The zero has to be a measurement, so remove what makes it one.
        t.write_text(s.replace("-- L7d: positive control for the unrelated bucket",
                               "-- L7z: positive control removed"))
        ok &= run("the unrelated bucket loses its positive control", "broken(2)")
        t.write_text(s)

        # The pooled row's own percentage and interval, which an earlier version of the
        # table pattern skipped past. Both had to be seen red before they could be said
        # to be held.
        for before, after, label in (
            ("**90/90 = 100% [95.91%, 100%]**", "**90/90 = 100% [9.91%, 12.00%]**",
             "the pooled link interval changed"),
            ("**90/90 = 100% [95.91%, 100%]**", "**90/90 = 3% [95.91%, 100%]**",
             "the pooled link percentage changed"),
        ):
            (tmp / "RESULTS.md").write_text(page.replace(before, after))
            ok &= run(label, "red")
        (tmp / "RESULTS.md").write_text(page)

        # An unrelated classification inside a printed block: the bucket check has to
        # notice one when there is one, or its zero says nothing.
        t.write_text(s.replace(
            "containment: outside, ancestor of an account path:",
            "containment: outside, unrelated to the account:", 1))
        ok &= run("an unrelated path appears in a printed block", "red")

    print("== self-test " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
