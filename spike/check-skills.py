#!/usr/bin/env python3
"""Hold the agent skills under skills/ to the binary they drive (#716, ADR 0103).

Usage: check-skills.py <repo root>
       check-skills.py --selftest

The skills are installed as copies outside this repository, so nothing else reads them
against the code again. Five claims, each a failure of its own:

  1. the set: there is at least one skill, and every directory under skills/ is one named
     `sideeye-` and lowercase words joined by single hyphens, at most 64 characters — the
     prefix is what keeps an install from overwriting a user's own skill — holding SKILL.md;
  2. the frontmatter, by the Agent Skills format: `name` equal to the directory name;
     `description` present, one line, 1 to 1024 characters; no key outside the format's own;
  3. every `sideeye <command>` a skill spells names a command the usage lines (src/cli.zig)
     list, and every flag after it on that line is one that command's usage lines list — so a
     renamed or removed command reddens as surely as a flag;
  4. every name a skill borrows from the source is still there: a `sideeye_*` word, and a
     snake_case word in backticks, is an MCP tool, an MCP tool's argument, a refusal's reason
     or a define key; a key in a ```toml block is a define key; a `SIDEEYE_*` variable appears
     in src/ — an agent is never sent to call, pass or wait for what no longer exists;
  5. every link is absolute, and one into this repository goes to its main branch and to a
     path that exists in the tree — a relative link resolves to nothing once the skill is
     copied out, and another branch is not what the tree holds.

The tool, reason and key sets are the contract-freeze gate's own definitions
(spike/freeze-audit/surface-sets.sh), so the two checks cannot disagree about what exists.

Sunset: if by 2027-04-09 nobody has reported using the skills, delete them, this check and
its CI job (ADR 0103).
"""
import os
import re
import subprocess
import sys
import tempfile

KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
REPO = "https://github.com/yottayoshida/sideeye"
REPO_URL = REPO + "/blob/main/"
NAME_RE = re.compile(r"^sideeye(?:-[a-z0-9]+)+$")
# The flag shape check-completions.py and acceptance check 14 read usage lines with.
FLAG_RE = re.compile(r"--[A-Za-z0-9][A-Za-z0-9-]*")
SNAKE_RE = re.compile(r"\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b")
SURFACE_SETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "freeze-audit", "surface-sets.sh")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def surface_set(name, text):
    """One of the contract-freeze gate's enumerated sets, extracted from `text`."""
    out = subprocess.run(["sh", "-c", '. "$1"; extract_surface_set "$2"', "sh", SURFACE_SETS, name],
                         input=text, capture_output=True, text=True, check=True)
    return set(out.stdout.split())


def usage_flags(cli_src):
    """{command: set of flags} from the `sideeye <command>` lines of the usage text."""
    out = {}
    for m in re.finditer(r"^\s*\\\\  sideeye ([a-z]+)(.*)$", cli_src, re.M):
        out.setdefault(m.group(1), set()).update(FLAG_RE.findall(m.group(2)))
    return out


def mcp_arguments(mcp_src):
    """The property names in the tool catalogue's input schemas."""
    m = re.search(r"fn toolsListBody\(\).*?\n}\n", mcp_src, re.S)
    return set(re.findall(r'\\"([a-z_]+)\\":\{\\"type\\"', m.group(0))) if m else set()


