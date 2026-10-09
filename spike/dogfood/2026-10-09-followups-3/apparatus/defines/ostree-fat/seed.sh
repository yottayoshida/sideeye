set -eu
sh /ap/fat.sh umount /s/ost/repo
rm -rf /s/ost /s/ost-in && mkdir -p /s/ost /s/ost-in
# The state on a fresh FAT filesystem (apparatus/fat.sh): no O_TMPFILE and no ACL there.
sh /ap/fat.sh mount /s/ost/repo
ostree --repo=/s/ost/repo init --mode=archive > /s/ost-in/seed.log 2>&1
ostree --repo=/s/ost/repo config set core.min-free-space-percent 5 >> /s/ost-in/seed.log 2>&1
ostree --repo=/s/ost/repo remote add --no-gpg-verify mirror https://mirror.example.invalid/repo >> /s/ost-in/seed.log 2>&1
grep -q mirror /s/ost/repo/config
