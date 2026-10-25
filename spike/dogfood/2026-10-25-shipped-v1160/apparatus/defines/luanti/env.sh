# Luanti needs no other setting for this define; the file carries the pinned clock.
# The clock, pinned: the operation writes the time into the rows it changes (created_at, modified,
# a player's modification_date), and two clean runs a second apart differ there
# (transcripts/entry-s4.txt). Monotonic time is left real so timeouts and polls still advance.
printf '/usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1\n' > /etc/ld.so.preload
export FAKETIME="2026-01-01 00:00:00" FAKETIME_DONT_FAKE_MONOTONIC=1
