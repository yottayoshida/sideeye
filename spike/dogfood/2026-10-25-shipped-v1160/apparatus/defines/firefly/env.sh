# Firefly III's settings for this define, as its .env would carry them for a SQLite install: the
# database file is the state; cache, sessions and logs kept off the disk so nothing the app writes
# beside the database (its storage/ directory is in the image, outside the state) differs from one
# world to the next.
export APP_ENV=production APP_KEY=base64:c2lkZWV5ZS1kb2dmb29kLW5vdC1hLXJlYWwta2V5ISE= \
       DB_CONNECTION=sqlite DB_DATABASE=/s/ff/database.sqlite \
       CACHE_STORE=array SESSION_DRIVER=array LOG_CHANNEL=stderr APP_LOG_LEVEL=warning QUEUE_DRIVER=sync \
       SEND_TELEMETRY=false ENABLE_EXTERNAL_RATES=false
# The clock, pinned: the operation writes the time into the rows it changes (created_at, modified,
# a player's modification_date), and two clean runs a second apart differ there
# (transcripts/entry-s4.txt). Monotonic time is left real so timeouts and polls still advance.
printf '/usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1\n' > /etc/ld.so.preload
export FAKETIME="2026-01-01 00:00:00" FAKETIME_DONT_FAKE_MONOTONIC=1
