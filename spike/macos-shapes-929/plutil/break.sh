#!/bin/sh
set -eu
n=$(wc -c < "$1/prefs.plist")
head -c $((n / 2)) "$1/prefs.plist" > "$1/prefs.cut" && mv "$1/prefs.cut" "$1/prefs.plist"
