set -eu
# A password database with entries in it, opened by a key file kept outside --state (a USB stick,
# say). They are made with the pins off: every pinned process reads the same bytes, so three adds
# drew one entry UUID and each replaced the last (transcripts/explore/keepassxc-fat). Only the
# operation runs pinned.
rm -rf /s/kp /s/kpaux && mkdir -p /s/kp /s/kpaux
[ -f /etc/ld.so.preload ] && mv /etc/ld.so.preload /etc/ld.so.preload.seed
keepassxc-cli db-create -q --set-key-file /s/kpaux/key.keyx /s/kp/vault.kdbx < /dev/null
for e in bank email nas; do keepassxc-cli add -q --no-password -k /s/kpaux/key.keyx /s/kp/vault.kdbx "$e" -u "owner-$e" < /dev/null; done
keepassxc-cli ls -q --no-password -k /s/kpaux/key.keyx /s/kp/vault.kdbx < /dev/null | grep -q nas
[ -f /etc/ld.so.preload.seed ] && mv /etc/ld.so.preload.seed /etc/ld.so.preload
install -m 755 /ap/defines/keepassxc/check.sh /s/kp-check.sh
