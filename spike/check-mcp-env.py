#!/usr/bin/env python3
"""Hold the README's MCP environment table to what the server actually reads.

Usage: check-mcp-env.py <README.md> <src/mcp.zig>

The failure this exists for (#389): the server reads six `SIDEEYE_MCP_*` variables and
the operating documentation named two. `SIDEEYE_MCP_SHIM` — without which every
`tools/call` fails — appeared only in an ADR, so the README's section read as complete
while omitting the one variable that stops every caller unconditionally.

Two claims, both directions:

  1. every environment read the server performs is either a row in the README's MCP
     table or a line in EXCUSED below, with a reason;
  2. every variable the README's table names is actually read.

**The unit is the call site, not the variable name.** A scan for `SIDEEYE_MCP_[A-Z_]+`
would have looked complete and been wrong on day one: `src/mcp.zig` also reads `PATH`,
and one read takes its name from a runtime value (`getenv(nz.ptr)`, the pass-through
list). So this walks `getenv(` call sites instead.

**That moved the blind spot rather than removing it, and the counts below are what
closes it.** A call-site regex is still a regex: review measured that a `getenv(`
split across lines slipped through *and left the reported total unchanged*, so the
miss did not even show up as a number. Two ratchets now stand behind the parse — the
count of `getenv` identifiers must equal the number of call sites parsed, and any
other environment-reading spelling must be absent. A read this file cannot parse is
therefore a red rather than a silent subtraction.

EXCUSED is a fixed list and its length is asserted: a new unexcused read goes red rather
than joining a set nobody counts.
"""
import re
import sys

# Reads that are deliberately not in the README's table, each with the reason. Keyed by
# the source text of the argument, because the line number moves with every edit.
EXCUSED = {
    '"PATH"':
        "inherited from the caller's shell rather than set for the server, and used only "
        "to build the child's minimal PATH. Not a row in the table on purpose: the table "
        "is what a caller has to set, and nobody sets PATH to run this",
    "nz.ptr":
        "the name is a runtime value — one entry of the SIDEEYE_MCP_CHILD_ENV list, which "
        "the table documents as the knob that decides these",
}
EXCUSED_COUNT = 2

# Other ways Zig code can read the environment. This codebase reads it through
# `posix.getenv` only; if that changes, this check has to learn the new spelling before
# the new reads can be accounted for, and the assertion below makes that a red rather
# than a silent gap.
OTHER_READERS = ("getEnvVarOwned", "getEnvMap", "getEnvVarOwnedZ", "environ")

SECTION_START = "## Driving it from an agent (MCP)"


def mcp_section(md):
    lines = md.split("\n")
    start = None
    for i, line in enumerate(lines):
        if line.strip() == SECTION_START:
            start = i
            break
    if start is None:
        sys.exit("the README has no %r heading; the section this checks is gone or renamed"
                 % SECTION_START)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("## "):
            return "\n".join(lines[start:j])
    return "\n".join(lines[start:])


def documented(section):
    """Variable names from the table's first cell: | `NAME` | ... |"""
    return {m.group(1) for m in re.finditer(r"^\|\s*`([A-Z][A-Z0-9_]*)`\s*\|", section, re.M)}


def read_sites(zig):
    """Every getenv call, as (line number, argument source text)."""
    sites = []
    for n, line in enumerate(zig.split("\n"), 1):
        for m in re.finditer(r"getenv\(([^)]*)\)", line):
            sites.append((n, m.group(1).strip()))
    return sites


def parse_is_complete(zig, sites):
    """Did the parse see every read the file contains?

    Not a style check. The point is that `read_sites` uses a line-at-a-time regex, so a
    call written across lines is invisible to it — and invisible in a way that leaves the
    reported total looking right. Comparing the identifier count to the parsed count
    turns that into a disagreement somebody has to resolve.
    """
    problems = []
    idents = len(re.findall(r"\bgetenv\b", zig))
    if idents != len(sites):
        problems.append(
            "found %d `getenv` identifier(s) but parsed %d call site(s) — a read this "
            "check cannot see is a read it cannot account for. Put the call on one line, "
            "or teach read_sites the shape." % (idents, len(sites)))
    for name in OTHER_READERS:
        hits = re.findall(r"\b%s\b" % re.escape(name), zig)
        if hits:
            problems.append(
                "the file reads the environment through `%s` (%d occurrence(s)), which "
                "this check does not parse; every such read would be unaccounted for and "
                "silent" % (name, len(hits)))
    return problems


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: check-mcp-env.py <README.md> <src/mcp.zig>")
    md = open(sys.argv[1], encoding="utf-8").read()
    zig = open(sys.argv[2], encoding="utf-8").read()

    if len(EXCUSED) != EXCUSED_COUNT:
        sys.exit("EXCUSED holds %d entries, not the %d this file declares — a read was "
                 "excused without moving the count, which is the edit this assertion "
                 "exists to make loud" % (len(EXCUSED), EXCUSED_COUNT))

    section = mcp_section(md)
    doc = documented(section)
    sites = read_sites(zig)

    # Neither side may be empty: a table nobody wrote and a source nobody parsed both make
    # the two directions below vacuously true.
    if not doc:
        sys.exit("the README's MCP section documents no environment variable — either the "
                 "table is gone or its shape changed and this check stopped seeing it")
    if not sites:
        sys.exit("no getenv call was found in %s — the parse failed, and a parse that "
                 "finds nothing agrees with every table" % sys.argv[2])

    incomplete = parse_is_complete(zig, sites)
    if incomplete:
        sys.exit("\n".join(incomplete))

    read_names = set()
    unaccounted = []
    for line_no, arg in sites:
        if arg in EXCUSED:
            continue
        m = re.fullmatch(r'"([A-Z][A-Z0-9_]*)"', arg)
        if not m:
            unaccounted.append("%s:%d reads getenv(%s), whose name this cannot resolve; "
                               "document it or excuse it with a reason" % (sys.argv[2], line_no, arg))
            continue
        name = m.group(1)
        read_names.add(name)
        if name not in doc:
            unaccounted.append("%s:%d reads %s, which the README's MCP table does not name"
                               % (sys.argv[2], line_no, name))

    for name in sorted(doc - read_names):
        unaccounted.append("the README's MCP table names %s, which the server never reads"
                           % name)

    if unaccounted:
        sys.exit("\n".join(unaccounted))
    print("the README's MCP table and the server's %d environment reads agree "
          "(%d documented, %d excused)" % (len(sites), len(doc), EXCUSED_COUNT))


if __name__ == "__main__":
    main()
