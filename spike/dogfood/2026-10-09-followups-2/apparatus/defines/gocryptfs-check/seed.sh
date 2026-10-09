set -eu
rm -rf /s/gocryptfs /s/gocryptfs-in && mkdir -p /s/gocryptfs/cipher /s/gocryptfs-in
printf 'old-passphrase\n' > /s/gocryptfs-in/old
printf 'new-passphrase\n' > /s/gocryptfs-in/new
printf 'exec gocryptfs -passwd -passfile /s/gocryptfs-in/old /s/gocryptfs/cipher < /s/gocryptfs-in/new\n' > /s/gocryptfs-in/chpw.sh
gocryptfs -init -q -passfile /s/gocryptfs-in/old /s/gocryptfs/cipher > /dev/null
# The master key, kept outside the state for the checker.
/opt/bin/gocryptfs-xray -dumpmasterkey /s/gocryptfs/cipher/gocryptfs.conf < /s/gocryptfs-in/old 2>/dev/null | tail -1 > /s/gocryptfs-in/masterkey
test -s /s/gocryptfs-in/masterkey
