#!/usr/bin/env python3
"""
    python3 spike/check-ci-required.py <workflow.yml>   # NEEDS holds ${{ toJSON(needs) }}
    python3 spike/check-ci-required.py --timeouts <workflow directory>
    python3 spike/check-ci-required.py --selftest
"""
import contextlib
import io
import json
import os
import re
import sys
import tempfile

GATE = "required"
# Any key at the jobs' indent, whatever follows its colon (a flow map, an anchor) and quoted or
# not: a job this did not recognise would be left out of the comparison and pass unchecked.
JOB_KEY = re.compile(r"^  ([^\s#][^:]*):")
NEEDS_LINE = re.compile(r"^    needs:\s*\[(.*)\]\s*(#.*)?$")
# The job's own indent only: a step's timeout bounds one step, and the job around it can still
# hold a runner for six hours.
TIMEOUT_LINE = re.compile(r"^    timeout-minutes:\s*(\d|\$\{\{)")
FLOW_JOB = re.compile(r"^  [^\s#][^:]*:\s*\{")
CALLS_WORKFLOW = re.compile(r"^    uses:\s*\S")


def job_blocks(text):
    blocks, in_jobs = [], False
    for line in text.splitlines():
        if line.startswith("jobs:"):
            in_jobs = True
            continue
        if not in_jobs:
            continue
        if line and not line.startswith(" ") and not line.startswith("#"):
            break
        m = JOB_KEY.match(line)
        if m:
            blocks.append((m.group(1).strip().strip("'\""), line, []))
        elif blocks:
            blocks[-1][2].append(line)
    return blocks


def jobs_and_needs(text):
    blocks, needs = job_blocks(text), None
    for name, _, body in blocks:
        if name != GATE:
            continue
        # A block-style `needs:` list would be read as none here and fail as missing,
        # rather than be half-read.
        for line in body:
            n = NEEDS_LINE.match(line)
            if n:
                needs = [x.strip() for x in n.group(1).split(",") if x.strip()]
    return [b[0] for b in blocks], needs


def timeout_gaps(text):
    blocks, untimed, flow = job_blocks(text), [], []
    for name, header, body in blocks:
        # Refused rather than searched: a line reader cannot tell which level of a flow
        # map a `timeout-minutes` belongs to.
        if FLOW_JOB.match(header):
            flow.append(name)
        # Not required of a job that calls a reusable workflow: GitHub rejects the key there,
        # and the jobs of the workflow it calls carry their own.
        elif any(CALLS_WORKFLOW.match(line) for line in body):
            continue
        elif not any(TIMEOUT_LINE.match(line) for line in body):
            untimed.append(name)
    return len(blocks), untimed, flow


def timeout_problems(named_texts):
    out, total = [], 0
    for name, text in named_texts:
        jobs, untimed, flow = timeout_gaps(text)
        total += jobs
        if not jobs:
            out.append(f"{name}: no job was read, so nothing here is a measurement")
        if untimed:
            out.append(f"{name}: job(s) with no job-level timeout-minutes: {', '.join(untimed)}")
        if flow:
            out.append(f"{name}: job(s) written as a flow map, whose timeout this cannot read: {', '.join(flow)}")
    return total, out


def problems(workflow_text, needs_json):
    out = []
    jobs, needs = jobs_and_needs(workflow_text)
    if not jobs:
        return ["no job was read from the workflow, so nothing here is a measurement"]
    if GATE not in jobs:
        return [f"the workflow has no `{GATE}` job"]
    if needs is None:
        return [f"the `{GATE}` job has no one-line `needs: [...]`"]
    others = [j for j in jobs if j != GATE]
    missing = sorted(set(others) - set(needs))
    extra = sorted(set(needs) - set(others))
    if missing:
        out.append(f"job(s) not in `{GATE}`'s needs, so not required: {', '.join(missing)}")
    if extra:
        out.append(f"`{GATE}`'s needs name job(s) the workflow does not have: {', '.join(extra)}")
    try:
        results = json.loads(needs_json)
    except ValueError as e:
        return out + [f"NEEDS is not JSON: {e}"]
    if not isinstance(results, dict) or not results:
        return out + ["NEEDS names no job, so no result was read"]
    for name in sorted(results):
        r = results[name].get("result") if isinstance(results[name], dict) else None
        if r != "success":
            out.append(f"{name}: {r}")
    unreported = sorted(set(needs) - set(results))
    if unreported:
        out.append(f"no result for: {', '.join(unreported)}")
    return out


WORKFLOW = """name: ci
on:
  pull_request:

jobs:
  linux:
    runs-on: ubuntu-latest
  fmt:  # a comment after the key
    runs-on: ubuntu-latest
  required:
    if: always()
    needs: [linux, fmt]
    runs-on: ubuntu-latest
"""


TIMED = """name: ci
jobs:
  linux:
    runs-on: ubuntu-24.04
    timeout-minutes: 40
    steps:
      - run: make
  fmt:  # a comment after the key
    timeout-minutes: 5
    runs-on: ubuntu-24.04
"""


def ok(*names):
    return json.dumps({n: {"result": "success", "outputs": {}} for n in names})


