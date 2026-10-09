set -eu
# 2026-10-05 user-data-2's solvespace define; the binary is v3.2 built from its tag, as 2026-10-05 measured #1783.
rm -rf /s/ss /s/ss-in && mkdir -p /s/ss /s/ss-in
cp /tmp/src/solvespace/test/group/translate_asy/normal_v22.slvs /s/ss/part.slvs
