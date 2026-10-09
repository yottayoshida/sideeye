set -eu
# zvm's settings with a custom Zig version map already set; the operation sets the ZLS map, which
# rewrites settings.json (lab 13: O_WRONLY|O_CREAT|O_TRUNC, twice).
rm -rf /s/aux/home/.zvm /s/zv && mkdir -p /s/zv
# On a home with no ~/.zvm the first command creates it and `vmu` then fails ("unable to create
# settings.json file open : no such file or directory", transcripts/entry-out/entry/zvm.seed.log);
# any first command initializes it, as `--help` did in lab 13.
zvm version > /s/zv-seed.log 2>&1
zvm vmu zig https://example.org/zig-index.json >> /s/zv-seed.log 2>&1
grep -q example.org /s/aux/home/.zvm/settings.json
