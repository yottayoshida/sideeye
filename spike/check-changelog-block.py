#!/usr/bin/env python3
"""Hold a CHANGELOG block to the things it says about itself (#374).

The file is appended per merge, so the author of an entry reads their own paragraph and
nothing else. Nothing reads a block against itself, and a release rewrites the heading
rather than the entries — so a statement an entry makes about its neighbours, or about the
block it sits in, survives the thing that made it false. Measured on 2026-09-04: `[1.0.0]`
shipped carrying "`readTrace` stays deliberately uncapped" beside the entry that capped it,
and two entries still calling `[1.0.0]` "this same unreleased block".

This checks the mechanical part only. Whether a later entry falsified an earlier claim is
prose and stays with the reader; what is checkable is that an entry does not name a
duplicate of itself, does not repeat a whole sentence of a neighbour, and that a reference
to another entry still resolves and still points the way it says.

An empty `[Unreleased]` is not a failure: that is exactly what a release leaves behind,
and the release is when the block gets read. It is skipped with a note, and the walk fails
only if it read no entries at all — a green from a walk that saw nothing says nothing.

Usage: check-changelog-block.py <CHANGELOG.md> [block ...]

With no block named, it walks `[Unreleased]` and the release directly beneath it — the
block being written, and the one whose heading was rewritten most recently. **Older
releases are deliberately not swept**: they were closed before anything read a block back,
they carry references to issues that never had an entry, and rewriting them would be
editing a record nobody can re-derive. The two blocks that move are the two that matter.
"""
import re
import sys
import pathlib
import collections

MIN_SHARED = 60  # a sentence this long, appearing twice, is a copy rather than a phrase
# The direction word has to sit beside the number it points at. Measured on the file this
# was written against: a legitimate reference keeps them within a few characters
# ("closed by #358, above", "the `#423` entry above"), while a quoted phrase that merely
# contains the word — `RESULTS.md`'s "Every number below is recomputable" — is fifty
# characters from the nearest `#N` and would otherwise be reported as a broken reference.
# The window is what keeps this check from reading English.
DIRECTION = re.compile(r"\b(above|below|later|earlier)\b", re.I)
NEAR = 25
# The qualifier is optional: "in this same block" is the commoner spelling and the one
# the release rename leaves standing, so a pattern that demanded a name missed exactly
# the case this check exists for. With no name there is nothing to compare against the
# heading, and only the "referent lives here" half applies.
SAME_BLOCK = re.compile(r"in this same (?:(\w[\w.]*) )?(?:block|release)", re.I)
BACKWARD = {"above", "earlier"}


def blocks(path):
    """Split the file into ``[name] -> [(line number, text), ...]``."""
    out, cur, name = {}, [], None
    for i, line in enumerate(path.read_text().splitlines(), 1):
        m = re.match(r"^## (\[[^\]]+\])", line)
        if m:
            if name is not None:
                out[name] = cur
            name, cur = m.group(1), []
            continue
        if name is not None:
            cur.append((i, line))
    if name is not None:
        out[name] = cur
    return out


def block_word(name):
    """The word an entry may legitimately use for the block it sits in."""
    return "unreleased" if name.lower() == "[unreleased]" else name.strip("[]").lower()


