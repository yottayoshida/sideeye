set -eu
sh /ap/fat.sh umount /s/h2/kit
# A two-instrument drumkit in the legacy format (drumkit.xml and two WAVs written here); `h2cli -u`
# writes drumkit.xml.<time>.bak and rewrites drumkit.xml in the current format (lab 14:
# O_WRONLY|O_CREAT|O_TRUNC). The clock is pinned in env.sh, so the backup's name repeats.
rm -rf /s/h2 /s/h2-in /s/aux/home/.hydrogen && mkdir -p /s/h2/kit /s/h2-in
# The state on a fresh FAT filesystem (apparatus/fat.sh): no O_TMPFILE and no ACL there.
sh /ap/fat.sh mount /s/h2/kit
python3 /ap/defines/h2cli-fat/make_kit.py /s/h2/kit
grep -q 'Box Kit' /s/h2/kit/drumkit.xml
