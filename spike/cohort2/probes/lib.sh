# Shared predicates for the cohort-2 probe harnesses (sourced, not executed).
# Every predicate here is seen red once in run-drills.sh before any probe
# verdict is trusted (the repo rule: falsify a new guard against its own
# predicate, not only against the accident that motivated it).

FAILS=0
note() { echo "== $*"; }
verdict() { # name ok(yes/no) detail
    if [ "$2" = yes ]; then echo "ok   $1: $3"; else echo "FAIL $1: $3"; FAILS=$((FAILS+1)); fi
}

# strace invocation for the closure pass: %file covers every path syscall
# (open/openat/openat2, creat, mkdir*, rmdir, rename*, link*, symlink*,
# unlink*, truncate*, chmod/fchmodat*, chown*, utimensat, mknod*); -yy
# decodes fd-relative paths so dirfd-relative opens are attributable.
run_strace() { # logfile cmd...
    _log=$1; shift
    strace -f -yy -o "$_log" -e trace=%file,write,clone,fork,vfork "$@"
}

# Every path a MUTATING syscall touched, one per line, deduped. Lines are
# taken only from successful calls (failed calls mutate nothing). For the
# open class the -yy RESULT decoration (`= N</resolved/path>`) is the
# source — it is the kernel's own resolution, immune to dirfd/cwd games.
# For the other mutating syscalls the quoted arguments are the source;
# dirfd-relative arguments there resolve against the operation's cwd in
# closure_check, an approximation the committed raw strace log keeps
# auditable.
mutating_paths() { # strace-log
    grep -E '^\S+ +(openat|openat2|open|creat)\(' "$1" | grep -E 'O_WRONLY|O_RDWR|O_CREAT|O_TRUNC' \
        | grep -oE '= [0-9]+<[^<>]+>$' | sed -e 's/^= [0-9]*<//' -e 's/>$//'
    grep -E '^\S+ +(mkdir|mkdirat|rmdir|rename|renameat|renameat2|link|linkat|symlink|symlinkat|unlink|unlinkat|truncate|ftruncate|chmod|fchmod|fchmodat|chown|lchown|fchown|fchownat|utimensat|futimesat|mknod|mknodat)\(' "$1" \
        | grep -vE '= -[0-9]+ ' | grep -oE '"[^"]+"'
}

# Condition 6, machine-judged: every mutating path must sit under one of
# the declared prefixes. Relative paths (no leading /) are resolved against
# the operation's cwd, which callers pass as the first prefix when the
# operation runs inside the state root. Anything left over fails the probe.
closure_check() { # strace-log opcwd declared-prefix...
    _log=$1; _cwd=$2; shift 2
    _left=$(mutating_paths "$_log" | tr -d '"' \
        | while IFS= read -r p; do
            case "$p" in
                /*) echo "$p" ;;
                pipe:*|socket:*|anon_inode:*|/dev/pts*) ;;
                *) echo "$_cwd/$p" ;;
            esac
        done | sort -u | while IFS= read -r p; do
            keep=1
            for pref in "$_cwd" "$@" /dev/ /proc/ /sys/; do
                case "$p" in "$pref"*) keep=0; break ;; esac
            done
            [ "$keep" = 1 ] && echo "$p"
        done)
    if [ -z "$_left" ]; then
        verdict "6-closure" yes "every mutating path sits under the declared prefixes"
    else
        echo "$_left" | sed 's/^/   outside: /'
        verdict "6-closure" no "mutating paths outside the declared prefixes (listed above)"
    fi
}

thread_counts() { # strace-log -> "total successful CLONE_THREAD creations"
    grep -E 'CLONE_THREAD' "$1" | grep -cE '= [0-9]+$'
}
