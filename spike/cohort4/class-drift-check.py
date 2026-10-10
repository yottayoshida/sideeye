"""Hold the analyser's class set to the engine's, so the copy cannot drift.

preflight-analyse.py maps syscall names onto the engine's kill-point
OpClass names. That is a second copy of a declaration whose home is
src/contract.zig, which is exactly the shape #65 is open about — a
declaration living in hand-synced copies across spike/. A comment asking
the next person to remember is not a check; this is.

Run from preflight.sh --selftest. Exit 0 when the sets match, 1 when they
do not, 2 when the check could not read what it needs (never read a 2 as
a pass).

Usage: class-drift-check.py <src/contract.zig> <preflight-analyse.py>
"""

import importlib.util
import re
import sys
from pathlib import Path


def engine_classes(path):
    # Not a position inside the enum and not a comment used as a marker: a class
    # added below the marker would drop out of this set with the check still
    # green. spike/check-shim-coverage.py already reads the `=> true` arm of
    # `isKillPoint`, which is the definition itself.
    spec = importlib.util.spec_from_file_location(
        "check_shim_coverage", Path(__file__).resolve().parent.parent / "check-shim-coverage.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.kill_point_classes(path)


def analyser_classes(path):
    body = open(path).read()
    head = body.index("SYSCALL_CLASS = {")
    block = body[head:body.index("}", head)]
    return set(re.findall(r':\s*"([a-z_]+)"', block))


def main(argv):
    if len(argv) != 3:
        print("  BROKEN usage: class-drift-check.py <contract.zig> <analyse.py>")
        return 2
    try:
        engine = engine_classes(argv[1])
        analyser = analyser_classes(argv[2])
    except (OSError, ValueError) as exc:
        print("  BROKEN could not read the declarations: %s" % exc)
        return 2
    if not engine or not analyser:
        print("  BROKEN one side parsed empty (engine=%d, analyser=%d) — a zero here"
              " means the parse broke, not that the sets agree"
              % (len(engine), len(analyser)))
        return 2

    missing = sorted(engine - analyser)
    extra = sorted(analyser - engine)
    print("  engine kill-point classes: %d, analyser classes: %d"
          % (len(engine), len(analyser)))
    if missing:
        print("  FAILED the analyser does not know these engine classes: %s"
              % ", ".join(missing))
    if extra:
        print("  FAILED the analyser invents classes the engine does not have: %s"
              % ", ".join(extra))
    if missing or extra:
        return 1
    print("  ok      the analyser's class set matches src/contract.zig exactly")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
