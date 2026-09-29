#!/bin/sh
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
terraform version | head -1
# repo/ is where fmt runs; repo/mod/versions.tf is a link to ../versions.tf, i.e. repo/versions.tf.
# Resolved from the cwd instead of from repo/mod, ../versions.tf is /w/versions.tf, a different
# file that happens to exist.
rm -rf /w && mkdir -p /w/repo/mod
printf 'terraform {\nrequired_version=">= 1.0"\n}\n' > /w/repo/versions.tf
ln -s ../versions.tf /w/repo/mod/versions.tf
printf '# not part of this repo\nlocals {\n  keep = "me"\n}\n' > /w/versions.tf
cd /w/repo
run 'cat /w/versions.tf; echo ...; cat versions.tf'
run 'terraform fmt mod; echo "exit $?"'
run 'cat /w/versions.tf; echo ...; cat versions.tf; ls -l mod'
