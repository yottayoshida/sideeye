#!/bin/sh
# Lab 5: OCRmyPDF's in-place run (the cookbook's `ocrmypdf myfile.pdf myfile.pdf`) without Sideeye —
# strace kills it at its first write to the input/output file, after the open that truncates it.
#   docker run --rm --network none --cap-add SYS_PTRACE -v <apparatus>:/ap:ro sideeye-fu2-1009 sh /ap/lab-5.sh
set -u
export HOME=/tmp/home; mkdir -p "$HOME"
rm -rf /t && mkdir -p /t && cd /t
python3 /ap/defines/ocrmypdf/mkpdf.py /t/myfile.pdf
ls -l /t/myfile.pdf; head -c 8 /t/myfile.pdf; echo
strace -f -qq -o /tmp/ocr.strace -P /t/myfile.pdf -e trace=openat,write -e inject=write:signal=KILL \
  ocrmypdf -q --force-ocr myfile.pdf myfile.pdf; echo "ocrmypdf exit $?"
grep -v ENOENT /tmp/ocr.strace | grep -E 'O_TRUNC|write|killed' | tail -4 | cut -c1-160
ls -l /t/myfile.pdf
echo "## the same command, not killed"
python3 /ap/defines/ocrmypdf/mkpdf.py /t/myfile.pdf
ocrmypdf -q --force-ocr myfile.pdf myfile.pdf; echo "ocrmypdf exit $?"; ls -l /t/myfile.pdf
