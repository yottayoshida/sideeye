# dvdbackup — wall W2 (state on hardware)

Debian description: "tool to rip DVD's from the command line"; debtags
`hardware::storage:dvd`, `implemented-in::c`, `use::storing`. Installed
0.4.2-5 in the trixie image. Freshness: no tracked file outside the selection
names it (`b2-author.sh`, 2026-09-18).

man dvdbackup: "dvdbackup is a tool to extract data from video DVDs"; every
state-changing mode (`-M` mirror, `-F` feature, `-T` title set, `-t` title)
reads from `-i DEVICE`, "where DEVICE is your DVD device. This switch only needs
to be used if your DVD device node is not /dev/dvd", and writes "a DVD-Video
structure under /my/dvd/backup/dir/TITLE_NAME/VIDEO_TS". The output is local
files, but no DVD-Video source exists in the container and the manual names
none but a device: no disc, no operation. The same shape as gammu in the first
group ("addresses a connected phone or modem; no phone, no state"). W2.

Not tried: handing libdvdread an ISO image as the "device". The manual does
not say it is accepted, and a valid DVD-Video image is not something a uniform
minimal define builds from documentation.
