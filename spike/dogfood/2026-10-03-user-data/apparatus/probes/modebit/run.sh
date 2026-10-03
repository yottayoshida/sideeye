#!/bin/sh
# The permission-bit probe, as run on 2026-10-03 (transcripts/probe-modebit.txt): a 0755 script
# inside the state root is the operation, and preflight --twice runs it twice from restored state.
# The first run succeeds; the second cannot exec it, because restore left it 0644.
#
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <apparatus>:/ap:ro sideeye-ud1003 sh /ap/probes/modebit/run.sh
set -u
sh /ap/probes/modebit/seed.sh
ls -l /s/modebit
"$(cat /install.path)" preflight --state /s/modebit --operation /s/modebit/prog --cwd /s/modebit \
    --twice --oracle /usr/bin/strace 2>&1 | head -4
ls -l /s/modebit
