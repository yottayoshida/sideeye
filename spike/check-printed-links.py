#!/usr/bin/env python3
"""Every document the engine names in what it prints opens for someone holding only the release.

A release carries the binary, the shim and two licence files; README, DESIGN.md and docs/ stay
in the repository. So a sentence the engine prints may name a document only through
`contract.docUrl("<path>#<anchor>")`, which builds the URL of that file at the release's tag.
This reads `src/*.zig` and fails when:

  - a string literal outside comments and tests names README, DESIGN.md, a docs/ page or an
    ADR by name instead (the help text, `usage_fmt` in src/cli.zig, is exempt: it prints the
    tag's URL once and names pages relative to it; so is the fuzz harness, src/fuzz*.zig,
    which prints nothing to a user);
  - a `docUrl` argument is not a literal, names a path that does not exist, or names an anchor
    no heading of that page produces;
  - a string says "file it" on a line that does not join `contract.issues_url` to it;
  - no `docUrl` is found at all — a scan that read nothing must not read as one that passed;
  - the bulleted list under "Refusals by reason" in docs/report-schema.md and the
    `UnknownReason` enum in src/contract.zig name different reasons: the class-wall step sends
    every refusal there, so every reason needs its line.

Usage: check-printed-links.py [<repo root>] | --selftest
"""
import os
import re
import shutil
import sys
import tempfile

DOC_NAME = re.compile(r"\bREADME\b|\bDESIGN\.md\b|\bdocs/[A-Za-z0-9_./-]+\.md\b|\bADR \d{4}\b")
DOC_URL_CALL = re.compile(r"\bdocUrl\(")
FILE_IT = re.compile(r"\b[Ff]ile it\b(?! names| runs)")
DOC_URL_LITERAL = re.compile(r'\bdocUrl\("([^"\\]*)"\)')
LIST_HEADING = "### Refusals by reason"


def string_literals(line):
    stripped = line.lstrip()
    if stripped.startswith("\\\\"):
        return [stripped[2:]]
    out, i = [], 0
    while i < len(line):
        ch = line[i]
        if ch == "/" and line.startswith("//", i):
            break
        if ch == "'":
            j = line.find("'", i + 3 if line[i + 1:i + 2] == "\\" else i + 2)
            i = (j + 1) if j > 0 else len(line)
            continue
        if ch == '"':
            j, buf = i + 1, []
            while j < len(line) and line[j] != '"':
                if line[j] == "\\":
                    buf.append(line[j:j + 2])
                    j += 2
                    continue
                buf.append(line[j])
                j += 1
            out.append("".join(buf))
            i = j + 1
            continue
        i += 1
    return out


def code_lines(text, help_file):
    in_test = in_usage = False
    for n, line in enumerate(text.split("\n"), 1):
        if in_test:
            if line.startswith("}"):
                in_test = False
            continue
        if line.startswith("test ") and line.rstrip().endswith("{"):
            in_test = True
            continue
        if help_file and re.match(r"\s*(pub )?const usage_fmt\b", line):
            in_usage = True
        if in_usage:
            if line.strip() == ";":
                in_usage = False
            continue
        if line.lstrip().startswith("//"):
            continue
        yield n, line


def slug(heading):
    s = heading.strip().lower()
    s = re.sub(r"[^\w\- ]", "", s)
    return s.replace(" ", "-")


