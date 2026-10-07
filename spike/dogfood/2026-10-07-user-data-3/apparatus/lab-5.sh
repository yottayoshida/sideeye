#!/bin/sh
# Lab 5 (2026-10-07 user-data-3): the third screen's candidates by hand in the box, stdin at EOF.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-5.sh > transcripts/lab-5.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; head -12 /tmp/show.out | cut -c1-160; echo "  -> exit $rc"; }
digest() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }
kind() { f=$(command -v "$1" 2>/dev/null || echo "$1"); echo "  image: $f: $(file -L "$f" | sed 's/^[^:]*: //' | cut -c1-110)"; }
PY=/opt/py/bin/python

echo "=== sndfile-metadata-set: a WAV's broadcast description, in place"
kind sndfile-metadata-set
d=/s/snd; rm -rf $d; mkdir -p $d
$PY -I -c "import wave,struct; w=wave.open('/s/snd/a.wav','wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(b''.join(struct.pack('<h',(i*37)%3000) for i in range(16000))); w.close()"
ls -l $d/a.wav
b=$(digest $d); show sndfile-metadata-set --bext-description=Take1 /s/snd/a.wav; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2
b=$(digest $d); show sndfile-metadata-set --str-comment=edited /s/snd/a.wav; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2

echo "=== minizip -e: erase an entry from an archive"
kind minizip
d=/s/mz; rm -rf $d; mkdir -p $d/src; cd $d/src; for n in a b c; do head -c 4096 /dev/urandom > $n.bin; done
$PY -I -c "import zipfile; z=zipfile.ZipFile('/s/mz/a.zip','w'); [z.write(n) for n in ('a.bin','b.bin','c.bin')]; z.close()"
cd $d; b=$(digest $d); show minizip -e /s/mz/a.zip b.bin; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2

echo "=== ezdxf strip: a drawing in place"
kind $PY
d=/s/dxf; rm -rf $d; mkdir -p $d
$PY -I -c "import ezdxf; doc=ezdxf.new('R2018'); msp=doc.modelspace(); [msp.add_line((i,0),(i,10)) for i in range(20)]; doc.saveas('/s/dxf/drawing.dxf')"
grep -c '^999' $d/drawing.dxf; head -4 $d/drawing.dxf
b=$(digest $d); show ezdxf strip /s/dxf/drawing.dxf; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2
b=$(digest $d); show ezdxf strip -b /s/dxf/drawing.dxf; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2

echo "=== lasinfo: set a header field of a LAS file in place"
kind lasinfo
d=/s/las; rm -rf $d; mkdir -p $d
$PY -I - <<'PY'
import struct
pts=[(i*100, i*50, i*10, 100+i) for i in range(10)]
hdr=bytearray(227)
struct.pack_into('<4sHH',hdr,0,b'LASF',0,0)
struct.pack_into('<BB',hdr,24,1,2)
hdr[26:58]=b'sideeye-lab'.ljust(32,b'\0'); hdr[58:90]=b'lab-5'.ljust(32,b'\0')
struct.pack_into('<HHHIIBHI',hdr,90,1,2026,227,227,0,0,20,len(pts))
struct.pack_into('<5I',hdr,111,len(pts),0,0,0,0)
struct.pack_into('<3d',hdr,131,0.01,0.01,0.01); struct.pack_into('<3d',hdr,155,0,0,0)
xs=[p[0]*0.01 for p in pts]; ys=[p[1]*0.01 for p in pts]; zs=[p[2]*0.01 for p in pts]
struct.pack_into('<6d',hdr,179,max(xs),min(xs),max(ys),min(ys),max(zs),min(zs))
body=b''.join(struct.pack('<iiiHBBbBH',x,y,z,it,0,1,0,0,0) for x,y,z,it in pts)
open('/s/las/a.las','wb').write(bytes(hdr)+body)
PY
show lasinfo -i /s/las/a.las -nh -nv -nmm
b=$(digest $d); show lasinfo -i /s/las/a.las -set_file_source_ID 7; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2
b=$(digest $d); show lasinfo -i /s/las/a.las -set_system_identifier relabelled; echo "  state: $b -> $(digest $d)"

