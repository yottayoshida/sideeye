# run-r4d.sh line 40: the cache directory is the state directory.
CCACHE_DIR=/s/ccache/state; export CCACHE_DIR
# Statistics off: ccache writes its stats file into a randomly chosen subdirectory, which made the
# operations differ between runs (kill_did_not_land, 2026-10-09 follow-ups 2, lab 3).
export CCACHE_NOSTATS=1
