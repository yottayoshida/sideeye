# Shared predicates for the cohort-2 probe harnesses (sourced, not executed).
# Every judging predicate here is seen red once in run-drills.sh before any
# probe verdict is trusted (the repo rule: falsify a new guard against its
# own predicate, not only against the accident that motivated it).

FAILS=0
note() { echo "== $*"; }
verdict() { # name ok(yes/no) detail
    if [ "$2" = yes ]; then echo "ok   $1: $3"; else echo "FAIL $1: $3"; FAILS=$((FAILS+1)); fi
}

# strace invocation for the closure pass: %file covers every path syscall;
# write is traced so a write through an fd re-attributes paths whose open
# strace could not decode; -yy decorates fds and dirfds with real paths.
run_strace() { # logfile cmd...
    _log=$1; shift
    strace -f -yy -o "$_log" -e trace=%file,write,clone,fork,vfork "$@"
}

# Closure accounting over the strace log. FAIL-CLOSED: every successful
# mutating call must yield an attributable path; a call whose path cannot
# be read (a target that locks its memory shows bare pointers) counts as
# unattributed and fails the condition rather than vanishing. Emits
# attributed paths on stdout, one per line; the unattributed count goes to
# the file named by $2.
#
# Attribution sources, in order: the -yy result decoration for opens (the
# kernel's own resolution); quoted path arguments, joined against the
# nearest preceding dirfd decoration when relative (an approximation the
# committed raw log keeps auditable); write(fd</path>) decorations.
closure_paths() { # strace-log unattributed-count-file
    awk -v countfile="$2" '
        function emit(p) { print p }
        BEGIN { unattributed = 0 }
        # ---- successful writes through a decorated fd ----
        /^[0-9]+ +(write|pwrite64)\(/ && !/= -1 / {
            if (match($0, /\([0-9]+<[^<>]+>/)) {
                s = substr($0, RSTART, RLENGTH)
                sub(/^\([0-9]+</, "", s); sub(/>$/, "", s)
                # only filesystem paths: pipes, sockets, eventfds and other
                # anon inodes decorate too, and are not persistent state
                if (s ~ /^\//) emit(s)
            }
            next
        }
        # ---- mutating opens ----
        /^[0-9]+ +(openat2?|open|creat)\(/ && /O_WRONLY|O_RDWR|O_CREAT|O_TRUNC|O_TMPFILE/ && !/= -1 / {
            # kernel-resolved result decoration
            if (match($0, /= [0-9]+<[^<>]+>/)) {
                s = substr($0, RSTART, RLENGTH)
                sub(/^= [0-9]+</, "", s); sub(/>$/, "", s)
                emit(s); next
            }
            # quoted argument, absolute or dirfd-joined
            if (match($0, /"[^"]+"/)) {
                q = substr($0, RSTART+1, RLENGTH-2)
                if (q ~ /^\//) { emit(q); next }
                if (match($0, /<[^<>]+>/)) {
                    d = substr($0, RSTART+1, RLENGTH-2)
                    emit(d "/" q); next
                }
            }
            unattributed++; next
        }
        # ---- other mutating path syscalls ----
        /^[0-9]+ +(mkdirat?|rmdir|renameat2?|rename|linkat|link|symlinkat|symlink|unlinkat|unlink|truncate|fchmodat|chmod|fchownat|chown|lchown|utimensat|futimesat|mknodat?|mknod)\(/ && !/= -1 / {
            line = $0
            # symlink family: the first quoted argument is the link TARGET,
            # arbitrary content rather than a mutated path (hg lock symlinks
            # embed hostname/pid there); the linkpath that follows is the
            # mutation
            skipfirstq = (line ~ /^[0-9]+ +symlink(at)?\(/) ? 1 : 0
            sub(/^[0-9]+ +[a-z0-9_]+\(/, "", line)
            lastdecor = ""
            n = length(line); i = 1
            found = 0
            while (i <= n) {
                c = substr(line, i, 1)
                if (c == "<") {
                    j = index(substr(line, i+1), ">")
                    if (j == 0) break
                    lastdecor = substr(line, i+1, j-1)
                    i += j + 1
                } else if (c == "\"") {
                    j = index(substr(line, i+1), "\"")
                    if (j == 0) break
                    q = substr(line, i+1, j-1)
                    if (skipfirstq) skipfirstq = 0
                    else if (q ~ /^\//) emit(q)
                    else if (lastdecor != "") emit(lastdecor "/" q)
                    else emit("UNRESOLVED-RELATIVE/" q)
                    found = 1
                    i += j + 1
                } else if (substr(line, i, 2) == "0x") {
                    unattributed++
                    i++
                } else i++
            }
            next
        }
        END { print unattributed > countfile }
    ' "$1"
}

# stdin filter: paths not under any of the given prefixes (boundary-correct:
# the prefix itself or prefix + "/"). Defined at top level because bash 3.2
# cannot parse case alternation inside command substitution.
paths_outside() { # prefix...
    while IFS= read -r p; do
        case "$p" in
            /dev/*|/proc/*|/sys/*) continue ;;
        esac
        keep=1
        for pref in "$@"; do
            pref=${pref%/}
            case "$p" in
                "$pref"|"$pref"/*) keep=0; break ;;
            esac
        done
        [ "$keep" = 1 ] && echo "$p"
    done
}

# Condition 6, machine-judged and fail-closed: every attributed mutating
# path must sit under a declared prefix, and zero mutating calls may
# remain unattributed.
closure_check() { # strace-log opcwd declared-prefix...
    _log=$1; _cwd=$2; shift 2
    _cnt=$(mktemp)
    _left=$(closure_paths "$_log" "$_cnt" | sort -u | paths_outside "$_cwd" "$@")
    _un=$(cat "$_cnt" 2>/dev/null || echo "?")
    rm -f "$_cnt"
    if [ -z "$_left" ] && [ "$_un" = 0 ]; then
        verdict "6-closure" yes "every successful mutating call attributed, every path under the declared prefixes"
    elif [ "$_un" != 0 ]; then
        [ -n "$_left" ] && echo "$_left" | sed 's/^/   outside: /'
        verdict "6-closure" no "$_un successful mutating call(s) could not be attributed to a path (fail-closed)"
    else
        echo "$_left" | sed 's/^/   outside: /'
        verdict "6-closure" no "mutating paths outside the declared prefixes (listed above)"
    fi
}

# Successful thread creations: inline CLONE_THREAD successes plus
# unfinished/resumed pairs. The pairing is asserted: every resumed clone
# success must correspond to an unfinished CLONE_THREAD line, or the count
# is reported as inconsistent rather than silently wrong.
thread_counts() { # strace-log
    _inline=$(grep -E 'CLONE_THREAD' "$1" | grep -cE '\) += [0-9]+$')
    _unfin=$(grep -E 'CLONE_THREAD' "$1" | grep -c 'unfinished')
    _resumed=$(grep -E 'clone resumed' "$1" | grep -cE '= [0-9]+$')
    if [ "$_unfin" = "$_resumed" ]; then
        echo $((_inline + _resumed))
    else
        echo "inconsistent: $_inline inline + $_unfin unfinished CLONE_THREAD vs $_resumed resumed clone successes"
    fi
}
