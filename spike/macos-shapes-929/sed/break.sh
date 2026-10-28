#!/bin/sh
set -eu
head -n 2 "$1/app.conf" > "$1/app.conf.cut" && mv "$1/app.conf.cut" "$1/app.conf"