def anchors(md_text):
    out, fenced = set(), False
    for line in md_text.split("\n"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        m = re.match(r"#{1,6}\s+(.*)", line)
        if m:
            out.add(slug(m.group(1)))
    return out


def unknown_reasons(contract_text):
    m = re.search(r"pub const UnknownReason = enum \{(.*?)\n\s*pub fn name", contract_text, re.S)
    if not m:
        return None
    return {w for w in re.findall(r"^\s*([a-z_]+),", m.group(1), re.M)}


def listed_reasons(schema_text):
    start = schema_text.find("\n" + LIST_HEADING + "\n")
    if start < 0:
        return None
    rest = schema_text[start + len(LIST_HEADING) + 2:]
    end = re.search(r"\n#{1,3} ", rest)
    section = rest[:end.start()] if end else rest
    return set(re.findall(r"^- `([a-z_]+)`", section, re.M))


def check(root):
    problems, urls = [], 0
    src = os.path.join(root, "src")
    files = sorted(
        os.path.join(d, f) for d, _, fs in os.walk(src) for f in fs
        if f.endswith(".zig") and not f.startswith("fuzz")
    )
    for path in files:
        rel = os.path.relpath(path, root)
        text = open(path, encoding="utf-8").read()
        for n, line in code_lines(text, rel == os.path.join("src", "cli.zig")):
            calls = len(DOC_URL_CALL.findall(line))
            literal_args = DOC_URL_LITERAL.findall(line)
            if calls != len(literal_args) and not line.lstrip().startswith("pub inline fn docUrl"):
                problems.append(f"{rel}:{n}: a docUrl argument is not a string literal, so it cannot be checked")
            for target in literal_args:
                urls += 1
                page, _, anchor = target.partition("#")
                if not page and not anchor:
                    continue
                page_path = os.path.join(root, page)
                if not os.path.isfile(page_path):
                    problems.append(f"{rel}:{n}: docUrl names {page}, which is not in the tree")
                    continue
                if anchor and anchor not in anchors(open(page_path, encoding="utf-8").read()):
                    problems.append(f"{rel}:{n}: docUrl names #{anchor}, which no heading of {page} produces")
            for lit in string_literals(DOC_URL_LITERAL.sub("docUrl()", line)):
                m = DOC_NAME.search(lit)
                if m:
                    problems.append(f"{rel}:{n}: a printed string names {m.group(0)} by name, not through docUrl")
                if FILE_IT.search(lit) and "issues_url" not in line:
                    problems.append(f"{rel}:{n}: a printed string says to file it with no tracker named")
    if urls == 0:
        problems.append("no docUrl argument was found under src/ — the scan read nothing")
    reasons = unknown_reasons(open(os.path.join(root, "src/contract.zig"), encoding="utf-8").read())
    listed = listed_reasons(open(os.path.join(root, "docs/report-schema.md"), encoding="utf-8").read())
    if reasons is None:
        problems.append("src/contract.zig: the UnknownReason enum was not found")
    elif listed is None:
        problems.append(f"docs/report-schema.md: no '{LIST_HEADING}' section")
    else:
        for r in sorted(reasons - listed):
            problems.append(f"docs/report-schema.md: '{LIST_HEADING}' has no line for {r}")
        for r in sorted(listed - reasons):
            problems.append(f"docs/report-schema.md: '{LIST_HEADING}' lists {r}, which UnknownReason does not have")
    return problems, urls, len(files)


def selftest():
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    failures = 0

    def run(label, want_red, edit):
        nonlocal failures
        tmp = tempfile.mkdtemp(prefix="printed-links-")
        try:
            for d in ("src", "docs"):
                shutil.copytree(os.path.join(base, d), os.path.join(tmp, d))
            for f in ("README.md", "DESIGN.md"):
                shutil.copy(os.path.join(base, f), os.path.join(tmp, f))
            edit(tmp)
            problems, _, _ = check(tmp)
            red = bool(problems)
            if red == want_red:
                print(f"ok   selftest: {label} reads {'red' if red else 'green'}")
            else:
                print(f"FAIL selftest: {label} reads {'red' if red else 'green'}")
                for p in problems[:3]:
                    print("      " + p)
                failures += 1
        finally:
            shutil.rmtree(tmp)

    def append(rel, text):
        def edit(tmp):
            with open(os.path.join(tmp, rel), "a", encoding="utf-8") as f:
                f.write(text)
        return edit

    def replace(rel, old, new):
        def edit(tmp):
            p = os.path.join(tmp, rel)
            s = open(p, encoding="utf-8").read()
            assert old in s, (rel, old)
            open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
        return edit

    def drop_doc_urls(tmp):
        for d, _, fs in os.walk(os.path.join(tmp, "src")):
            for f in fs:
                if f.endswith(".zig"):
                    p = os.path.join(d, f)
                    s = open(p, encoding="utf-8").read()
                    open(p, "w", encoding="utf-8").write(DOC_URL_LITERAL.sub('"x"', s))

    run("the tree as it is", False, lambda tmp: None)
    run("a page named by name in a printed string", True,
        append("src/report.zig", '\nconst planted = "see docs/cli.md for more";\n'))
    run("the same name after a test block", True,
        append("src/report.zig", '\ntest "t" {\n    _ = 1;\n}\nconst planted2 = "the README says so";\n'))
    run("a page named inside a test block", False,
        append("src/report.zig", '\ntest "t2" {\n    const s = "README";\n    _ = s;\n}\n'))
    run("a docUrl to a page that does not exist", True,
        append("src/report.zig", '\nconst planted3 = contract.docUrl("docs/no-such-page.md");\n'))
    run("a docUrl to an anchor no heading produces", True,
        append("src/report.zig", '\nconst planted4 = contract.docUrl("docs/cli.md#no-such-heading");\n'))
    run("a docUrl whose argument is not a literal", True,
        append("src/report.zig", '\nconst planted5 = contract.docUrl(some_path);\n'))
    run("no docUrl anywhere", True, drop_doc_urls)
    run("a 'file it' with nowhere to file", True,
        append("src/report.zig", '\nconst planted6 = "If it happens again, file it with the report attached.";\n'))
    run("a page named after a quote character literal", True,
        append("src/report.zig", "\nconst planted7 = f('\\'', \"see the README\");\n"))
    run("a docUrl to a heading that only a fenced comment spells", True,
        append("src/report.zig", '\nconst planted8 = contract.docUrl("docs/checker-cookbook.md#the-l2-checker-cross-examine-the-diagnostic-command-against-reality");\n'))
    run("a reason missing from the list", True,
        replace("docs/report-schema.md", "\n- `trace_truncated`", "\n- `trace_truncated_renamed`"))
    if failures:
        print(f"FAIL selftest: {failures} shape(s) read the wrong way")
        sys.exit(1)
    print("ok   selftest: every shape read as expected")


def main():
    if sys.argv[1:] == ["--selftest"]:
        selftest()
        return
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    problems, urls, files = check(root)
    for p in problems:
        print("FAIL " + p)
    if problems:
        sys.exit(1)
    print(f"ok   {urls} docUrl argument(s) in {files} file(s) resolve, nothing printed names a document by name, and every unknown_reason has its line")


if __name__ == "__main__":
    main()
