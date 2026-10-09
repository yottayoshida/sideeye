# ocrmypdf/OCRmyPDF#1762, the report's steps on 17.13.0, with the PDF posted to the issue.
mkdir -p /work/ocr && cd /work/ocr
/opt/py/bin/python /ap/latest/mkpdf.py myfile.pdf > /dev/null; sha256sum myfile.pdf
strace -f -qq -P "$PWD/myfile.pdf" -e trace=write -e inject=write:signal=KILL /opt/py/bin/ocrmypdf -q --force-ocr myfile.pdf myfile.pdf; echo "exit $?"
ls -l myfile.pdf | awk '{print $5, $NF}'
