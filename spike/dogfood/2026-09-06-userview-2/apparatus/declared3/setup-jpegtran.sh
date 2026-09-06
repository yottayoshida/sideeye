#!/bin/sh
mkdir -p /work/st3/jt
python3 - <<'PY'
w = h = 32
with open('/tmp/src.ppm', 'wb') as f:
    f.write(b'P6\n%d %d\n255\n' % (w, h))
    f.write(bytes([(x * 7 + y * 3) % 256 for y in range(h) for x in range(w) for _ in range(3)]))
PY
cjpeg -quality 80 -outfile /work/st3/jt/a.jpg /tmp/src.ppm
