#!/bin/sh
# An oracle that launches the target correctly and records nothing.
#
# Exists so `oracle_saw_nothing` can be watched firing. Reaching that branch needs an
# output file that exists and is empty: a missing file takes a different path (SETUP
# ERROR, "the oracle produced no output"), and no real strace produces an empty one, so
# there was no way to exercise the gate with the tools the suite already had.
#
# Accepts the argument shape the engine builds — `-f -y -e trace=... -o FILE -E K=V ...`
# — then execs the target with those variables set, exactly as strace would.
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

[ -n "$out" ] && : >"$out"
exec "$@"
