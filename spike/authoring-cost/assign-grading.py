#!/usr/bin/env python3
"""Hand a run's revisions to a grader under shuffled ids, and write the sheet's map (#618).

    assign-grading.py <run-dir> <grader-letter>

Prints the brief to give that grader (`grader-prompt.md` with the target and the id list
substituted) and creates `grades/<letter>.tsv` carrying only its `# map` lines, which the
grader's verdicts are appended to.

Two things this exists to make mechanical rather than remembered:

* **The shuffle is per grader and recorded.** The two graders see the same revisions under
  different ids and in a different order, so a verdict that follows position rather than
  content shows up as a disagreement the map explains. The order is seeded by the run name and
  the grader's letter, so re-running this prints the same assignment instead of a new one.
* **The map is written by the apparatus.** `audit.py` refuses a sheet without one — it compares
  revisions, not labels — and a map typed by hand afterwards is a map that can be typed wrong.

The ids are letters far apart in the alphabet rather than 1..N, because a grader handed `1, 2,
3` reads an order into them whatever the brief says.
"""

import hashlib
import json
import sys
from pathlib import Path

IDS = ["G", "K", "R", "W", "B", "M", "T", "Z", "D", "P", "V", "J"]


def selftest():
    """The two properties this script is trusted for, on scratch directories."""
    import tempfile

    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        run = Path(tmp) / "fossil"
        (run / "revisions").mkdir(parents=True)
        for n, body in ((1, "a = 1\n"), (2, "b = 2\n")):
            (run / "revisions" / f"{n:02d}.toml").write_text(body, encoding="utf-8")
        (run / "meta.json").write_text('{"target": "fossil"}', encoding="utf-8")

        # 1. The draw is a function of (run, grader) and nothing else, so re-running prints
        #    the same assignment rather than a fresh one.
        main([__file__, str(run), "A"])
        first = (run / "grades" / "a.tsv").read_text(encoding="utf-8")
        main([__file__, str(run), "A"])
        if (run / "grades" / "a.tsv").read_text(encoding="utf-8") != first:
            print("FAIL selftest: re-drawing an ungraded assignment changed it")
            failures += 1
        else:
            print("ok   an assignment is a function of (run, grader): re-drawing is the same")

        # 2. A sheet that carries verdicts is never overwritten. Without this, re-drawing
        #    deletes the grader's answers and the run drops to `ungraded` with nothing
        #    refusing — while the disposition tool beside it refuses a second decision.
        sheet = run / "grades" / "a.tsv"
        sheet.write_text(first + "G\tsemantically valid\tnone\tclaim 1\n", encoding="utf-8")
        graded = sheet.read_text(encoding="utf-8")
        rc = main([__file__, str(run), "A"])
        if rc == 0 or sheet.read_text(encoding="utf-8") != graded:
            print("FAIL selftest: a graded sheet was overwritten")
            failures += 1
        else:
            print("ok   a sheet carrying verdicts is refused, not overwritten")

    if failures:
        print(f"FAIL {failures} selftest case(s)")
        return 1
    print("ok   assign-grading selftest: 2 case(s)")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) != 3:
        print(__doc__)
        return 2
    # Resolved, because the listing below is written relative to the repository root and a
    # relative argument makes that subtraction impossible rather than wrong.
    run = Path(argv[1]).resolve()
    letter = argv[2].upper()
    here = Path(__file__).resolve().parent

    revisions = sorted(
        (p for p in (run / "revisions").glob("*.toml")), key=lambda p: int(p.stem)
    )
    if not revisions:
        print(f"assign-grading: {run}/revisions holds no snapshot", file=sys.stderr)
        return 1
    if len(revisions) > len(IDS):
        print(f"assign-grading: {len(revisions)} revisions, only {len(IDS)} ids", file=sys.stderr)
        return 1

    # Deterministic per (run, grader): the same assignment every time this is asked for.
    seed = hashlib.sha256(f"{run.name}\t{letter}".encode()).digest()
    order = sorted(range(len(revisions)), key=lambda i: seed[i % len(seed)] * 256 + i)

    # The target is READ from meta.json, never derived from the directory name. A run may be
    # named anything — `dos2unix-measured` exists because `dos2unix/` was already taken by the
    # void run — and a name-derived target hands the grader the path of a card that does not
    # exist. The launcher already recorded which package ran; deriving it a second way is the
    # second copy that goes wrong alone.
    target = json.loads((run / "meta.json").read_text(encoding="utf-8"))["target"]
    pairs = [(IDS[pos], revisions[idx]) for pos, idx in enumerate(order)]

    grades = run / "grades"
    grades.mkdir(exist_ok=True)
    sheet = grades / f"{letter.lower()}.tsv"
    # Never over a sheet that already carries verdicts. The write below is unconditional, and
    # the docstring above calls re-running safe — which it is, right up until the grader has
    # answered: then it deletes the verdicts, leaves a map-only sheet that `audit.py` reads as
    # `ungraded`, and a run drops from `graded` back to ungraded with nothing refusing. The
    # disposition tool already refuses a second decision; grading had no such stop.
    if sheet.exists():
        verdicts = [
            line
            for line in sheet.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("#")
        ]
        if verdicts:
            print(
                f"assign-grading: {sheet} already carries {len(verdicts)} verdict(s). "
                "Re-drawing would delete them. Move or remove the sheet deliberately if this "
                "run is being re-graded.",
                file=sys.stderr,
            )
            return 1
    lines = [f"# grader {letter}, run {run.name}, assignment seeded by (run, grader)"]
    lines += [f"# map\t{gid}\t{p.stem}" for gid, p in pairs]
    sheet.write_text("\n".join(lines) + "\n", encoding="utf-8")

    brief = (here / "grader-prompt.md").read_text(encoding="utf-8")
    brief = brief.split("---\n", 1)[1].rsplit("---\n", 1)[0]
    def shown(p):
        # Repository-relative where possible, absolute otherwise: the selftest builds its run
        # in a scratch directory, and a path outside the repo is not an error here.
        try:
            return p.relative_to(here.parent.parent)
        except ValueError:
            return p

    listing = "\n".join(f"   - 与え ID `{gid}` = `{shown(p)}`" for gid, p in pairs)
    print(
        brief.replace("REPO_PATH", str(here.parent.parent))
        .replace("TARGET", target)
        .replace("   GIVEN_IDS", listing)
    )
    print(f"\n(sheet prepared: {shown(sheet)})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
