set -eu
sh /ap/fat.sh umount /s/aux/home/.config/Kvantum
# A Kvantum config naming one theme; `--set` rewrites it through Qt's QSettings (lab 10: a lock
# file, a temporary name, rename).
rm -rf /s/aux/home/.config/Kvantum /s/kv && mkdir -p /s/kv /s/aux/home/.config/Kvantum
# The state on a fresh FAT filesystem (apparatus/fat.sh): no O_TMPFILE and no ACL there.
sh /ap/fat.sh mount /s/aux/home/.config/Kvantum
printf '[General]\ntheme=KvArc\n\n[Applications]\nKvFlat=okular, konsole\n' > /s/aux/home/.config/Kvantum/kvantum.kvconfig
grep -q KvArc /s/aux/home/.config/Kvantum/kvantum.kvconfig
