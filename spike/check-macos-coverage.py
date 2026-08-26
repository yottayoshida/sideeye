#!/usr/bin/env python3
"""Every write-capable libsystem_kernel export is interposed or explained (#333).

The macOS twin of check-shim-coverage.py, with a different pair of real things to
compare: `dyld_info -exports` on the RUNNER'S OWN libsystem_kernel (never a
transcribed list — the library is the authority on what a target can call) against
the interpose table parsed out of shim/src/macos.zig, with the reason table below
as the one place a classified-but-uninterposed name is allowed to live.

Why this exists: the Linux check reads shim/src/linux.zig only, and says so — "a
syscall the oracle classifies and macOS does not interpose is exactly the #256
shape and this check cannot see it". That declared blind spot became #333: the
clone family was invisible to the only observer macOS has, a real file appeared
with zero operations recorded, and with any other recorded mutation present the
run PASSed. Declaring a blind spot is not covering it; this file is the cover.

What this does NOT do, so nobody reads a green run as wider than it is:
  - "Write-capable" is a semantic judgement no script can make. WATCHED below is a
    curated list; a NEW kernel export this file has never heard of is invisible to
    it. The ratchet is over the curated set, not over the export namespace.
  - Deleting a row UN-WATCHES a name silently — measured during this file's own
    falsification: dropping `clonefile` from the interposed set stayed green,
    because the set is its own universe. The darwin_libc.zig cross-check below is
    the partial anchor (a symbol declared for interposition must be interposed or
    excused, so retiring an interposition without a reason is red); a name deleted
    from EVERY list at once is beyond any in-file check, and review owns that.
  - It says nothing about whether an interposed wrapper is CORRECT — the CI legs
    beside it carry that (the clone-counting leg, the argument-order leg, the
    copyfile-DATA pin).
  - The runner's OS lags releases, so an Apple-side change reaches this check when
    the runners reach that OS, not when users do.

Fail-closed discipline (the "never read a 2 as a pass" rule): dyld_info's textual
output is not a stable API. This script exits 2 (BROKEN) when the export parse
looks implausible — too few exports, or any interposed symbol missing from the
export list — because a format change that parses to zero names must never be a
green run that checked nothing.

Usage: check-macos-coverage.py <shim/src/macos.zig> <shim/src/darwin_libc.zig>
(macOS only)
"""

import re
import subprocess
import sys

KERNEL = "/usr/lib/system/libsystem_kernel.dylib"

# The curated write-capable set: every uninterposed-at-the-time name the #333
# enumeration produced, plus the names the batch interposed. Each row is either
# INTERPOSED (the table in macos.zig must list it) or carries the reason it is
# deliberately not. Removing a row, or adding a kernel export here without either
# disposition, is a red run.
WATCHED_INTERPOSED = {
    # The clone family (#333): .write on the destination; separate stubs, none
    # covering the others. Rust std's fs::copy reaches fclonefileat first.
    "clonefile", "clonefileat", "fclonefileat",
    # renameat2's macOS spelling — named in the interpose table's own comment when
    # #256 closed the Linux half, and not taken until #333.
    "renamex_np", "renameatx_np",
    # Refused in scope (the shim-issued `unsupported` marker): an atomic contents
    # swap has no place in the restore model.
    "exchangedata",
    # Metadata writers, except ATTR_CMN_NAME renames — flag-dispatched in the
    # wrapper, like unlinkat(AT_REMOVEDIR).
    "setattrlist", "fsetattrlist", "setattrlistat",
    # The open variant libcopyfile imports beside plain open.
    "open_dprotected_np",
}
NOT_INTERPOSED = {
    # The mmap/async class: the mutation is a memory store no wrapper can see; the
    # syscall is only the flush. Interposing msync would record SOME of the writes
    # and lend the account a completeness it does not have. Filed as the #217-shape
    # (a different observer, after 1.0).
    "msync": "mmap-store class: the write itself is invisible to any wrapper",
    "aio_write": "async class: completion, not issuance, changes the file; same 1.0+ observer question",
    # Creates entries the snapshot classifies `.other`, which every snapshot site
    # refuses (`unsupported_state_entry`) — measured: mkfifo-as-the-only-op refuses
    # as state_changed_without_ops, and a FIFO present in the tree refuses at the
    # snapshot whatever else ran. The downstream guard, not this table, covers it.
    "mkfifo": "artifact is refused downstream by the snapshot's .other demotion (measured)",
    "mknod": "same demotion as mkfifo; also root-gated for device nodes",
    # HFS-era; answers ENOTSUP on APFS. What the watch actually buys, said
    # precisely: a red run if the export DISAPPEARS or the name gets interposed —
    # a functional revival that keeps the same export is invisible to this file.
    "undelete": "HFS relic, ENOTSUP on APFS; watched for export drift, not for revival",
}


