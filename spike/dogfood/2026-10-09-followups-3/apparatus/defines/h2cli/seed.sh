set -eu
# A two-instrument drumkit in the legacy format (drumkit.xml and two WAVs written here); `h2cli -u`
# writes drumkit.xml.<time>.bak and rewrites drumkit.xml in the current format (lab 14:
# O_WRONLY|O_CREAT|O_TRUNC). The clock is pinned in env.sh, so the backup's name repeats.
rm -rf /s/h2 /s/h2-in /s/aux/home/.hydrogen && mkdir -p /s/h2/kit /s/h2-in
python3 /ap/defines/h2cli/make_kit.py /s/h2/kit
grep -q 'Box Kit' /s/h2/kit/drumkit.xml
