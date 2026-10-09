set -eu
# 2026-10-05 user-data-2's solvespace define; the binary is PR #1784 at a3b470a591.
rm -rf /s/ss /s/ss-in && mkdir -p /s/ss /s/ss-in
cp /tmp/src/solvespace/test/group/translate_asy/normal_v22.slvs /s/ss/part.slvs
