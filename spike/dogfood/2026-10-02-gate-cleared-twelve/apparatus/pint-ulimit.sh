#!/bin/sh
# Under `ulimit -f 0` pint dies before it touches a.php. Which write: strace, started outside
# the limit so its own log is not subject to it, follows a shell that sets the limit and execs
# pint. The last writes before SIGXFSZ, with the file each descriptor names.
sh /ap/defines/pint/seed.sh; cd /s/pint/proj
echo "before: $(wc -c < a.php) bytes"
strace -f -y -o /tmp/pint.strace -e trace=openat,write,pwrite64,ftruncate sh -c 'ulimit -f 0; exec php /opt/bin/pint.phar a.php' > /dev/null 2>&1
echo "exit $?"
echo "after:  $(wc -c < a.php) bytes"
echo "## the signal, and the three lines before it"
grep -n -B3 'SIGXFSZ' /tmp/pint.strace | cut -c1-220 | head -12
echo "## every openat of a.php for writing in the whole run: $(grep -c 'a\.php.*O_WRONLY\|a\.php.*O_RDWR' /tmp/pint.strace)"
