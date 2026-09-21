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


def scripts_for(run, revisions):
    """Map revision stem -> the scripts in force at that revision, latest capture each.

    `revisions/scripts/index.tsv` carries one row per capture (`MM  observed  sha256  path
    revision  note`), and a script can be rewritten several times while the define file stands still.
    A grader is handed the LAST capture of each name under that revision — "the content it had
    when that define was current" — rather than the whole edit history, which would be an
    ordering hint inside a sheet whose order is deliberately shuffled.

    `revisions` is the caller's own list of revision stems rather than a second glob of the
    same directory: two places deciding which revisions exist is two places that can disagree.

    A run recorded before #639 has no `scripts/` at all; that is the four published runs, and
    it reads as "no scripts" rather than as an error.
    """
    index = run / "revisions" / "scripts" / "index.tsv"
    if not index.exists():
        return {}
    captures = []   # (revision, basename, snapshot path), in observation order
    withheld = {}   # revision -> [(basename, why)] for captures the watcher did not copy
    for line in index.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        row = line.split("\t")
        if len(row) < 5:
            continue
        mm, path, rev = row[0], row[3], row[4]
        # A capture the watcher recorded but did not copy (over the size ceiling) carries a
        # note in its own column. It is evidence that something was written, not material a
        # grader can read, so it is not offered.
        if len(row) > 5 and row[5].strip():
            # Not offered as material — but SAID, because "there was no such file" and "there
            # was one and it is not here" are different things to a grader deciding whether a
            # checker can fail.
            withheld.setdefault(rev, []).append((path.rsplit("/", 1)[-1], row[5].strip()))
            continue
        # `isdigit` before `int`: `int(" 1")` is 1, so a stray space in a hand-edited index
        # would otherwise be read as a revision it is not.
        if not rev.isdigit():
            continue
        snap = run / "revisions" / "scripts" / f"{mm}.{path.rsplit('/', 1)[-1]}"
        if snap.exists():
            # Keyed by the path the subject wrote, not the basename: two define directories
            # can each hold a `check.sh`, and matching on the name alone hands one define's
            # grader the other's checker — worse than handing over nothing, since `vacuous
            # checker` would then be decided against a file the revision never named.
            captures.append((rev, path, snap))

    # **Carried forward, not keyed to the revision that happened to see a capture.** A subject
    # edits the define without touching its scripts all the time, and the first version of this
    # handed that revision nothing at all — which put its grader back in exactly the position
    # #639 describes, and, worse, made the empty one identifiable as the later revision in a
    # sheet whose order is deliberately shuffled. Measured on a live watcher run before this was
    # fixed: revision 02 was offered zero scripts while 01 was offered two.
    out = {}
    for target in revisions:
        if not target.isdigit():
            continue
        notes = [n for rev, rows in withheld.items() if rev.isdigit() and int(rev) <= int(target)
                 for n in rows]
        in_force = {}
        for rev, source, snap in captures:
            # Compared as numbers. As strings "100" sorts before "99", so past the second digit
            # a capture would be carried into a revision that came before it.
            if int(rev) <= int(target):
                in_force[source] = snap
        if in_force or notes:
            out[target] = (
                [snap for _source, snap in sorted(in_force.items())],
                sorted(set(notes)),
            )
    return out


