set -eu
# An ATAC collection with one request, written by atac; the operation adds a second request, which
# rewrites demo.json (lab 18: demo.json_ opened O_TRUNC and renamed over demo.json, twice).
rm -rf /s/atac /s/atac-in && mkdir -p /s/atac /s/atac-in
atac --directory /s/atac collection new demo > /s/atac-seed.log 2>&1
atac --directory /s/atac request new demo/ping -u http://localhost/ >> /s/atac-seed.log 2>&1
grep -q ping /s/atac/demo.json
