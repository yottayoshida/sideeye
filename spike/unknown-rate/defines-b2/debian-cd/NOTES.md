# debian-cd — wall W3 (no command of its own)

Debian description: "Tools for building (Official) Debian CD set"; debtags
`devel::debian`, `hardware::storage:cd`, `implemented-in::perl`/`shell`,
`use::storing`. Installed 3.2.2 in the trixie image. Freshness: no tracked
file outside the selection names it (`b2-author.sh`, 2026-09-18).

The package ships no executable on the path and no manual page (`dpkg -L`:
`/etc/debian-cd/conf.sh`, `/usr/share/debian-cd/Makefile`, `build.sh`,
`README*` and 642 files of tasks, data and tools under `/usr/share/debian-cd`).
Its README.easy-build describes what the Makefile builds — "single-
architecture and multi-architecture images … creates ISO files by default;
creating jigdo files is possible; specify which Debian release to use" — from
a local Debian mirror it has to be pointed at. No documented non-interactive
command exists at the package's own surface, the first group's gnupg-agent
shape ("documents no command of its own"); behind that, the mirror it needs
is the W2 shape as well. W3.
