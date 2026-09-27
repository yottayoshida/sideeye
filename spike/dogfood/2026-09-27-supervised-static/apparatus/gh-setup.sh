#!/bin/sh
# gh writes its config under GH_CONFIG_DIR (the judged root) and state under $HOME; start clean.
rm -rf /tmp/ghhome
mkdir -p /tmp/ghhome