def check(path, wanted):
    bs = blocks(path)
    if not bs:
        print(f"FAIL {path}: no `## [...]` block found — the file shape changed", file=sys.stderr)
        return 1
    for name in wanted:
        if name not in bs:
            print(f"FAIL {path}: no block named {name}", file=sys.stderr)
            return 1

    # Every entry heading in the file, so a reference that reaches into another block
    # resolves. Built once: the direction is a fact about file position, not about which
    # block the reader happens to be walking.
    all_heads = {}
    for bname, body in bs.items():
        for i, l in body:
            if not l.startswith("- "):
                continue
            # Only the number in the entry's opening sentence. Searching the whole line
            # takes the first `(#N` anywhere, and four entries in this file carry one
            # hundreds of characters into the prose — registering a body citation as an
            # entry heading, which the direction test would then compare against. The
            # first sentence is where the convention puts it, and a char budget is not:
            # entry titles here run past a hundred and twenty characters.
            first = re.split(r"(?<=[.!])\s", l, maxsplit=1)[0]
            m = re.search(r"\(#(\d+)", first)
            if m:
                # Every line, not the first: sixteen issue numbers head two or three
                # entries in this file (`#199` heads three), and taking one of them meant
                # a reference to a later copy was judged against the earlier copy's
                # position. The direction holds if it holds for any copy — "the #199 entry
                # above" is true when one of the three is above, and picking which one the
                # writer meant is not something this check can do.
                all_heads.setdefault(m.group(1), []).append(i)

    failures = 0
    checked = collections.Counter()
    for name in wanted:
        entries = [(i, l) for i, l in bs[name] if l.startswith("- ")]
        block_lines = {i for i, _ in entries}
        checked["entries"] += len(entries)
        if not entries:
            # An empty `[Unreleased]` is what a release leaves behind, and the release is
            # exactly when the block gets read — so failing here would redden the commit
            # this check exists to accompany. Recorded and skipped; the walk still has to
            # have seen entries somewhere, which the check below holds.
            print(
                f"note {name}: no entries, skipped — normal right after a release rewrites\n"
                f"     the heading, and a walk that read nothing anywhere fails below"
            )
            continue

        # 1. One entry per bold title. A change re-described in a second paragraph is the
        #    shape #374's third instance had: two copies, one of them never corrected.
        titles = collections.defaultdict(list)
        for i, l in entries:
            m = re.match(r"^- \*\*(.+?)\*\*", l)
            if m:
                titles[m.group(1)].append(i)
        for t, where in titles.items():
            checked["title"] += 1
            if len(where) > 1:
                print(f"FAIL {name}: two entries share the title {t!r} (lines {where})", file=sys.stderr)
                failures += 1

        # 2. No whole sentence shared by two entries.
        sentences = collections.defaultdict(list)
        for i, l in entries:
            for s in re.split(r"(?<=[.!])\s+", l):
                s = s.strip()
                if len(s) >= MIN_SHARED:
                    sentences[s].append(i)
        for s, where in sentences.items():
            checked["sentence"] += 1
            if len(set(where)) > 1:
                print(f"FAIL {name}: lines {sorted(set(where))} share a whole sentence: {s[:90]!r}", file=sys.stderr)
                failures += 1

        # 3. A reference to another entry resolves, names this block correctly, and points
        #    the way it says. The referent is any `#N` in the same sentence that heads an
        #    entry in this block; the direction has to hold for at least one of them.
        for i, l in entries:
            for s in re.split(r"(?<=[.!])\s+", l):
                s = s.strip()
                # A quoted example is not a claim about this file. An entry that documents
                # this check quotes sentences like "fixed by #10 and #12 above", and read
                # literally those are references that do not resolve — measured on the
                # entry describing this very change. Quoted spans come out before the
                # numbers are read. The cost: a real reference inside a quotation is not
                # checked, which is the right trade for a file whose entries quote code.
                bare = re.sub(r"[\"\u201c\u201d][^\"\u201c\u201d]*[\"\u201c\u201d]", " ", s)
                nums = re.findall(r"#(\d+)", bare)
                if not nums:
                    continue
                checked["numbered"] += 1
                same = SAME_BLOCK.search(bare)
                direction = None
                for m in DIRECTION.finditer(bare):
                    if any(abs(m.start() - n.start()) <= NEAR for n in re.finditer(r"#\d+", bare)):
                        direction = m
                        break
                if not same and not direction:
                    continue
                checked["xref"] += 1

                if same and same.group(1):
                    said = same.group(1).lower()
                    want = block_word(name)
                    if said != want:
                        print(
                            f"FAIL {name} line {i}: says {said!r} block, but this block is {name} "
                            f"— a release renamed it and the sentence did not move: {s[:90]!r}",
                            file=sys.stderr,
                        )
                        failures += 1

                # A reference may point into another block — "the #270 and #324 entries
                # below" reaches from [Unreleased] into the release beneath it — so the
                # referent is looked up across the file and the direction is judged by
                # file position. Only the "this same block" clause is about this block.
                cited = [(n, w) for n in nums for w in all_heads.get(n, []) if w != i]
                if not cited:
                    # A number that heads no entry is not a broken reference: entries cite
                    # issues that were never given one — twenty-seven of the hundred and
                    # twelve numbers cited in this file — and upstream trackers use the
                    # same `#N` spelling. Reported as a note so the reader can see what the
                    # check could not follow, and not as a failure, because the alternative
                    # is a red build the day someone writes "(#5, above)" about an issue
                    # that closed before this file had entries.
                    print(
                        f"note {name} line {i}: {['#' + n for n in nums]} heads no entry here, "
                        "so the reference is not checked"
                    )
                    checked["unresolved"] += 1
                    continue

                checked["resolved"] += 1
                if same and not any(where in block_lines for _, where in cited):
                    print(
                        f"FAIL {name} line {i}: says \"this same block\" but none of "
                        f"{['#' + n for n in nums]} heads an entry in {name}: {s[:90]!r}",
                        file=sys.stderr,
                    )
                    failures += 1

                if direction:
                    back = direction.group(1).lower() in BACKWARD
                    # The referent is the number nearest the direction word, not any of
                    # them: "fixed by #10 and #12 above" passed on #12 alone while #10 sat
                    # the other way. A sentence that means two different directions has to
                    # say so in two sentences.
                    # The nearest NUMBER, then any copy of it: sixteen numbers head more
                    # than one entry, and "the #199 entry above" is true when one of the
                    # three is above. Picking a copy for the writer is not something this
                    # check can do; picking the number is.
                    nearest_num = min(
                        {n for n, _ in cited},
                        key=lambda n: min(
                            abs(direction.start() - m.start())
                            for m in re.finditer(r"#" + n + r"\b", bare)
                        ),
                    )
                    where_all = [w for n, w in cited if n == nearest_num]
                    ok = any((w < i) == back for w in where_all)
                    if not ok:
                        print(
                            f"FAIL {name} line {i}: says {direction.group(1)!r} but "
                            f"#{nearest_num}, the nearest referent, heads "
                            f"{'entries at ' + ', '.join(str(w) for w in where_all) if len(where_all) > 1 else 'line ' + str(where_all[0])}"
                            f" — the other way: {s[:90]!r}",
                            file=sys.stderr,
                        )
                        failures += 1

    if checked["entries"] == 0:
        print(
            f"FAIL {path}: walked zero entries across {wanted} — a green from a walk that "
            "read nothing says nothing about the file",
            file=sys.stderr,
        )
        return 1
    if failures:
        print(f"FAIL {failures} problem(s) across {len(wanted)} block(s)", file=sys.stderr)
        return 1
    print(
        f"ok   {len(wanted)} block(s), {checked['entries']} entries: {checked['title']} title(s), "
        f"{checked['sentence']} sentence(s), and {checked['xref']} of {checked['numbered']} sentences "
        f"carrying a `#N` — those {checked['xref']} name a direction or this block, of which "
        f"{checked['resolved']} resolve to an entry and are checked and {checked['unresolved']} name only "
        f"issues with no entry here. The other {checked['numbered'] - checked['xref']} mention an issue "
        "without pointing anywhere and are not checked."
    )
    return 0


