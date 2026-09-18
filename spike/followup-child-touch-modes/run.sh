#!/bin/sh
# Bounded measurement (#617 follow-on): the three targets g3 refused
# `child_touched_state_dir`, each run once under the default observation mode and once
# under `--observe syscalls`, on the engine g3 used (the pinned v1.5.0 release).
#
# Not a sweep: g3 is complete and is never re-measured in place. Nothing here writes into
# artifacts-g3, no manifest is produced, and the defines are used exactly as committed.
#
# The apparatus is recorded from inside the box rather than asserted in the notes, the way
# spike/followup-527 does it: artifacts/apparatus.txt holds the engine's own version line,
# the sha256 of both artefacts as the container sees them, the image digests, and — per
# run — the exact argv the engine was given. Without that, "the engine g3 used" and "the
# flag reached the engine" are claims the record cannot answer.
#
# Usage: run.sh <repo> <engine-zig-out> <out-dir>
set -u
R=${1:?repo}; ENG=${2:?engine zig-out}; OUT=${3:?out dir}
mkdir -p "$OUT" || exit 1
APP=$OUT/apparatus.txt
: > "$APP"

for img in sideeye-ur-b2 sideeye-ur-extra; do
    printf 'image %s %s\n' "$img" \
        "$(docker images --no-trunc --format '{{.ID}}' "$img" | head -1)" >> "$APP"
done

# The engine's identity as the box sees it, not as the host asserts it.
docker run --rm -v "$ENG":/work/zig-out:ro sideeye-ur-b2 sh -c '
  echo "## sideeye version"; /work/zig-out/bin/sideeye version
  echo "## sha256"; sha256sum /work/zig-out/bin/sideeye /work/zig-out/lib/libsideeye_shim.so
  echo "## uname"; uname -m' >> "$APP" 2>&1

# target:define-dir:image — pacpl and mail-expire are B2 (the trixie image), lbdb is B.
for row in \
    "pacpl:defines-b2/pacpl:sideeye-ur-b2" \
    "mail-expire:defines-b2/mail-expire:sideeye-ur-b2" \
    "lbdb:defines-b/lbdb:sideeye-ur-extra"; do
    t=${row%%:*}; rest=${row#*:}; defs=${rest%%:*}; img=${rest##*:}
    for mode in wrappers syscalls; do
        echo "=== $t / $mode ($img) ==="
        flag=""
        [ "$mode" = syscalls ] && flag="--observe syscalls"
        # One state root for both modes of a target, emptied between them: the refusal
        # messages name the state path, and a path carrying the mode would make two runs
        # that differ only in the flag look like two runs that differ in their message.
        docker run --rm -v "$R":/work:ro -v "$ENG":/work/zig-out:ro \
            -v "$OUT":/out "$img" sh -c "
            set -u
            t='$t'; defs=/work/spike/unknown-rate/$defs; mode='$mode'
            extra=''
            [ -f \"\$defs/packages.txt\" ] && extra=\$(grep -v '^#' \"\$defs/packages.txt\" | tr '\n' ' ')
            apt-get install -y --no-install-recommends \$t \$extra >/tmp/apt.log 2>&1 || {
                echo 'INSTALL FAILED'; tail -n 3 /tmp/apt.log; exit 3; }
            export HOME=/tmp/bgroup-home/\$t; mkdir -p \"\$HOME\"
            root=/tmp/m/\$t; rm -rf \"\$root\"; mkdir -p \"\$root/state\"
            if [ -f \"\$defs/op.txt\" ]; then
                op=\$(head -n 1 \"\$defs/op.txt\" | sed \"s|\\\$TOY_STATE|\$root/state|g\")
            else
                op=\$defs/op.sh
            fi
            # The argv this run was given, recorded beside the reports.
            printf 'run %s %s :: explore --state %s --setup %s --operation %s --shim %s --oracle /usr/bin/strace --work %s --json %s %s\n' \\
                \"\$t\" \"\$mode\" \"\$root/state\" \"\$defs/setup.sh\" \"\$op\" /work/zig-out/lib/libsideeye_shim.so \"\$root/work\" /out/\$t-\$mode.json '$flag' >> /out/apparatus.txt
            /work/zig-out/bin/sideeye explore --state \"\$root/state\" --setup \"\$defs/setup.sh\" \\
                --operation \"\$op\" --shim /work/zig-out/lib/libsideeye_shim.so \\
                --oracle /usr/bin/strace --work \"\$root/work\" \\
                --json /out/\$t-\$mode.json $flag > /out/\$t-\$mode.txt 2>&1
            echo \"exit=\$?\"
            head -n 3 /out/\$t-\$mode.txt
        "
    done
done
