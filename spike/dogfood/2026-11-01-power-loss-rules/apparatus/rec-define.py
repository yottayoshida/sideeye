"""Turn a sideeye.toml into the shell variables record.sh runs: state, cwd, marker, setup, op.

A string-form command is split on single spaces with no quoting, as Sideeye splits it (ADR 0019);
a relative cwd is the toml's own directory joined with it (ADR 0007). `env:` apparatus entries are
exported; `preload:` entries are not loaded (they pin clocks and randomness, which decide no sync).
"""

import os
import shlex
import sys
import tomllib

path = sys.argv[1]
c = tomllib.load(open(path, "rb"))
w, d = c.get("world", {}), c.get("define", {})


def argv(v):
    return v if isinstance(v, list) else [x for x in v.split(" ") if x]


def line(words):
    return " ".join(shlex.quote(x) for x in words)


cwd = d.get("cwd", "/")
if not cwd.startswith("/"):
    cwd = os.path.normpath(os.path.join(os.path.dirname(path), cwd))
print("state=" + shlex.quote(w["state"]))
print("cwd=" + shlex.quote(cwd))
print("marker=" + ("yes" if d.get("marker") else "no"))
print("setup=" + shlex.quote(line(argv(d["setup"])) if d.get("setup") else ""))
print("op=" + shlex.quote(line(argv(d["operation"]))))
for a in d.get("apparatus", []):
    if a.startswith("env:") and "=" in a:
        k, v = a[4:].split("=", 1)
        print("export " + k + "=" + shlex.quote(v))
