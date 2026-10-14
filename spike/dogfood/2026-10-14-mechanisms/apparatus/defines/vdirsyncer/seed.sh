set -eu
S=/s/vd
rm -rf $S /s/vd-aux && mkdir -p $S/a/cal $S/b/cal $S/status $S/home /s/vd-aux
printf '[general]\nstatus_path = "%s/status/"\n\n[pair p]\na = "a"\nb = "b"\ncollections = null\nconflict_resolution = "a wins"\n\n[storage a]\ntype = "filesystem"\npath = "%s/a/cal/"\nfileext = ".ics"\n\n[storage b]\ntype = "filesystem"\npath = "%s/b/cal/"\nfileext = ".ics"\n' $S $S $S > $S/config
ev() { printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//x//EN\r\nBEGIN:VEVENT\r\nUID:%s\r\nDTSTAMP:20260101T000000Z\r\nDTSTART:20260102T100000Z\r\nSUMMARY:%s\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$1" "$1"; }
ev one > $S/a/cal/one.ics
ev two > $S/b/cal/two.ics
export VDIRSYNCER_CONFIG=$S/config HOME=$S/home
yes | vdirsyncer discover > /s/vd-aux/discover.log 2>&1
vdirsyncer sync > /s/vd-aux/first-sync.log 2>&1
ev three > $S/a/cal/three.ics
ev four > $S/b/cal/four.ics
install -m 755 /ap/defines/vdirsyncer/check.sh /s/vd-aux/check.sh
