# spike/followup-item4/run.sh's zstd leg, as a define: its setup-zstd.sh is this seed.
set -eu
rm -rf /s/zstd && mkdir -p /s/zstd/state
head -c 300000 /dev/urandom > /s/zstd/state/a.bin
