#!/usr/bin/env python3
"""One benchmark cell: one `sideeye explore`, one TSV row (#621, ADR 0081).

    run-cell.py --engine PATH --toy PATH --crash-points N --state-files K --state-bytes B
                --mode wrappers|syscalls --checker none|cheap --rep R [--oracle PATH]
                [--sample-work-dir] [--out FILE]
    run-cell.py --selftest

**What this records is what the engine reported.** `--crash-points` is a request: the toy is
asked for `ceil(N/3)` cycles because three crash points per cycle is what the drafting
measurements found, and the row carries BOTH the request and the count the report came back
with. They are different numbers and the row keeps them apart, because a harness that writes
down what it asked for cannot notice the day the engine counts differently.

**A run that did not explore produces no figures.** The rule is `measure.sh`'s, kept because a
refusal recorded as `0 worlds, 0 seconds` drags every average it lands in: a row is written
only when the report carries a verdict and `explored > 0`; otherwise the row is `not-counted`
with the reason and every numeric column empty.

**Peak RSS** is `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss`, which is the maximum over
waited-for descendants — never the sum of processes alive at once. It is a **high-water mark
that never decreases**, so this script refuses to run if it is already non-zero when the cell
starts: one cell is one process, and a second child in the same process would report the
larger of the two as this cell's. The unit differs by platform — bytes on macOS, KiB on
Linux — and the row carries the unit rather than a number whose meaning depends on where it
was taken.

**Timing and sampling are different legs.** `--sample-work-dir` walks the work directory on an
interval, which is heavy enough on a large padding tree to pollute the wall clock it would sit
next to; a sampling leg therefore leaves `wall_s` and `per_world_s` empty. The sampled maximum
is a **lower bound**: a peak between two samples is not seen, and the interval is in the row.
"""
import argparse
import json
import os
import resource
import subprocess
import sys
import tempfile
import threading
import time

COLUMNS = [
    "ts", "host", "crash_points_requested", "cycles_arg", "crash_points_reported",
    "worlds", "state_files", "state_bytes", "mode", "checker", "checker_cmd", "rep",
    "wall_s", "per_world_s", "maxrss", "maxrss_unit",
    "work_max_bytes", "work_final_bytes", "sample_interval_s",
    "trace_bytes", "report_bytes", "case_bytes", "verdict", "oracle_verified", "note",
]

# Measured on the drafting machine for `toy-scale`: one create-write-unlink cycle is an open,
# a write and an unlink. Used only to turn a requested crash-point count into a cycle count —
# never to fill in the reported figure, which comes from the report.
CRASH_POINTS_PER_CYCLE = 3


