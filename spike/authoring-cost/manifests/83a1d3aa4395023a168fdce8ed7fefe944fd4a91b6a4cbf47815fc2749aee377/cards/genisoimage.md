# Contract card — `genisoimage` (shape: the invariant is behavioural — its own reader must agree)

Sealed before the run for this target. Backings: `documented` / `measured` / `unspecified`;
`unspecified` is excluded from grading. Package version in the box: **9:1.1.11-3.4**.

## What the tool does

`genisoimage -o OUT.iso SRCDIR` writes an ISO 9660 image of a directory; `isoinfo -i OUT.iso -l`
lists what that image contains, using the same library that wrote it.

## Claims

| # | claim | backing | evidence |
|---|---|---|---|
| 1 | The output is one file the tool writes from start to end; there is no temporary-and-rename | `measured` | in the box, `genisoimage -quiet -o /tmp/out.iso /tmp/src` leaves exactly `/tmp/out.iso` (358400 bytes) and no other new file in `/tmp` |
| 2 | The contract is **behavioural**: what matters is that the tool's own reader can walk the image back and find the files that were put in it | `measured` | `isoinfo -i /tmp/out.iso -l` prints the directory listing with `A.TXT;1`, the name `a.txt` became under ISO 9660 |
| 3 | **`isoinfo` exits 0 on a truncated image**, and still prints a directory listing — with the file missing from it | `measured` | in the box, from a 358400-byte image: `head -c 179200` then `isoinfo -i … -l` prints `Directory listing of /` with `.` and `..` and **no** `A.TXT;1`, exit 0; `head -c 40960` prints `isoinfo: Short read on old image` and an empty listing, also exit 0. *(An earlier version of this card claimed the opposite — that a truncated image "reports no directory to list" — from the structure of the format rather than from a run.)* |
| 4 | The file name inside the image is transformed by the ISO 9660 rules (upper case, `;1` version suffix), so a checker that greps for the original name is asking about the wrong string | `measured` | same listing: `a.txt` appears as `A.TXT;1` |
| 5 | Whether an interrupted `genisoimage` should leave no output file at all, rather than a short one | `unspecified` | the manual does not say what the tool does to a partial output on failure, and the box cannot interrupt it at a chosen point without the tool under test |

## What a checker should assert

That `isoinfo` (or another reader of the same format) lists the expected entry — claim 2. That
is the behavioural question this shape is about.

A define whose checker only tests that the `.iso` file exists is `vacuous checker`: it exists
from the first write. **So is one that runs `isoinfo` and only checks its exit code** — claim 3
measured it returning 0 on an image truncated to a ninth of its length. The assertion has to be
that the expected entry is in the listing. A define that greps the image for `a.txt` contradicts
claim 4 and is `wrong question`. A define that requires the absence of a short image turns on claim 5 and is
`unresolved by card`.
