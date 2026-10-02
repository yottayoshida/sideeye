#!/bin/sh
# mutool without Sideeye, at two versions — Debian's 1.25.1 (`mutool`) and 1.28.5 built from the
# project's source tarball: the write path as strace prints it, the file under `ulimit -f 0`,
# and a SIGKILL delivered on entry to the openat that re-creates the file after the unlink.
# Every command is echoed. Output through pipes; the file compared with a copy of the seed.
#
# Which openat: counted on a separate copy of the same seed (/count), so the run that is killed
# starts from the seed itself — the ordinal of the first openat whose flags carry O_CREAT on
# a.pdf. The killed run's own strace is kept and its last lines printed, so the transcript shows
# where it died. (The first version of this script took the LAST openat of a counting run made
# in the same directory, which consumed the seed and kept no trace; the first review found it.)
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
mk() { rm -rf "$1" && mkdir -p "$1" && python3 /ap/defines/mutool-1285/mkpdf.py "$1/a.pdf" > /dev/null; }
for M in mutool /opt/mupdf1285/mutool; do
    echo "######## $M: $($M -v 2>&1)"
    mk /demo; cp /demo/a.pdf /tmp/orig.pdf; cd /demo
    echo "## the write path"
    run "wc -c < a.pdf"
    run "strace -f -y -e trace=openat,write,unlink,unlinkat,rename,renameat,renameat2 $M clean a.pdf a.pdf 2>&1 | grep -F a.pdf | grep -v O_RDONLY | cut -c1-150"
    run "wc -c < a.pdf"
    mk /demo; cd /demo
    echo "## ulimit -f 0"
    out=$( ( ulimit -f 0; $M clean a.pdf a.pdf ) 2>&1 ); echo "\$ ( ulimit -f 0; $M clean a.pdf a.pdf ) -> exit $?: $(printf '%s\n' "$out" | grep . | tail -1 | cut -c1-120)"
    run "ls -l a.pdf | cut -c1-60"
    cmp -s a.pdf /tmp/orig.pdf && echo "a.pdf: the seed bytes" || echo "a.pdf: not the seed bytes"
    echo "## SIGKILL on entry to the openat that re-creates a.pdf"
    mk /count; n=$(cd /count && strace -e trace=openat $M clean a.pdf a.pdf 2>&1 | grep '^openat' | grep -n 'a\.pdf.*O_CREAT' | head -1 | cut -d: -f1)
    echo "the creating openat is openat number $n of this command (counted on a copy in /count)"
    mk /demo; cd /demo
    run "cmp -s a.pdf /tmp/orig.pdf && echo 'before: the seed, 537 bytes'"
    run "strace -o /tmp/kill.strace -e trace=openat,unlinkat -e inject=openat:signal=KILL:when=$n $M clean a.pdf a.pdf > /dev/null 2>&1; echo \"exit \$?\""
    run "tail -3 /tmp/kill.strace | cut -c1-120"
    run "ls -A /demo; [ -e a.pdf ] && wc -c < a.pdf || echo 'a.pdf is gone'"
done
exit 0
