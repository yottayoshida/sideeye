#!/bin/sh
# #558 step 6, done again after review: can joplin CLI 3.7.1 stop writing log.txt, and how?
#
#   docker run --rm -v <this dir>:/ap:ro sideeye-joplin:2026-09-13 sh /ap/logger-level.sh
#
# The first reading looked only at `joplin help all` and the keys of `config -v`. A start-up flag
# is neither a command nor a setting, so it appears in neither, and review found one in joplin's
# source. This prints both halves: what help and settings name, and what the installed package's
# own code does with a log level — where it reads one, what a missing one becomes, and where the
# file logger takes it.
set -u
P=/tmp/lp
R=$(npm root -g)/joplin/node_modules
echo "joplin: $(npm ls -g joplin 2>/dev/null | grep -o 'joplin@[^ ]*')"

echo "## joplin help all: lines naming log, level, verbose, quiet or debug"
joplin --profile "$P" help all 2>&1 | grep -i -E "log|level|verbose|quiet|debug"
echo "## joplin config -v: $(joplin --profile "$P" config -v 2>/dev/null | wc -l) lines; those naming log, level or debug:"
joplin --profile "$P" config -v 2>&1 | grep -i -E "log|level|debug" || echo "(none)"

echo "## the installed code"
f=$R/@joplin/lib/utils/processStartFlags.js
echo "-- $f"
grep -n "log-level\|matched.logLevel" "$f"
f=$R/@joplin/lib/BaseApplication.js
echo "-- $f"
grep -n "flags.txt\|log.txt\|setLevel(initArgs.logLevel)" "$f"
for f in $(find "$R" -name Logger.js -path '*@joplin/utils*' | head -2); do
    echo "-- $f"
    grep -n "LEVEL_NONE =\|LEVEL_ERROR =\|LEVEL_INFO =\|static levelStringToId\|targetLevel(target) < level" "$f"
done
