set -eu
sh /ap/fat.sh umount /s/vim/state
rm -rf /s/vim && mkdir -p /s/vim/state
# The state on a fresh FAT filesystem (apparatus/fat.sh): no O_TMPFILE and no ACL there.
sh /ap/fat.sh mount /s/vim/state
mkdir -p "/s/vim/state"
cat > "/s/vim/state/a.txt" <<'EOT'
MARKER line one old
line two old
line three stays
EOT
