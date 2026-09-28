#!/bin/sh
# Ruby must still parse a.rb, and the method and its call must still be in it.
f=/s/standardrb/proj/a.rb
ruby -c "$f" > /dev/null 2>&1 || { echo "ruby cannot parse a.rb" >&2; exit 1; }
grep -q 'def f' "$f" || { echo "the method is gone" >&2; exit 1; }
grep -q 'puts f' "$f" || { echo "the call is gone" >&2; exit 1; }
