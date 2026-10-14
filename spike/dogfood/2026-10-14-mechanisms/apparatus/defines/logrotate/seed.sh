set -eu
S=/s/lr
rm -rf $S /s/lr-aux && mkdir -p $S /s/lr-aux
printf '%s/app.log {\n    rotate 3\n    create 0640 root root\n    nocompress\n    missingok\n}\n' $S > /s/lr-aux/app.conf
chmod 644 /s/lr-aux/app.conf
for i in 1 2 3; do echo "line A$i"; done > $S/app.log.2
for i in 1 2 3; do echo "line B$i"; done > $S/app.log.1
for i in 1 2 3 4; do echo "line C$i"; done > $S/app.log
logrotate -s $S/status /s/lr-aux/app.conf > /s/lr-aux/first-run.log 2>&1
install -m 755 /ap/defines/logrotate/check.sh /s/lr-aux/check.sh
