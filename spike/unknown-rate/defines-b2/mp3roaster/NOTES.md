# mp3roaster — wall W2 (state on hardware)

Debian description: "Perl hack for burning audio CDs out of MP3/OGG/FLAC/WAV
files"; debtags `hardware::storage:cd`, `implemented-in::perl`,
`use::storing`. Installed 0.3.0-8 in the trixie image. Freshness: no tracked
file outside the selection names it (`b2-author.sh`, 2026-09-18).

man mp3roaster: "A Perl hack for burning audio CDs out of MP3, OGG VORBIS and
FLAC files"; ENVIRONMENT "should run on all Unix like operating systems which
have Perl and wodim installed"; `-D, --dev` "CDR device to use", `-s`
"Burn speed", `-d, --dummy` "Burn with laser off". Every documented operation
ends in wodim writing a CD-R; the `-t, --temp` directory holds decoded WAVs
on the way to the drive, not a result. No drive, no state — dvdbackup's
shape in this group and gammu's in the first. W2.
