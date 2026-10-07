set -eu
rm -rf /s/mz /s/mz-in && mkdir -p /s/mz /s/mz-in/src && cd /s/mz-in/src
for n in a b c; do python3 -c "import sys; sys.stdout.buffer.write(bytes((i*11+ord('$n'))%256 for i in range(4096)))" > $n.bin; done
/opt/py/bin/python -I -c "import zipfile; z=zipfile.ZipFile('/s/mz/a.zip','w'); [z.write(n) for n in ('a.bin','b.bin','c.bin')]; z.close()"
test -s /s/mz/a.zip
