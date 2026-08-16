# bogofilter-bdb — define (explored)

Debian description: "fast Bayesian spam filter (Berkeley DB)";
implemented-in::c, works-with::db. man bogofilter: registration options
`[-s | -n]` (register spam / non-spam), general options `[-d dir]` (the
wordlist directory) and `[-I filename]` (read the message from a file
instead of stdin).

Local-file state (the wordlist database under `-d`), documented
non-interactive writer → define. Setup registers one ham message, creating
the wordlist; the operation registers a spam message — the documented
learning write, one invocation, everything under the state directory.
