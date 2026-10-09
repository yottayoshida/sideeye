#!/bin/sh
# f2's promise is one batch: after `f2 -f IMG_ -r trip_ -x` every photo is renamed, and before it
# none is. A crashed state holding both prefixes is a half-renamed batch — the state the undo
# record (written last, outside --state) cannot take back. Exit 0 when the directory is wholly
# before or wholly after; exit 1 when mixed, or when a photo is missing.
set -u
d=${SIDEEYE_STATE_DIR:?}
old=$(ls "$d" | grep -c '^IMG_[0-9]*\.jpg$')
new=$(ls "$d" | grep -c '^trip_[0-9]*\.jpg$')
total=$(ls "$d" | wc -l | tr -d ' ')
if [ "$total" -ne 3 ]; then echo "checker(f2): $total entries, expected 3"; exit 1; fi
# The bytes too: a rename moves a file whole, so photo N's bytes must still open with its seed
# line under either name (the falsification gate overwrites every file with junk and expects red).
for i in 1 2 3; do
    f=$(ls "$d" | grep -E "^(IMG|trip)_$i\.jpg$" | head -1)
    [ -n "$f" ] || { echo "checker(f2): photo $i missing under both names"; exit 1; }
    head -c 8 "$d/$f" | grep -q "^photo $i" || { echo "checker(f2): $f does not hold photo $i"; exit 1; }
done
if [ "$old" -eq 3 ] || [ "$new" -eq 3 ]; then exit 0; fi
echo "checker(f2): half-renamed: $old IMG_, $new trip_"; exit 1
