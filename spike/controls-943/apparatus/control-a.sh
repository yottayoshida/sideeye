#!/bin/sh
# legs.sh's break_a, from spike/dogfood/2026-10-14-mechanisms/apparatus/defines/alembic/.
exec sqlite3 "${SIDEEYE_STATE_DIR:?}/app.db" "INSERT INTO alembic_version VALUES ('r1');"
