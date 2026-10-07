#!/usr/bin/env python3
"""check-completions.py — `sideeye completions <shell>` offers what the usage lines list (#712).

Usage:
  python3 spike/check-completions.py <path to sideeye>

docs/cli.md: "`sideeye completions zsh|bash|fish` prints a completion script for that shell:
it offers exactly the subcommands; after a subcommand, its positional argument where its usage
line has one (a case file, a command name, a shell) and then exactly the flags its usage lines
list — explore's and preflight's two lines together, ... — with a value-taking flag's value
completed as a file where the usage names a path, as its listed words where it lists them, and
not at all otherwise."

This reads the usage lines out of `sideeye help` itself — a second reading, in Python, of the
same text the binary reads in Zig, so a script that offers a hand-kept list, or misreads a
line, disagrees with it here. Each shell's script is then asked, non-interactively, what it
completes at each position, and the answer must EQUAL the set the usage implies:
  bash  the function `complete -p sideeye` names, called with COMP_WORDS and COMP_CWORD set;
        `SIDEEYE_BASH` picks the bash (the macOS job passes /bin/bash, 3.2, and
        `SIDEEYE_EXPECT_BASH3=1` to hold it to that version)
  zsh   `zsh -f`, with compdef, compadd and _files replaced by recorders, `words` and
        `CURRENT` set, and `_sideeye` called
  fish  `complete -C "<line>"` after sourcing the script
Each runs in an empty scratch directory holding one file, `known.json`, so a file
completion is seen as that name and nothing else.

A shell that is not installed is NOT MEASURED (exit 0, said on stdout) unless
`SIDEEYE_EXPECT_SHELLS=1`, which CI sets where it installs all three.

Exit 0 holds, 1 does not, 2 could not run.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

FILE_TAGS = {"<dir>", "<path>", "<lib>", "<case.json>", "<sideeye.toml>", "<strace>"}
# The tags that take a value with nothing to offer. A tag in neither set stops the check: the
# Zig side keeps its own copy of FILE_TAGS, and a new path tag both copies read as opaque
# would agree here while the promise ("completed as a file where the usage names a path")
# went quietly false. A new tag has to be put in one set or the other by hand.
OPAQUE_TAGS = {"<cmd>", "<n>", "<s>", "<bytes>", "<entry>"}
KNOWN = "known.json"


def usage_model(sideeye):
    """{command: {"positional": kind, "flags": {flag: value}}} from `sideeye help`.
    kind/value: None (none), ("file",), ("words", [...]), ("commands",), or ("opaque",)."""
    out = subprocess.run([sideeye, "help"], capture_output=True, text=True).stdout
    model = {}
    for line in out.split("\n"):
        if not line.startswith("  sideeye "):
            continue
        tokens = line[len("  sideeye "):].split()
        cmd, rest = tokens[0], tokens[1:]
        entry = model.setdefault(cmd, {"positional": None, "flags": {}})
        if rest and not rest[0].lstrip("[").startswith("--") and rest[0] != "|":
            entry["positional"] = kind_of(rest[0])
        for i, tok in enumerate(rest):
            bare = tok.strip("[]")
            if not re.fullmatch(r"--[A-Za-z0-9][A-Za-z0-9-]*", bare):
                continue
            nxt = rest[i + 1].strip("[]") if i + 1 < len(rest) else ""
            if nxt.startswith("<") or re.fullmatch(r"[a-z]+(\|[a-z]+)+", nxt):
                entry["flags"][bare] = kind_of(nxt)
            else:
                entry["flags"].setdefault(bare, None)
    return model


class UnknownTag(Exception):
    pass


def kind_of(tok):
    bare = tok.strip("[]")
    if bare == "<command>":
        return ("commands",)
    if bare in FILE_TAGS:
        return ("file",)
    if bare.startswith("<") and bare not in OPAQUE_TAGS:
        raise UnknownTag(bare)
    if "|" in bare and not bare.startswith("<"):
        return ("words", sorted(bare.split("|")))
    return ("opaque",)


def expect_value(model, kind):
    if kind is None:
        return None
    if kind[0] == "file":
        return {KNOWN}
    if kind[0] == "words":
        return set(kind[1])
    if kind[0] == "commands":
        return set(model)
    return set()


# ------------------------------------------------------------------ shells

BASH_COMPOPT = []   # what the last ask_bash's script passed to compopt


def ask_bash(bash, script, words, line=None, point=None, cword=None):
    """`words` is COMP_WORDS as bash would cut the line; `line` the line as typed (by
    default the words joined by one space), `point` the cursor in it (by default its end)
    and `cword` the word bash says the cursor is in (by default the last). compopt is
    replaced by a recorder, kept in BASH_COMPOPT: on bash 4 and later the script's
    `compopt -o filenames` is what quotes a file name and gives a directory its slash, and
    outside a real completion the builtin only fails, silently."""
    prog = ('eval "$(cat "$1")"; fn=$(complete -p sideeye | sed -n "s/.*-F \\([^ ]*\\).*/\\1/p"); '
            '_co=; compopt() { _co="$_co $*"; }; '
            'COMP_LINE=$2; COMP_POINT=$3; COMP_CWORD=$4; shift 4; '
            'COMP_WORDS=("$@"); COMPREPLY=(); '
            '"$fn" sideeye "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"; '
            'printf "%s\\n" "${COMPREPLY[@]}"; printf "@@compopt:%s\\n" "$_co"')
    line = " ".join(words) if line is None else line
    point = len(line.encode()) if point is None else point
    cword = len(words) - 1 if cword is None else cword
    r = subprocess.run([bash, "-c", prog, "x", script, line, str(point), str(cword)] + words,
                       capture_output=True, text=True)
    out = [w for w in r.stdout.split("\n") if w]
    BASH_COMPOPT[:] = [w[len("@@compopt:"):] for w in out if w.startswith("@@compopt:")]
    return {w for w in out if not w.startswith("@@compopt:")}, r.stderr.strip()


def ask_zsh(script, words):
    prog = ('compdef() { :; }; compadd() { while [[ $1 == -* && $1 != -- ]]; do shift; done; '
            '[[ $1 == -- ]] && shift; print -rl -- "$@"; }; _files() { print -r -- ' + KNOWN + '; }; '
            'eval "$(cat "$1")"; shift; words=("$@"); CURRENT=$#; _sideeye')
    r = subprocess.run(["zsh", "-f", "-c", prog, "x", script] + words, capture_output=True, text=True)
    return {w for w in r.stdout.split("\n") if w}, r.stderr.strip()


def ask_fish(script, words):
    line = " ".join(words)
    r = subprocess.run(["fish", "--no-config", "-c", 'source $argv[1]; complete -C $argv[2]',
                        script, line], capture_output=True, text=True)
    return {w.split("\t")[0] for w in r.stdout.split("\n") if w}, r.stderr.strip()


def main(argv):
    if len(argv) != 1:
        print("usage: check-completions.py <path to sideeye>", file=sys.stderr)
        return 2
    sideeye = os.path.abspath(argv[0])
    try:
        model = usage_model(sideeye)
    except UnknownTag as exc:
        print("BROKEN the usage names a value tag %s this check does not classify: put it in "
              "FILE_TAGS or OPAQUE_TAGS here, and the same in src/cli.zig's file_tags" % exc)
        return 2
    if "completions" not in model or len(model) < 8:
        print("BROKEN the usage lines name %d commands and no `completions` line" % len(model))
        return 2
    expect_all = os.environ.get("SIDEEYE_EXPECT_SHELLS") == "1"
    bash = os.environ.get("SIDEEYE_BASH", "bash")
    shells = {"bash": shutil.which(bash) is not None, "zsh": shutil.which("zsh") is not None,
              "fish": shutil.which("fish") is not None}
    bad, measured = [], []
    with tempfile.TemporaryDirectory() as tmp, tempfile.TemporaryDirectory() as scripts:
        # The scripts live apart from the directory a file completion lists, which holds
        # `known.json` and nothing else.
        open(os.path.join(tmp, KNOWN), "w").close()
        os.chdir(tmp)
        for shell, here in shells.items():
            if not here:
                if expect_all:
                    bad.append("%s is not installed, and SIDEEYE_EXPECT_SHELLS=1 says it is" % shell)
                else:
                    print("NOT MEASURED %s: not installed here" % shell)
                continue
            r = subprocess.run([sideeye, "completions", shell], capture_output=True, text=True)
            if r.returncode != 0 or not r.stdout:
                bad.append("%s: `sideeye completions %s` exited %d with no script"
                           % (shell, shell, r.returncode))
                continue
            path = os.path.join(scripts, "script." + shell)
            with open(path, "w") as fh:
                fh.write(r.stdout)
            if shell == "bash":
                if os.environ.get("SIDEEYE_EXPECT_BASH3") == "1":
                    v = subprocess.run([bash, "-c", 'echo "${BASH_VERSINFO[0]}"'],
                                       capture_output=True, text=True).stdout.strip()
                    if v != "3":
                        bad.append("bash: SIDEEYE_EXPECT_BASH3=1 but %s is bash %s" % (bash, v))
                ask = lambda words, p=path: ask_bash(bash, p, words)
            elif shell == "zsh":
                ask = lambda words, p=path: ask_zsh(p, words)
            else:
                ask = lambda words, p=path: ask_fish(p, words)

            def same(where, words, want):
                have, err = ask(words)
                if err:
                    bad.append("%s %s: the shell wrote to stderr: %s" % (shell, where, err[:160]))
                if have != want:
                    bad.append("%s %s: offers %s, the usage says %s"
                               % (shell, where, sorted(have)[:12], sorted(want)[:12]))

            same("at the command", ["sideeye", ""], set(model))
            for cmd, entry in model.items():
                lead = ["sideeye", cmd]
                if entry["positional"] is not None:
                    same("%s's positional" % cmd, lead + [""], expect_value(model, entry["positional"]))
                    lead = lead + [KNOWN if entry["positional"][0] == "file"
                                   else next(iter(expect_value(model, entry["positional"])))]
                flags = set(entry["flags"])
                same("%s's flags" % cmd, lead + ["--"], flags)
                # A command with no flags offers nothing past its positional argument (or
                # past its name): an empty set compared, with the shell's stderr held empty.
                # (Where there are flags, fish offers them only once a `-` is typed, which is
                # fish's way; the `--` leg above measures them.)
                if not flags:
                    same("%s after its arguments" % cmd, lead + [""], set())
                for flag, value in entry["flags"].items():
                    if value is None:
                        same("%s after %s" % (cmd, flag), lead + [flag, "--"], flags)
                    else:
                        same("%s %s's value" % (cmd, flag), lead + [flag, ""],
                             expect_value(model, value))
            if shell == "bash":
                spec = subprocess.run([bash, "-c", 'eval "$(cat "$1")"; complete -p sideeye', "x", path],
                                      capture_output=True, text=True).stdout
                old = subprocess.run([bash, "-c", 'type compopt >/dev/null 2>&1 || echo old'],
                                     capture_output=True, text=True).stdout.strip() == "old"
                if re.search(r"-o (bash)?default", spec):
                    bad.append("bash: `complete -p sideeye` carries -o default, which falls back to files "
                               "where the usage offers nothing: %s" % spec.strip())
                if old and "-o filenames" not in spec:
                    bad.append("bash 3.2: no compopt, and `complete -p sideeye` lacks -o filenames, so a "
                               "file name is neither quoted nor given its slash: %s" % spec.strip())
                v4 = subprocess.run([bash, "-c", 'echo "${BASH_VERSINFO[0]}"'],
                                    capture_output=True, text=True).stdout.strip() != "3"
                tricky = os.path.join(scripts, "tricky")
                os.makedirs(os.path.join(tricky, "dir one"))
                open(os.path.join(tricky, "my case.json"), "w").close()
                os.chdir(tricky)
                for where, words in (("replay's case, named with a space", ["sideeye", "replay", ""]),
                                     ("explore --state, beside a directory", ["sideeye", "explore", "--state", ""])):
                    same(where, words, {"my case.json", "dir one"})
                    if v4 and "-o filenames" not in " ".join(BASH_COMPOPT):
                        bad.append("bash %s: the script did not ask compopt for -o filenames, which "
                                   "bash 4 and later need to quote the name and give the "
                                   "directory its slash (compopt got: %r)" % (where, BASH_COMPOPT))
                # A path holding `:`, `@`, or an escaped space before `:`. readline replaces only
                # the part past the word's last unquoted break character -- past `:`, from `@` on
                # -- on 3.2 as on 5 (measured interactively: a reply of the whole name came out
                # as `x:x\:y.json`, and `foofoo\@2x.json`). bash 4 and later also cut
                # COMP_WORDS there; the cuts below are the ones an interactive bash 5.2 made.
                # 3.2 hands each word over whole. An escaped `:` is not a break.
                open(os.path.join(tricky, "x:y.json"), "w").close()
                open(os.path.join(tricky, "foo@2x.json"), "w").close()
                open(os.path.join(tricky, "my case:1.json"), "w").close()
                os.makedirs(os.path.join(tricky, "a:dir"))
                for where, head, last, cut5, want in (
                        ("replay's case after `x:`", ["sideeye", "replay"], "x:", ["x", ":"], "y.json"),
                        ("--state after `a:d`", ["sideeye", "explore", "--state"], "a:d", ["a", ":", "d"], "dir"),
                        ("replay's case after `foo@`", ["sideeye", "replay"], "foo@", ["foo", "@"], "@2x.json"),
                        ("replay's case after `foo@2`", ["sideeye", "replay"], "foo@2", ["foo", "@", "2"], "@2x.json"),
                        ("replay's case after an escaped space and `:`", ["sideeye", "replay"],
                         "my\\ case:", ["my\\ case", ":"], "1.json"),
                        ("replay's case after an escaped `:`", ["sideeye", "replay"], "x\\:", ["x\\:"], "x:y.json")):
                    words = head + (cut5 if v4 else [last])
                    have, err = ask_bash(bash, path, words, " ".join(head + [last]))
                    if err or have != {want}:
                        bad.append("bash %s: offers %s, wanted %s%s"
                                   % (where, sorted(have), [want],
                                      (" (stderr: %s)" % err[:120]) if err else ""))
                # A Tab pressed with the cursor between two blanks before `--state`: bash says
                # the cursor is in `--state` (measured on 3.2), and the reply must be what goes
                # at the cursor -- explore's flags -- not a completion of `--state`.
                mid = "sideeye explore  --state x"
                have, err = ask_bash(bash, path, ["sideeye", "explore", "--state", "x"], mid,
                                     point=len("sideeye explore "), cword=2)
                if err or have != set(model["explore"]["flags"]):
                    bad.append("bash a Tab mid-line before --state: offers %s, wanted explore's %d flags"
                               % (sorted(have)[:6], len(model["explore"]["flags"])))
                os.chdir(tmp)
            measured.append(shell)
    if bad:
        print("FAIL the completion scripts and the usage lines disagree:")
        print("\n".join("  " + b for b in bad[:20]))
        return 1
    print("ok   completions for %s offer exactly what the usage lines of %d commands list"
          % (", ".join(measured) or "no shell", len(model)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