def cycles_for(crash_points):
    """Cycles to ask for, so the run lands at or just above the requested crash points."""
    return max(1, -(-crash_points // CRASH_POINTS_PER_CYCLE))


def rss_unit():
    """ru_maxrss is bytes on macOS and KiB on Linux. Reported, not converted away."""
    return "bytes" if sys.platform == "darwin" else "KiB"


def dir_bytes(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for name in files:
            try:
                total += os.lstat(os.path.join(root, name)).st_size
            except OSError:
                pass
    return total


def trace_bytes(work):
    """The traces alone, which is not the same number as the work directory.

    The engine keeps one `trace-N.bin` per world, so this column grows with the world count
    while the work directory also holds the captured stdout and any saved case. The first
    version of this script summed the whole directory into BOTH columns — two labels over one
    number, which is worse than a missing column because a reader takes them for two facts.
    """
    total = 0
    for name in os.listdir(work):
        if name.startswith("trace-") and name.endswith(".bin"):
            try:
                total += os.lstat(os.path.join(work, name)).st_size
            except OSError:
                pass
    return total


def build_padding(state, files, size):
    """Files the operation never touches — the state-size axis, as `measure.sh` shapes it."""
    pad = os.path.join(state, "pad")
    os.makedirs(pad, exist_ok=True)
    block = b"x" * size
    for i in range(files):
        with open(os.path.join(pad, "p%06d.bin" % i), "wb") as f:
            f.write(block)


def row_from(values):
    return "\t".join(str(values.get(c, "")) for c in COLUMNS)


# The columns a reader would total or average. A not-counted row carries none of them, and
# they are cleared here rather than merely never set: the cell path fills some of them
# (`maxrss`, the work-directory sizes) before it knows whether the run explored, and a refused
# run's memory figure sitting in the same column as an explored run's is the same defect as
# recording it as zero — a number that means something else, in a column that will be averaged.
FIGURE_COLUMNS = [
    "crash_points_reported", "worlds", "wall_s", "per_world_s", "maxrss",
    "work_max_bytes", "work_final_bytes", "trace_bytes", "report_bytes", "case_bytes",
    "verdict", "oracle_verified",
]


def add_note(base, text):
    """Notes accumulate. Assigning would let the last writer erase the others, and the two that
    can land on one row are exactly the pair that must not: a sampling leg's row also carries a
    memory figure, and the disclosure that the figure is a floor was being dropped on every one
    of them. Every small-state container cell in the pilot hits that disclosure, and the grid's
    sampling pass is half small-state, so it was silent precisely where it fires."""
    base["note"] = (base.get("note", "") + "; " + text).lstrip("; ")


def not_counted(base, reason):
    base = dict(base)
    for column in FIGURE_COLUMNS:
        base[column] = ""
    base["note"] = "not-counted: " + reason
    return row_from(base)


def run_cell(a):
    # First, before the probe spawns anything. Both refusals exist for one reason: a usage error
    # that reaches the engine comes back as a refusal, and a refusal lands in the record as a
    # not-counted **measurement**. A row saying "the engine refused" when the truth is "the
    # harness was invoked wrong" is exactly the confusion this apparatus exists to make
    # impossible, so neither shape gets as far as a row.
    #
    # `--setup-cmd` and `--operation-cmd` are one mode, not two flags. Half of them is never
    # meaningful: without `--toy` it spells the command `None init`, and *with* `--toy` it
    # silently pairs a real setup with the toy's own operation — a mixture nothing in the row
    # would show, since only `--operation-cmd` blanks the request columns.
    if (a.setup_cmd is None) != (a.operation_cmd is None):
        raise SystemExit("run-cell: --setup-cmd and --operation-cmd are one mode; give both "
                         "(a real target) or neither (the toy)")
    if a.setup_cmd is None and not a.toy:
        raise SystemExit("run-cell: --toy is required unless both --setup-cmd and "
                         "--operation-cmd are given")

    started = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    if started != 0:
        sys.exit("run-cell: this process has already waited for a child, so ru_maxrss is "
                 "another run's high-water mark; one cell must be one process")

    # The engine is proven to run before anything is measured. A path that cannot be executed
    # is an operator's mistake, not a run outcome: a traceback here would be unreadable, and a
    # `not-counted` row would file the mistake in the record as though it were data. Hit twice
    # while building this — a cross-compiled `zig-out` run on the build host — so it is checked
    # rather than remembered.
    # Read AFTER the guard above and BEFORE the explore: the probe is itself a waited child, so
    # `ru_maxrss` from here on is max(probe, explore). A cell whose explore never exceeds the
    # probe is saying its own memory figure is the probe's, and the row says so rather than
    # presenting the floor as the measurement.
    try:
        probe = subprocess.run([a.engine, "version"], capture_output=True)
    except OSError as e:
        sys.exit("run-cell: cannot execute %s: %s (is it built for this platform?)" % (a.engine, e))
    if probe.returncode != 0:
        sys.exit("run-cell: %s version exited %d; refusing to measure with an engine that does "
                 "not run" % (a.engine, probe.returncode))

    probe_rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss

    work_root = tempfile.mkdtemp(prefix="se621-cell-")
    state = os.path.join(work_root, "state")
    work = os.path.join(work_root, "work")
    os.makedirs(state)
    os.makedirs(work)
    if a.state_files:
        build_padding(state, a.state_files, a.state_bytes)

    cycles = cycles_for(a.crash_points)
    base = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "host": "%s-%s" % (os.uname().sysname, os.uname().machine),
        # An anchor asked for no particular count — the target's own operation decides. Leaving
        # the request columns empty is the honest reading; filling them with the toy's arithmetic
        # would put a number nobody asked for beside one the engine reported.
        "crash_points_requested": "" if a.operation_cmd else a.crash_points,
        "cycles_arg": "" if a.operation_cmd else cycles,
        "state_files": a.state_files, "state_bytes": a.state_bytes,
        "mode": a.mode, "checker": a.checker, "rep": a.rep,
        # Which checker, not just whether: the pilot holds two rows whose identity tuple is
        # otherwise the same — one with a falsifiable checker and one the engine refused.
        "checker_cmd": a.cheap_checker if a.checker == "cheap" else "",
        "maxrss_unit": rss_unit(),
        "sample_interval_s": a.sample_interval if a.sample_work_dir else "",
    }

    report = os.path.join(work_root, "report.json")
    setup_cmd = a.setup_cmd or ("%s init" % a.toy)
    operation_cmd = a.operation_cmd or ("%s rotate %d" % (a.toy, cycles))
    cmd = [a.engine, "explore", "--state", state,
           "--setup", setup_cmd,
           "--operation", operation_cmd,
           "--work", work, "--json", report]
    if a.mode == "syscalls":
        cmd += ["--observe", "syscalls"]
    if a.oracle:
        cmd += ["--oracle", a.oracle]
    else:
        cmd += ["--allow-unverified"]
    if a.checker == "cheap":
        cmd += ["--check", a.cheap_checker]

    env = dict(os.environ, TOY_STATE=state)
    if a.state_env:
        env[a.state_env] = state

    stop = threading.Event()
    seen = {"max": 0}

    def sampler():
        while not stop.is_set():
            seen["max"] = max(seen["max"], dir_bytes(work))
            stop.wait(a.sample_interval)

    thread = None
    if a.sample_work_dir:
        thread = threading.Thread(target=sampler, daemon=True)
        thread.start()

    t0 = time.monotonic()
    subprocess.run(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wall = time.monotonic() - t0
    if thread is not None:
        stop.set()
        thread.join(timeout=5)
        seen["max"] = max(seen["max"], dir_bytes(work))

    if a.label:
        add_note(base, "target: " + a.label)
    base["maxrss"] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    if base["maxrss"] <= probe_rss:
        add_note(base, "the engine's `version` probe reached the same peak, so this figure is "
                       "a floor rather than the exploration's own")
    base["work_final_bytes"] = dir_bytes(work)
    base["work_max_bytes"] = seen["max"] if a.sample_work_dir else ""

    if not os.path.exists(report):
        return not_counted(base, "the run wrote no report")
    try:
        d = json.load(open(report))
    except ValueError:
        return not_counted(base, "the report is not readable JSON")
    if d.get("schema") != "sideeye/report":
        return not_counted(base, "the report is not a sideeye report")

    explored = d.get("explored", 0)
    if not explored:
        return not_counted(base, "explored 0 worlds (%s%s)" % (
            d.get("verdict"), "/" + d["unknown_reason"] if d.get("unknown_reason") else ""))

    base["crash_points_reported"] = d["crash_points"]
    base["worlds"] = explored
    base["verdict"] = d["verdict"]
    base["oracle_verified"] = d["oracle_verified"]
    base["report_bytes"] = os.path.getsize(report)
    base["trace_bytes"] = trace_bytes(work)
    case = d.get("case", "(none)")
    base["case_bytes"] = os.path.getsize(case) if case not in ("(none)", "(not saved)") and os.path.exists(case) else 0
    if a.sample_work_dir:
        base["wall_s"] = ""
        base["per_world_s"] = ""
        add_note(base, "sampling leg: the wall clock is not recorded because the sampler "
                       "walks the work directory")
    else:
        base["wall_s"] = "%.3f" % wall
        base["per_world_s"] = "%.5f" % (wall / explored)
    return row_from(base)


# --- selftest -------------------------------------------------------------------------------
#
# Every case here drives a function this script's own cell path calls. The repository's rule is
# that a new check is seen red once before it is trusted (CLAUDE.md); a selftest is how that
# survives the commit that introduced it.
def selftest():
    fails = []

    def ok(name):
        print("ok   " + name)

    def check(name, cond, detail=""):
        if cond:
            ok(name)
        else:
            print("FAIL " + name + (": " + detail if detail else ""))
            fails.append(name)

    # The request-to-cycles mapping, and that it never claims to be the reported figure.
    check("10 crash points asks for 4 cycles", cycles_for(10) == 4, str(cycles_for(10)))
    check("1000 crash points asks for 334 cycles", cycles_for(1000) == 334, str(cycles_for(1000)))
    check("a request of 0 still asks for one cycle", cycles_for(0) == 1, str(cycles_for(0)))
    # 3N means a request and its report agree only where N is a multiple of three, and the row
    # keeps the two columns apart either way — so no cell can be chosen to hide a mismatch.
    check("the requested count is not reused as the reported one",
          "crash_points_requested" in COLUMNS and "crash_points_reported" in COLUMNS)

    # A run that did not explore must produce no figures at all.
    base = {"ts": "T", "host": "H", "crash_points_requested": 10, "worlds": 99, "wall_s": "1.0",
            "maxrss": 12345, "work_final_bytes": 99, "verdict": "UNKNOWN", "oracle_verified": False}
    line = not_counted(base, "explored 0 worlds (UNKNOWN/no_shim_marker)")
    cols = line.split("\t")
    idx = {c: i for i, c in enumerate(COLUMNS)}
    check("a not-counted row names the reason", "explored 0 worlds" in cols[idx["note"]], line)
    check("a not-counted row keeps the identity columns", cols[idx["host"]] == "H")
    # …and EVERY column a caller would total must be empty rather than zero or stale.
    #
    # **The expected list is written out here rather than read from `FIGURE_COLUMNS`.** Looping
    # over the list under test makes the check vacuous: dropping a column from it would remove
    # the case that guards it and the suite would stay green with one fewer assertion. Review
    # measured exactly that — `maxrss` and `worlds` could each be dropped and nothing went red.
    # Adding a figure column now fails here until it is added in both places, which is the
    # point.
    expected_figures = [
        "crash_points_reported", "worlds", "wall_s", "per_world_s", "maxrss",
        "work_max_bytes", "work_final_bytes", "trace_bytes", "report_bytes", "case_bytes",
        "verdict", "oracle_verified",
    ]
    check("the figure list is the one this test knows about",
          FIGURE_COLUMNS == expected_figures,
          "code has %r" % (sorted(set(FIGURE_COLUMNS) ^ set(expected_figures)),))
    # Every column is either an identity column or a figure column — a new column cannot be
    # added without a decision about which it is.
    identity = ["ts", "host", "crash_points_requested", "cycles_arg", "state_files",
                "state_bytes", "mode", "checker", "checker_cmd", "rep", "maxrss_unit",
                "sample_interval_s", "note"]
    check("every column is identity or figure",
          sorted(identity + expected_figures) == sorted(COLUMNS),
          "unclassified: %r" % (sorted(set(COLUMNS) - set(identity) - set(expected_figures)),))
    # The grid reads columns by position. Pin the order so a reshuffle cannot pass silently.
    check("the column order is the one run-grid.sh indexes",
          [COLUMNS.index(c) + 1 for c in
           ("crash_points_requested", "state_files", "mode", "checker", "rep", "note")]
          == [3, 7, 9, 10, 12, 25],
          "positions moved: %r" % ([COLUMNS.index(c) + 1 for c in
                                    ("crash_points_requested", "state_files", "mode",
                                     "checker", "rep", "note")],))
    base = dict(base)
    for col in expected_figures:
        check("a not-counted row leaves %s empty" % col, cols[idx[col]] == "",
              "got %r" % cols[idx[col]])

    # The two size columns must come from different places. A synthetic work directory with
    # one trace and one non-trace file of different sizes separates them; summing the whole
    # directory into both — the first version of this script — fails here.
    wtmp = tempfile.mkdtemp(prefix="se621-selftest-work-")
    with open(os.path.join(wtmp, "trace-1.bin"), "wb") as f:
        f.write(b"t" * 10)
    with open(os.path.join(wtmp, "stdout-record.txt"), "wb") as f:
        f.write(b"o" * 7)
    check("trace_bytes counts the traces alone", trace_bytes(wtmp) == 10, str(trace_bytes(wtmp)))
    check("the work directory is the larger figure", dir_bytes(wtmp) == 17, str(dir_bytes(wtmp)))
    os.remove(os.path.join(wtmp, "trace-1.bin"))
    os.remove(os.path.join(wtmp, "stdout-record.txt"))
    os.rmdir(wtmp)

    check("the row has one field per column", len(row_from({}).split("\t")) == len(COLUMNS))
    check("the rss unit is named for this platform", rss_unit() in ("bytes", "KiB"))

    # dir_bytes counts what it is given and does not follow out of it.
    tmp = tempfile.mkdtemp(prefix="se621-selftest-")
    with open(os.path.join(tmp, "a"), "wb") as f:
        f.write(b"0123456789")
    os.makedirs(os.path.join(tmp, "sub"))
    with open(os.path.join(tmp, "sub", "b"), "wb") as f:
        f.write(b"012345")
    check("dir_bytes sums the tree", dir_bytes(tmp) == 16, str(dir_bytes(tmp)))
    os.remove(os.path.join(tmp, "a"))
    os.remove(os.path.join(tmp, "sub", "b"))
    os.rmdir(os.path.join(tmp, "sub"))
    os.rmdir(tmp)

    # --- one pass through run_cell itself ------------------------------------------------
    #
    # Everything above is a pure function. Review measured what that leaves uncovered by
    # mutating the cell path: changing `per_world_s`'s divisor from the reported world count to
    # the requested crash points left the suite green, and so did deleting the rusage guard and
    # the sampling branch. The division is the single easiest line in this script to get wrong
    # and it was outside the tests. A stand-in engine closes that: it writes a report the cell
    # path then reads, so the row comes out of the real code with numbers this test chose.
    stub_dir = tempfile.mkdtemp(prefix="se621-selftest-stub-")

    def write_stub_engine(path, records_state_to=None):
        """One stand-in engine, used twice. `version` answers so the probe passes; `explore`
        writes a report at --json. The `sleep` is deliberate: without it the stub finishes
        inside the third decimal `wall_s` is rounded to, `wall_s` reads 0.000, and the divisor
        check compares three candidates against zero — where the SMALLEST wins and the case
        fails for a reason that has nothing to do with the divisor. It passed on a loaded
        machine and failed on an idle one, which is the wrong way round for a test to be
        sensitive to. `records_state_to` is for the anchor case: `--state-env` is the one knob
        whose effect never reaches the row, so the engine writes down what it was exported."""
        body = ["#!/bin/sh",
                "[ \"$1\" = version ] && { echo 'fake 0.0.0'; exit 0; }"]
        if records_state_to:
            body.append("printf '%s' \"$SE621_PROBE_STATE\" > " + records_state_to)
        body += ["sleep 0.05",
                 "while [ $# -gt 0 ]; do [ \"$1\" = --json ] && out=$2; shift; done",
                 "printf '%s' '{\"schema\":\"sideeye/report\",\"verdict\":\"PASS\","
                 "\"crash_points\":9,\"explored\":10,\"oracle_verified\":false,"
                 "\"case\":\"(none)\"}' > \"$out\""]
        with open(path, "w") as f:
            f.write("\n".join(body) + "\n")
        os.chmod(path, 0o755)

    stub = os.path.join(stub_dir, "fake-engine")
    write_stub_engine(stub)

    class Args:
        engine = stub
        toy = "/bin/true"
        crash_points = 7          # deliberately NOT 9: the row must carry the report's count
        state_files = 0
        state_bytes = 1024
        mode = "wrappers"
        checker = "none"
        cheap_checker = "/bin/true"
        rep = 1
        oracle = None
        sample_work_dir = False
        sample_interval = 0.25
        # The anchor knobs, at their defaults. This class is the cell path's whole input, so a
        # knob added to the parser and forgotten here stops the suite — which is how the two
        # were kept in step when the anchor mode arrived.
        setup_cmd = None
        operation_cmd = None
        state_env = None
        label = ""

    # Both refusals, each seen red once by deleting its own guard: without them the cell runs
    # on and the engine's complaint lands in the record as a not-counted measurement.
    def refused(what, mutate, wanted):
        bad = Args()
        mutate(bad)
        try:
            run_cell(bad)
            check(what, False, "it ran instead of refusing")
        except SystemExit as e:
            check(what, wanted in str(e), str(e))

    def half_given(x):
        x.operation_cmd = "some real operation"   # and setup_cmd left None
    refused("half an anchor is refused, not measured", half_given, "are one mode")

    def no_target_at_all(x):
        x.toy = ""
    refused("a cell with no target at all is refused", no_target_at_all, "--toy is required")

    row = run_cell(Args()).split("\t")
    at = {c: i for i, c in enumerate(COLUMNS)}
    check("the cell path records the reported count, not the request",
          row[at["crash_points_reported"]] == "9" and row[at["crash_points_requested"]] == "7",
          "requested=%s reported=%s" % (row[at["crash_points_requested"]],
                                        row[at["crash_points_reported"]]))
    # per-world must divide by the worlds the report gave (10), not by the request (7) and not
    # by the reported crash points (9). Asked as "which divisor reconstructs the wall clock
    # best" rather than as an equality: the two columns are rounded to different precisions
    # (three places against five), and on a stub that finishes in milliseconds that rounding is
    # larger than the gap between the candidates. The first version of this case compared
    # against `wall / 10` directly and failed on the rounding rather than on the logic.
    wall = float(row[at["wall_s"]])
    per = float(row[at["per_world_s"]])
    if wall <= 0.0:
        check("per-world divides by the reported world count", False,
              "wall_s rounded to %s, so no divisor can be told from another; the stub must "
              "take longer than the column's precision" % row[at["wall_s"]])
    else:
        closest = min((10, 9, 7), key=lambda n: abs(per * n - wall))
        check("per-world divides by the reported world count",
              closest == 10,
              "wall=%s per=%s; best divisor looks like %d" % (wall, per, closest))
    check("the cell path fills the row's verdict from the report",
          row[at["verdict"]] == "PASS", row[at["verdict"]])

    # The anchor path, driven end to end. It runs as a **subprocess** because one cell is one
    # process: this process has now waited for the stub above, so a second `run_cell` here would
    # be refused by the guard at the top of it — correctly. Until these cases existed, the
    # anchor mode's four effects were never executed by any test and the rows it produced were
    # the only evidence it worked.
    envstub = os.path.join(stub_dir, "env-engine")
    seen = os.path.join(stub_dir, "seen.txt")
    write_stub_engine(envstub, records_state_to=seen)
    out = subprocess.run(
        [sys.executable, os.path.abspath(__file__), "--engine", envstub,
         "--crash-points", "7", "--rep", "1",
         "--setup-cmd", "/bin/true", "--operation-cmd", "/bin/true",
         "--state-env", "SE621_PROBE_STATE",
         "--label", "a real target"],
        capture_output=True, text=True)
    check("the anchor path emits a row at all", out.returncode == 0, out.stderr[-200:])
    if out.returncode == 0:
        arow = out.stdout.rstrip("\n").split("\t")
        check("an anchor leaves the request columns empty",
              arow[at["crash_points_requested"]] == "" and arow[at["cycles_arg"]] == "",
              "requested=%r cycles=%r" % (arow[at["crash_points_requested"]],
                                          arow[at["cycles_arg"]]))
        check("an anchor still reports the engine's own counts",
              arow[at["crash_points_reported"]] == "9" and arow[at["worlds"]] == "10",
              "reported=%r worlds=%r" % (arow[at["crash_points_reported"]], arow[at["worlds"]]))
        check("the label rides the note column, beside whatever else is noted",
              "target: a real target" in arow[at["note"]], arow[at["note"]])
        got = open(seen).read() if os.path.exists(seen) else "(the engine never ran)"
        check("--state-env exports the resolved state directory to the child",
              got.endswith("/state") and os.path.isabs(got), got)

    os.remove(envstub)
    if os.path.exists(seen):
        os.remove(seen)
    os.remove(stub)
    os.rmdir(stub_dir)

    if fails:
        sys.exit("selftest: %d case(s) failed" % len(fails))
    print("selftest: every case behaved as documented")


def main():
    if "--selftest" in sys.argv:
        return selftest()
    # Before the parser, like --selftest: a caller asking only for the column names should not
    # have to invent an engine path to get them.
    if "--header" in sys.argv:
        print("\t".join(COLUMNS))
        return
    p = argparse.ArgumentParser()
    p.add_argument("--engine", required=True)
    p.add_argument("--toy")
    # The real-target anchor (#621 condition 5). Deliberately NOT `--config`: the engine refuses
    # `--config` beside `--state/--setup/--operation`, and a define whose `[world] state` the
    # harness never sees would leave the state columns describing padding that is not there.
    # With these, the anchor runs through the same row, the same not-counted rule and the same
    # RSS method as every synthetic cell, and the state columns keep meaning "what this harness
    # built" in both.
    p.add_argument("--setup-cmd", help="replaces the toy's `init` (real-target anchor)")
    p.add_argument("--operation-cmd", help="replaces the toy's `rotate N` (real-target anchor)")
    p.add_argument("--state-env", default=None,
                   help="an extra variable exported to the target, pointing at the state directory")
    p.add_argument("--label", default="", help="what this row is, when it is not the scale toy")
    p.add_argument("--crash-points", type=int, required=True)
    p.add_argument("--state-files", type=int, default=0)
    p.add_argument("--state-bytes", type=int, default=1024)
    p.add_argument("--mode", choices=("wrappers", "syscalls"), default="wrappers")
    p.add_argument("--checker", choices=("none", "cheap"), default="none")
    p.add_argument("--cheap-checker", default="/bin/true")
    p.add_argument("--rep", type=int, default=1)
    p.add_argument("--oracle", default=None)
    p.add_argument("--sample-work-dir", action="store_true")
    p.add_argument("--sample-interval", type=float, default=0.25)
    p.add_argument("--out", default=None)
    p.add_argument("--header", action="store_true", help="print the column header and exit")
    a = p.parse_args()
    if a.header:
        print("\t".join(COLUMNS))
        return
    line = run_cell(a)
    if a.out:
        new = not os.path.exists(a.out)
        with open(a.out, "a") as f:
            if new:
                f.write("\t".join(COLUMNS) + "\n")
            f.write(line + "\n")
    print(line)


if __name__ == "__main__":
    main()
