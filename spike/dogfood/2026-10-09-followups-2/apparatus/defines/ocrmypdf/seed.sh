set -eu
# 2026-09-11-read-only-542/apparatus/ocrmypdf.sh, setup.sh: one minimal PDF (the 2026-09-11
# past-walls run's mkpdf.py), which the operation OCRs over itself.
rm -rf /s/ocrmypdf && mkdir -p /s/ocrmypdf/ocr
python3 /ap/defines/ocrmypdf/mkpdf.py /s/ocrmypdf/ocr/a.pdf
