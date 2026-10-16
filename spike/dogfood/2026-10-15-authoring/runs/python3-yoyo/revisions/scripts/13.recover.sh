#!/bin/sh
# What a user runs after a crashed `yoyo apply`, before running yoyo again.
# A killed apply leaves its row in yoyo_lock; the next apply waits 10 s and stops with
# "run yoyo break-lock to remove this lock". break-lock is that documented step. Its open of
# app.db is also SQLite's own recovery: a hot journal is rolled back by the first opener.
# Runs in the directory holding app.db (the state directory).
set -u
cd "${SIDEEYE_STATE_DIR:-.}" || exit 1
exec timeout 60 python3 -m yoyo break-lock --batch --database sqlite:///app.db
