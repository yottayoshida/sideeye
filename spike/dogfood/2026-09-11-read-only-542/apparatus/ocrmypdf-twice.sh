#!/bin/sh
# #542, first of two: why ocrmypdf's exploration refuses `baseline_violates_invariant` once it
# is past `faccessat2`. `preflight --twice` runs the operation twice from the same pre-state
# and compares the bytes it left — plainly, and with SOURCE_DATE_EPOCH set, to see whether a
# define can make the output byte-repeatable. Same image, mounts and layout as ocrmypdf.sh.
#
# Usage: ocrmypdf-twice.sh <label>
set -u
label=${1:?usage: ocrmypdf-twice.sh <before|after>}
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/tmp/localrun
OUT=/d/transcripts
HOME=$R/home
export HOME
mkdir -p "$OUT" "$R/ap" "$HOME"
"$SE" version
ocrmypdf --version

cat > "$R/ap/setup.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; python3 /pw/mkpdf.py "$SD/a.pdf"
EOX
chmod 755 "$R/ap/setup.sh"

for variant in plain epoch; do
    SD=$R/st/twice-$variant/ocr
    export SD
    mkdir -p "$SD" "$R/wk/twice-$variant"
    op="ocrmypdf -q --force-ocr $SD/a.pdf $SD/a.pdf"
    [ "$variant" = epoch ] && op="env SOURCE_DATE_EPOCH=1700000000 $op"
    "$SE" preflight --twice --state "$SD" --setup "$R/ap/setup.sh" --operation "$op" \
        --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/twice-$variant" \
        > "$OUT/ocrmypdf.$label.twice-$variant.txt" 2>&1
    echo "twice $variant rc=$?: $(grep -E '^PREFLIGHT|differ|equal|identical' "$OUT/ocrmypdf.$label.twice-$variant.txt" | head -2 | tr -s ' \n' ' ')"
done
