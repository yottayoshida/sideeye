#!/bin/sh
# Lab 6: the two reports' reproductions run exactly as written (report-softhsm.md, report-ocrmypdf.md).
#   docker run --rm --network none --cap-add SYS_PTRACE -v <apparatus>:/ap:ro sideeye-fu2-1009 sh /ap/lab-6.sh
set -u
echo "## SoftHSM"
rm -rf /r1 && mkdir -p /r1 && cd /r1
export SOFTHSM2_CONF=$PWD/softhsm2.conf
mkdir tokens
printf 'directories.tokendir = %s/tokens\nobjectstore.backend = file\n' "$PWD" > softhsm2.conf
softhsm2-util --init-token --free --label t --pin 1234 --so-pin 5678
openssl genpkey -algorithm RSA -out k1.pem; openssl genpkey -algorithm RSA -out k2.pem
softhsm2-util --import k1.pem --token t --pin 1234 --label k1 --id 01
tok=$(ls -d tokens/*/)
strace -f -qq -P "$PWD/${tok}token.object" -e inject=write:signal=KILL \
  softhsm2-util --import k2.pem --token t --pin 1234 --label k2 --id 02
ls -l "$tok"; softhsm2-util --show-slots
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label t --login --pin 1234 --list-objects 2>&1 | tail -1
echo "## OCRmyPDF"
export HOME=/tmp/home; mkdir -p "$HOME"
rm -rf /r2 && mkdir -p /r2 && cd /r2 && python3 /ap/defines/ocrmypdf/mkpdf.py myfile.pdf > /dev/null && ls -l myfile.pdf
strace -f -qq -P "$PWD/myfile.pdf" -e inject=write:signal=KILL \
  ocrmypdf -q --force-ocr myfile.pdf myfile.pdf
ls -l myfile.pdf
