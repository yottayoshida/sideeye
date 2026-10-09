# Exiv2/exiv2#9482: `exiv2 rm pic1.jpg pic2.jpg pic3.jpg`, killed at its first write to pic1.jpg (the report's
# crash point 2 of 6: after the truncating open, before the write). Three 128x128 JPEGs, as 2026-09-05 made them.
export LD_LIBRARY_PATH=/opt/exiv2/lib
mkdir -p /work/ex && cd /work/ex
for n in 1 2 3; do /opt/py/bin/python -c "from PIL import Image; Image.new('RGB',(128,128),(0,128,0)).save('pic$n.jpg')"; done
ls -l pic*.jpg | awk '{print $5, $NF}'
strace -f -qq -P "$PWD/pic1.jpg" -e trace=openat,write -e inject=write:signal=KILL /opt/exiv2/bin/exiv2 rm pic1.jpg pic2.jpg pic3.jpg; echo "exit $?"
ls -l pic*.jpg | awk '{print $5, $NF}'
for n in 1 2 3; do /opt/py/bin/python -c "from PIL import Image; Image.open('pic$n.jpg').load(); print('pic$n.jpg reads')" 2>&1 | tail -1; done
