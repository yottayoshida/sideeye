#!/bin/sh
set -u
mkdir -p /work/d/php/src /work/d/fhome /work/d/site
printf 'From a@b Thu Jan  1 00:00:00 2026\nSubject: one\n\nbody one\n\nFrom a@b Thu Jan  1 00:01:00 2026\nSubject: two\n\nbody two\n' > /work/d/box
printf '{"name":"probe/probe","autoload":{"psr-4":{"Probe\\\\":"src/"}}}' > /work/d/php/composer.json
printf '<?php namespace Probe; class A {}\n' > /work/d/php/src/A.php
WHL=$(ls /usr/share/python-wheels/setuptools-*.whl | head -1)
echo "=== pip（実ファイル名で）==="
strace -f -e trace=clone,clone3 -o /tmp/t1 pip3 install --no-index --no-deps --target /work/d/site "$WHL" 2>&1 | tail -3
echo "rc=$? thread=$(grep -c CLONE_THREAD /tmp/t1) clone=$(grep -c clone /tmp/t1)"; ls /work/d/site | head -3
echo
echo "=== neomutt（push の引用を入れる）==="
strace -f -e trace=clone,clone3 -o /tmp/t2 env HOME=/work/d/fhome neomutt -F /dev/null -f /work/d/box -e 'push "<delete-message><sync-mailbox><quit>"' 2>&1 | tail -3
echo "rc=$? thread=$(grep -c CLONE_THREAD /tmp/t2) clone=$(grep -c clone /tmp/t2)"; wc -c < /work/d/box
echo
echo "=== composer dump-autoload の出力 ==="
env HOME=/work/d/fhome COMPOSER_HOME=/work/d/fhome/.composer composer --working-dir=/work/d/php --no-interaction dump-autoload 2>&1 | tail -5
echo "rc=$?"; find /work/d/php -maxdepth 2 | head -10
echo
echo "=== pre-commit（予備）==="
apt-get install -y --no-install-recommends git >/tmp/apt-git.log 2>&1 && echo "git OK"
mkdir -p /work/d/repo && cd /work/d/repo && git init -q . 2>/dev/null
printf 'repos:\n- repo: meta\n  hooks:\n  - id: check-useless-excludes\n' > .pre-commit-config.yaml
strace -f -e trace=clone,clone3 -o /tmp/t3 pre-commit install 2>&1 | tail -2
echo "rc=$? thread=$(grep -c CLONE_THREAD /tmp/t3) clone=$(grep -c clone /tmp/t3)"; ls -la .git/hooks/pre-commit 2>/dev/null
