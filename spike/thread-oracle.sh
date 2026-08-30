#!/bin/sh
# A fake strace that launches the target correctly (the empty-oracle.sh argument shape)
# and then writes a canned capture carrying a CLONE_THREAD clone — the oracle's own
# boundary class, which emits no second pid and so leaves `children` at zero.
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
      printf '%s\n' '4200  clone(child_stack=0x1, flags=CLONE_THREAD|CLONE_VM|CLONE_SIGHAND) = 4242'
    } > "$out"
fi
exit $rc