def broken(msg: str) -> None:
    print(f"  BROKEN {msg}")
    print("         could not read what it needs — never read a 2 as a pass")
    sys.exit(2)


def main() -> None:
    if len(sys.argv) != 3:
        broken("usage: check-macos-coverage.py <shim/src/macos.zig> <shim/src/darwin_libc.zig>")
    macos_zig, libc_zig = sys.argv[1], sys.argv[2]

    try:
        src = open(macos_zig, encoding="utf-8").read()
    except OSError as e:
        broken(f"cannot read {macos_zig}: {e}")
    # entry(&ops.NAME, libc.NAME) — the replacement's ops name is the interposed
    # symbol name for every row in that table today; parsed, never transcribed.
    interposed = set(re.findall(r"entry\(&ops\.(\w+),", src))
    if len(interposed) < 30:
        broken(f"parsed only {len(interposed)} interpose entries from {macos_zig}; the table holds far more, so the parse is wrong, not the table")

    # The partial anchor against silent un-watching: every real-libc symbol declared
    # in darwin_libc.zig is there because some wrapper calls through it, and for the
    # watched-class names that means it must be interposed or excused. Retiring an
    # interposition by deleting the table row alone leaves the declaration behind,
    # and this catches it.
    try:
        libc_src = open(libc_zig, encoding="utf-8").read()
    except OSError as e:
        broken(f"cannot read {libc_zig}: {e}")
    declared = set(re.findall(r'\.name = "(\w+)"', libc_src))
    if len(declared) < 30:
        broken(f"parsed only {len(declared)} extern declarations from {libc_zig}; the parse is wrong, not the file")

    try:
        out = subprocess.run(
            ["dyld_info", "-exports", KERNEL],
            capture_output=True, text=True, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        broken(f"dyld_info did not run: {e}")
    if out.returncode != 0:
        broken(f"dyld_info exited {out.returncode}: {out.stderr.strip()[:200]}")
    exports = set(re.findall(r"^\s*0x[0-9A-Fa-f]+\s+_(\w+)\s*$", out.stdout, re.M))
    # Plausibility floor: libsystem_kernel exports hundreds of names. A parse that
    # sees fewer saw a format change, not a smaller library.
    if len(exports) < 300:
        broken(f"parsed only {len(exports)} exports from {KERNEL}; dyld_info's format has likely changed")
    # Second anchor: every interposed plain-open-style symbol must exist as an
    # export. One missing is a parse artefact or a renamed symbol — both BROKEN.
    anchor_missing = {"open", "write", "rename"} - exports
    if anchor_missing:
        broken(f"anchor symbols missing from the export parse: {sorted(anchor_missing)}")

    failures = []
    for name in sorted(declared & exports):
        if name not in interposed and name not in NOT_INTERPOSED and name != "remove":
            # `remove` is declared for its address only (its wrapper reimplements the
            # two-step); everything else declared-and-exported must be one or the other.
            failures.append(f"{name}: declared in darwin_libc.zig and exported by the kernel, but neither interposed nor excused — a retired interposition left its declaration behind, or a new declaration landed without a table row")
    for name in sorted(WATCHED_INTERPOSED):
        if name in NOT_INTERPOSED:
            failures.append(f"{name}: listed both as interposed and as excused — pick one")
        if name not in interposed:
            failures.append(f"{name}: watched as interposed, but macos.zig's table does not list it")
        if name not in exports:
            failures.append(f"{name}: watched, but {KERNEL} no longer exports it — the row is stale; re-measure and update")
    for name, reason in sorted(NOT_INTERPOSED.items()):
        if name in interposed:
            failures.append(f"{name}: excused as not interposed ({reason}) — but macos.zig now interposes it; delete the excuse")
        if name not in exports:
            failures.append(f"{name}: excused, but {KERNEL} no longer exports it — the row is stale; re-measure and update")

    if failures:
        for f in failures:
            print(f"  FAIL {f}")
        sys.exit(1)
    print(f"  watched {len(WATCHED_INTERPOSED) + len(NOT_INTERPOSED)} write-capable exports; "
          f"{len(WATCHED_INTERPOSED)} interposed, {len(NOT_INTERPOSED)} excused with reasons; "
          f"parsed {len(interposed)} interpose entries and {len(exports)} kernel exports")
    print("  ok   every watched write-capable export is interposed or explained")


if __name__ == "__main__":
    main()
