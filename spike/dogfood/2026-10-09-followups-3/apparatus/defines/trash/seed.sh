set -eu
# A document in a folder and the XDG trash beside it under one state root, so the move from
# docs/ to xdg/Trash/files and the .trashinfo written beside it are judged together (lab 8:
# the trashinfo opened O_TRUNC, then the file renamed). env.sh points XDG_DATA_HOME here.
rm -rf /s/td && mkdir -p /s/td/docs /s/td/xdg
printf 'a report, 40 bytes of text that matter...\n' > /s/td/docs/report.txt
install -m 755 /ap/defines/trash/check.sh /s/td-check.sh
[ -s /s/td/docs/report.txt ]
