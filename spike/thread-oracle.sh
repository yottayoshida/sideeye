#!/bin/sh
# A fake strace that launches the target correctly (the empty-oracle.sh argument shape)
# and then writes a canned capture carrying a clone with CLONE_FS and no CLONE_THREAD —
# the oracle's own boundary class, which emits no pid the child count reads and so
# leaves `children` at zero. It carried CLONE_THREAD until contract v16, when a thread
# of the subject stopped being a boundary; the file keeps its name because three legs
# and a BUILDLOG entry cite it.
set -u
out=""
while [ $# -gt 0 ]; do
    case $1 in
        -o) out=$2; shift 2 ;;
        -E) name=${2%%=*}; value=${2#*=}; export "$name=$value"; shift 2 ;;
        -e) shift 2 ;;
        -f | -y) shift ;;
        *) break ;;
    esac
done
"$@"; rc=$?
if [ -n "$out" ]; then
    {
      printf '%s\n' '4200  execve("/target", ["target"], 0x7ff) = 0'
      printf '%s\n' '4200  clone(child_stack=0x1, flags=CLONE_FS|CLONE_VM|SIGCHLD) = 4242'
    } > "$out"
fi
exit $rc
