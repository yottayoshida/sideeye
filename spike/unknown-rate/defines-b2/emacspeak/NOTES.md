# emacspeak — wall W3 (no non-interactive writer)

Debian description: "speech output interface to Emacs"; debtags
`accessibility::screen-reader`, `implemented-in::lisp`, `implemented-in::perl`
and `implemented-in::tcl` (`apt-cache show`; the corpus row's class is
`perl-cli`, the first-table language among the three — the predicate admitted
the package on it), `use::editing`. Installed 53.0+dfsg-5 in the trixie image. Freshness: no
tracked file outside the selection names it (`b2-author.sh`, 2026-09-18).

The package's one executable is `/usr/sbin/emacspeakconfig`. man
emacspeakconfig: "This script records in /etc/emacspeak.conf the type of
text to speech device, the device (port) where it is connected, and the name
of the speech server used to access it"; `-i` "Initial configuration: If
/etc/emacspeakconfig exists and has all the required entries, then leave it
unchanged and ask no questions. The default is to ask regardless." Run
without a terminal it prints "Please enter the number of your choice" and
waits; the one path that asks nothing is the one that changes nothing.
emacspeak itself is an Emacs mode (man emacspeak(1)), driven from inside the
editor. No documented non-interactive command changes a file. W3.
