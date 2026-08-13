#!/usr/bin/env python3
"""Hold docs/report-schema.md to the generated reports, in both directions.

Usage: check-report-schema.py <schema.md> <contract.zig> <report.json>...

Three claims, each enforced:
  1. every field present in any given report is documented (a table row whose
     first cell backticks the field name);
  2. every documented field appears in at least one given report — a row that
     nothing generates is a claim nobody measured;
  3. the doc's closed unknown_reason set equals the contract's enum, exactly.

The verdict coverage itself is asserted too: the given reports must include all
four verdicts, or the reverse direction would go vacuously green for the
fields only some verdicts carry.
"""
import json
import re
import sys


def flatten(doc):
    keys = set()
    for k, v in doc.items():
        keys.add(k)
        if isinstance(v, dict):
            for k2 in v:
                keys.add("%s.%s" % (k, k2))
    return keys


def main():
    md_path, zig_path, report_paths = sys.argv[1], sys.argv[2], sys.argv[3:]
    md = open(md_path, encoding="utf-8").read()

    reports = [json.load(open(p)) for p in report_paths]
    verdicts = {r.get("verdict") for r in reports}
    want = {"PASS", "FAIL", "UNKNOWN", "SETUP_ERROR"}
    if verdicts != want:
        sys.exit("verdict coverage is %r, wanted all of %r — the reverse check "
                 "would be vacuous" % (sorted(verdicts), sorted(want)))

    observed = set()
    for r in reports:
        observed |= flatten(r)
    # after/before are documented as one row each ({op, path} described in
    # prose); their subkeys collapse onto the parent.
    observed = {k if not re.match(r"earliest\.(after|before)\.", k)
                else k.rsplit(".", 1)[0] for k in observed}

    documented = set(re.findall(r"^\| `([a-z0-9_.]+)`", md, re.M))

    undocumented = sorted(observed - documented)
    ungenerated = sorted(documented - observed)
    problems = []
    if undocumented:
        problems.append("generated but not documented: %s" % ", ".join(undocumented))
    if ungenerated:
        problems.append("documented but never generated: %s" % ", ".join(ungenerated))

    zig = open(zig_path, encoding="utf-8").read()
    # The whole enum block, to its closing brace at column 0 — values declared
    # after a pub fn still count. Members are exactly-4-space-indented bare
    # names ([a-z0-9_]: l0/l2-class names carry digits; the first version of
    # the FIELD regex dropped them, and the enum regex repeated that mistake
    # 14 lines later — caught in review, not by the author).
    m = re.search(r"UnknownReason = enum \{(.*?)\n\};", zig, re.S)
    if not m:
        sys.exit("could not find the UnknownReason enum in %s" % zig_path)
    enum_values = set(re.findall(r"^    ([a-z0-9_]+),", m.group(1), re.M))
    para = re.search(r"`unknown_reason` values \(closed set[^)]*\):(.*?)\n\n", md, re.S)
    if not para:
        problems.append("the doc has no '`unknown_reason` values (closed set...)' paragraph")
    else:
        doc_values = set(re.findall(r"`([a-z0-9_]+)`", para.group(1)))
        if doc_values != enum_values:
            problems.append("unknown_reason drift — doc-only: %s; enum-only: %s"
                            % (sorted(doc_values - enum_values) or "-",
                               sorted(enum_values - doc_values) or "-"))

    if problems:
        sys.exit("; ".join(problems))
    print("schema page, %d reports (all four verdicts), and the contract enum agree"
          % len(reports))


if __name__ == "__main__":
    main()
