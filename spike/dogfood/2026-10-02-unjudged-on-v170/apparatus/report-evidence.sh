#!/bin/sh
# What the two GitHub reports quote, run as the reports' own steps: the tool's version, the
# no-kill reproduction with `ulimit -f 0` in a fresh directory, and the write path as strace
# prints it for the one file (lines picked by the file's name). Every command is echoed.
#   sh report-evidence.sh ktlint|git-cliff
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
. /ap/env.sh
case "$1" in
ktlint)
    run 'java -jar /opt/ktlint --version; java -version 2>&1 | head -1'
    rm -rf /demo && mkdir -p /demo && cd /demo
    printf 'fun main( ) {\n    println( "hi" )\n}\n' > Main.kt
    run 'wc -c < Main.kt'
    run '( ulimit -f 0; java -jar /opt/ktlint -F Main.kt ) 2>&1 | grep -v "^\sat " | head -6; wc -c < Main.kt'
    echo; echo "## the same with --log-level=debug, as the project's template asks: the last three lines"
    printf 'fun main( ) {\n    println( "hi" )\n}\n' > Main.kt
    run '( ulimit -f 0; java -jar /opt/ktlint -F --log-level=debug Main.kt ) 2>&1 | grep -v "^\sat \|^\s\.\.\. " | tail -3; wc -c < Main.kt'
    echo; echo "## without the limit, under strace"
    printf 'fun main( ) {\n    println( "hi" )\n}\n' > Main.kt
    run 'strace -f -y -e trace=openat,write,rename,renameat,renameat2,ftruncate java -jar /opt/ktlint -F Main.kt 2>&1 | grep -F Main.kt | grep -v O_RDONLY | cut -c1-170'
    run 'wc -c < Main.kt; cat Main.kt'
    ;;
git-cliff)
    run 'git-cliff --version'
    mk() { rm -rf /demo && mkdir -p /demo && cd /demo && git init -q . && git config user.email t@example.com && git config user.name t \
        && echo a > a && git add a && git commit -qm "feat: first" && git tag v0.1.0 \
        && printf '# Changelog\n\nHand-written notes that exist nowhere else.\n' > CHANGELOG.md \
        && echo b > b && git add b && git commit -qm "fix: second"; }
    echo "## the control: a first run in a fresh home, under the limit"
    # git-cliff's update check writes a small cache file on its first run in a fresh home; under
    # the limit that write is the one that dies and CHANGELOG.md is never opened for writing.
    mk
    run 'ls "$XDG_CACHE_HOME" 2>/dev/null | wc -l'
    run 'strace -f -y -o /tmp/first.strace -e trace=openat,write sh -c "ulimit -f 0; exec git-cliff --unreleased --prepend CHANGELOG.md" > /dev/null 2>&1; echo "exit $?"; grep -B2 SIGXFSZ /tmp/first.strace | cut -c1-170; wc -c < CHANGELOG.md'
    echo; echo "## the report's steps: one ordinary run first, then the limit"
    mk
    run 'git-cliff --unreleased > /dev/null 2>&1; echo "exit $?"'
    run 'wc -c < CHANGELOG.md'
    run '( ulimit -f 0; git-cliff --unreleased --prepend CHANGELOG.md ) 2>&1 | tail -3; wc -c < CHANGELOG.md'
    echo; echo "## without the limit, under strace"
    printf '# Changelog\n\nHand-written notes that exist nowhere else.\n' > CHANGELOG.md
    run 'strace -f -y -e trace=openat,write,rename,renameat,renameat2,ftruncate git-cliff --unreleased --prepend CHANGELOG.md 2>&1 | grep -F CHANGELOG.md | grep -v O_RDONLY | cut -c1-170'
    run 'wc -c < CHANGELOG.md'
    ;;
esac
exit 0
