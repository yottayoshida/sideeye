#!/bin/sh
# 報告に載せる実測を採る: バージョン、strace の書き込み経路、kill 後のバイト数。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; mkdir -p "$R/ev/cs" "$R/ev/rb" "$R/wk"
echo "=== versions ==="
codespell --version; rubocop --version 2>/dev/null | head -1; ruby --version | cut -d' ' -f1-2
python3 --version; . /etc/os-release; echo "$PRETTY_NAME"; uname -m
dpkg-query -W -f='${Package} ${Version}\n' codespell rubocop 2>/dev/null

mk_cs() {
  mkdir -p "$R/ev/cs"
  cat > "$R/ev/cs/a.txt" <<'EOT'
MARKER-A keep this line
The reciever did not seperate the files.
Second line stays as it is.
EOT
  cat > "$R/ev/cs/b.txt" <<'EOT'
MARKER-B keep this line too
teh quick brown fox, occured twice.
EOT
}
mk_rb() {
  mkdir -p "$R/ev/rb"
  cat > "$R/ev/rb/a.rb" <<'EOT'
# MARKER-A
def greet( name )
  puts( "hello #{name}" )
end
greet( "world" )
EOT
}

echo
echo "=== codespell: strace の書き込み経路 ==="
mk_cs
strace -f -e trace=openat,write,unlink,rename,ftruncate -o /tmp/cs.tr \
  codespell -w "$R/ev/cs/a.txt" "$R/ev/cs/b.txt" >/dev/null 2>&1
grep -E "a\.txt|b\.txt" /tmp/cs.tr | grep -vE "ENOENT|O_RDONLY.*= 3$" | head -8
echo "--- 実行後 ---"; wc -c "$R/ev/cs/a.txt" "$R/ev/cs/b.txt"

echo
echo "=== codespell: crash point 2 で止めたときの状態 ==="
mk_cs
ls -l "$R/ev/cs" | tail -2
SIDEEYE_STATE_DIR="$R/ev/cs" SIDEEYE_TRACE_PATH="$R/wk/t1.bin" LD_PRELOAD="$SHIM" SIDEEYE_KILL_AT=2 \
  codespell -w "$R/ev/cs/a.txt" "$R/ev/cs/b.txt" >/dev/null 2>&1
echo "kill 後の exit=$?"; ls -l "$R/ev/cs" | tail -2
echo "a.txt の中身: [$(cat "$R/ev/cs/a.txt")]"

echo
echo "=== rubocop: strace の書き込み経路 ==="
mk_rb
strace -f -e trace=openat,write,unlink,rename,ftruncate -o /tmp/rb.tr \
  rubocop -a --force-default-config --only Layout/SpaceInsideParens "$R/ev/rb/a.rb" >/dev/null 2>&1
grep -E "a\.rb" /tmp/rb.tr | grep -vE "ENOENT" | head -8
echo "--- 実行後 ---"; wc -c "$R/ev/rb/a.rb"

echo
echo "=== rubocop: crash point 2 で止めたときの状態 ==="
mk_rb
ls -l "$R/ev/rb" | tail -1
SIDEEYE_STATE_DIR="$R/ev/rb" SIDEEYE_TRACE_PATH="$R/wk/t2.bin" LD_PRELOAD="$SHIM" SIDEEYE_KILL_AT=2 \
  rubocop -a --force-default-config --only Layout/SpaceInsideParens "$R/ev/rb/a.rb" >/dev/null 2>&1
echo "kill 後の exit=$?"; ls -l "$R/ev/rb" | tail -1
echo "a.rb の中身: [$(cat "$R/ev/rb/a.rb")]"
