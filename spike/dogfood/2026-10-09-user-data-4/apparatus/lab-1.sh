#!/bin/sh
# Lab 1: the first layer's five tools, each run by hand once from a seed, under strace, to find
# the operation and read its write path (open flags, temporary names, renames, unlinks) before
# any define is written. Runs inside the box:
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-1.sh
# Prints the tool's exit status (not the pipe's — lab 1 of 2026-10-07 printed cut's).
set -u
. /ap/env.sh
O=/out/lab-1; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { # <name> <cmd...>
    n=$1; shift
    strace -f -qq -s 0 -e trace=$T -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines"
    grep -E 'O_TRUNC|O_CREAT|rename|unlink|link\(|truncate|fsync' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale|/tmp/dl' | head -${MAXL:-20}
}

echo "## scw"
rm -rf "$HOME/.config/scw"; mkdir -p /s/scw && cd /s/scw
scw config set default-zone=fr-par-1 > "$O/scw-seed.out" 2>&1; echo "seed exit $?"; ls -l "$HOME/.config/scw/"; cat "$HOME/.config/scw/config.yaml"
tr_ scw scw config set default-region=fr-par
cat "$HOME/.config/scw/config.yaml"

echo "## f2"
rm -rf /s/f2 "$HOME/.local/share/f2" "$HOME/.config/f2"; mkdir -p /s/f2 && cd /s/f2
for i in 1 2 3; do printf 'photo %s\n' $i > IMG_$i.jpg; done
tr_ f2 f2 -f IMG_ -r trip_ -x
ls -la /s/f2; find "$HOME" -path '*f2*' -type f | head; find "$HOME" -path '*f2*' -type f -exec sh -c 'echo "--- $1"; head -c 400 "$1"; echo' _ {} \; 2>/dev/null | head -20

echo "## seconv"
rm -rf /s/seconv; mkdir -p /s/seconv && cd /s/seconv
printf '1\r\n00:00:05,000 --> 00:00:07,000\r\nHello\r\n\r\n2\r\n00:00:09,000 --> 00:00:11,000\r\nWorld\r\n\r\n' > subs.srt
tr_ seconv seconv subs.srt subrip --offset:-2000 --overwrite
ls -la /s/seconv; cat /s/seconv/subs.srt | head -8

echo "## iconvert"
rm -rf /s/oiio; mkdir -p /s/oiio && cd /s/oiio
oiiotool --pattern constant:color=0.5,0.5,0.5 64x64 3 -o photo.jpg > "$O/oiio-seed.out" 2>&1; echo "seed exit $?"; ls -l
tr_ iconvert iconvert --inplace --caption hello --keyword k photo.jpg
ls -la /s/oiio; iinfo -v photo.jpg | grep -i -E 'caption|keyword' | head -3

echo "## otiotool"
rm -rf /s/otio; mkdir -p /s/otio && cd /s/otio
/opt/py/bin/python3 - > "$O/otio-seed.out" 2>&1 <<'PY'
import opentimelineio as otio
tl = otio.schema.Timeline(name="cut")
tr = otio.schema.Track(name="V1", kind=otio.schema.TrackKind.Video)
tl.tracks.append(tr)
for i in range(3):
    c = otio.schema.Clip(name=f"clip{i}", media_reference=otio.schema.ExternalReference(target_url=f"/media/take{i}.mov"),
                         source_range=otio.opentime.TimeRange(otio.opentime.RationalTime(0, 24), otio.opentime.RationalTime(48, 24)))
    tr.append(c)
otio.adapters.write_to_file(tl, "cut.otio")
PY
echo "seed exit $?"; ls -l
tr_ otiotool otiotool -i cut.otio --redact -o cut.otio
ls -la /s/otio; head -c 300 cut.otio; echo
