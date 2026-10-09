# The clock pin docs/apparatus.md gives: libfaketime through /etc/ld.so.preload (never LD_PRELOAD,
# which Sideeye replaces), the time frozen. Written when this file is sourced, so a pinned define
# runs in a box of its own — the preload is global and would ride on every later target.
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'

# libuv runs Node's asynchronous file calls on its thread pool, four threads by default; with one
# they share a thread, and the threads wall is not met (yarn and trash-cli, transcripts/lab-1.txt).
export UV_THREADPOOL_SIZE=1
# The @lingui dependencies npm resolves today use fs.globSync, which Node 20 lacks (transcripts/explore/lingui:
# the seed's extract fails), so this run puts the box's Node 22 first, as cspell's and capacitor's defines do.
export PATH=/opt/node22/bin:$PATH
