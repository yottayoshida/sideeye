# run-r4d.sh line 40: the cache directory is the state directory.
CCACHE_DIR=/s/ccache/state; export CCACHE_DIR
# kill_did_not_land's next step (v1.10.0) names what the restore does not rebuild: modes, owners,
# timestamps, and the clock. ccache reads the clock and the files' times; the clock is pinned the
# way docs/apparatus.md gives (libfaketime through /etc/ld.so.preload, the time frozen).
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'
