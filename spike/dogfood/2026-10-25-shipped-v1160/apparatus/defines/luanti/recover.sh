#!/bin/sh
# What a server owner does after an interrupted migration: run it again, unless world.mt already
# names the new backend (the migration then refuses: "new backend is same as the old one").
grep -q '^player_backend = sqlite3' "$SIDEEYE_STATE_DIR/world.mt" && exit 0
exec /opt/bin/luantiserver --world "$SIDEEYE_STATE_DIR" --migrate-players sqlite3
