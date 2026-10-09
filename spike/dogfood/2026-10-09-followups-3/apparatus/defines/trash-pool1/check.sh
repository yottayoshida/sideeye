#!/bin/sh
# trash's promise: the document is either still in docs/ (nothing happened) or in the trash with
# a .trashinfo that names where it came from (so `trash` tooling can restore it). A document in
# neither place, or in the trash with no .trashinfo, or a .trashinfo whose file is gone, is red;
# so are bytes that are not the document's.
set -u
d=${SIDEEYE_STATE_DIR:?}
ok_bytes() { head -c 8 "$1" | grep -q '^a report'; }
if [ -f "$d/docs/report.txt" ]; then
    ok_bytes "$d/docs/report.txt" || { echo "checker(trash): docs/report.txt holds other bytes"; exit 1; }
    exit 0
fi
files=$(ls "$d/xdg/Trash/files" 2>/dev/null | wc -l | tr -d ' ')
infos=$(ls "$d/xdg/Trash/info" 2>/dev/null | wc -l | tr -d ' ')
[ "$files" = 1 ] || { echo "checker(trash): report.txt is in docs/ nor the trash ($files files)"; exit 1; }
f=$(ls "$d/xdg/Trash/files")
ok_bytes "$d/xdg/Trash/files/$f" || { echo "checker(trash): the trashed file holds other bytes"; exit 1; }
[ "$infos" = 1 ] || { echo "checker(trash): trashed file with $infos .trashinfo"; exit 1; }
grep -q '^Path=.*docs/report.txt' "$d"/xdg/Trash/info/*.trashinfo || { echo "checker(trash): .trashinfo does not name docs/report.txt"; exit 1; }
exit 0
