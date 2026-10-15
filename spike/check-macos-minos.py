#!/usr/bin/env python3
"""Every Mach-O the aarch64-macos release ships names the minimum macOS docs/cli.md states.

    check-macos-minos.py README.md docs/cli.md <sideeye> <libsideeye_shim.dylib>
    check-macos-minos.py --selftest
"""
import re
import struct
import sys
import tempfile
from pathlib import Path

MH_MAGIC_64 = b"\xcf\xfa\xed\xfe"
LC_BUILD_VERSION = 0x32
PLATFORM_MACOS = 1
NO_MACOS_VERSION = "none"


class Fail(Exception):
    pass


def one_version(path, pattern, what):
    found = re.findall(pattern, Path(path).read_text(encoding="utf-8"))
    if len(found) != 1:
        raise Fail("%s: expected exactly one %s, found %d" % (path, what, len(found)))
    major, minor = found[0]
    return (int(major), int(minor or 0))


def minos_at(data, off):
    if off + 32 > len(data):
        return None
    ncmds, sizeofcmds = struct.unpack_from("<II", data, off + 16)
    # Not trusted on the magic alone: four bytes of data can spell it, and a header whose load
    # commands do not walk to exactly sizeofcmds is such a coincidence rather than an image.
    if ncmds == 0 or ncmds > 4096 or off + 32 + sizeofcmds > len(data):
        return None
    p, end, minos = off + 32, off + 32 + sizeofcmds, None
    for _ in range(ncmds):
        if p + 8 > end:
            return None
        cmd, size = struct.unpack_from("<II", data, p)
        if size < 8 or size % 8 or p + size > end:
            return None
        if cmd == LC_BUILD_VERSION and size >= 24:
            platform, raw = struct.unpack_from("<II", data, p + 8)
            if platform == PLATFORM_MACOS:
                minos = (raw >> 16, (raw >> 8) & 0xFF)
        p += size
    if p != end:
        return None
    # Not dropped like a coincidence: these load commands walk exactly, so this is an image, and
    # one that names no macOS minimum is one the check cannot vouch for.
    return minos or NO_MACOS_VERSION


def headers(path):
    data = Path(path).read_bytes()
    if not data.startswith(MH_MAGIC_64):
        raise Fail("%s: not a thin 64-bit Mach-O" % path)
    out, i = [], 0
    while i != -1:
        m = minos_at(data, i)
        if m is not None:
            out.append((i, m))
        elif i == 0:
            raise Fail("%s: not a well-formed Mach-O at its start" % path)
        i = data.find(MH_MAGIC_64, i + 1)
    return out


def check(readme, cli_doc, binary, shim):
    floor = one_version(cli_doc, r"The asset's minimum is (\d+)\.(\d+)", "\"The asset's minimum is X.Y\"")
    promised = one_version(readme, r"Runs on macOS (\d+)(?:\.(\d+))?\+", "\"Runs on macOS N+\"")
    if floor > promised:
        raise Fail("%s states a minimum of %d.%d, above the macOS %d.%d+ that %s promises" % (cli_doc, *floor, *promised, readme))
    bad = []
    for path in (binary, shim):
        found = headers(path)
        if path == binary and len(found) < 2:
            bad.append("%s: no embedded Mach-O found, so the demo's toy went unchecked" % path)
        for off, m in found:
            if m == NO_MACOS_VERSION:
                bad.append("%s: the Mach-O at offset %d names no macOS minimum (no LC_BUILD_VERSION for macOS)" % (path, off))
            elif m != floor:
                bad.append("%s: the Mach-O at offset %d requires macOS %d.%d, where %s states %d.%d" % (path, off, *m, cli_doc, *floor))
    if bad:
        raise Fail("\n".join(bad))
    return floor


def macho(minos, platform=PLATFORM_MACOS):
    lc = struct.pack("<IIIIII", LC_BUILD_VERSION, 24, platform, (minos[0] << 16) | (minos[1] << 8), 26 << 16, 0)
    return MH_MAGIC_64 + struct.pack("<iiIIII", 0x0100000C, 0, 2, 1, len(lc), 0) + struct.pack("<I", 0) + lc


def selftest():
    junk = MH_MAGIC_64 + b"\xff" * 40
    v13, v15 = macho((13, 0)), macho((15, 0))
    cases = [
        ("the release's shape", True, "13.0", "14", v13 + junk + v13, v13),
        ("a binary built for 15.0", False, "13.0", "14", v15 + v15, v13),
        ("a 15.0 image embedded in a 13.0 binary", False, "13.0", "14", v13 + junk + v15, v13),
        ("a shim built for 15.0", False, "13.0", "14", v13 + v13, v15),
        ("a binary with nothing embedded", False, "13.0", "14", v13 + junk, v13),
        ("an embedded image that names no macOS minimum", False, "13.0", "14", v13 + junk + v13 + macho((13, 0), platform=2), v13),
        ("a stated minimum above README's promise", False, "15.0", "14", v15 + v15, v15),
    ]
    fails = 0
    with tempfile.TemporaryDirectory() as d:
        for name, want_ok, floor, promise, binary, shim in cases:
            files = {"README.md": "Runs on macOS %s+ (Apple silicon)\n" % promise,
                     "cli.md": "The asset's minimum is %s; no runner offers it\n" % floor,
                     "sideeye": binary, "shim.dylib": shim}
            for n, body in files.items():
                (Path(d) / n).write_bytes(body if isinstance(body, bytes) else body.encode())
            try:
                check(*(str(Path(d) / n) for n in files))
                ok = True
            except Fail:
                ok = False
            if ok != want_ok:
                fails += 1
                print("FAIL %s: expected %s" % (name, "green" if want_ok else "red"))
    if fails:
        print("FAIL check-macos-minos selftest: %d of %d" % (fails, len(cases)))
        return 1
    print("ok   check-macos-minos selftest: %d of %d" % (len(cases), len(cases)))
    return 0


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if len(argv) != 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        floor = check(*argv)
    except (Fail, OSError) as e:
        print("::error::%s" % e)
        return 1
    print("ok   every Mach-O in %s and %s requires macOS %d.%d" % (argv[2], argv[3], *floor))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
