#!/bin/sh
# Set 3: one define's preflight --twice under extra flags, to ask a wall the next steps the gate does
# not follow (another observation mode, a one-thread switch declared as apparatus).
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro -v <out>:/out \
#       sideeye-sv1025-s3 sh /ap/try-s3.sh <name> <label> [extra flags ...]
set -u
t=$1; label=$2; shift 2
d=/ap/defines/$t; SE=$(cat /install.path)
. /ap/env.sh; [ -f $d/env.sh ] && . $d/env.sh
sh $d/seed.sh > /dev/null 2>&1 || { echo "seed failed"; exit 2; }
extra=$(printf '%s\n' "$@"); set --
while IFS= read -r l; do set -- "$@" "$l"; done <<X
$(python3 /ap/toml2flags.py $d/sideeye.toml)
X
while IFS= read -r l; do [ -n "$l" ] && set -- "$@" "$l"; done <<X
$extra
X
mkdir -p /out/try
"$SE" preflight "$@" --twice --oracle /usr/bin/strace > /out/try/$t.$label.txt 2>&1
echo "$t $label rc=$? $(sed -n 's/^UNKNOWN  *//p;s/^SETUP ERROR  *//p' /out/try/$t.$label.txt | head -1) $(grep -o 'recording accepted — [0-9]* state-changing' /out/try/$t.$label.txt | head -1)"