# Four blocks, each breaking exactly one of the four things this checks. Kept beside the
# check rather than in a fixture directory because a green from a check that cannot go red
# says nothing, and CI runs this before it runs the check on the real file — the shape
# `check-adr-numbering.sh` established. Each must fail with exactly one problem: a case
# that reddens two clauses would let one of them rot unnoticed behind the other.
SELFTEST = [
    (
        "two entries share a title",
        "- **A title** (#10). One sentence that is long enough to be a real one here.\n"
        "- **A title** (#11). A different sentence that is also long enough to count.",
    ),
    (
        "two entries share a whole sentence",
        "- **First** (#10). This is one identical sentence that is definitely over sixty characters long.\n"
        "- **Second** (#11). This is one identical sentence that is definitely over sixty characters long.",
    ),
    (
        "a reference points the wrong way",
        "- **First** (#10). Nothing here.\n"
        "- **Second** (#11). Fixed by the `#10` entry below, which is not below.",
    ),
    (
        "a reference names a block this is not",
        "- **First** (#10). Nothing here.\n"
        "- **Second** (#11). Closed by #10, above in this same 1.0.0 block.",
    ),
    (
        "the nearest referent points the other way",
        "- **First** (#10). Nothing here.\n"
        "- **Second** (#11). Fixed by #10 and #12 above, and the nearer of the two is not.\n"
        "- **Third** (#12). Nothing here.",
    ),
    (
        "an unqualified 'this same block' names an entry that is elsewhere",
        "- **First** (#10). Nothing here.\n"
        "- **Second** (#11). Closed by #1, in this same block.",
    ),
]


