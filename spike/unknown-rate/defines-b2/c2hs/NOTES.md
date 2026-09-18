# c2hs — define (explored)

Debian description: "C->Haskell Interface Generator"; `implemented-in::haskell`,
`use::converting`, `works-with::software:source`. Installed 0.28.8-1 in the
trixie image. Freshness: no tracked file outside the selection names it
(`b2-author.sh`, 2026-09-18).

man c2hs: SYNOPSIS `c2hs [OPTIONS]... header-file binding-file`; `-o FILE,
--output=FILE` "output result to FILE (should end in .hs)"; "header-file is
the header file belonging to the marshalled library. It must end with suffix
.h. binding-file is the corresponding Haskell binding file, which must end
with suffix .chs." The program names its output file, so the operation is
one static command line (`op.txt`): generate `Hello.hs` from the seeded
`hello.h` and `Hello.chs` beside them. `setup.sh` seeds a one-function header
and the smallest binding file that exercises the generator — one `{# fun #}`
hook.

Measured while authoring (container, 0.28.8): c2hs runs the C preprocessor
on the header and refuses without one — "c2hs: does not exist (file:
`cpp')", exit 1 — so `packages.txt` names `cpp`, which the sweep image
installs. (The first binding file written for this trial used the wrong
quote characters in the hook and was rejected with syntax errors; the
committed one is the manual's form, `` `Int' ``.)

**Authoring run (2026-09-18, v1.5.0 in the trixie image), with `cpp`:**
`preflight --twice` accepted — 14 state-changing operations observed (the
preprocessed header and the generated module), "two runs 2001 ms apart left
equal state under --state". No explore was run before the sweep.
