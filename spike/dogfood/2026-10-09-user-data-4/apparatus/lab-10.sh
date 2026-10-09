#!/bin/sh
# Lab 10: the fifth layer's six tools by hand under strace — stack and cabal user config, carapace
# styles, chdman metadata on an existing CHD, Kvantum's theme setting, hunspell's personal dictionary.
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-10.sh
set -u
. /ap/env.sh
O=/out/lab-10; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T,clone,clone3,execve -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines; $(grep -c -E 'clone3?\(' "$O/$n.strace") clone; $(grep -c 'execve(' "$O/$n.strace") execve"
    grep -E 'O_TRUNC|O_CREAT|O_APPEND|rename|unlink|link\(|truncate|fsync' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale' | head -${MAXL:-14}
    tail -3 "$O/$n.out" | cut -c1-200
}

echo "## stack"
rm -rf /s/aux/home/.stack /s/stk && mkdir -p /s/stk && cd /s/stk
tr_ stack-first stack config set install-ghc false --global
ls -la /s/aux/home/.stack 2>&1 | head; find /s/aux/home/.stack -maxdepth 2 | head -20
tr_ stack-second stack config set system-ghc true --global
grep -v '^#' /s/aux/home/.stack/config.yaml | grep -v '^$' | head

echo "## cabal"
rm -rf /s/aux/home/.cabal /s/aux/home/.config/cabal && cd /s/stk
tr_ cabal-init cabal user-config init
find /s/aux/home/.config/cabal /s/aux/home/.cabal -maxdepth 1 2>/dev/null | head
tr_ cabal-update cabal user-config update -a 'jobs: 4'
grep -n -E '^ *jobs' /s/aux/home/.config/cabal/config /s/aux/home/.cabal/config 2>/dev/null | head -3

echo "## carapace"
rm -rf /s/aux/home/.config/carapace && cd /s/stk
tr_ carapace-first carapace --style 'carapace.Value=bold,magenta'
find /s/aux/home/.config/carapace -type f | head; cat /s/aux/home/.config/carapace/styles.json 2>/dev/null | head -5
tr_ carapace-second carapace --style 'carapace.Description=dim'
cat /s/aux/home/.config/carapace/styles.json 2>/dev/null | head -8

echo "## chdman"
rm -rf /s/chd && mkdir -p /s/chd && cd /s/chd
head -c 1048576 /dev/zero | tr '\0' 'A' > raw.bin
chdman 2>&1 | grep -E 'addmeta|delmeta|createraw' | head -5
chdman createraw -i raw.bin -o d.chd -hs 512 -us 4096 > "$O/chd-seed.out" 2>&1; echo "createraw exit $?"; ls -l
chdman addmeta 2>&1 | head -20 > "$O/chd-addmeta-help.txt"; cat "$O/chd-addmeta-help.txt"
tr_ chdman-addmeta chdman addmeta -i d.chd -t NOTE -vt hello
ls -l; chdman info -i d.chd 2>&1 | tail -6

echo "## kvantum"
ls /usr/share/Kvantum 2>&1 | head; ls /usr/bin | grep -i kvantum
rm -rf /s/aux/home/.config/Kvantum && cd /s/stk
export QT_QPA_PLATFORM=offscreen
kvantummanager --help > "$O/kvantum-help.txt" 2>&1; head -12 "$O/kvantum-help.txt"
tr_ kvantum-first kvantummanager --set KvArc
find /s/aux/home/.config/Kvantum -type f | head; cat /s/aux/home/.config/Kvantum/kvantum.kvconfig 2>/dev/null
tr_ kvantum-second kvantummanager --set KvFlat
cat /s/aux/home/.config/Kvantum/kvantum.kvconfig 2>/dev/null

echo "## hunspell"
rm -rf /s/hun && mkdir -p /s/hun && cd /s/hun
printf 'zzyzx\nqwerty\n' > my.dic
printf '*flibbertigibbet\n*snorkack\n#\n' > words.txt
tr_ hunspell sh -c 'hunspell -a -d en_US -p /s/hun/my.dic < /s/hun/words.txt'
cat /s/hun/my.dic
