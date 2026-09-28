#!/bin/sh
# The query must be the same query, formatted or not: whitespace removed and case folded, the
# file reads as the seed's statement.
exec python3 - <<'P'
import re, sys
s = re.sub(r"\s+", "", open("/s/sqruff/proj/a.sql").read()).lower()
if s != "selecta,bfromtwherec=1":
    sys.exit("a.sql is not the seed's query: %r" % s)
P
