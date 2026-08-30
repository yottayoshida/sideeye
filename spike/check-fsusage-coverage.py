#!/usr/bin/env python3
"""Every call the fs_usage oracle classifies is interposed by the shim, or explained.

The Linux twin is `check-shim-coverage.py`, whose first line makes this promise for
strace and whose own header says the macOS half is missing: "a syscall the oracle
classifies and macOS does not interpose is exactly the #256 shape and this check cannot
see it". ADR 0031 gave macOS an oracle; this is that check.

The comparison is between two observers, not between a list and a namespace. The
existing `check-macos-coverage.py` compares `libsystem_kernel`'s exports against a
curated set and says so ("the ratchet is over the curated set, not over the export
namespace"); it answers a different question and stays.

WHAT MAKES THIS DIFFERENT FROM AN EXCLUSION LIST. The first draft of this check carried
a hand-written spelling table (fs_usage prints one label, libc exports another). Review
broke it in two lines: adding a row is enough to turn a real uninterposed write green,
no reason text required, and a spelling row reads as a fact rather than a decision so it
does not stop a reviewer either. That is precisely what `check-shim-coverage.py:10-27`
refuses on Linux. So nothing here is transcribed: the spelling comes from the syscall
table `/usr/bin/fs_usage` carries in its own binary, cross-referenced against the SDK's
`sys/syscall.h` by name (exact first, then a prefix match only when it is unique — the
table is not addressed by syscall number anywhere here). Both are real things this check reads; neither is a list someone can
extend to make a failure disappear. NOT_INTERPOSED, below, IS such a list — it is a
place to declare a deliberate decision, and a false declaration there passes. The
same is true of the Linux twin's table of the same name, and the same two branches
guard both: a reason for something the shim does interpose, or for something nobody
classifies, is refused. What neither can do is judge the sentence.

FAIL-CLOSED RULES, each one a way this check could have gone quiet:

  * The name table is anchored, not offset-addressed. It is the run of identifiers from
    `exit` to `guarded_writev_np` (142 entries under `strings`' default 4-character
    floor; 143 with the floor lowered, since `dup` is shorter); a missing anchor, a short
    run, or a non-identifier inside the run is BROKEN. An earlier measurement addressed
    it by line number, which is not portable across builds of fs_usage.
  * An unresolvable spelling is BROKEN, never an identity fallback. Letting an
    unresolved label fall through to "compare the label to the interpose table" would
    reopen the exact hole the spelling table opened.
  * The classifier's size is ratcheted, and its classes are anchored to the `OpClass`
    enum. Two rules because one does not do it: anchoring on names left 20 of 26 rows
    deletable, and moving the anchor to the enum did not fix that — measured at 30 of
    31, since the comparison runs classified -> interposed and a shorter classifier is
    an easier one. The enum anchor catches a class losing its last row (one of the ten
    state-changing variants); MIN_CLASSIFIED catches every other deletion.

WHAT THIS CANNOT SEE, said here rather than left to be found: the classifier itself is
written by hand, so a call neither observer knows about is outside both sides of this
comparison. This check narrows the shim's blind spot to the oracle's, and the oracle's
blind spot stays. It also runs at build time only — it is not a runtime guard, and the
default path (no `--oracle-fs-usage`) still rests on `--allow-unverified` for its PASSes.

Usage:
  check-fsusage-coverage.py <src/fsusage.zig> <src/contract.zig> <shim/src/macos.zig>
  check-fsusage-coverage.py --selftest

Exit 0 the promise holds, 1 it does not, 2 the check could not run. Never read a 2 as a
pass.
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

FS_USAGE = "/usr/bin/fs_usage"
ANCHOR_FIRST = "exit"
ANCHOR_LAST = "guarded_writev_np"
# The run measured 142 on Darwin 24.3.0. A floor rather than the number: a different
# build may carry more calls, and pinning the exact count would fail on a newer OS for
# the wrong reason. Far below it means the anchors matched something else.
MIN_TABLE = 100
IDENT = re.compile(r"^[a-z_][a-z_0-9]*(-[A-Za-z]+)?$")

# A ratchet on the classifier's size, and the only thing here that catches a row being
# deleted. The class anchor below does not: the comparison runs classified -> interposed,
# so removing a row shrinks the population and the check gets easier. Measured on the
# tree this was written against — 30 of 31 rows could be deleted one at a time with the
# check still green, and the whole guarded family could be removed from BOTH the
# classifier and the interpose table without a word. The class anchor caught exactly one
# row, `rmdir`, because it is the only member of its class.
#
# Raising this is what adding calls looks like. LOWERING it is the operation that has to
# be argued for in a review, which is the point: it turns "delete a row" from something
# nothing notices into an edit that changes a number on a line of its own.
MIN_CLASSIFIED = 31

# Calls the classifier names and the shim deliberately does not wrap. A row here is a
# claim about behaviour, and `run_check` refutes it in both directions: a name the
# shim DOES interpose is stale, and a name the classifier does not mention excuses
# nothing. Those two branches are what the Linux and macOS twins carry
# (`contradicted`/`stale`), and the first version of this file did not — review
# turned three real uninterposed writes green with three rows of invented reason.
NOT_INTERPOSED = {}

# Calls the classifier names that THIS fs_usage cannot print. Every entry is a claim
# about a real binary, and the check refutes it: a name listed here that turns out to be
# printable is BROKEN, not quietly excused — a reason nothing can contradict is just a
# way to make a failure disappear. The refutation is partial, and the paragraph below
# says which part.
#
# The three below are absent from the table this fs_usage carries, which stops at
# guarded_writev_np (SYS 487).
#
# The refutation reaches one of the three, not all of them. `renamex_np` (473) is
# inside the anchored window, so a build that starts printing it is caught. The other
# two are numbered past 487, and fs_usage's table is ordered by syscall number — a
# newer build printing them would place them AFTER the closing anchor, outside the
# window this check reads, and the row would stay green while being false. Widening
# the window means choosing a new closing anchor, which is the same problem one call
# later. Stated rather than solved.
NOT_PRINTABLE = {
    "renamex_np": "SYS_renamex_np (473) is in range but absent — the table is a curated "
                  "subset, not a dense array of syscall numbers",
    "renameatx_np": "SYS_renameatx_np (488) is past the table's last entry (487)",
    "pwritev": "SYS_pwritev (541) is far past the table's last entry (487)",
}


def broken(msg):
    print(f"BROKEN {msg}")
    sys.exit(2)


def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as e:
        broken(f"cannot read {path}: {e}")


def name_table(binary=FS_USAGE):
    """The syscall labels fs_usage can print, from its own binary. No root, no run."""
    if not pathlib.Path(binary).exists():
        broken(f"{binary} is not present; this check needs the labels it carries")
    try:
        out = subprocess.run(["strings", "-a", binary], capture_output=True,
                             text=True, timeout=120)
    except OSError as e:
        broken(f"strings did not run: {e}")
    if out.returncode != 0:
        broken(f"strings exited {out.returncode} on {binary}")
    lines = out.stdout.splitlines()
    try:
        first = lines.index(ANCHOR_FIRST)
        last = lines.index(ANCHOR_LAST)
    except ValueError:
        broken(f"anchors {ANCHOR_FIRST!r}/{ANCHOR_LAST!r} not both present in {binary}; "
               "its layout has changed and the table cannot be located")
    if last <= first:
        broken(f"anchors out of order in {binary} ({first} then {last})")
    run = lines[first:last + 1]
    if len(run) < MIN_TABLE:
        broken(f"the anchored run holds {len(run)} entries, fewer than {MIN_TABLE}; "
               "the anchors have matched something other than the syscall table")
    stray = [x for x in run if not IDENT.match(x)]
    if stray:
        broken(f"the anchored run is not a table: {len(stray)} non-identifier "
               f"entries, first {stray[0]!r}")
    return run


def sys_numbers(sdk_syscall_h):
    """SYS_* names from the SDK header. Used only to resolve a spelling, never to
    enumerate: this check's population is the classifier, not the syscall namespace."""
    names = re.findall(r"^#define\s+SYS_([a-z_0-9]+)", read(sdk_syscall_h), re.M)
    if len(names) < 300:
        broken(f"parsed only {len(names)} SYS_ names from {sdk_syscall_h}; "
               "the header's shape has changed")
    return set(names)


