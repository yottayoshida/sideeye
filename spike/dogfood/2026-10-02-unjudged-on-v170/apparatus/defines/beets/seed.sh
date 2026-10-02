set -eu
# 2026-09-16-threads-take-turns/apparatus/run-v18.sh, setup-beets.sh: two one-track albums
# from one deterministic wav, a config whose library is the judged root, and the first album
# imported. The operation imports the second.
rm -rf /s/beets && mkdir -p /s/beets/lib /s/beets/in1 /s/beets/in2
python3 /ap/defines/beets/mkwav.py /tmp/src.wav
lame --quiet --tt Track1 --ta Artist1 --tl Album1 /tmp/src.wav /s/beets/in1/t1.mp3
lame --quiet --tt Track2 --ta Artist2 --tl Album2 /tmp/src.wav /s/beets/in2/t2.mp3
printf 'directory: %s/lib\nlibrary: %s/lib/library.db\nimport:\n  copy: yes\n  write: yes\n  quiet: yes\n  autotag: no\n' /s/beets /s/beets > /s/beets/config.yaml
beet -c /s/beets/config.yaml import -q /s/beets/in1 > /dev/null 2>&1
