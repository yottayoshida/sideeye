set -eu
# 2026-09-06-userview-2/apparatus/run-preflight.sh, setup-pdf.sh: one minimal PDF with a correct
# xref, so mutool takes its normal reading path and not its repair path (mkpdf.py).
rm -rf /s/mutool-1285 && mkdir -p /s/mutool-1285/mu
python3 /ap/defines/mutool-1285/mkpdf.py /s/mutool-1285/mu/a.pdf > /dev/null
