#!/bin/sh
# Lab 6 (2026-10-07 user-data-3): lab 5's four open questions again — sndfile-metadata-set's flag syntax,
# ezdxf strip on a drawing that has comments, qalc writing a variable to disk, and which file testdisk
# changes (lab 5 logged into the same directory).
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-6.sh > transcripts/lab-6.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; head -10 /tmp/show.out | cut -c1-160; echo "  -> exit $rc"; }
digest() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }
PY=/opt/py/bin/python

echo "=== sndfile-metadata-set"
d=/s/snd; rm -rf $d; mkdir -p $d
$PY -I -c "import wave,struct; w=wave.open('/s/snd/a.wav','wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(b''.join(struct.pack('<h',(i*37)%3000) for i in range(16000))); w.close()"
b=$(digest $d); show sndfile-metadata-set --bext-description Take1 /s/snd/a.wav; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2
b=$(digest $d); show sndfile-metadata-set --str-comment edited /s/snd/a.wav; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2
show sndfile-info /s/snd/a.wav

echo "=== ezdxf strip on a drawing with comments"
d=/s/dxf; rm -rf $d; mkdir -p $d
$PY -I -c "import ezdxf; doc=ezdxf.new('R2018'); msp=doc.modelspace(); [msp.add_line((i,0),(i,10)) for i in range(20)]; doc.saveas('/s/dxf/drawing.dxf')"
$PY -I -c "p='/s/dxf/drawing.dxf'; t=open(p).read(); open(p,'w').write('999\ndrawn by hand, revision 7\n'+t)"
grep -c '^999' $d/drawing.dxf
b=$(digest $d); show ezdxf strip /s/dxf/drawing.dxf; echo "  state: $b -> $(digest $d)"; grep -c '^999' $d/drawing.dxf; ls -la $d | tail -n +2

echo "=== qalc: a variable saved to disk"
rm -rf $HOME/.config/qalculate $HOME/.local/share/qalculate; mkdir -p /s/qalc-in
printf 'myrate := 42\nsave definitions\n' > /s/qalc-in/a.txt
show qalc -f /s/qalc-in/a.txt; find $HOME/.config/qalculate $HOME/.local/share/qalculate -type f 2>/dev/null
printf 'store myrate 43\n' > /s/qalc-in/b.txt
show qalc -f /s/qalc-in/b.txt; find $HOME/.local/share/qalculate -type f 2>/dev/null -exec grep -l myrate {} \;
printf 'myrate := 44\nsave definitions\n' > /s/qalc-in/c.txt
b=$(digest $HOME/.local/share/qalculate 2>/dev/null); show qalc -f /s/qalc-in/c.txt; echo "  state: $b -> $(digest $HOME/.local/share/qalculate 2>/dev/null)"
find $HOME/.local/share/qalculate -type f 2>/dev/null -exec sh -c 'echo "== $1"; grep -A2 myrate "$1" | head -4' _ {} \;

echo "=== testdisk: which file changes, with the log elsewhere"
d=/s/td; rm -rf $d /s/td-in; mkdir -p $d /s/td-in; cd $d
truncate -s 32M disk.img; printf 'label: dos\nstart=2048, size=40960, type=83\n' | sfdisk -q disk.img > /dev/null 2>&1 && echo "  partitioned"
command -v mkfs.ext2 >/dev/null && { dd if=/dev/zero of=/s/td-in/p.img bs=512 count=40960 2>/dev/null; mkfs.ext2 -q -F /s/td-in/p.img && dd if=/s/td-in/p.img of=disk.img bs=512 seek=2048 conv=notrunc 2>/dev/null && echo "  ext2 written"; } || echo "  no mkfs.ext2"
dd if=/dev/zero of=disk.img bs=1 seek=446 count=64 conv=notrunc 2>/dev/null && echo "  partition table zeroed"
cd /s/td-in; b=$(sha256sum /s/td/disk.img | cut -c1-12); show testdisk /cmd /s/td/disk.img analyze,quicksearch,write; echo "  disk.img: $b -> $(sha256sum /s/td/disk.img | cut -c1-12)"; ls -la $d /s/td-in | tail -n +2
printf 'label: dos\n' > /dev/null; sfdisk -d /s/td/disk.img 2>&1 | tail -2
