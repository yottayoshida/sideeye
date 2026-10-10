#!/bin/sh
# The snapshotted form with no tracked file left in the working copy: `alpha` is deleted and the
# deletion snapshotted (`jj status` last), so the commit writes no file contents and no file's time
# can differ between the recording and a restored world (restore assigns timestamps; docs/cli.md).
set -eu
mkdir -p /s/jj-home /s/jj-in
R=/s/jj/repo
rm -rf /s/jj && mkdir -p "$R" && cd "$R"
jj git init > /dev/null
git config core.logAllRefUpdates false
rm -rf .git/logs
printf 'alpha, fixed bytes\n' > alpha
touch -t 202601010000 alpha
jj commit -m initial > /dev/null
rm alpha
jj status > /dev/null
