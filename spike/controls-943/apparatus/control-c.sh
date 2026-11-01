#!/bin/sh
# legs.sh's break_c, from spike/dogfood/2026-10-14-mechanisms/apparatus/defines/alembic/.
exec sqlite3 "${SIDEEYE_STATE_DIR:?}/app.db" "DELETE FROM notes WHERE id = 50;"
