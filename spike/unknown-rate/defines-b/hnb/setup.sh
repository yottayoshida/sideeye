#!/bin/sh
set -eu
hnb "$TOY_STATE/notes.hnb" -ui cli -e "add seeded" save >/dev/null 2>&1
[ -s "$TOY_STATE/notes.hnb" ]
