#!/bin/sh
# An oracle that launches the target correctly and then removes its own capture.
#
# Exists so the unreadable-capture refusal can be watched firing — the branch #363
# adjudicated: a capture file that cannot be read is a SETUP ERROR (exit 3) saying
# so, while a readable-but-empty capture is UNKNOWN oracle_saw_nothing (that one is
# empty-oracle.sh's leg). No real strace removes its own -o file, so the suite had
# no way to drive this branch. Argument handling mirrors empty-oracle.sh; the
# target is run as a child rather than exec'd because the removal has to happen
# after it finishes.
set -u

out=""
while [ $# -gt 0 ]; do
    case $1 in
        -o)
            out=$2
            shift 2
            ;;
        -E)
            name=${2%%=*}
            value=${2#*=}
            export "$name=$value"
            shift 2
            ;;
        -e)
            shift 2
            ;;
        -f | -y)
            shift
            ;;
        *)
            break
            ;;
    esac
done

"$@"
rc=$?
[ -n "$out" ] && rm -f "$out"
exit $rc
