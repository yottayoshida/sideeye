#!/bin/sh
# mu's database under home/ is scratch (the Xapian index differs between two clean runs); this judges
# the mail, which is the user's data: message 1001 is in exactly one of inbox and archive, whole, and
# the other two messages are where they were.
M="$SIDEEYE_STATE_DIR/Maildir"
n=$(ls "$M"/inbox/cur "$M"/archive/cur 2>/dev/null | grep -c '^1001')
[ "$n" = 1 ] || { echo "message 1001 is in $n places"; exit 1; }
f=$(ls -d "$M"/inbox/cur/1001* "$M"/archive/cur/1001* 2>/dev/null | head -1)
grep -q '^Subject: message 1001$' "$f" && grep -q '^body of 1001$' "$f" || { echo "message 1001 is not whole ($(wc -c < "$f") bytes)"; exit 1; }
for m in 1002 1003; do ls "$M"/inbox/cur | grep -q "^$m" || { echo "message $m left the inbox"; exit 1; }; done
exit 0
