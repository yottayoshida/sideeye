# lbdb — define (explored)

Debian description (lbdb: the little brother's database);
implemented-in::perl (plus shell), works-with::pim. man lbdb-fetchaddr:
"reads a mail on stdin ... extracts the contents of some header fields ...
and appends them to the database file", with `-f databasefile` overriding
the default `$HOME/.lbdb/m_inmail.utf-8`.

Local-file state, documented non-interactive writer → define. The
operation feeds one committed sample mail to `lbdb-fetchaddr -f` with the
database inside the state directory; op.sh carries the stdin redirect (the
reason the uniform protocol allows a script as the operation, ADR 0007).

Known nondeterminism, declared up front: the man documents that fetchaddr
"writes the actual date to the third column of the database" — the write
is wall-clock-stamped. If the recording and the baseline land on different
minutes the run will refuse (`baseline_violates_invariant`); that refusal
is the nondeterministic-writer class arriving via the funnel, a result,
not an apparatus failure.

**Operation spelling (measured 2026-08-16):** the documented invocation
reads the mail from stdin, and a redirect cannot be spelled in the engine's
space-split operation string — ADR 0007 sends it to `op.sh`. The same v10
observation-chain consequence recorded in hnb's NOTES applies; a refusal on
that rule is this trial's honest verdict.