def frontmatter(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end < 0:
        return None
    fields = {}
    for line in text[4:end].split("\n"):
        if not line.strip():
            continue
        k, sep, v = line.partition(":")
        if not sep:
            return None
        fields[k.strip()] = v.strip()
    return fields


def src_text(root):
    parts = []
    for d, _, files in os.walk(os.path.join(root, "src")):
        parts += [read(os.path.join(d, f)) for f in files if f.endswith(".zig")]
    return "\n".join(parts)


def check(root):
    problems = []
    mcp_src = read(os.path.join(root, "src/mcp.zig"))
    flags = usage_flags(read(os.path.join(root, "src/cli.zig")))
    tools = surface_set("mcp_tools", mcp_src)
    keys = surface_set("config_keys", read(os.path.join(root, "src/config.zig")))
    known = tools | keys | mcp_arguments(mcp_src) | surface_set("unknown_reason", read(os.path.join(root, "src/contract.zig")))
    if not flags or not tools or not keys:
        return ["could not read the usage lines, the tool catalogue or the define keys — this check did not run"], 0
    source = src_text(root)
    sdir = os.path.join(root, "skills")
    names = sorted(d for d in (os.listdir(sdir) if os.path.isdir(sdir) else []) if not d.startswith("."))
    read_n = 0
    # Claim 1.
    if not names:
        problems.append("set: skills/ holds no skill")
    for name in names:
        p = os.path.join(sdir, name, "SKILL.md")
        if not NAME_RE.match(name) or len(name) > 64:
            problems.append("set: %r is not `sideeye-` and lowercase words joined by hyphens, at most 64" % name)
            continue
        if not os.path.isfile(p):
            problems.append("set: %s has no SKILL.md" % name)
            continue
        text = read(p)
        read_n += 1
        # Claim 2.
        fm = frontmatter(text)
        if fm is None:
            problems.append("frontmatter: %s does not open with a --- block of key: value lines" % name)
        else:
            if fm.get("name") != name:
                problems.append("frontmatter: %s's name is %r" % (name, fm.get("name")))
            d = fm.get("description", "")
            if not (1 <= len(d) <= 1024):
                problems.append("frontmatter: %s's description is %d characters" % (name, len(d)))
            extra = sorted(set(fm) - KEYS)
            if extra:
                problems.append("frontmatter: %s carries keys outside the format: %s" % (name, extra))
        # Claim 3: a command and the flags after it on the same line or span.
        for m in re.finditer(r"\bsideeye ([a-z]+)\b([^`\n]*)", text):
            cmd, rest = m.group(1), m.group(2)
            if cmd not in flags:
                problems.append("command: %s spells `sideeye %s`, which the usage lines do not list" % (name, cmd))
                continue
            for f in FLAG_RE.findall(rest):
                if f not in flags[cmd]:
                    problems.append("command: %s spells `sideeye %s ... %s`, which that command's usage does not list" % (name, cmd, f))
        # Claim 4.
        borrowed = set(re.findall(r"\bsideeye_[a-z_]+", text))
        for span in re.findall(r"`([^`\n]+)`", text):
            borrowed |= set(SNAKE_RE.findall(span))
        for w in sorted(borrowed - known):
            problems.append("name: %s names `%s`, which is no MCP tool, MCP argument, refusal reason or define key" % (name, w))
        for block in re.findall(r"```toml\n(.*?)```", text, re.S):
            for k in re.findall(r"^\s*([a-z_]+)\s*=", block, re.M):
                if k not in keys:
                    problems.append("name: %s's toml example sets `%s`, which the define parser does not read" % (name, k))
        for v in sorted(set(re.findall(r"\bSIDEEYE_[A-Z_]+\b", text))):
            if not re.search(r"\b%s\b" % v, source):
                problems.append("name: %s names `%s`, which nothing under src/ reads or sets" % (name, v))
        # Claim 5.
        for link in re.findall(r"\]\(([^)]+)\)", text):
            if link.startswith(REPO_URL):
                path = link[len(REPO_URL):].split("#")[0]
                if not os.path.exists(os.path.join(root, path)):
                    problems.append("link: %s points at %s, which is not in the tree" % (name, path))
            elif link == REPO or link.startswith(REPO + "/"):
                problems.append("link: %s points into this repository off main: %s" % (name, link))
            elif not link.startswith("https://"):
                problems.append("link: %s has a relative link %r, which resolves to nothing once copied out" % (name, link))
    return list(dict.fromkeys(problems)), read_n


def selftest():
    """Each planted defect must redden exactly the claim it plants."""
    fixture = {
        "src/cli.zig": '    \\\\  sideeye explore --config <sideeye.toml> [--oracle <strace>]\n    \\\\  sideeye replay <case.json> [--shim <lib>]\n',
        "src/mcp.zig": ('fn toolsListBody() []const u8 {\n'
                        r'    return "{\"name\":\"sideeye_explore_config\"," ++' '\n'
                        r'        "\"inputSchema\":{\"type\":\"object\",\"properties\":{\"config_path\":{\"type\":\"string\"}}}}";' '\n'
                        '}\n'),
        "src/contract.zig": "pub const UnknownReason = enum {\n    case_no_longer_applies,\n};\n",
        "src/config.zig": ('// SIDEEYE_STATE_DIR\n'
                           'if (std.mem.eql(u8, key, "state")) {}\nif (std.mem.eql(u8, key, "operation")) {}\n'),
        "docs/cli.md": "x",
    }
    def good(name):
        return ("---\nname: %s\ndescription: Does a thing.\n---\n\n# T\n\n"
                "`sideeye explore --config x --oracle /usr/bin/strace`, then `sideeye_explore_config` with "
                "`config_path`; `case_no_longer_applies` means rerun; the state is in `SIDEEYE_STATE_DIR`.\n\n"
                "```toml\nstate = \"./s\"\noperation = \"x\"\n```\n\n"
                "[docs](%sdocs/cli.md)\n" % (name, REPO_URL))
    def planted(old, new):
        return {"sideeye-scout": good("sideeye-scout").replace(old, new)}
    cases = [
        ("clean", {}, None),
        ("a skill without the prefix", {"scout": good("scout")}, "set:"),
        ("a name that is not the directory", {"sideeye-scout": good("sideeye-other")}, "frontmatter:"),
        ("an unknown flag", planted("--oracle", "--frobnicate"), "command:"),
        ("a command the usage does not have", planted("sideeye explore", "sideeye rerun"), "command:"),
        ("an unknown tool", planted("sideeye_explore_config", "sideeye_frobnicate"), "name:"),
        ("an MCP argument the server does not take", planted("`config_path`", "`config_file`"), "name:"),
        ("a refusal reason the engine does not have", planted("case_no_longer_applies", "case_gone_away"), "name:"),
        ("a define key the parser does not read", planted("operation =", "opration ="), "name:"),
        ("a variable nothing reads", planted("SIDEEYE_STATE_DIR", "SIDEEYE_STATE_PATH"), "name:"),
        ("a relative link", planted(REPO_URL + "docs/cli.md", "../docs/cli.md"), "link:"),
        ("a link to a missing file", planted("docs/cli.md", "docs/gone.md"), "link:"),
        ("a link off main", planted("/blob/main/", "/blob/master/"), "link:"),
    ]
    failed = 0
    for title, override, want in cases:
        with tempfile.TemporaryDirectory() as d:
            for rel, body in fixture.items():
                os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
                with open(os.path.join(d, rel), "w", encoding="utf-8") as f:
                    f.write(body)
            files = {n: good(n) for n in ("sideeye-scout", "sideeye-triage")}
            files.update(override)
            for n, t in files.items():
                os.makedirs(os.path.join(d, "skills", n))
                with open(os.path.join(d, "skills", n, "SKILL.md"), "w", encoding="utf-8") as f:
                    f.write(t)
            problems, _ = check(d)
        kinds = {p.split(":")[0] + ":" for p in problems}
        ok = (not problems) if want is None else (kinds == {want})
        print("== %s: %s" % ("ok" if ok else "self-test FAILED", title))
        if not ok:
            for p in problems:
                print("     | " + p)
            failed += 1
    return failed


def main():
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(1 if selftest() else 0)
    if len(sys.argv) != 2:
        sys.exit("usage: check-skills.py <repo root> | --selftest")
    problems, read_n = check(sys.argv[1])
    if problems:
        for p in problems:
            print("FAIL " + p)
        sys.exit(1)
    print("ok   %d agent skills: the set, their frontmatter, every command, flag, borrowed name and link they hold" % read_n)


if __name__ == "__main__":
    main()
