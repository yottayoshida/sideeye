#!/bin/sh
# legs.sh's break_d, from spike/dogfood/2026-10-14-mechanisms/apparatus/defines/alembic/.
exec sqlite3 "${SIDEEYE_STATE_DIR:?}/app.db" "ALTER TABLE notes DROP COLUMN created; ALTER TABLE notes RENAME COLUMN text TO body; UPDATE alembic_version SET version_num = 'r1'; CREATE TABLE _alembic_tmp_notes (x INTEGER);"
