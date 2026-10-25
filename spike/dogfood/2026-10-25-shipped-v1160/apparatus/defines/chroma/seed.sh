set -eu
# A persistent directory of one collection, 200 documents with fixed 16-dimension embeddings, the odd
# half deleted (make.py), made once per box so its collection's UUID is the same in every run, and
# copied before each run. The digest the checker wants is read from it once.
py=/opt/chroma/bin/python
if [ ! -f /s/.chroma-expect ]; then
    mkdir -p /s
    $py -I /ap/defines/chroma/make.py seed /s/.chroma-pristine > /s/.chroma-seed.log 2>&1
    $py -I /ap/defines/chroma/make.py read /s/.chroma-pristine 2>> /s/.chroma-seed.log > /s/.chroma-expect
fi
rm -rf /s/chroma && cp -a /s/.chroma-pristine /s/chroma
install -m 755 /ap/defines/chroma/check.sh /s/chroma-check.sh
