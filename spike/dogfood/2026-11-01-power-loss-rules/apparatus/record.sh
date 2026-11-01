#!/bin/sh
# In the box: one define's operation, once, under strace, after its seed and setup.
#   record.sh <define dir as mounted> <name>
set -u
d=$1; t=$2; o=/out/$t; mkdir -p "$o"
[ -f /ap/env.sh ] && . /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
python3 /rec-define.py "$d/sideeye.toml" > "$o/define.sh" || { echo "$t: define unreadable"; exit 2; }
. "$o/define.sh"
sh "$d/seed.sh" > "$o/seed.log" 2>&1 || { echo "$t: seed failed"; exit 2; }
if [ -n "$setup" ]; then
    (cd "$cwd" && eval "$setup") > "$o/setup.log" 2>&1 || { echo "$t: setup failed"; exit 2; }
fi
# Not left to the trace: it cannot say whether a create met a name that was already there.
(cd "$state" 2>/dev/null && find . -mindepth 1) > "$o/pre.txt"
calls=write,pwrite64,writev,pwritev,pwritev2,sendfile,copy_file_range,fallocate,ftruncate,truncate,openat,openat2,creat,renameat,renameat2,linkat,symlinkat,unlinkat,mkdirat,fsync,fdatasync,sync_file_range,syncfs,sync,msync,chdir,fchdir
(cd "$cwd" && eval "strace -f -y -qq -e trace=$calls -o $o/trace.strace $op") < /dev/null > "$o/op.log" 2>&1
echo "exit=$?" > "$o/op.exit"
{ echo "state=$state"; echo "marker=$marker"; echo "cwd=$cwd"; echo "op=$op"; strace -V | head -1; uname -m; } > "$o/meta.txt"
echo "$t recorded: $(wc -l < "$o/trace.strace") lines, $(cat "$o/op.exit")"
