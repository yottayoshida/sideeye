# Paperless-ngx's settings for this define: SQLite under the state, the journal switched from the WAL
# Paperless hard-codes (its -shm file is a shared writable mapping, ADR 0098's wall) to DELETE through
# PAPERLESS_DB_OPTIONS, the variable its settings document for overriding `init_command`
# (src/paperless/settings/custom.py, parse_db_settings) — every other PRAGMA kept as shipped.
export PAPERLESS_DATA_DIR=/s/paperless/data PAPERLESS_MEDIA_ROOT=/s/paperless/media \
       PAPERLESS_SECRET_KEY=sideeye-dogfood-not-a-secret PAPERLESS_REDIS=redis://127.0.0.1:1 \
       PAPERLESS_DB_OPTIONS='init_command=PRAGMA journal_mode=DELETE;PRAGMA synchronous=NORMAL;PRAGMA busy_timeout=5000;PRAGMA temp_store=MEMORY;PRAGMA mmap_size=134217728;PRAGMA journal_size_limit=67108864;PRAGMA cache_size=-8000' \
       PAPERLESS_NLTK_DIR=/nonexistent DJANGO_SETTINGS_MODULE=paperless.settings
# Paperless refuses every command when its consumption directory is missing (a system check error);
# it is kept outside the state, beside the run's other auxiliary directories.
export PAPERLESS_CONSUMPTION_DIR=/s/aux/consume; mkdir -p "$PAPERLESS_CONSUMPTION_DIR"
# No Redis in the box: Django's cache and Channels' layer moved to memory through the two variables
# Paperless reads for them (settings/__init__.py, _CACHE_BACKEND and _CHANNELS_BACKEND).
export PAPERLESS_CACHE_BACKEND=django.core.cache.backends.locmem.LocMemCache \
       PAPERLESS_CHANNELS_BACKEND=channels.layers.InMemoryChannelLayer
# The filing scheme the operation moves the library to (Paperless's documented reason to run
# document_renamer: the format changed), and its log kept out of the state: it is not the user's.
export PAPERLESS_FILENAME_FORMAT='{{ correspondent }}/{{ title }}' PAPERLESS_LOGGING_DIR=/s/aux/plog
mkdir -p /s/aux/plog
# The clock, pinned: the operation writes the time into the rows it changes (created_at, modified,
# a player's modification_date), and two clean runs a second apart differ there
# (transcripts/entry-s4.txt). Monotonic time is left real so timeouts and polls still advance.
printf '/usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1\n' > /etc/ld.so.preload
export FAKETIME="2026-01-01 00:00:00" FAKETIME_DONT_FAKE_MONOTONIC=1