echo "=== extract-xiso -r: rewrite an Xbox image"
kind extract-xiso
d=/s/xiso; rm -rf $d /s/xiso-in; mkdir -p $d /s/xiso-in/game/media; cd /s/xiso-in
printf 'default.xbe placeholder\n' > game/default.xbe; head -c 65536 /dev/urandom > game/media/intro.bik
show extract-xiso -c game /s/xiso/game.iso; ls -la $d | tail -n +2
cd $d; b=$(digest $d); show extract-xiso -r /s/xiso/game.iso; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2

echo "=== testdisk: rewrite a disk image's partition table"
kind testdisk
d=/s/td; rm -rf $d; mkdir -p $d; cd $d
truncate -s 32M disk.img; printf 'label: dos\nstart=2048, size=40960, type=83\n' | sfdisk -q disk.img > /dev/null 2>&1 && echo "  partitioned"
command -v mkfs.ext2 && { dd if=/dev/zero of=p.img bs=512 count=40960 2>/dev/null; mkfs.ext2 -q -F p.img && dd if=p.img of=disk.img bs=512 seek=2048 conv=notrunc 2>/dev/null && rm p.img && echo "  ext2 written into the partition"; }
b=$(digest $d); show testdisk /log /cmd /s/td/disk.img analyze,quicksearch,write; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2
b=$(digest $d); show testdisk /cmd /s/td/disk.img advanced,1,boot,rebuildbs,write; echo "  state: $b -> $(digest $d)"

echo "=== xbps-pkgdb -m hold"
kind xbps-pkgdb
d=/s/xbps; rm -rf $d; mkdir -p $d/root/var/db/xbps
cat > $d/root/var/db/xbps/pkgdb-0.38.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>hello</key>
	<dict>
		<key>architecture</key>
		<string>aarch64</string>
		<key>automatic-install</key>
		<false/>
		<key>pkgver</key>
		<string>hello-2.12_1</string>
		<key>short_desc</key>
		<string>Hello world</string>
		<key>state</key>
		<string>installed</string>
	</dict>
</dict>
</plist>
PL
show xbps-query -r $d/root -l
b=$(digest $d); show xbps-pkgdb -r $d/root -m hold hello; echo "  state: $b -> $(digest $d)"; ls -la $d/root/var/db/xbps | tail -n +2; grep -A1 hold $d/root/var/db/xbps/pkgdb-0.38.plist | head -3
b=$(digest $d); show xbps-pkgdb -r $d/root -m auto hello; echo "  state: $b -> $(digest $d)"

echo "=== qalc -f: save definitions and mode"
kind qalc
rm -rf $HOME/.config/qalculate $HOME/.local/share/qalculate
mkdir -p /s/qalc-in; printf 'myrate := 42\nsave myrate\nsave mode\n' > /s/qalc-in/cmds.txt
show qalc -f /s/qalc-in/cmds.txt; find $HOME/.config/qalculate $HOME/.local/share/qalculate -type f 2>/dev/null | head
printf 'myrate := 43\nsave myrate\nsave mode\n' > /s/qalc-in/cmds2.txt
c=$HOME/.config/qalculate; b=$(digest $HOME); show qalc -f /s/qalc-in/cmds2.txt; echo "  home: $b -> $(digest $HOME)"

echo "=== mcpm: edit a server's environment"
kind mcpm
rm -rf $HOME/.config/mcpm
show mcpm --help
show mcpm new srv --type stdio --command echo --force; find $HOME/.config/mcpm -type f 2>/dev/null | head
b=$(digest $HOME/.config/mcpm 2>/dev/null); show mcpm edit srv --env=K=v --force; echo "  state: $b -> $(digest $HOME/.config/mcpm 2>/dev/null)"

echo "=== tic80 --cli: save a cart"
kind tic80
d=/s/tic; rm -rf $d; mkdir -p $d; cd $d
show tic80 --cli --fs=/s/tic --cmd=new&save
ls -la $d | tail -n +2
