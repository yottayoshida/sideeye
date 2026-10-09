set -eu
# An uncompressed CHD (lab 11: a compressed one is refused "File not writeable"); addmeta writes
# the metadata entry past the end and then the header's pointer, in place (lab 12: three pwrite64).
rm -rf /s/chd && mkdir -p /s/chd
python3 -c 'open("/s/chd-raw.bin","wb").write(bytes((i*7+3)%251 for i in range(1048576)))'
chdman createraw -i /s/chd-raw.bin -o /s/chd/d.chd -hs 4096 -us 512 -c none > /s/chd-seed.log 2>&1
[ -s /s/chd/d.chd ]
