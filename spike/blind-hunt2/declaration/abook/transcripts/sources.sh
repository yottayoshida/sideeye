#!/bin/sh
# Campaign-2 Seal B artifact (abook): permitted-source transcripts, regenerated
# by this script inside the pinned container (ADR 0012 source rules via ADR
# 0015). Sources are the target's own --help / --formats output and the man
# pages shipped in the pinned Debian package. The slim image strips
# /usr/share/man, so the man pages are taken from the package file itself:
# apt-get download of the EXACT installed version (asserted below), unpacked
# with dpkg-deb into a scratch dir — nothing is installed, the image the sweep
# sealed is not altered. No source code, no traces, no bug trackers.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt2/declaration/abook/transcripts/sources.sh
set -eu
out=/work/spike/blind-hunt2/declaration/abook/transcripts

# Provenance goes to a COMMITTED transcript, not just this script's stdout
# (R1: an asserted provenance that only ever lived on a terminal cannot be
# verified from the repository).
prov=$out/sources-provenance.txt
: > "$prov"
note() { printf '%s\n' "$*" | tee -a "$prov"; }

installed=$(dpkg-query -W -f='${Version}' abook)
note "package: abook $installed (dpkg-query -W)"
note "binary: $(command -v abook) (what bare 'abook' resolves to in this image; the sealed operations name /usr/bin/abook)"

abook --help > "$out/help.txt" 2>&1
printf 'help.txt: rc=%s\n' "$?"
abook --formats > "$out/formats.txt" 2>&1
printf 'formats.txt: rc=%s\n' "$?"

d=$(mktemp -d)
cd "$d"
apt-get update >/dev/null 2>&1
apt-get download "abook=$installed" >/dev/null 2>&1
deb=$(ls abook_*.deb)
got=$(dpkg-deb -f "$deb" Version)
[ "$got" = "$installed" ] || { echo "FATAL: downloaded $got, installed $installed" >&2; exit 1; }
note "deb version check: downloaded $got == installed $installed"
note "deb: $deb sha256=$(sha256sum "$deb" | cut -d' ' -f1)"
dpkg-deb -x "$deb" x

render() { # render <groff-file.gz> <out.txt>
    if command -v col >/dev/null 2>&1; then
        MANWIDTH=80 man --no-hyphenation -l "$1" 2>/dev/null | col -bx > "$2"
    else
        MANWIDTH=80 man --no-hyphenation -l "$1" 2>/dev/null > "$2"
    fi
}
render x/usr/share/man/man1/abook.1.gz   "$out/man-abook.txt"
note "man-abook.txt: $(wc -l < "$out/man-abook.txt" | tr -d ' ') lines"
render x/usr/share/man/man5/abookrc.5.gz "$out/man-abookrc.txt"
note "man-abookrc.txt: $(wc -l < "$out/man-abookrc.txt" | tr -d ' ') lines"

# A transcript with zero lines is a renderer failure, not an empty document.
for f in "$out/help.txt" "$out/formats.txt" "$out/man-abook.txt" "$out/man-abookrc.txt"; do
    [ -s "$f" ] || { echo "FATAL: $f is empty" >&2; exit 1; }
done
note "sources: all transcripts non-empty"
