#!/bin/sh
# #8939 で報告した不変条件。コマンドラインに書いた名前にファイルがあり、読める。
f=/work/im/img1.png
[ -f "$f" ] || { echo "img1.png が無い"; exit 1; }
/usr/bin/identify "$f" > /dev/null 2>&1 || { echo "img1.png を identify が読めない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
