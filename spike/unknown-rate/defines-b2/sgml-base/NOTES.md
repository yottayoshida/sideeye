# sgml-base — define (explored): update-catalog

Debian description: "SGML infrastructure and SGML catalog file support";
`implemented-in::perl`, `use::configuring`/`use::organizing`,
`works-with::text`. Installed 1.31+nmu1 in the trixie image. Freshness: no
tracked file outside the selection names it (`b2-author.sh`, 2026-09-18).

Two programs, both under `/usr/sbin`. man update-catalog: "create or update
entry in SGML catalog file", SYNOPSIS `update-catalog [options] --add
centralized_catalog ordinary_catalog`; "update-catalog inserts, updates or
removes entries in the SGML centralized catalogs located in /etc/sgml". The
two catalogs are command-line paths, so the operation is one static command
line (`op.txt`) with both inside the state directory: add the seeded
ordinary catalog's entry to the seeded (empty) centralized catalog. The super
catalog `/etc/sgml/catalog` is touched only by `--update-super`, which the
operation does not pass.

Measured while authoring (container, 1.31): "Adding entry … to catalog …",
exit 0, the centralized catalog afterwards holding one `CATALOG` line naming
the ordinary one.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 3 state-changing operations observed, "two runs 2002 ms apart left
equal state under --state". No explore was run before the sweep.
