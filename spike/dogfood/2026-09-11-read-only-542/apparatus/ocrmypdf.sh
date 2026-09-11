#!/bin/sh
# #542, first of two: ocrmypdf past `faccessat2`, in both observation modes — a preflight
# and an exploration each — against whichever sideeye build is mounted at /se.
#
# Image: debian:trixie-slim with strace, file, python3, ca-certificates, procps, ocrmypdf,
# tesseract-ocr-eng and ghostscript from apt (the 2026-09-11 run's Dockerfile copies an
# oxipng and a Bun binary from the host, which are gone; this is its ocrmypdf half). The
# input PDF comes from that run's mkpdf.py, mounted at /pw. This directory is mounted at
# /d; state and work live on the container's own filesystem (#528).
#
# Usage: ocrmypdf.sh <label>   — before | after: which build is mounted.
set -u
label=${1:?usage: ocrmypdf.sh <before|after>}
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/tmp/localrun
OUT=/d/transcripts
# A HOME the run can write, whoever it runs as: under an unprivileged --user the image's
# HOME is not writable, and fontconfig, tesseract and ghostscript then fail to cache.
HOME=$R/home
export HOME
mkdir -p "$OUT" "$R/ap" "$HOME"
"$SE" version
ocrmypdf --version

cat > "$R/ap/setup.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; python3 /pw/mkpdf.py "$SD/a.pdf"
EOX
# The file ocrmypdf rewrites in place must still be a PDF in every world: the header, and
# a trailer in its last kilobyte.
cat > "$R/ap/check.sh" <<'EOX'
#!/bin/sh
python3 - "$SD/a.pdf" <<'EOP'
import sys
try:
    b = open(sys.argv[1], "rb").read()
except OSError as e:
    print("a.pdf unreadable: %s" % e); sys.exit(1)
if not b.startswith(b"%PDF-"):
    print("a.pdf does not start with %%PDF- (%d bytes)" % len(b)); sys.exit(1)
if b"%%EOF" not in b[-1024:]:
    print("a.pdf has no %%%%EOF in its last KiB (%d bytes)" % len(b)); sys.exit(1)
EOP
EOX
chmod 755 "$R/ap/setup.sh" "$R/ap/check.sh"

for mode in wrappers syscalls; do
    for what in preflight explore; do
        SD=$R/st/$mode-$what/ocr
        export SD
        mkdir -p "$SD" "$R/wk/$mode-$what"
        if [ "$what" = preflight ]; then
            "$SE" preflight --state "$SD" --setup "$R/ap/setup.sh" \
                --operation "ocrmypdf -q --force-ocr $SD/a.pdf $SD/a.pdf" \
                --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --work "$R/wk/$mode-$what" \
                > "$OUT/ocrmypdf.$label.$mode.$what.txt" 2>&1
        else
            "$SE" explore --state "$SD" --setup "$R/ap/setup.sh" \
                --operation "ocrmypdf -q --force-ocr $SD/a.pdf $SD/a.pdf" --check "$R/ap/check.sh" \
                --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --work "$R/wk/$mode-$what" \
                --json "$OUT/ocrmypdf.$label.$mode.$what.json" \
                > "$OUT/ocrmypdf.$label.$mode.$what.txt" 2>&1
        fi
        rc=$?
        echo "$mode $what rc=$rc: $(head -2 "$OUT/ocrmypdf.$label.$mode.$what.txt" | tr -s ' \n' ' ')"
    done
done
