#!/bin/sh
# PHP must still parse a.php, and the function must still be in it.
f=/s/phpcbf/proj/a.php
php -l "$f" > /dev/null 2>&1 || { echo "php cannot parse a.php" >&2; exit 1; }
grep -q 'function f' "$f" || { echo "the function is gone" >&2; exit 1; }
