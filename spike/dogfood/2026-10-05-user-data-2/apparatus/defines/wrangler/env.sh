export WRANGLER_LOG_PATH=/s/wrangler-in/logs
# The clock pin docs/apparatus.md gives: libfaketime through /etc/ld.so.preload (never LD_PRELOAD,
# which Sideeye replaces), the time frozen. Written when this file is sourced, so a pinned define
# runs in a box of its own — the preload is global and would ride on every later target.
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'
