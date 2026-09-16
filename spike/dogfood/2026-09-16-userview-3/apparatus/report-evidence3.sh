#!/bin/sh
# oxipng 報告と同じ「crash なしで見せられる再現」が効くかを測る。
set -u
R=/localrun/ev3; mkdir -p "$R"
mk() {
  printf 'MARKER-A keep this line\nThe reciever did not seperate the files.\nSecond line stays as it is.\n' > "$R/a.txt"
  printf '# MARKER-A\ndef greet( name )\n  puts( "hello #{name}" )\nend\ngreet( "world" )\n' > "$R/a.rb"
}
echo "=== codespell: ulimit -f 0 ==="
mk; echo "前: $(wc -c < "$R/a.txt") bytes"
( ulimit -f 0; codespell -w "$R/a.txt" ) 2>&1 | head -3
echo "後: $(wc -c < "$R/a.txt") bytes"
echo
echo "=== rubocop: ulimit -f 0 ==="
mk; echo "前: $(wc -c < "$R/a.rb") bytes"
( ulimit -f 0; rubocop -a --force-default-config --only Layout/SpaceInsideParens "$R/a.rb" ) 2>&1 | tail -3
echo "後: $(wc -c < "$R/a.rb") bytes"
echo
echo "=== codespell: 読み取り専用ディレクトリではなく、書き込み中の SIGKILL（sideeye 無し・手で）==="
mk; echo "前: $(wc -c < "$R/a.txt") bytes"
