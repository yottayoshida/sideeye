set -eu
rm -rf /s/bzip3 && mkdir -p /s/bzip3 && cd /s/bzip3
i=0; while [ $i -lt 2000 ]; do echo "line $i of a log that matters"; i=$((i+1)); done > a.log