def resolve(label, syscalls):
    """The libc spelling for a label fs_usage prints, or None.

    Exact first. A prefix match only when it is unambiguous — `open` prefixes a dozen
    SYS_ names, and picking one of them would be inventing a fact.
    """
    if label in syscalls:
        return label
    cand = sorted(n for n in syscalls if n.startswith(label))
    if len(cand) == 1:
        return cand[0]
    return None


def classified(fsusage_zig):
    src = read(fsusage_zig)
    m = re.search(r"const table = \[_\]struct \{ name: \[\]const u8, "
                  r"class: contract\.OpClass \}\{(.*?)\n    \};", src, re.S)
    if not m:
        broken(f"could not locate the classOf table in {fsusage_zig}")
    rows = re.findall(r'\.name = "([a-z_0-9]+)", \.class = \.([a-z_]+)', m.group(1))
    if len(rows) < 15:
        broken(f"parsed only {len(rows)} rows from the classOf table; the parse is "
               "wrong, not the table")
    return rows


def kill_point_classes(contract_zig):
    """OpClass variants that name a state change. The anchor population, taken from the
    enum so that no list here can fall behind it."""
    src = read(contract_zig)
    m = re.search(r"pub const OpClass = enum\(u16\) \{(.*?)\n\};", src, re.S)
    if not m:
        broken(f"could not locate OpClass in {contract_zig}")
    body = m.group(1)
    # Kill-point ops carry values 1..99; lifecycle starts at 100 and boundary detectors
    # at 200. Only the kill-point band is a state change this check is about.
    variants = [n for n, v in re.findall(r"^\s+([a-z_]+) = (\d+),", body, re.M)
                if int(v) < 100]
    if len(variants) < 5:
        broken(f"parsed only {len(variants)} kill-point OpClass variants from "
               f"{contract_zig}; the parse is wrong, not the enum")
    return variants


