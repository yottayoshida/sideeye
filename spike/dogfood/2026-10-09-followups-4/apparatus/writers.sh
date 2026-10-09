#!/bin/sh
# Round 2, off the page's path: which threads write the state, measured with strace -f outside Sideeye.
# The seed runs as run.sh runs it; the operation runs once under strace with each descriptor's path
# shown (-y), and writers.py lists every thread or process that changed something under the state.
#   docker run --rm --privileged --network none -v <apparatus>:/ap:ro -v <transcripts/writers>:/out \
#       sideeye-fu4-1009 sh /ap/writers.sh <target>
set -u
t=${1:?usage: writers.sh <target> [output name]}
d=/ap/defines/$t
. /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/${2:-$t}; mkdir -p "$o"   # a second argument names the output, for repeated runs
sh "$d/seed.sh" > "$o/seed.log" 2>&1 || { echo "seed failed"; exit 2; }
get() { python3 -c 'import sys,tomllib; c=tomllib.load(open(sys.argv[1],"rb")); print(c[sys.argv[2]].get(sys.argv[3],""))' "$d/sideeye.toml" "$1" "$2"; }
state=$(get world state); op=$(get define operation); cwd=$(get define cwd)
cd "${cwd:-/}"
calls=open,openat,creat,write,pwrite64,writev,pwritev,rename,renameat,renameat2,unlink,unlinkat,truncate,ftruncate,fsync,fdatasync,mkdir,mkdirat,rmdir,link,linkat,symlinkat,fchmod,fchmodat,mmap,clone,clone3,fork,vfork,execve
strace -f -qq -y -o "$o/writers.strace" -e trace=$calls sh -c "$op" > "$o/op.log" 2>&1
echo "operation exit $?  ($op)"
python3 /ap/writers.py "$o/writers.strace" "$state" | tee "$o/writers.txt"
