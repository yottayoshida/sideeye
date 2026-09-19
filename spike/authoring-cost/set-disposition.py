#!/usr/bin/env python3
"""Write a run's disposition into its meta.json, reading the audit first (#618, PROTOCOL.md).

    set-disposition.py <run-dir> graded|adjudicate|void "<note>"
    set-disposition.py --selftest

PROTOCOL.md's Disposition section is read in order — `void`, then `adjudicate`, then graded —
and it says step 2 is answered "from a list rather than from memory": the list of
repository-derived strings the audit found. Nothing made that true. This does:

* it runs the audit and **refuses `graded` when the audit found any repository trace**, naming
  each one. The judgement itself is still the operator's — `adjudicate` with a note, or `void`
  with a reason — but the version where the list is never opened is gone;
* it refuses to overwrite a disposition that is already written. A run's disposition is decided
  once, before the grades are read; a second call is either a mistake or a re-publication, and
  a re-publication goes through the ledger (PROTOCOL.md, "A card may not be written or changed
  after a run it grades");
* it refuses a disposition set **after a graded row exists**, for the same reason the protocol
  gives: the adjudication is made before the grades are read, and a tool that lets it be made
  afterwards makes the ordering unverifiable. A *sheet* is not a grade — `assign-grading.py`
  writes the map before the grader sees anything — and the first version of this check drew the
  line there and refused its own procedure.

`void` is exempt from the trace check — a run can be void for reasons that have nothing to do
with what the subject read — but it still takes a reason, which lands as `void_reason`.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
FORMS = ("graded", "adjudicate", "void")


def apply(run: Path, form: str, note: str, audit=None):
    if form not in FORMS:
        raise SystemExit(f"set-disposition: {form!r} is not one of {', '.join(FORMS)}")
    if not note.strip():
        raise SystemExit("set-disposition: a disposition without a reason is not a disposition")
    meta_path = run / "meta.json"
    if not meta_path.exists():
        raise SystemExit(f"set-disposition: {meta_path} does not exist")
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    if meta.get("disposition") not in (None, "", "pending"):
        raise SystemExit(
            f"set-disposition: {run.name} is already {meta['disposition']!r}; a run's disposition "
            "is decided once, and a re-publication goes through the ledger"
        )
    # A VERDICT row, not a sheet. `assign-grading.py` creates the sheet with its `# map` lines
    # before the grader is handed anything, so "the sheet exists" is true from the moment the
    # assignment is drawn — this refused its own procedure the first time it ran. What
    # PROTOCOL.md orders is the adjudication against *the grades*, and a map is not a grade.
    graded_rows = 0
    grades = run / "grades"
    if grades.is_dir():
        for sheet in grades.glob("*.tsv"):
            for line in sheet.read_text(encoding="utf-8").splitlines():
                if line.strip() and not line.startswith("#"):
                    graded_rows += 1
    if graded_rows:
        raise SystemExit(
            f"set-disposition: {run.name} already carries {graded_rows} graded row(s). "
            "PROTOCOL.md makes the adjudication before the grades are read; deciding it now "
            "cannot be shown to have followed that order"
        )

    if audit is None:
        proc = subprocess.run(
            [sys.executable, str(HERE / "audit.py"), "--check", str(run)],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            raise SystemExit(f"set-disposition: the audit refuses this run:\n{proc.stdout}{proc.stderr}")
        audit = json.loads(proc.stdout)

    traces = audit.get("repo_traces", [])
    if traces and form == "graded":
        listed = "\n".join(f"  {t.get('ts', '?')}\t{t.get('matched')}" for t in traces)
        raise SystemExit(
            f"set-disposition: the audit found {len(traces)} repository trace(s) in {run.name}, "
            "so this run is `adjudicate`, not `graded`. Count it or void it, with the evidence:\n"
            + listed
        )

    meta["disposition"] = form
    meta["disposition_note"] = note
    if form == "void":
        meta["void_reason"] = note
    meta["disposition_traces_seen"] = len(traces)
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{run.name}: {form} (repository traces seen: {len(traces)})")


def selftest():
    failures = 0

    def case(name, fn):
        nonlocal failures
        try:
            fn()
        except SystemExit as exc:
            print(f"ok   {name}: refused — {str(exc).splitlines()[0]}")
            return
        print(f"FAIL {name}: accepted")
        failures += 1

    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)

        def fresh(name, **meta):
            run = base / name
            run.mkdir()
            (run / "meta.json").write_text(
                json.dumps({"target": name, "disposition": "pending", **meta}), encoding="utf-8"
            )
            return run

        traced = {"repo_traces": [{"ts": "t", "matched": "git clone"}]}
        clean = {"repo_traces": []}

        case(
            "a traced run cannot be called graded",
            lambda: apply(fresh("traced"), "graded", "looks fine to me", audit=traced),
        )
        case(
            "a decided run is not re-decided",
            lambda: apply(fresh("decided", disposition="void"), "graded", "n", audit=clean),
        )
        case("a disposition needs a reason", lambda: apply(fresh("noreason"), "graded", "  ", audit=clean))
        case("an unknown form is refused", lambda: apply(fresh("badform"), "counted", "n", audit=clean))

        graded_run = fresh("aftergrades")
        (graded_run / "grades").mkdir()
        (graded_run / "grades" / "a.tsv").write_text(
            "# map\tG\t01\nG\tsemantically valid\tnone\tclaim 1\n", encoding="utf-8"
        )
        case(
            "a disposition after a graded row is refused",
            lambda: apply(graded_run, "graded", "n", audit=clean),
        )

        # The other side of that line: an assignment has been drawn, nothing graded yet. This
        # is the state every run passes through, and refusing it would refuse the procedure.
        assigned = fresh("assigned")
        (assigned / "grades").mkdir()
        (assigned / "grades" / "a.tsv").write_text("# grader A\n# map\tG\t01\n", encoding="utf-8")
        apply(assigned, "graded", "assignment drawn, no verdict yet", audit=clean)
        if json.loads((assigned / "meta.json").read_text(encoding="utf-8"))["disposition"] != "graded":
            print("FAIL a sheet holding only its map blocked the disposition")
            failures += 1
        else:
            print("ok   a sheet holding only its map does not count as a grade")

        # The positive half: without it, every case above would pass on a function that refuses
        # unconditionally — which is the vacuous-guard shape this repository checks for.
        ok_run = fresh("clean")
        apply(ok_run, "graded", "nothing in the trace list", audit=clean)
        written = json.loads((ok_run / "meta.json").read_text(encoding="utf-8"))
        if written.get("disposition") != "graded" or written.get("disposition_traces_seen") != 0:
            print(f"FAIL a clean run is written through: {written}")
            failures += 1
        else:
            print("ok   a clean run is written through, recording how many traces were seen")

        # And `void` past a trace: the exemption has to be real, not just documented.
        void_run = fresh("voidtraced")
        apply(void_run, "void", "the container died", audit=traced)
        if json.loads((void_run / "meta.json").read_text(encoding="utf-8")).get("void_reason") is None:
            print("FAIL void did not record its reason")
            failures += 1
        else:
            print("ok   void is allowed past a trace and records its reason")

    if failures:
        print(f"FAIL {failures} selftest case(s)")
        return 1
    print("ok   set-disposition selftest: 8 case(s)")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) != 4:
        print(__doc__)
        return 2
    apply(Path(argv[1]).resolve(), argv[2], argv[3])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
