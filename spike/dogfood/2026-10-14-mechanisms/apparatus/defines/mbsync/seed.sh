set -eu
S=/s/mb
rm -rf $S /s/mb-aux && mkdir -p $S/far/cur $S/far/new $S/far/tmp $S/near/cur $S/near/new $S/near/tmp $S/st /s/mb-aux
printf 'MaildirStore far\nInbox %s/far\n\nMaildirStore near\nInbox %s/near\n\nChannel ch\nFar :far:\nNear :near:\nSync All\nCreate Both\nExpunge None\nSyncState %s/st/\n' $S $S $S > $S/rc
m() { printf 'From: a@example.invalid\nTo: b@example.invalid\nMessage-ID: <%s@example.invalid>\nSubject: %s\n\nbody %s\n' "$1" "$1" "$1"; }
m one > $S/far/cur/1000.1.host:2,
m two > $S/far/cur/1001.1.host:2,
mbsync -c $S/rc ch > /s/mb-aux/first-sync.log 2>&1
m three > $S/far/new/1002.1.host
m four > $S/near/new/1003.1.host
one=$(grep -l 'Message-ID: <one@' $S/far/cur/*)
mv "$one" "${one%:2,}:2,S"
install -m 755 /ap/defines/mbsync/check.sh /s/mb-aux/check.sh
