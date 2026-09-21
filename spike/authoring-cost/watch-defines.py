#!/usr/bin/env python3
"""Snapshot every define an authoring subject writes, and the scripts beside it (#618, #639).

Usage: watch-defines.py <watch-root> <revisions-dir>
       watch-defines.py --selftest

Every second, each `*.toml` under the watch root (excluding the revisions directory itself) is
hashed. A path whose content differs from the last content seen **at that path** is copied to
`<revisions>/NN.toml`, numbered in the order the changes were observed, and a row is appended to
`<revisions>/index.tsv`:

    NN<TAB>iso8601<TAB>sha256<TAB>path

Why an artefact watcher rather than a wrapper around the engine: the subject unpacks the engine
itself, so a shim on `PATH` would both announce that the tool is already installed and be walked
around by an invocation that names a path. Watching the file catches a define that was written
and never run, which is the case #618 cares most about — the first wrong reading, abandoned
before it produced a verdict.

## The scripts beside the define (#639)

A define names a `check` and a `setup`, and `grade-rubric.md` defines one of its four verdicts
entirely in terms of the checker's behaviour. Snapshotting `*.toml` alone handed every grader a
verdict class they could not reach, and each of them said so unprompted. So the second column:

    <revisions>/scripts/MM.<basename>
    <revisions>/scripts/index.tsv     MM<TAB>iso8601<TAB>sha256<TAB>path<TAB>revision<TAB>note

It lives **inside** the revisions directory on purpose. `run-authoring.sh` lifts the run out with
`docker cp <box>:/home/user/revisions/. …`, so the scripts travel with no change to the launcher
or the image; and the existing "skip anything under the revisions directory" rule then keeps the
watcher from snapshotting its own output, which is the loop that would otherwise grow a row per
second forever. `audit.py` and `assign-grading.py` both read `revisions/*.toml` with a
non-recursive glob, so a subdirectory there is invisible to them and the revision sequence they
check is untouched.

**What is captured is stated positively, not by exclusions.** The watch root is `/home/user` —
the whole home — so a rule of the form "everything except …" reaches the shell dotfiles, the
image's own README, the engine tarball and, worst, this watcher's own `index.tsv`. A file is
captured only when it sits under a directory that holds a define this watcher has already
snapshotted. Measured over the five recorded runs, those directories are exactly the five the
subjects worked in, and none of them contains the revisions directory.

Within such a directory a file is skipped when it is a `*.toml` (that is the other column), when
it is under the define's `[world] state` (that is the target's data, not the subject's writing),
or when it is larger than MAX_SCRIPT_BYTES — the last is recorded as a row saying so rather than
dropped in silence.

**`state` is resolved against the define file's own directory**, and that is this watcher's rule,
not the engine's: the engine resolves a relative `[world] state` against its own working
directory, which a file watcher cannot know. Six of the eight recorded revisions spell it
relatively (`./state` four times, `state` twice) and the two rules agree on every one of them,
but they are different rules and a define could be written where they disagree.

## What it cannot see, stated here rather than assumed away

  * a define written and rewritten within one second shows as one revision;
  * a define held only in the subject's head, or piped straight into the engine, is not a file
    and is not seen. The transcript still holds it: the engine prints what it judged on every
    run, so `audit.py` derives the **judged-set sequence** from there and every run publishes
    it beside this snapshot count. Measured over the first four runs, three reached a judged set
    no snapshot caught, so the two counts differ routinely and a difference is **published, not
    refused** — the first item above produces one legitimately. What is refused is a record that
    does not carry its sequence, or carries one its transcript does not support. (This clause
    read "the audit's counts will disagree, which is a refusal rather than a silent gap" until
    2026-09-19, and nothing had ever performed that refusal — five published runs went through
    in silence. Refusing the difference itself would refuse the first item above.);
  * content is the key, so a define reverted to an earlier text counts as a new revision — the
    sequence is what was tried, not the set of distinct texts;
  * a script written **before** the first define in its directory is not captured at the moment
    it is written, because no directory qualifies yet. It is captured with the content it has
    when the define appears;
  * **a script the define names outside its own directory.** Capture is by directory, so a
    `check = "/home/user/bin/check.sh"` beside a define in `/home/user/case/` is not collected.
    All five recorded runs name scripts inside the define's directory, which is why the rule
    holds there, but nothing stops a define from pointing elsewhere;
  * a file the subject changed that the image had put there is captured — correctly, since the
    subject wrote it — but it is not distinguished in the index from a file the subject created;
  * anything the subject wrote in a **subdirectory** of the define's directory.
"""

