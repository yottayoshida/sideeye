#!/bin/sh
# 2026-09-06-userview-2/apparatus/run-preflight.sh lines 39-42 (op-ttf.sh), with the path moved.
# The FontForge statements are the direct spelling's (`Open(…);Generate(…);`); a sideeye.toml
# cannot carry the double quotes they need (src/config.zig: one double-quoted string, no
# escapes), so the operation is this script and the image the engine starts is /bin/sh — see
# ORIGIN.md.
exec fontforge -lang=ff -c 'Open("/s/fontforge/ff/f.ttf"); Generate("/s/fontforge/ff/f.ttf");'
