#!/usr/bin/env python3
"""Snapshot every define an authoring subject writes, inside the box (#618, ADR 0077).

Usage: watch-defines.py <watch-root> <revisions-dir>

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

What it cannot see, stated here rather than assumed away:

  * a define written and rewritten within one second shows as one revision;
  * a define held only in the subject's head, or piped straight into the engine, is not a file
    and is not seen (the run's transcript still holds it, and the audit's counts will disagree,
    which is a refusal rather than a silent gap);
  * content is the key, so a define reverted to an earlier text counts as a new revision — the
    sequence is what was tried, not the set of distinct texts.
"""

import hashlib
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

POLL_SECONDS = 1


def digest(path):
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    root, revisions = Path(argv[1]), Path(argv[2])
    revisions.mkdir(parents=True, exist_ok=True)
    index = revisions / "index.tsv"
    if not index.exists():
        index.write_text("# NN\tobserved\tsha256\tpath\n", encoding="utf-8")

    seen = {}
    count = 0
    while True:
        for path in sorted(root.rglob("*.toml")):
            if revisions in path.parents:
                continue
            h = digest(path)
            if h is None or seen.get(path) == h:
                continue
            seen[path] = h
            count += 1
            (revisions / f"{count:02d}.toml").write_bytes(path.read_bytes())
            stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            with index.open("a", encoding="utf-8") as fh:
                fh.write(f"{count:02d}\t{stamp}\t{h}\t{path}\n")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