import hashlib
import shutil
import sys
import tempfile
import time
import tomllib
from datetime import datetime, timezone
from pathlib import Path

POLL_SECONDS = 1
MAX_SCRIPT_BYTES = 256 * 1024


def digest(path):
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def is_engine_report(path):
    """True for a file that is one of Sideeye's own JSON reports.

    Identified by the report's own `schema` field (`docs/report-schema.md`: the literal
    `"sideeye/report"`), read from the head of the file rather than guessed from the name — the
    two recorded cases are both called `report.json`, but nothing makes them be.
    """
    try:
        with open(path, "rb") as fh:
            head = fh.read(200)
    except OSError:
        return False
    return b'"sideeye/report"' in head.replace(b" ", b"")


def stamp():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def state_dir(toml_path, body):
    """The `[world] state` a define names, resolved against the define file's own directory.

    Returns None when the define does not parse (a half-written file is the normal case at one
    poll per second) or names no state.
    """
    try:
        doc = tomllib.loads(body.decode("utf-8"))
    except Exception:
        return None
    raw = (doc.get("world") or {}).get("state")
    if not isinstance(raw, str) or not raw:
        return None
    p = Path(raw)
    return p if p.is_absolute() else (toml_path.parent / p)


class Watch:
    """One sweep's worth of memory, so the loop body can be driven by the selftest."""

    def __init__(self, root, revisions):
        self.root = Path(root)
        self.revisions = Path(revisions)
        self.scripts = self.revisions / "scripts"
        self.seen = {}           # toml path -> sha
        self.seen_script = {}    # script path -> sha
        self.count = 0           # revision number
        self.script_count = 0
        self.current = {}        # define directory -> revision number currently in force
        self.states = {}         # define directory -> set of resolved state directories

    def start(self):
        # Everything already under the root is the image's, not the subject's: the shell
        # dotfiles, the README the Dockerfile copies in, the engine tarball it downloads. They
        # are remembered at their current content, so they are captured only if the subject
        # CHANGES one — which is the subject writing, and is what this column is for. Without
        # this a define written directly in `/home/user/authoring` swept the README and the
        # tarball into the grading material (measured).
        for path in self.root.rglob("*"):
            if path.is_file():
                h = digest(path)
                if h is not None:
                    self.seen_script[path] = h
        self.revisions.mkdir(parents=True, exist_ok=True)
        self.scripts.mkdir(parents=True, exist_ok=True)
        index = self.revisions / "index.tsv"
        if not index.exists():
            index.write_text("# NN\tobserved\tsha256\tpath\n", encoding="utf-8")
        sindex = self.scripts / "index.tsv"
        if not sindex.exists():
            sindex.write_text(
                "# MM\tobserved\tsha256\tpath\trevision\tnote\n", encoding="utf-8"
            )

    # -- the two columns -------------------------------------------------------------------

    def sweep_defines(self):
        for path in sorted(self.root.rglob("*.toml")):
            if self.revisions in path.parents:
                continue
            h = digest(path)
            if h is None or self.seen.get(path) == h:
                continue
            body = path.read_bytes()
            self.seen[path] = h
            self.count += 1
            (self.revisions / f"{self.count:02d}.toml").write_bytes(body)
            with (self.revisions / "index.tsv").open("a", encoding="utf-8") as fh:
                fh.write(f"{self.count:02d}\t{stamp()}\t{h}\t{path}\n")
            self.current[path.parent] = self.count
            sd = state_dir(path, body)
            self.states.setdefault(path.parent, set())
            if sd is not None:
                self.states[path.parent].add(sd)

    def sweep_scripts(self):
        for d in sorted(self.current):
            # **Direct children only.** A subject's scripts sit beside the define in all five
            # recorded runs; the target's data sits under `state/`, a subdirectory. Recursing
            # captured that data whenever the state could not be resolved — a define that parses
            # but names no `[world] state` is enough, and it stayed captured because the content
            # never changes again (measured).
            # This define's own state, NOT the union over every define seen. `[world] state` is
            # a directory (`docs/cli.md`) and only direct children are swept, so a state's
            # contents are already out of reach and the union bought nothing — while costing
            # something real: where one define declares a directory that another define lives
            # in, the union deleted the second subject's scripts (measured).
            states = self.states.get(d, ())
            for path in sorted(p for p in d.iterdir() if p.is_file()):
                if self.revisions in path.parents or path.suffix == ".toml":
                    continue
                if any(st == path or st in path.parents for st in states):
                    continue
                # The engine's own verdict is not the subject's writing, and `grade-rubric.md`
                # says in as many words to judge the define "not against what the tool would
                # report". Two of the five recorded runs wrote `--json report.json` straight
                # into the define's directory, so this is the ordinary case, not a corner.
                if is_engine_report(path):
                    continue
                h = digest(path)
                if h is None or self.seen_script.get(path) == h:
                    continue
                self.seen_script[path] = h
                self.script_count += 1
                rev = f"{self.current[d]:02d}"
                try:
                    size = path.stat().st_size
                except OSError:
                    continue
                if size > MAX_SCRIPT_BYTES:
                    note = f"not copied: {size} bytes, over {MAX_SCRIPT_BYTES}"
                else:
                    shutil.copyfile(
                        path, self.scripts / f"{self.script_count:02d}.{path.name}"
                    )
                    note = ""
                with (self.scripts / "index.tsv").open("a", encoding="utf-8") as fh:
                    # The note is its OWN column. An earlier draft glued it onto the
                    # revision field, which quietly made the revision unmatchable and so made
                    # the "do not offer this as material" rule in `assign-grading.py`
                    # unreachable — a guard that cannot be seen red is a guard nobody has.
                    fh.write(
                        f"{self.script_count:02d}\t{stamp()}\t{h}\t{path}\t{rev}\t{note}\n"
                    )

    def poll(self):
        self.sweep_defines()
        self.sweep_scripts()


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    w = Watch(argv[1], argv[2])
    w.start()
    while True:
        # The whole body, because this process is the box's PID 1 (`Dockerfile` CMD): an
        # exception here kills the container and takes the running session with it, and the run
        # is void rather than short. A half-written TOML read at one poll per second is the
        # ordinary case, not the exceptional one.
        try:
            w.poll()
        except Exception as e:  # noqa: BLE001 - staying alive is the whole point
            print(f"watch-defines: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
        time.sleep(POLL_SECONDS)


# -- selftest -------------------------------------------------------------------------------

def selftest():
    fails = []

    def check(label, ok, detail=""):
        print(("ok   " if ok else "FAIL ") + label + ("" if ok else f": {detail}"))
        if not ok:
            fails.append(label)

    tmp = Path(tempfile.mkdtemp(prefix="se639-watch-"))
    root = tmp / "home"
    root.mkdir(parents=True)
    revisions = root / "revisions"

    # The decoys, in the shapes the real box has them: shell dotfiles, the image's README and
    # the engine tarball, all directly under the watch root and none beside a define.
    (root / ".bashrc").write_text("export PS1='$ '\n", encoding="utf-8")
    (root / "README.md").write_text("how to use the box\n", encoding="utf-8")
    (root / "sideeye-v1.5.0-aarch64-linux.tar.gz").write_bytes(b"\x1f\x8b" + b"x" * 512)

    # The watcher is the box's PID 1, so it is running BEFORE the subject writes anything. The
    # decoys above are the image's and exist at start; everything below is the subject's and
    # appears after. An earlier version of this fixture built both halves first, which is not a
    # state the box can produce — and it hid the rule that only what changes after start counts.
    w = Watch(root, revisions)
    w.start()

    d = root / "define"
    (d / "state").mkdir(parents=True)
    (d / "state" / "a.txt").write_text("target data, not the subject's writing\n", encoding="utf-8")
    (d / "check.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (d / "mksrc.sh").write_text("#!/bin/sh\n: build the fixture\n", encoding="utf-8")
    (d / "sideeye.toml").write_text(
        '[world]\nstate = "./state"\n\n[define]\n'
        'setup = "./setup.sh"\ncheck = "./check.sh"\n',
        encoding="utf-8",
    )

    w.poll()

    srows = [
        l for l in (revisions / "scripts" / "index.tsv").read_text(encoding="utf-8").splitlines()
        if l and not l.startswith("#")
    ]
    captured = {l.split("\t")[3].rsplit("/", 1)[-1] for l in srows}
    check("the scripts beside a define are captured",
          {"check.sh", "mksrc.sh"} <= captured, sorted(captured))
    check("a script the define does not name is captured too (check.sh calls it)",
          "mksrc.sh" in captured, sorted(captured))
    # The decoy leg. Every one of these is under the watch root and none is beside a define;
    # an exclusion-list rule reaches all four, and the last one grows a row every second.
    decoys = {".bashrc", "README.md", "sideeye-v1.5.0-aarch64-linux.tar.gz", "index.tsv"}
    check("nothing outside a define's directory is captured",
          not (decoys & captured), sorted(decoys & captured))
    check("the define's own state is not captured", "a.txt" not in captured, sorted(captured))

    # A script edited while the define file does not change: the case the TOML-only watcher
    # cannot see at all, and the reason the revision number is not the unit here.
    before = sorted(p.name for p in revisions.glob("*.toml"))
    before_idx = (revisions / "index.tsv").read_bytes()
    (d / "check.sh").write_text("#!/bin/sh\ntest -s state/a.txt\n", encoding="utf-8")
    w.poll()
    srows2 = [
        l for l in (revisions / "scripts" / "index.tsv").read_text(encoding="utf-8").splitlines()
        if l and not l.startswith("#")
    ]
    check("a script edited with the define unchanged makes a new row",
          len(srows2) == len(srows) + 1, f"{len(srows)} -> {len(srows2)}")
    check("that row carries the revision that was in force",
          srows2[-1].split("\t")[4].startswith("01"), srows2[-1])
    check("the revision column is untouched by a script edit",
          sorted(p.name for p in revisions.glob("*.toml")) == before
          and (revisions / "index.tsv").read_bytes() == before_idx,
          "revisions/ moved")

    # Two captures of one name must not overwrite each other.
    names = sorted(p.name for p in (revisions / "scripts").glob("*.check.sh"))
    check("each capture of a name is kept separately", len(names) == 2, names)

    # A half-written define is the ordinary case at one poll per second. It must not raise:
    # this process is the box's PID 1.
    (d / "broken.toml").write_text('[world]\nstate = "./sta', encoding="utf-8")
    try:
        w.poll()
        check("a half-written define does not raise", True)
    except Exception as e:  # noqa: BLE001
        check("a half-written define does not raise", False, f"{type(e).__name__}: {e}")
    check("a define that does not parse still becomes a revision",
          any(l.split("\t")[3].endswith("broken.toml")
              for l in (revisions / "index.tsv").read_text(encoding="utf-8").splitlines()
              if l and not l.startswith("#")),
          "broken.toml was skipped")

    # The size ceiling is a row, not a silent drop.
    (d / "big.bin").write_bytes(b"z" * (MAX_SCRIPT_BYTES + 1))
    w.poll()
    big = [l for l in (revisions / "scripts" / "index.tsv").read_text(encoding="utf-8").splitlines()
           if "big.bin" in l]
    check("a file over the ceiling is recorded rather than dropped",
          len(big) == 1 and big[0].split("\t")[5].startswith("not copied"), big)
    check("and the note sits in its own column, leaving the revision matchable",
          len(big) == 1 and big[0].split("\t")[4].isdigit(), big)
    check("and its bytes are not copied",
          not list((revisions / "scripts").glob("*.big.bin")),
          [p.name for p in (revisions / "scripts").glob("*.big.bin")])

    # `state` resolution: absolute spelling reaches the same directory as the relative one.
    d2 = root / "define2"
    (d2 / "state").mkdir(parents=True)
    (d2 / "state" / "b.txt").write_text("more target data\n", encoding="utf-8")
    (d2 / "check.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (d2 / "sideeye.toml").write_text(
        f'[world]\nstate = "{d2 / "state"}"\n\n[define]\ncheck = "./check.sh"\n',
        encoding="utf-8",
    )
    w.poll()
    captured2 = {
        l.split("\t")[3] for l in
        (revisions / "scripts" / "index.tsv").read_text(encoding="utf-8").splitlines()
        if l and not l.startswith("#")
    }
    check("an absolute state spelling is excluded as well",
          str(d2 / "state" / "b.txt") not in captured2,
          [c for c in captured2 if "b.txt" in c])

    # -- the shapes blind review found, each one measured leaking before these two rules ------
    #
    # The watcher is the box's PID 1, so it is up BEFORE the subject writes anything. These
    # cases build their tree in that order; an earlier version of this suite built it first and
    # then started the watcher, which is not a shape the box can produce.
    def leak_case(label, image, subject, want):
        t = Path(tempfile.mkdtemp(prefix="se639-leak-"))
        r = t / "home"
        r.mkdir()
        image(r)
        ww = Watch(r, r / "revisions")
        ww.start()
        subject(r)
        ww.poll()
        ww.poll()
        got = sorted(
            l.split("\t")[3].rsplit("/", 1)[-1]
            for l in (r / "revisions" / "scripts" / "index.tsv").read_text(encoding="utf-8").splitlines()
            if l and not l.startswith("#")
        )
        check(label, got == want, f"wanted {want}, got {got}")
        shutil.rmtree(t, ignore_errors=True)

    def write(p, text):
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    # A define may parse and still name no state — then nothing tells the watcher which
    # subdirectory is the target's. Recursing captured the target's data and kept it, because
    # the content never changes again.
    leak_case(
        "a define naming no state does not drag the target's data in",
        lambda r: None,
        lambda r: (write(r / "define" / "state" / "target.bin", "x" * 40),
                   write(r / "define" / "check.sh", "#!/bin/sh\nexit 0\n"),
                   write(r / "define" / "sideeye.toml", '[define]\ncheck = "./check.sh"\n')),
        ["check.sh"],
    )

    # `prompt.md` points the subject at `/home/user/authoring`, which is where the image's
    # README and the engine tarball already are. A define written there sweeps both in unless
    # what the image brought is remembered at start.
    leak_case(
        "a define beside the image's own files captures neither",
        lambda r: (write(r / "authoring" / "README.md", "how to use the box\n"),
                   write(r / "authoring" / "sideeye-v1.5.0-aarch64-linux.tar.gz", "\x1f\x8b" + "x" * 200)),
        lambda r: (write(r / "authoring" / "state" / "t.txt", "data\n"),
                   write(r / "authoring" / "check.sh", "#!/bin/sh\nexit 0\n"),
                   write(r / "authoring" / "sideeye.toml",
                         '[world]\nstate = "./state"\n\n[define]\ncheck = "./check.sh"\n')),
        ["check.sh"],
    )

    # Two defines, one directory inside the other. The outer sweep knows nothing of the inner
    # one's state unless the exclusion is the union over every define seen.
    leak_case(
        "a define nested in another does not leak the inner target",
        lambda r: None,
        lambda r: [(write(d / "state" / "t.bin", "y" * 40),
                    write(d / "check.sh", "#!/bin/sh\nexit 0\n"),
                    write(d / "sideeye.toml",
                          '[world]\nstate = "./state"\n\n[define]\ncheck = "./check.sh"\n'))
                   for d in (r / "work", r / "work" / "case2")],
        ["check.sh", "check.sh"],
    )

    # A define whose state IS its own directory: everything beside it is the target's, so the
    # column is empty for that define rather than full of the target's data.
    leak_case(
        "a define whose state is its own directory captures nothing",
        lambda r: None,
        lambda r: (write(r / "d" / "target.bin", "z" * 40),
                   write(r / "d" / "check.sh", "#!/bin/sh\nexit 0\n"),
                   write(r / "d" / "sideeye.toml",
                         '[world]\nstate = "."\n\n[define]\ncheck = "./check.sh"\n')),
        [],
    )

    # The engine's own report, written straight into the define's directory — what
    # `dos2unix` and `dos2unix-measured` actually did (`--json .../report.json`). Handing it to a
    # grader shows the verdict the rubric tells them not to judge against.
    leak_case(
        "the engine's own report is not grading material",
        lambda r: None,
        lambda r: (write(r / "d" / "state" / "a.txt", "data\n"),
                   write(r / "d" / "check.sh", "#!/bin/sh\nexit 0\n"),
                   write(r / "d" / "report.json",
                         '{"schema": "sideeye/report", "verdict": "PASS", "crash_points": 3}\n'),
                   write(r / "d" / "sideeye.toml",
                         '[world]\nstate = "./state"\n\n[define]\ncheck = "./check.sh"\n')),
        ["check.sh"],
    )

    # …by its own schema field, not by its name: a report called anything else is still one, and
    # a `report.json` that is not one is the subject's.
    leak_case(
        "a report is recognised by its schema, not its filename",
        lambda r: None,
        lambda r: (write(r / "d" / "state" / "a.txt", "data\n"),
                   write(r / "d" / "out.json", '{"schema":"sideeye/report","verdict":"FAIL"}\n'),
                   write(r / "d" / "report.json", '{"my": "own notes about the target"}\n'),
                   write(r / "d" / "sideeye.toml",
                         '[world]\nstate = "./state"\n\n[define]\ncheck = "./check.sh"\n')),
        ["report.json"],
    )

    # Two defines where one declares the directory the other lives in. Excluding by the union of
    # every state seen deleted the second subject's checker; excluding by this define's own does
    # not, and the nesting leak is closed by sweeping direct children only.
    leak_case(
        "one define's state does not delete another define's scripts",
        lambda r: None,
        lambda r: (write(r / "a" / "case2" / "check.sh", "#!/bin/sh\nexit 0\n"),
                   write(r / "a" / "case2" / "sideeye.toml",
                         '[world]\nstate = "./state"\n\n[define]\ncheck = "./check.sh"\n'),
                   write(r / "a" / "case2" / "state" / "t.bin", "y" * 30),
                   write(r / "a" / "check.sh", "#!/bin/sh\nexit 0\n"),
                   write(r / "a" / "sideeye.toml",
                         '[world]\nstate = "./case2"\n\n[define]\ncheck = "./check.sh"\n')),
        # BOTH checkers: the inner define's own sweep keeps it. Under the union the inner one
        # disappeared, because the outer define had declared its directory as state.
        ["check.sh", "check.sh"],
    )

    # The control: the shape all five recorded runs actually used still captures both scripts,
    # so the two rules above did not simply stop the column working.
    leak_case(
        "the ordinary shape still captures the scripts beside the define",
        lambda r: None,
        lambda r: (write(r / "d" / "state" / "a.txt", "data\n"),
                   write(r / "d" / "check.sh", "#!/bin/sh\nexit 0\n"),
                   write(r / "d" / "mksrc.sh", "#!/bin/sh\n:\n"),
                   write(r / "d" / "sideeye.toml",
                         '[world]\nstate = "./state"\n\n[define]\ncheck = "./check.sh"\n')),
        ["check.sh", "mksrc.sh"],
    )

    shutil.rmtree(tmp, ignore_errors=True)
    if fails:
        sys.exit(f"selftest: {len(fails)} case(s) failed")
    print("selftest: every case behaved as documented")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        sys.exit(main(sys.argv))
