#!/bin/sh
# The strace readings RESULTS.md cites, as runs with their output kept (the first review found
# them cited and not committed): what PHP CS Fixer writes bare, with its rules named, and
# inside pint; and which write kills fontforge under `ulimit -f 0`. Every command is echoed.
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
. /ap/env.sh
W='strace -f -y -e trace=openat,write,rename,renameat,renameat2,ftruncate'
F='grep -E "O_WRONLY|O_RDWR|a\.php" | grep -v -E "O_RDONLY|/tmp/|/dev/|pipe:" | cut -c1-150'
echo "######## PHP CS Fixer 3.95.27, bare: what it opens for writing under the project"
sh /ap/defines/php-cs-fixer/seed.sh; cd /s/php-cs-fixer/proj; cp a.php /tmp/a.orig
run "$W php /opt/bin/php-cs-fixer.phar fix a.php 2>&1 | $F"
run "ls -A; cmp -s a.php /tmp/a.orig && echo 'a.php: the seed bytes' || echo 'a.php: not the seed bytes'"
echo "######## PHP CS Fixer 3.95.27, --rules=@PSR12 --no-interaction"
sh /ap/defines/php-cs-fixer-r1/seed.sh; cd /s/php-cs-fixer-r1/proj
run "$W php /opt/bin/php-cs-fixer.phar fix --rules=@PSR12 --no-interaction a.php 2>&1 | $F"
echo "######## pint 1.32.1 (bundles v3.95.25)"
sh /ap/defines/php-cs-fixer-r1/seed.sh; cd /s/php-cs-fixer-r1/proj
run "$W php /opt/bin/pint.phar a.php 2>&1 | $F"
echo "######## fontforge under ulimit -f 0: the write that dies (strace started outside the limit)"
sh /ap/defines/fontforge/seed.sh > /dev/null 2>&1; cp /s/fontforge/ff/f.ttf /tmp/f.orig
strace -f -y -o /tmp/ff.strace -e trace=openat,write sh -c 'ulimit -f 0; exec /bin/sh /ap/defines/fontforge/op.sh' > /dev/null 2>&1; echo "exit $?"
run "grep -B2 SIGXFSZ /tmp/ff.strace | cut -c1-170"
run "grep -c 'f\.ttf.*O_\(WRONLY\|RDWR\)' /tmp/ff.strace"
cmp -s /s/fontforge/ff/f.ttf /tmp/f.orig && echo "f.ttf: the seed bytes" || echo "f.ttf: not the seed bytes"
exit 0
