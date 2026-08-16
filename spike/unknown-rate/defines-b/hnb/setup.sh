#!/bin/sh
set -eu
hnb "$TOY_STATE/notes.hnb" -ui cli -e "add seeded" >/dev/null 2>&1
[ -s "$TOY_STATE/notes.hnb" ]
