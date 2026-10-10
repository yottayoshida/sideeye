#!/bin/sh
# 1 レシピにつき 4 通り。結果は "<名前> rc=<n>" で出す
set -u
res() { echo "RESULT $1 rc=$2"; }
cp -r /box/py /tmp/py; cd /tmp/py
pytest -q -p no:cacheprovider test_crash_consistency.py > /out/py-clean.txt 2>&1; res py-clean $?
sed 's/^BUGGY = False/BUGGY = True/' keytool.py > k && mv k keytool.py
pytest -q -p no:cacheprovider test_crash_consistency.py > /out/py-bug.txt 2>&1; res py-bug $?
sed 's/^BUGGY = True/BUGGY = False/' keytool.py > k && mv k keytool.py
sed 's|"--oracle", "/usr/bin/strace",|"--allow-unverified",|' test_crash_consistency.py > /tmp/t.py && cp /tmp/t.py test_crash_consistency.py
pytest -q -p no:cacheprovider test_crash_consistency.py > /out/py-nooracle.txt 2>&1; res py-nooracle $?
cp /box/py/test_crash_consistency.py .
PATH=/usr/bin:/bin pytest -q -p no:cacheprovider test_crash_consistency.py > /out/py-nosideeye.txt 2>&1; res py-nosideeye $?
cp -r /box/rs /tmp/rs; cd /tmp/rs
cargo test -q --offline > /out/rs-clean.txt 2>&1; res rs-clean $?
cargo test -q --offline --features buggy > /out/rs-bug.txt 2>&1; res rs-bug $?
sed 's|.args(\["--oracle", "/usr/bin/strace"\])|.args(["--allow-unverified"])|' tests/crash_consistency.rs > /tmp/c.rs && cp /tmp/c.rs tests/crash_consistency.rs
cargo test -q --offline > /out/rs-nooracle.txt 2>&1; res rs-nooracle $?
cp /box/rs/tests/crash_consistency.rs tests/
PATH=/usr/bin:/bin cargo test -q --offline > /out/rs-nosideeye.txt 2>&1; res rs-nosideeye $?