def selftest():
    cases = [
        ("every job needed and green", WORKFLOW, ok("linux", "fmt"), None),
        ("a job missing from needs", WORKFLOW.replace("needs: [linux, fmt]", "needs: [linux]"), ok("linux"), "not required: fmt"),
        ("needs naming a job that is gone", WORKFLOW.replace("[linux, fmt]", "[linux, fmt, macos]"), ok("linux", "fmt", "macos"), "does not have: macos"),
        ("a failed job", WORKFLOW, json.dumps({"linux": {"result": "success"}, "fmt": {"result": "failure"}}), "fmt: failure"),
        ("a skipped job", WORKFLOW, json.dumps({"linux": {"result": "success"}, "fmt": {"result": "skipped"}}), "fmt: skipped"),
        ("a cancelled job", WORKFLOW, json.dumps({"linux": {"result": "cancelled"}, "fmt": {"result": "success"}}), "linux: cancelled"),
        ("a needed job with no result", WORKFLOW, ok("linux"), "no result for: fmt"),
        ("no gate job", WORKFLOW.replace("  required:", "  gate:"), ok("linux", "fmt"), "has no `required` job"),
        ("a block-style needs list", WORKFLOW.replace("    needs: [linux, fmt]\n", "    needs:\n      - linux\n      - fmt\n"), ok("linux", "fmt"), "no one-line"),
        ("a quoted job key left out of needs", WORKFLOW.replace("  fmt:  # a comment after the key", "  'lint':\n    runs-on: ubuntu-latest\n  fmt:"), ok("linux", "fmt"), "not required: lint"),
        ("a flow-map job left out of needs", WORKFLOW.replace("  required:", "  docs: {runs-on: ubuntu-latest}\n  required:"), ok("linux", "fmt"), "not required: docs"),
        ("nothing read", "name: ci\n", ok("linux"), "no job was read"),
        ("NEEDS empty", WORKFLOW, "{}", "NEEDS names no job"),
    ]
    timeout_cases = [
        ("every job with a timeout", TIMED, None),
        ("a timeout only in a comment", TIMED.replace("    timeout-minutes: 5\n", "    # timeout-minutes: 5\n"), "no job-level timeout-minutes: fmt"),
        ("a timeout only on a step", TIMED.replace("    timeout-minutes: 40\n", "").replace("      - run: make\n", "      - run: make\n        timeout-minutes: 40\n"), "no job-level timeout-minutes: linux"),
        ("the last job without one", TIMED.replace("    timeout-minutes: 5\n", ""), "no job-level timeout-minutes: fmt"),
        ("a flow-map job", TIMED + "  docs: {runs-on: ubuntu-24.04, timeout-minutes: 5}\n", "flow map, whose timeout this cannot read: docs"),
        ("a job that calls a reusable workflow", TIMED + "  call:\n    uses: ./.github/workflows/x.yml\n", None),
        ("a timeout of null", TIMED.replace("timeout-minutes: 5", "timeout-minutes: null"), "no job-level timeout-minutes: fmt"),
        ("nothing read", "name: ci\n", "no job was read"),
    ]
    def wrong(label, got, want):
        if (want is None and got) or (want is not None and (len(got) != 1 or want not in got[0])):
            print(f"FAIL selftest {label!r}: wanted {want!r}, got {got}", file=sys.stderr)
            return 1
        return 0

    bad = sum(wrong(label, problems(wf, needs), want) for label, wf, needs, want in cases)
    bad += sum(wrong(label, timeout_problems([("ci.yml", wf)])[1], want) for label, wf, want in timeout_cases)
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "a.yml"), "w") as f:
            f.write(TIMED)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            green = main(["--timeouts", d], {})
            with open(os.path.join(d, "b.yaml"), "w") as f:
                f.write(TIMED.replace("    timeout-minutes: 5\n", ""))
            red = main(["--timeouts", d], {})
            empty = main(["--timeouts", os.path.join(d, "none")], {})
        if green != 0 or red == 0 or empty == 0:
            print("FAIL selftest 'the --timeouts command line': wanted 0, then non-zero for a .yaml without one and for no directory", file=sys.stderr)
            bad += 1
    with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False) as f:
        f.write(WORKFLOW)
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            green = main([f.name], {"NEEDS": ok("linux", "fmt")})
            red = main([f.name], {"NEEDS": ok("linux")})
        if green != 0 or red == 0:
            print("FAIL selftest 'the command line': wanted 0 then non-zero", file=sys.stderr)
            bad += 1
    finally:
        os.unlink(f.name)
    if bad:
        return 1
    print(f"ok   selftest: {len(cases) + len(timeout_cases)} shapes, each failing exactly where planted")
    return 0


def main(argv, env):
    if argv == ["--selftest"]:
        return selftest()
    if argv[:1] == ["--timeouts"]:
        if len(argv) != 2:
            print(__doc__, file=sys.stderr)
            return 2
        # Not a shell glob of `*.yml`: GitHub also runs `*.yaml`, and a glob that matched
        # nothing would be passed on as a literal name.
        try:
            paths = sorted(e.path for e in os.scandir(argv[1])
                           if e.is_file() and e.name.endswith((".yml", ".yaml")))
        except OSError as e:
            print(f"FAIL cannot read {argv[1]}: {e}", file=sys.stderr)
            return 1
        if not paths:
            print(f"FAIL no workflow file under {argv[1]}, so nothing here is a measurement", file=sys.stderr)
            return 1
        named = []
        for path in paths:
            with open(path, encoding="utf-8") as f:
                named.append((os.path.basename(path), f.read()))
        total, found = timeout_problems(named)
        if found:
            for p in found:
                print(f"FAIL {p}", file=sys.stderr)
            return 1
        print(f"ok   {total} job(s) across {len(named)} workflow(s), every one with a job-level timeout-minutes")
        return 0
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[0], encoding="utf-8") as f:
        text = f.read()
    found = problems(text, env.get("NEEDS", ""))
    if found:
        for p in found:
            print(f"FAIL {p}", file=sys.stderr)
        return 1
    jobs, _ = jobs_and_needs(text)
    print(f"ok   {len(jobs) - 1} job(s) needed by `{GATE}`, every one of them succeeded")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], os.environ))
