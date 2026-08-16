# 2vcard — define (explored)

Debian description: "convert an addressbook to VCARD file format";
implemented-in::perl. man 2vcard: "Per default, 2vcard reads from stdin and
writes to stdout. Alternatively, the input- and output-files can be
specified as command-line options" (`-i FILE`, `-o FILE`; the man's own
example is `2vcard -i ~/.aliases -o ~/.addbook.grcd`).

Local-file state, documented non-interactive writer → define. The state
directory holds a mutt-format alias file (the default `-f mutt`) and the
operation converts it to a `.vcf` beside it — the documented primary
function, one invocation.
