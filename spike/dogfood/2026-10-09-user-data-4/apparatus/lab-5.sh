#!/bin/sh
# Lab 5: prefsCleaner with the script copied into the profile and owned by the user (lab 4: it
# refuses when the script's own file is root's), and MCA Selector's command-line mode read from
# its help. Inside the box:
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-5.sh
set -u
. /ap/env.sh
O=/out/lab-5; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close,execve'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines"
    grep -E 'O_TRUNC|O_CREAT|rename|unlink|link\(|truncate|fsync|execve\("' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/usr/lib|/lib|\.so|locale' | head -${MAXL:-30}
}
echo "## prefsCleaner, script in the profile"
rm -rf /s/ffprofile && mkdir -p /s/ffprofile && cd /s/ffprofile
cp /opt/arkenfox/user.js user.js; cp /opt/arkenfox/prefsCleaner.sh prefsCleaner.sh
printf '// Mozilla User Preferences\n\nuser_pref("app.update.auto", false);\nuser_pref("browser.startup.homepage", "https://example.org");\nuser_pref("privacy.resistFingerprinting", false);\nuser_pref("browser.download.dir", "/s/downloads");\nuser_pref("network.cookie.cookieBehavior", 0);\n' > prefs.js
chown -R 1000:1000 /s/ffprofile
tr_ prefsCleaner setpriv --reuid=1000 --regid=1000 --clear-groups bash ./prefsCleaner.sh -s -d
cat "$O/prefsCleaner.out" | head -12
ls -la /s/ffprofile | head; echo '--- prefs.js after'; cat /s/ffprofile/prefs.js

echo "## mcaselector"
ls -l /opt/mcaselector/bin; cat /opt/mcaselector/bin/mcaselector 2>/dev/null | head -5
/opt/mcaselector/bin/mcaselector --help > "$O/mca-help.txt" 2>&1; echo "help exit $?"; head -40 "$O/mca-help.txt"
