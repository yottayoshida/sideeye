# aggregate — wall W3 (no non-interactive writer)

Debian description: "ipv4 cidr prefix aggregator"; `implemented-in::c`,
`use::filtering`/`use::organizing`, `works-with::text`. Installed 1.6-8 in
the trixie image.

Freshness: `b2-author.sh`'s word-match grep names nine tracked files outside
the selection (`BUILDLOG.md`, `spike/unknown-rate/count.py`,
`spike/explore-cost/corpus.py`, `spike/macos-oracle/sudo-survey*`, …). Each
hit is the English word — "the `timew_test` aggregate depends on a `doc`
target", "dtrace aggregate rows 0", a function that aggregates counts — and
none is contact with this program. Recorded as a false hit, not a W0.

man aggregate: "Takes a list of prefixes in conventional format on stdin, and
performs two optimisations to attempt to reduce the length of the prefix
list"; SYNOPSIS `aggregate [-m max-length] [-o max-opt-length] [-p
default-length] [-q] [-t] [-v]` — no file argument, no output option, no
redirect in the documented invocation. The optimised list goes to standard
output. (roffit's define in this group carries a redirect because its own
SYNOPSIS is `roffit < inputfile > outputfile`; aggregate's names neither.)
No documented command changes a file. W3.
