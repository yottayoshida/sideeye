set -eu
. /ap/defines/trashcli-latest/env.sh
rm -rf /s/tc && mkdir -p /s/tc/live && cd /s/tc
for f in kept1 kept2 kept3; do echo $f > live/$f.txt; /opt/py/bin/trash-put live/$f.txt; done
echo doomed > live/doomed.txt
test "$(ls data/Trash/info | wc -l)" = 3
