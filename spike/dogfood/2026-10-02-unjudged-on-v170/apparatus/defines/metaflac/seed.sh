set -eu
# 2026-09-06-userview-2/apparatus/run-explore.sh, setup-flac2.sh: three flac files from one
# deterministic wav, each tagged ORIG=keep so the checker can see the original tag survive —
# metaflac rewrites only the padding block, so a file can stay readable and still be wrong.
rm -rf /s/metaflac && mkdir -p /s/metaflac/fl
python3 /ap/defines/metaflac/mkwav.py /tmp/src.wav
for n in a b c; do
  flac -s -f /tmp/src.wav -o "/s/metaflac/fl/$n.flac"
  metaflac --set-tag=ORIG=keep "/s/metaflac/fl/$n.flac"
done
