#!/bin/sh
set -u
R=/localrun; mkdir -p "$R/ev/rb2"
cat > "$R/ev/rb2/a.rb" <<'EOT'
# MARKER-A
def greet( name )
  puts( "hello #{name}" )
end
greet( "world" )
EOT
echo "=== rubocop: a.rb に対する書き込み経路だけ ==="
strace -f -e trace=openat,write,ftruncate,rename,unlink -o /tmp/rb.tr \
  rubocop -a --force-default-config --only Layout/SpaceInsideParens "$R/ev/rb2/a.rb" >/dev/null 2>&1
grep "ev/rb2/a.rb" /tmp/rb.tr | head -10
echo "--- 実行後 ---"; wc -c "$R/ev/rb2/a.rb"; cat "$R/ev/rb2/a.rb"
