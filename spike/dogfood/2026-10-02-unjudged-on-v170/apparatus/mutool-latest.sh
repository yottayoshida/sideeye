#!/bin/sh
# mutool 1.28.5 (built from the project's source tarball) without Sideeye: the write path as
# strace prints it, the file under `ulimit -f 0`, and a SIGKILL delivered on entry to the open
# that follows the unlink. Every command is echoed. Output through pipes, the file compared with
# a copy.
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
M=/opt/mupdf1285/mutool
run "$M -v"
mk() { rm -rf /demo && mkdir -p /demo && python3 /ap/defines/mutool-1285/mkpdf.py /demo/a.pdf > /dev/null && cp /demo/a.pdf /tmp/orig.pdf; cd /demo; }
mk; echo "## the write path"
run "wc -c < a.pdf"
run "strace -f -y -e trace=openat,write,unlink,unlinkat,rename,renameat,renameat2 $M clean a.pdf a.pdf 2>&1 | grep -F a.pdf | grep -v O_RDONLY | cut -c1-150"
run "wc -c < a.pdf"
mk; echo "## ulimit -f 0"
out=$( ( ulimit -f 0; $M clean a.pdf a.pdf ) 2>&1 ); echo "\$ ( ulimit -f 0; mutool clean a.pdf a.pdf ); exit $?: $(printf '%s\n' "$out" | grep . | tail -1 | cut -c1-120)"
run "ls -l a.pdf | cut -c1-60"
cmp -s a.pdf /tmp/orig.pdf && echo "a.pdf: the original bytes" || echo "a.pdf: not the original bytes"
mk; echo "## SIGKILL on entry to the first openat that would create a.pdf (after the unlink)"
run "strace -f -o /dev/null -e trace=openat -e inject=openat:signal=KILL:when=\$(strace -f -e trace=openat $M clean a.pdf a.pdf 2>&1 | grep -c openat) $M clean a.pdf a.pdf > /dev/null 2>&1; echo \"exit \$?\""
run "ls -A /demo; [ -e a.pdf ] && wc -c < a.pdf || echo 'a.pdf is gone'"
exit 0
