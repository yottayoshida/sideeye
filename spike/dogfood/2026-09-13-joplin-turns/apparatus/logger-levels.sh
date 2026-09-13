#!/bin/sh
# #558 review: what each `--log-level` does to `log.txt`, run rather than read off the flag
# parser. One `mknote` per level, each over a fresh seed of its own, no strace and no Sideeye:
#
#   docker run --rm -v <this dir>:/ap:ro sideeye-joplin:2026-09-13 sh /ap/logger-levels.sh
#
# A level holds the logger quiet for that command when `log.txt` is the same size after it.
set -u
echo "joplin: $(npm ls -g joplin 2>/dev/null | grep -o 'joplin@[^ ]*')  node: $(node --version)"
for level in "" none error warn info debug; do
    SD=/w/p-${level:-unset}
    mkdir -p "$SD"
    { joplin --profile "$SD" mkbook TestBook && joplin --profile "$SD" use TestBook \
        && joplin --profile "$SD" mknote SeedNote; } > /dev/null 2>&1 || { echo "BROKEN: seed for '$level'"; continue; }
    before=$(wc -c < "$SD/log.txt" 2>/dev/null || echo absent)
    if [ -n "$level" ]; then
        joplin --log-level "$level" --profile "$SD" mknote SecondNote > /dev/null 2>&1
    else
        joplin --profile "$SD" mknote SecondNote > /dev/null 2>&1
    fi
    rc=$?
    after=$(wc -c < "$SD/log.txt" 2>/dev/null || echo absent)
    echo "--log-level ${level:-(not given)}: joplin rc=$rc  log.txt bytes before=$before after=$after"
done
