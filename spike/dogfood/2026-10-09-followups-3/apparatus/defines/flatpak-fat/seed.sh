set -eu
sh /ap/fat.sh umount /s/flatpak
rm -rf /s/flatpak && mkdir -p /s/flatpak/data/flatpak/overrides
# The state on a fresh FAT filesystem (apparatus/fat.sh): no O_TMPFILE and no ACL there.
sh /ap/fat.sh mount /s/flatpak
mkdir -p /s/flatpak/data/flatpak/overrides
printf '[Context]\nfilesystems=~/Documents/notes;\n\n[Environment]\nNOTES_SYNC=1\n' > /s/flatpak/data/flatpak/overrides/org.example.Notes
