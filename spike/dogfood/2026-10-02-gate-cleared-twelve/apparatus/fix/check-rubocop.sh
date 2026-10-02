#!/bin/sh
# The 2026-09-16 userview-3 rubocop checker, the same tests with the messages in English: each
# file is there, not empty, parses as Ruby, and keeps its MARKER line and its method.
for n in a b; do
  f="$SD/$n.rb"
  [ -f "$f" ] || { echo "$n.rb is gone"; exit 1; }
  [ -s "$f" ] || { echo "$n.rb is empty"; exit 1; }
  ruby -c "$f" >/dev/null 2>&1 || { echo "$n.rb does not parse as Ruby ($(wc -c < "$f") bytes)"; exit 1; }
  m=$(echo "$n" | tr 'a-z' 'A-Z')
  grep -q "MARKER-$m" "$f" || { echo "$n.rb lost MARKER-$m"; exit 1; }
done
grep -q "def greet" "$SD/a.rb" || { echo "a.rb lost def greet"; exit 1; }
grep -q "def add"   "$SD/b.rb" || { echo "b.rb lost def add"; exit 1; }
exit 0