# Blocks that must produce NO failure. The clauses that answer "leave this alone" need
# proving as much as the ones that answer "fail": a check that only demonstrates its reds
# has not shown where it stops.
SELFTEST_GREEN_CASES = [
    (
        "a quoted example is not a reference",
        "- **First** (#10). Nothing here.\n"
        "- **Second** (#11). The check reads \"fixed by #98 and #99 above\" as prose, not as a reference.",
    ),
    (
        "an issue with no entry here is noted, not failed",
        "- **First** (#10). Nothing here.\n"
        "- **Second** (#11). The probe was retired after #5 above blocked forever.",
    ),
    (
        "a number heading two entries satisfies a direction from either",
        "- **First** (#10). The early copy.\n"
        "- **Second** (#11). Fixed by #10 below, which is the later copy.\n"
        "- **Third** (#10). The later copy.",
    ),
]

def selftest():
    import tempfile
    import contextlib
    import io

    failures = 0
    with tempfile.TemporaryDirectory(prefix="changelog-selftest-") as d:
        for label, body in SELFTEST:
            f = pathlib.Path(d) / "CHANGELOG.md"
            f.write_text(
                "# Changelog\n\n## [Unreleased]\n\n### Added\n\n"
                + body
                + "\n\n## [1.0.0] - 2026-08-29\n\n### Added\n\n- Something shipped (#1). It did a thing.\n"
            )
            err = io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
                rc = check(f, ["[Unreleased]", "[1.0.0]"])
            problems = [l for l in err.getvalue().splitlines() if l.startswith("FAIL") and "problem(s)" not in l]
            if rc == 0 or len(problems) != 1:
                print(
                    f"FAIL selftest {label!r}: rc={rc}, {len(problems)} problem(s), wanted exactly 1\n"
                    + err.getvalue(),
                    file=sys.stderr,
                )
                failures += 1
        # The green cases, in the same scratch directory.
        for label, body in SELFTEST_GREEN_CASES:
            f = pathlib.Path(d) / "CHANGELOG.md"
            f.write_text(
                "# Changelog\n\n## [Unreleased]\n\n### Added\n\n"
                + body
                + "\n\n## [1.0.0] - 2026-08-29\n\n### Added\n\n- Something shipped (#1). It did a thing.\n"
            )
            err = io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
                rc = check(f, ["[Unreleased]", "[1.0.0]"])
            if rc != 0:
                print(f"FAIL selftest {label!r}: rc={rc}, wanted 0\n" + err.getvalue(), file=sys.stderr)
                failures += 1

        # And the walk itself has to be able to fail: two empty blocks read nothing.
        f = pathlib.Path(d) / "CHANGELOG.md"
        f.write_text("# Changelog\n\n## [Unreleased]\n\n## [1.0.0] - 2026-08-29\n")
        err = io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            rc = check(f, ["[Unreleased]", "[1.0.0]"])
        if rc == 0:
            print("FAIL selftest 'a walk that read nothing': rc=0, wanted non-zero", file=sys.stderr)
            failures += 1

    if failures:
        return 1
    print(
        f"ok   selftest: {len(SELFTEST)} planted defects each caught by exactly one clause, "
        f"{len(SELFTEST_GREEN_CASES)} shapes deliberately left alone, and a walk of two empty "
        "blocks refused"
    )
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    if argv[1] == "--selftest":
        return selftest()
    path = pathlib.Path(argv[1])
    if not path.is_file():
        print(f"FAIL {path}: not a file", file=sys.stderr)
        return 1
    wanted = argv[2:]
    if not wanted:
        names = list(blocks(path))
        if not names:
            print(f"FAIL {path}: no `## [...]` block found — the file shape changed", file=sys.stderr)
            return 1
        # `[Unreleased]` and the release under it, in file order.
        wanted = names[:2]
    return check(path, wanted)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
