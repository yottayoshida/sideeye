set -eu
# 2026-09-06-userview-2/apparatus/run-explore.sh, setup-ttf2.sh: one DejaVu Sans copy, which the
# operation opens and regenerates over itself.
rm -rf /s/fontforge && mkdir -p /s/fontforge/ff
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /s/fontforge/ff/f.ttf
