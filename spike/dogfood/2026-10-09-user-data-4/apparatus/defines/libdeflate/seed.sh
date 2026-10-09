set -eu
# A 400 KB text file; libdeflate-gzip writes notes.txt.gz (O_EXCL, one write, close) and then
# unlinks notes.txt (lab 9). The bytes are fixed so the two runs of --twice agree.
rm -rf /s/gz && mkdir -p /s/gz
python3 -c 'import random; r=random.Random(1009); open("/s/gz/notes.txt","w").write("".join(r.choice("abcdefghijklmnopqrstuvwxyz \n") for _ in range(400000)))'
[ -s /s/gz/notes.txt ]
sha256sum < /s/gz/notes.txt | cut -d' ' -f1 > /s/gz-expect.sha256
install -m 755 /ap/defines/libdeflate/check.sh /s/gz-check.sh
