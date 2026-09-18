# pgdbf — wall W3 (no non-interactive writer)

Debian description: "converter of XBase / FoxPro tables to PostgreSQL";
`implemented-in::c`, `use::converting`, `works-with::db`. Installed
0.6.3+git20180121.4e84775-1 in the trixie image. Freshness: the word-match
grep names `spike/unknown-rate/b-candidates.txt` — the first group's pool,
in which this package sat unselected and unread — and nothing else; not
contact.

man pgdbf: "PgDBF is a program for converting XBase databases … into a
format that PostgreSQL can directly import", SYNOPSIS `pgdbf [-cCdDeEhqQtTuU]
[-m memofile] filename [indexcolumn ...]` — the file arguments are the table
and its memo file to read; no option names a file to write, and the manual
does not say where the SQL goes. Measured while authoring (container, on a
77-byte hand-made dBase III table): the SQL — `BEGIN; … CREATE TABLE t (name
VARCHAR(10)); \COPY t FROM STDIN …` — is printed to standard output, exit 0,
and nothing in the table's directory changes. A reader whose output is the
terminal, aggregate's and zbarimg's shape in this group; the documented
invocation names no file the program changes. W3.
