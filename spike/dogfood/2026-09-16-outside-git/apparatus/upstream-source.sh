#!/bin/sh
# The upstream source of the two rewrites RESULTS.md reports on, at the measured release and on the
# default branch, so the pages can say which version does what. Line numbers are the files' own.
set -u
nv() {  # nv <ref>
  gh api "repos/neovim/neovim/contents/src/nvim/shada.c?ref=$1" --jq .content | base64 -d > /tmp/shada.c
  gh api "repos/neovim/neovim/contents/src/nvim/fileio.c?ref=$1" --jq .content | base64 -d > /tmp/fileio.c
  echo "== neovim $1: src/nvim/shada.c, shada_write_file — the write, the rename, the close"
  grep -n -E 'const ShaDaWriteResult sw_ret = shada_write\(|vim_rename\(tempname, fname\)|os_remove\(tempname\);|^  close_file\(&sd_writer\);' /tmp/shada.c
  echo "== neovim $1: src/nvim/fileio.c, vim_rename — the target removed before the rename"
  awk '/^int vim_rename\(/{on=1} on&&/os_remove\(to\);|os_rename\(from, to\) == OK/{print NR": "$0} on&&/^}/{exit}' /tmp/fileio.c
}
nv v0.10.4
nv master
echo "== neovim latest release: $(gh api repos/neovim/neovim/releases/latest --jq '.tag_name + " " + .published_at[:10]')"
aw() {  # aw <ref>
  gh api "repos/aws/aws-cli/contents/awscli/customizations/configure/writer.py?ref=$1" --jq .content | base64 -d > /tmp/writer.py
  echo "== aws-cli $1: awscli/customizations/configure/writer.py — the rewrite of an existing file"
  grep -n -E "with open\(config_filename, 'w'\) as f:|f.write\(''.join\(contents\)\)" /tmp/writer.py
}
aw 2.23.6
aw v2
echo "== aws-cli: latest tag $(gh api 'repos/aws/aws-cli/tags?per_page=1' --jq '.[0].name')"
