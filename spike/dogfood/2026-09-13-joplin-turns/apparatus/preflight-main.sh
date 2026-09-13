#!/bin/sh
# #558 step 5: does main still refuse joplin on the writer count, and which operations does
# the refusal name? The engine and shim built from main are mounted at /se:
#
#   docker run --rm -v <prefix>:/se:ro -v <this dir>:/ap:ro \
#     -e SIDEEYE_COMMIT=<sha> -e SIDEEYE_BUILT='<how it was built>' sideeye-joplin:2026-09-13 sh /ap/preflight-main.sh
#
# Same seed and same operation as run.sh, the default observation mode, strace as the oracle.
# JOPLIN_FLAGS goes before `--profile` on the measured command only, as in run.sh, and is
# printed: the logger-off preflight passes `-e JOPLIN_FLAGS='--log-level error'`.
#
# `sideeye --version` prints the version in build.zig.zon, which a release and every commit after it
# share, so it cannot say which main was measured. The caller names the commit and how the binaries
# were built, and the binaries' own hashes are printed beside that.
set -u
SD=/w/jp
JOPLIN_FLAGS=${JOPLIN_FLAGS:-}
echo "commit: ${SIDEEYE_COMMIT:-(not given)}  built: ${SIDEEYE_BUILT:-(not given)}"
echo "engine: $(/se/bin/sideeye --version 2>&1 | head -1)  joplin: $(npm ls -g joplin 2>/dev/null | grep -o 'joplin@[^ ]*')  flags on the measured command: '$JOPLIN_FLAGS'"
echo "engine sha256: $(sha256sum /se/bin/sideeye | cut -d' ' -f1)"
echo "shim: $(sha256sum /se/lib/libsideeye_shim.so | cut -d' ' -f1)"
mkdir -p "$SD"
{ joplin --profile "$SD" mkbook TestBook && joplin --profile "$SD" use TestBook \
    && joplin --profile "$SD" mknote SeedNote; } > /dev/null 2>&1 || { echo "BROKEN: seed"; exit 2; }
# The engine splits --operation on spaces, so an empty JOPLIN_FLAGS must add no word at all.
OP=$(command -v joplin)
[ -n "$JOPLIN_FLAGS" ] && OP="$OP $JOPLIN_FLAGS"
/se/bin/sideeye preflight --state "$SD" \
    --operation "$OP --profile $SD mknote SecondNote" \
    --shim /se/lib/libsideeye_shim.so --oracle /usr/bin/strace --work /w/work
echo "preflight rc=$?"
