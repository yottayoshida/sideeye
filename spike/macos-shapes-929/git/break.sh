#!/bin/sh
set -eu
victim=$(find "$1/repo/.git/objects" -type f -path '*/objects/??/*' | sort | head -n 1)
[ -n "$victim" ] && rm -f "$victim"
