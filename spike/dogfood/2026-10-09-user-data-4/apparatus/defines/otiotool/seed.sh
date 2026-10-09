set -eu
# A three-clip timeline written by the same library; otiotool --redact writes it back over
# the same path (lab 1: open O_WRONLY|O_CREAT|O_TRUNC on cut.otio, then the write).
rm -rf /s/otio && mkdir -p /s/otio
/opt/py/bin/python3 /ap/defines/otiotool/make.py /s/otio/cut.otio > /s/otio-seed.log 2>&1
grep -q take2 /s/otio/cut.otio
