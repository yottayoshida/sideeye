set -eu
rm -rf /s/ntfs /s/ntfs-in && mkdir -p /s/ntfs /s/ntfs-in
truncate -s 16M /s/ntfs/vol.img
mkntfs -F -Q -L OLDLABEL /s/ntfs/vol.img > /s/ntfs-in/mkntfs.log 2>&1
