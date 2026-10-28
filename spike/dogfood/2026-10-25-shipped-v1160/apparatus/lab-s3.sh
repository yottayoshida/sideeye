#!/bin/sh
# Set 3: each define plain, no Sideeye — seed, the operation as the toml spells it, the checker — so a
# gate's answer is read against a target that is known to run.
#   docker run --rm --privileged --network none -v <apparatus>:/ap:ro sideeye-sv1025-s3 sh /ap/lab-s3.sh [name ...]
set -u
[ $# -gt 0 ] || set -- salt-grains sysusers vagrant freshrss juicefs
for t in "$@"; do
  ( . /ap/env.sh; [ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh
    d=/ap/defines/$t
    echo "===== $t"
    sh $d/seed.sh; echo "seed exit $?"
    op=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["define"]["operation"])' $d/sideeye.toml)
    st=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["world"]["state"])' $d/sideeye.toml)
    cw=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["define"].get("cwd",""))' $d/sideeye.toml); cw=${cw:-$st}
    find "$st" -type f | sort | xargs sha256sum 2>/dev/null | cut -c1-16,65- > /tmp/before.txt
    ( cd "$cw" && sh -c "$op" ) > /tmp/op.txt 2>&1; echo "operation exit $?"; tail -5 /tmp/op.txt
    find "$st" -type f | sort | xargs sha256sum 2>/dev/null | cut -c1-16,65- > /tmp/after.txt
    echo "-- changed files:"; diff /tmp/before.txt /tmp/after.txt | grep '^[<>]' | head -20
    SIDEEYE_STATE_DIR=$st sh $d/check.sh; echo "check exit $?"
    echo "-- writing threads/children (strace -f, the operation's calls on the state):"
    sh $d/seed.sh > /dev/null 2>&1
    ( cd "$cw" && strace -f -qq -e trace=openat,rename,renameat,renameat2,unlink,unlinkat,write,pwrite64,fsync,fdatasync,ftruncate,fallocate,mmap,clone,clone3,execve,setxattr,fsetxattr -o /tmp/st.txt sh -c "$op" ) > /dev/null 2>&1
    echo "pids: $(cut -d' ' -f1 /tmp/st.txt | sort -u | wc -l); execve: $(grep -c execve /tmp/st.txt); clone: $(grep -c 'clone' /tmp/st.txt); fallocate: $(grep -c fallocate /tmp/st.txt); xattr: $(grep -c setxattr /tmp/st.txt); MAP_SHARED+PROT_WRITE: $(grep mmap /tmp/st.txt | grep MAP_SHARED | grep -c PROT_WRITE)"
    grep -E "$st" /tmp/st.txt | grep -v -E 'ENOENT|O_RDONLY' | cut -c1-170 | head -25
  )
done
