#!/bin/sh
# The 2026-09-16 userview-3 codespell checker, the same tests with the messages in English:
# no file is gone or empty, each keeps its MARKER line and its line count. Whether the
# spelling was fixed is not asked.
for n in a b c; do
  f="$SD/$n.txt"
  [ -f "$f" ] || { echo "$n.txt is gone"; exit 1; }
  [ -s "$f" ] || { echo "$n.txt is empty"; exit 1; }
  m=$(echo "$n" | tr 'a-z' 'A-Z')
  grep -q "MARKER-$m" "$f" || { echo "$n.txt lost MARKER-$m ($(wc -c < "$f") bytes)"; exit 1; }
done
[ "$(wc -l < "$SD/a.txt")" -eq 3 ] || { echo "a.txt is not 3 lines: $(wc -l < "$SD/a.txt")"; exit 1; }
[ "$(wc -l < "$SD/b.txt")" -eq 2 ] || { echo "b.txt is not 2 lines: $(wc -l < "$SD/b.txt")"; exit 1; }
[ "$(wc -l < "$SD/c.txt")" -eq 2 ] || { echo "c.txt is not 2 lines: $(wc -l < "$SD/c.txt")"; exit 1; }
exit 0
