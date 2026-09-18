# debmirror — wall W2 (state on a server)

Debian description: "Debian partial mirror script, with ftp and package pool
support"; `implemented-in::perl`, `use::downloading`/`use::synchronizing`,
`works-with::software:package`. Installed 1:2.47+deb13u1 in the trixie image.
Freshness: no tracked file outside the selection names it (`b2-author.sh`,
2026-09-18).

man debmirror: "This program downloads and maintains a partial local Debian
mirror … Files are transferred by ftp, and package pools are fully
supported"; the three steps are "download Packages and Sources files",
"download everything else", "clean up unknown files", and `-h, --host`
"Specify the remote host to mirror from. Defaults to ftp.debian.org". The
mirror directory is local, but every documented operation fetches from a
remote host first, and no Debian archive exists inside the sweep's container.
The same wall as httrack in this group. W2.