def selftest():
    """The two properties this script is trusted for, on scratch directories."""
    import tempfile

    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        run = Path(tmp) / "fossil"
        (run / "revisions").mkdir(parents=True)
        for n, body in ((1, "a = 1\n"), (2, "b = 2\n")):
            (run / "revisions" / f"{n:02d}.toml").write_text(body, encoding="utf-8")
        # 99 and 100 exist so the carry-forward is compared as numbers: as strings "100" sorts
        # before "99", which would hand revision 99 a script captured after it.
        for n in (99, 100):
            (run / "revisions" / f"{n}.toml").write_text(f"n = {n}\n", encoding="utf-8")
        (run / "meta.json").write_text('{"target": "fossil"}', encoding="utf-8")

        # 0. The scripts beside a revision reach the grader, and reach the SHEET not at all.
        #    Both halves matter: the first is what #639 asks for, and the second is what keeps
        #    `audit.py`'s map check true — it refuses a `# map` naming anything that is not a
        #    revision number, so a script line written there would void every run.
        sdir = run / "revisions" / "scripts"
        sdir.mkdir(parents=True)
        (sdir / "01.check.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (sdir / "02.check.sh").write_text("#!/bin/sh\ntest -s state/a\n", encoding="utf-8")
        (sdir / "03.mksrc.sh").write_text("#!/bin/sh\n:\n", encoding="utf-8")
        (sdir / "08.check.sh").write_text("#!/bin/sh\n: another define entirely\n", encoding="utf-8")
        # The bytes exist on disk for this one, so the "the watcher said it did not copy it"
        # guard is the only thing that can keep it out of the brief — otherwise the existence
        # check would mask it and the case would pass for the wrong reason.
        (sdir / "04.big.bin").write_bytes(b"z" * 9)
        # A revision field that is not a number — a hand-edited index. `int(" 1")` is 1, so
        # without the `isdigit` guard this would be read as revision 1 and offered.
        (sdir / "06.odd.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (sdir / "07.late.sh").write_text("#!/bin/sh\n: captured at revision 100\n", encoding="utf-8")
        (sdir / "index.tsv").write_text(
            "# MM\tobserved\tsha256\tpath\trevision\tnote\n"
            "01\t2026-01-01T00:00:00Z\tdeadbeef\t/home/user/d/check.sh\t01\t\n"
            "02\t2026-01-01T00:00:01Z\tcafebabe\t/home/user/d/check.sh\t01\t\n"
            "03\t2026-01-01T00:00:02Z\tfeedface\t/home/user/d/mksrc.sh\t02\t\n"            # Same basename, a different define directory: its checker must not be offered
            # under this run's revisions as though it were theirs.
            "08\t2026-01-01T00:00:07Z\t5add1e00\t/home/user/other/check.sh\t01\t\n"
            "04\t2026-01-01T00:00:03Z\tbaddcafe\t/home/user/d/big.bin\t02\tnot copied: 9 bytes, over 8\n"
            "05\t2026-01-01T00:00:04Z\tdecafbad\t/home/user/d/gone.sh\t02\t\n"
            "06\t2026-01-01T00:00:05Z\tdefaced0\t/home/user/d/odd.sh\t 1\t\n"
            "07\t2026-01-01T00:00:06Z\t0ddba11e\t/home/user/d/late.sh\t100\t\n",
            encoding="utf-8",
        )
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            main([__file__, str(run), "A"])
        brief = buf.getvalue()
        # The LAST capture of a name under a revision, not every capture: 02 supersedes 01.
        if "08.check.sh" not in brief:
            print("FAIL selftest: a checker from a second define directory was dropped")
            failures += 1
        if "02.check.sh" not in brief or "01.check.sh" in brief:
            print("FAIL selftest: the brief does not hand over the checker in force")
            print(brief)
            failures += 1
        if "03.mksrc.sh" not in brief:
            print("FAIL selftest: a script beside a later revision is missing from the brief")
            failures += 1
        if "revisions/scripts" in brief.split("big.bin")[0].rsplit("\n", 1)[-1]:
            print("FAIL selftest: a capture the watcher did not copy was offered as material")
            failures += 1
        # …but the grader is told it existed: "no checker was written" and "one was written and
        # you are not being shown it" are different premises for the same verdict.
        if "big.bin" not in brief:
            print("FAIL selftest: a withheld capture was dropped without saying so")
            failures += 1
        # Row 05 claims a copy and the file is not there — a run lifted out of a box half way.
        if "gone.sh" in brief:
            print("FAIL selftest: a snapshot named by the index but absent was offered")
            failures += 1
        if "odd.sh" in brief:
            print("FAIL selftest: a row whose revision is not a number was offered")
            failures += 1
        block99 = brief.split("99.toml", 1)[-1].split("与え ID", 1)[0]
        if "late.sh" in block99:
            print("FAIL selftest: a capture at revision 100 was carried back into revision 99")
            failures += 1
        # Every revision is offered scripts, not only the ones that happened to see a capture.
        # A define edited without touching its scripts is ordinary, and the first version of
        # this handed such a revision nothing — which both reproduces #639 for that revision and
        # marks it out as the later one in a sheet whose order is shuffled. Revision 02 here has
        # no capture of its own: 03.mksrc.sh is the last thing recorded under it, and check.sh
        # was last written under 01.
        for gid in ("G", "K"):
            block = brief.split(f"与え ID `{gid}`", 1)[-1].split("与え ID", 1)[0]
            if "check.sh" not in block:
                print(f"FAIL selftest: revision under id {gid} was offered no checker")
                failures += 1

        sheet = (run / "grades" / "a.tsv").read_text(encoding="utf-8")
        stray = [l for l in sheet.splitlines()
                 if l.startswith("# map")
                 and l.rsplit("\t", 1)[-1] not in ("01", "02", "99", "100")]
        if stray:
            print(f"FAIL selftest: the sheet's map names something other than a revision: {stray}")
            failures += 1
        (run / "grades" / "a.tsv").unlink()

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

    # The scripts the subject wrote beside each revision (#639). `grade-rubric.md` defines
    # `vacuous checker` entirely in terms of the checker's behaviour, and until this listing
    # carried them every grader in the round said, unprompted, that the class was undecidable
    # from what it had been handed.
    #
    # They ride the revision's OWN given id. A separate id would be a second ordering hint, and
    # — the reason that actually bites — `audit.py` refuses a grades sheet whose `# map` names
    # anything that is not a revision number, in both directions. So the scripts appear here,
    # in the printed brief, and never in the sheet written below.
    scripts = scripts_for(run, [p.stem for p in revisions])

    def with_scripts(gid, p):
        line = f"   - 与え ID `{gid}` = `{shown(p)}`"
        offered, withheld = scripts.get(p.stem, ([], []))
        for sp in offered:
            line += f"\n     - 同じ define が書かれた時点のスクリプト: `{shown(sp)}`"
        for name, why in withheld:
            line += f"\n     - このとき `{name}` も書かれていたが、本文は渡していない（{why}）"
        return line

    listing = "\n".join(with_scripts(gid, p) for gid, p in pairs)
    print(
        brief.replace("REPO_PATH", str(here.parent.parent))
        .replace("TARGET", target)
        .replace("   GIVEN_IDS", listing)
    )
    print(f"\n(sheet prepared: {shown(sheet)})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
