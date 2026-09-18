# crip — wall W2 (state on hardware)

Debian description: "terminal-based ripper/encoder/tagger tool"; debtags
`hardware::storage:cd`, `implemented-in::perl`, `use::converting`. Installed
3.9-4 in the trixie image. Freshness: no tracked file outside the selection
names it (`b2-author.sh`, 2026-09-18).

man crip: "crip is a terminal-based ripper/encoder/tagger tool for creating
Ogg Vorbis/FLAC files"; `-s media` "Specify the source media (default =
CD)", `-d device` "CDrom device to read from (default = /dev/cdrom)", `-c
flags` "Flags to pass to cdparanoia". The files it creates are local, but
the documented source is a disc in a drive; `-w on` "Skip the ripping (makes
empty .wav files)" exists to re-encode WAVs an earlier ripping left, and the
naming step defaults to an editor (`-u`, "Use editor to name the files
(default = on)"). No drive, no rip — dvdbackup's and mp3roaster's shape in
this group. W2.
