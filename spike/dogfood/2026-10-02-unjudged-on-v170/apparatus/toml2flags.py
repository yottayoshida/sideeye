#!/usr/bin/env python3
"""The preflight flags a sideeye.toml means, so a define is written once.

    python3 toml2flags.py <sideeye.toml>      # prints one flag or value per line

`preflight` takes flags only and `explore --config` takes the toml. Writing the define twice
by hand is two chances to disagree, and they disagree quietly: a relative path in the toml
resolves against the toml's directory and on the command line against the directory Sideeye
was started in, and a `scratch` written in one place only splits `--twice`. So the toml is
the one source, and relative paths are made absolute against the toml's directory here —
which is the resolution `docs/cli.md` gives the toml.

Keys preflight has no flag for — `check`, `marker`, the recovery pair — are dropped: preflight
does not run a checker. Exit 2 when the define cannot be spelled as flags at all: the argv form, which `preflight`
cannot take (a gate that cannot measure answers 2, never 1).
"""
import sys
import tomllib
from pathlib import Path


def main(path):
    d = tomllib.loads(Path(path).read_text())
    base = Path(path).resolve().parent
    world, define = d.get("world", {}), d.get("define", {})

    def absolute(p):
        return p if Path(p).is_absolute() else str((base / p).resolve())

    out = ["--state", absolute(world["state"])]
    for key, flag in (("operation", "--operation"), ("setup", "--setup")):
        v = define.get(key)
        if v is None:
            continue
        if isinstance(v, list):
            print(f"toml2flags: {key} is in the argv form, which preflight cannot take", file=sys.stderr)
            return 2
        out += [flag, v]
    if "cwd" in define:
        out += ["--cwd", absolute(define["cwd"])]
    if "expected_status" in define:
        out += ["--expect-status", str(define["expected_status"])]
    for s in define.get("scratch", []):
        out += ["--scratch", s]
    for a in define.get("apparatus", []):
        out += ["--apparatus", a]
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
