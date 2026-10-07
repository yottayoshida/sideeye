set -eu
rm -rf /s/zip /s/zip-in && mkdir -p /s/zip /s/zip-in/src && cd /s/zip-in/src
for n in a b c; do python3 -c "import sys; sys.stdout.buffer.write(bytes((i*13+ord('$n'))%256 for i in range(4096)))" > $n.bin; done
/opt/py/bin/python -I -c "import zipfile; z=zipfile.ZipFile('/s/zip/a.zip','w'); [z.write(n) for n in ('a.bin','b.bin','c.bin')]; z.close()"
test -s /s/zip/a.zip
