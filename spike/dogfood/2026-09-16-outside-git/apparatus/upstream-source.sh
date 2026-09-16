#!/bin/sh
# The upstream source of the two rewrites RESULTS.md reports on, at the measured releases and on the
# default branch, so the pages can say which version does what. Line numbers are the files' own.
# The first version grepped four fixed lines of shada_write_file and so could not see the flush
# v0.11.0 added at the end of shada_write, before the rename; the first review of this record read
# it in the source. This version prints that flush for every ref.
set -u
nv() {  # nv <ref>
  gh api "repos/neovim/neovim/contents/src/nvim/shada.c?ref=$1" --jq .content | base64 -d > /tmp/shada.c
  gh api "repos/neovim/neovim/contents/src/nvim/fileio.c?ref=$1" --jq .content | base64 -d > /tmp/fileio.c
  echo "== neovim $1: src/nvim/shada.c — the flush at the end of shada_write (absent before v0.11.0), then in shada_write_file the rename and the close"
  grep -n -E '^shada_write_exit:|packer\.packer_flush\(&packer\);|const ShaDaWriteResult sw_ret = shada_write\(|vim_rename\(tempname, fname\)|os_remove\(tempname\);|^  close_file\(&sd_writer\);' /tmp/shada.c
  echo "   ($(grep -c 'packer_flush(&packer)' /tmp/shada.c) packer_flush(&packer) call(s) in this file)"
  echo "== neovim $1: src/nvim/fileio.c, vim_rename — the target removed before the rename"
  awk '/^int vim_rename\(/{on=1} on&&/os_remove\(to\);|os_rename\(from, to\) == OK/{print NR": "$0} on&&/^}/{exit}' /tmp/fileio.c
}
nv v0.10.4
nv v0.11.0
nv v0.12.5
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
