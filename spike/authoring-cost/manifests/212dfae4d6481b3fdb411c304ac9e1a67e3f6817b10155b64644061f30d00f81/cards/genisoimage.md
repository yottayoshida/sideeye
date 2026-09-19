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
| 3 | A partially written image is a file that exists and is the wrong length; nothing in the format makes a prefix of an image a valid image | `measured` | the listing in claim 2 comes from structures the tool writes after the file data (the path tables and the directory records), so a truncated image loses them; `isoinfo` on a truncated copy reports no directory to list |
| 4 | The file name inside the image is transformed by the ISO 9660 rules (upper case, `;1` version suffix), so a checker that greps for the original name is asking about the wrong string | `measured` | same listing: `a.txt` appears as `A.TXT;1` |
| 5 | Whether an interrupted `genisoimage` should leave no output file at all, rather than a short one | `unspecified` | the manual does not say what the tool does to a partial output on failure, and the box cannot interrupt it at a chosen point without the tool under test |

## What a checker should assert

That `isoinfo` (or another reader of the same format) lists the expected entry — claim 2. That
is the behavioural question this shape is about.

A define whose checker only tests that the `.iso` file exists is `vacuous checker`: it exists
from the first write. A define that greps the image for `a.txt` contradicts claim 4 and is
`wrong question`. A define that requires the absence of a short image turns on claim 5 and is
`unresolved by card`.