def interposed(macos_zig):
    names = set(re.findall(r"entry\(&ops\.(\w+),", read(macos_zig)))
    if len(names) < 30:
        broken(f"parsed only {len(names)} interpose entries from {macos_zig}; the "
               "table holds far more, so the parse is wrong, not the table")
    return names


def run_check(fsusage_zig, contract_zig, macos_zig, sdk_syscall_h, binary=FS_USAGE):
    table = set(name_table(binary))
    syscalls = sys_numbers(sdk_syscall_h)
    rows = classified(fsusage_zig)
    anchors = kill_point_classes(contract_zig)
    wrapped = interposed(macos_zig)

    # The anchor rule: every kill-point class keeps at least one classified row. Names
    # cannot carry this — five classes have no obviously-anchorable name, and a class
    # with one row loses the class when that row goes.
    have = {cls for _, cls in rows}
    missing = [c for c in anchors if c not in have]
    if missing:
        broken("the classifier no longer names any call for these state-changing "
               f"OpClass variants: {' '.join(missing)}")

    # The ratchet. This, not the class anchor above, is what sees a row disappear.
    if len(rows) < MIN_CLASSIFIED:
        broken(f"the classifier holds {len(rows)} rows and this check was last raised to "
               f"{MIN_CLASSIFIED}; a call stopped being classified. Adding calls raises "
               "the number, and lowering it is an edit a reviewer can see")

    # NOT_INTERPOSED is the one table here a person can extend, so it is the one that has
    # to be refutable in both directions — the same discipline the Linux and macOS twins
    # apply to theirs (`contradicted` and `stale` in check-shim-coverage.py, the two FAIL
    # branches in check-macos-coverage.py). Without these, three rows of invented reason
    # text turn three real uninterposed writes green; that was measured, on this file.
    classified_names = {n for n, _ in rows}
    contradicted = sorted(n for n in NOT_INTERPOSED if n in wrapped)
    if contradicted:
        broken("excused as uninterposed, but the shim does interpose them — the rows are "
               "stale: " + " ".join(contradicted))
    orphaned = sorted(n for n in NOT_INTERPOSED if n not in classified_names)
    if orphaned:
        broken("excused, but the classifier does not name them, so the excuse covers "
               "nothing and hides nothing it claims to: " + " ".join(orphaned))

    # A stale excuse is BROKEN, not a pass. Without this the NOT_PRINTABLE table would
    # be an exclusion list: rows could sit there forever, excusing nothing, and the next
    # real unprintable name could be hidden by adding a fourth.
    stale = sorted(n for n in NOT_PRINTABLE if n in table)
    if stale:
        broken("excused as unprintable, but this fs_usage prints them — the rows are "
               "stale and must be removed: " + " ".join(stale))

    unprintable = sorted({n for n, _ in rows
                          if n not in table and n not in NOT_PRINTABLE})
    unresolved, gaps = [], []
    for name, _cls in rows:
        if name in wrapped or name in NOT_INTERPOSED:
            continue
        libc = resolve(name, syscalls)
        if libc is None:
            unresolved.append(name)
        elif libc not in wrapped and libc not in NOT_INTERPOSED:
            gaps.append((name, libc))

    if unresolved:
        broken("no libc spelling could be resolved for these classified calls, and "
               "guessing one is how a hand-written table hid a real gap: "
               + " ".join(sorted(set(unresolved))))

    rc = 0
    if unprintable:
        print("REFUSE the classifier names calls this fs_usage cannot print:")
        for n in unprintable:
            print(f"  {n}: no such label in {binary}'s own table")
        rc = 1
    if gaps:
        print("REFUSE the oracle classifies calls the shim does not interpose:")
        for name, libc in sorted(set(gaps)):
            via = "" if name == libc else f" (fs_usage prints {name!r})"
            print(f"  {libc}: classified, neither interposed nor explained{via}")
        rc = 1
    if rc:
        print(f"  classified {len(rows)}, interposed {len(wrapped)}, "
              f"table {len(table)}")
        return rc

    print(f"ok   {len(rows)} classified calls, all printable by this fs_usage and all "
          f"interposed or explained; {len(anchors)} state-changing classes anchored")
    print("     (this pair, not every call a target can make — the classifier is "
          "hand-written, so a call neither observer knows is outside both sides)")
    return 0


