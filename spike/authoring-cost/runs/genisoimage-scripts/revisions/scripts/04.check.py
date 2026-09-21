#!/usr/bin/env python3
"""
What genisoimage promises about its files, and nothing more.

genisoimage is a stream producer: it opens -o with O_WRONLY|O_CREAT|O_TRUNC and
writes the image forward, sector by sector, with no lseek, no temp file, no
rename and no fsync (verified with strace on this machine; the pipeline example
in its own man page, genisoimage ... | wodim ..., only works if that is true).

So it promises:
  (1) the pathspec tree is READ ONLY -- a crash must leave src/ byte-identical;
  (2) whatever is in out.iso is a PREFIX of the image a complete run writes.

It does NOT promise that out.iso is complete, valid, mountable, or absent after
a crash, and it does not promise that a pre-existing out.iso survives (O_TRUNC
destroys it before the first sector is written). This checker asserts none of
those.

Clock-derived fields are excluded from the byte comparison: genisoimage stamps
the ISO9660 volume dates and the directory-record recording dates from the wall
clock at run time and has no option to pin them, so they are not part of the
content it reproduces. They are masked structurally -- whole date fields,
located by parsing the reference image, not by sampling two runs -- so a run
that crosses a minute or an hour boundary is still compared honestly.
"""
import hashlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HERE, "state")
SRC = os.path.join(STATE, "src")
OUT = os.path.join(STATE, "out.iso")
REF = "/tmp/sideeye-genisoimage-ref.iso"
MAN = os.path.join(HERE, "src.manifest")
SECT = 2048


def fail(msg):
    print("VIOLATION: " + msg, file=sys.stderr)
    sys.exit(1)


def manifest_of(root):
    rows = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        rows.append("d %s" % os.path.relpath(dirpath, root))
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            with open(p, "rb") as fh:
                data = fh.read()
            rows.append("f %s %d %s" % (os.path.relpath(p, root), len(data),
                                        hashlib.sha256(data).hexdigest()))
    return "\n".join(rows)


def date_mask(img):
    """Offsets in img that hold a clock-derived ISO9660 date field."""
    masked = set()
    pvd = 16 * SECT
    if img[pvd:pvd + 6] != b"\x01CD001":
        fail("no ISO9660 primary volume descriptor in the reference image")
    # PVD offsets 813..880: creation, modification, expiration, effective.
    masked.update(range(pvd + 813, pvd + 881))

    def rec_date(base, off):
        masked.update(range(base + off + 18, base + off + 25))

    def lba_len(rec):
        return (int.from_bytes(rec[2:6], "little"),
                int.from_bytes(rec[10:14], "little"))

    rec_date(pvd, 156)                       # PVD copy of the root record
    todo = [lba_len(img[pvd + 156:pvd + 190])]
    seen = set()
    while todo:
        lba, ln = todo.pop()
        if (lba, ln) in seen:
            continue
        seen.add((lba, ln))
        base = lba * SECT
        off = 0
        while off < ln:
            rec_len = img[base + off]
            if rec_len == 0:                 # rest of the sector is padding
                off = (off // SECT + 1) * SECT
                continue
            rec = img[base + off:base + off + rec_len]
            rec_date(base, off)
            name = rec[33:33 + rec[32]]
            if rec[25] & 0x02 and name not in (b"\x00", b"\x01"):
                todo.append(lba_len(rec))
            off += rec_len
    return masked


# ---- invariant 1: genisoimage never writes to the tree it reads ------------
if not os.path.isdir(SRC):
    fail("the source tree %s is gone" % SRC)
now = manifest_of(SRC)
if len(sys.argv) > 1 and sys.argv[1] == "--record":
    # setup.sh calls this once, on the pristine tree, so that the baseline the
    # checker compares against can never be a state sideeye already corrupted.
    with open(MAN, "w") as fh:
        fh.write(now)
    sys.exit(0)
if not os.path.exists(MAN):
    fail("no source manifest: setup did not run")
with open(MAN) as fh:
    want = fh.read()
if now != want:
    fail("the source tree changed; genisoimage only ever reads its pathspec")

# ---- invariant 2: out.iso is a prefix of the complete image ----------------
if os.environ.get("GENISO_SIZELOG"):
    with open(os.environ["GENISO_SIZELOG"], "a") as fh:
        fh.write("%d\n" % (os.path.getsize(OUT) if os.path.exists(OUT) else -1))

if not os.path.exists(OUT):
    sys.exit(0)          # the empty prefix: the file was never created. Legal.

rc = subprocess.run(["/usr/bin/genisoimage", "-quiet", "-o", REF, SRC],
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
if rc.returncode != 0:
    fail("could not rebuild the reference image: %s"
         % rc.stderr.decode(errors="replace").strip()[-200:])

with open(REF, "rb") as fh:
    ref = fh.read()
with open(OUT, "rb") as fh:
    got = fh.read()

if len(got) > len(ref):
    fail("out.iso is %d bytes, longer than a complete image (%d bytes)"
         % (len(got), len(ref)))

masked = date_mask(ref)
for i in range(len(got)):
    if got[i] != ref[i] and i not in masked:
        fail("out.iso byte %d (sector %d, offset %d) is 0x%02x but a complete "
             "image has 0x%02x there: the %d bytes on disk are not a prefix of "
             "the image genisoimage writes"
             % (i, i // SECT, i % SECT, got[i], ref[i], len(got)))
sys.exit(0)
