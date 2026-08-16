# cookietool — define (explored)

Debian description: "suite of programs to help maintain a fortune
database"; implemented-in::c, works-with::db. man cookietool (section 6;
the binaries live in /usr/games): "cookietool is a program that should be
used to sort, clear and maintain cookie database in standard fortune(6)
format" — invoked as `cookietool [options] <database>`, deleting duplicate
cookies and rewriting the database; a temporary file is the default and
`-o` means "overwrite directly without temporary file. CAUTION NEEDED."

Local-file state, documented non-interactive writer → define. The
operation is the default dedup rewrite (the temp-file path — the mode the
tool itself calls safe); the state directory holds one cookie database
seeded with a duplicate so the rewrite has work to do.