def _selftest():
    """Falsify each rule against its own predicate, not against the accident."""
    root = pathlib.Path(__file__).resolve().parent.parent
    fsu = root / "src/fsusage.zig"
    con = root / "src/contract.zig"
    mac = root / "shim/src/macos.zig"
    sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True,
                         text=True).stdout.strip()
    syscall_h = pathlib.Path(sdk) / "usr/include/sys/syscall.h"

    def leg(want, label, mutate=None, **kw):
        """Run the real check in a child, so a leg that edits module state cannot leak.

        A child rather than a parameter: giving run_check a way to take a different
        NOT_PRINTABLE would be a surface that exists only for the test, and the thing
        under test is what the committed module does with its committed tables.
        """
        args = dict(fsusage_zig=fsu, contract_zig=con, macos_zig=mac,
                    sdk_syscall_h=syscall_h)
        args.update(kw)
        print(f"== {label}")
        pid = os.fork()
        if pid == 0:
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, 1)
            try:
                if mutate:
                    mutate()
                sys.exit(run_check(**args))
            except SystemExit as e:
                os._exit(e.code or 0)
            except BaseException:
                # A crash is not a verdict, and without this it passes for one: an
                # unhandled exception exits the interpreter with 1, which is exactly
                # what a `leg(1, ...)` accepts. Measured — replacing the REFUSE report
                # with a `raise` left the selftest green. The child would also run the
                # parent's `finally:` on its way out and delete scratch files the parent
                # still owns.
                os._exit(9)
        _, status = os.waitpid(pid, 0)
        got = os.waitstatus_to_exitcode(status)
        if got != want:
            print(f"== self-test FAILED: {label} — exited {got}, wanted {want}")
            sys.exit(2)

    def temp_copy(path, transform):
        src = read(path)
        new = transform(src)
        if new == src:
            print(f"== self-test FAILED: the edit to {pathlib.Path(path).name} "
                  "changed nothing")
            sys.exit(2)
        fh = tempfile.NamedTemporaryFile("w", suffix=".zig", delete=False)
        fh.write(new)
        fh.close()
        return fh.name

    scratch = []
    try:
        leg(0, "green leg: the committed tree holds in both directions")

        # A whole OpClass losing its rows. Deleting one row is NOT the shape to test:
        # the comparison runs classified -> interposed, so removing rows shrinks the
        # population and makes it pass. Measured: 20 of 26 single-row deletions stay
        # green. Only the class-level anchor sees this.
        p = temp_copy(fsu, lambda s: re.sub(
            r'\n\s+\.\{ \.name = "rmdir", \.class = \.rmdir \},', "", s))
        scratch.append(p)
        leg(2, "class-anchor leg: a state-changing class with no classified row is BROKEN",
            fsusage_zig=p)

        # A real uninterposed write, added to the classifier. This is the shape a
        # spelling table could turn green in two lines.
        p = temp_copy(fsu, lambda s: s.replace(
            '.{ .name = "write", .class = .write },',
            '.{ .name = "write", .class = .write },\n'
            '        .{ .name = "open_extended", .class = .open },'))
        scratch.append(p)
        leg(1, "gap leg: a classified call the shim does not interpose must REFUSE",
            fsusage_zig=p)

        # A label this fs_usage cannot print.
        p = temp_copy(fsu, lambda s: s.replace(
            '.{ .name = "write", .class = .write },',
            '.{ .name = "write", .class = .write },\n'
            '        .{ .name = "no_such_call_np", .class = .write },'))
        scratch.append(p)
        leg(2, "unresolvable leg: a label with no libc spelling is BROKEN, not a guess",
            fsusage_zig=p)

        # The interpose table emptied out.
        p = temp_copy(mac, lambda s: re.sub(r"entry\(&ops\.", "entry(&ops_", s))
        scratch.append(p)
        # NOTE: this leg gets its 2 from `unresolved`, not from the parse floor —
        # emptying the interpose table makes `renamex_np` reach `resolve()`, and no
        # SYS_renamex_np exists in the SDK header. The floor is therefore NOT what this
        # leg proves. Kept because the outcome is right and the path is worth naming.
        leg(2, "interpose-parse leg: an empty interpose table is BROKEN (via unresolved)",
            macos_zig=p)

        # The name table anchored to something that is not the table.
        fh = tempfile.NamedTemporaryFile("wb", suffix=".bin", delete=False)
        fh.write(b"exit\x00nonsense\x00guarded_writev_np\x00")
        fh.close()
        scratch.append(fh.name)
        leg(2, "short-table leg: an anchored run far below the floor is BROKEN",
            binary=fh.name)

        # A stale excuse. NOT_PRINTABLE is the one table here a person can extend, so it
        # is the one that has to be refutable: adding a name this fs_usage does print
        # must be BROKEN. Without this leg the table is an exclusion list, and the next
        # genuinely unprintable call could be hidden by a fourth row.
        leg(2, "stale-excuse leg: a printable name excused as unprintable is BROKEN",
            mutate=lambda: NOT_PRINTABLE.update(
                {"write": "false — this fs_usage prints write"}))

        # The four legs below cover branches that no NORMAL input reaches. Mutation
        # found all four surviving: a guard against an abnormal input is untested until
        # something makes that input. They are the reason this file grew a `mutate`
        # hook and two synthetic binaries.

        # Emptying the excuse table must surface the calls it was excusing. Without
        # this, deleting the whole printability check stays green.
        leg(1, "printability leg: an unexcused unprintable call must REFUSE",
            mutate=NOT_PRINTABLE.clear)

        # A label with no exact SYS_ name and more than one prefix match. There is no
        # such label in the real table today (measured: zero), so the branch that
        # refuses to pick one is unreachable from committed data — and stayed green
        # when it was deleted. `renam` prefixes rename, renameat and renameatx_np.
        p = temp_copy(fsu, lambda s: s.replace(
            '.{ .name = "write", .class = .write },',
            '.{ .name = "write", .class = .write },\n'
            '        .{ .name = "renam", .class = .rename },'))
        scratch.append(p)
        leg(2, "ambiguous-spelling leg: several prefix matches must not be guessed",
            fsusage_zig=p)

        # A binary long enough to clear the floor but missing an anchor.
        fh = tempfile.NamedTemporaryFile("wb", suffix=".bin", delete=False)
        fh.write(b"\x00".join(b"call_%d" % i for i in range(200)) + b"\x00")
        fh.close()
        scratch.append(fh.name)
        leg(2, "missing-anchor leg: a binary with no anchors is BROKEN",
            binary=fh.name)

        # Anchored, long enough, and not a table: one entry is not an identifier.
        fh = tempfile.NamedTemporaryFile("wb", suffix=".bin", delete=False)
        body = b"\x00".join(b"call_%d" % i for i in range(150))
        fh.write(b"exit\x00" + body + b"\x00not an identifier\x00guarded_writev_np\x00")
        fh.close()
        scratch.append(fh.name)
        leg(2, "non-identifier leg: an anchored run holding non-identifiers is BROKEN",
            binary=fh.name)

        # The ratchet. Deleting a classified row is the shape neither the class
        # anchor nor the containment comparison sees — measured at 30 of 31 rows.
        p = temp_copy(fsu, lambda s: re.sub(
            r'\n\s+\.\{ \.name = "fdatasync", \.class = \.fsync \},', "", s))
        scratch.append(p)
        leg(2, "ratchet leg: one fewer classified row is BROKEN", fsusage_zig=p)

        # NOT_INTERPOSED in both directions. Three rows of invented reason turned three
        # real uninterposed writes green before these branches existed.
        leg(2, "excuse-contradicted leg: excusing a call the shim interposes is BROKEN",
            mutate=lambda: NOT_INTERPOSED.update({"write": "false — write is interposed"}))
        leg(2, "excuse-orphaned leg: excusing a call nobody classifies is BROKEN",
            mutate=lambda: NOT_INTERPOSED.update({"no_such_call": "covers nothing"}))

        # The class anchor, separated from the ratchet. Moving `rmdir` to another class
        # leaves the row count at MIN_CLASSIFIED and empties a state-changing class, so
        # this is the one input where the anchor is the only rule that can see it.
        # Without it, deleting the anchor survives — the ratchet covers every other case.
        p = temp_copy(fsu, lambda s: s.replace(
            '.{ .name = "rmdir", .class = .rmdir },',
            '.{ .name = "rmdir", .class = .unlink },'))
        scratch.append(p)
        leg(2, "class-anchor leg: a class emptied without shrinking the table is BROKEN",
            fsusage_zig=p)

        # A crash is not a verdict. This leg exists because the guard that makes it true
        # was itself untested: with the child exiting 1 on an unhandled exception, a
        # `leg(1, ...)` accepts a crash as a REFUSE, which is how a broken report path
        # stayed green through a whole review round.
        def _boom():
            raise RuntimeError("the check itself is broken")
        leg(9, "crash leg: an exception inside the check is not a verdict", mutate=_boom)

        print("== self-test ok")
        return 0
    finally:
        for p in scratch:
            try:
                os.unlink(p)
            except OSError:
                pass


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(_selftest())
    if len(sys.argv) != 4:
        broken("usage: check-fsusage-coverage.py <src/fsusage.zig> <src/contract.zig> "
               "<shim/src/macos.zig>")
    sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True)
    if sdk.returncode != 0:
        broken("xcrun could not report the SDK path; the syscall header is needed to "
               "resolve a spelling")
    syscall_h = pathlib.Path(sdk.stdout.strip()) / "usr/include/sys/syscall.h"
    sys.exit(run_check(sys.argv[1], sys.argv[2], sys.argv[3], syscall_h))


if __name__ == "__main__":
    main()
