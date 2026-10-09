#!/bin/sh
# Lab 3: iconvert under the shim by hand (the gate's recording run dies of SIGABRT with
# --threads 1 too), and the second layer's cook and prefsCleaner run by hand to find their
# operations. Inside the box:
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-3.sh
set -u
. /ap/env.sh
O=/out/lab-3; mkdir -p "$O"
SE=$(cat /install.path); SHIM=$(dirname "$SE")/libsideeye_shim.so
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines"
    grep -E 'O_TRUNC|O_CREAT|rename|unlink|link\(|truncate|fsync' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale' | head -${MAXL:-20}
}

echo "## iconvert under the shim, by hand"
sh /ap/defines/iconvert/seed.sh; cd /s/oiio
LD_PRELOAD=$SHIM iconvert --threads 1 --inplace --caption hello photo.jpg > "$O/iconvert-preload.out" 2>&1; echo "preload only, --threads 1: exit $?: $(head -c 200 "$O/iconvert-preload.out")"
sh /ap/defines/iconvert/seed.sh; cd /s/oiio
LD_PRELOAD=$SHIM iconvert --inplace --caption hello photo.jpg > "$O/iconvert-preload-nt.out" 2>&1; echo "preload only, default threads: exit $?: $(head -c 200 "$O/iconvert-preload-nt.out")"
sh /ap/defines/iconvert/seed.sh; cd /s/oiio
LD_PRELOAD=$SHIM oiiotool --threads 1 photo.jpg --caption hello -o photo2.jpg > "$O/oiiotool-preload.out" 2>&1; echo "oiiotool under preload: exit $?: $(head -c 200 "$O/oiiotool-preload.out")"
sh /ap/defines/iconvert/seed.sh
"$SE" preflight --config /ap/defines/iconvert/sideeye.toml --twice --oracle /usr/bin/strace --observe syscalls > "$O/iconvert-preflight-syscalls.txt" 2>&1; echo "preflight --observe syscalls: exit $?"; grep -E '^(UNKNOWN|SETUP|next|recording accepted|PASS|FAIL)' "$O/iconvert-preflight-syscalls.txt" | cut -c1-200 | head -5

echo "## cook"
cook --help 2>&1 | head -30 > "$O/cook-help.txt"; cook pantry --help > "$O/cook-pantry-help.txt" 2>&1; cat "$O/cook-pantry-help.txt" | head -30
rm -rf /s/cook && mkdir -p /s/cook/config && cd /s/cook
printf '[dairy]\nmilk = "1%%l"\nbutter = "200%%g"\n\n[pantry]\nflour = "1%%kg"\n' > /s/cook/config/pantry.conf
printf -- '---\nservings: 2\n---\nMix @flour{200%%g} with @milk{300%%ml} and @butter{50%%g}.\n' > /s/cook/Pancakes.cook
tr_ cook-pantry-add cook pantry add dairy eggs --quantity 6
ls -la /s/cook /s/cook/config; cat /s/cook/config/pantry.conf
tr_ cook-pantry-remove cook pantry remove dairy eggs
cat /s/cook/config/pantry.conf

echo "## prefsCleaner"
rm -rf /s/ffprofile && mkdir -p /s/ffprofile && cd /s/ffprofile
cp /opt/arkenfox/user.js user.js
printf '// Mozilla User Preferences\n\nuser_pref("app.update.auto", false);\nuser_pref("browser.startup.homepage", "https://example.org");\nuser_pref("privacy.resistFingerprinting", false);\nuser_pref("browser.download.dir", "/s/downloads");\nuser_pref("network.cookie.cookieBehavior", 0);\n' > prefs.js
tr_ prefsCleaner bash /opt/arkenfox/prefsCleaner.sh -s -d
ls -la /s/ffprofile | head; cat /s/ffprofile/prefs.js | head -8
