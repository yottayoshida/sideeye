# Node's file calls on one thread (docs/apparatus.md); nx's daemon and cloud off, and its workspace data
# and cache outside the state (Lerna 10 runs on nx, which otherwise writes node_modules/.cache from
# its own native threads: transcripts/entry-s1e.txt, first gate).
mkdir -p /s/aux/nx-data /s/aux/nx-cache
export UV_THREADPOOL_SIZE=1 NX_DAEMON=false NX_NO_CLOUD=true NX_WORKSPACE_DATA_DIRECTORY=/s/aux/nx-data NX_CACHE_DIRECTORY=/s/aux/nx-cache
