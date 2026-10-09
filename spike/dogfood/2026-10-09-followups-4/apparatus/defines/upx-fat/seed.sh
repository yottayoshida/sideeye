set -eu
sh /ap/fat.sh umount /s/upx
rm -rf /s/upx && mkdir -p /s/upx
# The state on a fresh FAT filesystem mounted with fmask=0022,dmask=0022: every file 0755: upx wants its input executable, which the restore's 0644 is not (#678).
sh /ap/fat.sh mount /s/upx fmask=0022,dmask=0022
cp /usr/bin/bash /s/upx/prog
