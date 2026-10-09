#!/bin/sh
# Lab 4: prefsCleaner refuses to run as root (lab 3: "You shouldn't run this with elevated
# privileges"), and the box is root. Run it as an unprivileged user through setpriv, the way
# a define can spell it, and read the write path.
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-4.sh
set -u
. /ap/env.sh
O=/out/lab-4; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close,execve'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines"
    grep -E 'O_TRUNC|O_CREAT|rename|unlink|link\(|truncate|fsync|execve' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/lib|/lib|\.so|locale' | head -${MAXL:-24}
}
grep -n -i -E 'elevated|id -u|EUID|root' /opt/arkenfox/prefsCleaner.sh | head -5
rm -rf /s/ffprofile && mkdir -p /s/ffprofile && cd /s/ffprofile
cp /opt/arkenfox/user.js user.js
printf '// Mozilla User Preferences\n\nuser_pref("app.update.auto", false);\nuser_pref("browser.startup.homepage", "https://example.org");\nuser_pref("privacy.resistFingerprinting", false);\nuser_pref("browser.download.dir", "/s/downloads");\nuser_pref("network.cookie.cookieBehavior", 0);\n' > prefs.js
chown -R 1000:1000 /s/ffprofile
tr_ prefsCleaner setpriv --reuid=1000 --regid=1000 --clear-groups bash /opt/arkenfox/prefsCleaner.sh -s -d
cat "$O/prefsCleaner.out" | head -12
ls -la /s/ffprofile | head; echo '--- prefs.js after'; cat /s/ffprofile/prefs.js
