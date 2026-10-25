#!/bin/sh
# After the recovery (the conversion run again on what the crash left), the project is the one an
# uninterrupted conversion gives: no file torn, none converted twice.
cd "$SIDEEYE_STATE_DIR" && find . -path ./.godot -prune -o -type f -print | sort | xargs sha256sum > /tmp/godot-now.sha
if diff /s/aux/godot-ref/new.sha /tmp/godot-now.sha > /tmp/godot-diff.txt; then echo "checker(godot recovery): the project is the one conversion gives"; exit 0; fi
sed 's/^/checker(godot recovery): /' /tmp/godot-diff.txt | head -8; exit 1
